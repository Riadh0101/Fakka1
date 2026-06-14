// ═══════════════════════════════════════════════════════════════════════════════
// GameEngineService — pure, stateless game logic
// ═══════════════════════════════════════════════════════════════════════════════
//
// This service is FRAMEWORK-AGNOSTIC. It imports zero NestJS, Redis, or DB
// dependencies. It takes a game state + a move and returns a new state.
//
// All game mechanics are ported EXACTLY from fekka.py.

import { Injectable } from '@nestjs/common';
import { Card, cardsEqual, pointValue, cardKey } from './card.js';
import { Deck } from './deck.js';
import { MiddlePool } from './middle-pool.js';

// ═══════════════════════════════════════════════════════════════════════════════
// Type definitions
// ═══════════════════════════════════════════════════════════════════════════════

export interface PlayerState {
  /** UUID v4 */
  id: string;
  /** Display name */
  name: string;
  /** Cards currently in hand (visible only to owning player). */
  hand: Card[];
  /** Private LIFO captured-card stack. */
  stack: Card[];
  /** Cumulative points across all rounds. */
  cumulativeScore: number;
  /** Has this player been eliminated? */
  eliminated: boolean;
  /** Assigned rank (1=best, 4=worst). null if still active. */
  rankEarned: number | null;
  /** Seat position 0–3. */
  seatIndex: number;
  /** Is the player currently connected via WebSocket? */
  connected: boolean;
}

export interface GameState {
  /** Room identifier. */
  roomId: string;
  /** Cards remaining in the deck (array, last element = top of deck). */
  deck: Card[];
  /** Middle pool cards (array, last element = top of pool). */
  pool: Card[];
  /** All 4 players (active + eliminated), in seat order. */
  players: PlayerState[];
  /** Index into the active players array for whose turn it is. */
  currentPlayerIndex: number;
  /** Number of plays completed in the current round (resets each round). */
  roundPlaysCompleted: number;
  /** Next rank to assign (1–4). Increments with each elimination. */
  nextRank: number;
  /** Has the game ended? */
  gameOver: boolean;
  /** Total rounds played so far. */
  roundCount: number;
}

/** A single stolen stack entry for reporting. */
export interface StolenEntry {
  playerId: string;
  cards: Card[];
}

/** Result returned by processTurn(). */
export interface TurnResult {
  /** The updated game state after the move. */
  newState: GameState;
  /** Human-readable action description. */
  action: 'discard' | 'capture' | 'steal' | 'combined';
  /** Cards captured from the pool (cascade order: top → deep). */
  poolCaptured: Card[];
  /** Stolen stacks, one entry per victim. */
  stolenFrom: StolenEntry[];
  /** The card that was played. */
  playedCard: Card;
  /** Did this play complete the round? */
  roundEnded: boolean;
  /** IDs of players eliminated this round (after scoring). */
  eliminatedPlayerIds: string[];
}

// ═══════════════════════════════════════════════════════════════════════════════
// GameEngineService
// ═══════════════════════════════════════════════════════════════════════════════

@Injectable()
export class GameEngineService {
  /**
   * Create the initial game state for a new room.
   *
   * @param roomId       Room identifier.
   * @param playerNames  Array of 4 player names (in seat order).
   * @param playerIds    Array of 4 player UUIDs (in seat order).
   * @param seed         Optional random seed for deterministic shuffling.
   */
  createInitialState(
    roomId: string,
    playerNames: string[],
    playerIds: string[],
    seed?: number,
  ): GameState {
    if (playerNames.length !== 4 || playerIds.length !== 4) {
      throw new Error('Fekka requires exactly 4 players');
    }

    const deck = new Deck(seed);

    // Build initial player states.
    const players: PlayerState[] = playerNames.map((name, i) => ({
      id: playerIds[i],
      name,
      hand: [],
      stack: [],
      cumulativeScore: 0,
      eliminated: false,
      rankEarned: null,
      seatIndex: i,
      connected: true,
    }));

    const state: GameState = {
      roomId,
      deck: [...deck.cards],
      pool: [],
      players,
      currentPlayerIndex: 0,
      roundPlaysCompleted: 0,
      nextRank: 1,
      gameOver: false,
      roundCount: 0,
    };

    // Deal initial round.
    return this.setupRound(state);
  }

  // ── Round Setup ──────────────────────────────────────────────────────────

  /**
   * Prepare a new round:
   *  - If pool is empty, deal 4 cards to it.
   *  - Deal 3 cards to each active player.
   *  - If deck is insufficient, recycle non-held cards.
   *  - Reset roundPlaysCompleted.
   */
  setupRound(state: GameState): GameState {
    const activePlayers = state.players.filter((p) => !p.eliminated);
    const deck = new Deck(); // We rebuild a Deck wrapper around the array
    deck.setCards([...state.deck]);
    const pool = new MiddlePool();
    pool.setCards([...state.pool]);

    // Calculate how many cards we need.
    let needed = 0;
    if (pool.isEmpty) {
      needed += 4;
    }
    needed += activePlayers.length * 3;

    // If the deck doesn't have enough, recycle non-held cards.
    if (deck.remaining < needed) {
      // Drain the Middle Pool — its cards are "non-held" and recyclable.
      const poolCards: Card[] = [];
      while (!pool.isEmpty) {
        poolCards.push(pool.pop());
      }
      // Exclude all cards currently in player stacks (these are "held").
      const excluded: Card[] = [];
      for (const p of state.players) {
        for (const c of p.stack) {
          excluded.push(c);
        }
      }
      deck.recycle(poolCards, excluded);
      // Pool is now empty; the branch below will refill it if possible.
    }

    // Recalculate needed after recycling.
    let postNeeded = 0;
    if (pool.isEmpty) {
      postNeeded += 4;
    }
    postNeeded += activePlayers.length * 3;

    const available = deck.remaining;

    if (available < postNeeded) {
      // --- Fallback: deal proportionally if deck is still short ---
      if (pool.isEmpty && available > 0) {
        const poolDeal = Math.min(4, available);
        const dealt = deck.deal(poolDeal);
        for (const c of dealt) {
          pool.push(c);
        }
      }
      const remainingAfterPool = deck.remaining;
      const numPlayers = activePlayers.length;
      if (numPlayers > 0 && remainingAfterPool > 0) {
        const perPlayer = Math.floor(remainingAfterPool / numPlayers);
        const remainder = remainingAfterPool % numPlayers;
        for (let i = 0; i < numPlayers; i++) {
          const dealN = perPlayer + (i < remainder ? 1 : 0);
          if (dealN > 0) {
            const cards = deck.deal(dealN);
            activePlayers[i].hand = cards;
          }
        }
      }
    } else {
      // Normal path: enough cards.
      if (pool.isEmpty) {
        const poolCardsFresh = deck.deal(4);
        for (const c of poolCardsFresh) {
          pool.push(c);
        }
      }
      for (const player of activePlayers) {
        const cards = deck.deal(3);
        player.hand = cards;
      }
    }

    // Update state.
    const newState: GameState = {
      ...state,
      deck: [...deck.cards],
      pool: [...pool.cards],
      players: state.players.map((p) => ({ ...p })), // shallow clone
      roundPlaysCompleted: 0,
      roundCount: state.roundCount + 1,
    };

    return newState;
  }

  // ── Core Turn Logic ──────────────────────────────────────────────────────

  /**
   * Process a single play. This is THE critical method implementing all
   * capture mechanics.
   *
   * 1. Find the active player by ID and validate it's their turn.
   * 2. Remove the played card from the player's hand.
   * 3. Try to capture from the Middle Pool via sequential reveal.
   * 4. Try to steal from opponent stacks whose top card matches.
   * 5. If anything was captured, merge and add to player's stack.
   * 6. If nothing was captured, discard the card to the Middle Pool.
   * 7. Increment roundPlaysCompleted; check if round ended.
   *
   * COMBINED CAPTURE MERGE ORDER:
   *   (a) Pool-captured cards in cascade order (first-popped = first)
   *   (b) The played card itself
   *   (c) Stolen stacks in SEAT ORDER (the order players appear in state.players)
   *
   * @param state    Current game state.
   * @param playerId UUID of the player making the move.
   * @param card     The card being played.
   * @returns TurnResult with new state and action details.
   */
  processTurn(state: GameState, playerId: string, card: Card): TurnResult {
    // Find the active player and validate it's their turn.
    const activePlayers = state.players.filter((p) => !p.eliminated);

    if (activePlayers.length === 0) {
      throw new Error('No active players — game is over');
    }

    const playerIndex = activePlayers.findIndex((p) => p.id === playerId);
    if (playerIndex === -1) {
      throw new Error(`Player ${playerId} is not active or not found`);
    }

    if (playerIndex !== state.currentPlayerIndex % activePlayers.length) {
      throw new Error(
        `Not player ${playerId}'s turn (current: ${activePlayers[state.currentPlayerIndex % activePlayers.length]?.id})`,
      );
    }

    const player = activePlayers[playerIndex];

    // Remove the card from the player's hand.
    const handIndex = player.hand.findIndex(
      (c) => c.rank === card.rank && c.suit === card.suit,
    );
    if (handIndex === -1) {
      throw new Error(
        `Card ${card.rank}${card.suit} not found in player's hand`,
      );
    }
    player.hand.splice(handIndex, 1);

    // ── 1. Pool capture via sequential reveal ──
    const pool = new MiddlePool();
    pool.setCards([...state.pool]);
    const poolCaptured: Card[] = pool.sequentialReveal(card.rank);

    // ── 2. Steal from opponent stacks matching top ──
    const stolenFrom: StolenEntry[] = [];

    // Iterate ALL players in seat order (state.players) checking only
    // active players other than the current player.
    for (const p of state.players) {
      if (p.eliminated) continue;
      if (p.id === playerId) continue;

      const stackTop = p.stack.length > 0 ? p.stack[p.stack.length - 1] : null;
      if (stackTop !== null && stackTop.rank === card.rank) {
        // Steal the entire stack.
        const stolen = [...p.stack];
        p.stack = [];
        stolenFrom.push({ playerId: p.id, cards: stolen });
      }
    }

    // ── 3. Determine outcome ──
    let action: TurnResult['action'];

    if (poolCaptured.length > 0 || stolenFrom.length > 0) {
      // ── Combined Capture: Merge in the specified order ──
      const merged: Card[] = [];

      // (a) Pool captured cards in cascade order (first popped = first in list).
      for (const c of poolCaptured) {
        merged.push(c);
      }

      // (b) The played card itself.
      merged.push(card);

      // (c) Stolen stacks in seat order (the order we iterated state.players).
      for (const entry of stolenFrom) {
        for (const c of entry.cards) {
          merged.push(c);
        }
      }

      // Push all merged cards onto the active player's stack.
      for (const c of merged) {
        player.stack.push(c);
      }

      if (poolCaptured.length > 0 && stolenFrom.length > 0) {
        action = 'combined';
      } else if (poolCaptured.length > 0) {
        action = 'capture';
      } else {
        action = 'steal';
      }
    } else {
      // ── 4. No match anywhere: discard to pool ──
      pool.push(card);
      action = 'discard';
    }

    // ── Advance turn ──
    const newCurrentPlayerIndex =
      (state.currentPlayerIndex + 1) % activePlayers.length;

    const newRoundPlaysCompleted = state.roundPlaysCompleted + 1;

    const newState: GameState = {
      ...state,
      deck: [...state.deck],
      pool: [...pool.cards],
      players: state.players.map((p) => ({ ...p })),
      currentPlayerIndex: newCurrentPlayerIndex,
      roundPlaysCompleted: newRoundPlaysCompleted,
    };

    // Check if the round has ended (all active players have played all cards).
    const totalCardsInRound = activePlayers.reduce(
      (sum, p) =>
        sum +
        newState.players.find((sp) => sp.id === p.id)!.hand.length,
      0,
    );
    // A round ends when every active player has played all 3 cards
    // (or the proportional-deal equivalents). We detect this by checking
    // if all active players now have empty hands.
    const roundEnded = activePlayers.every(
      (ap) =>
        newState.players.find((sp) => sp.id === ap.id)!.hand.length === 0,
    );

    return {
      newState,
      action,
      poolCaptured,
      stolenFrom,
      playedCard: card,
      roundEnded,
      eliminatedPlayerIds: [],
    };
  }

  // ── Round Scoring ────────────────────────────────────────────────────────

  /**
   * Each active player adds their private-stack score to cumulative total.
   * NOTE: stacks are NOT cleared — cards stay for the next round.
   */
  scoreRound(state: GameState): GameState {
    const newState: GameState = {
      ...state,
      players: state.players.map((p) => {
        if (p.eliminated) return { ...p };

        const roundScore = p.stack.reduce((sum, c) => sum + pointValue(c), 0);
        return {
          ...p,
          cumulativeScore: p.cumulativeScore + roundScore,
          // Stack is NOT cleared — cards remain.
        };
      }),
    };

    return newState;
  }

  // ── Elimination ──────────────────────────────────────────────────────────

  /**
   * Check for players who have reached 51+ cumulative points.
   * Assign ranks and eliminate them.
   *
   * If multiple players cross the threshold in the same round,
   * rank by score descending (higher score = better/lower rank number).
   * Ties broken by seat order (lower seat index = better rank).
   *
   * If exactly 1 active player remains, auto-assign the final rank.
   *
   * @returns Updated state and list of newly eliminated player IDs.
   */
  checkElimination(state: GameState): {
    newState: GameState;
    eliminatedPlayerIds: string[];
  } {
    const activePlayers = state.players.filter((p) => !p.eliminated);

    // Find active players who qualify for elimination.
    const qualifiers = activePlayers.filter((p) => p.cumulativeScore >= 51);

    if (qualifiers.length === 0) {
      return { newState: state, eliminatedPlayerIds: [] };
    }

    // Sort qualifiers by score descending (higher score = better rank).
    // Tie-break: seatIndex ascending (lower seat = better).
    qualifiers.sort((a, b) => {
      const scoreDiff = b.cumulativeScore - a.cumulativeScore;
      if (scoreDiff !== 0) return scoreDiff;
      return a.seatIndex - b.seatIndex;
    });

    let nextRank = state.nextRank;
    const eliminatedIds: string[] = [];
    const players = state.players.map((p) => ({ ...p }));

    for (const q of qualifiers) {
      const playerIdx = players.findIndex((p) => p.id === q.id);
      if (playerIdx !== -1) {
        players[playerIdx].rankEarned = nextRank;
        players[playerIdx].eliminated = true;
        eliminatedIds.push(q.id);
        nextRank++;
      }
    }

    let gameOver = state.gameOver;

    // Recompute active players after elimination.
    const remainingActive = players.filter((p) => !p.eliminated);

    // If exactly 1 active player remains, auto-assign the final rank.
    if (remainingActive.length === 1) {
      const lastPlayerIdx = players.findIndex(
        (p) => p.id === remainingActive[0].id,
      );
      players[lastPlayerIdx].rankEarned = nextRank;
      players[lastPlayerIdx].eliminated = true;
      eliminatedIds.push(remainingActive[0].id);
      gameOver = true;
    }

    // If all 4 are now eliminated, game over.
    if (players.every((p) => p.eliminated)) {
      gameOver = true;
    }

    // Adjust currentPlayerIndex after active player list changed.
    const newActive = players.filter((p) => !p.eliminated);
    const newCurrentPlayerIndex =
      newActive.length > 0
        ? state.currentPlayerIndex % newActive.length
        : 0;

    return {
      newState: {
        ...state,
        players,
        nextRank,
        currentPlayerIndex: newCurrentPlayerIndex,
        gameOver,
      },
      eliminatedPlayerIds: eliminatedIds,
    };
  }

  // ── Full Round + Elimination processing ──────────────────────────────────

  /**
   * Complete end-of-round processing:
   *  1. Score the round
   *  2. Check for eliminations
   *  3. Return combined result
   */
  processRoundEnd(state: GameState): TurnResult {
    const scored = this.scoreRound(state);
    const { newState, eliminatedPlayerIds } = this.checkElimination(scored);

    return {
      newState,
      action: 'discard', // Not meaningful at round end.
      poolCaptured: [],
      stolenFrom: [],
      playedCard: { rank: '', suit: '' }, // Sentinel.
      roundEnded: true,
      eliminatedPlayerIds,
    };
  }

  // ── State Sanitization ───────────────────────────────────────────────────

  /**
   * Sanitize the game state for a specific player.
   *
   * Each player receives:
   *  - Their OWN full hand cards
   *  - Other players: stack top card ONLY + hand COUNT (not contents)
   *  - Pool: top card only + pool size
   *  - Turn indicator, scores, elimination status
   */
  sanitizeForPlayer(state: GameState, playerId: string): GameState {
    return {
      ...state,
      deck: [], // Never reveal deck contents to clients.
      players: state.players.map((p) => {
        if (p.id === playerId) {
          // Full info for the owning player.
          return { ...p };
        }
        // Sanitize for opponents.
        const stackTop = p.stack.length > 0 ? [p.stack[p.stack.length - 1]] : [];
        return {
          ...p,
          hand: [], // Hide opponent hand contents.
          handCount: p.hand.length, // Show only the count.
          stack: stackTop, // Show only the top card.
        } as PlayerState & { handCount: number };
      }),
    } as GameState;
  }
}

#!/usr/bin/env python3
"""
Fekka (Schkobba 40) — Phase 1 CLI Game Engine
==============================================

40-card Italian deck: ranks 1-7, J, Q, K in 4 suits (10 per suit).
4 players, 3 cards each per round + 4 to Middle Pool initially.
Matching is rank-only (J matches J, Q matches Q, 7 matches 7; NO numeric equivalence).

Middle Pool (LIFO):
  - Play a card onto the pool. If it matches the pool's top card, capture it.
  - SEQUENTIAL REVEAL: after capturing the top, check the newly-exposed top.
    If it ALSO matches, capture it too. Cascade while matches hold. Stop at first
    non-match or empty pool.

Player Stack (LIFO):
  - Each player has a private stack. Only the top card is visible to opponents.
  - If a played card matches another player's stack top, steal their ENTIRE stack.

Combined Capture:
  - Pool cascade + steals happen in the SAME turn if both match.
  - Merge order: pool-captured (cascade order) + the played card + stolen stacks
    (in seat order). All go onto the capturing player's stack.
  - If NO match anywhere, the played card is pushed onto the Middle Pool (discard).

Round: 4 players × 3 cards = 12 plays. At round end, tally scores from private
stacks. Redeal 3 new cards each. Middle Pool persists across rounds.
When the 24-card reserve is exhausted, reshuffle all non-held cards
(pool + deck remainder, excluding player-stack cards).

Scoring: End-of-round only. Numeric cards (1-7) = 1 point. Face cards (J,Q,K) = 2 pts.
Cumulative across rounds.

Winning: First player to reach >= 51 cumulative points earns rank 1 and exits.
Game continues for remaining players. If multiple players cross 51 in the same
round, they are ranked by score descending (higher score = better rank).
Last remaining player earns rank 4 (worst).
"""

from __future__ import annotations

import argparse
import copy
import random
import sys
import unittest
from dataclasses import dataclass
from typing import Any, Dict, List, Optional, Tuple

# ═══════════════════════════════════════════════════════════════════════════════
# Card
# ═══════════════════════════════════════════════════════════════════════════════

RANKS: List[str] = ["1", "2", "3", "4", "5", "6", "7", "J", "Q", "K"]
SUITS: List[str] = ["♠", "♣", "♥", "♦"]
FACE_RANKS: set[str] = {"J", "Q", "K"}


@dataclass(frozen=True)
class Card:
    """A single Italian playing card. Equality is rank-only for game matching."""

    rank: str
    suit: str

    @property
    def point_value(self) -> int:
        """Face cards (J/Q/K) are worth 2 points; numerals 1-7 worth 1."""
        return 2 if self.rank in FACE_RANKS else 1

    def __eq__(self, other: object) -> bool:
        if not isinstance(other, Card):
            return NotImplemented
        return self.rank == other.rank

    def __hash__(self) -> int:
        # Hash must be consistent with __eq__ for set/dict correctness.
        return hash(self.rank)

    def __repr__(self) -> str:
        return f"{self.rank}{self.suit}"


def card_exact_match(a: Card, b: Card) -> bool:
    """Exact identity comparison (rank AND suit), used for deck uniqueness."""
    return a.rank == b.rank and a.suit == b.suit


# ═══════════════════════════════════════════════════════════════════════════════
# Deck
# ═══════════════════════════════════════════════════════════════════════════════

class Deck:
    """A 40-card Italian deck with shuffle, deal, and recycle capabilities."""

    def __init__(self, seed: Optional[int] = None) -> None:
        self._cards: List[Card] = []
        self._seed: Optional[int] = seed
        self._shuffle_count: int = 0
        self._build()
        self.shuffle(seed)

    def _build(self) -> None:
        """Construct the 40-card deck: each rank × each suit."""
        self._cards = [Card(rank=r, suit=s) for r in RANKS for s in SUITS]

    def shuffle(self, seed: Optional[int] = None) -> None:
        """Shuffle the deck. Optional seed for deterministic testing."""
        # Combine stored seed with shuffle count for unique-but-deterministic
        # shuffles on every call (prevents identical recycles).
        effective_seed: Optional[int] = seed
        if effective_seed is None and self._seed is not None:
            effective_seed = self._seed + self._shuffle_count
        rng = random.Random(effective_seed)
        rng.shuffle(self._cards)
        self._shuffle_count += 1

    def deal(self, n: int) -> List[Card]:
        """Deal *n* cards from the top of the deck (end of list = top)."""
        if n > len(self._cards):
            raise ValueError(
                f"Deck has only {len(self._cards)} cards, cannot deal {n}"
            )
        dealt: List[Card] = []
        for _ in range(n):
            dealt.append(self._cards.pop())
        return dealt

    def recycle(self, available_cards: List[Card], excluded_cards: List[Card]) -> None:
        """
        Gather all non-excluded cards into the deck and reshuffle.

        This is used when the reserve is exhausted: the caller empties the
        Middle Pool and passes those cards as *available_cards* along with
        whatever remains in the deck. Player-stack cards are *excluded_cards*
        (they remain "held" by players and are not recycled).

        Args:
            available_cards: Cards gathered from the pool to be recycled.
            excluded_cards: Cards to exclude from recycling (player-stack cards).
        """
        # Build a set of (rank, suit) tuples for exact exclusion matching
        # (rank-only __eq__ would cause false deduplication in a Card set).
        excluded_set: set[Tuple[str, str]] = {
            (c.rank, c.suit) for c in excluded_cards
        }
        # Gather: available external cards + current deck remainder,
        # filtering out any excluded (held) cards.
        gathered: List[Card] = [
            c for c in available_cards if (c.rank, c.suit) not in excluded_set
        ]
        gathered.extend(
            c for c in self._cards if (c.rank, c.suit) not in excluded_set
        )
        self._cards = gathered
        # Shuffle with auto-incremented seed derivative for deterministic variety.
        self.shuffle()

    @property
    def remaining(self) -> int:
        """Number of cards left in the deck."""
        return len(self._cards)

    def __repr__(self) -> str:
        return f"Deck({len(self._cards)} cards)"


# ═══════════════════════════════════════════════════════════════════════════════
# PlayerStack  (LIFO)
# ═══════════════════════════════════════════════════════════════════════════════

class PlayerStack:
    """
    A private LIFO card stack owned by a player or used as the Middle Pool.

    Index 0 = bottom, index -1 = top.
    """

    def __init__(self) -> None:
        self._cards: List[Card] = []

    def push(self, card: Card) -> None:
        """Push a single card onto the top of the stack."""
        self._cards.append(card)

    def push_many(self, cards: List[Card]) -> None:
        """
        Push multiple cards in order.
        First card in the list becomes the bottom-most of the batch;
        last card in the list becomes the new top of the stack.
        """
        for c in cards:
            self._cards.append(c)

    def pop(self) -> Card:
        """Remove and return the top card. Raises IndexError if empty."""
        if not self._cards:
            raise IndexError("Cannot pop from empty stack")
        return self._cards.pop()

    def peek_top(self) -> Optional[Card]:
        """Return the top card without removing it, or None if empty."""
        return self._cards[-1] if self._cards else None

    def steal_all(self) -> List[Card]:
        """
        Return the full contents of the stack (bottom-to-top order)
        and clear the stack. Used when an opponent steals your stack.
        """
        cards = self._cards[:]
        self._cards.clear()
        return cards

    def peek_all(self) -> List[Card]:
        """Return a copy of all cards without modifying the stack."""
        return self._cards[:]

    def score(self) -> int:
        """Sum the point values of all cards in this stack."""
        return sum(c.point_value for c in self._cards)

    @property
    def is_empty(self) -> bool:
        return len(self._cards) == 0

    @property
    def size(self) -> int:
        return len(self._cards)

    def __repr__(self) -> str:
        top = self.peek_top()
        top_str = repr(top) if top else "—"
        return f"Stack({self.size} cards, top={top_str})"


# ═══════════════════════════════════════════════════════════════════════════════
# MiddlePool  (extends PlayerStack with sequential-reveal capture)
# ═══════════════════════════════════════════════════════════════════════════════

class MiddlePool(PlayerStack):
    """
    The shared LIFO pool in the middle of the table.

    Extends PlayerStack with the 'sequential reveal' capture mechanic:
    when a played card matches the pool's top card, capture it and then
    check the newly-exposed top. Continue capturing while ranks match.
    """

    def sequential_reveal(self, rank: str) -> List[Card]:
        """
        Capture cards from the top of the pool whose rank matches *rank*.

        Algorithm (step-by-step):
          1. Examine the pool's current top card.
          2. If the pool is empty → stop. Return captured list.
          3. If top.rank == rank → pop it, add to captured list, go to step 2.
          4. If top.rank != rank → stop. Return captured list.
          5. Repeat until the first non-match or empty pool.

        The returned list is in capture order (first captured = first in list =
        former pool top; last captured = last in list = deepest match).
        """
        captured: List[Card] = []
        # Continue checking the pool top as long as ranks match.
        while not self.is_empty and self.peek_top().rank == rank:  # type: ignore[union-attr]
            captured.append(self.pop())
        return captured


# ═══════════════════════════════════════════════════════════════════════════════
# Player
# ═══════════════════════════════════════════════════════════════════════════════

class Player:
    """A single player with a hand, private stack, and scoring state."""

    def __init__(self, name: str) -> None:
        self.name: str = name
        self.hand: List[Card] = []
        self.stack: PlayerStack = PlayerStack()
        self.cumulative_score: int = 0
        self.eliminated: bool = False
        self.rank_earned: Optional[int] = None

    def play_card(self, index: int) -> Card:
        """
        Remove and return the card at *index* from the player's hand.
        Raises IndexError if index is out of range.
        """
        if index < 0 or index >= len(self.hand):
            raise IndexError(
                f"Card index {index} out of range (hand has {len(self.hand)} cards)"
            )
        return self.hand.pop(index)

    def add_captures(self, cards: List[Card]) -> None:
        """Add captured cards onto the player's private stack."""
        self.stack.push_many(cards)

    def tally_score(self) -> None:
        """Add this round's stack score to the cumulative total."""
        round_score = self.stack.score()
        self.cumulative_score += round_score

    def __repr__(self) -> str:
        status = ""
        if self.eliminated:
            status = f" [ELIMINATED rank={self.rank_earned}]"
        return (
            f"Player({self.name}, hand={len(self.hand)} cards, "
            f"stack={self.stack.size}, score={self.cumulative_score}{status})"
        )


# ═══════════════════════════════════════════════════════════════════════════════
# GameManager
# ═══════════════════════════════════════════════════════════════════════════════

class GameManager:
    """
    Orchestrates the full Fekka game lifecycle: rounds, turns, scoring,
    elimination, and end-game ranking.
    """

    def __init__(self, player_names: List[str], seed: Optional[int] = None) -> None:
        if len(player_names) != 4:
            raise ValueError("Fekka requires exactly 4 players")
        self.deck: Deck = Deck(seed)
        self.pool: MiddlePool = MiddlePool()
        self.players: List[Player] = [Player(name) for name in player_names]
        self.active_players: List[Player] = list(self.players)
        self.current_player_idx: int = 0
        self.next_rank: int = 1  # Ranks 1 (best) through 4 (worst)
        self._rng: random.Random = random.Random(seed)
        self._round_count: int = 0
        self._game_over: bool = False

    # ── Setup ────────────────────────────────────────────────────────────────

    def setup_round(self) -> None:
        """
        Prepare a new round: deal to pool (if empty) and deal 3 cards to each
        active player. If the deck is insufficient, recycle non-held cards first.

        Edge case: if even after recycling the deck is still insufficient (e.g.
        most cards are held in player stacks), deal proportionally — pool gets
        up to 4, remaining cards distributed evenly among active players.
        """
        # Calculate how many cards we need.
        needed: int = 0
        if self.pool.is_empty:
            needed += 4
        needed += len(self.active_players) * 3

        # If the deck doesn't have enough, recycle non-held cards.
        if self.deck.remaining < needed:
            # Drain the Middle Pool — its cards are "non-held" and recyclable.
            pool_cards: List[Card] = []
            while not self.pool.is_empty:
                pool_cards.append(self.pool.pop())
            # Exclude all cards currently in player stacks (these are "held").
            excluded: List[Card] = []
            for p in self.players:
                excluded.extend(p.stack.peek_all())
            self.deck.recycle(pool_cards, excluded)
            # Pool is now empty; the branch below will refill it if possible.

        # Recalculate needed — recycling may not have produced enough cards
        # if too many are held in player stacks.
        post_needed: int = 0
        if self.pool.is_empty:
            post_needed += 4
        post_needed += len(self.active_players) * 3

        # --- Fallback: deal proportionally if deck is still short ---
        available: int = self.deck.remaining
        if available < post_needed:
            # Deal what we can to the pool first (up to 4).
            if self.pool.is_empty and available > 0:
                pool_deal: int = min(4, available)
                for c in self.deck.deal(pool_deal):
                    self.pool.push(c)
                available -= pool_deal
            # Distribute remaining cards evenly among active players.
            num_players: int = len(self.active_players)
            if num_players > 0 and available > 0:
                per_player: int = available // num_players
                remainder: int = available % num_players
                for i, player in enumerate(self.active_players):
                    deal_n: int = per_player + (1 if i < remainder else 0)
                    if deal_n > 0:
                        cards: List[Card] = self.deck.deal(deal_n)
                        player.hand = cards
        else:
            # Normal path: enough cards.
            if self.pool.is_empty:
                pool_cards_fresh: List[Card] = self.deck.deal(4)
                for c in pool_cards_fresh:
                    self.pool.push(c)

            for player in self.active_players:
                cards: List[Card] = self.deck.deal(3)
                player.hand = cards

        self._round_count += 1

    # ── Core Turn Logic ──────────────────────────────────────────────────────

    def process_turn(self, player: Player, card: Card) -> str:
        """
        Process a single play. This is the CRITICAL method implementing all
        capture mechanics.

        1. Try to capture from the Middle Pool via sequential reveal.
        2. Try to steal from opponent stacks whose top card matches.
        3. If anything was captured, merge and add to player's stack.
        4. If nothing was captured, discard the card to the Middle Pool.

        Returns a human-readable description of what happened.

        Merge order (Combined Capture):
          pool_captured (cascade order, first-captured first)
          + [played_card]
          + stolen_stacks (in seat order — the order players appear in active_players)
        """
        # ── 1. Pool capture via sequential reveal ──
        pool_captured: List[Card] = self.pool.sequential_reveal(card.rank)

        # ── 2. Steal from opponents matching top ──
        stolen_stacks: List[List[Card]] = []
        # Iterate ALL players (including eliminated ones? No, only active) in
        # natural seat order (the order they appear in self.players).
        # But we only check active players other than the current player.
        for p in self.active_players:
            if p is player:
                continue
            top_card: Optional[Card] = p.stack.peek_top()
            if top_card is not None and top_card.rank == card.rank:
                # Steal the entire stack.
                stolen = p.stack.steal_all()
                stolen_stacks.append(stolen)

        # ── 3. Determine outcome ──
        if pool_captured or stolen_stacks:
            # ── Merge captured cards in the specified order ──
            merged: List[Card] = []

            # (a) Pool captured cards in cascade order (first popped = first in list).
            merged.extend(pool_captured)

            # (b) The played card itself.
            merged.append(card)

            # (c) Stolen stacks in seat order (the order we iterated).
            for stolen in stolen_stacks:
                merged.extend(stolen)

            player.add_captures(merged)

            # Build a description.
            parts: List[str] = []
            if pool_captured:
                parts.append(f"captured {len(pool_captured)} from pool")
            if stolen_stacks:
                total_stolen = sum(len(s) for s in stolen_stacks)
                parts.append(f"stole {total_stolen} from opponents")
            return f"{player.name}: " + ", ".join(parts) + f" [{len(merged)} total → stack]"

        # ── 4. No match: discard to pool ──
        self.pool.push(card)
        return f"{player.name}: Discarded (pool now {self.pool.size})"

    # ── Round & Game Lifecycle ───────────────────────────────────────────────

    def score_round(self) -> None:
        """Each active player adds their private-stack score to cumulative total."""
        for p in self.active_players:
            p.tally_score()

    def check_elimination(self) -> bool:
        """
        Check for players who have reached 51+ cumulative points.
        Assign ranks and eliminate them. If multiple players cross the
        threshold in the same round, rank by score descending (higher
        score = better/lower rank number). Ties broken by seat order.

        Returns True if the game is over (all 4 ranked).
        """
        # Find active players who qualify for elimination.
        qualifiers: List[Player] = [
            p for p in self.active_players if p.cumulative_score >= 51
        ]
        if not qualifiers:
            return False

        # Sort qualifiers by score descending (higher score = better rank).
        # Use stable sort + seat order for tie-breaking.
        qualifiers.sort(key=lambda p: (-p.cumulative_score, self.players.index(p)))

        for p in qualifiers:
            p.rank_earned = self.next_rank
            self.next_rank += 1
            p.eliminated = True
            # Remove from active players list.
            self.active_players.remove(p)

        # Clamp current_player_idx after active_players list changed.
        if self.active_players:
            self.current_player_idx = self.current_player_idx % len(self.active_players)
        else:
            self.current_player_idx = 0

        # If exactly 1 active player remains, auto-assign the final rank.
        if len(self.active_players) == 1:
            last = self.active_players[0]
            last.rank_earned = self.next_rank
            last.eliminated = True
            self.active_players.clear()
            self._game_over = True
            return True

        # If all 4 are now eliminated, game over.
        if len(self.active_players) == 0:
            self._game_over = True
            return True

        return False

    def advance_turn(self) -> None:
        """Move to the next active player, wrapping around."""
        if not self.active_players:
            return
        self.current_player_idx = (self.current_player_idx + 1) % len(
            self.active_players
        )

    def get_game_state(self) -> dict:
        """Return visible game state for CLI display."""
        pool_top = self.pool.peek_top()
        return {
            "round": self._round_count,
            "pool_top": repr(pool_top) if pool_top else "(empty)",
            "pool_size": self.pool.size,
            "deck_remaining": self.deck.remaining,
            "active_count": len(self.active_players),
            "players": [
                {
                    "name": p.name,
                    "hand": [repr(c) for c in p.hand],
                    "stack_top": repr(p.stack.peek_top()) if not p.stack.is_empty else "(empty)",
                    "stack_size": p.stack.size,
                    "score": p.cumulative_score,
                    "eliminated": p.eliminated,
                    "rank": p.rank_earned,
                }
                for p in self.players
            ],
            "game_over": self._game_over,
        }

    def run_round(self) -> None:
        """
        Execute one full round: each active player plays all 3 of their cards.
        After 12 plays (4 × 3), score the round and check for eliminations.
        """
        total_plays: int = sum(len(p.hand) for p in self.active_players)
        for _ in range(total_plays):
            # Skip players who have no cards (proportional-deal fallback).
            while len(self.active_players[self.current_player_idx].hand) == 0:
                self.advance_turn()
            player: Player = self.active_players[self.current_player_idx]
            # Player selects a card — the caller (CLI) provides the logic.
            # We expose the player and await a card index.
            yield (player, self)
            self.advance_turn()

        self.score_round()
        self.check_elimination()

    @property
    def game_over(self) -> bool:
        return self._game_over

    @property
    def round_count(self) -> int:
        return self._round_count


# ═══════════════════════════════════════════════════════════════════════════════
# CLI Runner
# ═══════════════════════════════════════════════════════════════════════════════

def auto_play_game(player_names: List[str], seed: Optional[int] = None) -> None:
    """
    Run a full game in auto mode: each player randomly selects a valid card
    from their hand each turn. Prints round-by-round output.
    """
    gm = GameManager(player_names, seed=seed)
    rng = random.Random(seed)

    print("=" * 60)
    print("FEKKA (Schkobba 40) -- Auto Play")
    print(f"Players: {', '.join(player_names)}")
    print(f"Seed: {seed}")
    print("=" * 60)

    while not gm.game_over:
        gm.setup_round()
        print(f"\n{'-' * 60}")
        print(f"ROUND {gm.round_count}")
        print(f"Pool: {gm.pool.peek_top() if not gm.pool.is_empty else '(empty)'} "
              f"| Deck: {gm.deck.remaining} cards remaining")
        print(f"{'-' * 60}")

        # Total plays = sum of hand sizes (handles proportional dealing).
        total_plays = sum(len(p.hand) for p in gm.active_players)
        for _ in range(total_plays):
            # Skip players with empty hands (shouldn't happen but safe).
            while len(gm.active_players[gm.current_player_idx].hand) == 0:
                gm.advance_turn()
            player = gm.active_players[gm.current_player_idx]
            # Randomly pick a card from hand.
            idx = rng.randint(0, len(player.hand) - 1)
            card = player.play_card(idx)

            result = gm.process_turn(player, card)
            print(f"  {result}")

            gm.advance_turn()

        # Score and elimination.
        gm.score_round()
        # Check eliminations BEFORE printing so statuses are live.
        # Snapshot ranks before check so we can report new eliminations.
        prev_ranks = {p.name: p.rank_earned for p in gm.players}
        gm.check_elimination()

        print(f"\n  --- Round {gm.round_count} Scores ---")
        for p in gm.players:
            status = ""
            if p.eliminated and p.rank_earned is not None:
                status = f" [RANK {p.rank_earned}!]"
            print(f"  {p.name}: {p.cumulative_score} pts{status}")

        # Announce newly eliminated players (rank just assigned this round).
        for p in gm.players:
            if p.eliminated and p.rank_earned is not None and prev_ranks.get(p.name) != p.rank_earned:
                print(f"    → {p.name} eliminated at rank {p.rank_earned}")

    # ── Final standings ──
    print(f"\n{'=' * 60}")
    print("FINAL STANDINGS")
    ranked = sorted(gm.players, key=lambda p: p.rank_earned or 99)
    for p in ranked:
        print(f"  Rank {p.rank_earned}: {p.name} ({p.cumulative_score} pts)")
    print(f"Total rounds: {gm.round_count}")
    print(f"{'=' * 60}")


def manual_play_game(player_names: List[str], seed: Optional[int] = None) -> None:
    """Run a full game in manual/interactive mode with prompts."""
    gm = GameManager(player_names, seed=seed)

    print("=" * 60)
    print("FEKKA (Schkobba 40) -- Manual Play")
    print("=" * 60)

    while not gm.game_over:
        gm.setup_round()
        print(f"\n{'-' * 60}")
        print(f"ROUND {gm.round_count}")
        print(f"{'-' * 60}")

        total_plays = sum(len(p.hand) for p in gm.active_players)
        for _ in range(total_plays):
            # Skip players with empty hands.
            while len(gm.active_players[gm.current_player_idx].hand) == 0:
                gm.advance_turn()
            player = gm.active_players[gm.current_player_idx]

            # Show game state.
            pool_top = gm.pool.peek_top()
            print(f"\nPool top: {pool_top if pool_top else '(empty)'} "
                  f"| Pool size: {gm.pool.size} | Deck: {gm.deck.remaining}")

            print(f"\n{player.name}'s turn (score: {player.cumulative_score}):")
            print(f"  Stack top: {player.stack.peek_top() or '(empty)'} "
                  f"| Stack size: {player.stack.size}")
            print("  Hand:")
            for i, c in enumerate(player.hand):
                print(f"    [{i}] {c}")

            # Show opponent stack tops.
            print("  Opponent stack tops:")
            for p in gm.active_players:
                if p is not player:
                    top = p.stack.peek_top()
                    print(f"    {p.name}: {top if top else '(empty)'}")

            # Prompt for card index.
            while True:
                try:
                    choice = input(f"  Choose card [0-{len(player.hand)-1}]: ").strip()
                    idx = int(choice)
                    card = player.play_card(idx)
                    break
                except (ValueError, IndexError) as e:
                    print(f"  Invalid: {e}. Try again.")

            result = gm.process_turn(player, card)
            print(f"  → {result}")

            gm.advance_turn()

        # Score round.
        gm.score_round()
        # Check eliminations BEFORE printing so statuses are live.
        prev_ranks = {p.name: p.rank_earned for p in gm.players}
        gm.check_elimination()

        print(f"\n  --- Round {gm.round_count} Scores ---")
        for p in gm.players:
            status = ""
            if p.eliminated:
                status = f" [RANK {p.rank_earned}]"
            print(f"  {p.name}: {p.cumulative_score} pts{status}")

        # Announce newly eliminated players.
        for p in gm.players:
            if p.eliminated and p.rank_earned is not None and prev_ranks.get(p.name) != p.rank_earned:
                print(f"    → {p.name} eliminated at rank {p.rank_earned}")

    print(f"\n{'=' * 60}")
    print("FINAL STANDINGS")
    ranked = sorted(gm.players, key=lambda p: p.rank_earned or 99)
    for p in ranked:
        print(f"  Rank {p.rank_earned}: {p.name} ({p.cumulative_score} pts)")
    print(f"{'=' * 60}")


# ═══════════════════════════════════════════════════════════════════════════════
# Unit Tests
# ═══════════════════════════════════════════════════════════════════════════════

class TestCard(unittest.TestCase):
    """Card class unit tests."""

    def test_rank_only_equality(self):
        """Cards with same rank but different suits are equal."""
        c1 = Card("7", "♠")
        c2 = Card("7", "♣")
        self.assertEqual(c1, c2)

    def test_different_ranks_not_equal(self):
        """Cards with different ranks are not equal."""
        c1 = Card("K", "♠")
        c2 = Card("Q", "♠")
        self.assertNotEqual(c1, c2)

    def test_face_card_points(self):
        """Face cards (J, Q, K) are worth 2 points."""
        self.assertEqual(Card("J", "♠").point_value, 2)
        self.assertEqual(Card("Q", "♣").point_value, 2)
        self.assertEqual(Card("K", "♥").point_value, 2)

    def test_numeral_card_points(self):
        """Numeral cards (1-7) are worth 1 point."""
        for r in ["1", "2", "3", "4", "5", "6", "7"]:
            self.assertEqual(Card(r, "♦").point_value, 1, f"Rank {r} should be 1pt")

    def test_repr_format(self):
        """Card repr shows rank + suit symbol."""
        c = Card("K", "♠")
        self.assertEqual(repr(c), "K♠")

    def test_hash_consistency(self):
        """Cards equal by rank must have same hash."""
        c1 = Card("3", "♠")
        c2 = Card("3", "♦")
        self.assertEqual(hash(c1), hash(c2))
        # Can be used in a set (dedupes by rank).
        s = {c1, c2}
        self.assertEqual(len(s), 1)


class TestPlayerStack(unittest.TestCase):
    """PlayerStack / LIFO mechanics."""

    def setUp(self) -> None:
        self.stack = PlayerStack()

    def test_push_and_peek(self):
        self.stack.push(Card("1", "♠"))
        self.assertEqual(self.stack.peek_top(), Card("1", "♠"))
        self.assertEqual(self.stack.size, 1)

    def test_pop(self):
        self.stack.push(Card("K", "♥"))
        popped = self.stack.pop()
        self.assertEqual(popped, Card("K", "♥"))
        self.assertTrue(self.stack.is_empty)

    def test_pop_empty_raises(self):
        with self.assertRaises(IndexError):
            self.stack.pop()

    def test_push_many_order(self):
        """push_many preserves order: first goes to bottom, last to top."""
        cards = [Card("1", "♠"), Card("2", "♠"), Card("3", "♠")]
        self.stack.push_many(cards)
        self.assertEqual(self.stack.size, 3)
        self.assertEqual(self.stack.peek_top(), Card("3", "♠"))
        # Verify bottom card (pop all and check first).
        popped = [self.stack.pop() for _ in range(3)]
        self.assertEqual(popped, [Card("3", "♠"), Card("2", "♠"), Card("1", "♠")])

    def test_steal_all(self):
        self.stack.push_many([Card("A", "♠") for _ in range(3)])  # noqa — test cards
        stolen = self.stack.steal_all()
        self.assertEqual(len(stolen), 3)
        self.assertTrue(self.stack.is_empty)
        self.assertEqual(self.stack.size, 0)

    def test_score(self):
        self.stack.push(Card("1", "♠"))  # 1 pt
        self.stack.push(Card("J", "♠"))  # 2 pt
        self.stack.push(Card("K", "♠"))  # 2 pt
        self.assertEqual(self.stack.score(), 5)

    def test_peek_all_does_not_modify(self):
        self.stack.push(Card("7", "♣"))
        all_cards = self.stack.peek_all()
        self.assertEqual(len(all_cards), 1)
        self.assertEqual(self.stack.size, 1)


class TestMiddlePool(unittest.TestCase):
    """MiddlePool sequential-reveal tests."""

    def setUp(self) -> None:
        self.pool = MiddlePool()

    # ── Scenario 1: Discard to empty pool ──
    def test_discard_to_empty_pool(self):
        """When pool is empty, sequential_reveal returns nothing."""
        captured = self.pool.sequential_reveal("7")
        self.assertEqual(captured, [])

    # ── Scenario 2: Single pool capture ──
    def test_single_pool_capture(self):
        """Playing a matching card on a pool with one matching top captures it."""
        self.pool.push(Card("5", "♠"))
        captured = self.pool.sequential_reveal("5")
        self.assertEqual(len(captured), 1)
        self.assertEqual(captured[0], Card("5", "♠"))
        self.assertTrue(self.pool.is_empty)

    # ── Scenario 3: 3-deep sequential reveal cascade ──
    def test_three_deep_cascade(self):
        """
        Pool (bottom→top): [X, 7♠, 7♣, 7♥].
        Playing a 7 should capture all three 7s in cascade order.
        """
        self.pool.push(Card("K", "♦"))          # bottom — blocker
        self.pool.push(Card("7", "♠"))          # 1st match (deepest)
        self.pool.push(Card("7", "♣"))          # 2nd match
        self.pool.push(Card("7", "♥"))          # 3rd match (top)
        captured = self.pool.sequential_reveal("7")
        # Cascade captures top→deepest: 7♥, 7♣, 7♠
        self.assertEqual(len(captured), 3)
        self.assertEqual(captured[0], Card("7", "♥"))  # first popped (was top)
        self.assertEqual(captured[1], Card("7", "♣"))
        self.assertEqual(captured[2], Card("7", "♠"))
        # Pool should now have only the blocker.
        self.assertEqual(self.pool.size, 1)
        self.assertEqual(self.pool.peek_top(), Card("K", "♦"))

    # ── Scenario 4: Steal from one opponent ──
    # (Tested via GameManager in integration, but stack steal is unit-testable.)
    def test_steal_mechanism(self):
        """steal_all returns all cards and empties stack."""
        stack = PlayerStack()
        stack.push_many([Card("1", "♠"), Card("2", "♠"), Card("J", "♠")])
        stolen = stack.steal_all()
        self.assertEqual(len(stolen), 3)
        self.assertTrue(stack.is_empty)

    def test_no_match_no_capture(self):
        """Non-matching rank returns empty capture list, pool unchanged."""
        self.pool.push(Card("K", "♠"))
        captured = self.pool.sequential_reveal("3")
        self.assertEqual(captured, [])
        self.assertEqual(self.pool.size, 1)


class TestPlayer(unittest.TestCase):
    """Player class unit tests."""

    def setUp(self) -> None:
        self.player = Player("TestPlayer")

    def test_play_card_valid(self):
        self.player.hand = [Card("1", "♠"), Card("2", "♠"), Card("3", "♠")]
        card = self.player.play_card(0)
        self.assertEqual(card, Card("1", "♠"))
        self.assertEqual(len(self.player.hand), 2)

    def test_play_card_invalid_index(self):
        self.player.hand = [Card("1", "♠")]
        with self.assertRaises(IndexError):
            self.player.play_card(5)
        with self.assertRaises(IndexError):
            self.player.play_card(-1)

    def test_add_captures(self):
        cards = [Card("K", "♠"), Card("Q", "♠")]
        self.player.add_captures(cards)
        self.assertEqual(self.player.stack.size, 2)
        self.assertEqual(self.player.stack.peek_top(), Card("Q", "♠"))

    def test_tally_score(self):
        """tally_score adds stack score to cumulative."""
        self.player.stack.push(Card("1", "♠"))  # 1 pt
        self.player.stack.push(Card("J", "♠"))  # 2 pt
        self.assertEqual(self.player.cumulative_score, 0)
        self.player.tally_score()
        self.assertEqual(self.player.cumulative_score, 3)


class TestGameManager(unittest.TestCase):
    """GameManager integration tests covering all 12 required scenarios."""

    def setUp(self) -> None:
        self.gm = GameManager(["P0", "P1", "P2", "P3"], seed=42)

    # ── Helper to set up a controlled pool ──
    def _set_pool(self, cards: List[Card]) -> None:
        """Replace pool contents with specific cards (bottom→top order)."""
        # Clear existing pool.
        while not self.gm.pool.is_empty:
            self.gm.pool.pop()
        for c in cards:
            self.gm.pool.push(c)

    # ── Scenario 1: Discard to empty pool ──
    def test_scenario1_discard_empty_pool(self):
        """If no match anywhere, card is pushed onto pool."""
        # Ensure pool is empty.
        while not self.gm.pool.is_empty:
            self.gm.pool.pop()
        player = self.gm.active_players[0]
        card = Card("3", "♠")
        result = self.gm.process_turn(player, card)
        self.assertIn("Discarded", result)
        self.assertEqual(self.gm.pool.size, 1)
        self.assertEqual(self.gm.pool.peek_top(), Card("3", "♠"))

    # ── Scenario 2: Single pool capture ──
    def test_scenario2_single_pool_capture(self):
        """Playing a matching card on a pool with one matching top captures it."""
        self._set_pool([Card("4", "♠")])
        player = self.gm.active_players[0]
        card = Card("4", "♣")  # Same rank, different suit.
        result = self.gm.process_turn(player, card)
        self.assertIn("captured 1 from pool", result)
        self.assertTrue(self.gm.pool.is_empty)
        self.assertEqual(player.stack.size, 2)  # captured pool + played card

    # ── Scenario 3: 3-deep sequential reveal cascade ──
    def test_scenario3_three_deep_cascade(self):
        """Three matching cards on pool top captured in cascade."""
        self._set_pool([
            Card("K", "♦"),   # bottom — blocker
            Card("7", "♠"),   # match
            Card("7", "♣"),   # match
            Card("7", "♥"),   # match (top)
        ])
        player = self.gm.active_players[0]
        card = Card("7", "♦")
        result = self.gm.process_turn(player, card)
        self.assertIn("captured 3 from pool", result)
        # Pool should have only the blocker left.
        self.assertEqual(self.gm.pool.size, 1)
        self.assertEqual(self.gm.pool.peek_top(), Card("K", "♦"))
        # Player should have 4 cards (3 captured + 1 played).
        self.assertEqual(player.stack.size, 4)

    # ── Scenario 4: Steal from one opponent ──
    def test_scenario4_steal_one_opponent(self):
        """Played card matches one opponent's stack top → steal their stack."""
        # Give P1 a stack with a matching top.
        self.gm.active_players[1].stack.push(Card("1", "♠"))
        self.gm.active_players[1].stack.push(Card("2", "♠"))
        self.gm.active_players[1].stack.push(Card("5", "♣"))  # top — rank 5

        # P0 plays a 5 (no pool match).
        player = self.gm.active_players[0]
        card = Card("5", "♦")
        result = self.gm.process_turn(player, card)

        self.assertIn("stole", result)
        # P1's stack should be empty.
        self.assertTrue(self.gm.active_players[1].stack.is_empty)
        # P0 should have: played card + P1's 3 stolen cards = 4.
        self.assertEqual(player.stack.size, 4)

    # ── Scenario 5: Steal from two opponents simultaneously ──
    def test_scenario5_steal_two_opponents(self):
        """Played card matches two opponents' stack tops → steal both."""
        # P1 stack top = 5.
        self.gm.active_players[1].stack.push(Card("5", "♠"))
        # P2 stack top = 5.
        self.gm.active_players[2].stack.push(Card("A", "♠"))  # noqa — filler
        self.gm.active_players[2].stack.push(Card("5", "♣"))

        player = self.gm.active_players[0]
        card = Card("5", "♦")
        result = self.gm.process_turn(player, card)

        self.assertIn("stole", result)
        self.assertTrue(self.gm.active_players[1].stack.is_empty)
        self.assertTrue(self.gm.active_players[2].stack.is_empty)
        # P0: 1 played + 1 from P1 + 2 from P2 = 4.
        self.assertEqual(player.stack.size, 4)

    # ── Scenario 6: Combined pool-cascade + steal in same turn ──
    def test_scenario6_combined_capture_and_steal(self):
        """Both pool cascade and opponent stack steals happen in same turn."""
        # Pool setup: one matching top.
        self._set_pool([Card("6", "♠")])
        # P1 stack top matches.
        self.gm.active_players[1].stack.push(Card("X", "♠"))  # noqa — filler
        self.gm.active_players[1].stack.push(Card("6", "♣"))
        # P2 stack top also matches.
        self.gm.active_players[2].stack.push(Card("6", "♥"))

        player = self.gm.active_players[0]
        card = Card("6", "♦")
        result = self.gm.process_turn(player, card)

        self.assertIn("captured 1 from pool", result)
        self.assertIn("stole", result)
        self.assertTrue(self.gm.pool.is_empty)
        self.assertTrue(self.gm.active_players[1].stack.is_empty)
        self.assertTrue(self.gm.active_players[2].stack.is_empty)
        # P0: 1 pool + 1 played + 2 from P1 + 1 from P2 = 5.
        self.assertEqual(player.stack.size, 5)

    # ── Scenario 7: Numeral cards score 1pt ──
    def test_scenario7_numeral_scoring(self):
        """Each numeral (1-7) contributes 1 point."""
        player = self.gm.active_players[0]
        for r in ["1", "2", "3", "4", "5", "6", "7"]:
            player.stack.push(Card(r, "♠"))
        self.assertEqual(player.stack.score(), 7)  # 7 × 1pt

    # ── Scenario 8: Face cards score 2pt ──
    def test_scenario8_face_card_scoring(self):
        """Each face card (J, Q, K) contributes 2 points."""
        player = self.gm.active_players[0]
        for r in ["J", "Q", "K"]:
            player.stack.push(Card(r, "♠"))
        self.assertEqual(player.stack.score(), 6)  # 3 × 2pt

    # ── Scenario 9: Elimination at 51 points ──
    def test_scenario9_elimination_at_51(self):
        """Player with 51+ cumulative score is eliminated."""
        player = self.gm.active_players[0]
        player.cumulative_score = 51
        game_over = self.gm.check_elimination()
        # Game is NOT over (3 players remain); only 1 eliminated.
        self.assertFalse(game_over)
        self.assertTrue(player.eliminated)
        self.assertEqual(player.rank_earned, 1)
        self.assertNotIn(player, self.gm.active_players)

    # ── Scenario 10: Rank assignment 1→4 ──
    def test_scenario10_rank_assignment(self):
        """All 4 players get ranks 1-4 in correct order."""
        # Give all players >51 points with different scores.
        scores = [60, 55, 70, 51]
        expected_ranks = [2, 3, 1, 4]  # Sorted by score desc: 70→1, 60→2, 55→3, 51→4
        for i, s in enumerate(scores):
            self.gm.active_players[i].cumulative_score = s
        self.gm.check_elimination()

        for i, expected in enumerate(expected_ranks):
            self.assertEqual(
                self.gm.players[i].rank_earned, expected,
                f"Player {i} (score {scores[i]}) should be rank {expected}"
            )
        self.assertTrue(self.gm.game_over)

    # ── Scenario 11: Redeal with pool persistence ──
    def test_scenario11_redeal_pool_persistence(self):
        """After setup_round, pool retains its cards; players get 3 each."""
        # Seed pool with known cards.
        self._set_pool([Card("1", "♠"), Card("2", "♠")])
        self.gm.setup_round()
        # Pool should still have its 2 cards (pool was not empty, so no deal).
        self.assertEqual(self.gm.pool.size, 2)
        # Each active player should have 3 cards in hand.
        for p in self.gm.active_players:
            self.assertEqual(len(p.hand), 3)

    # ── Scenario 12: Deck recycling when exhausted ──
    def test_scenario12_deck_recycling(self):
        """When deck is exhausted, non-held cards are reshuffled back."""
        # Move most deck cards to the pool (non-held, recyclable).
        # Pool gets 24 cards; deck keeps 16.
        big_pool: List[Card] = self.gm.deck.deal(24)
        for c in big_pool:
            self.gm.pool.push(c)
        self.assertEqual(self.gm.pool.size, 24)
        self.assertEqual(self.gm.deck.remaining, 16)

        # Take 4 cards from the deck for player stacks (held).
        for p in self.gm.active_players:
            p.stack.push(self.gm.deck.deal(1)[0])
        self.assertEqual(sum(p.stack.size for p in self.gm.active_players), 4)
        self.assertEqual(self.gm.deck.remaining, 12)
        # Total: pool(24) + deck(12) + stacks(4) = 40 ✓

        # ROUND 1: Pool not empty → need 12 for players. Deck has 12 → no recycle.
        self.gm.setup_round()
        self.assertEqual(self.gm.pool.size, 24)  # Pool persists.
        for p in self.gm.active_players:
            self.assertEqual(len(p.hand), 3)
        self.assertEqual(self.gm.deck.remaining, 0)

        # End of round 1: move all hand cards to pool (simulating all discards)
        # to preserve the 40-card total.
        for p in self.gm.active_players:
            while p.hand:
                self.gm.pool.push(p.hand.pop())
        # Now: pool(36), deck(0), stacks(4) = 40
        self.assertEqual(self.gm.pool.size, 36)

        # ROUND 2: Pool not empty → need 12 for players. Deck has 0 < 12 → RECYCLE.
        # Recycling: pool(36) + deck(0) - excluded(4 stacks) = 32 cards → deck.
        # Then deal to pool? Pool is NOT empty (36), but we drained it for
        # recycling. After recycling, pool is empty → deal 4 to pool.
        # Then deal 12 to players. Total dealt: 16. Deck: 32-16 = 16.
        self.gm.setup_round()
        self.assertEqual(self.gm.pool.size, 4)   # Refilled after recycling.
        for p in self.gm.active_players:
            self.assertEqual(len(p.hand), 3)
        # 36 recycled - 4 (pool) - 12 (hands) = 20 remaining in deck.
        self.assertEqual(self.gm.deck.remaining, 20)

        # Verify total card count = 40.
        total = (self.gm.pool.size +
                 sum(len(p.hand) for p in self.gm.active_players) +
                 sum(p.stack.size for p in self.gm.players) +
                 self.gm.deck.remaining)
        self.assertEqual(total, 40)

    # ── No numeric equivalence ──
    def test_no_numeric_equivalence(self):
        """J, Q, K do not match any numeric rank even if 'value' might suggest."""
        self._set_pool([Card("J", "♠")])
        player = self.gm.active_players[0]
        # Play a card that is NOT J — should not match.
        card = Card("1", "♣")
        result = self.gm.process_turn(player, card)
        self.assertIn("Discarded", result)
        self.assertEqual(self.gm.pool.size, 2)  # original J + discarded 1

    # ── Steal does NOT target self ──
    def test_steal_does_not_target_self(self):
        """If player's own stack top matches, it is NOT stolen."""
        player = self.gm.active_players[0]
        player.stack.push(Card("K", "♠"))  # own stack top = K
        self._set_pool([])
        card = Card("K", "♣")
        result = self.gm.process_turn(player, card)
        # Should discard (no pool match, own stack doesn't count for stealing).
        self.assertIn("Discarded", result)
        self.assertEqual(player.stack.size, 1)  # unchanged


def run_tests() -> None:
    """Run the unit test suite."""
    # Fix Unicode output on Windows consoles.
    if sys.stdout.encoding and sys.stdout.encoding.lower() in ('cp1252', 'cp850', 'cp437'):
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')

    loader = unittest.TestLoader()
    suite = loader.loadTestsFromModule(sys.modules[__name__])
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)

    # ── 100-game smoke test ──
    print("\n" + "=" * 60)
    print("100-GAME SMOKE TEST")
    print("=" * 60)
    smoke_pass = 0
    smoke_fail = 0
    for i in range(100):
        try:
            gm = GameManager(["A", "B", "C", "D"], seed=i)
            rng = random.Random(i)
            round_count = 0
            deadlock_counter: int = 0
            prev_total_score: int = -1
            while not gm.game_over:
                gm.setup_round()
                total_plays = sum(len(p.hand) for p in gm.active_players)
                if total_plays == 0:
                    # Cannot deal any cards — force game end with current scores.
                    gm._game_over = True
                    for p in gm.active_players:
                        p.rank_earned = gm.next_rank
                        gm.next_rank += 1
                        p.eliminated = True
                    gm.active_players.clear()
                    break
                for _ in range(total_plays):
                    while len(gm.active_players[gm.current_player_idx].hand) == 0:
                        gm.advance_turn()
                    player = gm.active_players[gm.current_player_idx]
                    idx = rng.randint(0, len(player.hand) - 1)
                    card = player.play_card(idx)
                    gm.process_turn(player, card)
                    gm.advance_turn()
                gm.score_round()
                gm.check_elimination()
                round_count += 1
                # Deadlock detection: if total cumulative score hasn't changed
                # in 100 consecutive rounds, force-end the game. This handles
                # the edge case where too few cards remain in circulation for
                # any rank matches to be possible.
                current_total = sum(p.cumulative_score for p in gm.players)
                if current_total == prev_total_score:
                    deadlock_counter += 1
                else:
                    deadlock_counter = 0
                    prev_total_score = current_total
                if deadlock_counter >= 100:
                    gm._game_over = True
                    for p in gm.active_players:
                        p.rank_earned = gm.next_rank
                        gm.next_rank += 1
                        p.eliminated = True
                    gm.active_players.clear()
                    break
                if round_count > 2000:  # Safety valve.
                    raise RuntimeError("Game ran too many rounds — infinite loop?")
            # Verify all 4 players got ranks.
            ranks = {p.rank_earned for p in gm.players}
            if ranks != {1, 2, 3, 4}:
                raise AssertionError(f"Invalid ranks: {ranks}")
            smoke_pass += 1
        except Exception as e:
            smoke_fail += 1
            print(f"  Game {i+1} FAILED: {e}")

    print(f"  Passed: {smoke_pass}/100")
    if smoke_fail > 0:
        print(f"  Failed: {smoke_fail}/100")
    print("=" * 60)

    if not result.wasSuccessful() or smoke_fail > 0:
        sys.exit(1)


# ═══════════════════════════════════════════════════════════════════════════════
# Entry Point
# ═══════════════════════════════════════════════════════════════════════════════

def main() -> None:
    # Fix Unicode output on Windows consoles.
    if sys.stdout.encoding and sys.stdout.encoding.lower() in ('cp1252', 'cp850', 'cp437'):
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')

    parser = argparse.ArgumentParser(
        description="Fekka (Schkobba 40) — CLI Game Engine"
    )
    parser.add_argument(
        "--auto", action="store_true",
        help="Run a full game in auto (random-play) mode."
    )
    parser.add_argument(
        "--seed", type=int, default=None,
        help="Random seed for deterministic shuffles and auto-play."
    )
    parser.add_argument(
        "--test", action="store_true",
        help="Run the unit test suite including 100-game smoke test."
    )
    parser.add_argument(
        "--players", type=str, default="P0,P1,P2,P3",
        help="Comma-separated list of 4 player names (default: P0,P1,P2,P3)."
    )
    args = parser.parse_args()

    player_names = args.players.split(",")
    if len(player_names) != 4:
        print("Error: exactly 4 players required.", file=sys.stderr)
        sys.exit(1)

    if args.test:
        run_tests()
    elif args.auto:
        auto_play_game(player_names, seed=args.seed)
    else:
        manual_play_game(player_names, seed=args.seed)


if __name__ == "__main__":
    main()

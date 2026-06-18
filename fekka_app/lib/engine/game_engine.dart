// ═══════════════════════════════════════════════════════════════════════════════
// GameEngine — pure, stateless game logic (ported 1:1 from game-engine.service.ts)
// ═══════════════════════════════════════════════════════════════════════════════
//
// Framework-agnostic: no Flutter, no dart:io, no HTTP deps.
// Takes a game state + a move and returns a new state.

import 'card.dart';
import 'deck.dart';
import 'middle_pool.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Type definitions
// ═══════════════════════════════════════════════════════════════════════════════

class PlayerState {
  final String id;
  final String name;
  List<Card> hand;
  List<Card> stack;
  int cumulativeScore;
  bool eliminated;
  int? rankEarned;
  final int seatIndex;
  bool connected;

  /// Transient field: set by sanitizeForPlayer to show opponent hand count.
  /// Not serialized by default — only attached when hand is hidden.
  int? handCount;

  PlayerState({
    required this.id,
    required this.name,
    List<Card>? hand,
    List<Card>? stack,
    this.cumulativeScore = 0,
    this.eliminated = false,
    this.rankEarned,
    required this.seatIndex,
    this.connected = true,
    this.handCount,
  })  : hand = hand ?? [],
        stack = stack ?? [];

  /// Deep copy for immutability in state transitions.
  PlayerState copy() => PlayerState(
        id: id,
        name: name,
        hand: [...hand],
        stack: [...stack],
        cumulativeScore: cumulativeScore,
        eliminated: eliminated,
        rankEarned: rankEarned,
        seatIndex: seatIndex,
        connected: connected,
        handCount: handCount,
      );

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'id': id,
      'name': name,
      'hand': hand.map((c) => c.toJson()).toList(),
      'stack': stack.map((c) => c.toJson()).toList(),
      'cumulativeScore': cumulativeScore,
      'eliminated': eliminated,
      'rankEarned': rankEarned,
      'seatIndex': seatIndex,
      'connected': connected,
    };
    if (handCount != null) {
      json['handCount'] = handCount;
    }
    return json;
  }

  factory PlayerState.fromJson(Map<String, dynamic> json) => PlayerState(
        id: json['id'] as String,
        name: json['name'] as String,
        hand: (json['hand'] as List<dynamic>?)
                ?.map((c) => Card.fromJson(c as Map<String, dynamic>))
                .toList() ??
            [],
        stack: (json['stack'] as List<dynamic>?)
                ?.map((c) => Card.fromJson(c as Map<String, dynamic>))
                .toList() ??
            [],
        cumulativeScore: json['cumulativeScore'] as int? ?? 0,
        eliminated: json['eliminated'] as bool? ?? false,
        rankEarned: json['rankEarned'] as int?,
        seatIndex: json['seatIndex'] as int,
        connected: json['connected'] as bool? ?? true,
      );
}

class GameState {
  final String roomId;
  List<Card> deck;
  List<Card> pool;
  List<PlayerState> players;
  int currentPlayerIndex;
  int roundPlaysCompleted;
  int nextRank;
  bool gameOver;
  int roundCount;
  int? seed;

  GameState({
    required this.roomId,
    List<Card>? deck,
    List<Card>? pool,
    List<PlayerState>? players,
    this.currentPlayerIndex = 0,
    this.roundPlaysCompleted = 0,
    this.nextRank = 1,
    this.gameOver = false,
    this.roundCount = 0,
    this.seed,
  })  : deck = deck ?? [],
        pool = pool ?? [],
        players = players ?? [];

  GameState copy() => GameState(
        roomId: roomId,
        deck: [...deck],
        pool: [...pool],
        players: players.map((p) => p.copy()).toList(),
        currentPlayerIndex: currentPlayerIndex,
        roundPlaysCompleted: roundPlaysCompleted,
        nextRank: nextRank,
        gameOver: gameOver,
        roundCount: roundCount,
        seed: seed,
      );

  Map<String, dynamic> toJson() => {
        'roomId': roomId,
        'deck': deck.map((c) => c.toJson()).toList(),
        'pool': pool.map((c) => c.toJson()).toList(),
        'players': players.map((p) => p.toJson()).toList(),
        'currentPlayerIndex': currentPlayerIndex,
        'roundPlaysCompleted': roundPlaysCompleted,
        'nextRank': nextRank,
        'gameOver': gameOver,
        'roundCount': roundCount,
        'seed': seed,
      };

  factory GameState.fromJson(Map<String, dynamic> json) => GameState(
        roomId: json['roomId'] as String,
        deck: (json['deck'] as List<dynamic>?)
                ?.map((c) => Card.fromJson(c as Map<String, dynamic>))
                .toList() ??
            [],
        pool: (json['pool'] as List<dynamic>?)
                ?.map((c) => Card.fromJson(c as Map<String, dynamic>))
                .toList() ??
            [],
        players: (json['players'] as List<dynamic>?)
                ?.map((p) => PlayerState.fromJson(p as Map<String, dynamic>))
                .toList() ??
            [],
        currentPlayerIndex: json['currentPlayerIndex'] as int? ?? 0,
        roundPlaysCompleted: json['roundPlaysCompleted'] as int? ?? 0,
        nextRank: json['nextRank'] as int? ?? 1,
        gameOver: json['gameOver'] as bool? ?? false,
        roundCount: json['roundCount'] as int? ?? 0,
        seed: json['seed'] as int?,
      );
}

class StolenEntry {
  final String playerId;
  final List<Card> cards;

  StolenEntry({required this.playerId, required this.cards});

  Map<String, dynamic> toJson() => {
        'playerId': playerId,
        'cards': cards.map((c) => c.toJson()).toList(),
      };
}

class TurnResult {
  final GameState newState;
  final String action; // 'discard' | 'capture' | 'steal' | 'combined'
  final List<Card> poolCaptured;
  final List<StolenEntry> stolenFrom;
  final Card playedCard;
  final bool roundEnded;
  final List<String> eliminatedPlayerIds;

  TurnResult({
    required this.newState,
    required this.action,
    required this.poolCaptured,
    required this.stolenFrom,
    required this.playedCard,
    required this.roundEnded,
    required this.eliminatedPlayerIds,
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
// GameEngine
// ═══════════════════════════════════════════════════════════════════════════════

class GameEngine {
  /// Create the initial game state for a new room.
  GameState createInitialState({
    required String roomId,
    required List<String> playerNames,
    required List<String> playerIds,
    int? seed,
  }) {
    if (playerNames.length != 4 || playerIds.length != 4) {
      throw ArgumentError('Fakka requires exactly 4 players');
    }

    final deck = Deck(seed: seed);

    final players = List<PlayerState>.generate(4, (i) => PlayerState(
          id: playerIds[i],
          name: playerNames[i],
          seatIndex: i,
        ));

    final state = GameState(
      roomId: roomId,
      deck: [...deck.cards],
      players: players,
      seed: seed,
    );

    return setupRound(state);
  }

  // ── Round Setup ──────────────────────────────────────────────────────────

  /// Prepare a new round: deal pool (if empty), deal 3 cards to each active
  /// player, recycle if deck insufficient, reset roundPlaysCompleted.
  GameState setupRound(GameState state) {
    final activePlayers = state.players.where((p) => !p.eliminated).toList();
    final deck = Deck(seed: state.seed)..cards = [...state.deck];
    final pool = MiddlePool()..cards = [...state.pool];

    // Calculate cards needed.
    var needed = 0;
    if (pool.isEmpty) needed += 4;
    needed += activePlayers.length * 3;

    // Recycle non-held cards if deck is insufficient.
    if (deck.remaining < needed) {
      final poolCards = <Card>[];
      while (!pool.isEmpty) {
        poolCards.add(pool.pop());
      }
      final excluded = <Card>[];
      for (final p in state.players) {
        excluded.addAll(p.stack);
      }
      deck.recycle(poolCards, excluded);
    }

    // Recalculate after recycling.
    var postNeeded = 0;
    if (pool.isEmpty) postNeeded += 4;
    postNeeded += activePlayers.length * 3;

    if (deck.remaining < postNeeded) {
      // Fallback: deal proportionally.
      if (pool.isEmpty && deck.remaining > 0) {
        final poolDeal = min(4, deck.remaining);
        for (final c in deck.deal(poolDeal)) {
          pool.push(c);
        }
      }
      final remainingAfterPool = deck.remaining;
      final numPlayers = activePlayers.length;
      if (numPlayers > 0 && remainingAfterPool > 0) {
        final perPlayer = remainingAfterPool ~/ numPlayers;
        final remainder = remainingAfterPool % numPlayers;
        for (var i = 0; i < numPlayers; i++) {
          final dealN = perPlayer + (i < remainder ? 1 : 0);
          if (dealN > 0) {
            activePlayers[i].hand = deck.deal(dealN);
          }
        }
      }
    } else {
      // Normal path: enough cards.
      if (pool.isEmpty) {
        for (final c in deck.deal(4)) {
          pool.push(c);
        }
      }
      for (final player in activePlayers) {
        player.hand = deck.deal(3);
      }
    }

    // If the current player was dealt an empty hand, advance to the next
    // active player who has cards. If no active player has cards, the game
    // cannot continue; assign final ranks and mark it over.
    var newCurrentPlayerIndex = state.currentPlayerIndex % activePlayers.length;
    var gameOver = state.gameOver;
    var nextRank = state.nextRank;
    final handsDealt = activePlayers.map((p) => p.hand.length).toList();
    if (handsDealt.every((n) => n == 0)) {
      gameOver = true;
      // Deck exhausted: rank remaining active players from highest score
      // (lowest rank number) to lowest score (highest rank number).
      final ranked = activePlayers.toList()
        ..sort((a, b) {
          final scoreDiff = b.cumulativeScore - a.cumulativeScore;
          if (scoreDiff != 0) return scoreDiff;
          return a.seatIndex - b.seatIndex;
        });
      for (final p in ranked) {
        p.rankEarned = nextRank;
        p.eliminated = true;
        nextRank++;
      }
    } else {
      final startIndex = newCurrentPlayerIndex;
      while (activePlayers[newCurrentPlayerIndex].hand.isEmpty) {
        newCurrentPlayerIndex =
            (newCurrentPlayerIndex + 1) % activePlayers.length;
        if (newCurrentPlayerIndex == startIndex) {
          // Should not happen because we already checked not all are empty,
          // but handle defensively.
          gameOver = true;
          break;
        }
      }
    }

    return GameState(
      roomId: state.roomId,
      deck: [...deck.cards],
      pool: [...pool.cards],
      players: state.players.map((p) => p.copy()).toList(),
      roundPlaysCompleted: 0,
      currentPlayerIndex: newCurrentPlayerIndex,
      nextRank: nextRank,
      gameOver: gameOver,
      roundCount: state.roundCount + 1,
      seed: state.seed,
    );
  }

  // ── Core Turn Logic ──────────────────────────────────────────────────────

  /// Process a single play — THE critical method.
  ///
  /// 1. Validate it's the player's turn.
  /// 2. Remove card from hand.
  /// 3. Try pool capture via sequential reveal.
  /// 4. Try stack steals from opponents with matching top.
  /// 5. Merge captured + played + stolen onto player's stack.
  /// 6. If nothing matches, discard to pool.
  /// 7. Advance turn; check if round ended.
  TurnResult processTurn(GameState state, String playerId, Card card) {
    final activePlayers = state.players.where((p) => !p.eliminated).toList();

    if (activePlayers.isEmpty) {
      throw StateError('No active players — game is over');
    }

    final playerIndex = activePlayers.indexWhere((p) => p.id == playerId);
    if (playerIndex == -1) {
      throw StateError('Player $playerId is not active or not found');
    }

    if (playerIndex != state.currentPlayerIndex % activePlayers.length) {
      final currentId = activePlayers[state.currentPlayerIndex % activePlayers.length].id;
      throw StateError("Not player $playerId's turn (current: $currentId)");
    }

    final player = activePlayers[playerIndex];

    // Remove card from hand (exact match by rank + suit).
    final handIndex = player.hand.indexWhere(
        (c) => c.rank == card.rank && c.suit == card.suit);
    if (handIndex == -1) {
      throw StateError('Card ${card.rank}${card.suit} not found in hand');
    }
    player.hand.removeAt(handIndex);

    // 1. Pool capture via sequential reveal.
    final pool = MiddlePool()..cards = [...state.pool];
    final poolCaptured = pool.sequentialReveal(card.rank);

    // 2. Steal from opponent stacks matching top.
    final stolenFrom = <StolenEntry>[];
    for (final p in state.players) {
      if (p.eliminated) continue;
      if (p.id == playerId) continue;

      final stackTop = p.stack.isEmpty ? null : p.stack.last;
      if (stackTop != null && stackTop.rank == card.rank) {
        stolenFrom.add(StolenEntry(playerId: p.id, cards: [...p.stack]));
        p.stack.clear();
      }
    }

    // 3. Determine outcome.
    final String action;
    if (poolCaptured.isNotEmpty || stolenFrom.isNotEmpty) {
      final merged = <Card>[];

      // (a) Pool-captured cards in cascade order.
      merged.addAll(poolCaptured);
      // (b) The played card.
      merged.add(card);
      // (c) Stolen stacks in seat order.
      for (final entry in stolenFrom) {
        merged.addAll(entry.cards);
      }

      player.stack.addAll(merged);

      if (poolCaptured.isNotEmpty && stolenFrom.isNotEmpty) {
        action = 'combined';
      } else if (poolCaptured.isNotEmpty) {
        action = 'capture';
      } else {
        action = 'steal';
      }
    } else {
      pool.push(card);
      action = 'discard';
    }

    // Advance turn, skipping any active players who ran out of cards.
    var newCurrentPlayerIndex =
        (state.currentPlayerIndex + 1) % activePlayers.length;
    final startIndex = newCurrentPlayerIndex;
    while (activePlayers[newCurrentPlayerIndex].hand.isEmpty) {
      newCurrentPlayerIndex =
          (newCurrentPlayerIndex + 1) % activePlayers.length;
      // Guard against an infinite loop if every active hand is empty; in that
      // case roundEnded will be true below and the round will end.
      if (newCurrentPlayerIndex == startIndex) break;
    }
    final newRoundPlaysCompleted = state.roundPlaysCompleted + 1;

    final newState = GameState(
      roomId: state.roomId,
      deck: [...state.deck],
      pool: [...pool.cards],
      players: state.players.map((p) => p.copy()).toList(),
      currentPlayerIndex: newCurrentPlayerIndex,
      roundPlaysCompleted: newRoundPlaysCompleted,
      nextRank: state.nextRank,
      gameOver: state.gameOver,
      roundCount: state.roundCount,
      seed: state.seed,
    );

    // Round ends when all active players have empty hands.
    final roundEnded = activePlayers.every((ap) {
      final sp = newState.players.firstWhere((p) => p.id == ap.id);
      return sp.hand.isEmpty;
    });

    return TurnResult(
      newState: newState,
      action: action,
      poolCaptured: poolCaptured,
      stolenFrom: stolenFrom,
      playedCard: card,
      roundEnded: roundEnded,
      eliminatedPlayerIds: [],
    );
  }

  // ── Round Scoring ────────────────────────────────────────────────────────

  /// Each active player adds their stack score to cumulative total.
  /// NOTE: stacks are NOT cleared — cards stay for the next round.
  GameState scoreRound(GameState state) {
    final newPlayers = state.players.map((p) {
      if (p.eliminated) return p.copy();
      final roundScore = p.stack.fold<int>(0, (sum, c) => sum + c.pointValue);
      return p.copy()
        ..cumulativeScore = p.cumulativeScore + roundScore;
    }).toList();

    return GameState(
      roomId: state.roomId,
      deck: [...state.deck],
      pool: [...state.pool],
      players: newPlayers,
      currentPlayerIndex: state.currentPlayerIndex,
      roundPlaysCompleted: state.roundPlaysCompleted,
      nextRank: state.nextRank,
      gameOver: state.gameOver,
      roundCount: state.roundCount,
      seed: state.seed,
    );
  }

  // ── Elimination ──────────────────────────────────────────────────────────

  /// Check for players ≥51 cumulative points. Assign ranks, eliminate.
  /// If 1 active player remains, auto-assign final rank.
  EliminationResult checkElimination(GameState state) {
    final activePlayers = state.players.where((p) => !p.eliminated).toList();
    final qualifiers =
        activePlayers.where((p) => p.cumulativeScore >= 51).toList();

    if (qualifiers.isEmpty) {
      return EliminationResult(newState: state, eliminatedPlayerIds: []);
    }

    // Sort by score descending, tie-break seatIndex ascending.
    qualifiers.sort((a, b) {
      final scoreDiff = b.cumulativeScore - a.cumulativeScore;
      if (scoreDiff != 0) return scoreDiff;
      return a.seatIndex - b.seatIndex;
    });

    var nextRank = state.nextRank;
    final eliminatedIds = <String>[];
    final players = state.players.map((p) => p.copy()).toList();

    for (final q in qualifiers) {
      final idx = players.indexWhere((p) => p.id == q.id);
      if (idx != -1) {
        players[idx]
          ..rankEarned = nextRank
          ..eliminated = true;
        eliminatedIds.add(q.id);
        nextRank++;
      }
    }

    var gameOver = state.gameOver;
    final remainingActive = players.where((p) => !p.eliminated).toList();

    if (remainingActive.length == 1) {
      final idx = players.indexWhere((p) => p.id == remainingActive[0].id);
      players[idx]
        ..rankEarned = nextRank
        ..eliminated = true;
      eliminatedIds.add(remainingActive[0].id);
      gameOver = true;
    }

    if (players.every((p) => p.eliminated)) {
      gameOver = true;
    }

    final newActive = players.where((p) => !p.eliminated).toList();
    final newCurrentPlayerIndex = newActive.isNotEmpty
        ? state.currentPlayerIndex % newActive.length
        : 0;

    return EliminationResult(
      newState: GameState(
        roomId: state.roomId,
        deck: [...state.deck],
        pool: [...state.pool],
        players: players,
        currentPlayerIndex: newCurrentPlayerIndex,
        roundPlaysCompleted: state.roundPlaysCompleted,
        nextRank: nextRank,
        gameOver: gameOver,
        roundCount: state.roundCount,
        seed: state.seed,
      ),
      eliminatedPlayerIds: eliminatedIds,
    );
  }

  // ── Full Round End Processing ────────────────────────────────────────────

  /// Score round + check eliminations, return combined TurnResult.
  TurnResult processRoundEnd(GameState state) {
    final scored = scoreRound(state);
    final elim = checkElimination(scored);

    return TurnResult(
      newState: elim.newState,
      action: 'discard',
      poolCaptured: [],
      stolenFrom: [],
      playedCard: Card(rank: '', suit: ''),
      roundEnded: true,
      eliminatedPlayerIds: elim.eliminatedPlayerIds,
    );
  }

  // ── State Sanitization ───────────────────────────────────────────────────

  /// Sanitize game state for a specific player.
  /// Hides opponents' hands, shows only stack top + hand count.
  GameState sanitizeForPlayer(GameState state, String playerId) {
    return GameState(
      roomId: state.roomId,
      deck: [], // Never reveal deck to clients.
      pool: [...state.pool],
      players: state.players.map((p) {
        if (p.id == playerId) return p.copy(); // Full info for owner.

        final stackTop =
            p.stack.isNotEmpty ? [p.stack.last] : <Card>[];
        final copy = p.copy()
          ..hand = [] // Hide opponent hand contents.
          ..stack = stackTop // Show only top card.
          ..handCount = p.hand.length; // Show hand count.
        return copy;
      }).toList(),
      currentPlayerIndex: state.currentPlayerIndex,
      roundPlaysCompleted: state.roundPlaysCompleted,
      nextRank: state.nextRank,
      gameOver: state.gameOver,
      roundCount: state.roundCount,
      seed: state.seed,
    );
  }
}

/// Result from [GameEngine.checkElimination].
class EliminationResult {
  final GameState newState;
  final List<String> eliminatedPlayerIds;

  EliminationResult({
    required this.newState,
    required this.eliminatedPlayerIds,
  });
}

/// Math.min for int (avoid dart:math import pollution in engine).
int min(int a, int b) => a < b ? a : b;

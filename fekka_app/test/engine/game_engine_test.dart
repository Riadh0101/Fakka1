// ═══════════════════════════════════════════════════════════════════════════════
// GameEngine Unit Tests — ported from TS Jest suite
// ═══════════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:fekka_app/engine/card.dart';
import 'package:fekka_app/engine/deck.dart';
import 'package:fekka_app/engine/player_stack.dart';
import 'package:fekka_app/engine/middle_pool.dart';
import 'package:fekka_app/engine/game_engine.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Test: Card
// ═══════════════════════════════════════════════════════════════════════════════

void main() {
  group('Card', () {
    test('should have rank-only equality via matches()', () {
      final c1 = Card(rank: '7', suit: '\u2660'); // 7♠
      final c2 = Card(rank: '7', suit: '\u2663'); // 7♣
      expect(c1.matches(c2), isTrue);
    });

    test('should not match different ranks', () {
      final c1 = Card(rank: 'K', suit: '\u2660');
      final c2 = Card(rank: 'Q', suit: '\u2660');
      expect(c1.matches(c2), isFalse);
    });

    test('should score face cards as 2 points', () {
      expect(Card(rank: 'J', suit: '\u2660').pointValue, 2);
      expect(Card(rank: 'Q', suit: '\u2663').pointValue, 2);
      expect(Card(rank: 'K', suit: '\u2665').pointValue, 2);
    });

    test('should score numeral cards as 1 point', () {
      for (final r in ['1', '2', '3', '4', '5', '6', '7']) {
        expect(Card(rank: r, suit: '\u2666').pointValue, 1);
      }
    });

    test('should produce correct string representation', () {
      final c = Card(rank: 'K', suit: '\u2660');
      expect(c.toString(), 'K\u2660');
    });

    test('should support exact match for deck uniqueness', () {
      final c1 = Card(rank: '3', suit: '\u2660');
      final c2 = Card(rank: '3', suit: '\u2666');
      expect(c1.exactMatch(c2), isFalse);
      expect(c1.exactMatch(c1), isTrue);
    });

    test('should serialize and deserialize from JSON', () {
      final c = Card(rank: '7', suit: '\u2665');
      final json = c.toJson();
      final restored = Card.fromJson(json);
      expect(restored.exactMatch(c), isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Test: Deck
  // ═══════════════════════════════════════════════════════════════════════════

  group('Deck', () {
    test('should build a 40-card deck', () {
      final deck = Deck(seed: 42);
      expect(deck.remaining, 40);
    });

    test('should deal cards from the top', () {
      final deck = Deck(seed: 42);
      final dealt = deck.deal(3);
      expect(dealt, hasLength(3));
      expect(deck.remaining, 37);
    });

    test('should throw if dealing more than available', () {
      final deck = Deck(seed: 42);
      expect(() => deck.deal(41), throwsStateError);
    });

    test('should recycle cards excluding held ones', () {
      final deck = Deck(seed: 42);
      final poolCards = deck.deal(35);
      final heldCards = deck.deal(2);
      expect(deck.remaining, 3);

      deck.recycle(poolCards, heldCards);
      expect(deck.remaining, 38);
    });

    test('deterministic seed produces same order', () {
      final deck1 = Deck(seed: 42);
      final deck2 = Deck(seed: 42);
      final cards1 = deck1.deal(5);
      final cards2 = deck2.deal(5);
      for (var i = 0; i < 5; i++) {
        expect(cards1[i].exactMatch(cards2[i]), isTrue);
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Test: PlayerStack
  // ═══════════════════════════════════════════════════════════════════════════

  group('PlayerStack', () {
    late PlayerStack stack;

    setUp(() {
      stack = PlayerStack();
    });

    test('should push and peek', () {
      stack.push(Card(rank: '1', suit: '\u2660'));
      expect(stack.peekTop()!.exactMatch(Card(rank: '1', suit: '\u2660')),
          isTrue);
      expect(stack.size, 1);
    });

    test('should pop from top', () {
      stack.push(Card(rank: 'K', suit: '\u2665'));
      final popped = stack.pop();
      expect(popped.exactMatch(Card(rank: 'K', suit: '\u2665')), isTrue);
      expect(stack.isEmpty, isTrue);
    });

    test('should throw on pop empty', () {
      expect(() => stack.pop(), throwsStateError);
    });

    test('should pushMany in correct order', () {
      final cards = [
        Card(rank: '1', suit: '\u2660'),
        Card(rank: '2', suit: '\u2660'),
        Card(rank: '3', suit: '\u2660'),
      ];
      stack.pushMany(cards);
      expect(stack.size, 3);
      expect(stack.peekTop()!.exactMatch(Card(rank: '3', suit: '\u2660')),
          isTrue);

      expect(stack.pop().exactMatch(Card(rank: '3', suit: '\u2660')), isTrue);
      expect(stack.pop().exactMatch(Card(rank: '2', suit: '\u2660')), isTrue);
      expect(stack.pop().exactMatch(Card(rank: '1', suit: '\u2660')), isTrue);
    });

    test('should stealAll and empty stack', () {
      stack.pushMany([
        Card(rank: '4', suit: '\u2660'),
        Card(rank: '5', suit: '\u2660'),
        Card(rank: '6', suit: '\u2660'),
      ]);
      final stolen = stack.stealAll();
      expect(stolen, hasLength(3));
      expect(stack.isEmpty, isTrue);
      expect(stack.size, 0);
    });

    test('should score correctly', () {
      stack.push(Card(rank: '1', suit: '\u2660')); // 1 pt
      stack.push(Card(rank: 'J', suit: '\u2660')); // 2 pt
      stack.push(Card(rank: 'K', suit: '\u2660')); // 2 pt
      expect(stack.score(), 5);
    });

    test('should peekAll without modifying', () {
      stack.push(Card(rank: '7', suit: '\u2663'));
      final all = stack.peekAll();
      expect(all, hasLength(1));
      expect(stack.size, 1);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Test: MiddlePool
  // ═══════════════════════════════════════════════════════════════════════════

  group('MiddlePool', () {
    late MiddlePool pool;

    setUp(() {
      pool = MiddlePool();
    });

    test('should return empty when pool is empty', () {
      final captured = pool.sequentialReveal('7');
      expect(captured, isEmpty);
    });

    test('should capture a single matching top card', () {
      pool.push(Card(rank: '5', suit: '\u2660'));
      final captured = pool.sequentialReveal('5');
      expect(captured, hasLength(1));
      expect(captured[0].exactMatch(Card(rank: '5', suit: '\u2660')), isTrue);
      expect(pool.isEmpty, isTrue);
    });

    test('should capture three matching cards in cascade order', () {
      pool.push(Card(rank: 'K', suit: '\u2666')); // blocker (bottom)
      pool.push(Card(rank: '7', suit: '\u2660')); // 1st match (deepest)
      pool.push(Card(rank: '7', suit: '\u2663')); // 2nd match
      pool.push(Card(rank: '7', suit: '\u2665')); // 3rd match (top)

      final captured = pool.sequentialReveal('7');
      expect(captured, hasLength(3));
      // Cascade order: top→deepest: 7♥, 7♣, 7♠
      expect(captured[0].exactMatch(Card(rank: '7', suit: '\u2665')), isTrue);
      expect(captured[1].exactMatch(Card(rank: '7', suit: '\u2663')), isTrue);
      expect(captured[2].exactMatch(Card(rank: '7', suit: '\u2660')), isTrue);
      // Pool should now have only the blocker.
      expect(pool.size, 1);
      expect(pool.peekTop()!.exactMatch(Card(rank: 'K', suit: '\u2666')),
          isTrue);
    });

    test('should return empty when top does not match', () {
      pool.push(Card(rank: 'K', suit: '\u2660'));
      final captured = pool.sequentialReveal('3');
      expect(captured, isEmpty);
      expect(pool.size, 1);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Helpers for GameEngine tests
  // ═══════════════════════════════════════════════════════════════════════════

  GameState makeTestState({List<Card>? poolCards}) {
    return GameState(
      roomId: 'TEST01',
      pool: poolCards ?? [],
      players: [
        PlayerState(id: 'p0', name: 'P0', seatIndex: 0),
        PlayerState(id: 'p1', name: 'P1', seatIndex: 1),
        PlayerState(id: 'p2', name: 'P2', seatIndex: 2),
        PlayerState(id: 'p3', name: 'P3', seatIndex: 3),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Test: GameEngine — 12 Required Scenarios
  // ═══════════════════════════════════════════════════════════════════════════

  group('GameEngine', () {
    final engine = GameEngine();

    // Scenario 1: Discard to empty pool
    test('Scenario 1: should discard to empty pool when no match', () {
      final state = makeTestState();
      state.players[0].hand = [Card(rank: '3', suit: '\u2660')];

      final result =
          engine.processTurn(state, 'p0', Card(rank: '3', suit: '\u2660'));
      expect(result.action, 'discard');
      expect(result.poolCaptured, isEmpty);
      expect(result.stolenFrom, isEmpty);
      expect(result.newState.pool, hasLength(1));
      expect(result.newState.pool[0].exactMatch(Card(rank: '3', suit: '\u2660')),
          isTrue);
    });

    // Scenario 2: Single pool capture
    test('Scenario 2: should capture a single matching pool top', () {
      final state = makeTestState(poolCards: [Card(rank: '4', suit: '\u2660')]);
      state.players[0].hand = [Card(rank: '4', suit: '\u2663')];

      final result =
          engine.processTurn(state, 'p0', Card(rank: '4', suit: '\u2663'));
      expect(result.action, 'capture');
      expect(result.poolCaptured, hasLength(1));
      expect(result.newState.pool, isEmpty);
      expect(result.newState.players[0].stack, hasLength(2));
    });

    // Scenario 3: 3-deep sequential reveal cascade
    test('Scenario 3: should capture three matching cards in cascade', () {
      final state = makeTestState(poolCards: [
        Card(rank: 'K', suit: '\u2666'), // bottom — blocker
        Card(rank: '7', suit: '\u2660'), // match
        Card(rank: '7', suit: '\u2663'), // match
        Card(rank: '7', suit: '\u2665'), // match (top)
      ]);
      state.players[0].hand = [Card(rank: '7', suit: '\u2666')];

      final result =
          engine.processTurn(state, 'p0', Card(rank: '7', suit: '\u2666'));
      expect(result.action, 'capture');
      expect(result.poolCaptured, hasLength(3));
      expect(result.newState.pool, hasLength(1));
      expect(
          result.newState.pool[0].exactMatch(Card(rank: 'K', suit: '\u2666')),
          isTrue);
      expect(result.newState.players[0].stack, hasLength(4));
    });

    // Scenario 4: Steal from one opponent
    test('Scenario 4: should steal from one opponent when top matches', () {
      final state = makeTestState();
      state.players[1].stack = [
        Card(rank: '1', suit: '\u2660'),
        Card(rank: '2', suit: '\u2660'),
        Card(rank: '5', suit: '\u2663'), // top — rank 5
      ];
      state.players[0].hand = [Card(rank: '5', suit: '\u2666')];

      final result =
          engine.processTurn(state, 'p0', Card(rank: '5', suit: '\u2666'));
      expect(result.action, 'steal');
      expect(result.stolenFrom, hasLength(1));
      expect(result.stolenFrom[0].playerId, 'p1');
      expect(result.newState.players[1].stack, isEmpty);
      expect(result.newState.players[0].stack, hasLength(4));
    });

    // Scenario 5: Steal from two opponents simultaneously
    test('Scenario 5: should steal from two opponents in same turn', () {
      final state = makeTestState();
      state.players[1].stack = [Card(rank: '5', suit: '\u2660')];
      state.players[2].stack = [
        Card(rank: '1', suit: '\u2660'),
        Card(rank: '5', suit: '\u2663'),
      ];
      state.players[0].hand = [Card(rank: '5', suit: '\u2666')];

      final result =
          engine.processTurn(state, 'p0', Card(rank: '5', suit: '\u2666'));
      expect(result.action, 'steal');
      expect(result.stolenFrom, hasLength(2));
      expect(result.newState.players[1].stack, isEmpty);
      expect(result.newState.players[2].stack, isEmpty);
      expect(result.newState.players[0].stack, hasLength(4));
    });

    // Scenario 6: Combined pool-cascade + steal in same turn
    test('Scenario 6: should combine pool capture and steal', () {
      final state =
          makeTestState(poolCards: [Card(rank: '6', suit: '\u2660')]);
      state.players[1].stack = [
        Card(rank: 'Q', suit: '\u2660'),
        Card(rank: '6', suit: '\u2663'),
      ];
      state.players[2].stack = [Card(rank: '6', suit: '\u2665')];
      state.players[0].hand = [Card(rank: '6', suit: '\u2666')];

      final result =
          engine.processTurn(state, 'p0', Card(rank: '6', suit: '\u2666'));
      expect(result.action, 'combined');
      expect(result.poolCaptured, hasLength(1));
      expect(result.stolenFrom, hasLength(2));
      expect(result.newState.pool, isEmpty);
      expect(result.newState.players[1].stack, isEmpty);
      expect(result.newState.players[2].stack, isEmpty);
      expect(result.newState.players[0].stack, hasLength(5));
    });

    // Scenario 7: Elimination at 51 points
    test('Scenario 7: should eliminate player at 51+ cumulative score', () {
      final state = makeTestState();
      state.players[0].cumulativeScore = 51;

      final elim = engine.checkElimination(state);
      expect(elim.newState.gameOver, isFalse);
      expect(elim.newState.players[0].eliminated, isTrue);
      expect(elim.newState.players[0].rankEarned, 1);
      expect(elim.eliminatedPlayerIds, contains('p0'));
    });

    // Scenario 8: Multiple eliminations in one round
    test('Scenario 8: should rank multiple qualifiers by score desc', () {
      final state = makeTestState();
      state.players[0].cumulativeScore = 51; // P0: 51
      state.players[1].cumulativeScore = 60; // P1: 60 (higher = better rank)
      state.players[2].cumulativeScore = 55; // P2: 55

      final elim = engine.checkElimination(state);
      expect(elim.eliminatedPlayerIds, containsAll(['p0', 'p1', 'p2']));
      // P1 should have best rank (1) because highest score.
      expect(elim.newState.players[1].rankEarned, 1);
      expect(elim.newState.players[2].rankEarned, 2);
      expect(elim.newState.players[0].rankEarned, 3);
      // P3 is last active → auto-ranked 4, game over.
      expect(elim.newState.players[3].eliminated, isTrue);
      expect(elim.newState.players[3].rankEarned, 4);
      expect(elim.newState.gameOver, isTrue);
    });

    // Scenario 9: Sanitize for player hides opponent hands
    test('Scenario 9: should sanitize state hiding opponent hands', () {
      final state = makeTestState();
      state.players[0].hand = [Card(rank: '3', suit: '\u2660')];
      state.players[1].hand = [Card(rank: 'K', suit: '\u2665')];
      state.players[1].stack = [Card(rank: '7', suit: '\u2663')];

      final sanitized = engine.sanitizeForPlayer(state, 'p0');

      // P0 sees their own hand.
      expect(sanitized.players[0].hand, hasLength(1));
      // P1's hand is hidden (empty).
      expect(sanitized.players[1].hand, isEmpty);
      // P1's stack only shows top card.
      expect(sanitized.players[1].stack, hasLength(1));
      expect(
          sanitized.players[1].stack[0].exactMatch(Card(rank: '7', suit: '\u2663')),
          isTrue);
    });

    // Scenario 10: createInitialState with seed
    test('Scenario 10: should create initial state with seed determinism', () {
      final state1 = engine.createInitialState(
        roomId: 'R1',
        playerNames: ['A', 'B', 'C', 'D'],
        playerIds: ['a', 'b', 'c', 'd'],
        seed: 42,
      );
      final state2 = engine.createInitialState(
        roomId: 'R2',
        playerNames: ['A', 'B', 'C', 'D'],
        playerIds: ['a', 'b', 'c', 'd'],
        seed: 42,
      );
      // Both states should have identical deck order.
      for (var i = 0; i < state1.deck.length; i++) {
        expect(state1.deck[i].exactMatch(state2.deck[i]), isTrue);
      }
      // Each player should have 3 cards.
      for (var i = 0; i < 4; i++) {
        expect(state1.players[i].hand, hasLength(3));
      }
      // Pool should have 4 cards.
      expect(state1.pool, hasLength(4));
    });

    // Scenario 11: Turn validation
    test('Scenario 11: should reject play when not player turn', () {
      final state = makeTestState();
      state.players[0].hand = [Card(rank: '1', suit: '\u2660')];
      state.currentPlayerIndex = 1; // P1's turn, not P0.

      expect(
        () => engine.processTurn(state, 'p0', Card(rank: '1', suit: '\u2660')),
        throwsStateError,
      );
    });

    // Scenario 12: scoreRound adds to cumulative
    test('Scenario 12: should score round and accumulate', () {
      final state = makeTestState();
      state.players[0].stack = [
        Card(rank: '1', suit: '\u2660'), // 1
        Card(rank: 'J', suit: '\u2660'), // 2
      ];

      final scored = engine.scoreRound(state);
      expect(scored.players[0].cumulativeScore, 3);
    });

    // Scenario 13: No self-steal — playing a card matching own stack top
    test('Scenario 13: should NOT steal from own stack', () {
      final state = makeTestState();
      // P0 has stack with top = 5.
      state.players[0].stack = [
        Card(rank: '1', suit: '\u2660'),
        Card(rank: '5', suit: '\u2660'), // top
      ];
      state.players[0].hand = [Card(rank: '5', suit: '\u2663')];

      final result =
          engine.processTurn(state, 'p0', Card(rank: '5', suit: '\u2663'));
      // Should be capture (own stack match is ignored, discard to pool).
      // Pool was empty, so no capture → discard.
      expect(result.action, 'discard');
      // Own stack unchanged (not stolen from self).
      expect(result.newState.players[0].stack, hasLength(2));
      // Card discarded to pool.
      expect(result.newState.pool, hasLength(1));
    });

    // Scenario 14: J/Q/K should not match numerals
    test('Scenario 14: should NOT match J/Q/K with numeral ranks', () {
      final state = makeTestState(
          poolCards: [Card(rank: '1', suit: '\u2660')]);
      state.players[0].hand = [Card(rank: 'J', suit: '\u2660')];

      final result =
          engine.processTurn(state, 'p0', Card(rank: 'J', suit: '\u2660'));
      // J does not match 1 — discard.
      expect(result.action, 'discard');
      expect(result.poolCaptured, isEmpty);
    });

    // Scenario 15: Pool persists across rounds
    test('Scenario 15: pool should persist across round resets', () {
      final state = makeTestState(
          poolCards: [Card(rank: 'K', suit: '\u2660')]);
      // Setup a new round — pool should NOT be cleared since it's non-empty.
      final newState = engine.setupRound(state);
      // Pool should still have the K.
      expect(newState.pool, hasLength(1));
      expect(
          newState.pool[0].exactMatch(Card(rank: 'K', suit: '\u2660')), isTrue);
    });

    // Scenario 16: Deck recycling card count integrity
    test('Scenario 16: createInitialState should account for all 40 cards', () {
      final state = engine.createInitialState(
        roomId: 'R1',
        playerNames: ['A', 'B', 'C', 'D'],
        playerIds: ['a', 'b', 'c', 'd'],
        seed: 123,
      );

      // 4 players × 3 cards = 12 in hands
      var handCards = 0;
      for (final p in state.players) {
        handCards += p.hand.length;
      }
      // 4 pool cards + 12 hand cards + deck remainder = 40
      final total = state.pool.length + handCards + state.deck.length;
      expect(total, 40);
    });

    // Scenario 17: scoreRound with all players having cards
    test('Scenario 17: scoreRound should accumulate for multiple players', () {
      final state = makeTestState();
      state.players[0].stack = [Card(rank: '7', suit: '\u2660')]; // 1 pt
      state.players[1].stack = [
        Card(rank: 'J', suit: '\u2660'),
        Card(rank: 'K', suit: '\u2660'),
      ]; // 4 pt
      state.players[2].stack = []; // 0 pt

      final scored = engine.scoreRound(state);
      expect(scored.players[0].cumulativeScore, 1);
      expect(scored.players[1].cumulativeScore, 4);
      expect(scored.players[2].cumulativeScore, 0);
    });
  });
}

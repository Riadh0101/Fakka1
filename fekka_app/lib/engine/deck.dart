// ═══════════════════════════════════════════════════════════════════════════════
// Deck — a 40-card Italian deck with shuffle, deal, and recycle
// ═══════════════════════════════════════════════════════════════════════════════
// Ported 1:1 from deck.ts

import 'dart:math';
import 'card.dart';

/// Mulberry32 PRNG — mirrors the TS implementation for deterministic shuffles.
int _mulberry32(int seed) {
  var state = seed;
  state = (state + 0x6D2B79F5) & 0xFFFFFFFF;
  var t = (state ^ (state >> 15)) * (1 | state);
  t = (t + (t ^ (t >> 7)) * (61 | t)) ^ t;
  return ((t ^ (t >> 14)) >> 0) & 0xFFFFFFFF;
}

/// Seeded random generator matching mulberry32 output as [0, 1) double.
double _seededRandom(int seed) {
  return _mulberry32(seed).toDouble() / 4294967296.0;
}

/// Fisher-Yates shuffle using a provided random function.
void _shuffleList<T>(List<T> list, double Function() rand) {
  for (var i = list.length - 1; i > 0; i--) {
    final j = (rand() * (i + 1)).floor();
    final tmp = list[i];
    list[i] = list[j];
    list[j] = tmp;
  }
}

/// A 40-card Italian deck.
///
/// Contains all combinations of 4 suits × 10 ranks.
/// Supports seeded shuffling for deterministic testing.
class Deck {
  List<Card> _cards;
  final int? _seed;
  int _shuffleCount = 0;
  final Random _rng = Random();

  Deck({int? seed})
      : _cards = [],
        _seed = seed {
    _build();
    shuffle(seed);
  }

  /// Build the 40-card deck: each rank × each suit.
  void _build() {
    _cards = [];
    for (final r in ranks) {
      for (final s in suits) {
        _cards.add(Card(rank: r, suit: s));
      }
    }
  }

  /// Shuffle the deck. Optional seed for deterministic testing.
  ///
  /// When no seed is explicitly provided but the deck was constructed
  /// with one, the effective seed is `storedSeed + shuffleCount` so that
  /// each shuffle call produces a different deterministic ordering.
  void shuffle([int? seed]) {
    int? effectiveSeed = seed;
    if (effectiveSeed == null && _seed != null) {
      effectiveSeed = _seed! + _shuffleCount;
    }
    if (effectiveSeed != null) {
      final rand = () => _seededRandom(effectiveSeed!);
      _shuffleList(_cards, rand);
    } else {
      _shuffleList(_cards, _rng.nextDouble);
    }
    _shuffleCount++;
  }

  /// Deal `n` cards from the top (end) of the deck.
  /// Throws if fewer than `n` cards remain.
  List<Card> deal(int n) {
    if (n > _cards.length) {
      throw StateError(
          'Deck has only ${_cards.length} cards, cannot deal $n');
    }
    final dealt = <Card>[];
    for (var i = 0; i < n; i++) {
      dealt.add(_cards.removeLast());
    }
    return dealt;
  }

  /// Gather all non-excluded cards into the deck and reshuffle.
  ///
  /// [availableCards] are gathered from the pool to be recycled.
  /// [excludedCards] are player-stack cards that stay held and are NOT recycled.
  void recycle(List<Card> availableCards, List<Card> excludedCards) {
    final excludedSet = <String>{};
    for (final c in excludedCards) {
      excludedSet.add(c.key);
    }

    final gathered = <Card>[];
    for (final c in availableCards) {
      if (!excludedSet.contains(c.key)) gathered.add(c);
    }
    for (final c in _cards) {
      if (!excludedSet.contains(c.key)) gathered.add(c);
    }

    _cards = gathered;
    shuffle(); // Auto-incremented seed derivative
  }

  /// Number of cards left.
  int get remaining => _cards.length;

  /// Read-only view of cards.
  List<Card> get cards => List.unmodifiable(_cards);

  /// Replace all cards (for deserialization).
  set cards(List<Card> value) {
    _cards = [...value];
  }
}

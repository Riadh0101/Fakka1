// ═══════════════════════════════════════════════════════════════════════════════
// PlayerStack — LIFO card stack (private stacks & base for Middle Pool)
// ═══════════════════════════════════════════════════════════════════════════════
// Ported 1:1 from player-stack.ts

import 'card.dart';

/// A private LIFO (last-in-first-out) card stack.
///
/// Index 0 = bottom of stack, last element = top.
/// Used for each player's captured-card stack and as base for MiddlePool.
class PlayerStack {
  final List<Card> _cards = [];

  /// Push a single card onto the top.
  void push(Card card) => _cards.add(card);

  /// Push multiple cards in order: first → bottom, last → new top.
  void pushMany(List<Card> cards) {
    for (final c in cards) {
      _cards.add(c);
    }
  }

  /// Remove and return the top card. Throws if empty.
  Card pop() {
    if (_cards.isEmpty) throw StateError('Cannot pop from empty stack');
    return _cards.removeLast();
  }

  /// Return the top card without removing, or null if empty.
  Card? peekTop() => _cards.isEmpty ? null : _cards.last;

  /// Return all cards and clear the stack (for opponent steals).
  List<Card> stealAll() {
    final stolen = List<Card>.from(_cards);
    _cards.clear();
    return stolen;
  }

  /// Return a copy of all cards without modifying the stack.
  List<Card> peekAll() => List<Card>.from(_cards);

  /// Sum the point values of all cards in this stack.
  int score() => _cards.fold(0, (sum, c) => sum + c.pointValue);

  bool get isEmpty => _cards.isEmpty;
  int get size => _cards.length;

  /// Read-only view of cards.
  List<Card> get cards => List.unmodifiable(_cards);

  /// Replace internal cards (for deserialization).
  set cards(List<Card> value) {
    _cards
      ..clear()
      ..addAll(value);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Card — the fundamental unit of the Fakka game (pure Dart, zero Flutter deps)
// ═══════════════════════════════════════════════════════════════════════════════
// Ported 1:1 from card.ts

/// The 10 ranks of the 40-card Italian deck.
const List<String> ranks = ['1', '2', '3', '4', '5', '6', '7', 'J', 'Q', 'K'];

/// The 4 suits of the 40-card Italian deck (Unicode symbols).
const List<String> suits = ['\u2660', '\u2663', '\u2665', '\u2666']; // ♠ ♣ ♥ ♦

/// Face-card ranks (J, Q, K) — worth 2 points each.
const Set<String> faceRanks = {'J', 'Q', 'K'};

/// A single Italian playing card.
///
/// Equality is rank-only for game matching (7♠ matches 7♣).
/// Use [exactMatch] when suit identity is needed (deck uniqueness).
class Card {
  final String rank;
  final String suit;

  const Card({required this.rank, required this.suit});

  /// Point value: face cards = 2, numerals 1-7 = 1.
  int get pointValue => faceRanks.contains(rank) ? 2 : 1;

  /// Rank-only equality for game matching.
  bool matches(Card other) => rank == other.rank;

  /// Exact identity comparison (rank AND suit).
  bool exactMatch(Card other) => rank == other.rank && suit == other.suit;

  /// Unique string key for Set/Map lookups needing suit-level distinction.
  String get key => '$rank|$suit';

  /// Human-readable representation, e.g. "7♠", "K♥".
  @override
  String toString() => '$rank$suit';

  @override
  bool operator ==(Object other) =>
      other is Card && rank == other.rank && suit == other.suit;

  @override
  int get hashCode => Object.hash(rank, suit);

  /// Serialize to JSON-compatible map.
  Map<String, dynamic> toJson() => {'rank': rank, 'suit': suit};

  /// Deserialize from JSON map.
  factory Card.fromJson(Map<String, dynamic> json) {
    return Card(rank: json['rank'] as String, suit: json['suit'] as String);
  }
}

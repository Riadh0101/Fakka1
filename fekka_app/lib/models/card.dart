/// Represents a single playing card in the Fekka deck.
///
/// The deck is a standard 52-card deck. Only ranks 1 (Ace) through 7
/// plus 10 (King), 11 (Queen), 12 (Jack) are used in Schkobba 40.
class GameCard {
  /// Numeric rank of the card (1-13, Ace=1, Jack=11, Queen=12, King=13).
  final int rank;

  /// Suit of the card: 'hearts', 'diamonds', 'clubs', 'spades'.
  final String suit;

  /// Point value for scoring in Schkobba 40.
  /// Aces = 1, Court cards = 0, Number cards = face value.
  final int pointValue;

  /// Whether this card is currently face-up (visible).
  final bool faceUp;

  const GameCard({
    required this.rank,
    required this.suit,
    required this.pointValue,
    this.faceUp = true,
  });

  /// Creates a [GameCard] from a JSON map received from the server.
  factory GameCard.fromJson(Map<String, dynamic> json) {
    return GameCard(
      rank: json['rank'] as int,
      suit: json['suit'] as String,
      pointValue: json['pointValue'] as int? ?? _computePointValue(json['rank'] as int),
      faceUp: json['faceUp'] as bool? ?? true,
    );
  }

  /// Converts this card to a JSON map for sending to the server.
  Map<String, dynamic> toJson() => {
    'rank': rank,
    'suit': suit,
    'pointValue': pointValue,
    'faceUp': faceUp,
  };

  /// Human-readable rank string (e.g., "A", "7", "K").
  String get rankString {
    switch (rank) {
      case 1: return 'A';
      case 11: return 'J';
      case 12: return 'Q';
      case 13: return 'K';
      default: return rank.toString();
    }
  }

  /// Unicode suit symbol.
  String get suitSymbol {
    switch (suit.toLowerCase()) {
      case 'hearts': return '♥';
      case 'diamonds': return '♦';
      case 'clubs': return '♣';
      case 'spades': return '♠';
      default: return '?';
    }
  }

  static int _computePointValue(int rank) {
    if (rank == 1) return 1; // Ace
    if (rank >= 11) return 0; // Court cards
    return rank; // 2-10
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GameCard && rank == other.rank && suit == other.suit;

  @override
  int get hashCode => rank.hashCode ^ suit.hashCode;

  @override
  String toString() => '$rankString$suitSymbol';
}

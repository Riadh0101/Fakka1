import 'card.dart';

/// Represents a player's state as received from the server,
/// used both in the lobby and during gameplay.
class PlayerInfo {
  final String playerId;
  final String name;
  final int seatIndex;
  final bool isConnected;
  final bool isEliminated;

  const PlayerInfo({
    required this.playerId,
    required this.name,
    required this.seatIndex,
    this.isConnected = true,
    this.isEliminated = false,
  });

  factory PlayerInfo.fromJson(Map<String, dynamic> json) {
    return PlayerInfo(
      playerId: json['playerId'] as String,
      name: json['name'] as String,
      seatIndex: json['seatIndex'] as int,
      isConnected: json['isConnected'] as bool? ?? true,
      isEliminated: json['isEliminated'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'playerId': playerId,
    'name': name,
    'seatIndex': seatIndex,
    'isConnected': isConnected,
    'isEliminated': isEliminated,
  };
}

/// Extended player info visible during gameplay (opponent view).
class PlayerGameInfo {
  final String playerId;
  final String name;
  final int seatIndex;
  final GameCard? stackTop;       // top card of their captured stack
  final int handCount;        // number of cards in hand
  final int score;            // current round score
  final int cumulativeScore;  // total across all rounds
  final bool isActive;        // whether it's this player's turn
  final bool isConnected;
  final bool isEliminated;

  const PlayerGameInfo({
    required this.playerId,
    required this.name,
    required this.seatIndex,
    this.stackTop,
    this.handCount = 0,
    this.score = 0,
    this.cumulativeScore = 0,
    this.isActive = false,
    this.isConnected = true,
    this.isEliminated = false,
  });

  factory PlayerGameInfo.fromJson(Map<String, dynamic> json) {
    return PlayerGameInfo(
      playerId: json['playerId'] as String,
      name: json['name'] as String,
      seatIndex: json['seatIndex'] as int,
      stackTop: json['stackTop'] != null
          ? GameCard.fromJson(json['stackTop'] as Map<String, dynamic>)
          : null,
      handCount: json['handCount'] as int? ?? 0,
      score: json['score'] as int? ?? 0,
      cumulativeScore: json['cumulativeScore'] as int? ?? 0,
      isActive: json['isActive'] as bool? ?? false,
      isConnected: json['isConnected'] as bool? ?? true,
      isEliminated: json['isEliminated'] as bool? ?? false,
    );
  }
}

/// Final ranking entry shown on the Game Over screen.
class Ranking {
  final String playerId;
  final String name;
  final int seatIndex;
  final int totalScore;
  final int rank;

  const Ranking({
    required this.playerId,
    required this.name,
    required this.seatIndex,
    required this.totalScore,
    required this.rank,
  });

  factory Ranking.fromJson(Map<String, dynamic> json) {
    return Ranking(
      playerId: json['playerId'] as String,
      name: json['name'] as String,
      seatIndex: json['seatIndex'] as int,
      totalScore: json['totalScore'] as int,
      rank: json['rank'] as int,
    );
  }
}

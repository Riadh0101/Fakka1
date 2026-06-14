import 'card.dart';
import 'player_state.dart';

/// Central game state model — the single source of truth for the UI.
///
/// This is managed by [GameNotifier] via Riverpod and updated
/// through socket events from the NestJS backend.
class GameState {
  final String? roomId;
  final String? playerId;
  final String? playerName;
  final int? seatIndex;
  final String roomStatus; // 'waiting' | 'in_progress' | 'finished'

  // ---- Lobby ----
  final List<PlayerInfo> lobbyPlayers;

  // ---- Gameplay ----
  final List<GameCard> myHand;
  final GameCard? poolTop;
  final int poolSize;
  final List<PlayerGameInfo> opponents;
  final int currentPlayerSeat;
  final bool isMyTurn;
  final Map<String, int> scores; // playerId → cumulative score
  final int roundNumber;

  // ---- Capture animation ----
  final String? capturingPlayerId;
  final List<GameCard>? capturedCards;

  // ---- Round end ----
  final Map<String, int>? roundScores;

  // ---- End ----
  final List<Ranking> finalRankings;
  final bool gameOver;

  // ---- Connection ----
  final bool isConnected;
  final bool isReconnecting;
  final String? errorMessage;

  const GameState({
    this.roomId,
    this.playerId,
    this.playerName,
    this.seatIndex,
    this.roomStatus = 'waiting',
    this.lobbyPlayers = const [],
    this.myHand = const [],
    this.poolTop,
    this.poolSize = 0,
    this.opponents = const [],
    this.currentPlayerSeat = -1,
    this.isMyTurn = false,
    this.scores = const {},
    this.roundNumber = 0,
    this.capturingPlayerId,
    this.capturedCards,
    this.roundScores,
    this.finalRankings = const [],
    this.gameOver = false,
    this.isConnected = true,
    this.isReconnecting = false,
    this.errorMessage,
  });

  /// Full copy with optional overrides.
  GameState copyWith({
    String? roomId,
    String? playerId,
    String? playerName,
    int? seatIndex,
    String? roomStatus,
    List<PlayerInfo>? lobbyPlayers,
    List<GameCard>? myHand,
    GameCard? poolTop,
    int? poolSize,
    List<PlayerGameInfo>? opponents,
    int? currentPlayerSeat,
    bool? isMyTurn,
    Map<String, int>? scores,
    int? roundNumber,
    String? capturingPlayerId,
    List<GameCard>? capturedCards,
    Map<String, int>? roundScores,
    List<Ranking>? finalRankings,
    bool? gameOver,
    bool? isConnected,
    bool? isReconnecting,
    String? errorMessage,
    bool clearCapturingPlayerId = false,
    bool clearCapturedCards = false,
    bool clearRoundScores = false,
    bool clearError = false,
  }) {
    return GameState(
      roomId: roomId ?? this.roomId,
      playerId: playerId ?? this.playerId,
      playerName: playerName ?? this.playerName,
      seatIndex: seatIndex ?? this.seatIndex,
      roomStatus: roomStatus ?? this.roomStatus,
      lobbyPlayers: lobbyPlayers ?? this.lobbyPlayers,
      myHand: myHand ?? this.myHand,
      poolTop: poolTop ?? this.poolTop,
      poolSize: poolSize ?? this.poolSize,
      opponents: opponents ?? this.opponents,
      currentPlayerSeat: currentPlayerSeat ?? this.currentPlayerSeat,
      isMyTurn: isMyTurn ?? this.isMyTurn,
      scores: scores ?? this.scores,
      roundNumber: roundNumber ?? this.roundNumber,
      capturingPlayerId:
          clearCapturingPlayerId ? null : (capturingPlayerId ?? this.capturingPlayerId),
      capturedCards:
          clearCapturedCards ? null : (capturedCards ?? this.capturedCards),
      roundScores:
          clearRoundScores ? null : (roundScores ?? this.roundScores),
      finalRankings: finalRankings ?? this.finalRankings,
      gameOver: gameOver ?? this.gameOver,
      isConnected: isConnected ?? this.isConnected,
      isReconnecting: isReconnecting ?? this.isReconnecting,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  /// Builds a [GameState] from the server's `state_sync` payload.
  factory GameState.fromServerSync(
    Map<String, dynamic> json, {
    required String playerId,
    required String playerName,
    int? seatIndex,
  }) {
    final playersJson = (json['players'] as List<dynamic>?)
            ?.map((p) => PlayerInfo.fromJson(p as Map<String, dynamic>))
            .toList() ??
        [];

    final myHandJson = (json['myHand'] as List<dynamic>?)
            ?.map((c) => GameCard.fromJson(c as Map<String, dynamic>))
            .toList() ??
        [];

    final opponentsJson = (json['opponents'] as List<dynamic>?)
            ?.map((o) => PlayerGameInfo.fromJson(o as Map<String, dynamic>))
            .toList() ??
        [];

    final scoresJson = (json['scores'] as Map<String, dynamic>?)
            ?.map((k, v) => MapEntry(k, v as int)) ??
        {};

    final poolJson = json['pool'];
    final poolTopCard = poolJson != null && poolJson['topCard'] != null
        ? GameCard.fromJson(poolJson['topCard'] as Map<String, dynamic>)
        : null;

    return GameState(
      roomId: json['roomId'] as String?,
      playerId: playerId,
      playerName: playerName,
      seatIndex: seatIndex ?? json['seatIndex'] as int?,
      roomStatus: json['roomStatus'] as String? ?? 'waiting',
      lobbyPlayers: playersJson,
      myHand: myHandJson,
      poolTop: poolTopCard,
      poolSize: poolJson?['size'] as int? ?? 0,
      opponents: opponentsJson,
      currentPlayerSeat: json['currentPlayerSeat'] as int? ?? -1,
      isMyTurn: json['isMyTurn'] as bool? ?? false,
      scores: scoresJson,
      roundNumber: json['roundNumber'] as int? ?? 0,
      gameOver: json['gameOver'] as bool? ?? false,
    );
  }
}

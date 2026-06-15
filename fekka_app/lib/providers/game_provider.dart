import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../config.dart';
import '../models/card.dart';
import '../models/game_state.dart';
import '../models/player_state.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';

/// The central Riverpod provider for game state.
///
/// All UI reads from `gameProvider` and writes through its methods.
final gameProvider = StateNotifierProvider<GameNotifier, GameState>((ref) {
  final api = ApiService();
  final socket = SocketService();
  return GameNotifier(api, socket);
});

class GameNotifier extends StateNotifier<GameState> {
  final ApiService _api;
  final SocketService _socket;

  StreamSubscription? _stateSyncSub;
  StreamSubscription? _stateUpdateSub;
  StreamSubscription? _captureSub;
  StreamSubscription? _roundEndSub;
  StreamSubscription? _playerEliminatedSub;
  StreamSubscription? _gameOverSub;
  StreamSubscription? _playerJoinedSub;
  StreamSubscription? _errorSub;
  StreamSubscription? _connectionSub;

  GameNotifier(this._api, this._socket) : super(const GameState()) {
    _bindSocketListeners();
  }

  void _bindSocketListeners() {
    _stateSyncSub = _socket.onStateSync.listen(_onStateSync);
    _stateUpdateSub = _socket.onStateUpdate.listen(_onStateUpdate);
    _captureSub = _socket.onCapture.listen(_onCaptureEvent);
    _roundEndSub = _socket.onRoundEnd.listen(_onRoundEnd);
    _playerEliminatedSub =
        _socket.onPlayerEliminated.listen(_onPlayerEliminated);
    _gameOverSub = _socket.onGameOver.listen(_onGameOver);
    _playerJoinedSub = _socket.onPlayerJoined.listen(_onPlayerJoined);
    _errorSub = _socket.onError.listen(_onSocketError);
    _connectionSub = _socket.onConnectionChange.listen(_onConnectionChange);
  }

  // ---- Public Actions ----

  /// Creates a new game room and connects via socket.
  Future<void> createGame(String playerName) async {
    state = state.copyWith(errorMessage: null, clearError: false);

    try {
      final result = await _api.createRoom(playerName);
      final roomId = result['roomId'] as String;
      final playerId = result['adminPlayerId'] as String;

      state = state.copyWith(
        roomId: roomId,
        playerId: playerId,
        playerName: playerName,
        seatIndex: 0,
        roomStatus: 'waiting',
      );

      await _socket.connect(
        serverUrl: AppConfig.socketUrl,
        roomId: roomId,
        playerId: playerId,
      );
    } on ApiException catch (e) {
      state = state.copyWith(errorMessage: e.message, clearError: false);
    } catch (e) {
      state = state.copyWith(errorMessage: 'Unexpected error: $e',
          clearError: false);
    }
  }

  /// Joins an existing game room.
  Future<void> joinGame(String roomId, String playerName) async {
    state = state.copyWith(errorMessage: null, clearError: false);

    try {
      final result = await _api.joinRoom(roomId, playerName);
      final playerId = result['playerId'] as String;
      final seatIndex = result['seatIndex'] as int? ?? 0;

      state = state.copyWith(
        roomId: roomId,
        playerId: playerId,
        playerName: playerName,
        seatIndex: seatIndex,
        roomStatus: result['roomStatus'] as String? ?? 'waiting',
      );

      await _socket.connect(
        serverUrl: AppConfig.socketUrl,
        roomId: roomId,
        playerId: playerId,
      );
    } on ApiException catch (e) {
      state = state.copyWith(errorMessage: e.message, clearError: false);
    } catch (e) {
      state = state.copyWith(errorMessage: 'Unexpected error: $e',
          clearError: false);
    }
  }

  /// Starts the game (admin only).
  Future<void> startGame() async {
    if (state.roomId == null || state.playerId == null) return;
    state = state.copyWith(errorMessage: null, clearError: false);

    try {
      await _api.startGame(state.roomId!, state.playerId!);
      // The server will emit state_sync with roomStatus='in_progress'
    } on ApiException catch (e) {
      state = state.copyWith(errorMessage: e.message, clearError: false);
    } catch (e) {
      state = state.copyWith(errorMessage: 'Unexpected error: $e',
          clearError: false);
    }
  }

  /// Emits a play_card event for the card at the given hand index.
  void playCard(int handIndex) {
    if (handIndex < 0 || handIndex >= state.myHand.length) return;
    _socket.emitPlayCard(state.myHand[handIndex]);
  }

  /// Attempts to rejoin a previously active session on app restart.
  Future<bool> tryRejoin() async {
    final reconnected = await _socket.tryReconnect();
    if (!reconnected) return false;
    state = state.copyWith(isReconnecting: true);
    return true;
  }

  /// Clears the current error message.
  void clearError() {
    state = state.copyWith(clearError: true);
  }

  // ---- Socket Event Handlers ----

  void _onStateSync(dynamic data) {
    if (data is! Map<String, dynamic>) return;

    final incoming = GameState.fromServerSync(
      data,
      playerId: state.playerId ?? const Uuid().v4(),
      playerName: state.playerName ?? 'Player',
      seatIndex: state.seatIndex,
    );

    state = incoming.copyWith(
      // Preserve local identifiers
      roomId: incoming.roomId ?? state.roomId,
      playerId: state.playerId,
      playerName: state.playerName,
      seatIndex: incoming.seatIndex ?? state.seatIndex,
      isReconnecting: false,
      isConnected: true,
      // Clear transient animation / round-end state on full sync
      clearError: true,
      clearRoundScores: true,
      clearCapturedCards: true,
      clearCapturingPlayerId: true,
    );
  }

  void _onStateUpdate(dynamic data) {
    if (data is! Map<String, dynamic>) return;

    final event = data['event'] as String? ?? '';

    switch (event) {
      case 'hand_update':
        final handJson = data['myHand'] as List<dynamic>?;
        if (handJson != null) {
          state = state.copyWith(
            myHand: handJson
                .map((c) => GameCard.fromJson(c as Map<String, dynamic>))
                .toList(),
          );
        }
        break;

      case 'turn_change':
        final currentSeat = data['currentPlayerSeat'] as int?;
        if (currentSeat != null) {
          state = state.copyWith(
            currentPlayerSeat: currentSeat,
            isMyTurn: currentSeat == state.seatIndex,
          );
        }
        break;

      case 'pool_update':
        final poolData = data['pool'] as Map<String, dynamic>?;
        if (poolData != null) {
          state = state.copyWith(
            poolSize: poolData['size'] as int? ?? state.poolSize,
            poolTop: poolData['topCard'] != null
                ? GameCard.fromJson(poolData['topCard'] as Map<String, dynamic>)
                : state.poolTop,
          );
        }
        break;

      case 'opponent_update':
        final opponentsJson = data['opponents'] as List<dynamic>?;
        if (opponentsJson != null) {
          state = state.copyWith(
            opponents: opponentsJson
                .map((o) => PlayerGameInfo.fromJson(o as Map<String, dynamic>))
                .toList(),
          );
        }
        break;

      case 'score_update':
        final scoresJson = data['scores'] as Map<String, dynamic>?;
        if (scoresJson != null) {
          state = state.copyWith(
            scores: scoresJson.map((k, v) => MapEntry(k, v as int)),
          );
        }
        break;

      default:
        break;
    }
  }

  void _onCaptureEvent(dynamic data) {
    if (data is! Map<String, dynamic>) return;
    final cardsJson = data['capturedCards'] as List<dynamic>?;
    state = state.copyWith(
      capturingPlayerId: data['capturingPlayerId'] as String?,
      capturedCards: cardsJson
          ?.map((c) => GameCard.fromJson(c as Map<String, dynamic>))
          .toList(),
    );
  }

  void _onRoundEnd(dynamic data) {
    if (data is! Map<String, dynamic>) return;
    final scoresJson = data['scores'] as Map<String, dynamic>?;
    state = state.copyWith(
      roundScores: scoresJson?.map((k, v) => MapEntry(k, v as int)),
    );
  }

  void _onPlayerEliminated(dynamic data) {
    if (data is! Map<String, dynamic>) return;
    // Server sends updated player states; we'll get them via state_update
    // This is a hook for toast/snackbar notifications
  }

  void _onGameOver(dynamic data) {
    if (data is! Map<String, dynamic>) return;
    final rankingsJson = data['rankings'] as List<dynamic>?;
    state = state.copyWith(
      gameOver: true,
      roomStatus: 'finished',
      finalRankings: rankingsJson
              ?.map((r) => Ranking.fromJson(r as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  void _onPlayerJoined(dynamic data) {
    if (data is! Map<String, dynamic>) return;
    final playersJson = data['players'] as List<dynamic>?;
    if (playersJson != null) {
      state = state.copyWith(
        lobbyPlayers: playersJson
            .map((p) => PlayerInfo.fromJson(p as Map<String, dynamic>))
            .toList(),
      );
    }
  }

  void _onSocketError(dynamic data) {
    String message;
    if (data is Map<String, dynamic>) {
      message = data['message'] as String? ?? 'Unknown socket error';
    } else if (data is String) {
      message = data;
    } else {
      message = 'Unknown socket error';
    }
    state = state.copyWith(errorMessage: message, clearError: false);
  }

  void _onConnectionChange(bool connected) {
    state = state.copyWith(
      isConnected: connected,
      isReconnecting: !connected && !_socket.isConnected,
    );
  }

  @override
  void dispose() {
    _stateSyncSub?.cancel();
    _stateUpdateSub?.cancel();
    _captureSub?.cancel();
    _roundEndSub?.cancel();
    _playerEliminatedSub?.cancel();
    _gameOverSub?.cancel();
    _playerJoinedSub?.cancel();
    _errorSub?.cancel();
    _connectionSub?.cancel();
    _api.dispose();
    _socket.dispose();
    super.dispose();
  }
}

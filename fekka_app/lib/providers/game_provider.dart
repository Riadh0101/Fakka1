import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../config.dart';
import '../engine/room_manager.dart';
import '../engine/state_adapter.dart';
import '../models/card.dart';
import '../models/game_state.dart';
import '../models/player_state.dart';
import '../server/fakka_server.dart';
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
  FakkaServer? _server;

  StreamSubscription? _stateSyncSub;
  StreamSubscription? _stateUpdateSub;
  StreamSubscription? _captureSub;
  StreamSubscription? _roundEndSub;
  StreamSubscription? _playerEliminatedSub;
  StreamSubscription? _gameOverSub;
  StreamSubscription? _playerJoinedSub;
  StreamSubscription? _playerLeftSub;
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
    _playerLeftSub = _socket.onPlayerLeft.listen(_onPlayerLeft);
    _errorSub = _socket.onError.listen(_onSocketError);
    _connectionSub = _socket.onConnectionChange.listen(_onConnectionChange);
  }

  // ---- Public Actions ----

  /// Creates a new game room and connects via socket.
  /// Uses the cloud server — no embedded server needed.
  Future<void> createGame(String playerName, {bool isHost = true}) async {
    state = state.copyWith(errorMessage: null, clearError: false);

    try {
      if (isHost) {
        AppConfig.isHost = true;
      }

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
        playerName: playerName,
      );
    } on ApiException catch (e) {
      state = state.copyWith(errorMessage: e.message, clearError: false);
    } catch (e) {
      state = state.copyWith(errorMessage: 'خطأ غير متوقع: $e',
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
        playerName: playerName,
      );
    } on ApiException catch (e) {
      state = state.copyWith(errorMessage: e.message, clearError: false);
    } catch (e) {
      state = state.copyWith(errorMessage: 'خطأ غير متوقع: $e',
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
      state = state.copyWith(errorMessage: 'خطأ غير متوقع: $e',
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
    final session = await _socket.tryReconnect();
    if (session == null) return false;
    state = state.copyWith(
      roomId: session['roomId'],
      playerId: session['playerId'],
      playerName: session['playerName'] ?? state.playerName,
      isReconnecting: true,
    );
    return true;
  }

  /// Clears the current error message.
  void clearError() {
    state = state.copyWith(clearError: true);
  }

  /// Leaves the current game and disconnects.
  void leaveGame() {
    _socket.emitLeaveRoom();
    // Short delay so the leave_room message is sent before socket closes
    Future.delayed(const Duration(milliseconds: 100), () {
      _socket.disconnect();
    });
    _server?.stop();
    _server = null;
    AppConfig.isHost = false;
    state = const GameState();
  }

  // ---- Socket Event Handlers ----

  void _onStateSync(dynamic data) {
    if (data is! Map<String, dynamic>) return;

    final incoming = StateAdapter.fromEngineStateSync(
      data,
      playerId: state.playerId ?? const Uuid().v4(),
      playerName: state.playerName ?? 'لاعب',
      seatIndex: state.seatIndex,
    );

    state = incoming.copyWith(
      roomId: incoming.roomId ?? state.roomId,
      playerId: state.playerId,
      playerName: state.playerName,
      seatIndex: incoming.seatIndex ?? state.seatIndex,
      isReconnecting: false,
      isConnected: true,
      clearError: true,
      clearRoundScores: true,
      clearCapturedCards: true,
      clearCapturingPlayerId: true,
    );
  }

  void _onStateUpdate(dynamic data) {
    if (data is! Map<String, dynamic>) return;

    final incoming = StateAdapter.fromEngineStateUpdate(
      data,
      playerId: state.playerId ?? '',
      playerName: state.playerName ?? 'لاعب',
      seatIndex: state.seatIndex,
    );

    state = state.copyWith(
      myHand: incoming.myHand,
      poolTop: incoming.poolTop,
      poolSize: incoming.poolSize,
      opponents: incoming.opponents,
      currentPlayerSeat: incoming.currentPlayerSeat,
      isMyTurn: incoming.isMyTurn,
      scores: incoming.scores,
      roundNumber: incoming.roundNumber,
      gameOver: incoming.gameOver,
      roomStatus: incoming.roomStatus != 'waiting' ? incoming.roomStatus : null,
    );
  }

  void _onCaptureEvent(dynamic data) {
    if (data is! Map<String, dynamic>) return;

    final parsed = StateAdapter.parseCaptureEvent(data);
    if (parsed == null) return;

    final cardsJson = parsed['capturedCards'] as List<dynamic>?;
    state = state.copyWith(
      capturingPlayerId: parsed['capturingPlayerId'] as String?,
      capturedCards: cardsJson
          ?.map((c) => GameCard.fromJson(c as Map<String, dynamic>))
          .toList(),
    );
  }

  void _onRoundEnd(dynamic data) {
    if (data is! Map<String, dynamic>) return;
    // Server sends scores as a list of player score maps.
    final scoresList = data['scores'] as List<dynamic>?;
    if (scoresList != null) {
      final scoresMap = <String, int>{};
      for (final s in scoresList) {
        final sm = s as Map<String, dynamic>;
        scoresMap[sm['playerId'] as String] = sm['cumulativeScore'] as int? ?? 0;
      }
      state = state.copyWith(roundScores: scoresMap);
    }
  }

  void _onPlayerEliminated(dynamic data) {
    if (data is! Map<String, dynamic>) return;
    // Server sends updated player states; we'll get them via state_update
    // This is a hook for toast/snackbar notifications
  }

  void _onGameOver(dynamic data) {
    if (data is! Map<String, dynamic>) return;
    final rankingsList = data['rankings'] as List<dynamic>?;
    state = state.copyWith(
      gameOver: true,
      roomStatus: 'finished',
      finalRankings: rankingsList
              ?.map((r) {
                final rm = r as Map<String, dynamic>;
                return Ranking(
                  playerId: rm['playerId'] as String? ?? '',
                  name: rm['playerName'] as String? ?? '',
                  seatIndex: 0,
                  totalScore: rm['score'] as int? ?? 0,
                  rank: rm['rank'] as int? ?? 99,
                );
              })
              .toList() ??
          [],
    );
  }

  void _onPlayerJoined(dynamic data) {
    if (data is! Map<String, dynamic>) return;
    // Handle both formats:
    // 1. Full list: { players: [{ playerId, name, seatIndex, isConnected }] }
    // 2. Single rejoin: { playerId, name, seatIndex, reconnected }
    final playersJson = data['players'] as List<dynamic>?;
    if (playersJson != null) {
      state = state.copyWith(
        lobbyPlayers: playersJson
            .map((p) => PlayerInfo.fromJson(p as Map<String, dynamic>))
            .toList(),
      );
    }
  }

  void _onPlayerLeft(dynamic data) {
    if (data is! Map<String, dynamic>) return;
    // { players: [...], newAdminId: '...' }
    final playersJson = data['players'] as List<dynamic>?;
    if (playersJson != null) {
      state = state.copyWith(
        lobbyPlayers: playersJson
            .map((p) => PlayerInfo.fromJson(p as Map<String, dynamic>))
            .toList(),
      );
    }
    // If admin changed and we are the new admin, update seatIndex to 0
    final newAdminId = data['newAdminId'] as String?;
    if (newAdminId != null && newAdminId == state.playerId) {
      state = state.copyWith(seatIndex: 0);
    }
  }

  void _onSocketError(dynamic data) {
    String message;
    if (data is Map<String, dynamic>) {
      message = data['message'] as String? ?? 'خطأ غير معروف في الاتصال';
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
    _playerLeftSub?.cancel();
    _errorSub?.cancel();
    _connectionSub?.cancel();
    _api.dispose();
    _socket.dispose();
    _server?.stop();
    AppConfig.isHost = false;
    super.dispose();
  }
}

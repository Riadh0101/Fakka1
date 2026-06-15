import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';
import '../models/card.dart';
import '../models/socket_event.dart';

/// Manages the Socket.IO connection to the NestJS backend.
///
/// Handles connect, disconnect, reconnection, and event routing.
/// Stores playerId and roomId in shared_preferences so the player
/// can rejoin on app restart.
class SocketService {
  io.Socket? _socket;
  String? _roomId;
  String? _playerId;

  // Internal callback registries
  final _onStateSyncController = StreamController<dynamic>.broadcast();
  final _onStateUpdateController = StreamController<dynamic>.broadcast();
  final _onCaptureController = StreamController<dynamic>.broadcast();
  final _onRoundEndController = StreamController<dynamic>.broadcast();
  final _onPlayerEliminatedController = StreamController<dynamic>.broadcast();
  final _onGameOverController = StreamController<dynamic>.broadcast();
  final _onPlayerJoinedController = StreamController<dynamic>.broadcast();
  final _onErrorController = StreamController<dynamic>.broadcast();
  final _onConnectionChangeController = StreamController<bool>.broadcast();

  Timer? _reconnectTimer;
  // ignore: unused_field
  bool _wasManuallyDisconnected = false;

  // ---- Public streams ----
  Stream<dynamic> get onStateSync => _onStateSyncController.stream;
  Stream<dynamic> get onStateUpdate => _onStateUpdateController.stream;
  Stream<dynamic> get onCapture => _onCaptureController.stream;
  Stream<dynamic> get onRoundEnd => _onRoundEndController.stream;
  Stream<dynamic> get onPlayerEliminated => _onPlayerEliminatedController.stream;
  Stream<dynamic> get onGameOver => _onGameOverController.stream;
  Stream<dynamic> get onPlayerJoined => _onPlayerJoinedController.stream;
  Stream<dynamic> get onError => _onErrorController.stream;
  Stream<bool> get onConnectionChange => _onConnectionChangeController.stream;

  bool get isConnected => _socket?.connected ?? false;

  // ---- Connect / Disconnect ----

  /// Opens a Socket.IO connection and joins the given room.
  Future<void> connect({
    required String serverUrl,
    required String roomId,
    required String playerId,
  }) async {
    _roomId = roomId;
    _playerId = playerId;
    _wasManuallyDisconnected = false;

    await _persistSession(roomId, playerId);

    _socket = io.io(
      '$serverUrl/game',
      io.OptionBuilder()
          .setTransports(['websocket'])
          .enableAutoConnect()
          .disableForceNew()
          .setQuery({'roomId': roomId, 'playerId': playerId})
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(5000)
          .setTimeout(10000)
          .build(),
    );

    _registerListeners();
    _socket!.connect();
  }

  /// Reconnects to a previously persisted session.
  Future<bool> tryReconnect() async {
    final session = await _loadSession();
    if (session == null) return false;

    final serverUrl = AppConfig.socketUrl;
    _roomId = session['roomId'];
    _playerId = session['playerId'];
    _wasManuallyDisconnected = false;

    _socket = io.io(
      '$serverUrl/game',
      io.OptionBuilder()
          .setTransports(['websocket'])
          .enableAutoConnect()
          .disableForceNew()
          .setQuery({'roomId': _roomId!, 'playerId': _playerId!})
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(5000)
          .build(),
    );

    _registerListeners();
    _socket!.connect();
    return true;
  }

  /// Gracefully disconnects and clears persisted session.
  void disconnect() {
    _wasManuallyDisconnected = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _clearSession();
  }

  // ---- Emitters ----

  /// Sends a play_card event with the selected card.
  void emitPlayCard(GameCard card) {
    _socket?.emit(SocketEvent.playCard, {
      'roomId': _roomId,
      'playerId': _playerId,
      'card': card.toJson(),
    });
  }

  /// Sends a rejoin event to restore session state.
  void emitRejoin() {
    _socket?.emit(SocketEvent.rejoin, {
      'roomId': _roomId,
      'playerId': _playerId,
    });
  }

  // ---- Internal ----

  void _registerListeners() {
    _socket?.onConnect((_) {
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      _onConnectionChangeController.add(true);
      // On fresh connect or reconnect, emit rejoin to get state sync
      if (_roomId != null && _playerId != null) {
        emitRejoin();
      }
    });

    _socket?.onDisconnect((_) {
      _onConnectionChangeController.add(false);
      _startReconnectTimeout();
    });

    _socket?.onConnectError((_) {
      _onConnectionChangeController.add(false);
    });

    _socket?.on(SocketEvent.stateSync, (data) {
      _onStateSyncController.add(data);
    });

    _socket?.on(SocketEvent.stateUpdate, (data) {
      _onStateUpdateController.add(data);
    });

    _socket?.on(SocketEvent.capture, (data) {
      _onCaptureController.add(data);
    });

    _socket?.on(SocketEvent.roundEnd, (data) {
      _onRoundEndController.add(data);
    });

    _socket?.on(SocketEvent.playerEliminated, (data) {
      _onPlayerEliminatedController.add(data);
    });

    _socket?.on(SocketEvent.gameOver, (data) {
      _onGameOverController.add(data);
    });

    _socket?.on(SocketEvent.playerJoined, (data) {
      _onPlayerJoinedController.add(data);
    });

    _socket?.on(SocketEvent.error, (data) {
      _onErrorController.add(data);
    });
  }

  void _startReconnectTimeout() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(
      Duration(seconds: AppConfig.reconnectTimeoutSeconds),
      () {
        if (!(_socket?.connected ?? false)) {
          _onErrorController.add({
            'type': 'connection_lost',
            'message': 'Connection lost. Please leave and rejoin.',
          });
        }
      },
    );
  }

  // ---- Persistence ----

  static const _prefsRoomIdKey = 'fekka_room_id';
  static const _prefsPlayerIdKey = 'fekka_player_id';

  Future<void> _persistSession(String roomId, String playerId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsRoomIdKey, roomId);
    await prefs.setString(_prefsPlayerIdKey, playerId);
  }

  Future<Map<String, String>?> _loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    final roomId = prefs.getString(_prefsRoomIdKey);
    final playerId = prefs.getString(_prefsPlayerIdKey);
    if (roomId == null || playerId == null) return null;
    return {'roomId': roomId, 'playerId': playerId};
  }

  Future<void> _clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsRoomIdKey);
    await prefs.remove(_prefsPlayerIdKey);
  }

  /// Clean up all controllers and timers.
  void dispose() {
    _reconnectTimer?.cancel();
    _onStateSyncController.close();
    _onStateUpdateController.close();
    _onCaptureController.close();
    _onRoundEndController.close();
    _onPlayerEliminatedController.close();
    _onGameOverController.close();
    _onPlayerJoinedController.close();
    _onErrorController.close();
    _onConnectionChangeController.close();
    _socket?.dispose();
  }
}

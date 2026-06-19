import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';
import '../engine/card_adapter.dart';
import '../models/card.dart';
import '../models/socket_event.dart';

/// Manages the raw WebSocket connection to the embedded Dart server.
///
/// Handles connect, disconnect, reconnection, and event routing.
/// Stores playerId and roomId in shared_preferences so the player
/// can rejoin on app restart.
class SocketService {
  WebSocket? _socket;
  String? _roomId;
  String? _playerId;
  bool _connected = false;

  // Internal callback registries
  final _onStateSyncController = StreamController<dynamic>.broadcast();
  final _onStateUpdateController = StreamController<dynamic>.broadcast();
  final _onCaptureController = StreamController<dynamic>.broadcast();
  final _onRoundEndController = StreamController<dynamic>.broadcast();
  final _onPlayerEliminatedController = StreamController<dynamic>.broadcast();
  final _onGameOverController = StreamController<dynamic>.broadcast();
  final _onPlayerJoinedController = StreamController<dynamic>.broadcast();
  final _onPlayerLeftController = StreamController<dynamic>.broadcast();
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
  Stream<dynamic> get onPlayerLeft => _onPlayerLeftController.stream;
  Stream<dynamic> get onError => _onErrorController.stream;
  Stream<bool> get onConnectionChange => _onConnectionChangeController.stream;

  bool get isConnected => _connected;

  // ---- Connect / Disconnect ----

  /// Opens a raw WebSocket connection and joins the given room.
  Future<void> connect({
    required String serverUrl,
    required String roomId,
    required String playerId,
    String? playerName,
  }) async {
    _roomId = roomId;
    _playerId = playerId;
    _wasManuallyDisconnected = false;

    await _persistSession(
        roomId, playerId, playerName: playerName);

    final wsUrl =
        '$serverUrl/game?roomId=$roomId&playerId=$playerId';

    try {
      _socket = await WebSocket.connect(wsUrl);
      _connected = true;
      _onConnectionChangeController.add(true);
      _reconnectTimer?.cancel();
      _reconnectTimer = null;

      // Emit rejoin to trigger state_sync from the server.
      if (_roomId != null && _playerId != null) {
        emitRejoin();
      }

      _startListening();
    } catch (e) {
      _connected = false;
      _onConnectionChangeController.add(false);
      _onErrorController.add({
        'type': 'connection_error',
        'message': 'فشل الاتصال: $e',
      });
    }
  }

  /// Reconnects to a previously persisted session.
  /// Returns the session map (roomId, playerId, playerName) on success,
  /// or null on failure.
  Future<Map<String, String>?> tryReconnect() async {
    final session = await _loadSession();
    if (session == null) return null;

    final serverUrl = AppConfig.socketUrl;
    _roomId = session['roomId'];
    _playerId = session['playerId'];
    _wasManuallyDisconnected = false;

    final wsUrl =
        '$serverUrl/game?roomId=${_roomId!}&playerId=${_playerId!}';

    try {
      _socket = await WebSocket.connect(wsUrl);
      _connected = true;
      _onConnectionChangeController.add(true);
      _reconnectTimer?.cancel();
      _reconnectTimer = null;

      emitRejoin();
      _startListening();
      return session;
    } catch (_) {
      _connected = false;
      return null;
    }
  }

  /// Gracefully disconnects and clears persisted session.
  void disconnect() {
    _wasManuallyDisconnected = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _connected = false;
    _socket?.close();
    _socket = null;
    _clearSession();
  }

  // ---- Emitters ----

  /// Sends a play_card event with the selected card (converted to engine format).
  void emitPlayCard(GameCard gc) {
    final ec = toEngineCard(gc);
    _socket?.add(jsonEncode({
      'event': 'play_card',
      'data': {
        'roomId': _roomId,
        'playerId': _playerId,
        'rank': ec.rank,
        'suit': ec.suit,
      },
    }));
  }

  /// Sends a rejoin event to restore session state.
  void emitRejoin() {
    _socket?.add(jsonEncode({
      'event': 'rejoin',
      'data': {
        'roomId': _roomId,
        'playerId': _playerId,
      },
    }));
  }

  /// Sends a leave_room event before disconnecting so the server
  /// removes the player and broadcasts to the lobby.
  void emitLeaveRoom() {
    if (_socket != null && _socket!.readyState == WebSocket.open) {
      _socket?.add(jsonEncode({
        'event': 'leave_room',
        'data': {
          'roomId': _roomId,
          'playerId': _playerId,
        },
      }));
    }
  }

  // ---- Internal ----

  /// Starts listening to the WebSocket stream and routes incoming
  /// JSON messages to the appropriate stream controllers.
  void _startListening() {
    _socket?.listen(
      (data) {
        final String text =
            data is String ? data : utf8.decode(data as List<int>);
        try {
          final message = jsonDecode(text) as Map<String, dynamic>;
          final event = message['event'] as String?;
          final payload = message['data'];
          _routeEvent(event, payload);
        } catch (_) {
          // Ignore malformed frames.
        }
      },
      onError: (_) {
        _connected = false;
        _onConnectionChangeController.add(false);
        _startReconnectTimeout();
      },
      onDone: () {
        _connected = false;
        _onConnectionChangeController.add(false);
        _startReconnectTimeout();
      },
      cancelOnError: false,
    );
  }

  /// Routes an incoming event to its matching stream controller.
  void _routeEvent(String? event, dynamic data) {
    if (event == null) return;
    switch (event) {
      case 'state_sync':
        _onStateSyncController.add(data);
        break;
      case 'state_update':
        _onStateUpdateController.add(data);
        break;
      case 'capture_event':
      case 'capture':
        _onCaptureController.add(data);
        break;
      case 'round_end':
        _onRoundEndController.add(data);
        break;
      case 'player_eliminated':
        _onPlayerEliminatedController.add(data);
        break;
      case 'game_over':
        _onGameOverController.add(data);
        break;
      case 'player_joined':
        _onPlayerJoinedController.add(data);
        break;
      case 'player_left':
        _onPlayerLeftController.add(data);
        break;
      case 'error':
        _onErrorController.add(data);
        break;
      case 'player_disconnected':
        // Handled via the connection state stream.
        break;
    }
  }

  void _startReconnectTimeout() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(
      Duration(seconds: AppConfig.reconnectTimeoutSeconds),
      () {
        if (!_connected) {
          _onErrorController.add({
            'type': 'connection_lost',
            'message': 'انقطع الاتصال. الرجاء المغادرة وإعادة الانضمام.',
          });
        }
      },
    );
  }

  // ---- Persistence ----

  static const _prefsRoomIdKey = 'fekka_room_id';
  static const _prefsPlayerIdKey = 'fekka_player_id';
  static const _prefsPlayerNameKey = 'fekka_player_name';

  Future<void> _persistSession(String roomId, String playerId,
      {String? playerName}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsRoomIdKey, roomId);
    await prefs.setString(_prefsPlayerIdKey, playerId);
    if (playerName != null) {
      await prefs.setString(_prefsPlayerNameKey, playerName);
    }
  }

  Future<Map<String, String>?> _loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    final roomId = prefs.getString(_prefsRoomIdKey);
    final playerId = prefs.getString(_prefsPlayerIdKey);
    if (roomId == null || playerId == null) return null;
    final playerName = prefs.getString(_prefsPlayerNameKey);
    return {
      'roomId': roomId,
      'playerId': playerId,
      if (playerName != null) 'playerName': playerName,
    };
  }

  Future<void> _clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsRoomIdKey);
    await prefs.remove(_prefsPlayerIdKey);
    await prefs.remove(_prefsPlayerNameKey);
  }

  /// Public wrapper to clear persisted session (e.g. after stale room detection).
  Future<void> clearSession() => _clearSession();

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
    _onPlayerLeftController.close();
    _onErrorController.close();
    _onConnectionChangeController.close();
    _socket?.close();
  }
}

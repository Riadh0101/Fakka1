// ═══════════════════════════════════════════════════════════════════════════════
// FakkaServer — embedded HTTP + WebSocket game server for the host phone
// ═══════════════════════════════════════════════════════════════════════════════
//
// Uses dart:io only — zero external packages. Runs inside the Flutter app on
// the host phone. Handles REST endpoints + WebSocket game communication.
//
// REST endpoints (on port 3000):
//   POST /games/create        Body: { "adminName": "..." }
//   POST /games/:roomId/join   Body: { "playerName": "..." }
//   POST /games/:roomId/start  Body: { "adminPlayerId": "..." }
//
// WebSocket on same port at /game?roomId=...&playerId=...

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../engine/card.dart';
import '../engine/game_engine.dart';
import '../engine/room_manager.dart';

class FakkaServer {
  final RoomManager _roomManager = RoomManager();
  HttpServer? _httpServer;
  final int port;

  /// Connected WebSocket clients mapped by "roomId:playerId".
  final Map<String, WebSocket> _clients = {};

  FakkaServer({this.port = 3000});

  /// The actual bound port. Useful when [port] was 0 and the OS picked one.
  int get actualPort => _httpServer?.port ?? port;

  RoomManager get roomManager => _roomManager;

  /// Start the HTTP + WebSocket server.
  Future<void> start() async {
    _httpServer = await HttpServer.bind(InternetAddress.anyIPv4, port);
    print('[FakkaServer] Listening on port $port');

    _httpServer!.listen(_handleRequest);
  }

  /// Stop the server.
  Future<void> stop() async {
    // Snapshot the clients to avoid concurrent modification if a delayed
    // cleanup task (e.g. from _handleGameOver) mutates _clients while we
    // are iterating.
    final clientsSnapshot = _clients.values.toList();
    _clients.clear();
    for (final ws in clientsSnapshot) {
      await ws.close();
    }
    await _httpServer?.close(force: true);
    _httpServer = null;
    print('[FakkaServer] Stopped');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Request Router
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      // CORS headers.
      request.response.headers
        ..set('Access-Control-Allow-Origin', '*')
        ..set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        ..set('Access-Control-Allow-Headers', 'Content-Type');

      if (request.method == 'OPTIONS') {
        request.response.statusCode = 204;
        await request.response.close();
        return;
      }

      final path = request.uri.path;
      final method = request.method;
      final segments = request.uri.pathSegments;

      // WebSocket upgrade on /game.
      if (path == '/game') {
        await _handleWebSocket(request);
        return;
      }

      // Read body for POST requests.
      Map<String, dynamic>? body;
      if (method == 'POST') {
        body = await _readJsonBody(request);
      }

      // Route: POST /games/create
      if (method == 'POST' && segments.length == 2 && segments[0] == 'games' && segments[1] == 'create') {
        final adminName = body?['adminName'] as String?;
        if (adminName == null || adminName.isEmpty) {
          _sendError(request.response, 400, 'اسم المسؤول مطلوب');
          return;
        }
        final result = _roomManager.createRoom(adminName);
        _sendJson(request.response, 200, {
          'roomId': result.roomId,
          'adminPlayerId': result.adminPlayerId,
          'inviteLink': result.inviteLink,
        });
        return;
      }

      // Route: POST /games/{roomId}/join
      if (method == 'POST' && segments.length == 3 && segments[0] == 'games' && segments[2] == 'join') {
        final roomId = segments[1];
        final playerName = body?['playerName'] as String?;
        if (playerName == null || playerName.isEmpty) {
          _sendError(request.response, 400, 'اسم اللاعب مطلوب');
          return;
        }
        try {
          final result = _roomManager.joinRoom(roomId, playerName);
          _sendJson(request.response, 200, {
            'playerId': result.playerId,
            'seatIndex': result.seatIndex,
            'roomStatus': 'waiting',
          });
        } on StateError catch (e) {
          _sendError(request.response, 400, e.message);
        }
        return;
      }

      // Route: POST /games/{roomId}/start
      if (method == 'POST' && segments.length == 3 && segments[0] == 'games' && segments[2] == 'start') {
        final roomId = segments[1];
        final adminPlayerId = body?['adminPlayerId'] as String?;
        if (adminPlayerId == null) {
          _sendError(request.response, 400, 'معرف المسؤول مطلوب');
          return;
        }
        final seed = body?['seed'] as int?;
        try {
          final state = _roomManager.startGame(roomId, adminPlayerId, seed: seed);
          final sanitized = _roomManager.engine.sanitizeForPlayer(state, adminPlayerId);
          _sendJson(request.response, 200, sanitized.toJson());
          // Broadcast init to all connected players.
          _broadcastState(roomId);
        } on StateError catch (e) {
          _sendError(request.response, 400, e.message);
        }
        return;
      }

      // Route: GET /games/{roomId}/status
      if (method == 'GET' && segments.length == 3 && segments[0] == 'games' && segments[2] == 'status') {
        final roomId = segments[1];
        try {
          final status = _roomManager.getRoomStatus(roomId);
          _sendJson(request.response, 200, {
            'status': status.status.name,
            'playerCount': status.playerCount,
          });
        } on StateError catch (e) {
          _sendError(request.response, 404, e.message);
        }
        return;
      }

      // 404.
      _sendError(request.response, 404, 'غير موجود: $method $path');
    } catch (e, st) {
      print('[FakkaServer] Unhandled error: $e\n$st');
      try {
        _sendError(request.response, 500, 'خطأ داخلي في الخادم');
      } catch (_) {}
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // WebSocket Handling
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _handleWebSocket(HttpRequest request) async {
    final roomId = request.uri.queryParameters['roomId'];
    final playerId = request.uri.queryParameters['playerId'];

    if (roomId == null || playerId == null) {
      request.response.statusCode = 400;
      await request.response.close();
      return;
    }

    if (!_roomManager.roomExists(roomId)) {
      request.response.statusCode = 404;
      await request.response.close();
      return;
    }

    final player = _roomManager.getPlayer(roomId, playerId);
    if (player == null) {
      request.response.statusCode = 403;
      await request.response.close();
      return;
    }

    final ws = await WebSocketTransformer.upgrade(request);
    final clientKey = '$roomId:$playerId';
    _clients[clientKey] = ws;

    _roomManager.setPlayerConnected(roomId, playerId, true);

    // Send lobby player list.
    _broadcastLobbyPlayers(roomId);

    // If game in progress, send state sync.
    final state = _roomManager.loadGameState(roomId);
    if (state != null) {
      final sanitized = _roomManager.engine.sanitizeForPlayer(state, playerId);
      ws.add(jsonEncode({
        'event': 'state_sync',
        'data': sanitized.toJson(),
      }));
    }

    // Listen for messages.
    ws.listen(
      (data) => _handleWsMessage(ws, roomId, playerId, data as String),
      onError: (e) => _handleWsDisconnect(roomId, playerId),
      onDone: () => _handleWsDisconnect(roomId, playerId),
      cancelOnError: true,
    );
  }

  void _handleWsMessage(
      WebSocket ws, String roomId, String playerId, String raw) {
    try {
      final msg = jsonDecode(raw) as Map<String, dynamic>;
      final event = msg['event'] as String?;

      switch (event) {
        case 'play_card':
          _handlePlayCard(roomId, playerId, msg['data'] as Map<String, dynamic>? ?? {});
          break;
        case 'rejoin':
          _handleRejoin(ws, roomId, playerId);
          break;
        case 'get_state':
          _handleGetState(ws, roomId, playerId);
          break;
        default:
          _sendWsError(ws, 'حدث غير معروف: $event');
      }
    } catch (e) {
      _sendWsError(ws, 'صيغة رسالة غير صالحة: $e');
    }
  }

  // ── Game Event Handlers ──────────────────────────────────────────────────

  void _handlePlayCard(
      String roomId, String playerId, Map<String, dynamic> data) {
    try {
      final rank = data['rank'] as String?;
      final suit = data['suit'] as String?;

      if (rank == null || suit == null) {
        _sendWsError(_clients['$roomId:$playerId']!, 'بيانات الورقة غير صالحة');
        return;
      }

      final state = _roomManager.loadGameState(roomId);
      if (state == null) return;
      if (state.gameOver) return;

      final card = Card(rank: rank, suit: suit);
      final result = _roomManager.engine.processTurn(state, playerId, card);

      // Broadcast capture event.
      _broadcastToRoom(roomId, 'capture_event', {
        'poolCaptured':
            result.poolCaptured.map((c) => c.toJson()).toList(),
        'stolenFrom': result.stolenFrom.map((s) => s.toJson()).toList(),
        'activePlayerId': playerId,
        'action': result.action,
        'playedCard': result.playedCard.toJson(),
      });

      _roomManager.saveGameState(roomId, result.newState);

      // Check round end.
      if (result.roundEnded) {
        final roundResult =
            _roomManager.engine.processRoundEnd(result.newState);

        _broadcastToRoom(roomId, 'round_end', {
          'scores': roundResult.newState.players.map((p) => {
                'playerId': p.id,
                'name': p.name,
                'cumulativeScore': p.cumulativeScore,
                'rankEarned': p.rankEarned,
                'eliminated': p.eliminated,
              }).toList(),
        });

        for (final elimId in roundResult.eliminatedPlayerIds) {
          final elimPlayer = roundResult.newState.players
              .firstWhere((p) => p.id == elimId);
          _broadcastToRoom(roomId, 'player_eliminated', {
            'playerId': elimId,
            'name': elimPlayer.name,
            'rank': elimPlayer.rankEarned,
            'remainingPlayers':
                roundResult.newState.players.where((p) => !p.eliminated).length,
          });
        }

        _roomManager.saveGameState(roomId, roundResult.newState);

        if (roundResult.newState.gameOver) {
          _handleGameOver(roomId, roundResult.newState);
        } else {
          final nextRound =
              _roomManager.engine.setupRound(roundResult.newState);
          _roomManager.saveGameState(roomId, nextRound);

          if (nextRound.gameOver) {
            _handleGameOver(roomId, nextRound);
          }
        }
      }

      // Broadcast sanitized state to each player.
      _broadcastState(roomId);
    } catch (e) {
      print('[FakkaServer] play_card error: $e');
      _sendWsError(_clients['$roomId:$playerId']!, '$e');
    }
  }

  void _handleRejoin(WebSocket ws, String roomId, String playerId) {
    // Validate room and player membership.
    if (!_roomManager.roomExists(roomId)) {
      _sendWsError(ws, 'الغرفة غير موجودة');
      return;
    }
    final player = _roomManager.getPlayer(roomId, playerId);
    if (player == null) {
      _sendWsError(ws, 'اللاعب غير موجود في هذه الغرفة');
      return;
    }

    _roomManager.setPlayerConnected(roomId, playerId, true);

    final state = _roomManager.loadGameState(roomId);
    if (state != null) {
      final sanitized = _roomManager.engine.sanitizeForPlayer(state, playerId);
      ws.add(jsonEncode({
        'event': 'state_sync',
        'data': sanitized.toJson(),
      }));
    }

    _broadcastToRoom(roomId, 'player_joined', {
      'playerId': playerId,
      'name': player.name,
      'seatIndex': player.seatIndex,
      'reconnected': true,
    });
  }

  void _handleGetState(WebSocket ws, String roomId, String playerId) {
    final state = _roomManager.loadGameState(roomId);
    if (state != null) {
      final sanitized = _roomManager.engine.sanitizeForPlayer(state, playerId);
      ws.add(jsonEncode({
        'event': 'state_sync',
        'data': sanitized.toJson(),
      }));
    }
  }

  void _handleGameOver(String roomId, GameState state) {
    final rankings = [...state.players]
      ..sort((a, b) => (a.rankEarned ?? 99) - (b.rankEarned ?? 99));

    _broadcastToRoom(roomId, 'game_over', {
      'rankings': rankings.map((p) => {
            'playerId': p.id,
            'playerName': p.name,
            'rank': p.rankEarned ?? 99,
            'score': p.cumulativeScore,
          }).toList(),
      'totalRounds': state.roundCount,
    });

    // Clean up after delay.
    Future.delayed(const Duration(seconds: 30), () {
      for (final key in _clients.keys.toList()) {
        if (key.startsWith('$roomId:')) {
          _clients.remove(key);
        }
      }
      _roomManager.deleteRoom(roomId);
    });
  }

  void _handleWsDisconnect(String roomId, String playerId) {
    final clientKey = '$roomId:$playerId';
    _clients.remove(clientKey);
    _roomManager.setPlayerConnected(roomId, playerId, false);

    _broadcastToRoom(roomId, 'player_disconnected', {
      'playerId': playerId,
      'message': 'انقطع اتصال اللاعب',
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Broadcasting Helpers
  // ═══════════════════════════════════════════════════════════════════════════

  void _broadcastToRoom(String roomId, String event, dynamic data) {
    final message = jsonEncode({'event': event, 'data': data});
    // Iterate a snapshot to avoid ConcurrentModificationError.
    for (final key in _clients.keys.toList()) {
      if (key.startsWith('$roomId:')) {
        try {
          _clients[key]?.add(message);
        } catch (_) {}
      }
    }
  }

  void _broadcastState(String roomId) {
    final state = _roomManager.loadGameState(roomId);
    if (state == null) return;

    // Iterate a snapshot to avoid ConcurrentModificationError.
    for (final key in _clients.keys.toList()) {
      if (!key.startsWith('$roomId:')) continue;
      final playerId = key.split(':')[1];
      final ws = _clients[key];
      if (ws == null) continue;
      try {
        final sanitized =
            _roomManager.engine.sanitizeForPlayer(state, playerId);
        ws.add(jsonEncode({
          'event': 'state_update',
          'data': sanitized.toJson(),
        }));
      } catch (_) {}
    }
  }

  void _broadcastLobbyPlayers(String roomId) {
    final players = _roomManager.getLobbyPlayers(roomId);
    _broadcastToRoom(roomId, 'player_joined', {'players': players});
  }

  void _sendWsError(WebSocket? ws, String message) {
    if (ws == null) return;
    try {
      ws.add(jsonEncode({
        'event': 'error',
        'data': {'message': message, 'code': 'INTERNAL'},
      }));
    } catch (_) {}
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HTTP Helpers
  // ═══════════════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>?> _readJsonBody(HttpRequest request) async {
    try {
      final raw = await utf8.decodeStream(request);
      if (raw.isEmpty) return null;
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  void _sendJson(HttpResponse response, int status, dynamic data) {
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(data));
    response.close();
  }

  void _sendError(HttpResponse response, int status, String message) {
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    // Match client's _extractError which reads body['message'].
    response.write(jsonEncode({'message': message}));
    response.close();
  }
}

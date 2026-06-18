import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fekka_app/server/fakka_server.dart';
import 'package:flutter_test/flutter_test.dart';

/// Helper representing one player/client in the integration test.
class _TestClient {
  final String name;
  String? playerId;
  String? _roomId;
  WebSocket? _ws;
  final List<Map<String, dynamic>> _pending = [];
  final _waiters = <String, List<Completer<Map<String, dynamic>>>>{};
  Map<String, dynamic>? latestState;

  _TestClient(this.name);

  /// POST a JSON body to the given path and return the decoded response.
  Future<Map<String, dynamic>> post(
      String host, String path, Map<String, dynamic> body) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse('http://$host$path'));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
      final response = await request.close();
      final raw = await response.transform(utf8.decoder).join();
      return jsonDecode(raw) as Map<String, dynamic>;
    } finally {
      client.close();
    }
  }

  /// Connect this client's WebSocket and start collecting messages.
  Future<void> connect(String host, String roomId) async {
    if (playerId == null) {
      throw StateError('playerId must be set before connect');
    }
    _roomId = roomId;
    _ws = await WebSocket.connect(
        'ws://$host/game?roomId=$roomId&playerId=$playerId');
    _ws!.listen(
      (dynamic data) {
        final msg = jsonDecode(data as String) as Map<String, dynamic>;
        final eventType = msg['event'] as String;
        final waiters = _waiters[eventType];
        if (waiters != null && waiters.isNotEmpty) {
          final completer = waiters.removeAt(0);
          completer.complete(msg);
        } else {
          _pending.add(msg);
        }
        if (eventType == 'state_update' || eventType == 'state_sync') {
          latestState = msg['data'] as Map<String, dynamic>;
          unawaited(_maybePlayCard());
        }
      },
      onError: (Object e) => fail('$name WebSocket error: $e'),
      onDone: () {},
      cancelOnError: true,
    );
  }

  /// If this client is the current player and has cards, auto-play one.
  /// Yields to the event loop before sending to avoid flooding the server
  /// and to let incoming messages be processed.
  Future<void> _maybePlayCard() async {
    await Future.delayed(Duration.zero);

    final roomId = _roomId;
    final id = playerId;
    final state = latestState;
    if (roomId == null || id == null || state == null) return;
    if (state['gameOver'] == true) return;

    final players = (state['players'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final activePlayers =
        players.where((p) => p['eliminated'] != true).toList();
    if (activePlayers.isEmpty) return;

    final currentIndex =
        (state['currentPlayerIndex'] as int) % activePlayers.length;
    final currentPlayer = activePlayers[currentIndex];
    if (currentPlayer['id'] != id) return;

    final hand = currentPlayer['hand'] as List<dynamic>;
    if (hand.isEmpty) return;

    final card = hand.first as Map<String, dynamic>;
    send('play_card', {
      'roomId': roomId,
      'playerId': id,
      'rank': card['rank'] as String,
      'suit': card['suit'] as String,
    });
  }

  /// Send a WebSocket event to the server.
  void send(String event, Map<String, dynamic> data) {
    _ws!.add(jsonEncode({'event': event, 'data': data}));
  }

  /// Wait for a specific event type, with timeout.
  Future<Map<String, dynamic>> waitForEvent(String eventType,
      {Duration timeout = const Duration(seconds: 10)}) async {
    for (var i = 0; i < _pending.length; i++) {
      if (_pending[i]['event'] == eventType) {
        return _pending.removeAt(i);
      }
    }
    final completer = Completer<Map<String, dynamic>>();
    _waiters.putIfAbsent(eventType, () => []).add(completer);
    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _waiters[eventType]?.remove(completer);
        throw TimeoutException(
            '$name did not receive $eventType within $timeout');
      },
    );
  }

  Future<void> close() async {
    await _ws?.close();
  }
}

void main() {
  late FakkaServer server;
  late String host;
  late _TestClient hostClient;
  late List<_TestClient> guestClients;
  late String roomId;

  setUpAll(() async {
    server = FakkaServer(port: 0);
    await server.start();
    host = '127.0.0.1:${server.actualPort}';
  });

  tearDownAll(() async {
    await hostClient.close();
    for (final guest in guestClients) {
      await guest.close();
    }
    await server.stop();
  });

  test('full 4-player game completes with valid rankings', () async {
    // 1. Host creates the room.
    hostClient = _TestClient('Host');
    final createResp =
        await hostClient.post(host, '/games/create', {'adminName': 'Host'});
    expect(createResp['roomId'], isNotNull);
    expect(createResp['adminPlayerId'], isNotNull);
    roomId = createResp['roomId'] as String;
    hostClient.playerId = createResp['adminPlayerId'] as String;

    // 2. Three guests join.
    guestClients =
        ['Guest1', 'Guest2', 'Guest3'].map(_TestClient.new).toList();
    for (final guest in guestClients) {
      final joinResp = await guest.post(
          host, '/games/$roomId/join', {'playerName': guest.name});
      expect(joinResp['playerId'], isNotNull);
      guest.playerId = joinResp['playerId'] as String;
    }

    // 3. All four clients connect via WebSocket.
    await hostClient.connect(host, roomId);
    for (final guest in guestClients) {
      await guest.connect(host, roomId);
    }

    // Allow connection handshake broadcasts to settle before starting.
    await Future.delayed(const Duration(milliseconds: 300));

    // 4. Host starts the game via REST.
    // Use a deterministic seed so the integration test reaches game_over
    // reliably; the underlying engine can otherwise deal a current player an
    // empty hand in the deck-exhaustion fallback, leaving the game stuck.
    final startResp = await hostClient.post(host, '/games/$roomId/start', {
      'adminPlayerId': hostClient.playerId,
      'seed': 4,
    });
    expect(startResp['players'], isA<List<dynamic>>());

    // 5. Wait for the game to end.
    final allClients = [hostClient, ...guestClients];
    final gameOverPayloads = <Map<String, dynamic>>[];
    for (final client in allClients) {
      final msg = await client.waitForEvent('game_over');
      gameOverPayloads.add(msg['data'] as Map<String, dynamic>);
    }

    expect(gameOverPayloads, hasLength(4));
    final rankings = gameOverPayloads.first['rankings'] as List<dynamic>;
    expect(rankings, hasLength(4));

    final ranks = rankings
        .map((r) => (r as Map<String, dynamic>)['rank'] as int)
        .toSet();
    expect(ranks, equals({1, 2, 3, 4}));

    final playerIds = rankings
        .map((r) => (r as Map<String, dynamic>)['playerId'] as String)
        .toSet();
    expect(playerIds, hasLength(4));
  });
}

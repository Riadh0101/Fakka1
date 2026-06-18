import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fekka_app/server/fakka_server.dart';
import 'package:flutter_test/flutter_test.dart';

/// Helper representing one player/client in the integration test.
class _TestClient {
  final String name;
  String? playerId;
  WebSocket? _ws;
  StreamSubscription<dynamic>? _wsSubscription;
  final List<Map<String, dynamic>> _pending = [];
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  Map<String, dynamic>? latestState;
  bool gameOverReceived = false;
  Map<String, dynamic>? gameOverPayload;

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
    if (playerId == null) throw StateError('playerId must be set before connect');
    _ws = await WebSocket.connect(
        'ws://$host/game?roomId=$roomId&playerId=$playerId');
    _wsSubscription = _ws!.listen(
      (dynamic data) {
        final msg = jsonDecode(data as String) as Map<String, dynamic>;
        if (_messageController.isClosed) return;
        _pending.add(msg);
        _messageController.add(msg);
        if (msg['event'] == 'state_update' || msg['event'] == 'state_sync') {
          latestState = msg['data'] as Map<String, dynamic>;
        } else if (msg['event'] == 'game_over') {
          gameOverReceived = true;
          gameOverPayload ??= msg['data'] as Map<String, dynamic>;
        }
      },
      onError: (Object e) => fail('$name WebSocket error: $e'),
      onDone: () {},
      cancelOnError: true,
    );
  }

  /// Send a WebSocket event to the server.
  void send(String event, Map<String, dynamic> data) {
    _ws!.add(jsonEncode({'event': event, 'data': data}));
  }

  /// Wait for a specific event type, with timeout.
  Future<Map<String, dynamic>> waitForEvent(String eventType,
      {Duration timeout = const Duration(seconds: 30)}) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      for (var i = 0; i < _pending.length; i++) {
        if (_pending[i]['event'] == eventType) {
          return _pending.removeAt(i);
        }
      }
      await Future.delayed(const Duration(milliseconds: 50));
    }
    throw TimeoutException('$name did not receive $eventType within $timeout');
  }

  /// Wait for any of the given event types, returning the first one received.
  Future<Map<String, dynamic>> waitForAnyEvent(List<String> eventTypes,
      {Duration timeout = const Duration(seconds: 30)}) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      for (var i = 0; i < _pending.length; i++) {
        if (eventTypes.contains(_pending[i]['event'])) {
          return _pending.removeAt(i);
        }
      }
      await Future.delayed(const Duration(milliseconds: 50));
    }
    throw TimeoutException(
        '$name did not receive any of $eventTypes within $timeout');
  }

  Future<void> close() async {
    // Cancel the subscription first so no late messages arrive after we
    // close the stream controller.
    await _wsSubscription?.cancel();
    _wsSubscription = null;
    await _ws?.close();
    _ws = null;
    if (!_messageController.isClosed) {
      await _messageController.close();
    }
  }
}

void main() {
  late FakkaServer server;
  late String host;
  late _TestClient hostClient;
  var hostClientInitialized = false;
  late List<_TestClient> guestClients;
  late String roomId;

  setUpAll(() async {
    server = FakkaServer(port: 0);
    await server.start();
    host = '127.0.0.1:${server.actualPort}';
  });

  tearDownAll(() async {
    if (hostClientInitialized) {
      await hostClient.close();
      for (final guest in guestClients) {
        await guest.close();
      }
    }
    await server.stop();
  });

  test(
    'full 4-player game completes with valid rankings',
    () async {
    // 1. Host creates the room.
    hostClient = _TestClient('Host');
    hostClientInitialized = true;
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

    // 4. Host starts the game via REST.
    final startResp = await hostClient.post(
        host, '/games/$roomId/start', {
      'adminPlayerId': hostClient.playerId,
      'seed': 42,
    });
    expect(startResp['players'], isA<List<dynamic>>());

    // 5. Wait for the first state update on every client.
    final allClients = [hostClient, ...guestClients];
    for (final client in allClients) {
      await client.waitForEvent('state_update');
    }

    // 6. Play cards until the game is over.
    // We drive the loop from the host's state only; other clients still
    // receive broadcasts, but waiting for all of them on every play is flaky.
    var plays = 0;
    const maxPlays = 500;
    while (plays < maxPlays) {
      if (hostClient.latestState?['gameOver'] == true ||
          hostClient.gameOverReceived) {
        break;
      }

      final players = (hostClient.latestState!['players'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final activePlayers =
          players.where((p) => p['eliminated'] != true).toList();
      final currentIndex =
          (hostClient.latestState!['currentPlayerIndex'] as int) %
              activePlayers.length;
      final currentPlayer = activePlayers[currentIndex];
      final currentId = currentPlayer['id'] as String;

      final currentClient =
          allClients.firstWhere((c) => c.playerId == currentId);
      final currentState = currentClient.latestState!;
      final currentHand = (currentState['players'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .firstWhere((p) => p['id'] == currentId)['hand'] as List<dynamic>;

      if (currentHand.isEmpty) {
        // Round transition in progress; wait for the host's next state update
        // or game_over when the deck is exhausted and the game ends.
        final msg = await hostClient.waitForAnyEvent(['state_update', 'game_over']);
        if (msg['event'] == 'state_update') {
          hostClient.latestState = msg['data'] as Map<String, dynamic>;
        }
        continue;
      }

      final card = currentHand.first as Map<String, dynamic>;
      currentClient.send('play_card', {
        'roomId': roomId,
        'playerId': currentId,
        'rank': card['rank'] as String,
        'suit': card['suit'] as String,
      });

      // Wait for every client to receive either a state_update or game_over.
      // game_over can arrive before the final state_update if this play ended
      // the game, so handle it explicitly.
      for (final client in allClients) {
        final msg = await client.waitForAnyEvent(['state_update', 'game_over']);
        if (msg['event'] == 'state_update') {
          client.latestState = msg['data'] as Map<String, dynamic>;
        }
      }

      plays++;
    }

    expect(plays, lessThan(maxPlays),
        reason: 'Game did not end within $maxPlays plays');
    expect(
        hostClient.latestState?['gameOver'] == true ||
            hostClient.gameOverReceived,
        isTrue);

    // 7. Collect game_over payloads from all clients and validate rankings.
    final gameOverPayloads = <Map<String, dynamic>>[];
    for (final client in allClients) {
      if (client.gameOverPayload != null) {
        gameOverPayloads.add(client.gameOverPayload!);
      } else {
        final msg = await client.waitForEvent('game_over');
        gameOverPayloads.add(msg['data'] as Map<String, dynamic>);
      }
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
  }, timeout: const Timeout(Duration(seconds: 120)));
}

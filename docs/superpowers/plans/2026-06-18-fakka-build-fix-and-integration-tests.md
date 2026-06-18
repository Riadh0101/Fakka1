# Fakka — Build Fix + 4-Player Server Integration Tests

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the corrupted `build_info.dart` file so the Flutter app builds, then add an automated integration test that proves the embedded Fakka server can run a complete 4-player game from create through game-over.

**Architecture:** Make two small, independent changes: (1) regenerate `lib/build_info.dart` with ASCII-only content and patch `build_apk.ps1` to emit UTF-8, and (2) add a `test/server/fakka_server_integration_test.dart` that spawns `FakkaServer` on an OS-assigned port, drives four raw `WebSocket` clients through the REST + WS protocol, and asserts invariants at each phase.

**Tech Stack:** Flutter 3.x, Dart 3.x, `dart:io` (`HttpClient`, `WebSocket`, `HttpServer`), `flutter_test`.

## Global Constraints

- Do not change core game rules, scoring, or engine behavior.
- All new files live under `fekka_app/`; do not touch `fekka_server` or `fekka_cli`.
- Integration test must run with `flutter test test/server/fakka_server_integration_test.dart` and require no emulator or physical devices.
- Every code change must keep `flutter analyze` error-free.
- `build_apk.ps1` must continue auto-incrementing `BuildInfo.number` and cycling `BuildInfo.colors`.

---

### Task 1: Fix `build_info.dart` encoding and harden `build_apk.ps1`

**Files:**
- Modify: `fekka_app/lib/build_info.dart`
- Modify: `fekka_app/build_apk.ps1`
- Test: `fekka_app/` (run `flutter analyze`)

**Interfaces:**
- Consumes: `home_screen.dart` expects `BuildInfo.number` (`int`) and `BuildInfo.colors` (`List<int>`).
- Produces: `BuildInfo.number` and `BuildInfo.colors` remain unchanged in type and usage.

- [ ] **Step 1: Regenerate `lib/build_info.dart` with ASCII-only content**

Replace the entire contents of `fekka_app/lib/build_info.dart` with:

```dart
/// Auto-generated build info - do not edit manually.
class BuildInfo {
  static const int number = 1;
  static const List<int> colors = [0xFF2196F3, 0xFFE94560, 0xFFFFC107]; // blue, red, yellow
}
```

- [ ] **Step 2: Patch `build_apk.ps1` to prevent re-corruption**

In `fekka_app/build_apk.ps1`, change the generated header em dash to an ASCII hyphen and force UTF-8 output.

Old block (lines 23-29):

```powershell
# Write updated build info
@"
/// Auto-generated build info — do not edit manually.
class BuildInfo {
  static const int number = $v;
  static const List<int> colors = [0xFF2196F3, 0xFFE94560, 0xFFFFC107]; // blue, red, yellow
}
"@ | Set-Content $buildFile -NoNewline
```

New block:

```powershell
# Write updated build info
@"
/// Auto-generated build info - do not edit manually.
class BuildInfo {
  static const int number = $v;
  static const List<int> colors = [0xFF2196F3, 0xFFE94560, 0xFFFFC107]; // blue, red, yellow
}
"@ | Set-Content $buildFile -NoNewline -Encoding UTF8
```

- [ ] **Step 3: Verify the analyzer passes**

Run:

```bash
flutter analyze
```

Expected: zero errors (warnings/info are acceptable).

- [ ] **Step 4: Verify the build script still works**

Run:

```powershell
powershell -File fekka_app/build_apk.ps1
```

Expected: script completes, `fekka_app/lib/build_info.dart` is regenerated with `number = 2` and valid UTF-8 content.

- [ ] **Step 5: Commit**

```bash
git add fekka_app/lib/build_info.dart fekka_app/build_apk.ps1
git commit -m "fix: ASCII-only build_info.dart and UTF-8 PowerShell output"
```

---

### Task 2: Expose the actual bound port on `FakkaServer`

**Files:**
- Modify: `fekka_app/lib/server/fakka_server.dart`
- Test: `fekka_app/test/server/fakka_server_integration_test.dart` (Task 3)

**Interfaces:**
- Consumes: `HttpServer.port` after `HttpServer.bind(InternetAddress.anyIPv4, port)`.
- Produces: `int get actualPort` on `FakkaServer` returning the real bound port (falls back to requested `port` if not bound).

- [ ] **Step 1: Add `actualPort` getter**

In `fekka_app/lib/server/fakka_server.dart`, add the following getter inside the `FakkaServer` class after the existing `port` field declaration (around line 32):

```dart
  /// The actual bound port. Useful when [port] was 0 and the OS picked one.
  int get actualPort => _httpServer?.port ?? port;
```

- [ ] **Step 2: Verify the getter compiles**

Run:

```bash
flutter analyze
```

Expected: zero errors.

- [ ] **Step 3: Commit**

```bash
git add fekka_app/lib/server/fakka_server.dart
git commit -m "feat: expose actual bound port on FakkaServer"
```

---

### Task 3: Write the 4-player server integration test

**Files:**
- Create: `fekka_app/test/server/fakka_server_integration_test.dart`
- Test: `fekka_app/test/server/fakka_server_integration_test.dart`

**Interfaces:**
- Consumes:
  - `FakkaServer({port: 0})`, `start()`, `stop()`, `actualPort`.
  - REST endpoints `POST /games/create`, `POST /games/:roomId/join`, `POST /games/:roomId/start`.
  - WebSocket endpoint `/game?roomId=...&playerId=...`.
  - WS events: `state_update`, `state_sync`, `capture_event`, `round_end`, `player_eliminated`, `game_over`.
  - WS client events: `play_card`, `get_state`.
- Produces: A passing test that verifies a full game completes with unique rankings.

- [ ] **Step 1: Create the test directory and file**

Create `fekka_app/test/server/fakka_server_integration_test.dart` with the following content:

```dart
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
  final List<Map<String, dynamic>> _pending = [];
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
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
    if (playerId == null) throw StateError('playerId must be set before connect');
    _ws = await WebSocket.connect(
        'ws://$host/game?roomId=$roomId&playerId=$playerId');
    _ws!.listen(
      (dynamic data) {
        final msg = jsonDecode(data as String) as Map<String, dynamic>;
        _pending.add(msg);
        _messageController.add(msg);
        if (msg['event'] == 'state_update' || msg['event'] == 'state_sync') {
          latestState = msg['data'] as Map<String, dynamic>;
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
      {Duration timeout = const Duration(seconds: 10)}) async {
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

  Future<void> close() async {
    await _ws?.close();
    await _messageController.close();
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

    // 4. Host starts the game via REST.
    final startResp = await hostClient.post(
        host, '/games/$roomId/start', {'adminPlayerId': hostClient.playerId});
    expect(startResp['players'], isA<List<dynamic>>());

    // 5. Wait for the first state update on every client.
    final allClients = [hostClient, ...guestClients];
    for (final client in allClients) {
      await client.waitForEvent('state_update');
    }

    // 6. Play cards until the game is over.
    var plays = 0;
    const maxPlays = 300;
    while (plays < maxPlays) {
      if (hostClient.latestState?['gameOver'] == true) break;

      final players = (hostClient.latestState!['players'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final activePlayers = players.where((p) => p['eliminated'] != true).toList();
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
        // Round transition in progress; wait for the next state update.
        await currentClient.waitForEvent('state_update');
        continue;
      }

      final card = currentHand.first as Map<String, dynamic>;
      currentClient.send('play_card', {
        'roomId': roomId,
        'playerId': currentId,
        'rank': card['rank'] as String,
        'suit': card['suit'] as String,
      });

      // Wait for every client to receive the updated state.
      for (final client in allClients) {
        await client.waitForEvent('state_update');
      }

      plays++;
    }

    expect(plays, lessThan(maxPlays), reason: 'Game did not end within $maxPlays plays');
    expect(hostClient.latestState?['gameOver'], isTrue);

    // 7. Wait for game_over on all clients and validate rankings.
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
```

- [ ] **Step 2: Run the test to verify it passes**

Run:

```bash
flutter test test/server/fakka_server_integration_test.dart
```

Expected: test passes with output similar to:

```
00:00 +0: full 4-player game completes with valid rankings
00:12 +1: All tests passed!
```

- [ ] **Step 3: Run the full test suite**

Run:

```bash
flutter test
```

Expected: all existing engine tests and the new integration test pass.

- [ ] **Step 4: Commit**

```bash
git add fekka_app/test/server/fakka_server_integration_test.dart
git commit -m "test: 4-player Fakka server integration test"
```

---

## Spec Coverage Check

| Spec Requirement | Implementing Task |
|---|---|
| Fix corrupted `build_info.dart` | Task 1 |
| Prevent re-corruption in `build_apk.ps1` | Task 1 |
| Expose actual bound port for testing | Task 2 |
| Spawn `FakkaServer` on free port | Task 3 |
| Connect 4 WebSocket clients | Task 3 |
| REST create/join/start flow | Task 3 |
| Play cards until game over | Task 3 |
| Assert unique 1-4 rankings | Task 3 |
| `flutter analyze` error-free | Tasks 1, 2, 3 |

## Placeholder Scan

- No `TBD`, `TODO`, or "implement later" strings.
- No vague "add error handling" steps.
- No "similar to Task N" references.
- All code blocks contain complete, runnable code.

## Type Consistency Check

- `BuildInfo.number` remains `int`; `BuildInfo.colors` remains `List<int>`.
- `FakkaServer.actualPort` returns `int`.
- WS event names match those used in `fekka_server.dart` (`play_card`, `get_state`, `state_update`, `state_sync`, `capture_event`, `round_end`, `player_eliminated`, `game_over`).
- REST paths match `fakta_server.dart` routing.

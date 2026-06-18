# Fakka — Build Fix + 4-Player Server Integration Tests

> **Status:** Design approved  
> **Scope:** Fix the corrupted `build_info.dart` file, then add an automated integration test that proves the embedded Fakka server can run a complete 4-player game from create through game-over.

---

## Problem Statement

1. `fekka_app/lib/build_info.dart` is currently corrupted: it contains a Windows-1252 em dash (`0x97`) instead of a valid UTF-8 em dash, so the Dart analyzer cannot parse it and the project fails to build.
2. The Fakka embedded server and game engine are implemented, but there is no automated end-to-end proof that a full 4-player game completes successfully. Manual multi-device testing is slow and non-repeatable.

---

## Goals

1. Make `fekka_app` analyze and build cleanly on Windows.
2. Prevent the encoding bug from recurring in `build_apk.ps1`.
3. Provide a repeatable, fast integration test that drives four WebSocket clients through an entire game and asserts invariants at each phase.

---

## Non-Goals

- UI automation or widget tests.
- New gameplay features (capture animations, reconnection, etc.).
- Production signing or domain setup.
- Changes to the core game rules or scoring logic.

---

## Architecture

Two independent deliverables:

1. **Build fix** — ASCII-only regeneration of `lib/build_info.dart` plus a one-line encoding fix in `build_apk.ps1`.
2. **Integration test harness** — a new Dart test file under `fekka_app/test/server/` that:
   - Starts `FakkaServer` on an OS-assigned free port.
   - Connects four raw `dart:io` WebSocket clients.
   - Uses REST endpoints to create/join a room.
   - Uses the WebSocket protocol to start the game and play all cards.
   - Asserts state invariants after every major phase.

The test runs with `flutter test` and requires no emulator or physical devices.

---

## Components

### `fekka_app/lib/build_info.dart`

- Exports a `BuildInfo` class with:
  - `static const int number` — the build number shown in the home-screen circle.
  - `static const List<int> colors` — color values cycled by `(number - 1) % 3`.
- Content must be valid UTF-8 and ASCII-safe (no em dashes or other non-ASCII characters).
- Format must remain compatible with `home_screen.dart`, which imports it and displays `BuildInfo.number` inside `BuildInfo.colors[(BuildInfo.number - 1) % 3]`.

### `fekka_app/build_apk.ps1`

- Replace the em dash in the generated header with an ASCII hyphen (`-`).
- Add `-Encoding UTF8` to the `Set-Content` call that writes `lib/build_info.dart`.

### `fekka_app/test/server/fakka_server_integration_test.dart`

- `TestClient` helper class:
  - Holds `WebSocket`, `HttpClient`, and per-client message queue.
  - Provides `connect()`, `send(event, data)`, `expectEvent(type)`, and `close()`.
- Server fixture:
  - `setUpAll`: start `FakkaServer(port: 0)`, record assigned port.
  - `tearDownAll`: close server and dispose clients.
- Test flow:
  1. Host creates room via `POST /games/create`.
  2. Three guests join via `POST /games/:roomId/join`.
  3. All four clients open WebSocket `/game?roomId=...&playerId=...`.
  4. Host sends `start_game`.
  5. Loop until `game_over`:
     - Each client receives its personalized `state_update`.
     - Active player selects the first card in its hand and sends `play_card`.
     - All clients receive `capture_event` and updated state.
  6. Assert rankings are unique values `1..4`, cumulative scores are consistent, and the game-over event was broadcast to all clients.

---

## Data Flow

```
+-------------+   POST /games/create   +------------------+
| Host Client |----------------------->|                  |
+-------------+                        |   FakkaServer    |
                                       |  (port assigned  |
+-------------+   POST /games/:id/join |   by OS)         |
| Guest 1..3  |----------------------->|                  |
+-------------+                        |                  |
                                       |  +------------+  |
+-------------+   WS /game?...         |  | RoomManager|  |
| All clients |----------------------->|  | GameEngine |  |
+-------------+                        |  +------------+  |
                                       +------------------+
```

Messages:
- Client → Server: `{event: 'start_game', data: {roomId, playerId}}`
- Client → Server: `{event: 'play_card', data: {roomId, playerId, rank, suit}}`
- Server → Client: `{event: 'state_update', data: <personalized state>}`
- Server → Client: `{event: 'capture_event', data: {...}}`
- Server → Client: `{event: 'round_end', data: {scores, cumulativeScores}}`
- Server → Client: `{event: 'game_over', data: {rankings}}`

---

## Error Handling

- `expectEvent` must throw a descriptive error if the expected event is not received within 10 seconds.
- If a WebSocket closes unexpectedly, the helper throws with the close code/reason.
- `tearDownAll` must always run: close all clients, then shut down the server, even if a test fails.
- Any unhandled exception in `FakkaServer` must propagate and fail the test rather than hanging.

---

## Testing

- `flutter test test/server/fakka_server_integration_test.dart` — full 4-player integration test.
- `flutter analyze` — must report zero errors after the build fix.
- `powershell -File fekka_app/build_apk.ps1` — must succeed and produce a valid `build_info.dart`.

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Test is flaky due to timing | Use deterministic seeded engine + `await` for server events instead of `sleep`. |
| Port collision | Pass `port: 0` to `FakkaServer` so the OS assigns an ephemeral port. |
| Test hangs on WS close | Set a 10s timeout on every `expectEvent` and close clients in `tearDownAll`. |
| Existing server code has bugs that block the test | Fix only bugs necessary to make the test pass; file separate tasks for larger issues. |

---

## Acceptance Criteria

- [ ] `flutter analyze` passes with no errors in `fekka_app`.
- [ ] `build_apk.ps1` runs without errors and generates a UTF-8-valid `lib/build_info.dart`.
- [ ] `flutter test test/server/fakka_server_integration_test.dart` passes.
- [ ] The integration test verifies create, 3 joins, start, a full round (or full game), and game-over rankings.

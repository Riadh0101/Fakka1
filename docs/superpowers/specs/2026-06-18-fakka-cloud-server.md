# Fakka Cloud Server — Design Spec

**Date:** 2026-06-18
**Status:** Approved

## Goal

Enable 4 phones to play Fakka from anywhere on the internet by deploying a
cloud-hosted Node.js game server. The Flutter APK connects to it instead of
the embedded Dart phone server.

## Architecture

```
4 Phones (Flutter APK) ──► https://fakka-game.onrender.com
                                    │
                            ┌───────▼────────┐
                            │  fakka-cloud/  │
                            │  Node.js + ws  │
                            │  + TS engine   │
                            │  (Render free) │
                            └────────────────┘
```

The Flutter client protocol is unchanged. The cloud server implements the
exact same REST+WS contract as the embedded Dart `FakkaServer`.

## Components

### 1. `fakka-cloud/` — New Node.js server
- `src/server.ts` — Express HTTP router + raw WebSocket upgrade handler
- `src/room.ts` — In-memory room manager (create, join, start, status)
- `src/engine/` — Copied from `fekka_server/src/fekka/engine/` (TypeScript game engine)
- `package.json` — Express, ws, uuid, typescript
- Deploy target: Render (free tier)

### 2. `fekka_app/lib/config.dart` — One-line URL change
- `_fallbackBaseUrl` → `https://fakka-game.onrender.com`
- Keep `isHost` / `hostIp` path for offline LAN mode

### 3. `fekka_app/lib/server/fakka_server.dart` — No changes
- Embedded Dart server stays as-is for offline/hotspot 2-phone

## Protocol (matches Dart server exactly)

| Endpoint | Method | Request | Response |
|---|---|---|---|
| `/games/create` | POST | `{adminName}` | `{roomId, adminPlayerId}` |
| `/games/:id/join` | POST | `{playerName}` | `{playerId, seatIndex, roomStatus}` |
| `/games/:id/start` | POST | `{adminPlayerId}` | game state JSON |
| `/games/:id/status` | GET | — | `{status, playerCount}` |
| `/game` | WS | `?roomId=X&playerId=Y` | `{event, data}` |

WS events: `state_sync`, `state_update`, `capture_event`, `round_end`,
`player_eliminated`, `game_over`, `player_joined`, `error`

## Constraints
- Cost: $0 (Render free tier: 750h/month, auto-sleep, wakes on HTTP)
- Room codes: 5-char uppercase (matching Dart server: `uuid.v4().hex[:5]`)
- Player limit: 4 per room
- State: In-memory (acceptable for free tier; rooms expire on deploy)
- No database (Render free tier disk is ephemeral)

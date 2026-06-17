# FAKKA (Schkobba 40) — Master Tracker

> **Status**: Embedded server architecture complete — engine ported to Dart, server runs on host phone.  
> **Last updated**: June 17, 2026

---

## PROJECT STRUCTURE

```
D:\Fakka\
├── TODO.md                                    ← This file
├── Fekka_Multiplayer_App_Implementation_Prompt.txt
├── fakka_App.apk                              ← Latest APK (hotspot: 192.168.137.1)
├── fekka_cli\fekka.py                         ← Phase 1: Python engine
├── fekka_server\                              ← Phase 2: NestJS backend (legacy — replaced by embedded)
├── fekka_app\                                 ← Phase 3: Flutter app with embedded server
│   └── lib\
│       ├── engine\                            ← Pure Dart game engine (ported from TS)
│       │   ├── card.dart
│       │   ├── card_adapter.dart              ← UI ↔ engine Card conversion
│       │   ├── deck.dart
│       │   ├── player_stack.dart
│       │   ├── middle_pool.dart
│       │   ├── game_engine.dart
│       │   └── room_manager.dart
│       └── server\
│           └── fakka_server.dart              ← Embedded HTTP+WS server (dart:io)
├── open_firewall.bat
├── fix_network.bat
├── connection_guide.bat
└── build_apk.ps1
```

---

## ✅ DONE

### Phase 1 — Python CLI Engine
- [x] Card, Deck, PlayerStack, MiddlePool classes
- [x] Player + GameManager + combined capture logic
- [x] Sequential reveal cascade algorithm
- [x] 36 unit tests + 12 required scenarios
- [x] 100-game smoke test (0 exceptions)
- [x] QA audit passed

### Phase 2 — Backend (NestJS) — LEGACY
- [x] GameEngineService ported to TypeScript (38 Jest tests)
- [x] GameRoomService + InMemoryRoomRepository + RoomRedisRepository
- [x] FekkaGateway (Socket.IO namespaced per room)
- [x] REST endpoints: POST /games/create, /join, /start
- [x] SQLite instead of PostgreSQL
- [x] In-memory fallback when Redis unavailable

### Phase 3 — Embedded Server Architecture (June 17)
- [x] Dart game engine ported from TypeScript (card, deck, player_stack, middle_pool, game_engine, room_manager)
- [x] Card adapter: UI GameCard (int rank, word suit) ↔ engine Card (string rank, symbol suit)
- [x] Embedded HTTP+WS server (dart:io HttpServer + WebSocket, port 3000)
- [x] REST endpoints: POST /games/create, /games/:id/join, /games/:id/start, GET /games/:id/status
- [x] WebSocket namespace /game with JSON event protocol
- [x] config.dart updated for host/guest dynamic URLs
- [x] socket_service.dart replaced socket_io_client with raw dart:io WebSocket
- [x] api_service.dart uses dynamic AppConfig.apiUrl
- [x] game_provider.dart starts FakkaServer when hosting, sets isHost flag
- [x] app.dart parses `host` query param from deep links
- [x] join_screen.dart handles Map arguments (roomId + hostIp) from deep links
- [x] lobby_screen.dart detects device IP, includes host in share invite link

### Phase 2 — Frontend (Flutter)
- [x] 6 screens: Home, Join, Lobby, GameTable, ScoreSummary, GameOver
- [x] Riverpod state management
- [x] Share invite via share_plus (WhatsApp)
- [x] Deep linking config (Android App Links)
- [x] Fakka branding (name, icon, colors)
- [x] Build version circle
- [x] Cleartext HTTP fix (Android 9+)
- [x] APK build script

### E2E Verified
- [x] App launches on emulator (Pixel 6, Android 14)
- [x] Home screen: "Fakka" title, name input, Create/Join buttons
- [x] Create Game → API call → Lobby with room code, 4 seats

---

## 🔲 REMAINING

### Gameplay (the actual game)
- [ ] GameTable screen: play cards, show pool, show opponents
- [ ] Server processes turns, broadcasts state updates
- [ ] Capture animations (pool cascade, stack steal)
- [ ] Round scoring + elimination flow
- [ ] Game over screen with rankings

### Multiplayer
- [ ] 4-player join flow (Share Invite → Join → Lobby → Start)
- [ ] Admin Start Game button
- [ ] Real-time socket gameplay with 4 phones
- [ ] Reconnection handling

### Testing
- [ ] Dart unit tests for game engine (port 38 Jest tests)
- [ ] Server integration tests (spawn server, connect WS clients, simulate turns)

### Production
- [ ] APK signed with release keystore
- [ ] iOS build + Universal Links
- [ ] Domain: fekka-game.com with assetlinks.json

---

## NEW ARCHITECTURE: Embedded Server

```
┌─────────────────────────┐
│     Phone A (Host)      │
│  ┌───────────────────┐  │
│  │  Flutter App      │  │
│  │  ┌─────────────┐  │  │
│  │  │ UI (Client)  │  │  │
│  │  └──────┬──────┘  │  │
│  │         │connect  │  │
│  │  ┌──────▼──────┐  │  │
│  │  │ FakkaServer │  │  │  ← Embedded HTTP + WS
│  │  │ RoomManager │  │  │    on port 3000
│  │  │ GameEngine  │  │  │
│  │  └─────────────┘  │  │
│  └───────────────────┘  │
│  Shares WhatsApp link   │
│  with host IP           │
└────────┬───────────────┘
         │ 192.168.1.5:3000
    ┌────┼────┬────┐
    ▼    ▼    ▼    ▼
  Phone Phone Phone Phone
   B     C     D     (A)
```

- **No PC required** — host phone runs the server
- **Same Wi-Fi or hotspot** — guests connect via host IP
- **Deep link format**: `https://fekka-game.com/join/{roomId}?host={ip}:3000`
- **Single codebase** — pure Dart, zero external server dependencies

---

## QUICK START

```bash
# Build new APK
cd D:\Fakka\fekka_app
.\build_apk.ps1

# Python engine (instant)
python D:\Fakka\fekka_cli\fekka.py --auto --seed 42

# Python tests
python D:\Fakka\fekka_cli\fekka.py --test
```

## CONNECTION GUIDE

| Method | IP | Requires |
|---|---|---|
| Phone Hotspot | Host IP (e.g. `192.168.43.1:3000`) | Guests join host hotspot |
| Same Wi-Fi | Host IP on Wi-Fi (e.g. `192.168.1.5:3000`) | Same network |
| Host itself | `localhost:3000` | App auto-connects |

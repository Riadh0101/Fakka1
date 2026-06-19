# FAKKA (Schkobba 40) — Master Tracker

> **Status**: Playable — cloud server with game engine deployed on Render, Flutter app with full Arabic UI.  
> **Last updated**: June 20, 2026  
> **Server**: https://fakka1.onrender.com  

---

## PROJECT STRUCTURE

```
D:\Fakka1\
├── TODO.md                                    ← This file
├── fekka_cli\fekka.py                         ← Phase 1: Python engine + 36 tests
├── fekka_server\                              ← Phase 2: NestJS backend (legacy)
├── fekka_app\                                 ← Phase 3: Flutter app
│   ├── lib\
│   │   ├── engine\                            ← Pure Dart game engine
│   │   │   ├── card.dart, deck.dart, player_stack.dart, middle_pool.dart
│   │   │   ├── game_engine.dart, room_manager.dart
│   │   │   └── card_adapter.dart, state_adapter.dart
│   │   ├── screens\                           ← 6 screens (home, join, lobby, game_table, score_summary, game_over)
│   │   ├── widgets\                           ← card, hand, middle_pool, player_position, turn_indicator
│   │   ├── providers\game_provider.dart       ← Riverpod state management
│   │   ├── services\                          ← api_service.dart, socket_service.dart
│   │   └── server\fakka_server.dart           ← Embedded Dart server (fallback)
│   ├── test\
│   │   ├── engine\game_engine_test.dart       ← 40 tests
│   │   ├── engine\room_manager_test.dart      ← 58 tests
│   │   └── server\fakka_server_integration.dart ← E2E test
│   └── build_apk.ps1                          ← Auto-incrementing build script
├── fakka-cloud\                               ← Phase 3: Cloud server (PRODUCTION)
│   ├── src\
│   │   ├── engine\                            ← TypeScript game engine
│   │   ├── server.ts                          ← Express + WebSocket server
│   │   └── room.ts                            ← Room manager + engine integration
│   └── render.yaml                            ← Render deploy config
├── bot_test.js                                ← Auto-play bot for testing
├── qa_comprehensive_tests.py                  ← QA edge case suite (903 lines)
└── build_apk.ps1
```

---

## ✅ DONE

### Core Gameplay
- [x] Full game engine: 40-card deck, deal, sequential-reveal capture, stack steals, combined capture
- [x] Turn-based play with turn indicator ("دورك" / "دور X")
- [x] Round scoring: J/Q/K=2pts, numerals=1pt, cumulative tracking
- [x] Elimination at 51pts, ranking by score desc
- [x] 12 rounds per game, auto-deal, deck recycling
- [x] Cloud server handles all game logic server-authoritatively

### Cloud Server (fakka-cloud on Render)
- [x] Deployed at https://fakka1.onrender.com
- [x] REST: POST /games/create, /join, /start, /leave, GET /status
- [x] WebSocket: /game with state_sync, state_update, capture_event, round_end, game_over
- [x] Game engine fully integrated (processTurn, processRoundEnd, setupNextRound)
- [x] Per-player sanitized state (opponent hands/stacks hidden)
- [x] 4-digit numeric room codes (1000-9999)
- [x] Connected-player-only join limit (disconnected players don't block)
- [x] Leave room + seat re-indexing + admin transfer

### Flutter App (build #18, yellow)
- [x] Full Arabic UI: all screens, buttons, labels, errors, notifications
- [x] Home screen: Fakka logo, name input, Create/Join buttons, Quit (خروج)
- [x] Join screen: room code entry, deep link support
- [x] Lobby: player list (4 seats), share room code, admin start, live refresh
- [x] GameTable: live opponent names, stack top, hand count, active player glow
- [x] Capture notifications: amber toast "أنت التقطت N ورقة"
- [x] Score summary screen after each round
- [x] Game over screen with trophies and rankings
- [x] Turn indicator with pulsing dot
- [x] Card overlap using Transform (no crash)
- [x] Mid-game rejoin with state restore
- [x] Stale session auto-cleanup on launch
- [x] Leave always navigates to Home

### Testing
- [x] 40 Dart engine unit tests (game_engine_test.dart)
- [x] 58 Dart RoomManager unit tests (room_manager_test.dart)
- [x] 36 Python engine tests (fekka_cli/fekka.py)
- [x] QA comprehensive suite (qa_comprehensive_tests.py) — path fixed
- [x] E2E integration test (fakka_server_integration.dart)
- [x] Auto-play bot for multiplayer testing (bot_test.js)
- [x] Broken NestJS test deleted

### Production Setup
- [x] Release keystore generated (fakka-upload-key.jks)
- [x] key.properties with signing config
- [x] build.gradle.kts: release signing, ProGuard, R8 minification
- [x] ProGuard rules (proguard-rules.pro)
- [x] Network security config (cleartext off, local dev allowed)
- [x] flutter_launcher_icons config
- [x] versionCode=15, versionName=1.0.0

---

## 🔲 REMAINING

### Polish
- [ ] Capture animations (pool cascade visual, stack steal effect)
- [ ] Sound effects (card play, capture, round end)
- [ ] Player elimination animation/toast

### Testing
- [ ] Property-based/fuzz tests for engine
- [ ] Load test with 10+ simultaneous rooms

### Production
- [ ] Replace placeholder app icons with branded PNGs
- [ ] Run `flutter pub run flutter_launcher_icons`
- [ ] Play Store listing (screenshots, descriptions, privacy policy)
- [ ] `flutter build appbundle --release` → upload to Play Console
- [ ] iOS build (future)

---

## ARCHITECTURE

```
4 Phones (Flutter APK)
   │
   │  REST + WebSocket (wss://)
   ▼
https://fakka1.onrender.com (Render free tier, Node.js)
   │
   ├── Express REST (create, join, start, leave, status)
   ├── WebSocket (state_sync, state_update, capture_event, round_end, game_over)
   └── GameEngine (processTurn, processRoundEnd, setupNextRound, sanitizeForPlayer)
```

## QUICK START

```bash
# Build new APK
cd D:\Fakka1\fekka_app
.\build_apk.ps1

# Start bots for testing (replace ROOM and IDs)
node D:\Fakka1\bot_test.js

# Python engine tests
python D:\Fakka1\fekka_cli\fekka.py --test

# Build cloud server
cd D:\Fakka1\fakka-cloud
npm run build
```

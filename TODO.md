# FAKKA (Schkobba 40) — Master Tracker

> **Status**: Paused — core engine + Create Game lobby working. Full gameplay remaining.  
> **Last updated**: June 15, 2026

---

## PROJECT STRUCTURE

```
D:\Apps\Fakka\
├── TODO.md                                    ← This file
├── Fekka_Multiplayer_App_Implementation_Prompt.txt
├── fakka_App.apk                              ← Latest APK (hotspot: 192.168.137.1)
├── fekka_cli\fekka.py                         ← Phase 1: Python engine
├── fekka_server\                              ← Phase 2: NestJS backend
├── fekka_app\                                 ← Phase 2: Flutter app
├── open_firewall.bat                          ← Admin: open port 3000
├── fix_network.bat                            ← Admin: firewall + Private network
├── connection_guide.bat                       ← Connection help
└── build_apk.ps1                              ← Auto-increment build script
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

### Phase 2 — Backend (NestJS)
- [x] GameEngineService ported to TypeScript (38 Jest tests)
- [x] GameRoomService + InMemoryRoomRepository + RoomRedisRepository
- [x] FekkaGateway (Socket.IO namespaced per room)
- [x] REST endpoints: POST /games/create, /join, /start
- [x] SQLite instead of PostgreSQL (datetime + simple-json types)
- [x] In-memory fallback when Redis unavailable
- [x] Server binds 0.0.0.0 for phone connectivity

### Phase 2 — Frontend (Flutter)
- [x] 6 screens: Home, Join, Lobby, GameTable, ScoreSummary, GameOver
- [x] Riverpod state management + Socket.IO client
- [x] Share invite via share_plus (WhatsApp)
- [x] Deep linking config (Android App Links)
- [x] Fakka branding (name, icon, colors)
- [x] Build version circle (auto-increment, blue/red/yellow cycle)
- [x] Cleartext HTTP fix (Android 9+)
- [x] Clean SocketException error messages
- [x] APK build script (build_apk.ps1)

### E2E Verified
- [x] App launches on emulator (Pixel 6, Android 14)
- [x] Home screen: "Fakka" title, name input, Create/Join buttons
- [x] Join screen: room code field, name field
- [x] Create Game → API call → Lobby with room code, 4 seats, Share Invite
- [x] Server reachable on hotspot 192.168.137.1:3000

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

### Production
- [ ] APK signed with release keystore
- [ ] Production server deploy (not localhost)
- [ ] Domain: fekka-game.com with assetlinks.json
- [ ] iOS build + Universal Links

---

## QUICK START

```bash
# Server
cd D:\Apps\Fakka\fekka_server
node dist/main.js

# Build new APK
cd D:\Apps\Fakka\fekka_app
.\build_apk.ps1

# Python engine (instant)
python D:\Apps\Fakka\fekka_cli\fekka.py --auto --seed 42

# Python tests
python D:\Apps\Fakka\fekka_cli\fekka.py --test

# NestJS tests
cd D:\Apps\Fakka\fekka_server && npx jest --testPathPatterns="game-engine"
```

## CONNECTION GUIDE

| Method | IP | Requires |
|---|---|---|
| PC Hotspot | `192.168.137.1:3000` | Phone connects to PC hotspot |
| Same Wi-Fi | `192.168.1.97:3000` | Same network, firewall open, Private profile |
| Emulator | `10.0.2.2:3000` | Android emulator only |

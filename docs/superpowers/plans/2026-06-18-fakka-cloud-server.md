# Fakka Cloud Server — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to
> implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy a Node.js cloud server that enables 4-phone Fakka play from anywhere on the internet.

**Architecture:** New `fakka-cloud/` directory with Express + raw WebSocket server reusing the
TypeScript engine from `fekka_server/`. Deployed to Render free tier. Flutter app config points at it.

**Tech Stack:** Node.js 18+, Express, ws (WebSocket), TypeScript, uuid

## Global Constraints

- Cost: $0 (Render free tier)
- Protocol: Must match Dart `FakkaServer` exactly (same route paths, JSON shapes, WS event names)
- Room codes: 5 uppercase hex chars
- Max 4 players per room
- In-memory state only (no database)
- The Flutter app must NOT require any client-side protocol changes

---

### Task 1: Scaffold fakka-cloud project

**Files:**
- Create: `fakka-cloud/package.json`
- Create: `fakka-cloud/tsconfig.json`
- Create: `fakka-cloud/src/engine/card.ts`
- Create: `fakka-cloud/src/engine/deck.ts`
- Create: `fakka-cloud/src/engine/middle-pool.ts`
- Create: `fakka-cloud/src/engine/player-stack.ts`
- Create: `fakka-cloud/src/engine/game-engine.ts`
- Create: `fakka-cloud/src/engine/index.ts`

**Interfaces:**
- Produces: Game engine exports (Card, Deck, MiddlePool, PlayerStack, GameEngine, GameState, PlayerState)

- [ ] **Step 1: Create package.json**

```json
{
  "name": "fakka-cloud",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "build": "tsc",
    "start": "node dist/server.js",
    "dev": "ts-node src/server.ts"
  },
  "dependencies": {
    "express": "^4.21.0",
    "ws": "^8.18.0",
    "uuid": "^10.0.0"
  },
  "devDependencies": {
    "@types/express": "^4.17.21",
    "@types/uuid": "^10.0.0",
    "@types/ws": "^8.5.12",
    "typescript": "^5.6.0",
    "ts-node": "^10.9.0"
  }
}
```

- [ ] **Step 2: Create tsconfig.json**

```json
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "commonjs",
    "lib": ["ES2020"],
    "outDir": "./dist",
    "rootDir": "./src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true,
    "declaration": true
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist"]
}
```

- [ ] **Step 3: Copy engine files from fekka_server**

Copy these files exactly as-is to `fakka-cloud/src/engine/`:
- `D:\Apps\Fakka1\fekka_server\src\fekka\engine\card.ts` → `fakka-cloud/src/engine/card.ts`
- `D:\Apps\Fakka1\fekka_server\src\fekka\engine\deck.ts` → `fakka-cloud/src/engine/deck.ts`
- `D:\Apps\Fakka1\fekka_server\src\fekka\engine\middle-pool.ts` → `fakka-cloud/src/engine/middle-pool.ts`
- `D:\Apps\Fakka1\fekka_server\src\fekka\engine\player-stack.ts` → `fakka-cloud/src/engine/player-stack.ts`
- `D:\Apps\Fakka1\fekka_server\src\fekka\engine\game-engine.service.ts` → `fakka-cloud/src/engine/game-engine.ts`

- [ ] **Step 4: Create barrel export**

```typescript
// fakka-cloud/src/engine/index.ts
export { Card } from './card';
export { Deck } from './deck';
export { MiddlePool } from './middle-pool';
export { PlayerStack } from './player-stack';
export { GameEngineService as GameEngine, GameState, PlayerState } from './game-engine';
```

- [ ] **Step 5: Install dependencies and verify build**

```bash
cd fakka-cloud
npm install
npx tsc --noEmit
```

Expected: No TypeScript errors from engine files.

- [ ] **Step 6: Commit**

```bash
git add fakka-cloud/
git commit -m "feat: scaffold fakka-cloud with TS game engine"
```

---

### Task 2: Implement room manager

**Files:**
- Create: `fakka-cloud/src/room.ts`

**Interfaces:**
- Consumes: `v4` from `uuid`
- Produces: `RoomManager` class with `createRoom(name)`, `joinRoom(roomId, name)`, `roomStatus(roomId)`, `getRoom(roomId)`, `roomExists(roomId)`, `getPlayer(roomId, playerId)`, `setPlayerConnected(roomId, playerId, connected)`, `getLobbyPlayers(roomId)`, `deleteRoom(roomId)`

- [ ] **Step 1: Write room.ts**

```typescript
// fakka-cloud/src/room.ts
import { v4 } from 'uuid';

export interface PlayerInfo {
  playerId: string;
  name: string;
  seatIndex: number;
  isConnected: boolean;
}

export interface RoomData {
  roomId: string;
  adminPlayerId: string;
  players: PlayerInfo[];
  status: 'waiting' | 'in_progress' | 'finished';
}

const rooms = new Map<string, RoomData>();

export class RoomManager {
  createRoom(adminName: string): { roomId: string; adminPlayerId: string } {
    const roomId = v4().replace(/-/g, '').slice(0, 5).toUpperCase();
    const adminPlayerId = v4().replace(/-/g, '').slice(0, 8);
    rooms.set(roomId, {
      roomId,
      adminPlayerId,
      players: [{ playerId: adminPlayerId, name: adminName, seatIndex: 0, isConnected: true }],
      status: 'waiting',
    });
    return { roomId, adminPlayerId };
  }

  joinRoom(roomId: string, playerName: string): { playerId: string; seatIndex: number; roomStatus: string } {
    const room = rooms.get(roomId);
    if (!room) throw new Error('Room not found');
    if (room.players.length >= 4) throw new Error('Room is full');
    if (room.status !== 'waiting') throw new Error('Game already started');
    const playerId = v4().replace(/-/g, '').slice(0, 8);
    const seatIndex = room.players.length;
    room.players.push({ playerId, name: playerName, seatIndex, isConnected: true });
    return { playerId, seatIndex, roomStatus: room.status };
  }

  roomStatus(roomId: string): { status: string; playerCount: number } {
    const room = rooms.get(roomId);
    if (!room) throw new Error('Room not found');
    return { status: room.status, playerCount: room.players.length };
  }

  getRoom(roomId: string): RoomData | undefined { return rooms.get(roomId); }
  roomExists(roomId: string): boolean { return rooms.has(roomId); }

  getPlayer(roomId: string, playerId: string): PlayerInfo | undefined {
    return rooms.get(roomId)?.players.find(p => p.playerId === playerId);
  }

  setPlayerConnected(roomId: string, playerId: string, connected: boolean): void {
    const player = this.getPlayer(roomId, playerId);
    if (player) player.isConnected = connected;
  }

  getLobbyPlayers(roomId: string): PlayerInfo[] {
    return rooms.get(roomId)?.players ?? [];
  }

  deleteRoom(roomId: string): void { rooms.delete(roomId); }
}
```

- [ ] **Step 2: Commit**

```bash
git add fakka-cloud/src/room.ts
git commit -m "feat: add in-memory room manager"
```

---

### Task 3: Implement HTTP + WebSocket server

**Files:**
- Create: `fakka-cloud/src/server.ts`

**Interfaces:**
- Consumes: `RoomManager` from `./room`, `express`, `ws`, `WebSocket` from `ws`
- Produces: Running HTTP+WS server on `process.env.PORT || 3000`

- [ ] **Step 1: Write server.ts**

```typescript
// fakka-cloud/src/server.ts
import express, { Request, Response } from 'express';
import { createServer } from 'http';
import { WebSocketServer, WebSocket } from 'ws';
import { RoomManager } from './room';

const app = express();
app.use(express.json());

// CORS
app.use((_req, res, next) => {
  res.header('Access-Control-Allow-Origin', '*');
  res.header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.header('Access-Control-Allow-Headers', 'Content-Type');
  next();
});
app.options('*', (_req, res) => res.sendStatus(204));

const rooms = new RoomManager();

// ── REST endpoints ──────────────────────────────────────

app.post('/games/create', (req: Request, res: Response) => {
  const { adminName } = req.body;
  if (!adminName || !adminName.trim()) {
    res.status(400).json({ message: 'adminName is required' });
    return;
  }
  const result = rooms.createRoom(adminName.trim());
  res.json(result);
});

app.post('/games/:roomId/join', (req: Request, res: Response) => {
  const { roomId } = req.params;
  const { playerName } = req.body;
  if (!playerName || !playerName.trim()) {
    res.status(400).json({ message: 'playerName is required' });
    return;
  }
  try {
    const result = rooms.joinRoom(roomId, playerName.trim());
    // Broadcast to lobby
    broadcastToRoom(roomId, 'player_joined', { players: rooms.getLobbyPlayers(roomId) });
    res.json(result);
  } catch (e: any) {
    res.status(400).json({ message: e.message });
  }
});

app.post('/games/:roomId/start', (req: Request, res: Response) => {
  const { roomId } = req.params;
  const { adminPlayerId } = req.body;
  const room = rooms.getRoom(roomId);
  if (!room) { res.status(404).json({ message: 'Room not found' }); return; }
  if (room.adminPlayerId !== adminPlayerId) {
    res.status(403).json({ message: 'Only admin can start' });
    return;
  }
  if (room.players.length < 2) {
    res.status(400).json({ message: 'Need at least 2 players' });
    return;
  }
  room.status = 'in_progress';
  broadcastToRoom(roomId, 'state_sync', { roomStatus: 'in_progress', message: 'Game starting' });
  res.json({ started: true });
});

app.get('/games/:roomId/status', (req: Request, res: Response) => {
  try {
    const status = rooms.roomStatus(req.params.roomId);
    res.json(status);
  } catch (e: any) {
    res.status(404).json({ message: e.message });
  }
});

// ── WebSocket ───────────────────────────────────────────

const server = createServer(app);
const wss = new WebSocketServer({ server, path: '/game' });

// clientKey -> { ws, roomId, playerId }
const clients = new Map<string, { ws: WebSocket; roomId: string; playerId: string }>();

function broadcastToRoom(roomId: string, event: string, data: any) {
  const message = JSON.stringify({ event, data });
  for (const [, client] of clients) {
    if (client.roomId === roomId && client.ws.readyState === WebSocket.OPEN) {
      client.ws.send(message);
    }
  }
}

wss.on('connection', (ws: WebSocket, req) => {
  const url = new URL(req.url || '', 'http://localhost');
  const roomId = url.searchParams.get('roomId');
  const playerId = url.searchParams.get('playerId');

  if (!roomId || !playerId) {
    ws.close(4000, 'roomId and playerId required');
    return;
  }
  if (!rooms.roomExists(roomId)) {
    ws.close(4004, 'Room not found');
    return;
  }
  const player = rooms.getPlayer(roomId, playerId);
  if (!player) {
    ws.close(4003, 'Player not in room');
    return;
  }

  const clientKey = `${roomId}:${playerId}`;
  clients.set(clientKey, { ws, roomId, playerId });
  rooms.setPlayerConnected(roomId, playerId, true);

  // Announce in lobby
  broadcastToRoom(roomId, 'player_joined', { players: rooms.getLobbyPlayers(roomId) });

  ws.on('message', (raw) => {
    try {
      const msg = JSON.parse(raw.toString());
      const { event, data } = msg;
      switch (event) {
        case 'play_card':
          broadcastToRoom(roomId, 'state_update', {
            action: 'played',
            playedBy: playerId,
            card: data,
          });
          break;
        case 'get_state':
          ws.send(JSON.stringify({
            event: 'state_sync',
            data: { roomStatus: rooms.getRoom(roomId)?.status },
          }));
          break;
        default:
          ws.send(JSON.stringify({ event: 'error', data: { message: `Unknown event: ${event}` } }));
      }
    } catch {
      ws.send(JSON.stringify({ event: 'error', data: { message: 'Invalid message' } }));
    }
  });

  ws.on('close', () => {
    clients.delete(clientKey);
    rooms.setPlayerConnected(roomId, playerId, false);
    broadcastToRoom(roomId, 'player_joined', { players: rooms.getLobbyPlayers(roomId) });
  });

  ws.on('error', () => {
    clients.delete(clientKey);
    rooms.setPlayerConnected(roomId, playerId, false);
  });
});

// ── Health check ────────────────────────────────────────

app.get('/', (_req, res) => res.json({ ok: true, name: 'fakka-cloud' }));

// ── Start ───────────────────────────────────────────────

const PORT = parseInt(process.env.PORT || '3000', 10);
server.listen(PORT, '0.0.0.0', () => {
  console.log(`[fakka-cloud] Listening on port ${PORT}`);
});
```

- [ ] **Step 2: Build and test locally**

```bash
cd fakka-cloud
npm install
npx tsc
node dist/server.js &
sleep 2
# Test create
curl -s -X POST http://localhost:3000/games/create -H 'Content-Type: application/json' -d '{"adminName":"Test"}'
# Expected: {"roomId":"XXXXX","adminPlayerId":"XXXXXXXX"}
# Test status
curl -s http://localhost:3000/games/XXXXX/status
# Expected: {"status":"waiting","playerCount":1}
# Stop
kill %1
```

- [ ] **Step 3: Commit**

```bash
git add fakka-cloud/src/server.ts
git commit -m "feat: add HTTP+WebSocket server with room management"
```

---

### Task 4: Update Flutter config to use cloud server

**Files:**
- Modify: `fekka_app/lib/config.dart:16`

- [ ] **Step 1: Change fallback URL**

In `config.dart`, line 16, change:
```dart
static const String _fallbackBaseUrl = 'http://192.168.137.1:3000';
```
To:
```dart
static const String _fallbackBaseUrl = 'https://fakka-game.onrender.com';
```

- [ ] **Step 2: Verify the Dart server startup guards against duplicate bind**

No changes needed — the `isHost` path in `config.dart` is only activated when a player creates a game from within the app (which will be removed later for cloud-only mode). For now, cloud URL takes precedence as fallback.

- [ ] **Step 3: Commit**

```bash
git add fekka_app/lib/config.dart
git commit -m "feat: point config at cloud server (fakka-game.onrender.com)"
```

---

### Task 5: Create Render deployment config and deploy

**Files:**
- Create: `fakka-cloud/render.yaml`
- Create: `fakka-cloud/.gitignore`

- [ ] **Step 1: Create render.yaml**

```yaml
services:
  - type: web
    name: fakka-game
    runtime: node
    buildCommand: npm install && npm run build
    startCommand: node dist/server.js
    envVars:
      - key: PORT
        value: 3000
```

- [ ] **Step 2: Create .gitignore**

```
node_modules/
dist/
.env
```

- [ ] **Step 3: Deploy to Render**

Options (choose one):
- **A: Render Dashboard** — Go to dashboard.render.com, New Web Service, connect GitHub repo, set root directory to `fakka-cloud`, deploy.
- **B: Render CLI** — If `render` CLI is installed, run from `fakka-cloud/` directory.

After deploy, verify:
```bash
curl https://fakka-game.onrender.com/
# Expected: {"ok":true,"name":"fakka-cloud"}
```

- [ ] **Step 4: Commit**

```bash
git add fakka-cloud/render.yaml fakka-cloud/.gitignore
git commit -m "chore: add Render deploy config"
```

---

### Task 6: End-to-end validation

- [ ] **Step 1: Create game via cloud API**

```bash
ROOM=$(curl -s -X POST https://fakka-game.onrender.com/games/create \
  -H 'Content-Type: application/json' \
  -d '{"adminName":"Host"}')
echo $ROOM
ROOM_ID=$(echo $ROOM | jq -r '.roomId')
```

- [ ] **Step 2: Join as second player**

```bash
curl -s -X POST https://fakka-game.onrender.com/games/$ROOM_ID/join \
  -H 'Content-Type: application/json' \
  -d '{"playerName":"Guest1"}'
```

- [ ] **Step 3: Verify status shows 2 players**

```bash
curl -s https://fakka-game.onrender.com/games/$ROOM_ID/status
# Expected: {"status":"waiting","playerCount":2}
```

- [ ] **Step 4: Build APK and test on emulator**

```bash
cd fekka_app
flutter build apk --debug
adb install build/app/outputs/flutter-apk/app-debug.apk
# Launch app, tap "Create Game", verify lobby loads from cloud
```

- [ ] **Step 5: Commit final verification notes**

```bash
git add -A
git commit -m "chore: end-to-end validation of cloud server"
```

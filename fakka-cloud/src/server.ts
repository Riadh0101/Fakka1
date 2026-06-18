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

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
    res.status(400).json({ message: 'اسم المسؤول مطلوب' });
    return;
  }
  const result = rooms.createRoom(adminName.trim());
  res.json(result);
});

app.post('/games/:roomId/join', (req: Request, res: Response) => {
  const { roomId } = req.params;
  const { playerName } = req.body;
  if (!playerName || !playerName.trim()) {
    res.status(400).json({ message: 'اسم اللاعب مطلوب' });
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
  if (!room) {     res.status(404).json({ message: 'الغرفة غير موجودة' }); return; }
  if (room.adminPlayerId !== adminPlayerId) {
    res.status(403).json({ message: 'فقط المسؤول يمكنه البدء' });
    return;
  }
  if (room.players.length < 2) {
    res.status(400).json({ message: 'يلزم لاعبان على الأقل' });
    return;
  }
  room.status = 'in_progress';
  broadcastToRoom(roomId, 'state_sync', { roomStatus: 'in_progress', message: 'Game starting' });
  res.json({ started: true });
});

app.post('/games/:roomId/leave', (req: Request, res: Response) => {
  const { roomId } = req.params;
  const { playerId } = req.body;
  if (!playerId) {
    res.status(400).json({ message: 'معرف اللاعب مطلوب' });
    return;
  }
  try {
    const result = rooms.leaveRoom(roomId, playerId);
    broadcastToRoom(roomId, 'player_left', {
      players: rooms.getLobbyPlayers(roomId),
      newAdminId: result.newAdminId,
    });
    res.json({ left: true, playerCount: rooms.getLobbyPlayers(roomId).length });
  } catch (e: any) {
    res.status(400).json({ message: e.message });
  }
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
        case 'leave_room':
          try {
            const result = rooms.leaveRoom(roomId, playerId);
            broadcastToRoom(roomId, 'player_left', {
              players: rooms.getLobbyPlayers(roomId),
              newAdminId: result.newAdminId,
            });
            // Close this client's WS gracefully
            ws.close(1000, 'Left room');
          } catch {
            ws.send(JSON.stringify({ event: 'error', data: { message: 'فشلت مغادرة الغرفة' } }));
          }
          break;
        case 'get_state':
          ws.send(JSON.stringify({
            event: 'state_sync',
            data: { roomStatus: rooms.getRoom(roomId)?.status },
          }));
          break;
        default:
          ws.send(JSON.stringify({ event: 'error', data: { message: `حدث غير معروف: ${event}` } }));
      }
    } catch {
      ws.send(JSON.stringify({ event: 'error', data: { message: 'صيغة رسالة غير صالحة' } }));
    }
  });

  ws.on('close', () => {
    clients.delete(clientKey);
    // Only update if player still exists (not removed by explicit leave_room)
    const stillInRoom = rooms.getPlayer(roomId, playerId);
    if (stillInRoom) {
      rooms.setPlayerConnected(roomId, playerId, false);
      broadcastToRoom(roomId, 'player_joined', { players: rooms.getLobbyPlayers(roomId) });
    }
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

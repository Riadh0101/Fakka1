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

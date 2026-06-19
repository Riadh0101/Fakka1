import { v4 } from 'uuid';
import { GameEngine } from './engine';
import type { GameState, TurnResult } from './engine';

function generateRoomCode(): string {
  return String(Math.floor(1000 + Math.random() * 9000));
}

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
  private gameStates = new Map<string, GameState>();

  private _engine?: GameEngine;
  get engine(): GameEngine {
    if (!this._engine) this._engine = new GameEngine();
    return this._engine;
  }

  createRoom(adminName: string): { roomId: string; adminPlayerId: string } {
    const roomId = generateRoomCode();
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
    if (!room) throw new Error('الغرفة غير موجودة');
    if (room.status !== 'waiting') throw new Error('اللعبة قد بدأت بالفعل');

    // Remove any stale disconnected players first, then check limit
    room.players = room.players.filter(p => p.isConnected);
    if (room.players.length >= 4) throw new Error('الغرفة ممتلئة');

    const playerId = v4().replace(/-/g, '').slice(0, 8);
    const seatIndex = room.players.length;
    room.players.push({ playerId, name: playerName, seatIndex, isConnected: true });
    return { playerId, seatIndex, roomStatus: room.status };
  }

  roomStatus(roomId: string): { status: string; playerCount: number } {
    const room = rooms.get(roomId);
    if (!room) throw new Error('الغرفة غير موجودة');
    // Only count connected players in status
    const connected = room.players.filter(p => p.isConnected).length;
    return { status: room.status, playerCount: connected };
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
    return (rooms.get(roomId)?.players ?? []).filter(p => p.isConnected);
  }

  /** Remove a player from the room, re-index seats, and transfer admin if needed. */
  leaveRoom(roomId: string, playerId: string): { removed: boolean; newAdminId?: string } {
    const room = rooms.get(roomId);
    if (!room) throw new Error('الغرفة غير موجودة');

    const idx = room.players.findIndex(p => p.playerId === playerId);
    if (idx === -1) throw new Error('اللاعب غير موجود في هذه الغرفة');

    const wasAdmin = room.adminPlayerId === playerId;
    room.players.splice(idx, 1);

    // Re-index seat numbers
    room.players.forEach((p, i) => { p.seatIndex = i; });

    // Transfer admin if admin left
    let newAdminId: string | undefined;
    if (wasAdmin && room.players.length > 0) {
      room.adminPlayerId = room.players[0].playerId;
      newAdminId = room.adminPlayerId;
    }

    // Delete room if empty
    if (room.players.length === 0) {
      rooms.delete(roomId);
    }

    return { removed: true, newAdminId };
  }

  // ── Game Engine Integration ────────────────────────────────────────────

  startGameEngine(roomId: string): GameState {
    const room = rooms.get(roomId);
    if (!room) throw new Error('الغرفة غير موجودة');
    const playerIds = room.players.map(p => p.playerId);
    const playerNames = room.players.map(p => p.name);
    const state = this.engine.createInitialState(roomId, playerNames, playerIds);
    this.gameStates.set(roomId, state);
    room.status = 'in_progress';
    return state;
  }

  processTurn(roomId: string, playerId: string, card: { rank: string; suit: string }): TurnResult {
    const state = this.gameStates.get(roomId);
    if (!state) throw new Error('اللعبة لم تبدأ بعد');
    const result = this.engine.processTurn(state, playerId, card);
    this.gameStates.set(roomId, result.newState);
    return result;
  }

  processRoundEnd(roomId: string): TurnResult {
    const state = this.gameStates.get(roomId);
    if (!state) throw new Error('اللعبة لم تبدأ بعد');
    const result = this.engine.processRoundEnd(state);
    this.gameStates.set(roomId, result.newState);
    return result;
  }

  setupNextRound(roomId: string): GameState {
    const state = this.gameStates.get(roomId);
    if (!state) throw new Error('اللعبة لم تبدأ بعد');
    const next = this.engine.setupRound(state);
    this.gameStates.set(roomId, next);
    return next;
  }

  getGameState(roomId: string): GameState | undefined {
    return this.gameStates.get(roomId);
  }

  sanitizeForPlayer(roomId: string, playerId: string): GameState | undefined {
    const state = this.gameStates.get(roomId);
    if (!state) return undefined;
    return this.engine.sanitizeForPlayer(state, playerId);
  }

  deleteRoom(roomId: string): void {
    rooms.delete(roomId);
    this.gameStates.delete(roomId);
  }
}

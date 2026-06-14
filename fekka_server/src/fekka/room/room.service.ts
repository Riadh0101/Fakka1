// ═══════════════════════════════════════════════════════════════════════════════
// GameRoomService — room lifecycle management & state machine
// ═══════════════════════════════════════════════════════════════════════════════

import { Injectable, Logger, Inject } from '@nestjs/common';
import { v4 as uuidv4 } from 'uuid';
import type { IRoomRepository } from './IRoomRepository.js';
import { ROOM_REPOSITORY } from './IRoomRepository.js';
import { GameEngineService, GameState, PlayerState } from '../engine/game-engine.service.js';

/** Maximum number of players per room. */
const MAX_PLAYERS = 4;

/** Room statuses. */
type RoomStatus = 'waiting' | 'in_progress' | 'finished' | 'expired';

/**
 * Service that manages room creation, joining, starting,
 * and the state-machine transitions.
 */
@Injectable()
export class GameRoomService {
  private readonly logger = new Logger(GameRoomService.name);

  constructor(
    @Inject(ROOM_REPOSITORY) private readonly repo: IRoomRepository,
    private readonly engine: GameEngineService,
  ) {}

  /**
   * Generate a 6-character alphanumeric room ID.
   */
  private generateRoomId(): string {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    let id = '';
    for (let i = 0; i < 6; i++) {
      id += chars[Math.floor(Math.random() * chars.length)];
    }
    return id;
  }

  /**
   * Create a new room. The admin is the first player.
   */
  async createRoom(
    adminName: string,
  ): Promise<{ roomId: string; adminPlayerId: string; inviteLink: string }> {
    const roomId = this.generateRoomId();
    const adminPlayerId = uuidv4();

    const adminPlayer: PlayerState = {
      id: adminPlayerId,
      name: adminName,
      hand: [],
      stack: [],
      cumulativeScore: 0,
      eliminated: false,
      rankEarned: null,
      seatIndex: 0,
      connected: true,
    };

    await this.repo.createRoom(roomId, adminPlayer);

    this.logger.log(`Room ${roomId} created by ${adminName} (${adminPlayerId})`);

    return {
      roomId,
      adminPlayerId,
      inviteLink: `https://fekka-game.com/join/${roomId}`,
    };
  }

  /**
   * Join an existing waiting room.
   */
  async joinRoom(
    roomId: string,
    playerName: string,
  ): Promise<{ playerId: string; seatIndex: number }> {
    const meta = await this.repo.getMeta(roomId);
    if (!meta) {
      throw new Error('Room not found');
    }

    if (meta.status !== 'waiting') {
      throw new Error('Game is already in progress or finished');
    }

    const playerIds = await this.repo.getPlayerIds(roomId);
    if (playerIds.length >= MAX_PLAYERS) {
      throw new Error('Room is full (max 4 players)');
    }

    const playerId = uuidv4();
    const seatIndex = playerIds.length;

    const player: PlayerState = {
      id: playerId,
      name: playerName,
      hand: [],
      stack: [],
      cumulativeScore: 0,
      eliminated: false,
      rankEarned: null,
      seatIndex,
      connected: true,
    };

    const result = await this.repo.joinRoom(roomId, player);
    if (!result.success) {
      throw new Error(result.error || 'Failed to join room');
    }

    this.logger.log(`${playerName} (${playerId}) joined room ${roomId}, seat ${seatIndex}`);

    return { playerId, seatIndex };
  }

  /**
   * Start the game. Only the admin can start. All 4 seats must be filled.
   */
  async startGame(
    roomId: string,
    adminPlayerId: string,
    seed?: number,
  ): Promise<GameState> {
    const meta = await this.repo.getMeta(roomId);
    if (!meta) {
      throw new Error('Room not found');
    }

    if (meta.status !== 'waiting') {
      throw new Error('Game cannot be started — invalid status: ' + meta.status);
    }

    if (meta.adminPlayerId !== adminPlayerId) {
      throw new Error('Only the room admin can start the game');
    }

    const playerIds = await this.repo.getPlayerIds(roomId);
    if (playerIds.length !== MAX_PLAYERS) {
      throw new Error(
        `Need exactly ${MAX_PLAYERS} players to start (currently ${playerIds.length})`,
      );
    }

    // Load player data via the repository.
    const playerHashes = await Promise.all(
      playerIds.map((id: string) => this.repo.getPlayerData(roomId, id)),
    );

    const playerNames: string[] = [];
    const playerUuids: string[] = [];

    playerHashes
      .filter((h): h is Record<string, string> => h !== null && Object.keys(h).length > 0)
      .sort((a, b) => parseInt(a.seatIndex, 10) - parseInt(b.seatIndex, 10))
      .forEach((h) => {
        playerNames.push(h.name);
        playerUuids.push(h.id);
      });

    if (playerNames.length !== MAX_PLAYERS) {
      throw new Error('Invalid player count after sorting');
    }

    const state = this.engine.createInitialState(
      roomId,
      playerNames,
      playerUuids,
      seed,
    );

    await this.repo.saveGameState(roomId, state);
    await this.repo.setMetaField(roomId, 'status', 'in_progress');
    await this.repo.refreshTTL(roomId);

    this.logger.log(`Game started in room ${roomId}`);

    return state;
  }

  /**
   * Get the current room status.
   */
  async getRoomStatus(
    roomId: string,
  ): Promise<{ status: RoomStatus; playerCount: number }> {
    const meta = await this.repo.getMeta(roomId);
    if (!meta) {
      throw new Error('Room not found');
    }

    const playerIds = await this.repo.getPlayerIds(roomId);

    return {
      status: meta.status as RoomStatus,
      playerCount: playerIds.length,
    };
  }

  /**
   * Check if a room exists.
   */
  async roomExists(roomId: string): Promise<boolean> {
    const meta = await this.repo.getMeta(roomId);
    return meta !== null && Object.keys(meta).length > 0;
  }
}

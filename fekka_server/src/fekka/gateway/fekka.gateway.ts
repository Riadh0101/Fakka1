// ═══════════════════════════════════════════════════════════════════════════════
// FekkaGateway — Socket.IO gateway for real-time game communication
// ═══════════════════════════════════════════════════════════════════════════════

import {
  WebSocketGateway,
  WebSocketServer,
  SubscribeMessage,
  OnGatewayConnection,
  OnGatewayDisconnect,
  ConnectedSocket,
  MessageBody,
} from '@nestjs/websockets';
import { Server, Socket } from 'socket.io';
import { Injectable, Logger, Inject } from '@nestjs/common';
import { GameEngineService, GameState } from '../engine/game-engine.service.js';
import type { IRoomRepository } from '../room/IRoomRepository.js';
import { ROOM_REPOSITORY } from '../room/IRoomRepository.js';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { MatchHistory, PlayerRanking } from '../entities/match-history.entity.js';

/** Time a disconnected player has to reconnect before being forfeited. */
const RECONNECT_TIMEOUT_MS = 60_000;

/** Map tracking disconnect timers: key = `${roomId}:${playerId}` */
const disconnectTimers = new Map<string, NodeJS.Timeout>();

@Injectable()
@WebSocketGateway({
  namespace: '/game',
  cors: { origin: '*', credentials: true },
  transports: ['websocket', 'polling'],
})
export class FekkaGateway implements OnGatewayConnection, OnGatewayDisconnect {
  @WebSocketServer()
  server: Server;

  private readonly logger = new Logger(FekkaGateway.name);

  constructor(
    private readonly engine: GameEngineService,
    @Inject(ROOM_REPOSITORY) private readonly repo: IRoomRepository,
    @InjectRepository(MatchHistory)
    private readonly matchRepo: Repository<MatchHistory>,
  ) {}

  // ═══════════════════════════════════════════════════════════════════════════
  // Connection Lifecycle
  // ═══════════════════════════════════════════════════════════════════════════

  async handleConnection(client: Socket): Promise<void> {
    try {
      const { roomId, playerId } = client.handshake.query as {
        roomId?: string;
        playerId?: string;
      };

      // If query params are provided, perform early joining.
      if (roomId && playerId) {
        // Validate room exists.
        const meta = await this.repo.getMeta(roomId);
        if (!meta) {
          client.emit('error', { message: 'Room not found', code: 'ROOM_NOT_FOUND' });
          client.disconnect();
          return;
        }

        // Check if player is in this room.
        const playerIds = await this.repo.getPlayerIds(roomId);
        if (!playerIds.includes(playerId)) {
          client.emit('error', { message: 'Player not in this room', code: 'NOT_IN_ROOM' });
          client.disconnect();
          return;
        }

        // Join the Socket.IO room.
        client.join(roomId);
        client.data = { roomId, playerId };

        // Cancel any pending disconnect timer for this player.
        const timerKey = `${roomId}:${playerId}`;
        const timer = disconnectTimers.get(timerKey);
        if (timer) {
          clearTimeout(timer);
          disconnectTimers.delete(timerKey);
        }

        // Mark player as connected.
        await this.repo.setPlayerConnected(roomId, playerId, true);

        this.logger.log(`Client connected: player=${playerId}, room=${roomId}`);

        // If game is in progress, send state sync.
        if (meta.status === 'in_progress') {
          const state = await this.repo.loadGameState(roomId);
          if (state) {
            const sanitized = this.engine.sanitizeForPlayer(state, playerId);
            client.emit('state_sync', sanitized);
          }
        }

        // Send player_joined event to room (for lobby display).
        const playerData = await this.repo.getPlayerData(roomId, playerId);
        if (playerData) {
          this.server.to(roomId).emit('player_joined', {
            players: (await Promise.all(
              (await this.repo.getPlayerIds(roomId)).map(async (pid: string) => {
                const pd = await this.repo.getPlayerData(roomId, pid);
                return {
                  playerId: pid,
                  name: pd?.name ?? 'Unknown',
                  seatIndex: parseInt(pd?.seatIndex ?? '0', 10),
                  isConnected: pd?.connected === 'true',
                };
              })
            )),
          });
        }
      }
      // If no query params, the client will send a 'rejoin' event to join.
    } catch (error) {
      this.logger.error(`Connection error: ${(error as Error).message}`);
      client.emit('error', { message: 'Internal connection error', code: 'INTERNAL' });
      client.disconnect();
    }
  }

  async handleDisconnect(client: Socket): Promise<void> {
    try {
      const { roomId, playerId } = client.data || {};
      if (!roomId || !playerId) return;

      this.logger.log(`Client disconnected: player=${playerId}, room=${roomId}`);

      // Mark player as disconnected.
      await this.repo.setPlayerConnected(roomId, playerId, false);

      // Start 60s reconnection timer.
      const timerKey = `${roomId}:${playerId}`;
      const timer = setTimeout(async () => {
        disconnectTimers.delete(timerKey);
        this.logger.log(
          `Player ${playerId} reconnection timeout — forfeiting`,
        );
        this.server.to(roomId).emit('player_disconnected', {
          playerId,
          message: 'Player disconnected (timeout)',
        });
      }, RECONNECT_TIMEOUT_MS);

      disconnectTimers.set(timerKey, timer);

      // Notify room.
      this.server.to(roomId).emit('player_disconnected', {
        playerId,
        message: 'Player disconnected (reconnecting...)',
      });
    } catch (error) {
      this.logger.error(`Disconnect error: ${(error as Error).message}`);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Event Handlers
  // ═══════════════════════════════════════════════════════════════════════════

  @SubscribeMessage('play_card')
  async handlePlayCard(
    @ConnectedSocket() client: Socket,
    @MessageBody() payload: { roomId: string; playerId: string; rank: string; suit: string },
  ): Promise<void> {
    try {
      const { roomId, playerId, rank, suit } = payload;

      if (!roomId || !playerId || !rank || !suit) {
        client.emit('error', { message: 'Invalid payload', code: 'INVALID_PAYLOAD' });
        return;
      }

      if (client.data?.playerId !== playerId || client.data?.roomId !== roomId) {
        client.emit('error', { message: 'Player/room mismatch', code: 'FORBIDDEN' });
        return;
      }

      // Acquire per-room lock to prevent race conditions.
      const lockAcquired = await this.repo.acquireLock(roomId, 5000);
      if (!lockAcquired) {
        client.emit('error', {
          message: 'Another action is in progress, please wait',
          code: 'LOCKED',
        });
        return;
      }

      try {
        // Load current state.
        const state = await this.repo.loadGameState(roomId);
        if (!state) {
          client.emit('error', { message: 'Game state not found', code: 'STATE_NOT_FOUND' });
          return;
        }

        if (state.gameOver) {
          client.emit('error', { message: 'Game is over', code: 'GAME_OVER' });
          return;
        }

        const card = { rank, suit };

        // Process the turn.
        const result = this.engine.processTurn(state, playerId, card);

        // Broadcast capture animation event.
        this.server.to(roomId).emit('capture_event', {
          poolCaptured: result.poolCaptured,
          stolenFrom: result.stolenFrom,
          activePlayerId: playerId,
          action: result.action,
          playedCard: result.playedCard,
        });

        // Save intermediate state.
        await this.repo.saveGameState(roomId, result.newState);

        // Check if round ended.
        if (result.roundEnded) {
          const roundResult = this.engine.processRoundEnd(result.newState);

          this.server.to(roomId).emit('round_end', {
            scores: roundResult.newState.players.map((p) => ({
              playerId: p.id,
              name: p.name,
              cumulativeScore: p.cumulativeScore,
              rankEarned: p.rankEarned,
              eliminated: p.eliminated,
            })),
          });

          for (const elimId of roundResult.eliminatedPlayerIds) {
            const elimPlayer = roundResult.newState.players.find((p) => p.id === elimId);
            this.server.to(roomId).emit('player_eliminated', {
              playerId: elimId,
              name: elimPlayer?.name,
              rank: elimPlayer?.rankEarned,
              remainingPlayers: roundResult.newState.players.filter(
                (p) => !p.eliminated,
              ).length,
            });
          }

          await this.repo.saveGameState(roomId, roundResult.newState);

          if (roundResult.newState.gameOver) {
            await this.handleGameOver(roomId, roundResult.newState);
          } else {
            const nextRoundState = this.engine.setupRound(roundResult.newState);
            await this.repo.saveGameState(roomId, nextRoundState);
          }
        }

        // Refresh TTL (no-op for in-memory).
        await this.repo.refreshTTL(roomId);

        // Broadcast sanitized state to each player individually.
        const currentState = await this.repo.loadGameState(roomId);
        if (currentState) {
          const sockets = await this.server.in(roomId).fetchSockets();
          for (const sock of sockets) {
            const sockPlayerId = (sock as any).data?.playerId;
            if (sockPlayerId) {
              const sanitized = this.engine.sanitizeForPlayer(
                currentState,
                sockPlayerId,
              );
              sock.emit('state_update', sanitized);
            }
          }
        }
      } finally {
        await this.repo.releaseLock(roomId);
      }
    } catch (error) {
      this.logger.error(`play_card error: ${(error as Error).message}`, (error as Error).stack);
      client.emit('error', {
        message: (error as Error).message || 'Internal server error',
        code: 'INTERNAL',
      });
    }
  }

  @SubscribeMessage('rejoin')
  async handleRejoin(
    @ConnectedSocket() client: Socket,
    @MessageBody() payload: { roomId: string; playerId: string },
  ): Promise<void> {
    try {
      const { roomId, playerId } = payload;

      const meta = await this.repo.getMeta(roomId);
      if (!meta) {
        client.emit('error', { message: 'Room not found', code: 'ROOM_NOT_FOUND' });
        return;
      }

      const playerIds = await this.repo.getPlayerIds(roomId);
      if (!playerIds.includes(playerId)) {
        client.emit('error', { message: 'Player not in room', code: 'NOT_IN_ROOM' });
        return;
      }

      client.join(roomId);
      client.data = { roomId, playerId };

      await this.repo.setPlayerConnected(roomId, playerId, true);

      const timerKey = `${roomId}:${playerId}`;
      const timer = disconnectTimers.get(timerKey);
      if (timer) {
        clearTimeout(timer);
        disconnectTimers.delete(timerKey);
      }

      if (meta.status === 'in_progress') {
        const state = await this.repo.loadGameState(roomId);
        if (state) {
          const sanitized = this.engine.sanitizeForPlayer(state, playerId);
          client.emit('state_sync', sanitized);
        }
      }

      // Broadcast rejoining to room.
      const playerData = await this.repo.getPlayerData(roomId, playerId);
      this.server.to(roomId).emit('player_joined', {
        playerId,
        name: playerData?.name || 'Unknown',
        seatIndex: parseInt(playerData?.seatIndex || '0', 10),
        reconnected: true,
      });

      this.logger.log(`Player ${playerId} rejoined room ${roomId}`);
    } catch (error) {
      this.logger.error(`rejoin error: ${(error as Error).message}`);
      client.emit('error', {
        message: (error as Error).message || 'Rejoin failed',
        code: 'INTERNAL',
      });
    }
  }

  @SubscribeMessage('get_state')
  async handleGetState(
    @ConnectedSocket() client: Socket,
    @MessageBody() payload: { roomId: string; playerId: string },
  ): Promise<void> {
    try {
      const { roomId, playerId } = payload;
      const state = await this.repo.loadGameState(roomId);
      if (!state) {
        client.emit('error', { message: 'Game state not found', code: 'STATE_NOT_FOUND' });
        return;
      }
      const sanitized = this.engine.sanitizeForPlayer(state, playerId);
      client.emit('state_sync', sanitized);
    } catch (error) {
      this.logger.error(`get_state error: ${(error as Error).message}`);
      client.emit('error', { message: 'Failed to get state', code: 'INTERNAL' });
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Game Over
  // ═══════════════════════════════════════════════════════════════════════════

  private async handleGameOver(roomId: string, state: GameState): Promise<void> {
    this.logger.log(`Game over in room ${roomId}`);

    const rankings: PlayerRanking[] = [...state.players]
      .sort((a, b) => (a.rankEarned ?? 99) - (b.rankEarned ?? 99))
      .map((p) => ({
        playerName: p.name,
        rank: p.rankEarned ?? 99,
        score: p.cumulativeScore,
      }));

    try {
      const match = this.matchRepo.create({
        roomId,
        playedAt: new Date(),
        totalRounds: state.roundCount,
        rankings,
      });
      await this.matchRepo.save(match);
      this.logger.log(`Match archived: ${roomId}`);
    } catch (dbError) {
      this.logger.error(
        `Failed to archive match: ${(dbError as Error).message}`,
      );
    }

    this.server.to(roomId).emit('game_over', {
      rankings,
      totalRounds: state.roundCount,
    });

    setTimeout(async () => {
      try {
        await this.repo.deleteRoom(roomId);
        this.logger.log(`Cleanup complete for room ${roomId}`);
      } catch (cleanupError) {
        this.logger.error(
          `Cleanup error: ${(cleanupError as Error).message}`,
        );
      }
    }, 30_000);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// RoomRedisRepository — Redis operations for game state persistence
// ═══════════════════════════════════════════════════════════════════════════════

import { Injectable } from '@nestjs/common';
import { InjectRedis } from '@nestjs-modules/ioredis';
import Redis from 'ioredis';
import { Card } from '../engine/card.js';
import { GameState, PlayerState } from '../engine/game-engine.service.js';
import { IRoomRepository } from './IRoomRepository.js';

@Injectable()
export class RoomRedisRepository implements IRoomRepository {
  constructor(@InjectRedis() private readonly redis: Redis) {}

  // ── Key patterns ──────────────────────────────────────────────────────────

  private metaKey(roomId: string) {
    return `room:${roomId}:meta`;
  }
  private deckKey(roomId: string) {
    return `room:${roomId}:deck`;
  }
  private poolKey(roomId: string) {
    return `room:${roomId}:pool`;
  }
  private playerKey(roomId: string, playerId: string) {
    return `room:${roomId}:player:${playerId}`;
  }
  private playerSetKey(roomId: string) {
    return `room:${roomId}:players`;
  }
  private lockKey(roomId: string) {
    return `room:${roomId}:lock`;
  }

  // ── Room lifecycle ────────────────────────────────────────────────────────

  async createRoom(roomId: string, adminPlayer: PlayerState): Promise<void> {
    const pipe = this.redis.pipeline();

    pipe.hset(
      this.metaKey(roomId),
      'status', 'waiting',
      'turnIndex', '0',
      'roundPlays', '0',
      'nextRank', '1',
      'gameOver', 'false',
      'adminPlayerId', adminPlayer.id,
      'roundCount', '0',
    );

    pipe.sadd(this.playerSetKey(roomId), adminPlayer.id);

    pipe.hset(
      this.playerKey(roomId, adminPlayer.id),
      ...this.playerFields(adminPlayer),
    );

    pipe.expire(this.metaKey(roomId), 600);
    pipe.expire(this.playerSetKey(roomId), 600);
    pipe.expire(this.playerKey(roomId, adminPlayer.id), 600);

    await pipe.exec();
  }

  async joinRoom(
    roomId: string,
    player: PlayerState,
  ): Promise<{ success: boolean; error?: string }> {
    const meta = await this.redis.hgetall(this.metaKey(roomId));
    if (!meta || Object.keys(meta).length === 0) {
      return { success: false, error: 'Room not found' };
    }

    if (meta.status !== 'waiting') {
      return { success: false, error: 'Game already in progress' };
    }

    const playerIds = await this.redis.smembers(this.playerSetKey(roomId));
    if (playerIds.length >= 4) {
      return { success: false, error: 'Room is full (max 4 players)' };
    }

    const pipe = this.redis.pipeline();
    pipe.sadd(this.playerSetKey(roomId), player.id);
    pipe.hset(this.playerKey(roomId, player.id), ...this.playerFields(player));
    pipe.expire(this.playerKey(roomId, player.id), 600);
    await pipe.exec();

    return { success: true };
  }

  // ── Game state persistence ───────────────────────────────────────────────

  async saveGameState(roomId: string, state: GameState): Promise<void> {
    const pipe = this.redis.pipeline();

    pipe.hset(
      this.metaKey(roomId),
      'status', 'in_progress',
      'turnIndex', String(state.currentPlayerIndex),
      'roundPlays', String(state.roundPlaysCompleted),
      'nextRank', String(state.nextRank),
      'gameOver', String(state.gameOver),
      'roundCount', String(state.roundCount),
    );

    pipe.del(this.deckKey(roomId));
    if (state.deck.length > 0) {
      const deckCards = state.deck.map((c) => JSON.stringify(c));
      pipe.rpush(this.deckKey(roomId), ...deckCards);
    }

    pipe.del(this.poolKey(roomId));
    if (state.pool.length > 0) {
      const poolCards = state.pool.map((c) => JSON.stringify(c));
      pipe.rpush(this.poolKey(roomId), ...poolCards);
    }

    for (const player of state.players) {
      pipe.hset(
        this.playerKey(roomId, player.id),
        ...this.playerFields(player),
      );
    }

    await pipe.exec();
  }

  async loadGameState(roomId: string): Promise<GameState | null> {
    const meta = await this.redis.hgetall(this.metaKey(roomId));
    if (!meta || Object.keys(meta).length === 0) {
      return null;
    }

    const playerIds = await this.redis.smembers(this.playerSetKey(roomId));

    const deckRaw = await this.redis.lrange(this.deckKey(roomId), 0, -1);
    const deck: Card[] = deckRaw.map((s: string) => JSON.parse(s));

    const poolRaw = await this.redis.lrange(this.poolKey(roomId), 0, -1);
    const pool: Card[] = poolRaw.map((s: string) => JSON.parse(s));

    const playerPromises = playerIds.map((id: string) =>
      this.redis.hgetall(this.playerKey(roomId, id)),
    );
    const playerHashes = await Promise.all(playerPromises);

    const players: PlayerState[] = playerHashes
      .filter((h: Record<string, string>) => h && Object.keys(h).length > 0)
      .map((h: Record<string, string>) => this.hydratePlayer(h))
      .sort((a, b) => a.seatIndex - b.seatIndex);

    return {
      roomId,
      deck,
      pool,
      players,
      currentPlayerIndex: parseInt(meta.turnIndex || '0', 10),
      roundPlaysCompleted: parseInt(meta.roundPlays || '0', 10),
      nextRank: parseInt(meta.nextRank || '1', 10),
      gameOver: meta.gameOver === 'true',
      roundCount: parseInt(meta.roundCount || '0', 10),
    };
  }

  // ── TTL management ────────────────────────────────────────────────────────

  async refreshTTL(roomId: string): Promise<void> {
    const ttl = 3600;
    const pipe = this.redis.pipeline();
    pipe.expire(this.metaKey(roomId), ttl);
    pipe.expire(this.deckKey(roomId), ttl);
    pipe.expire(this.poolKey(roomId), ttl);
    pipe.expire(this.playerSetKey(roomId), ttl);
    const playerIds = await this.redis.smembers(this.playerSetKey(roomId));
    for (const pid of playerIds) {
      pipe.expire(this.playerKey(roomId, pid), ttl);
    }
    await pipe.exec();
  }

  async deleteRoom(roomId: string): Promise<void> {
    const playerIds = await this.redis.smembers(this.playerSetKey(roomId));
    const keys = [
      this.metaKey(roomId),
      this.deckKey(roomId),
      this.poolKey(roomId),
      this.playerSetKey(roomId),
      this.lockKey(roomId),
    ];
    for (const pid of playerIds) {
      keys.push(this.playerKey(roomId, pid));
    }
    if (keys.length > 0) {
      await this.redis.del(...keys);
    }
  }

  // ── Locking ───────────────────────────────────────────────────────────────

  async acquireLock(roomId: string, ttlMs = 3000): Promise<boolean> {
    const result = await this.redis.set(
      this.lockKey(roomId),
      '1',
      'PX',
      String(ttlMs),
      'NX',
    );
    return result === 'OK';
  }

  async releaseLock(roomId: string): Promise<void> {
    await this.redis.del(this.lockKey(roomId));
  }

  // ── Queries ───────────────────────────────────────────────────────────────

  async getMeta(roomId: string): Promise<Record<string, string> | null> {
    const meta = await this.redis.hgetall(this.metaKey(roomId));
    if (!meta || Object.keys(meta).length === 0) return null;
    return meta;
  }

  async getPlayerIds(roomId: string): Promise<string[]> {
    return this.redis.smembers(this.playerSetKey(roomId));
  }

  async getPlayerData(
    roomId: string,
    playerId: string,
  ): Promise<Record<string, string> | null> {
    const data = await this.redis.hgetall(this.playerKey(roomId, playerId));
    if (!data || Object.keys(data).length === 0) return null;
    return data;
  }

  async setMetaField(
    roomId: string,
    field: string,
    value: string,
  ): Promise<void> {
    await this.redis.hset(this.metaKey(roomId), field, value);
  }

  async setPlayerConnected(
    roomId: string,
    playerId: string,
    connected: boolean,
  ): Promise<void> {
    await this.redis.hset(
      this.playerKey(roomId, playerId),
      'connected',
      String(connected),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /** Build flat hset args for a PlayerState. */
  private playerFields(player: PlayerState): string[] {
    return [
      'id', player.id,
      'name', player.name,
      'hand', JSON.stringify(player.hand),
      'stack', JSON.stringify(player.stack),
      'cumulativeScore', String(player.cumulativeScore),
      'eliminated', String(player.eliminated),
      'rankEarned', player.rankEarned === null ? '' : String(player.rankEarned),
      'seatIndex', String(player.seatIndex),
      'connected', String(player.connected),
    ];
  }

  /** Reconstruct a PlayerState from a Redis hash. */
  private hydratePlayer(h: Record<string, string>): PlayerState {
    return {
      id: h.id,
      name: h.name,
      hand: JSON.parse(h.hand || '[]'),
      stack: JSON.parse(h.stack || '[]'),
      cumulativeScore: parseInt(h.cumulativeScore || '0', 10),
      eliminated: h.eliminated === 'true',
      rankEarned: h.rankEarned ? parseInt(h.rankEarned, 10) : null,
      seatIndex: parseInt(h.seatIndex || '0', 10),
      connected: h.connected !== 'false',
    };
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// IRoomRepository — repository interface for room state persistence
// ═══════════════════════════════════════════════════════════════════════════════

import { GameState, PlayerState } from '../engine/game-engine.service.js';

/**
 * DI token for the room repository.
 * Use @Inject(ROOM_REPOSITORY) to inject the active implementation.
 */
export const ROOM_REPOSITORY = 'IRoomRepository';

export interface IRoomRepository {
  // ── Room lifecycle ──────────────────────────────────────────────────────

  /** Create a new room with the admin as the first player. */
  createRoom(roomId: string, adminPlayer: PlayerState): Promise<void>;

  /** Add a player to an existing waiting room. */
  joinRoom(roomId: string, player: PlayerState): Promise<{ success: boolean; error?: string }>;

  /** Delete all data for a room. */
  deleteRoom(roomId: string): Promise<void>;

  // ── Game state persistence ──────────────────────────────────────────────

  /** Persist the full game state. */
  saveGameState(roomId: string, state: GameState): Promise<void>;

  /** Load the full game state.  Returns null if not found. */
  loadGameState(roomId: string): Promise<GameState | null>;

  // ── Queries ─────────────────────────────────────────────────────────────

  /** Get room metadata hash (status, turnIndex, adminPlayerId, etc.). */
  getMeta(roomId: string): Promise<Record<string, string> | null>;

  /** Get the list of player IDs currently in the room. */
  getPlayerIds(roomId: string): Promise<string[]>;

  /** Get the full player data hash for one player. */
  getPlayerData(roomId: string, playerId: string): Promise<Record<string, string> | null>;

  /** Set a single metadata field. */
  setMetaField(roomId: string, field: string, value: string): Promise<void>;

  /** Update a player's connected flag. */
  setPlayerConnected(roomId: string, playerId: string, connected: boolean): Promise<void>;

  /** Refresh the TTL for all keys in an in-progress room. No-op for in-memory. */
  refreshTTL(roomId: string): Promise<void>;

  // ── Locking ─────────────────────────────────────────────────────────────

  /**
   * Acquire a per-room lock for mutual exclusion during turn processing.
   * Returns true if the lock was acquired.
   */
  acquireLock(roomId: string, ttlMs?: number): Promise<boolean>;

  /** Release the per-room lock. */
  releaseLock(roomId: string): Promise<void>;
}

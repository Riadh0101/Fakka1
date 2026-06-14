// ═══════════════════════════════════════════════════════════════════════════════
// InMemoryRoomRepository — in-memory fallback when Redis is unavailable
// ═══════════════════════════════════════════════════════════════════════════════

import { Injectable } from '@nestjs/common';
import { IRoomRepository } from './IRoomRepository.js';
import { Card } from '../engine/card.js';
import { GameState, PlayerState } from '../engine/game-engine.service.js';

/** Internal room metadata stored alongside the game state. */
interface RoomMeta {
  status: string;
  turnIndex: string;
  roundPlays: string;
  nextRank: string;
  gameOver: string;
  adminPlayerId: string;
  roundCount: string;
}

@Injectable()
export class InMemoryRoomRepository implements IRoomRepository {
  // ── Stores ──────────────────────────────────────────────────────────────

  /** Room metadata keyed by roomId. */
  private readonly metas = new Map<string, RoomMeta>();

  /** Set of player IDs per room. */
  private readonly playerSets = new Map<string, Set<string>>();

  /** Player data hashes keyed by `roomId:playerId`. */
  private readonly playerData = new Map<string, Record<string, string>>();

  /** Full game states keyed by roomId. */
  private readonly gameStates = new Map<string, GameState>();

  /** Lock flags keyed by roomId. */
  private readonly locks = new Map<string, boolean>();

  // ── Room lifecycle ──────────────────────────────────────────────────────

  async createRoom(roomId: string, adminPlayer: PlayerState): Promise<void> {
    // Metadata.
    this.metas.set(roomId, {
      status: 'waiting',
      turnIndex: '0',
      roundPlays: '0',
      nextRank: '1',
      gameOver: 'false',
      adminPlayerId: adminPlayer.id,
      roundCount: '0',
    });

    // Player set.
    this.playerSets.set(roomId, new Set([adminPlayer.id]));

    // Player data.
    this.setPlayerDataEntry(roomId, adminPlayer);
  }

  async joinRoom(
    roomId: string,
    player: PlayerState,
  ): Promise<{ success: boolean; error?: string }> {
    const meta = this.metas.get(roomId);
    if (!meta) {
      return { success: false, error: 'Room not found' };
    }

    if (meta.status !== 'waiting') {
      return { success: false, error: 'Game already in progress' };
    }

    const playerSet = this.playerSets.get(roomId);
    if (!playerSet) {
      return { success: false, error: 'Room not found' };
    }

    if (playerSet.size >= 4) {
      return { success: false, error: 'Room is full (max 4 players)' };
    }

    playerSet.add(player.id);
    this.setPlayerDataEntry(roomId, player);

    return { success: true };
  }

  async deleteRoom(roomId: string): Promise<void> {
    this.metas.delete(roomId);
    this.gameStates.delete(roomId);
    this.locks.delete(roomId);

    const playerSet = this.playerSets.get(roomId);
    if (playerSet) {
      for (const pid of playerSet) {
        this.playerData.delete(`${roomId}:${pid}`);
      }
      this.playerSets.delete(roomId);
    }
  }

  // ── Game state persistence ──────────────────────────────────────────────

  async saveGameState(roomId: string, state: GameState): Promise<void> {
    // Deep-clone to prevent external mutation of our stored state.
    this.gameStates.set(roomId, this.cloneState(state));

    // Sync metadata from state.
    const meta = this.metas.get(roomId);
    if (meta) {
      meta.status = 'in_progress';
      meta.turnIndex = String(state.currentPlayerIndex);
      meta.roundPlays = String(state.roundPlaysCompleted);
      meta.nextRank = String(state.nextRank);
      meta.gameOver = String(state.gameOver);
      meta.roundCount = String(state.roundCount);
    }

    // Sync player data from state.
    for (const p of state.players) {
      this.setPlayerDataEntry(roomId, p);
    }
  }

  async loadGameState(roomId: string): Promise<GameState | null> {
    const state = this.gameStates.get(roomId);
    if (!state) return null;
    // Return a clone so callers can't mutate our stored copy.
    return this.cloneState(state);
  }

  // ── Queries ─────────────────────────────────────────────────────────────

  async getMeta(roomId: string): Promise<Record<string, string> | null> {
    const meta = this.metas.get(roomId);
    if (!meta) return null;
    return { ...meta };
  }

  async getPlayerIds(roomId: string): Promise<string[]> {
    const playerSet = this.playerSets.get(roomId);
    if (!playerSet) return [];
    return Array.from(playerSet);
  }

  async getPlayerData(
    roomId: string,
    playerId: string,
  ): Promise<Record<string, string> | null> {
    const data = this.playerData.get(`${roomId}:${playerId}`);
    return data ? { ...data } : null;
  }

  async setMetaField(
    roomId: string,
    field: string,
    value: string,
  ): Promise<void> {
    const meta = this.metas.get(roomId);
    if (meta) {
      (meta as any)[field] = value;
    }
  }

  async setPlayerConnected(
    roomId: string,
    playerId: string,
    connected: boolean,
  ): Promise<void> {
    const data = this.playerData.get(`${roomId}:${playerId}`);
    if (data) {
      data.connected = String(connected);
    }
  }

  async refreshTTL(_roomId: string): Promise<void> {
    // No-op: in-memory store doesn't expire.
  }

  // ── Locking ─────────────────────────────────────────────────────────────

  async acquireLock(roomId: string, _ttlMs = 3000): Promise<boolean> {
    if (this.locks.get(roomId)) {
      return false;
    }
    this.locks.set(roomId, true);
    return true;
  }

  async releaseLock(roomId: string): Promise<void> {
    this.locks.delete(roomId);
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  private setPlayerDataEntry(roomId: string, player: PlayerState): void {
    this.playerData.set(`${roomId}:${player.id}`, {
      id: player.id,
      name: player.name,
      hand: JSON.stringify(player.hand),
      stack: JSON.stringify(player.stack),
      cumulativeScore: String(player.cumulativeScore),
      eliminated: String(player.eliminated),
      rankEarned:
        player.rankEarned === null ? '' : String(player.rankEarned),
      seatIndex: String(player.seatIndex),
      connected: String(player.connected),
    });
  }

  /** Deep-clone a GameState so internal state can't be corrupted by callers. */
  private cloneState(state: GameState): GameState {
    return {
      roomId: state.roomId,
      deck: state.deck.map((c) => ({ ...c })),
      pool: state.pool.map((c) => ({ ...c })),
      players: state.players.map((p) => ({
        ...p,
        hand: p.hand.map((c) => ({ ...c })),
        stack: p.stack.map((c) => ({ ...c })),
      })),
      currentPlayerIndex: state.currentPlayerIndex,
      roundPlaysCompleted: state.roundPlaysCompleted,
      nextRank: state.nextRank,
      gameOver: state.gameOver,
      roundCount: state.roundCount,
    };
  }
}

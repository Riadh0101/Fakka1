// ═══════════════════════════════════════════════════════════════════════════════
// MatchHistory — TypeORM entity (SQLite / PostgreSQL compatible)
// ═══════════════════════════════════════════════════════════════════════════════

import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
} from 'typeorm';

export interface PlayerRanking {
  playerName: string;
  rank: number;
  score: number;
}

@Entity('match_history')
export class MatchHistory {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ type: 'varchar', length: 10 })
  roomId: string;

  @Column({ type: 'datetime' })
  playedAt: Date;

  @Column({ type: 'integer' })
  totalRounds: number;

  @Column({ type: 'simple-json' })
  rankings: PlayerRanking[];

  @CreateDateColumn({ type: 'datetime' })
  createdAt: Date;
}

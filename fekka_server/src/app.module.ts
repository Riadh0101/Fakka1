// ═══════════════════════════════════════════════════════════════════════════════
// AppModule — root application module
// ═══════════════════════════════════════════════════════════════════════════════

import { Module } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { TypeOrmModule } from '@nestjs/typeorm';
import { FekkaModule } from './fekka/fekka.module.js';
import { MatchHistory } from './fekka/entities/match-history.entity.js';
import { RedisModule } from '@nestjs-modules/ioredis';

@Module({
  imports: [
    // Environment configuration.
    ConfigModule.forRoot({
      isGlobal: true,
      envFilePath: ['.env', '.env.local'],
    }),

    // Redis client — always imported for DI token availability.
    // lazyConnect: true ensures no connection attempt until first use.
    // When REDIS_URL is absent, the InMemoryRoomRepository is selected
    // and the Redis client is never actually connected.
    RedisModule.forRootAsync({
      imports: [ConfigModule],
      useFactory: (config: ConfigService) => ({
        type: 'single' as const,
        url: config.get<string>('REDIS_URL', 'redis://localhost:6379'),
        options: {
          lazyConnect: true,
          retryStrategy(times: number) {
            if (times > 3) return null;
            return Math.min(times * 200, 2000);
          },
        },
      }),
      inject: [ConfigService],
    }),

    // SQLite via TypeORM for match history.
    TypeOrmModule.forRoot({
      type: 'better-sqlite3',
      database: 'fekka.db',
      entities: [MatchHistory],
      synchronize: true,
    }),

    // Fekka game module.
    FekkaModule,
  ],
})
export class AppModule {}

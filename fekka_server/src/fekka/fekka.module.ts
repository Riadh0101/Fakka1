// ═══════════════════════════════════════════════════════════════════════════════
// FekkaModule — the game module
// ═══════════════════════════════════════════════════════════════════════════════

import { Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { TypeOrmModule } from '@nestjs/typeorm';
import { GameEngineService } from './engine/game-engine.service.js';
import { RoomRedisRepository } from './room/room-redis.repository.js';
import { InMemoryRoomRepository } from './room/in-memory-room.repository.js';
import { ROOM_REPOSITORY } from './room/IRoomRepository.js';
import { GameRoomService } from './room/room.service.js';
import { FekkaGateway } from './gateway/fekka.gateway.js';
import { GameController } from './controllers/game.controller.js';
import { MatchHistory } from './entities/match-history.entity.js';

@Module({
  imports: [TypeOrmModule.forFeature([MatchHistory])],
  controllers: [GameController],
  providers: [
    // Engine (always available, no external dependencies).
    GameEngineService,

    // Both repository implementations registered so NestJS can resolve them.
    RoomRedisRepository,
    InMemoryRoomRepository,

    // Factory: pick the right repository based on REDIS_URL.
    {
      provide: ROOM_REPOSITORY,
      useFactory: (
        config: ConfigService,
        redisRepo: RoomRedisRepository,
        memRepo: InMemoryRoomRepository,
      ) => {
        const redisUrl = config.get<string>('REDIS_URL');
        if (redisUrl) {
          return redisRepo;
        }
        return memRepo;
      },
      inject: [ConfigService, RoomRedisRepository, InMemoryRoomRepository],
    },

    // Services that depend on the repository via @Inject(ROOM_REPOSITORY).
    GameRoomService,
    FekkaGateway,
  ],
  exports: [GameEngineService, GameRoomService],
})
export class FekkaModule {}

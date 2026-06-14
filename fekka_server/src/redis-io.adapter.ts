// ═══════════════════════════════════════════════════════════════════════════════
// RedisIoAdapter — Redis-backed Socket.IO adapter for horizontal scaling
// ═══════════════════════════════════════════════════════════════════════════════

import { IoAdapter } from '@nestjs/platform-socket.io';
import { ServerOptions } from 'socket.io';
import { createAdapter } from '@socket.io/redis-adapter';
import Redis from 'ioredis';
import { INestApplicationContext, Logger } from '@nestjs/common';

export class RedisIoAdapter extends IoAdapter {
  private readonly logger = new Logger(RedisIoAdapter.name);
  private adapterConstructor: ReturnType<typeof createAdapter> | null = null;
  private pubClient: Redis | null = null;
  private subClient: Redis | null = null;

  constructor(app: INestApplicationContext) {
    super(app);
  }

  /**
   * Connect to Redis and set up the pub/sub adapter.
   * Falls back gracefully if Redis is unavailable.
   */
  async connectToRedis(): Promise<void> {
    try {
      const redisUrl = process.env.REDIS_URL || 'redis://localhost:6379';

      this.pubClient = new Redis(redisUrl, { lazyConnect: true });
      this.subClient = new Redis(redisUrl, { lazyConnect: true });

      await Promise.all([
        this.pubClient.connect(),
        this.subClient.connect(),
      ]);

      this.adapterConstructor = createAdapter(this.pubClient, this.subClient);

      this.logger.log('RedisIoAdapter connected to Redis');
    } catch (error) {
      this.logger.warn(
        `Redis not available (${(error as Error).message}), falling back to in-memory adapter`,
      );
      this.adapterConstructor = null;
      // Clean up failed connections.
      try {
        await this.pubClient?.quit();
        await this.subClient?.quit();
      } catch {
        // Ignore cleanup errors.
      }
      this.pubClient = null;
      this.subClient = null;
    }
  }

  /**
   * Create the Socket.IO server with the Redis adapter if available.
   */
  createIOServer(port: number, options?: ServerOptions): any {
    const server = super.createIOServer(port, options);

    if (this.adapterConstructor) {
      server.adapter(this.adapterConstructor);
      this.logger.log('Socket.IO using Redis adapter');
    }

    return server;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// main.ts — application bootstrap
// ═══════════════════════════════════════════════════════════════════════════════

import { NestFactory } from '@nestjs/core';
import { ValidationPipe, Logger } from '@nestjs/common';
import { AppModule } from './app.module.js';
import { RedisIoAdapter } from './redis-io.adapter.js';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);

  // Enable CORS for all origins (development-friendly; restrict in production).
  app.enableCors({
    origin: '*',
    methods: ['GET', 'POST'],
    credentials: true,
  });

  // Set up Redis adapter for Socket.IO multi-instance support.
  // Falls back to default in-memory adapter if Redis is unavailable.
  try {
    const redisIoAdapter = new RedisIoAdapter(app);
    await redisIoAdapter.connectToRedis();
    app.useWebSocketAdapter(redisIoAdapter);
  } catch (error) {
    Logger.warn(
      `RedisIoAdapter setup failed (${(error as Error).message}), using default in-memory adapter`,
      'Bootstrap',
    );
    // Default Socket.IO adapter (in-memory) is used automatically.
  }

  // Global validation pipe with automatic transformation and whitelisting.
  app.useGlobalPipes(
    new ValidationPipe({
      transform: true,
      whitelist: true,
      forbidNonWhitelisted: true,
    }),
  );

  const port = process.env.PORT ?? 3000;
  await app.listen(port);

  const redisStatus = process.env.REDIS_URL
    ? `Redis: ${process.env.REDIS_URL}`
    : 'Redis: not configured (in-memory store)';

  console.log(`\n🎴 Fekka Server running on http://localhost:${port}`);
  console.log(`   WebSocket namespace: /game`);
  console.log(`   REST API: http://localhost:${port}/games`);
  console.log(`   ${redisStatus}\n`);
}

bootstrap();

// ═══════════════════════════════════════════════════════════════════════════════
// GameController — REST endpoints for room lifecycle
// ═══════════════════════════════════════════════════════════════════════════════

import { Controller, Post, Param, Body, HttpCode, HttpException, HttpStatus } from '@nestjs/common';
import { GameRoomService } from '../room/room.service.js';
import { GameEngineService } from '../engine/game-engine.service.js';
import { CreateRoomDto } from '../room/dto/create-room.dto.js';
import { JoinRoomDto } from '../room/dto/join-room.dto.js';
import { StartGameDto } from '../room/dto/play-card.dto.js';

@Controller('games')
export class GameController {
  constructor(
    private readonly roomService: GameRoomService,
    private readonly engine: GameEngineService,
  ) {}

  /**
   * POST /games/create
   */
  @Post('create')
  @HttpCode(HttpStatus.CREATED)
  async createRoom(@Body() dto: CreateRoomDto): Promise<{
    roomId: string;
    adminPlayerId: string;
    inviteLink: string;
  }> {
    try {
      const result = await this.roomService.createRoom(dto.adminName);
      return result;
    } catch (error) {
      throw new HttpException(
        (error as Error).message || 'Failed to create room',
        HttpStatus.INTERNAL_SERVER_ERROR,
      );
    }
  }

  /**
   * POST /games/:roomId/join
   */
  @Post(':roomId/join')
  @HttpCode(HttpStatus.OK)
  async joinRoom(
    @Param('roomId') roomId: string,
    @Body() dto: JoinRoomDto,
  ): Promise<{ playerId: string; seatIndex: number }> {
    try {
      const result = await this.roomService.joinRoom(roomId, dto.playerName);
      return result;
    } catch (error) {
      const msg = (error as Error).message;
      if (msg.includes('not found')) {
        throw new HttpException(msg, HttpStatus.NOT_FOUND);
      }
      if (msg.includes('progress') || msg.includes('full')) {
        throw new HttpException(msg, HttpStatus.CONFLICT);
      }
      throw new HttpException(msg, HttpStatus.BAD_REQUEST);
    }
  }

  /**
   * POST /games/:roomId/start
   */
  @Post(':roomId/start')
  @HttpCode(HttpStatus.OK)
  async startGame(
    @Param('roomId') roomId: string,
    @Body() dto: StartGameDto,
  ): Promise<any> {
    try {
      const state = await this.roomService.startGame(roomId, dto.adminPlayerId);
      return this.engine.sanitizeForPlayer(state, dto.adminPlayerId);
    } catch (error) {
      const msg = (error as Error).message;
      if (msg.includes('not found')) {
        throw new HttpException(msg, HttpStatus.NOT_FOUND);
      }
      if (msg.includes('admin')) {
        throw new HttpException(msg, HttpStatus.FORBIDDEN);
      }
      if (msg.includes('Need exactly')) {
        throw new HttpException(msg, HttpStatus.BAD_REQUEST);
      }
      throw new HttpException(msg, HttpStatus.BAD_REQUEST);
    }
  }

  /**
   * GET /games/:roomId/status
   */
  @Post(':roomId/status')
  @HttpCode(HttpStatus.OK)
  async getStatus(
    @Param('roomId') roomId: string,
  ): Promise<{ status: string; playerCount: number }> {
    try {
      return await this.roomService.getRoomStatus(roomId);
    } catch (error) {
      throw new HttpException(
        (error as Error).message || 'Room not found',
        HttpStatus.NOT_FOUND,
      );
    }
  }
}

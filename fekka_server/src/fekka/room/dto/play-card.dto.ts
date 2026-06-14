import { IsString, IsNotEmpty } from 'class-validator';

export class PlayCardDto {
  @IsString()
  @IsNotEmpty()
  roomId: string;

  @IsString()
  @IsNotEmpty()
  playerId: string;

  /** Card rank (e.g. "7", "K"). */
  rank: string;

  /** Card suit (e.g. "♠", "♥"). */
  suit: string;
}

export class StartGameDto {
  @IsString()
  @IsNotEmpty()
  adminPlayerId: string;
}

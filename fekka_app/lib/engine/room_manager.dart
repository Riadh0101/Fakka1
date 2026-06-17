// ═══════════════════════════════════════════════════════════════════════════════
// RoomManager — in-memory room lifecycle management
// ═══════════════════════════════════════════════════════════════════════════════
// Ported from room.service.ts. Replaces Redis/DB with in-memory Map.
// Zero framework deps.

import 'dart:math';
import 'package:uuid/uuid.dart';
import 'game_engine.dart';

const _maxPlayers = 4;
const _uuid = Uuid();
final _random = Random();

/// Room lifecycle status.
enum RoomStatus { waiting, inProgress, finished }

/// Internal room data stored in memory.
class _RoomData {
  final String roomId;
  String adminPlayerId;
  RoomStatus status;
  final List<PlayerState> players;
  GameState? gameState;
  DateTime createdAt;

  _RoomData({
    required this.roomId,
    required this.adminPlayerId,
    this.status = RoomStatus.waiting,
    List<PlayerState>? players,
    this.gameState,
    DateTime? createdAt,
  })  : players = players ?? [],
        createdAt = createdAt ?? DateTime.now();
}

class RoomManager {
  final GameEngine _engine = GameEngine();
  final Map<String, _RoomData> _rooms = {};

  /// Generate a 6-character alphanumeric room ID.
  String _generateRoomId() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final buffer = StringBuffer();
    for (var i = 0; i < 6; i++) {
      buffer.write(chars[_random.nextInt(chars.length)]);
    }
    return buffer.toString();
  }

  /// Create a new room. Admin is player 0.
  ({String roomId, String adminPlayerId, String inviteLink}) createRoom(
      String adminName) {
    final roomId = _generateRoomId();
    final adminPlayerId = _uuid.v4();

    final adminPlayer = PlayerState(
      id: adminPlayerId,
      name: adminName,
      seatIndex: 0,
    );

    _rooms[roomId] = _RoomData(
      roomId: roomId,
      adminPlayerId: adminPlayerId,
      players: [adminPlayer],
    );

    return (
      roomId: roomId,
      adminPlayerId: adminPlayerId,
      inviteLink: 'https://fekka-game.com/join/$roomId',
    );
  }

  /// Join an existing waiting room.
  ({String playerId, int seatIndex}) joinRoom(
      String roomId, String playerName) {
    final room = _rooms[roomId];
    if (room == null) throw StateError('Room not found');
    if (room.status != RoomStatus.waiting) {
      throw StateError('Game is already in progress or finished');
    }
    if (room.players.length >= _maxPlayers) {
      throw StateError('Room is full (max 4 players)');
    }

    final playerId = _uuid.v4();
    final seatIndex = room.players.length;

    room.players.add(PlayerState(
      id: playerId,
      name: playerName,
      seatIndex: seatIndex,
    ));

    return (playerId: playerId, seatIndex: seatIndex);
  }

  /// Start the game. Admin only, all 4 seats required.
  GameState startGame(String roomId, String adminPlayerId, {int? seed}) {
    final room = _rooms[roomId];
    if (room == null) throw StateError('Room not found');
    if (room.status != RoomStatus.waiting) {
      throw StateError('Game cannot be started — invalid status');
    }
    if (room.adminPlayerId != adminPlayerId) {
      throw StateError('Only the room admin can start the game');
    }
    if (room.players.length != _maxPlayers) {
      throw StateError(
          'Need exactly $_maxPlayers players to start (currently ${room.players.length})');
    }

    final playerNames = room.players.map((p) => p.name).toList();
    final playerIds = room.players.map((p) => p.id).toList();

    final state = _engine.createInitialState(
      roomId: roomId,
      playerNames: playerNames,
      playerIds: playerIds,
      seed: seed,
    );

    room.gameState = state;
    room.status = RoomStatus.inProgress;

    return state;
  }

  /// Get current room status.
  ({RoomStatus status, int playerCount}) getRoomStatus(String roomId) {
    final room = _rooms[roomId];
    if (room == null) throw StateError('Room not found');
    return (status: room.status, playerCount: room.players.length);
  }

  /// Check if a room exists.
  bool roomExists(String roomId) => _rooms.containsKey(roomId);

  /// Get a player by ID within a room.
  PlayerState? getPlayer(String roomId, String playerId) {
    final room = _rooms[roomId];
    if (room == null) return null;
    return room.players.cast<PlayerState?>().firstWhere(
          (p) => p?.id == playerId,
          orElse: () => null,
        );
  }

  /// Get all players in a room (lobby list).
  List<Map<String, dynamic>> getLobbyPlayers(String roomId) {
    final room = _rooms[roomId];
    if (room == null) return [];
    return room.players
        .map((p) => {
              'playerId': p.id,
              'name': p.name,
              'seatIndex': p.seatIndex,
              'isConnected': p.connected,
            })
        .toList();
  }

  /// Load game state for a room.
  GameState? loadGameState(String roomId) {
    return _rooms[roomId]?.gameState;
  }

  /// Save game state for a room.
  void saveGameState(String roomId, GameState state) {
    final room = _rooms[roomId];
    if (room != null) {
      room.gameState = state;
    }
  }

  /// Get room admin player ID.
  String? getAdminPlayerId(String roomId) {
    return _rooms[roomId]?.adminPlayerId;
  }

  /// Set player connection status.
  void setPlayerConnected(String roomId, String playerId, bool connected) {
    final room = _rooms[roomId];
    if (room == null) return;
    for (final p in room.players) {
      if (p.id == playerId) {
        p.connected = connected;
        break;
      }
    }
  }

  /// Get the game engine instance (for external use like fakka_server).
  GameEngine get engine => _engine;

  /// Clean up a finished room after game over.
  void deleteRoom(String roomId) {
    _rooms.remove(roomId);
  }
}

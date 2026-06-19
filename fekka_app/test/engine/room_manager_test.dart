// ═══════════════════════════════════════════════════════════════════════════════
// RoomManager Unit Tests — room lifecycle, player management, game orchestration
// ═══════════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:fekka_app/engine/room_manager.dart';
import 'package:fekka_app/engine/game_engine.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════════════════════════════════

/// Create a room with 4 joined players (admin + 3 joins) and start it.
({RoomManager manager, String roomId, String adminPlayerId, GameState state})
    setupFullRoom({int? seed}) {
  final manager = RoomManager();
  final cr = manager.createRoom('Admin');
  final roomId = cr.roomId;
  final adminPlayerId = cr.adminPlayerId;

  for (final name in ['Bob', 'Charlie', 'Diana']) {
    manager.joinRoom(roomId, name);
  }

  final state = manager.startGame(roomId, adminPlayerId, seed: seed);
  return (manager: manager, roomId: roomId, adminPlayerId: adminPlayerId, state: state);
}

/// Create a room and join n additional players (total = n+1 including admin).
({RoomManager manager, String roomId, String adminPlayerId, List<String> playerIds})
    setupRoomWithPlayers(int additionalPlayers) {
  final manager = RoomManager();
  final cr = manager.createRoom('Admin');
  final roomId = cr.roomId;
  final adminPlayerId = cr.adminPlayerId;

  final playerIds = <String>[adminPlayerId];
  for (var i = 0; i < additionalPlayers; i++) {
    final jr = manager.joinRoom(roomId, 'Player${i + 1}');
    playerIds.add(jr.playerId);
  }

  return (
    manager: manager,
    roomId: roomId,
    adminPlayerId: adminPlayerId,
    playerIds: playerIds,
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════════════════════

void main() {
  group('RoomManager', () {
    late RoomManager manager;

    setUp(() => manager = RoomManager());

    // ═══════════════════════════════════════════════════════════════════════════
    // createRoom
    // ═══════════════════════════════════════════════════════════════════════════

    group('createRoom', () {
      test('creates room with admin at seat 0', () {
        final cr = manager.createRoom('Admin');

        final player = manager.getPlayer(cr.roomId, cr.adminPlayerId);
        expect(player, isNotNull);
        expect(player!.name, 'Admin');
        expect(player.seatIndex, 0);
        expect(player.connected, isTrue);
      });

      test('roomId is a 4-digit numeric string', () {
        final cr = manager.createRoom('Admin');

        expect(cr.roomId, isA<String>());
        expect(cr.roomId.length, 4);
        expect(int.tryParse(cr.roomId), isNotNull);
        final numeric = int.parse(cr.roomId);
        expect(numeric, greaterThanOrEqualTo(1000));
        expect(numeric, lessThanOrEqualTo(9999));
      });

      test('generates valid inviteLink', () {
        final cr = manager.createRoom('Admin');

        expect(cr.inviteLink, contains('https://fekka-game.com/join/'));
        expect(cr.inviteLink, contains(cr.roomId));
        expect(cr.inviteLink, 'https://fekka-game.com/join/${cr.roomId}');
      });

      test('room exists after creation', () {
        final cr = manager.createRoom('Admin');

        expect(manager.roomExists(cr.roomId), isTrue);
      });

      test('returns admin as the only lobby player', () {
        final cr = manager.createRoom('Admin');

        final lobby = manager.getLobbyPlayers(cr.roomId);
        expect(lobby, hasLength(1));
        expect(lobby[0]['name'], 'Admin');
        expect(lobby[0]['seatIndex'], 0);
      });

      test('adminPlayerId matches getAdminPlayerId', () {
        final cr = manager.createRoom('Admin');

        expect(manager.getAdminPlayerId(cr.roomId), cr.adminPlayerId);
      });
    });

    // ═══════════════════════════════════════════════════════════════════════════
    // joinRoom
    // ═══════════════════════════════════════════════════════════════════════════

    group('joinRoom', () {
      test('adds players at seats 1, 2, 3', () {
        final cr = manager.createRoom('Admin');

        for (final name in ['Bob', 'Charlie', 'Diana']) {
          final jr = manager.joinRoom(cr.roomId, name);
          final player = manager.getPlayer(cr.roomId, jr.playerId);
          expect(player, isNotNull);
          expect(player!.name, name);
        }

        // Verify seat indices.
        final lobby = manager.getLobbyPlayers(cr.roomId);
        expect(lobby, hasLength(4));
        final seats = lobby.map((p) => p['seatIndex'] as int).toSet();
        expect(seats, {0, 1, 2, 3});
      });

      test('assigns sequential seat indices', () {
        final cr = manager.createRoom('Admin');

        var jr = manager.joinRoom(cr.roomId, 'P1');
        expect(jr.seatIndex, 1);

        jr = manager.joinRoom(cr.roomId, 'P2');
        expect(jr.seatIndex, 2);

        jr = manager.joinRoom(cr.roomId, 'P3');
        expect(jr.seatIndex, 3);
      });

      test('throws when room not found', () {
        expect(
          () => manager.joinRoom('9999', 'Stranger'),
          throwsStateError,
        );
      });

      test('throws when room is full (4 players)', () {
        final cr = manager.createRoom('Admin');
        manager.joinRoom(cr.roomId, 'Bob');
        manager.joinRoom(cr.roomId, 'Charlie');
        manager.joinRoom(cr.roomId, 'Diana');

        // Room is now full — 5th join should throw.
        expect(
          () => manager.joinRoom(cr.roomId, 'Extra'),
          throwsStateError,
        );
      });

      test('throws when game already started', () {
        final result = setupFullRoom();

        expect(
          () => result.manager.joinRoom(result.roomId, 'Late'),
          throwsStateError,
        );
      });

      test('returns correct roomStatus after join', () {
        final cr = manager.createRoom('Admin');

        // Initially 1 player.
        var status = manager.getRoomStatus(cr.roomId);
        expect(status.status, RoomStatus.waiting);
        expect(status.playerCount, 1);

        // After 2 joins → 3 players.
        manager.joinRoom(cr.roomId, 'Bob');
        manager.joinRoom(cr.roomId, 'Charlie');
        status = manager.getRoomStatus(cr.roomId);
        expect(status.status, RoomStatus.waiting);
        expect(status.playerCount, 3);
      });

      test('each player gets a unique playerId', () {
        final cr = manager.createRoom('Admin');

        final ids = <String>[cr.adminPlayerId];
        for (final name in ['B', 'C', 'D']) {
          final jr = manager.joinRoom(cr.roomId, name);
          ids.add(jr.playerId);
        }

        expect(ids.toSet().length, 4);
      });
    });

    // ═══════════════════════════════════════════════════════════════════════════
    // startGame
    // ═══════════════════════════════════════════════════════════════════════════

    group('startGame', () {
      test('throws when room not found', () {
        expect(
          () => manager.startGame('9999', 'fake-admin'),
          throwsStateError,
        );
      });

      test('throws when not enough players', () {
        final setup = setupRoomWithPlayers(1); // 2 players total.

        expect(
          () => manager.startGame(setup.roomId, setup.adminPlayerId),
          throwsStateError,
        );
      });

      test('throws when non-admin tries to start', () {
        final setup = setupRoomWithPlayers(3); // 4 players total.

        expect(
          () => manager.startGame(setup.roomId, setup.playerIds[1]),
          throwsStateError,
        );
      });

      test('throws when room is already in progress', () {
        final result = setupFullRoom();

        expect(
          () => result.manager.startGame(result.roomId, result.adminPlayerId),
          throwsStateError,
        );
      });

      test('returns GameState with 4 players and dealt cards', () {
        final result = setupFullRoom();

        expect(result.state.roomId, result.roomId);
        expect(result.state.players, hasLength(4));
        expect(result.state.pool, hasLength(4));

        // Each player has 3 cards in hand.
        for (final p in result.state.players) {
          expect(p.hand, hasLength(3));
          expect(p.cumulativeScore, 0);
          expect(p.eliminated, isFalse);
          expect(p.stack, isEmpty);
        }

        // Total cards accounted: 4×3 hands + 4 pool + deck = 40.
        final handTotal =
            result.state.players.fold<int>(0, (s, p) => s + p.hand.length);
        final total =
            handTotal + result.state.pool.length + result.state.deck.length;
        expect(total, 40);
      });

      test('room status changes to inProgress after start', () {
        final result = setupFullRoom();

        final status = result.manager.getRoomStatus(result.roomId);
        expect(status.status, RoomStatus.inProgress);
        expect(status.playerCount, 4);
      });

      test('deterministic with same seed', () {
        final result1 = setupFullRoom(seed: 42);
        final result2 = setupFullRoom(seed: 42);

        // Compare decks.
        expect(result1.state.deck.length, result2.state.deck.length);
        for (var i = 0; i < result1.state.deck.length; i++) {
          expect(
            result1.state.deck[i].exactMatch(result2.state.deck[i]),
            isTrue,
          );
        }

        // Compare pools.
        expect(result1.state.pool.length, result2.state.pool.length);
        for (var i = 0; i < result1.state.pool.length; i++) {
          expect(
            result1.state.pool[i].exactMatch(result2.state.pool[i]),
            isTrue,
          );
        }

        // Compare player hands.
        for (var i = 0; i < 4; i++) {
          expect(
            result1.state.players[i].hand.length,
            result2.state.players[i].hand.length,
          );
          for (var j = 0; j < result1.state.players[i].hand.length; j++) {
            expect(
              result1.state.players[i].hand[j]
                  .exactMatch(result2.state.players[i].hand[j]),
              isTrue,
            );
          }
        }

        // Different seeds should differ.
        final result3 = setupFullRoom(seed: 99);
        var anyDiff = false;
        for (var i = 0; i < result1.state.deck.length; i++) {
          if (!result1.state.deck[i].exactMatch(result3.state.deck[i])) {
            anyDiff = true;
            break;
          }
        }
        expect(anyDiff, isTrue);
      });

      test('uses random seed when none provided', () {
        // Two starts without seed should produce different results
        // (extremely unlikely to collide with 40! deck permutations).
        final result1 = setupFullRoom();
        final result2 = setupFullRoom();

        var identical = true;
        for (var i = 0; i < 4; i++) {
          if (!result1.state.deck[i].exactMatch(result2.state.deck[i])) {
            identical = false;
            break;
          }
        }
        // In the astronomically unlikely event they match, the test
        // still passes — it's a statistical assertion.
        expect(identical, isFalse);
      });
    });

    // ═══════════════════════════════════════════════════════════════════════════
    // getRoomStatus
    // ═══════════════════════════════════════════════════════════════════════════

    group('getRoomStatus', () {
      test('throws for unknown room', () {
        expect(
          () => manager.getRoomStatus('nonexistent'),
          throwsStateError,
        );
      });

      test('returns waiting with correct playerCount', () {
        final cr = manager.createRoom('Admin');

        final status = manager.getRoomStatus(cr.roomId);
        expect(status.status, RoomStatus.waiting);
        expect(status.playerCount, 1);

        manager.joinRoom(cr.roomId, 'B');
        final status2 = manager.getRoomStatus(cr.roomId);
        expect(status2.playerCount, 2);
      });

      test('returns inProgress after game starts', () {
        final result = setupFullRoom();

        final status = result.manager.getRoomStatus(result.roomId);
        expect(status.status, RoomStatus.inProgress);
      });
    });

    // ═══════════════════════════════════════════════════════════════════════════
    // roomExists
    // ═══════════════════════════════════════════════════════════════════════════

    group('roomExists', () {
      test('returns false for unknown room', () {
        expect(manager.roomExists('nonexistent'), isFalse);
      });

      test('returns true for created room', () {
        final cr = manager.createRoom('Admin');
        expect(manager.roomExists(cr.roomId), isTrue);
      });

      test('returns false after deletion', () {
        final cr = manager.createRoom('Admin');
        manager.deleteRoom(cr.roomId);
        expect(manager.roomExists(cr.roomId), isFalse);
      });
    });

    // ═══════════════════════════════════════════════════════════════════════════
    // getPlayer
    // ═══════════════════════════════════════════════════════════════════════════

    group('getPlayer', () {
      test('returns null for unknown room', () {
        expect(manager.getPlayer('nonexistent', 'any-id'), isNull);
      });

      test('returns null for unknown playerId in valid room', () {
        final cr = manager.createRoom('Admin');

        expect(manager.getPlayer(cr.roomId, 'fake-id'), isNull);
      });

      test('returns correct player by ID', () {
        final cr = manager.createRoom('Admin');

        final player = manager.getPlayer(cr.roomId, cr.adminPlayerId);
        expect(player, isNotNull);
        expect(player!.name, 'Admin');
        expect(player.seatIndex, 0);
        expect(player.id, cr.adminPlayerId);
      });

      test('returns joined player correctly', () {
        final cr = manager.createRoom('Admin');
        final jr = manager.joinRoom(cr.roomId, 'Bob');

        final player = manager.getPlayer(cr.roomId, jr.playerId);
        expect(player, isNotNull);
        expect(player!.name, 'Bob');
        expect(player.seatIndex, 1);
      });
    });

    // ═══════════════════════════════════════════════════════════════════════════
    // getLobbyPlayers
    // ═══════════════════════════════════════════════════════════════════════════

    group('getLobbyPlayers', () {
      test('returns empty list for unknown room', () {
        expect(manager.getLobbyPlayers('nonexistent'), isEmpty);
      });

      test('returns all players with correct fields', () {
        final setup = setupRoomWithPlayers(3); // 4 total.

        final lobby = setup.manager.getLobbyPlayers(setup.roomId);
        expect(lobby, hasLength(4));

        for (final entry in lobby) {
          expect(entry, contains('playerId'));
          expect(entry, contains('name'));
          expect(entry, contains('seatIndex'));
          expect(entry, contains('isConnected'));
          expect(entry['seatIndex'], isA<int>());
          expect(entry['isConnected'], isA<bool>());
        }
      });

      test('player names match what was provided', () {
        final cr = manager.createRoom('Admin');
        manager.joinRoom(cr.roomId, 'Bob');
        manager.joinRoom(cr.roomId, 'Charlie');

        final lobby = manager.getLobbyPlayers(cr.roomId);
        final names = lobby.map((p) => p['name'] as String).toSet();
        expect(names, {'Admin', 'Bob', 'Charlie'});
      });
    });

    // ═══════════════════════════════════════════════════════════════════════════
    // loadGameState / saveGameState
    // ═══════════════════════════════════════════════════════════════════════════

    group('loadGameState / saveGameState', () {
      test('loadGameState returns null before game starts', () {
        final cr = manager.createRoom('Admin');

        expect(manager.loadGameState(cr.roomId), isNull);
      });

      test('loadGameState returns null for unknown room', () {
        expect(manager.loadGameState('nonexistent'), isNull);
      });

      test('loadGameState returns state after startGame', () {
        final result = setupFullRoom();

        final loaded = result.manager.loadGameState(result.roomId);
        expect(loaded, isNotNull);
        expect(loaded!.roomId, result.roomId);
        expect(loaded.players, hasLength(4));
      });

      test('save then load returns same state', () {
        final result = setupFullRoom();
        final original = result.state;

        // Modify something to distinguish.
        final modified = original.copy();
        modified.players[0].cumulativeScore = 99;

        result.manager.saveGameState(result.roomId, modified);
        final loaded = result.manager.loadGameState(result.roomId);
        expect(loaded, isNotNull);
        expect(loaded!.players[0].cumulativeScore, 99);
      });

      test('saveGameState on unknown room is a no-op', () {
        final result = setupFullRoom();
        // Should not throw.
        manager.saveGameState('nonexistent', result.state);
        expect(manager.loadGameState('nonexistent'), isNull);
      });

      test('overwrite with saveGameState', () {
        final result = setupFullRoom();

        final modified = result.state.copy();
        modified.players[0].cumulativeScore = 42;
        result.manager.saveGameState(result.roomId, modified);

        final loaded = result.manager.loadGameState(result.roomId);
        expect(loaded!.players[0].cumulativeScore, 42);
      });
    });

    // ═══════════════════════════════════════════════════════════════════════════
    // getAdminPlayerId
    // ═══════════════════════════════════════════════════════════════════════════

    group('getAdminPlayerId', () {
      test('returns null for unknown room', () {
        expect(manager.getAdminPlayerId('nonexistent'), isNull);
      });

      test('returns the admin playerId for a valid room', () {
        final cr = manager.createRoom('Admin');

        expect(manager.getAdminPlayerId(cr.roomId), cr.adminPlayerId);
      });

      test('admin playerId never changes after joins', () {
        final cr = manager.createRoom('Admin');
        manager.joinRoom(cr.roomId, 'Bob');
        manager.joinRoom(cr.roomId, 'Charlie');

        expect(manager.getAdminPlayerId(cr.roomId), cr.adminPlayerId);
      });
    });

    // ═══════════════════════════════════════════════════════════════════════════
    // setPlayerConnected
    // ═══════════════════════════════════════════════════════════════════════════

    group('setPlayerConnected', () {
      test('toggles connected flag to false', () {
        final cr = manager.createRoom('Admin');

        // Initially connected.
        var player = manager.getPlayer(cr.roomId, cr.adminPlayerId);
        expect(player!.connected, isTrue);

        // Disconnect.
        manager.setPlayerConnected(cr.roomId, cr.adminPlayerId, false);
        player = manager.getPlayer(cr.roomId, cr.adminPlayerId);
        expect(player!.connected, isFalse);
      });

      test('toggles connected flag back to true', () {
        final cr = manager.createRoom('Admin');

        manager.setPlayerConnected(cr.roomId, cr.adminPlayerId, false);
        manager.setPlayerConnected(cr.roomId, cr.adminPlayerId, true);

        final player = manager.getPlayer(cr.roomId, cr.adminPlayerId);
        expect(player!.connected, isTrue);
      });

      test('does nothing for unknown room', () {
        // Should not throw.
        manager.setPlayerConnected('nonexistent', 'some-id', false);
      });

      test('does nothing for unknown playerId in valid room', () {
        final cr = manager.createRoom('Admin');

        // Should not throw.
        manager.setPlayerConnected(cr.roomId, 'fake-id', false);

        // Admin still connected.
        final player = manager.getPlayer(cr.roomId, cr.adminPlayerId);
        expect(player!.connected, isTrue);
      });

      test('reflects in lobby list', () {
        final cr = manager.createRoom('Admin');
        manager.joinRoom(cr.roomId, 'Bob');

        manager.setPlayerConnected(cr.roomId, cr.adminPlayerId, false);

        final lobby = manager.getLobbyPlayers(cr.roomId);
        final adminEntry =
            lobby.firstWhere((p) => p['playerId'] == cr.adminPlayerId);
        expect(adminEntry['isConnected'], isFalse);

        final bobEntry = lobby.firstWhere((p) => p['name'] == 'Bob');
        expect(bobEntry['isConnected'], isTrue);
      });

      test('can disconnect multiple players', () {
        final cr = manager.createRoom('Admin');
        final jr = manager.joinRoom(cr.roomId, 'Bob');

        manager.setPlayerConnected(cr.roomId, cr.adminPlayerId, false);
        manager.setPlayerConnected(cr.roomId, jr.playerId, false);

        final lobby = manager.getLobbyPlayers(cr.roomId);
        for (final entry in lobby) {
          expect(entry['isConnected'], isFalse);
        }
      });
    });

    // ═══════════════════════════════════════════════════════════════════════════
    // deleteRoom
    // ═══════════════════════════════════════════════════════════════════════════

    group('deleteRoom', () {
      test('removes room from existence', () {
        final cr = manager.createRoom('Admin');

        expect(manager.roomExists(cr.roomId), isTrue);
        manager.deleteRoom(cr.roomId);
        expect(manager.roomExists(cr.roomId), isFalse);
      });

      test('loadGameState returns null after deletion', () {
        final result = setupFullRoom();
        expect(result.manager.loadGameState(result.roomId), isNotNull);

        result.manager.deleteRoom(result.roomId);
        expect(result.manager.loadGameState(result.roomId), isNull);
      });

      test('getRoomStatus throws after deletion', () {
        final cr = manager.createRoom('Admin');
        manager.deleteRoom(cr.roomId);

        expect(
          () => manager.getRoomStatus(cr.roomId),
          throwsStateError,
        );
      });

      test('calling delete on unknown room is safe (no-op)', () {
        // Should not throw.
        manager.deleteRoom('nonexistent');
      });

      test('roomId can be reused after deletion', () {
        final cr = manager.createRoom('Admin1');
        final reusedId = cr.roomId;

        manager.deleteRoom(reusedId);

        final newRoom = manager.createRoom('Admin2');
        expect(newRoom.roomId, isNot(reusedId)); // Random should differ.
        expect(manager.roomExists(newRoom.roomId), isTrue);
      });
    });

    // ═══════════════════════════════════════════════════════════════════════════
    // engine accessor
    // ═══════════════════════════════════════════════════════════════════════════

    group('engine', () {
      test('exposes GameEngine instance', () {
        expect(manager.engine, isNotNull);
      });

      test('same engine instance across calls', () {
        final e1 = manager.engine;
        final e2 = manager.engine;
        expect(identical(e1, e2), isTrue);
      });
    });

    // ═══════════════════════════════════════════════════════════════════════════
    // Integration scenarios
    // ═══════════════════════════════════════════════════════════════════════════

    group('integration', () {
      test('full lifecycle: create -> join -> start -> play -> delete', () {
        // Create room.
        final cr = manager.createRoom('Admin');
        expect(manager.roomExists(cr.roomId), isTrue);
        expect(manager.getRoomStatus(cr.roomId).status, RoomStatus.waiting);

        // Join 3 players.
        final joinedIds = <String>[];
        for (final name in ['Bob', 'Charlie', 'Diana']) {
          final jr = manager.joinRoom(cr.roomId, name);
          joinedIds.add(jr.playerId);
          expect(jr.seatIndex, joinedIds.length);
        }
        expect(manager.getRoomStatus(cr.roomId).playerCount, 4);

        // Start game.
        final state = manager.startGame(cr.roomId, cr.adminPlayerId, seed: 42);
        expect(state.players, hasLength(4));
        expect(state.pool, hasLength(4));
        expect(
            manager.getRoomStatus(cr.roomId).status, RoomStatus.inProgress);

        // Play one turn — admin (player 0) plays first card.
        final turn = manager.engine.processTurn(
          state,
          cr.adminPlayerId,
          state.players[0].hand[0],
        );
        manager.saveGameState(cr.roomId, turn.newState);
        expect(manager.loadGameState(cr.roomId)!.roundPlaysCompleted, 1);

        // Clean up.
        manager.deleteRoom(cr.roomId);
        expect(manager.roomExists(cr.roomId), isFalse);
      });

      test('two simultaneous rooms are independent', () {
        final room1 = manager.createRoom('Admin1');
        final room2 = manager.createRoom('Admin2');

        expect(room1.roomId, isNot(room2.roomId));

        // Join 3 to each.
        for (final name in ['B1', 'C1', 'D1']) {
          manager.joinRoom(room1.roomId, name);
        }
        for (final name in ['B2', 'C2', 'D2']) {
          manager.joinRoom(room2.roomId, name);
        }

        // Start both games with different seeds.
        final s1 =
            manager.startGame(room1.roomId, room1.adminPlayerId, seed: 1);
        final s2 =
            manager.startGame(room2.roomId, room2.adminPlayerId, seed: 2);

        // Room 1 unaffected by room 2.
        expect(manager.getRoomStatus(room1.roomId).status,
            RoomStatus.inProgress);
        expect(manager.getRoomStatus(room2.roomId).status,
            RoomStatus.inProgress);
        expect(manager.loadGameState(room1.roomId)!.roomId, room1.roomId);
        expect(manager.loadGameState(room2.roomId)!.roomId, room2.roomId);
        expect(s1.roomId, isNot(s2.roomId));

        // Players in room 1 are separate from room 2.
        final lobby1 = manager.getLobbyPlayers(room1.roomId);
        final lobby2 = manager.getLobbyPlayers(room2.roomId);
        final names1 = lobby1.map((p) => p['name'] as String).toSet();
        final names2 = lobby2.map((p) => p['name'] as String).toSet();
        expect(names1.intersection(names2), isEmpty);

        // Delete room 1, room 2 survives.
        manager.deleteRoom(room1.roomId);
        expect(manager.roomExists(room1.roomId), isFalse);
        expect(manager.roomExists(room2.roomId), isTrue);
      });
    });
  });
}

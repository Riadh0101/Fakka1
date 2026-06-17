// ═══════════════════════════════════════════════════════════════════════════════
// StateAdapter — converts engine GameState ↔ UI GameState
// ═══════════════════════════════════════════════════════════════════════════════
//
// The embedded server sends engine-level GameState JSON.
// The Flutter UI consumes UI-level GameState from models/game_state.dart.
// This adapter bridges the two schemas.

import '../models/card.dart' as ui;
import '../models/game_state.dart' as ui;
import '../models/player_state.dart' as ui;
import 'card.dart';
import 'game_engine.dart' as engine;
import 'card_adapter.dart';

class StateAdapter {
  /// Convert an engine state_sync payload to UI GameState for a specific player.
  static ui.GameState fromEngineStateSync(
    Map<String, dynamic> json, {
    required String playerId,
    required String playerName,
    int? seatIndex,
  }) {
    final eState = engine.GameState.fromJson(json);

    return _convert(
      state: eState,
      playerId: playerId,
      playerName: playerName,
      seatIndex: seatIndex,
    );
  }

  /// Convert an engine state_update payload to UI GameState for a player.
  static ui.GameState fromEngineStateUpdate(
    Map<String, dynamic> json, {
    required String playerId,
    required String playerName,
    int? seatIndex,
  }) {
    final eState = engine.GameState.fromJson(json);

    return _convert(
      state: eState,
      playerId: playerId,
      playerName: playerName,
      seatIndex: seatIndex,
    );
  }

  /// Core conversion: engine.GameState → ui.GameState.
  static ui.GameState _convert({
    required engine.GameState state,
    required String playerId,
    required String playerName,
    int? seatIndex,
  }) {
    // Find the local player.
    final myPlayer = state.players.firstWhere(
      (p) => p.id == playerId,
      orElse: () => state.players.first,
    );

    final resolvedSeat = seatIndex ?? myPlayer.seatIndex;

    // Convert hand cards to UI format.
    final myHand = myPlayer.hand.map((c) => toGameCard(c)).toList();

    // Convert pool.
    final poolTop =
        state.pool.isNotEmpty ? toGameCard(state.pool.last) : null;
    final poolSize = state.pool.length;

    // Build opponents list (all players except self).
    final activePlayers = state.players.where((p) => !p.eliminated).toList();
    final activePlayerIds = activePlayers.map((p) => p.id).toSet();
    final currentActiveIdx = activePlayers.isNotEmpty
        ? state.currentPlayerIndex % activePlayers.length
        : 0;
    final currentActivePlayerId = activePlayers.isNotEmpty
        ? activePlayers[currentActiveIdx].id
        : null;

    final opponents = state.players
        .where((p) => p.id != playerId)
        .map((p) {
          final stackTop =
              p.stack.isNotEmpty ? toGameCard(p.stack.last) : null;
          return ui.PlayerGameInfo(
            playerId: p.id,
            name: p.name,
            seatIndex: p.seatIndex,
            stackTop: stackTop,
            handCount: p.handCount ?? p.hand.length,
            cumulativeScore: p.cumulativeScore,
            isActive: p.id == currentActivePlayerId,
            isConnected: p.connected,
            isEliminated: p.eliminated,
          );
        })
        .toList();

    // Build scores map.
    final scores = <String, int>{};
    for (final p in state.players) {
      scores[p.id] = p.cumulativeScore;
    }

    // Determine if it's my turn.
    final isMyTurn = myPlayer.id == currentActivePlayerId;

    // Lobby players (used in waiting state).
    final lobbyPlayers = state.players
        .map((p) => ui.PlayerInfo(
              playerId: p.id,
              name: p.name,
              seatIndex: p.seatIndex,
              isConnected: p.connected,
              isEliminated: p.eliminated,
            ))
        .toList();

    return ui.GameState(
      roomId: state.roomId,
      playerId: playerId,
      playerName: playerName,
      seatIndex: resolvedSeat,
      roomStatus: state.gameOver
          ? 'finished'
          : (state.roundCount > 0 ? 'in_progress' : 'waiting'),
      lobbyPlayers: lobbyPlayers,
      myHand: myHand,
      poolTop: poolTop,
      poolSize: poolSize,
      opponents: opponents,
      currentPlayerSeat: activePlayers.isNotEmpty
          ? activePlayers[currentActiveIdx].seatIndex
          : -1,
      isMyTurn: isMyTurn,
      scores: scores,
      roundNumber: state.roundCount,
      gameOver: state.gameOver,
    );
  }

  /// Build game over rankings from engine state.
  static List<ui.Ranking> buildRankings(engine.GameState state) {
    final sorted = [...state.players]
      ..sort((a, b) => (a.rankEarned ?? 99) - (b.rankEarned ?? 99));

    return sorted
        .map((p) => ui.Ranking(
              playerId: p.id,
              name: p.name,
              seatIndex: p.seatIndex,
              totalScore: p.cumulativeScore,
              rank: p.rankEarned ?? 99,
            ))
        .toList();
  }

  /// Build round-end scores from engine state (returns List of player score maps).
  static List<Map<String, dynamic>> buildRoundScores(engine.GameState state) {
    return state.players.map((p) => {
          'playerId': p.id,
          'name': p.name,
          'cumulativeScore': p.cumulativeScore,
          'rankEarned': p.rankEarned,
          'eliminated': p.eliminated,
        }).toList();
  }

  /// Parse capture event data from server to UI-friendly format.
  static Map<String, dynamic>? parseCaptureEvent(Map<String, dynamic> data) {
    final cardsJson = <Map<String, dynamic>>[];
    final poolCaptured = data['poolCaptured'] as List<dynamic>?;
    if (poolCaptured != null) {
      for (final c in poolCaptured) {
        cardsJson.add(toGameCard(Card.fromJson(c as Map<String, dynamic>)).toJson());
      }
    }
    final stolenFrom = data['stolenFrom'] as List<dynamic>?;
    if (stolenFrom != null) {
      for (final entry in stolenFrom) {
        final em = entry as Map<String, dynamic>;
        final cards = em['cards'] as List<dynamic>?;
        if (cards != null) {
          for (final c in cards) {
            cardsJson.add(
                toGameCard(Card.fromJson(c as Map<String, dynamic>)).toJson());
          }
        }
      }
    }

    return {
      'capturingPlayerId': data['activePlayerId'],
      'capturedCards': cardsJson,
      'action': data['action'],
    };
  }
}

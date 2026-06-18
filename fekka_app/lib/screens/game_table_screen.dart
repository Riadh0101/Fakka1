import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/game_state.dart';
import '../models/player_state.dart';
import '../providers/game_provider.dart';
import '../widgets/hand_widget.dart';
import '../widgets/middle_pool_widget.dart';
import '../widgets/player_position_widget.dart';
import '../widgets/turn_indicator.dart';
import 'score_summary_screen.dart';
import 'game_over_screen.dart';

/// Core gameplay screen displaying 4 positions around the pool.
///
/// Layout adapts to portrait/landscape orientations.
class GameTableScreen extends ConsumerStatefulWidget {
  const GameTableScreen({super.key});

  @override
  ConsumerState<GameTableScreen> createState() => _GameTableScreenState();
}

class _GameTableScreenState extends ConsumerState<GameTableScreen> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(gameProvider);

    // Listen for navigation triggers (round_end / game_over)
    ref.listen<GameState>(gameProvider, (prev, next) {
      if (next.roundScores != null && !next.gameOver &&
          prev?.roundScores == null) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ScoreSummaryScreen()),
        );
      }
      if (next.gameOver && next.finalRankings.isNotEmpty &&
          !(prev?.gameOver ?? false)) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const GameOverScreen()),
          (route) => route.isFirst,
        );
      }
    });

    // Organize opponents by position relative to the player
    final opponents = _getPositionedOpponents(state);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 1.2,
            colors: [
              Color(0xFF0D2E1F), // green felt center
              Color(0xFF0A1A2E), // dark edge
            ],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              // Main game table
              Column(
                children: [
                  // Top bar: round + scores
                  _buildTopBar(state),
                  // Game area
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth > 500;
                        return isWide
                            ? _buildWideLayout(opponents, state)
                            : _buildTallLayout(opponents, state);
                      },
                    ),
                  ),
                  // Bottom: my hand
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Turn indicator centered
                        Center(
                          child: TurnIndicator(
                            isMyTurn: state.isMyTurn,
                            activePlayerName:
                                _getActivePlayerName(state),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Player label
                        Text(
                          'أنت  ·  ${state.playerName ?? ""}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        // Hand cards
                        HandWidget(
                          cards: state.myHand,
                          isMyTurn: state.isMyTurn,
                          onCardTap: (index) {
                            ref.read(gameProvider.notifier).playCard(index);
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // Reconnecting overlay
              if (state.isReconnecting || !state.isConnected)
                _buildReconnectingOverlay(state),

              // Error snackbar listener
              if (state.errorMessage != null)
                Positioned(
                  bottom: 100,
                  left: 24,
                  right: 24,
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade800,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        state.errorMessage!,
                        style: const TextStyle(color: Colors.white),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- Layout Builders ----

  Widget _buildTallLayout(
    Map<String, PlayerGameInfo?> opponents,
    GameState state,
  ) {
    // Portrait: top player2+3, middle pool, bottom-left player1, bottom-right=you
    return Column(
      children: [
        const SizedBox(height: 8),
        // Top row: Player 2 (left) and Player 3 (right)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              if (opponents['topLeft'] != null)
                PlayerPositionWidget(
                  label: 'اللاعب 2',
                  player: opponents['topLeft']!,
                  isActive: opponents['topLeft']!.seatIndex ==
                      state.currentPlayerSeat,
                ),
              if (opponents['topRight'] != null)
                PlayerPositionWidget(
                  label: 'اللاعب 3',
                  player: opponents['topRight']!,
                  isActive: opponents['topRight']!.seatIndex ==
                      state.currentPlayerSeat,
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Middle pool
        Expanded(
          child: Center(
            child: MiddlePoolWidget(
              topCard: state.poolTop,
              poolSize: state.poolSize,
            ),
          ),
        ),
        // Bottom row: Player 1 (left) + you area is in the hand section
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: opponents['bottomLeft'] != null
                ? PlayerPositionWidget(
                    label: 'اللاعب 1',
                    player: opponents['bottomLeft']!,
                    isActive:
                        opponents['bottomLeft']!.seatIndex ==
                            state.currentPlayerSeat,
                  )
                : const SizedBox.shrink(),
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _buildWideLayout(
    Map<String, PlayerGameInfo?> opponents,
    GameState state,
  ) {
    return Row(
      children: [
        // Left column: Player 1 + Player 2
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (opponents['topLeft'] != null)
                PlayerPositionWidget(
                  label: 'اللاعب 2',
                  player: opponents['topLeft']!,
                  isActive:
                      opponents['topLeft']!.seatIndex == state.currentPlayerSeat,
                ),
              const SizedBox(height: 16),
              if (opponents['bottomLeft'] != null)
                PlayerPositionWidget(
                  label: 'Player 1',
                  player: opponents['bottomLeft']!,
                  isActive: opponents['bottomLeft']!.seatIndex ==
                      state.currentPlayerSeat,
                ),
            ],
          ),
        ),
        // Center pool
        Expanded(
          child: Center(
            child: MiddlePoolWidget(
              topCard: state.poolTop,
              poolSize: state.poolSize,
            ),
          ),
        ),
        // Right column: Player 3
        Expanded(
          child: Center(
            child: opponents['topRight'] != null
                ? PlayerPositionWidget(
                    label: 'اللاعب 3',
                    player: opponents['topRight']!,
                    isActive: opponents['topRight']!.seatIndex ==
                        state.currentPlayerSeat,
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }

  Widget _buildTopBar(GameState state) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Round number
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'الجولة ${state.roundNumber}',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // Pool count compact
          Text(
            'المجمع: ${state.poolSize}',
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 12,
            ),
          ),
          // Room code
          Text(
            state.roomId ?? '',
            style: const TextStyle(
              color: Colors.white24,
              fontSize: 11,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReconnectingOverlay(GameState state) {
    return Container(
      color: Colors.black.withOpacity(0.7),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (state.isReconnecting) ...[
              const SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                  color: Color(0xFFE94560),
                  strokeWidth: 3,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'جاري إعادة الاتصال...',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ] else ...[
              const Icon(Icons.cloud_off, color: Colors.white54, size: 48),
              const SizedBox(height: 16),
              const Text(
                'انقطع الاتصال',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  ref.read(gameProvider.notifier).clearError();
                  Navigator.of(context).popUntil((r) => r.isFirst);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE94560),
                  foregroundColor: Colors.white,
                ),
                child: const Text('مغادرة اللعبة'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ---- Helpers ----

  /// Maps opponent positions around the table relative to the player's seat.
  Map<String, PlayerGameInfo?> _getPositionedOpponents(GameState state) {
    final mySeat = state.seatIndex ?? -1;
    final all = state.opponents;

    // Seats around the table: 0=bottom(player), 1=left, 2=top, 3=right
    // We rotate so that mySeat is at bottom.

    // Build a seat-indexed map of opponents
    final seatMap = <int, PlayerGameInfo>{};
    for (final opp in all) {
      seatMap[opp.seatIndex] = opp;
    }

    // Map absolute seats to relative positions.
    // relativeSeat = (absoluteSeat - mySeat + 4) % 4
    int rel(int absoluteSeat) => (absoluteSeat - mySeat + 4) % 4;

    return {
      // rel 0 = bottom = you (not an opponent)
      'bottomLeft': seatMap.entries
          .where((e) => rel(e.key) == 1)
          .map((e) => e.value)
          .firstOrNull,
      'topLeft': seatMap.entries
          .where((e) => rel(e.key) == 2)
          .map((e) => e.value)
          .firstOrNull,
      'topRight': seatMap.entries
          .where((e) => rel(e.key) == 3)
          .map((e) => e.value)
          .firstOrNull,
    };
  }

  String _getActivePlayerName(GameState state) {
    if (state.currentPlayerSeat == state.seatIndex) {
      return state.playerName ?? 'أنت';
    }
    final active = state.opponents
        .where((o) => o.seatIndex == state.currentPlayerSeat)
        .firstOrNull;
    return active?.name ?? '...';
  }
}

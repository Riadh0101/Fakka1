import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/game_provider.dart';

/// Final rankings screen shown when the game ends.
///
/// Displays player rankings with trophy icons and a "Play Again" button.
class GameOverScreen extends ConsumerWidget {
  const GameOverScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gameProvider);
    final rankings = state.finalRankings;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF1A1A2E),
              Color(0xFF16213E),
              Color(0xFF0F3460),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 20),
                  // Trophy / title
                  const Icon(
                    Icons.emoji_events,
                    size: 64,
                    color: Colors.amber,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'انتهت اللعبة!',
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'بعد ${state.roundNumber} جولات',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Rankings
                  ...List.generate(rankings.length, (i) {
                    final rank = rankings[i];
                    final isFirst = rank.rank == 1;
                    final isMe = rank.playerId == state.playerId;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 14),
                      decoration: BoxDecoration(
                        gradient: isFirst
                            ? LinearGradient(
                                colors: [
                                  Colors.amber.withOpacity(0.3),
                                  Colors.amber.withOpacity(0.08),
                                ],
                              )
                            : null,
                        color: isFirst ? null : Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isFirst
                              ? Colors.amber.withOpacity(0.5)
                              : isMe
                                  ? const Color(0xFFE94560).withOpacity(0.4)
                                  : Colors.white.withOpacity(0.1),
                          width: isFirst ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          // Rank icon
                          _RankIcon(rank: rank.rank),
                          const SizedBox(width: 14),
                          // Name
                          Expanded(
                            child: Text(
                              rank.name,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: isMe
                                    ? const Color(0xFFFF6B6B)
                                    : Colors.white,
                              ),
                            ),
                          ),
                          // Score
                          Text(
                            rank.totalScore.toString(),
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              color: isFirst
                                  ? Colors.amber
                                  : Colors.white.withOpacity(0.8),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            'نقطة',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white38,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),

                  const SizedBox(height: 32),

                  // Play Again button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () {
                        ref.read(gameProvider.notifier).clearError();
                        Navigator.of(context)
                            .popUntil((route) => route.isFirst);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE94560),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 4,
                      ),
                      child: const Text(
                        'العب مرة أخرى',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RankIcon extends StatelessWidget {
  final int rank;
  const _RankIcon({required this.rank});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;

    switch (rank) {
      case 1:
        icon = Icons.emoji_events;
        color = Colors.amber;
        break;
      case 2:
        icon = Icons.emoji_events;
        color = const Color(0xFFB0BEC5); // silver
        break;
      case 3:
        icon = Icons.emoji_events;
        color = const Color(0xFF8D6E63); // bronze
        break;
      default:
        return Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withOpacity(0.08),
          ),
          child: Center(
            child: Text(
              '$rank',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Colors.white38,
              ),
            ),
          ),
        );
    }

    return Icon(icon, color: color, size: 36);
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/game_provider.dart';

/// Round score summary — shown after each round ends.
///
/// Auto-dismisses after 5 seconds or when the user taps "Continue".
class ScoreSummaryScreen extends ConsumerStatefulWidget {
  const ScoreSummaryScreen({super.key});

  @override
  ConsumerState<ScoreSummaryScreen> createState() =>
      _ScoreSummaryScreenState();
}

class _ScoreSummaryScreenState extends ConsumerState<ScoreSummaryScreen> {
  Timer? _autoDismissTimer;

  @override
  void initState() {
    super.initState();
    _autoDismissTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) _dismiss();
    });
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    super.dispose();
  }

  void _dismiss() {
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(gameProvider);
    final roundScores = state.roundScores ?? {};
    final cumulativeScores = state.scores;

    // Build sorted player entries
    final entries = <_PlayerScoreEntry>[];
    for (final player in state.opponents) {
      entries.add(_PlayerScoreEntry(
        name: player.name,
        roundScore: roundScores[player.playerId] ?? 0,
        totalScore: cumulativeScores[player.playerId] ?? 0,
      ));
    }
    // Add self
    final myRoundScore = roundScores[state.playerId] ?? 0;
    final myTotalScore = cumulativeScores[state.playerId] ?? 0;
    entries.add(_PlayerScoreEntry(
      name: state.playerName ?? 'You',
      roundScore: myRoundScore,
      totalScore: myTotalScore,
      isMe: true,
    ));

    // Sort by total score descending
    entries.sort((a, b) => b.totalScore.compareTo(a.totalScore));

    return Scaffold(
      backgroundColor: Colors.black.withOpacity(0.85),
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Title
                Text(
                  'Round ${state.roundNumber} Results',
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 24),

                // Score cards
                ...List.generate(entries.length, (i) {
                  final entry = entries[i];
                  final isBest = i == 0;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: entry.isMe
                          ? const Color(0xFFE94560).withOpacity(0.15)
                          : Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: entry.isMe
                            ? const Color(0xFFE94560).withOpacity(0.4)
                            : Colors.white.withOpacity(0.1),
                        width: entry.isMe ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        // Rank
                        Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: isBest
                                ? Colors.amber
                                : Colors.white38,
                          ),
                        ),
                        const SizedBox(width: 14),
                        // Name
                        Expanded(
                          child: Text(
                            entry.name,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: entry.isMe
                                  ? const Color(0xFFFF6B6B)
                                  : Colors.white,
                            ),
                          ),
                        ),
                        // Round score
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '+${entry.roundScore}',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF4ADE80),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 16),
                        // Total score
                        SizedBox(
                          width: 48,
                          child: Text(
                            entry.totalScore.toString(),
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: Colors.white.withOpacity(0.9),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),

                const SizedBox(height: 28),

                // Continue button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _dismiss,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE94560),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Continue',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Auto-continuing in a few seconds...',
                  style: TextStyle(color: Colors.white24, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayerScoreEntry {
  final String name;
  final int roundScore;
  final int totalScore;
  final bool isMe;

  const _PlayerScoreEntry({
    required this.name,
    required this.roundScore,
    required this.totalScore,
    this.isMe = false,
  });
}

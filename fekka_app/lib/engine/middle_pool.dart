// ═══════════════════════════════════════════════════════════════════════════════
// MiddlePool — the shared LIFO pool with sequential reveal capture
// ═══════════════════════════════════════════════════════════════════════════════
// Ported 1:1 from middle-pool.ts

import 'card.dart';
import 'player_stack.dart';

/// The shared pool in the middle of the table.
///
/// Extends [PlayerStack] with sequential reveal: when a played card matches
/// the pool's top, capture it and check the newly-exposed top. Continue
/// while ranks match — the cascade can capture multiple same-rank cards.
class MiddlePool extends PlayerStack {
  /// Capture cards from the top whose rank matches [playedRank].
  ///
  /// SEQUENTIAL REVEAL ALGORITHM:
  /// 1. Examine pool's current top card.
  /// 2. If pool empty → STOP.
  /// 3. If top.rank == playedRank → pop it, add to captured, GO TO 2.
  /// 4. If top.rank != playedRank → STOP.
  ///
  /// Returns cards in capture order (first = original pool top, last = deepest match).
  List<Card> sequentialReveal(String playedRank) {
    final captured = <Card>[];

    while (!isEmpty) {
      final top = peekTop()!;
      if (top.rank == playedRank) {
        captured.add(pop());
      } else {
        break;
      }
    }

    return captured;
  }
}

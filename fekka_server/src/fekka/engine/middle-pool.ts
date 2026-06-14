// ═══════════════════════════════════════════════════════════════════════════════
// MiddlePool — the shared LIFO pool in the center of the table
// ═══════════════════════════════════════════════════════════════════════════════

import { Card } from './card.js';
import { PlayerStack } from './player-stack.js';

/**
 * The shared pool in the middle of the table.
 *
 * Extends PlayerStack with the "sequential reveal" capture mechanic:
 * when a played card matches the pool's top card, capture it and then
 * check the newly-exposed top. Continue capturing while ranks match.
 *
 * The sequential reveal is the signature mechanic of Fekka: it causes
 * cascading captures where playing a matching rank on a pool with
 * multiple consecutive same-rank cards at the top will capture all of them.
 */
export class MiddlePool extends PlayerStack {
  /**
   * Capture cards from the top of the pool whose rank matches `playedRank`.
   *
   * SEQUENTIAL REVEAL ALGORITHM (step-by-step):
   *
   *   Step 1. Examine the pool's current top card.
   *   Step 2. If the pool is empty → STOP. Return the captured list.
   *   Step 3. If top.rank === playedRank → pop it, add to captured list, GO TO Step 2.
   *   Step 4. If top.rank !== playedRank → STOP. Return the captured list.
   *   Step 5. This loop repeats, checking the NEW top card after each pop,
   *           until the first non-matching rank is exposed or the pool becomes empty.
   *
   * The returned list is in **capture order**:
   *   - first element = first popped (was the original pool top)
   *   - last element = last popped (deepest matching card exposed by the cascade)
   *
   * @param playedRank - The rank of the card the player just played.
   * @returns Array of captured cards in cascade order (top→deep).
   */
  sequentialReveal(playedRank: string): Card[] {
    const captured: Card[] = [];

    // Loop: check the pool top, capture if rank matches, repeat.
    while (!this.isEmpty) {
      const top = this.peekTop()!;
      if (top.rank === playedRank) {
        // Pop the matching card and add it to the captured pile.
        captured.push(this.pop());
        // Continue to check the newly-exposed top card.
      } else {
        // Non-matching rank exposed — stop the cascade.
        break;
      }
    }

    return captured;
  }
}

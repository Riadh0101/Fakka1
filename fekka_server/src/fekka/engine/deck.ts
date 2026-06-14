// ═══════════════════════════════════════════════════════════════════════════════
// Deck — a 40-card Italian deck with shuffle, deal, and recycle
// ═══════════════════════════════════════════════════════════════════════════════

import { Card, RANKS, SUITS, makeCard, cardKey } from './card.js';

/**
 * Simple seeded PRNG (mulberry32) for deterministic shuffles.
 * Mirrors Python's random.Random(seed) behavior for test compatibility.
 */
function mulberry32(seed: number): () => number {
  let state = seed | 0;
  return () => {
    state = (state + 0x6d2b79f5) | 0;
    let t = Math.imul(state ^ (state >>> 15), 1 | state);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** Fisher-Yates shuffle using a provided random function. */
function shuffleArray<T>(arr: T[], rand: () => number): void {
  for (let i = arr.length - 1; i > 0; i--) {
    const j = Math.floor(rand() * (i + 1));
    [arr[i], arr[j]] = [arr[j], arr[i]];
  }
}

/**
 * A 40-card Italian deck.
 *
 * Contains: all combinations of 4 suits × 10 ranks.
 * Supports seeded shuffling for deterministic testing.
 */
export class Deck {
  private _cards: Card[];
  private _seed: number | null;
  private _shuffleCount: number;

  /**
   * Construct and shuffle a new 40-card deck.
   * @param seed Optional seed for deterministic shuffle.
   */
  constructor(seed?: number) {
    this._cards = [];
    this._seed = seed ?? null;
    this._shuffleCount = 0;
    this._build();
    this.shuffle(seed);
  }

  /** Build the 40-card deck: each rank × each suit. */
  private _build(): void {
    this._cards = [];
    for (const r of RANKS) {
      for (const s of SUITS) {
        this._cards.push(makeCard(r, s));
      }
    }
  }

  /**
   * Shuffle the deck. Optional seed for deterministic testing.
   *
   * When no seed is explicitly provided but the deck was constructed
   * with one, the effective seed is `storedSeed + shuffleCount` so that
   * each shuffle call produces a different deterministic ordering
   * (prevents identical recycles).
   */
  shuffle(seed?: number): void {
    let effectiveSeed: number | undefined = seed;
    if (effectiveSeed === undefined && this._seed !== null) {
      effectiveSeed = this._seed + this._shuffleCount;
    }
    if (effectiveSeed !== undefined) {
      const rand = mulberry32(effectiveSeed);
      shuffleArray(this._cards, rand);
    } else {
      // No seed at all → use Math.random (non-deterministic).
      shuffleArray(this._cards, Math.random);
    }
    this._shuffleCount++;
  }

  /**
   * Deal `n` cards from the top of the deck.
   * "Top" = end of the array, so we pop from the back.
   * @throws If the deck has fewer than `n` cards.
   */
  deal(n: number): Card[] {
    if (n > this._cards.length) {
      throw new Error(
        `Deck has only ${this._cards.length} cards, cannot deal ${n}`,
      );
    }
    const dealt: Card[] = [];
    for (let i = 0; i < n; i++) {
      dealt.push(this._cards.pop()!);
    }
    return dealt;
  }

  /**
   * Gather all non-excluded cards into the deck and reshuffle.
   *
   * Used when the reserve is exhausted: the caller empties the
   * Middle Pool and passes those cards as `availableCards` along with
   * whatever remains in the deck. Player-stack cards are `excludedCards`
   * (they remain "held" by players and are NOT recycled).
   *
   * @param availableCards Cards gathered from the pool to be recycled.
   * @param excludedCards Cards to exclude (player-stack cards, which stay held).
   */
  recycle(availableCards: Card[], excludedCards: Card[]): void {
    // Build a Set of unique card keys for exact exclusion matching.
    // We use cardKey (rank|suit) because rank-only equality would
    // falsely deduplicate different-suited same-rank cards.
    const excludedSet = new Set<string>(
      excludedCards.map((c) => cardKey(c)),
    );

    // Gather: available external cards + current deck remainder,
    // filtering out any excluded (held) cards.
    const gathered: Card[] = [];
    for (const c of availableCards) {
      if (!excludedSet.has(cardKey(c))) {
        gathered.push(c);
      }
    }
    for (const c of this._cards) {
      if (!excludedSet.has(cardKey(c))) {
        gathered.push(c);
      }
    }

    this._cards = gathered;
    // Shuffle with auto-incremented seed derivative for deterministic variety.
    this.shuffle();
  }

  /** Number of cards left in the deck. */
  get remaining(): number {
    return this._cards.length;
  }

  /** Raw access to cards (for serialization). */
  get cards(): readonly Card[] {
    return this._cards;
  }

  /** Replace cards (for deserialization from Redis). */
  setCards(cards: Card[]): void {
    this._cards = [...cards];
  }
}

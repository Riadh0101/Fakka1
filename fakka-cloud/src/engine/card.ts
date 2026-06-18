// ═══════════════════════════════════════════════════════════════════════════════
// Card — the fundamental unit of the Fekka game
// ═══════════════════════════════════════════════════════════════════════════════

/** The 10 ranks of the 40-card Italian deck. */
export const RANKS: readonly string[] = ['1', '2', '3', '4', '5', '6', '7', 'J', 'Q', 'K'];

/** The 4 suits of the 40-card Italian deck. */
export const SUITS: readonly string[] = ['♠', '♣', '♥', '♦'];

/** Ranks that are face cards (J, Q, K) — worth 2 points each. */
export const FACE_RANKS: ReadonlySet<string> = new Set(['J', 'Q', 'K']);

/**
 * A single Italian playing card.
 *
 * Equality is rank-only for game matching purposes (a 7♠ matches a 7♣).
 * Use exactMatch() when suit identity is needed (deck uniqueness).
 */
export interface Card {
  readonly rank: string;
  readonly suit: string;
}

// ── Factory ──────────────────────────────────────────────────────────────────

/**
 * Create a new Card instance.
 * Convenience factory for readability.
 */
export function makeCard(rank: string, suit: string): Card {
  return { rank, suit };
}

// ── Utility functions ────────────────────────────────────────────────────────

/**
 * Point value of a card.
 * Face cards (J, Q, K) = 2 points.
 * Numerals (1–7) = 1 point.
 */
export function pointValue(card: Card): number {
  return FACE_RANKS.has(card.rank) ? 2 : 1;
}

/**
 * Rank-only equality matching.
 * Two cards are "equal" for game purposes if they share the same rank.
 */
export function cardsEqual(a: Card, b: Card): boolean {
  return a.rank === b.rank;
}

/**
 * Exact identity comparison (rank AND suit).
 * Used for deck uniqueness — a 7♠ and 7♣ are different cards in the deck.
 */
export function exactMatch(a: Card, b: Card): boolean {
  return a.rank === b.rank && a.suit === b.suit;
}

/**
 * Create a unique string key for exact card identity.
 * Used for Set/Map lookups that need suit-level distinction.
 */
export function cardKey(card: Card): string {
  return `${card.rank}|${card.suit}`;
}

/**
 * Human-readable string representation of a card.
 * Example: "7♠", "K♥"
 */
export function cardToString(card: Card): string {
  return `${card.rank}${card.suit}`;
}

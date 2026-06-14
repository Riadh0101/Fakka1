// ═══════════════════════════════════════════════════════════════════════════════
// PlayerStack — LIFO card stack (private stacks & base for Middle Pool)
// ═══════════════════════════════════════════════════════════════════════════════

import { Card, pointValue } from './card.js';

/**
 * A private LIFO (last-in-first-out) card stack.
 *
 * Index 0 = bottom of stack, index -1 (last element) = top.
 *
 * Used for:
 *  - Each player's private captured-card stack
 *  - Base class for the Middle Pool
 */
export class PlayerStack {
  protected _cards: Card[];

  constructor() {
    this._cards = [];
  }

  // ── Core operations ──────────────────────────────────────────────────────

  /** Push a single card onto the top of the stack. */
  push(card: Card): void {
    this._cards.push(card);
  }

  /**
   * Push multiple cards in order.
   * First card in the list → bottom-most of the batch.
   * Last card in the list → new top of the stack.
   */
  pushMany(cards: Card[]): void {
    for (const c of cards) {
      this._cards.push(c);
    }
  }

  /** Remove and return the top card. Throws if empty. */
  pop(): Card {
    if (this._cards.length === 0) {
      throw new Error('Cannot pop from empty stack');
    }
    return this._cards.pop()!;
  }

  /** Return the top card without removing it, or null if empty. */
  peekTop(): Card | null {
    return this._cards.length > 0 ? this._cards[this._cards.length - 1] : null;
  }

  /**
   * Return the full contents of the stack (bottom-to-top order)
   * and clear the stack. Used when an opponent steals your stack.
   */
  stealAll(): Card[] {
    const cards = [...this._cards];
    this._cards = [];
    return cards;
  }

  /** Return a copy of all cards without modifying the stack. */
  peekAll(): Card[] {
    return [...this._cards];
  }

  // ── Scoring & queries ────────────────────────────────────────────────────

  /** Sum the point values of all cards in this stack. */
  score(): number {
    return this._cards.reduce((sum, c) => sum + pointValue(c), 0);
  }

  get isEmpty(): boolean {
    return this._cards.length === 0;
  }

  get size(): number {
    return this._cards.length;
  }

  // ── Serialization helpers ────────────────────────────────────────────────

  /** Return all cards (for serialization). */
  get cards(): readonly Card[] {
    return this._cards;
  }

  /** Replace internal cards (for deserialization). */
  setCards(cards: Card[]): void {
    this._cards = [...cards];
  }
}

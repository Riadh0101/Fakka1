// ═══════════════════════════════════════════════════════════════════════════════
// CardAdapter — converts between UI GameCard and engine Card models
// ═══════════════════════════════════════════════════════════════════════════════

import '../models/card.dart' as ui;
import 'card.dart' as engine;

/// Convert engine [engine.Card] → UI [ui.GameCard].
ui.GameCard toGameCard(engine.Card ec) {
  return ui.GameCard(
    rank: _rankToInt(ec.rank),
    suit: _suitToWord(ec.suit),
    pointValue: ec.pointValue,
    faceUp: true,
  );
}

/// Convert UI [ui.GameCard] → engine [engine.Card].
engine.Card toEngineCard(ui.GameCard gc) {
  return engine.Card(
    rank: _rankToString(gc.rank),
    suit: _suitToSymbol(gc.suit),
  );
}

/// Convert engine rank string → UI rank int.
int _rankToInt(String rank) {
  switch (rank) {
    case '1': return 1;
    case '2': return 2;
    case '3': return 3;
    case '4': return 4;
    case '5': return 5;
    case '6': return 6;
    case '7': return 7;
    case 'J': return 11;
    case 'Q': return 12;
    case 'K': return 13;
    default: return int.tryParse(rank) ?? 1;
  }
}

/// Convert UI rank int → engine rank string.
String _rankToString(int rank) {
  switch (rank) {
    case 1: return '1';
    case 2: return '2';
    case 3: return '3';
    case 4: return '4';
    case 5: return '5';
    case 6: return '6';
    case 7: return '7';
    case 11: return 'J';
    case 12: return 'Q';
    case 13: return 'K';
    default: return rank.toString();
  }
}

/// Convert engine suit symbol → UI suit word.
String _suitToWord(String suit) {
  switch (suit) {
    case '\u2660': return 'spades';   // ♠
    case '\u2663': return 'clubs';    // ♣
    case '\u2665': return 'hearts';   // ♥
    case '\u2666': return 'diamonds'; // ♦
    default: return suit;
  }
}

/// Convert UI suit word → engine suit symbol.
String _suitToSymbol(String suit) {
  switch (suit.toLowerCase()) {
    case 'spades': return '\u2660';
    case 'clubs': return '\u2663';
    case 'hearts': return '\u2665';
    case 'diamonds': return '\u2666';
    default: return suit;
  }
}

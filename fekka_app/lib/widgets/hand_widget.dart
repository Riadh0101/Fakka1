import 'package:flutter/material.dart';
import '../models/card.dart';
import 'card_widget.dart';

/// Displays the current player's hand of cards.
///
/// Cards are laid out in a horizontal row. If [isMyTurn] is true,
/// cards are tappable and slightly elevated. The [onCardTap] callback
/// receives the index of the tapped card.
class HandWidget extends StatelessWidget {
  final List<GameCard> cards;
  final bool isMyTurn;
  final void Function(int index)? onCardTap;

  const HandWidget({
    super.key,
    required this.cards,
    this.isMyTurn = false,
    this.onCardTap,
  });

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) {
      return const SizedBox(
        height: 90,
        child: Center(
          child: Text(
            'No cards in hand',
            style: TextStyle(color: Colors.white38, fontSize: 13),
          ),
        ),
      );
    }

    return SizedBox(
      height: 100,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(cards.length, (i) {
          final card = cards[i];
          return Padding(
            padding: EdgeInsets.only(
              left: i > 0 ? -12 : 0, // slight overlap
            ),
            child: CardWidget(
              card: card,
              width: 60,
              height: 90,
              elevated: isMyTurn,
              onTap: isMyTurn && onCardTap != null
                  ? () => onCardTap!(i)
                  : null,
            ),
          );
        }),
      ),
    );
  }
}

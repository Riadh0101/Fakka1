import 'package:flutter/material.dart';
import '../models/card.dart';

/// Renders a single playing card.
///
/// When [faceUp] is true, shows rank in top-left, suit symbol in center.
/// When false, shows a dark patterned back.
/// If [onTap] is provided, the card is tappable with a slight elevation.
class CardWidget extends StatelessWidget {
  final GameCard card;
  final VoidCallback? onTap;
  final double width;
  final double height;
  final bool elevated;

  const CardWidget({
    super.key,
    required this.card,
    this.onTap,
    this.width = 60,
    this.height = 90,
    this.elevated = false,
  });

  @override
  Widget build(BuildContext context) {
    final isRed = card.suit == 'hearts' || card.suit == 'diamonds';
    final textColor = isRed ? Colors.red : Colors.black;

    final child = GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: width,
        height: height,
        margin: elevated
            ? const EdgeInsets.only(bottom: 8)
            : EdgeInsets.zero,
        decoration: BoxDecoration(
          color: card.faceUp ? const Color(0xFFFFF8E7) : const Color(0xFF1E3A5F),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: elevated
                ? Colors.amber.withOpacity(0.8)
                : Colors.black26,
            width: elevated ? 2 : 0.5,
          ),
          boxShadow: [
            BoxShadow(
              color: elevated
                  ? Colors.amber.withOpacity(0.4)
                  : Colors.black.withOpacity(0.2),
              blurRadius: elevated ? 10 : 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: card.faceUp ? _buildFaceUp(textColor) : _buildFaceDown(),
      ),
    );

    return child;
  }

  Widget _buildFaceUp(Color textColor) {
    return Stack(
      children: [
        // Rank in top-left
        Positioned(
          top: 4,
          left: 6,
          child: Text(
            card.rankString,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: textColor,
              height: 1,
            ),
          ),
        ),
        // Suit in center
        Center(
          child: Text(
            card.suitSymbol,
            style: TextStyle(
              fontSize: 22,
              color: textColor,
              height: 1,
            ),
          ),
        ),
        // Rank in bottom-right (inverted)
        Positioned(
          bottom: 4,
          right: 6,
          child: Transform.rotate(
            angle: 3.14159,
            child: Text(
              card.rankString,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: textColor,
                height: 1,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFaceDown() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2C5282), Color(0xFF1A365D)],
        ),
      ),
      child: Center(
        child: Container(
          width: width * 0.6,
          height: height * 0.6,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: const Color(0xFF4A90D9).withOpacity(0.5),
              width: 1.5,
            ),
          ),
          child: const Icon(
            Icons.casino,
            color: Color(0xFF4A90D9),
            size: 18,
          ),
        ),
      ),
    );
  }
}

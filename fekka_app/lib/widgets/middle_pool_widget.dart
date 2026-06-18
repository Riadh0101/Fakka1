import 'package:flutter/material.dart';
import '../models/card.dart';
import 'card_widget.dart';

/// Displays the center pool on the game table.
///
/// Shows the top card face-up and a badge with the total card count.
class MiddlePoolWidget extends StatelessWidget {
  final GameCard? topCard;
  final int poolSize;

  const MiddlePoolWidget({
    super.key,
    this.topCard,
    this.poolSize = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'المجمع',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Colors.white38,
            letterSpacing: 3,
          ),
        ),
        const SizedBox(height: 6),
        // Pool cards visual
        if (topCard != null && poolSize > 0)
          _buildPoolStack()
        else
          SizedBox(
            width: 60,
            height: 90,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.white.withOpacity(0.2),
                  style: BorderStyle.solid,
                ),
                color: Colors.white.withOpacity(0.03),
              ),
              child: const Center(
                child: Icon(Icons.inbox_outlined,
                    color: Colors.white24, size: 28),
              ),
            ),
          ),
        const SizedBox(height: 6),
        // Count badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '$poolSize ${poolSize == 1 ? 'ورقة' : 'ورقات'}',
            style: const TextStyle(
              fontSize: 12,
              color: Colors.white70,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPoolStack() {
    // Show up to 3 shadow cards behind the top card for depth effect
    final shadowCount = (poolSize - 1).clamp(0, 3);
    return SizedBox(
      width: 80,
      height: 100,
      child: Stack(
        children: [
          // Shadow cards behind the top card
          if (poolSize > 1)
            ...List.generate(shadowCount, (i) {
              return Positioned(
                top: (i + 1) * 3.0,
                left: (i + 1) * 3.0,
                  child: CardWidget(
                    card: GameCard(
                        rank: 0, suit: '', pointValue: 0, faceUp: false),
                  width: 60,
                  height: 90,
                ),
              );
            }),
          // Top card (face up)
          Positioned(
            top: 0,
            left: 0,
            child: CardWidget(
              card: topCard!,
              width: 60,
              height: 90,
            ),
          ),
        ],
      ),
    );
  }
}

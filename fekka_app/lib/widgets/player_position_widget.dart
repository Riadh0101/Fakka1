import 'package:flutter/material.dart';
import '../models/player_state.dart';
import 'card_widget.dart';

/// Renders one opponent's area on the game table:
/// their stack top card (face-up) + hand card count.
///
/// The [label] is shown above the area (e.g. "Player 2").
class PlayerPositionWidget extends StatelessWidget {
  final String label;
  final PlayerGameInfo player;
  final bool isActive;

  const PlayerPositionWidget({
    super.key,
    required this.label,
    required this.player,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive
              ? Colors.amber.withOpacity(0.8)
              : Colors.white.withOpacity(0.15),
          width: isActive ? 2.5 : 1,
        ),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: Colors.amber.withOpacity(0.3),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Player name + eliminated badge
          Text(
            player.name.isNotEmpty ? player.name : label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: player.isConnected ? Colors.white : Colors.grey,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          if (player.isEliminated)
            _buildEliminatedBadge()
          else ...[
            // Stack top card
            if (player.stackTop != null)
              CardWidget(
                card: player.stackTop!,
                width: 48,
                height: 72,
              )
            else
              SizedBox(
                width: 48,
                height: 72,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.2),
                    ),
                  ),
                  child: const Center(
                    child: Icon(Icons.inventory_2_outlined,
                        color: Colors.white24, size: 20),
                  ),
                ),
              ),
            const SizedBox(height: 4),
            // Hand count
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.style, size: 14, color: Colors.white54),
                const SizedBox(width: 4),
                Text(
                  '${player.handCount}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
            // Score
            Text(
              'النقاط: ${player.cumulativeScore}',
              style: const TextStyle(
                fontSize: 10,
                color: Colors.white54,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEliminatedBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text(
        'خارج',
        style: TextStyle(fontSize: 11, color: Colors.redAccent, fontWeight: FontWeight.bold),
      ),
    );
  }
}

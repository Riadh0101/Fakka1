import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../config.dart';
import '../models/game_state.dart';
import '../models/player_state.dart';
import '../providers/game_provider.dart';
import 'game_table_screen.dart';

/// Lobby screen showing room code, player list, share button, and start button.
///
/// Admin (seat 0) sees a "Start Game" button enabled when 4 players are in.
/// Other players see a "Waiting for host..." message.
class LobbyScreen extends ConsumerWidget {
  const LobbyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gameProvider);

    // If the game has started, navigate to game table
    ref.listen<GameState>(gameProvider, (prev, next) {
      if (next.roomStatus == 'in_progress' && !next.gameOver) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const GameTableScreen()),
        );
      }
    });

    final isAdmin = state.seatIndex == 0;
    final canStart = state.lobbyPlayers.length == 4;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF1A1A2E),
              Color(0xFF16213E),
              Color(0xFF0F3460),
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const SizedBox(height: 16),
                // Header
                const Text(
                  'Game Lobby',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 24),

                // Room code display
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: const Color(0xFFE94560).withOpacity(0.4),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'Room: ',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        state.roomId ?? '---',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 4,
                        ),
                      ),
                      const SizedBox(width: 12),
                      InkWell(
                        onTap: () {
                          if (state.roomId != null) {
                            Clipboard.setData(
                                ClipboardData(text: state.roomId!));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Room code copied!'),
                                duration: Duration(seconds: 1),
                              ),
                            );
                          }
                        },
                        child: const Icon(
                          Icons.copy,
                          color: Colors.white38,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Share invite button
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed: () => _shareInvite(state.roomId),
                    icon: const Icon(Icons.share, size: 18),
                    label: const Text('Share Invite'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // Player list label
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Players (${state.lobbyPlayers.length}/4)',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Player list with 4 seat slots
                Expanded(
                  child: _buildPlayerList(state.lobbyPlayers, state.seatIndex),
                ),

                // Bottom action
                Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: isAdmin
                      ? SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: canStart
                                ? () =>
                                    ref.read(gameProvider.notifier).startGame()
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: canStart
                                  ? const Color(0xFFE94560)
                                  : Colors.grey.shade700,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: Text(
                              canStart
                                  ? 'Start Game'
                                  : 'Waiting for players...',
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        )
                      : Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: Colors.amber.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.hourglass_bottom,
                                  color: Colors.white38, size: 18),
                              SizedBox(width: 8),
                              Text(
                                'Waiting for host to start...',
                                style: TextStyle(
                                  color: Colors.white38,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlayerList(List<PlayerInfo> players, int? mySeat) {
    // Build 4 seat slots
    final slots = <Widget>[];
    for (int i = 0; i < 4; i++) {
      final player = players.cast<PlayerInfo?>().firstWhere(
            (p) => p?.seatIndex == i,
            orElse: () => null,
          );

      slots.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: _PlayerSeatTile(
            seatIndex: i,
            player: player,
            isMe: i == mySeat,
          ),
        ),
      );
    }

    return ListView(children: slots);
  }

  void _shareInvite(String? roomId) {
    if (roomId == null) return;
    if (AppConfig.isHost) {
      _getDeviceIp().then((ipResult) {
        final hostPart = ipResult != null
            ? '?host=${ipResult.ip}:${AppConfig.serverPort}'
            : '';
        final url =
            'https://${AppConfig.deepLinkHost}/join/$roomId$hostPart';
        SharePlus.instance.share(
          ShareParams(text: 'Join my Fakka game! Tap to play: $url'),
        );
      });
    } else {
      final url = 'https://${AppConfig.deepLinkHost}/join/$roomId';
      SharePlus.instance.share(
        ShareParams(text: 'Join my Fakka game! Tap to play: $url'),
      );
    }
  }

  /// Tries to discover the device's Wi-Fi or hotspot IPv4 address.
  static Future<({String ip})?> _getDeviceIp() async {
    try {
      final interfaces = await NetworkInterface.list();
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.type == InternetAddressType.IPv4 &&
              !addr.isLoopback &&
              !addr.isLinkLocal) {
            return (ip: addr.address);
          }
        }
      }
    } catch (_) {}
    return null;
  }
}

/// A single seat slot in the lobby player list.
class _PlayerSeatTile extends StatelessWidget {
  final int seatIndex;
  final PlayerInfo? player;
  final bool isMe;

  const _PlayerSeatTile({
    required this.seatIndex,
    this.player,
    this.isMe = false,
  });

  @override
  Widget build(BuildContext context) {
    final isOccupied = player != null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isOccupied
            ? Colors.white.withOpacity(0.06)
            : Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isOccupied
              ? (isMe
                  ? const Color(0xFFE94560).withOpacity(0.5)
                  : Colors.white.withOpacity(0.1))
              : Colors.white.withOpacity(0.05),
          width: isMe ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          // Seat number badge
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isOccupied
                  ? const Color(0xFF0F3460)
                  : Colors.white.withOpacity(0.05),
            ),
            child: Center(
              child: Text(
                '${seatIndex + 1}',
                style: TextStyle(
                  color: isOccupied ? Colors.white70 : Colors.white24,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Player name or empty slot label
          Expanded(
            child: Text(
              isOccupied ? player!.name : 'Empty seat',
              style: TextStyle(
                color: isOccupied ? Colors.white : Colors.white24,
                fontSize: 15,
                fontWeight: isOccupied ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),

          // Status indicators
          if (isOccupied) ...[
            if (isMe)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFE94560).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'YOU',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFFE94560),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            if (player!.seatIndex == 0)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(Icons.star,
                    color: Colors.amber.withOpacity(0.7), size: 18),
              ),
            if (!player!.isConnected)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(Icons.signal_wifi_off,
                    color: Colors.red.withOpacity(0.6), size: 16),
              ),
          ],
        ],
      ),
    );
  }
}

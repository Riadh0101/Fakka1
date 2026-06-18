import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/game_state.dart';
import '../providers/game_provider.dart';
import '../build_info.dart';
import 'lobby_screen.dart';
import 'join_screen.dart';
import 'game_table_screen.dart';

/// Home screen with app title, Create Game and Join Game buttons.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _nameController = TextEditingController(text: '');
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    // Attempt to reconnect to a previously active session
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(gameProvider.notifier).tryRejoin();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _createGame() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء إدخال اسمك')),
      );
      return;
    }

    setState(() => _isCreating = true);

    await ref.read(gameProvider.notifier).createGame(name);

    if (!mounted) return;
    setState(() => _isCreating = false);

    final state = ref.read(gameProvider);
    if (state.roomId != null && state.errorMessage == null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const LobbyScreen(),
        ),
      );
    } else if (state.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(state.errorMessage!)),
      );
    }
  }

  void _joinGame() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const JoinScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(gameProvider);

    // Auto-navigate if reconnected to an in-progress game
    ref.listen<GameState>(gameProvider, (prev, next) {
      if (next.roomId != null && next.isConnected && !next.isReconnecting) {
        final wasReconnecting = prev?.isReconnecting == true;
        if (wasReconnecting) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (_) => next.roomStatus == 'in_progress'
                  ? const GameTableScreen()
                  : const LobbyScreen(),
            ),
            (route) => false,
          );
        }
      }
    });

    return Scaffold(
      body: Stack(
        children: [
          Container(
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
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 40),
                  // Logo
                  Text(
                    'Fakka',
                    style: TextStyle(
                      fontSize: 56,
                      fontWeight: FontWeight.w900,
                      foreground: Paint()
                        ..shader = const LinearGradient(
                          colors: [Color(0xFFE94560), Color(0xFFFF6B6B)],
                        ).createShader(
                          const Rect.fromLTWH(0, 0, 200, 70),
                        ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Build version circle
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(BuildInfo.colors[(BuildInfo.number - 1) % 3]),
                    ),
                    child: Center(
                      child: Text(
                        '${BuildInfo.number}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const SizedBox(height: 8),
                  const Text(
                    '\u0625\u0644\u0641\u0643\u0629 \u0639\u0644\u0649 \u0637\u0631\u064a\u0642\u0629 \u0627\u0644\u0645\u0643\u0646\u064a\u0646',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white54,
                    ),
                  ),
                  const SizedBox(height: 48),

                  // Name input
                  TextField(
                    controller: _nameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'اسمك المعروض',
                      labelStyle: const TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.08),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                            color: Color(0xFFE94560), width: 1.5),
                      ),
                      prefixIcon: const Icon(Icons.person,
                          color: Colors.white38),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Create Game button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isCreating ? null : _createGame,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE94560),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 4,
                      ),
                      child: _isCreating
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'إنشاء لعبة',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Join Game button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton(
                      onPressed: _joinGame,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(
                            color: Color(0xFFE94560), width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'الانضمام إلى لعبة',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),

                  // Rejoin hint if session exists
                  if (state.isReconnecting)
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: Text(
                        'جاري محاولة إعادة الاتصال...',
                        style: TextStyle(color: Colors.white38, fontSize: 13),
                      ),
                    ),
                ],
              ),
            ),
          ),
          ),
        ),
        // خروج (Quit) button — top-right
        Positioned(
          top: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: TextButton(
                onPressed: () => SystemNavigator.pop(),
                child: const Text(
                  'خروج',
                  style: TextStyle(color: Colors.white38, fontSize: 15),
                ),
              ),
            ),
          ),
        ),
      ],
      ),
    );
  }
}

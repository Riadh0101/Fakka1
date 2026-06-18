import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config.dart';
import '../providers/game_provider.dart';
import 'lobby_screen.dart';

/// Join screen with room code and player name fields.
///
/// If opened via deep link (`/join/{roomId}`), the room code field
/// is pre-filled from the route argument.
class JoinScreen extends ConsumerStatefulWidget {
  const JoinScreen({super.key});

  @override
  ConsumerState<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends ConsumerState<JoinScreen> {
  final _roomCodeController = TextEditingController();
  final _nameController = TextEditingController();
  bool _isJoining = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Pre-fill room code from deep link if available
    final routeArgs = ModalRoute.of(context)?.settings.arguments;
    if (routeArgs is String && routeArgs.isNotEmpty) {
      if (_roomCodeController.text.isEmpty) {
        _roomCodeController.text = routeArgs;
      }
    } else if (routeArgs is Map) {
      final roomId = routeArgs['roomId'];
      final hostIp = routeArgs['hostIp'];
      if (roomId is String && roomId.isNotEmpty) {
        if (_roomCodeController.text.isEmpty) {
          _roomCodeController.text = roomId;
        }
      }
      if (hostIp is String && hostIp.isNotEmpty) {
        AppConfig.hostIp = hostIp;
        AppConfig.isHost = false;
      }
    }
  }

  @override
  void dispose() {
    _roomCodeController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final roomCode = _roomCodeController.text.trim().toUpperCase();
    final name = _nameController.text.trim();

    if (roomCode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء إدخال رمز الغرفة')),
      );
      return;
    }
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء إدخال اسمك')),
      );
      return;
    }

    setState(() => _isJoining = true);

    await ref.read(gameProvider.notifier).joinGame(roomCode, name);

    if (!mounted) return;
    setState(() => _isJoining = false);

    final state = ref.read(gameProvider);
    if (state.roomId != null && state.errorMessage == null) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LobbyScreen()),
      );
    } else if (state.errorMessage != null) {
      String displayMsg = state.errorMessage!;
      // Map common server errors to user-friendly messages (supports Arabic and English)
      if (displayMsg.contains('غير موجودة') || displayMsg.toLowerCase().contains('not found')) {
        displayMsg = 'الغرفة غير موجودة. تحقق من الرمز وحاول مرة أخرى.';
      } else if (displayMsg.contains('ممتلئة') || displayMsg.toLowerCase().contains('full')) {
        displayMsg = 'الغرفة ممتلئة (4/4 لاعبين).';
      } else if (displayMsg.contains('بدأت') || displayMsg.toLowerCase().contains('started')) {
        displayMsg = 'اللعبة قد بدأت بالفعل.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(displayMsg),
          backgroundColor: Colors.red.shade800,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
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
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              children: [
                const SizedBox(height: 20),
                // Back button
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back,
                        color: Colors.white70),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'الانضمام إلى لعبة',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'أدخل رمز الغرفة الذي شاركه صديقك',
                  style: TextStyle(color: Colors.white54, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),

                // Room code field
                TextField(
                  controller: _roomCodeController,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 8,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 6,
                  ),
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    hintText: 'رمز الغرفة',
                    hintStyle: TextStyle(
                      color: Colors.white.withOpacity(0.2),
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 6,
                    ),
                    counterText: '',
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
                  ),
                ),
                const SizedBox(height: 20),

                // Name field
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
                    prefixIcon:
                        const Icon(Icons.person, color: Colors.white38),
                  ),
                ),
                const SizedBox(height: 32),

                // Join button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isJoining ? null : _join,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE94560),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 4,
                    ),
                    child: _isJoining
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'انضمام',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
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
}

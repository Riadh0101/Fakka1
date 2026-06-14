import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'screens/home_screen.dart';
import 'screens/join_screen.dart';
import 'screens/lobby_screen.dart';
import 'screens/game_table_screen.dart';
import 'screens/score_summary_screen.dart';
import 'screens/game_over_screen.dart';

/// Root MaterialApp with named routes and deep link handling.
///
/// Deep links matching `/join/{roomId}` on platform `fekka-game.com` or
/// custom scheme `fekka://` are parsed and forwarded as route arguments.
class FekkaApp extends ConsumerWidget {
  const FekkaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Fekka',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFFE94560),
        scaffoldBackgroundColor: const Color(0xFF1A1A2E),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFE94560),
          secondary: Color(0xFF0F3460),
          surface: Color(0xFF16213E),
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: Color(0xFF2A2A3E),
          contentTextStyle: TextStyle(color: Colors.white),
          behavior: SnackBarBehavior.floating,
        ),
      ),
      initialRoute: '/',
      onGenerateRoute: _onGenerateRoute,
    );
  }

  Route<dynamic>? _onGenerateRoute(RouteSettings settings) {
    // Parse deep link arguments
    String? roomId;

    // Deep link from platform: `/join/{roomId}`
    final uri = Uri.tryParse(settings.name ?? '');
    if (uri != null && uri.pathSegments.length >= 2) {
      if (uri.pathSegments[0] == 'join') {
        roomId = uri.pathSegments[1];
        settings = RouteSettings(
          name: '/join',
          arguments: roomId,
        );
      }
    }

    // Also handle custom scheme: `fekka://join/{roomId}`
    if (settings.name?.startsWith('fekka://') == true) {
      final customUri = Uri.tryParse(settings.name!);
      if (customUri != null &&
          customUri.pathSegments.isNotEmpty &&
          customUri.pathSegments[0] == 'join') {
        roomId = customUri.pathSegments.length >= 2
            ? customUri.pathSegments[1]
            : null;
        settings = RouteSettings(
          name: '/join',
          arguments: roomId,
        );
      }
    }

    switch (settings.name) {
      case '/':
        return MaterialPageRoute(
          builder: (_) => const HomeScreen(),
          settings: settings,
        );
      case '/join':
        return MaterialPageRoute(
          builder: (_) => const JoinScreen(),
          settings: settings, // passes roomId via arguments
        );
      case '/lobby':
        return MaterialPageRoute(
          builder: (_) => const LobbyScreen(),
          settings: settings,
        );
      case '/game':
        return MaterialPageRoute(
          builder: (_) => const GameTableScreen(),
          settings: settings,
        );
      case '/scores':
        return MaterialPageRoute(
          builder: (_) => const ScoreSummaryScreen(),
          settings: settings,
        );
      case '/gameover':
        return MaterialPageRoute(
          builder: (_) => const GameOverScreen(),
          settings: settings,
        );
      default:
        // Unknown route → home
        return MaterialPageRoute(
          builder: (_) => const HomeScreen(),
          settings: settings,
        );
    }
  }
}

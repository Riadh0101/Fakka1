/// Central configuration for the Fakka app.
///
/// All API and Socket URLs are derived from [baseUrl].
/// Change [baseUrl] to point at a different server environment.
class AppConfig {
  /// Whether this device is the host (game creator).
  static bool isHost = false;

  /// The host's IP:port when joining as a guest (set from deep link or input).
  static String? hostIp;

  /// Server port used when running as host.
  static const int serverPort = 3000;

  /// Fallback base URL used when neither host nor guest IP is set.
  static const String _fallbackBaseUrl = 'https://fakka1.onrender.com';

  /// Base URL of the NestJS backend server.
  ///
  /// - Host mode → http://localhost:$serverPort
  /// - Guest mode (hostIp set) → http://$hostIp
  /// - Fallback → $_fallbackBaseUrl
  static String get baseUrl {
    if (isHost) return 'http://localhost:$serverPort';
    if (hostIp != null && hostIp!.isNotEmpty) return 'http://$hostIp';
    return _fallbackBaseUrl;
  }

  /// REST API base URL.
  static String get apiUrl => baseUrl;

  /// WebSocket connection URL (ws:// or wss:// derived from baseUrl).
  static String get socketUrl => baseUrl
      .replaceFirst('https://', 'wss://')
      .replaceFirst('http://', 'ws://');

  /// Deep link base host for share invites.
  static const String deepLinkHost = 'fakka1.onrender.com';

  /// Timeout (seconds) before "Connection Lost" is shown.
  static const int reconnectTimeoutSeconds = 60;

  /// Android package name (for Play Store fallback).
  static const String androidPackageName = 'com.fekka.game';

  /// iOS App Store ID (placeholder).
  static const String iosAppStoreId = '0000000000';
}

/// Central configuration for the Fekka app.
///
/// All API and Socket URLs are derived from [baseUrl].
/// Change [baseUrl] to point at a different server environment.
class AppConfig {
  /// Base URL of the NestJS backend server.
  /// Defaults to localhost for development.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:3000',
  );

  /// REST API base URL.
  static String get apiUrl => baseUrl;

  /// Socket.IO connection URL (same host as REST).
  static String get socketUrl => baseUrl;

  /// Deep link base host for share invites.
  static const String deepLinkHost = 'fekka-game.com';

  /// Timeout (seconds) before "Connection Lost" is shown.
  static const int reconnectTimeoutSeconds = 60;

  /// Android package name (for Play Store fallback).
  static const String androidPackageName = 'com.fekka.game';

  /// iOS App Store ID (placeholder).
  static const String iosAppStoreId = '0000000000';
}

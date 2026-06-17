import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:http/http.dart' as http;
import '../config.dart';

/// Thin REST client for room-management endpoints on the embedded server.
class ApiService {
  final http.Client _client = http.Client();

  /// Dynamically resolves the base URL from [AppConfig].
  String get _baseUrl => AppConfig.apiUrl;

  /// POST /games/create
  Future<Map<String, dynamic>> createRoom(String adminName) async {
    final uri = Uri.parse('$_baseUrl/games/create');
    developer.log('🌐 POST $uri', name: 'API');
    try {
      final response = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'adminName': adminName}),
      ).timeout(const Duration(seconds: 10));

      developer.log('📥 Response: ${response.statusCode} ${response.body}', name: 'API');

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }

      final error = _extractError(response);
      throw ApiException('Failed to create room: $error',
          statusCode: response.statusCode);
    } catch (e) {
      developer.log('❌ Error: $e', name: 'API');
      if (e is SocketException) {
        throw ApiException('Cannot connect to game server. Make sure the server is running.');
      }
      rethrow;
    }
  }

  /// POST /games/:roomId/join
  ///
  /// Joins an existing game room. Returns player assignment data.
  /// Expected response: `{ playerId, seatIndex, roomStatus, ... }`
  Future<Map<String, dynamic>> joinRoom(
    String roomId,
    String playerName,
  ) async {
    final uri = Uri.parse('$_baseUrl/games/$roomId/join');
    final response = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'playerName': playerName}),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }

    final error = _extractError(response);
    throw ApiException('Failed to join room: $error',
        statusCode: response.statusCode);
  }

  /// POST /games/:roomId/start
  ///
  /// Starts the game (admin only). Returns initial game state.
  Future<Map<String, dynamic>> startGame(
    String roomId,
    String playerId,
  ) async {
    final uri = Uri.parse('$_baseUrl/games/$roomId/start');
    final response = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'adminPlayerId': playerId}),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }

    final error = _extractError(response);
    throw ApiException('Failed to start game: $error',
        statusCode: response.statusCode);
  }

  String _extractError(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      return body['message'] as String? ?? response.reasonPhrase ?? 'Unknown error';
    } catch (_) {
      return response.reasonPhrase ?? 'Unknown error (${response.statusCode})';
    }
  }

  void dispose() => _client.close();
}

/// Custom exception for REST API errors.
class ApiException implements Exception {
  final String message;
  final int? statusCode;

  const ApiException(this.message, {this.statusCode});

  @override
  String toString() => 'ApiException: $message (status: $statusCode)';
}

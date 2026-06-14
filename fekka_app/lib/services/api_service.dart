import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';

/// Thin REST client for room-management endpoints on the NestJS backend.
///
/// Socket.IO is used for all real-time game communication;
/// this service only handles room lifecycle (create / join / start).
class ApiService {
  final http.Client _client = http.Client();
  final String _baseUrl = AppConfig.apiUrl;

  /// POST /games/create
  ///
  /// Creates a new game room. Returns the created room data.
  /// Expected response: `{ roomId, playerId, adminPlayerId, ... }`
  Future<Map<String, dynamic>> createRoom(String playerName) async {
    final uri = Uri.parse('$_baseUrl/games/create');
    final response = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'playerName': playerName}),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }

    final error = _extractError(response);
    throw ApiException('Failed to create room: $error',
        statusCode: response.statusCode);
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
      body: jsonEncode({'playerId': playerId}),
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

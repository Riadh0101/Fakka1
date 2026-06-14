/// Socket.IO event type constants used for communication
/// between the Flutter client and the NestJS backend.
class SocketEvent {
  SocketEvent._();

  // ---- Client → Server ----
  static const String playCard = 'play_card';
  static const String rejoin = 'rejoin';

  // ---- Server → Client ----
  static const String stateSync = 'state_sync';
  static const String stateUpdate = 'state_update';
  static const String capture = 'capture';
  static const String roundEnd = 'round_end';
  static const String playerEliminated = 'player_eliminated';
  static const String gameOver = 'game_over';
  static const String playerJoined = 'player_joined';
  static const String error = 'error';
}

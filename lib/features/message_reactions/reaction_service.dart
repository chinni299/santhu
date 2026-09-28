import 'package:socket_io_client/socket_io_client.dart' as io;

class ReactionService {
  static void sendReaction({
    required io.Socket? socket,
    required int conversationId,
    required int messageId,
    required String emoji,
  }) {
    if (socket == null || !socket.connected) return;
    socket.emit('reactToMessage', {
      'conversationId': conversationId,
      'messageId': messageId,
      'reaction': emoji,
    });
  }
}

import 'package:socket_io_client/socket_io_client.dart' as io;

class ThinkingOfYouService {
  static const int cooldownSeconds = 30;
  static int _lastSentTimestamp = 0;

  static bool get canSend {
    final now = DateTime.now().millisecondsSinceEpoch;
    return (now - _lastSentTimestamp) >= (cooldownSeconds * 1000);
  }

  static int get remainingCooldownSeconds {
    final now = DateTime.now().millisecondsSinceEpoch;
    final elapsed = (now - _lastSentTimestamp) ~/ 1000;
    final remaining = cooldownSeconds - elapsed;
    return remaining > 0 ? remaining : 0;
  }

  static bool sendThinkingOfYou({
    required io.Socket? socket,
    required int conversationId,
  }) {
    if (!canSend) return false;
    if (socket == null || !socket.connected) return false;

    _lastSentTimestamp = DateTime.now().millisecondsSinceEpoch;
    socket.emit('thinkingOfYou', {
      'conversationId': conversationId,
    });
    return true;
  }
}

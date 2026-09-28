import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../../config/api_config.dart';
import '../../services/auth_service.dart';
import 'disappearing_message_duration.dart';

class DisappearingMessageService {
  static Future<DisappearingDuration> fetchTimer({
    required int conversationId,
    required int currentUserId,
  }) async {
    try {
      final headers = await AuthService.getAuthHeadersForUser(currentUserId);
      final url = Uri.parse('${ApiConfig.baseUrl}/messages/disappearing-timer/$conversationId');
      final response = await http.get(url, headers: headers);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          final seconds = int.tryParse(data['data']['disappearing_timer_seconds']?.toString() ?? '0');
          return DisappearingDuration.fromSeconds(seconds);
        }
      }
    } catch (_) {}
    return DisappearingDuration.off;
  }

  static Future<bool> setTimer({
    required io.Socket? socket,
    required int conversationId,
    required DisappearingDuration duration,
  }) async {
    if (socket == null || !socket.connected) return false;
    socket.emit('setDisappearingTimer', {
      'conversationId': conversationId,
      'durationSeconds': duration.seconds,
    });
    return true;
  }
}

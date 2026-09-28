import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../../config/api_config.dart';
import '../../services/auth_service.dart';
import 'mood.dart';

class MoodService {
  static Future<UserMood?> fetchMood(int userId, int currentUserId) async {
    try {
      final headers = await AuthService.getAuthHeadersForUser(currentUserId);
      final url = Uri.parse('${ApiConfig.baseUrl}/auth/mood/$userId');
      final res = await http.get(url, headers: headers);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && data['data'] != null) {
          return UserMood.fromJson(data['data']);
        }
      }
    } catch (_) {}
    return null;
  }

  static void setMood({
    required io.Socket? socket,
    MoodType? moodType,
  }) {
    if (socket == null || !socket.connected) return;
    socket.emit('setMood', {
      'mood': moodType?.key,
    });
  }
}

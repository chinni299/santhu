import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../../config/api_config.dart';
import '../../services/auth_service.dart';
import 'couple_status.dart';

class CoupleStatusService {
  static Future<CoupleStatus?> fetchStatus(int userId, int currentUserId) async {
    try {
      final headers = await AuthService.getAuthHeadersForUser(currentUserId);
      final url = Uri.parse('${ApiConfig.baseUrl}/auth/couple-status/$userId');
      final res = await http.get(url, headers: headers);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && data['data'] != null) {
          return CoupleStatus.fromJson(data['data']);
        }
      }
    } catch (_) {}
    return null;
  }

  static void setStatus({
    required io.Socket? socket,
    required CoupleStatusType statusType,
    String? customText,
  }) {
    if (socket == null || !socket.connected) return;
    socket.emit('setCoupleStatus', {
      'status': statusType.key,
      'customText': customText?.trim(),
    });
  }
}

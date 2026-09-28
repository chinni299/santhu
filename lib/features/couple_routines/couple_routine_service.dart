import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../config/api_config.dart';
import '../../services/auth_service.dart';
import 'couple_routine.dart';

class CoupleRoutineService {
  static Future<CoupleRoutine?> getRoutines() async {
    final token = await AuthService.getToken();
    final response = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/messages/routines'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      if (body['success'] == true && body['data'] != null) {
        return CoupleRoutine.fromJson(body['data']);
      }
    }
    return null;
  }

  static Future<CoupleRoutine?> saveRoutines({
    required bool morningEnabled,
    required String morningTime,
    required bool nightEnabled,
    required String nightTime,
    String? customMorningMsg,
    String? customNightMsg,
    required bool soundEnabled,
  }) async {
    final token = await AuthService.getToken();
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/messages/routines'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'morning_enabled': morningEnabled,
        'morning_time': morningTime,
        'night_enabled': nightEnabled,
        'night_time': nightTime,
        'custom_morning_msg': customMorningMsg,
        'custom_night_msg': customNightMsg,
        'sound_enabled': soundEnabled,
      }),
    );

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      if (body['success'] == true && body['data'] != null) {
        return CoupleRoutine.fromJson(body['data']);
      }
    }
    return null;
  }
}

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../config/api_config.dart';
import '../../services/auth_service.dart';
import 'important_date.dart';

class ImportantDateService {
  static Future<List<ImportantDate>> getDates() async {
    final token = await AuthService.getToken();
    final response = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/messages/important-dates'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      if (body['success'] == true) {
        final List list = body['data'] ?? [];
        return list.map((e) => ImportantDate.fromJson(e)).toList();
      }
    }
    return [];
  }

  static Future<ImportantDate?> createDate({
    required String title,
    required String dateType,
    required DateTime dateValue,
    String? note,
  }) async {
    final token = await AuthService.getToken();
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/messages/important-dates'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'title': title,
        'date_type': dateType,
        'date_value': dateValue.toIso8601String(),
        'note': note,
      }),
    );

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      if (body['success'] == true) {
        return ImportantDate.fromJson(body['data']);
      }
    }
    return null;
  }

  static Future<ImportantDate?> updateDate({
    required int id,
    String? title,
    String? dateType,
    DateTime? dateValue,
    String? note,
  }) async {
    final token = await AuthService.getToken();
    final bodyMap = <String, dynamic>{};
    if (title != null) bodyMap['title'] = title;
    if (dateType != null) bodyMap['date_type'] = dateType;
    if (dateValue != null) bodyMap['date_value'] = dateValue.toIso8601String();
    if (note != null) bodyMap['note'] = note;

    final response = await http.put(
      Uri.parse('${ApiConfig.baseUrl}/messages/important-dates/$id'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode(bodyMap),
    );

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      if (body['success'] == true) {
        return ImportantDate.fromJson(body['data']);
      }
    }
    return null;
  }

  static Future<bool> deleteDate(int id) async {
    final token = await AuthService.getToken();
    final response = await http.delete(
      Uri.parse('${ApiConfig.baseUrl}/messages/important-dates/$id'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      return body['success'] == true;
    }
    return false;
  }
}

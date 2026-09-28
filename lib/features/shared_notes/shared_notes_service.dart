import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../config/api_config.dart';
import '../../services/auth_service.dart';
import 'shared_note.dart';

class SharedNotesService {
  static Future<List<SharedNote>> getNotes() async {
    final token = await AuthService.getToken();
    final response = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/messages/notes'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      if (body['success'] == true) {
        final List list = body['data'] ?? [];
        return list.map((e) => SharedNote.fromJson(e)).toList();
      }
    }
    return [];
  }

  static Future<SharedNote?> createNote({required String title, required String content}) async {
    final token = await AuthService.getToken();
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/messages/notes'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'title': title, 'content': content}),
    );

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      if (body['success'] == true) {
        return SharedNote.fromJson(body['data']);
      }
    }
    return null;
  }

  static Future<SharedNote?> updateNote({required int id, String? title, String? content}) async {
    final token = await AuthService.getToken();
    final bodyMap = <String, dynamic>{};
    if (title != null) bodyMap['title'] = title;
    if (content != null) bodyMap['content'] = content;

    final response = await http.put(
      Uri.parse('${ApiConfig.baseUrl}/messages/notes/$id'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode(bodyMap),
    );

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      if (body['success'] == true) {
        return SharedNote.fromJson(body['data']);
      }
    }
    return null;
  }

  static Future<bool> deleteNote(int id) async {
    final token = await AuthService.getToken();
    final response = await http.delete(
      Uri.parse('${ApiConfig.baseUrl}/messages/notes/$id'),
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

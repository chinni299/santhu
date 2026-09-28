import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../../config/api_config.dart';
import '../../services/auth_service.dart';
import 'memory_model.dart';

class MemoryService {
  static Future<List<MemoryModel>> getMemories() async {
    final token = await AuthService.getToken();
    final response = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/messages/memories'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      if (body['success'] == true) {
        final List list = body['data'] ?? [];
        return list.map((e) => MemoryModel.fromJson(e)).toList();
      }
    }
    return [];
  }

  static Future<MemoryModel?> createMemory({
    required File file,
    required String type,
    String? caption,
    required DateTime memoryDate,
  }) async {
    final token = await AuthService.getToken();
    final request = http.MultipartRequest('POST', Uri.parse('${ApiConfig.baseUrl}/messages/memories'));
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    request.fields['type'] = type;
    if (caption != null) request.fields['caption'] = caption;
    request.fields['memory_date'] = memoryDate.toIso8601String();
    request.files.add(await http.MultipartFile.fromPath('media', file.path));

    final streamedRes = await request.send();
    final response = await http.Response.fromStream(streamedRes);

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      if (body['success'] == true) {
        return MemoryModel.fromJson(body['data']);
      }
    }
    return null;
  }

  static Future<bool> deleteMemory(int id) async {
    final token = await AuthService.getToken();
    final response = await http.delete(
      Uri.parse('${ApiConfig.baseUrl}/messages/memories/$id'),
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

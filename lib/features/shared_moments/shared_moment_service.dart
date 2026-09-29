import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../../config/api_config.dart';
import '../../services/auth_service.dart';
import 'shared_moment.dart';

class SharedMomentService {
  static Future<List<SharedMoment>> getMoments() async {
    final token = await AuthService.getToken();
    final response = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/messages/shared-moments'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      if (body['success'] == true) {
        final List list = body['data'] ?? [];
        return list.map((e) => SharedMoment.fromJson(e)).toList();
      }
    }
    return [];
  }

  static Future<SharedMoment?> createMoment({
    File? file,
    String? caption,
    double? latitude,
    double? longitude,
    required bool locationEnabled,
    required DateTime momentDate,
  }) async {
    final token = await AuthService.getToken();
    final request = http.MultipartRequest('POST', Uri.parse('${ApiConfig.baseUrl}/messages/shared-moments'));
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    if (caption != null) request.fields['caption'] = caption;
    request.fields['location_enabled'] = locationEnabled.toString();
    if (locationEnabled && latitude != null && longitude != null) {
      request.fields['latitude'] = latitude.toString();
      request.fields['longitude'] = longitude.toString();
    }
    request.fields['moment_date'] = momentDate.toIso8601String();

    if (file != null) {
      request.files.add(await http.MultipartFile.fromPath('media', file.path));
    }

    final streamedRes = await request.send();
    final response = await http.Response.fromStream(streamedRes);

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      if (body['success'] == true) {
        return SharedMoment.fromJson(body['data']);
      }
    }
    return null;
  }

  static Future<bool> deleteMoment(int id) async {
    final token = await AuthService.getToken();
    final response = await http.delete(
      Uri.parse('${ApiConfig.baseUrl}/messages/shared-moments/$id'),
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

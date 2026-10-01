import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../../config/api_config.dart';
import '../../services/auth_service.dart';
import 'shared_sky_model.dart';

class SharedSkyService {
  static io.Socket? _socket;
  static int _conversationId = 1;

  // Real-time callbacks
  static void Function(NamedStar star)? onStarNamed;
  static void Function(NamedStar star)? onStarUpdated;
  static void Function(int starIndex, int starId)? onStarDeleted;
  static void Function(int? starIndex, bool isHovering, int userId)? onPartnerHover;
  static void Function(bool isOpen, int userId)? onPartnerStatus;

  static void initialize(io.Socket? socket, int conversationId) {
    _socket = socket;
    _conversationId = conversationId;
    _attachListeners();
  }

  static void _attachListeners() {
    _socket?.off('sharedSky_starNamed');
    _socket?.off('sharedSky_starUpdated');
    _socket?.off('sharedSky_starDeleted');
    _socket?.off('sharedSky_partnerHover');
    _socket?.off('sharedSky_partnerStatus');

    _socket?.on('sharedSky_starNamed', (data) {
      if (data != null && data['star'] != null) {
        try {
          final star = NamedStar.fromJson(Map<String, dynamic>.from(data['star']));
          onStarNamed?.call(star);
        } catch (e) {
          debugPrint('[SHARED SKY SERVICE] Parse error on starNamed: $e');
        }
      }
    });

    _socket?.on('sharedSky_starUpdated', (data) {
      if (data != null && data['star'] != null) {
        try {
          final star = NamedStar.fromJson(Map<String, dynamic>.from(data['star']));
          onStarUpdated?.call(star);
        } catch (e) {
          debugPrint('[SHARED SKY SERVICE] Parse error on starUpdated: $e');
        }
      }
    });

    _socket?.on('sharedSky_starDeleted', (data) {
      if (data != null) {
        final starIndex = (data['starIndex'] as num?)?.toInt() ?? -1;
        final starId = (data['starId'] as num?)?.toInt() ?? -1;
        onStarDeleted?.call(starIndex, starId);
      }
    });

    _socket?.on('sharedSky_partnerHover', (data) {
      if (data != null) {
        final starIndex = (data['starIndex'] as num?)?.toInt();
        final isHovering = data['isHovering'] == true;
        final userId = (data['userId'] as num?)?.toInt() ?? 0;
        onPartnerHover?.call(starIndex, isHovering, userId);
      }
    });

    _socket?.on('sharedSky_partnerStatus', (data) {
      if (data != null) {
        final isOpen = data['isOpen'] == true;
        final userId = (data['userId'] as num?)?.toInt() ?? 0;
        onPartnerStatus?.call(isOpen, userId);
      }
    });
  }

  static void openSky() {
    _socket?.emit('sharedSky_open', {'conversationId': _conversationId});
  }

  static void closeSky() {
    _socket?.emit('sharedSky_close', {'conversationId': _conversationId});
  }

  static void emitHover(int? starIndex, bool isHovering) {
    _socket?.emit('sharedSky_hover', {
      'conversationId': _conversationId,
      'starIndex': starIndex,
      'isHovering': isHovering,
    });
  }

  // ── REST API Calls ────────────────────────────────────────────────────────

  static Future<List<NamedStar>> fetchStars(int conversationId) async {
    try {
      final token = await AuthService.getToken();
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/shared-sky/$conversationId'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body['success'] == true && body['stars'] is List) {
          return (body['stars'] as List)
              .map((e) => NamedStar.fromJson(Map<String, dynamic>.from(e)))
              .toList();
        }
      }
    } catch (e) {
      debugPrint('[SHARED SKY SERVICE] fetchStars error: $e');
    }
    return [];
  }

  static Future<NamedStar?> nameStar({
    required int conversationId,
    required int starIndex,
    required String starName,
  }) async {
    try {
      final token = await AuthService.getToken();
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/shared-sky'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'conversationId': conversationId,
          'starIndex': starIndex,
          'starName': starName.trim(),
        }),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body['success'] == true && body['star'] != null) {
          return NamedStar.fromJson(Map<String, dynamic>.from(body['star']));
        }
      }
    } catch (e) {
      debugPrint('[SHARED SKY SERVICE] nameStar error: $e');
    }
    return null;
  }

  static Future<NamedStar?> renameStar({
    required int starId,
    required String starName,
  }) async {
    try {
      final token = await AuthService.getToken();
      final response = await http.put(
        Uri.parse('${ApiConfig.baseUrl}/shared-sky/$starId'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'starName': starName.trim(),
        }),
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body['success'] == true && body['star'] != null) {
          return NamedStar.fromJson(Map<String, dynamic>.from(body['star']));
        }
      }
    } catch (e) {
      debugPrint('[SHARED SKY SERVICE] renameStar error: $e');
    }
    return null;
  }

  static Future<bool> deleteStar(int starId) async {
    try {
      final token = await AuthService.getToken();
      final response = await http.delete(
        Uri.parse('${ApiConfig.baseUrl}/shared-sky/$starId'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        return body['success'] == true;
      }
    } catch (e) {
      debugPrint('[SHARED SKY SERVICE] deleteStar error: $e');
    }
    return false;
  }
}

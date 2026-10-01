import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../../config/api_config.dart';
import '../../services/auth_service.dart';

class HugData {
  final int id;
  final int conversationId;
  final int senderId;
  final String senderName;
  final DateTime createdAt;
  final bool isLive;

  HugData({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.senderName,
    required this.createdAt,
    this.isLive = true,
  });

  factory HugData.fromJson(Map<String, dynamic> json) {
    return HugData(
      id: (json['id'] as num?)?.toInt() ?? 0,
      conversationId: (json['conversation_id'] ?? json['conversationId'] as num?)?.toInt() ?? 1,
      senderId: (json['sender_id'] ?? json['senderId'] as num?)?.toInt() ?? 1,
      senderName: json['sender_name']?.toString() ?? json['senderName']?.toString() ?? 'Partner',
      createdAt: json['created_at'] != null || json['createdAt'] != null
          ? DateTime.tryParse((json['created_at'] ?? json['createdAt']).toString()) ?? DateTime.now()
          : DateTime.now(),
      isLive: json['isLive'] != false,
    );
  }
}

class HugKissService {
  static io.Socket? _socket;
  static int _conversationId = 1;
  static int _currentUserId = 1;
  static int get currentUserId => _currentUserId;

  // Real-time Event Callbacks
  static void Function(HugData hug)? onHugReceived;
  static void Function(bool isPressing, int partnerId)? onKissPartnerStatus;
  static void Function(int syncDiffMs)? onKissSyncMatched;
  static void Function(Map<String, dynamic> data)? onKissSuccess;
  static void Function(String reason)? onKissCancelled;
  static void Function(String message)? onKissTimeout;
  static void Function(String message)? onKissWindowMissed;

  static void initialize({
    required io.Socket? socket,
    required int conversationId,
    required int currentUserId,
  }) {
    _socket = socket;
    _conversationId = conversationId;
    _currentUserId = currentUserId;
    _attachListeners();
  }

  static void _attachListeners() {
    if (_socket == null) return;

    _socket?.off('hug_received');
    _socket?.off('kiss_partner_status');
    _socket?.off('kiss_sync_matched');
    _socket?.off('kiss_success');
    _socket?.off('kiss_cancelled');
    _socket?.off('kiss_timeout');
    _socket?.off('kiss_sync_window_missed');

    // Received Hug
    _socket?.on('hug_received', (data) {
      debugPrint('[HUG & KISS SERVICE] Received hug_received: $data');
      if (data != null) {
        try {
          final hug = HugData.fromJson(Map<String, dynamic>.from(data));
          _triggerHugHaptics();
          onHugReceived?.call(hug);
        } catch (e) {
          debugPrint('[HUG & KISS SERVICE] Parse error on hug: $e');
        }
      }
    });

    // Partner is touching the Kiss button
    _socket?.on('kiss_partner_status', (data) {
      debugPrint('[HUG & KISS SERVICE] Partner kiss status: $data');
      if (data != null) {
        final isPressing = data['isPressing'] == true;
        final partnerId = (data['partnerId'] as num?)?.toInt() ?? 0;
        if (isPressing) {
          _triggerLightHaptics();
        }
        onKissPartnerStatus?.call(isPressing, partnerId);
      }
    });

    // Both touches arrived within 500ms window!
    _socket?.on('kiss_sync_matched', (data) {
      debugPrint('[HUG & KISS SERVICE] Kiss sync matched: $data');
      final diff = (data != null && data['syncDiffMs'] != null)
          ? (data['syncDiffMs'] as num).toInt()
          : 0;
      _triggerMediumHaptics();
      onKissSyncMatched?.call(diff);
    });

    // Kiss Success after 1s synchronized hold
    _socket?.on('kiss_success', (data) {
      debugPrint('[HUG & KISS SERVICE] 💋 KISS SUCCESS: $data');
      _triggerKissSuccessHaptics();
      onKissSuccess?.call(data != null ? Map<String, dynamic>.from(data) : {});
    });

    // Kiss Cancelled (released before 1s)
    _socket?.on('kiss_cancelled', (data) {
      debugPrint('[HUG & KISS SERVICE] Kiss cancelled: $data');
      final reason = data?['reason']?.toString() ?? 'Hold was released.';
      onKissCancelled?.call(reason);
    });

    // Kiss 10-second timeout
    _socket?.on('kiss_timeout', (data) {
      debugPrint('[HUG & KISS SERVICE] Kiss timeout: $data');
      final msg = data?['message']?.toString() ?? 'Timed out.';
      onKissTimeout?.call(msg);
    });

    // 500ms window missed
    _socket?.on('kiss_sync_window_missed', (data) {
      debugPrint('[HUG & KISS SERVICE] Kiss window missed: $data');
      final msg = data?['message']?.toString() ?? 'Touches must be within 500ms.';
      onKissWindowMissed?.call(msg);
    });
  }

  // ── Client Actions ────────────────────────────────────────────────────────

  /// Send Hug to Partner
  static void sendHug() {
    debugPrint('[HUG & KISS SERVICE] Sending hug for conv $_conversationId from user $_currentUserId');
    _triggerMediumHaptics();
    _socket?.emit('hug_send', {
      'conversationId': _conversationId,
      'senderId': _currentUserId,
    });
  }

  /// Kiss Button Touch Down (Starts touch hold with server timestamp)
  static void touchDownKiss() {
    debugPrint('[HUG & KISS SERVICE] touchDownKiss emitted for user $_currentUserId');
    _triggerLightHaptics();
    _socket?.emit('kiss_touch_down', {
      'conversationId': _conversationId,
      'senderId': _currentUserId,
    });
  }

  /// Kiss Button Touch Up (Released hold)
  static void touchUpKiss() {
    debugPrint('[HUG & KISS SERVICE] touchUpKiss emitted for user $_currentUserId');
    _socket?.emit('kiss_touch_up', {
      'conversationId': _conversationId,
      'senderId': _currentUserId,
    });
  }

  // ── REST API Fallback & Offline Queue ─────────────────────────────────────

  /// Fetch pending undelivered hugs stored in PostgreSQL
  static Future<List<HugData>> fetchPendingHugs() async {
    try {
      final token = await AuthService.getToken();
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/hug-kiss/pending'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body['success'] == true && body['pendingHugs'] is List) {
          return (body['pendingHugs'] as List)
              .map((e) => HugData.fromJson(Map<String, dynamic>.from(e)))
              .toList();
        }
      }
    } catch (e) {
      debugPrint('[HUG & KISS SERVICE] fetchPendingHugs error: $e');
    }
    return [];
  }

  // ── Haptic Vibration Helpers (Cross-Platform Safe) ─────────────────────────

  static void _triggerLightHaptics() {
    try {
      HapticFeedback.lightImpact();
    } catch (_) {}
  }

  static void _triggerMediumHaptics() {
    try {
      HapticFeedback.mediumImpact();
    } catch (_) {}
  }

  static void _triggerHugHaptics() {
    try {
      HapticFeedback.mediumImpact();
      Timer(const Duration(milliseconds: 180), () {
        HapticFeedback.lightImpact();
      });
      Timer(const Duration(milliseconds: 360), () {
        HapticFeedback.mediumImpact();
      });
    } catch (_) {}
  }

  static void _triggerKissSuccessHaptics() {
    try {
      HapticFeedback.heavyImpact();
      Timer(const Duration(milliseconds: 140), () {
        HapticFeedback.heavyImpact();
      });
      Timer(const Duration(milliseconds: 280), () {
        HapticFeedback.mediumImpact();
      });
      Timer(const Duration(milliseconds: 440), () {
        HapticFeedback.heavyImpact();
      });
    } catch (_) {}
  }
}

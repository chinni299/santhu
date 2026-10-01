import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

/// A single normalized trail point.
class TrailPoint {
  final double x; // 0.0 – 1.0 (relative to canvas width)
  final double y; // 0.0 – 1.0 (relative to canvas height)
  final int timestamp; // ms since epoch

  const TrailPoint({required this.x, required this.y, required this.timestamp});

  Map<String, dynamic> toMap() => {'x': x, 'y': y, 't': timestamp};

  factory TrailPoint.fromMap(Map<String, dynamic> m) => TrailPoint(
        x: (m['x'] as num).toDouble(),
        y: (m['y'] as num).toDouble(),
        timestamp: (m['t'] ?? m['timestamp'] ?? DateTime.now().millisecondsSinceEpoch as num).toInt(),
      );
}

/// Manages socket communication for the Live Finger Trail feature.
class FingerTrailService {
  static io.Socket? _socket;
  static int _conversationId = 1;
  static int _currentUserId = 1;

  // ── Global / App-Level Callbacks ──────────────────────────────────────────
  /// Called at app level (e.g. ChatScreen) so partner auto-opens when one starts
  static void Function(bool isOpen, int userId)? onGlobalPartnerStatus;

  // ── Active Overlay Callbacks ──────────────────────────────────────────────
  /// Called when the partner opens or closes the overlay.
  static void Function(bool isOpen, int userId)? onPartnerStatus;

  /// Called when a batch of partner trail points arrives.
  static void Function(List<TrailPoint> points)? onPartnerPoints;

  // ── Internal emit buffer ──────────────────────────────────────────────────
  static final List<TrailPoint> _buffer = [];
  static Timer? _flushTimer;

  /// Target: ~40 emits/sec (25 ms flush interval).
  static const int _flushIntervalMs = 25;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  static void initialize(io.Socket? socket, int conversationId, [int userId = 1]) {
    _socket = socket;
    _conversationId = conversationId;
    _currentUserId = userId;
    _attachListeners();
  }

  static void _attachListeners() {
    if (_socket == null) return;

    _socket?.off('fingerTrail_partnerStatus');
    _socket?.off('fingerTrail_points');

    _socket?.on('fingerTrail_partnerStatus', (data) {
      if (data == null) return;
      final isOpen = data['isOpen'] == true;
      final userId = (data['userId'] as num?)?.toInt() ?? 0;
      debugPrint('[FINGER TRAIL SERVICE] Partner status received: isOpen=$isOpen, userId=$userId');
      onPartnerStatus?.call(isOpen, userId);
      onGlobalPartnerStatus?.call(isOpen, userId);
    });

    _socket?.on('fingerTrail_points', (data) {
      if (data == null || data['points'] == null) return;
      try {
        final rawList = data['points'] as List;
        final senderId = (data['senderId'] as num?)?.toInt();
        // Ignore own points if echoed back
        if (senderId != null && senderId == _currentUserId) return;

        final localNow = DateTime.now().millisecondsSinceEpoch;
        final count = rawList.length;
        final points = <TrailPoint>[];
        for (int i = 0; i < count; i++) {
          final p = rawList[i];
          if (p is Map) {
            final x = (p['x'] as num).toDouble();
            final y = (p['y'] as num).toDouble();
            // Stagger points slightly backward from localNow to prevent clock skew issues
            final t = localNow - ((count - 1 - i) * 15);
            points.add(TrailPoint(x: x, y: y, timestamp: t));
          }
        }

        if (points.isNotEmpty) {
          debugPrint('[FINGER TRAIL SERVICE] Received ${points.length} partner points from $senderId');
          onPartnerPoints?.call(points);
        }
      } catch (e) {
        debugPrint('[FINGER TRAIL SERVICE] Error parsing points: $e');
      }
    });
  }

  /// Call when the user opens the Touch Together overlay.
  static void openOverlay([int? userId]) {
    if (userId != null) _currentUserId = userId;
    _attachListeners();
    _socket?.emit('fingerTrail_open', {
      'conversationId': _conversationId,
      'userId': _currentUserId,
    });
    _startFlushTimer();
    debugPrint('[FINGER TRAIL SERVICE] Overlay opened (conv: $_conversationId, user: $_currentUserId)');
  }

  /// Call when the user closes the Touch Together overlay.
  static void closeOverlay() {
    _stopFlushTimer();
    _buffer.clear();
    _socket?.emit('fingerTrail_close', {
      'conversationId': _conversationId,
      'userId': _currentUserId,
    });
    debugPrint('[FINGER TRAIL SERVICE] Overlay closed');
  }

  /// Add a point to the outgoing buffer (called on every pointer move).
  static void addPoint(double nx, double ny) {
    _buffer.add(TrailPoint(
      x: nx,
      y: ny,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  // ── Flush timer ───────────────────────────────────────────────────────────

  static void _startFlushTimer() {
    _flushTimer?.cancel();
    _flushTimer =
        Timer.periodic(const Duration(milliseconds: _flushIntervalMs), (_) => _flush());
  }

  static void _stopFlushTimer() {
    _flushTimer?.cancel();
    _flushTimer = null;
  }

  static void _flush() {
    if (_buffer.isEmpty || _socket == null) return;
    final points = _buffer.map((p) => p.toMap()).toList();
    _buffer.clear();
    _socket!.emit('fingerTrail_points', {
      'conversationId': _conversationId,
      'senderId': _currentUserId,
      'points': points,
    });
  }
}

import 'dart:async';
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
        timestamp: (m['t'] as num).toInt(),
      );
}

/// Manages socket communication for the Live Finger Trail feature.
///
/// Call [initialize] once when the socket is ready, then [openOverlay] when
/// the canvas opens and [closeOverlay] when it closes.
class FingerTrailService {
  static io.Socket? _socket;
  static int _conversationId = 1;

  // ── External callbacks ────────────────────────────────────────────────────
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

  static void initialize(io.Socket? socket, int conversationId) {
    _socket = socket;
    _conversationId = conversationId;
    _attachListeners();
  }

  static void _attachListeners() {
    _socket?.on('fingerTrail_partnerStatus', (data) {
      if (data == null) return;
      final isOpen = data['isOpen'] == true;
      final userId = (data['userId'] as num?)?.toInt() ?? 0;
      onPartnerStatus?.call(isOpen, userId);
    });

    _socket?.on('fingerTrail_points', (data) {
      if (data == null || data['points'] == null) return;
      try {
        final rawList = data['points'] as List;
        final points = rawList
            .whereType<Map>()
            .map((p) => TrailPoint.fromMap(Map<String, dynamic>.from(p)))
            .toList();
        if (points.isNotEmpty) onPartnerPoints?.call(points);
      } catch (_) {}
    });
  }

  /// Call when the user opens the Touch Together overlay.
  static void openOverlay() {
    _socket?.emit('fingerTrail_open', {'conversationId': _conversationId});
    _startFlushTimer();
  }

  /// Call when the user closes the Touch Together overlay.
  static void closeOverlay() {
    _stopFlushTimer();
    _buffer.clear();
    _socket?.emit('fingerTrail_close', {'conversationId': _conversationId});
    _socket?.off('fingerTrail_partnerStatus');
    _socket?.off('fingerTrail_points');
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
        Timer.periodic(Duration(milliseconds: _flushIntervalMs), (_) => _flush());
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
      'points': points,
    });
  }
}

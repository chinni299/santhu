import 'package:flutter/material.dart';
import 'finger_trail_service.dart';

/// CustomPainter for the Live Finger Trail canvas.
///
/// Takes a [repaint] listenable (AnimationController) so Flutter calls paint()
/// at the vsync rate WITHOUT rebuilding the widget tree.
/// Reads DateTime.now() directly in paint() — no need for a nowMs parameter.
class FingerTrailPainter extends CustomPainter {
  final List<TrailPoint> myPoints;
  final List<TrailPoint> partnerPoints;
  final Color myColor;
  final Color partnerColor;

  const FingerTrailPainter({
    required this.myPoints,
    required this.partnerPoints,
    required this.myColor,
    required this.partnerColor,
    required Listenable repaint,
  }) : super(repaint: repaint);

  static const double _fadeDurationMs = 2000.0;
  static const double _maxStrokeWidth = 24.0;

  @override
  void paint(Canvas canvas, Size size) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    _drawTrail(canvas, size, myPoints, myColor, nowMs);
    _drawTrail(canvas, size, partnerPoints, partnerColor, nowMs);
  }

  void _drawTrail(
      Canvas canvas, Size size, List<TrailPoint> pts, Color color, int nowMs) {
    if (pts.isEmpty) return;

    for (int i = 1; i < pts.length; i++) {
      final p0 = pts[i - 1];
      final p1 = pts[i];

      final age = (nowMs - p0.timestamp).clamp(0, _fadeDurationMs.toInt());
      final alpha = 1.0 - (age / _fadeDurationMs);
      if (alpha <= 0.01) continue;

      // Taper: newer segments are thicker
      final progress = i / pts.length;
      final strokeW =
          (_maxStrokeWidth * progress * alpha).clamp(1.5, _maxStrokeWidth);

      final x0 = p0.x * size.width;
      final y0 = p0.y * size.height;
      final x1 = p1.x * size.width;
      final y1 = p1.y * size.height;

      // Glow layer
      canvas.drawLine(
        Offset(x0, y0),
        Offset(x1, y1),
        Paint()
          ..color = color.withValues(alpha: alpha * 0.25)
          ..strokeWidth = strokeW * 2.8
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10)
          ..style = PaintingStyle.stroke,
      );

      // Core stroke
      canvas.drawLine(
        Offset(x0, y0),
        Offset(x1, y1),
        Paint()
          ..color = color.withValues(alpha: alpha * 0.92)
          ..strokeWidth = strokeW
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke,
      );
    }

    // Bright cursor dot at the most recent point
    if (pts.isNotEmpty) {
      final last = pts.last;
      final age = (nowMs - last.timestamp).clamp(0, _fadeDurationMs.toInt());
      final alpha = 1.0 - (age / _fadeDurationMs);
      if (alpha > 0.01) {
        final cx = last.x * size.width;
        final cy = last.y * size.height;

        // Outer glow
        canvas.drawCircle(
          Offset(cx, cy),
          14 * alpha,
          Paint()
            ..color = color.withValues(alpha: alpha * 0.4)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12)
            ..style = PaintingStyle.fill,
        );

        // Inner white dot
        canvas.drawCircle(
          Offset(cx, cy),
          7 * alpha,
          Paint()
            ..color = Colors.white.withValues(alpha: alpha * 0.95)
            ..style = PaintingStyle.fill,
        );
      }
    }
  }

  @override
  bool shouldRepaint(FingerTrailPainter old) => true;
}

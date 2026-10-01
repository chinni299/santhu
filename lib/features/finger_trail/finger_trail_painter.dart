import 'package:flutter/material.dart';
import 'finger_trail_service.dart';

/// CustomPainter for the Live Finger Trail canvas (Touch Together).
///
/// Uses multi-pass alpha layering instead of MaskFilter.blur to guarantee 100%
/// WebGL/CanvasKit/Mobile GPU compatibility and high performance.
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

  // Keep trail visible for 4.5 seconds so handwriting / drawings can be easily read
  static const double _fadeDurationMs = 4500.0;
  static const double _maxStrokeWidth = 16.0;

  @override
  void paint(Canvas canvas, Size size) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    _drawTrail(canvas, size, partnerPoints, partnerColor, nowMs);
    _drawTrail(canvas, size, myPoints, myColor, nowMs);
  }

  void _drawTrail(
      Canvas canvas, Size size, List<TrailPoint> pts, Color color, int nowMs) {
    if (pts.isEmpty) return;

    for (int i = 0; i < pts.length; i++) {
      final p = pts[i];
      final age = (nowMs - p.timestamp).clamp(0, _fadeDurationMs.toInt());
      final alpha = (1.0 - (age / _fadeDurationMs)).clamp(0.0, 1.0);
      if (alpha <= 0.01) continue;

      final pPos = Offset(p.x * size.width, p.y * size.height);

      if (i > 0) {
        final p0 = pts[i - 1];
        // If points were drawn close together in time, connect them with smooth lines
        if ((p.timestamp - p0.timestamp).abs() <= 600) {
          final pStart = Offset(p0.x * size.width, p0.y * size.height);
          final strokeW = (_maxStrokeWidth * alpha).clamp(3.0, _maxStrokeWidth);

          // Layer 1: Outer Neon Glow
          canvas.drawLine(
            pStart,
            pPos,
            Paint()
              ..color = color.withValues(alpha: alpha * 0.25)
              ..strokeWidth = strokeW * 3.0
              ..strokeCap = StrokeCap.round
              ..strokeJoin = StrokeJoin.round
              ..style = PaintingStyle.stroke,
          );

          // Layer 2: Mid Neon Halo
          canvas.drawLine(
            pStart,
            pPos,
            Paint()
              ..color = color.withValues(alpha: alpha * 0.60)
              ..strokeWidth = strokeW * 1.6
              ..strokeCap = StrokeCap.round
              ..strokeJoin = StrokeJoin.round
              ..style = PaintingStyle.stroke,
          );

          // Layer 3: Vibrant Core Stroke
          canvas.drawLine(
            pStart,
            pPos,
            Paint()
              ..color = color.withValues(alpha: alpha * 0.95)
              ..strokeWidth = strokeW
              ..strokeCap = StrokeCap.round
              ..strokeJoin = StrokeJoin.round
              ..style = PaintingStyle.stroke,
          );

          // Layer 4: Center Bright White Core
          if (strokeW > 5.0) {
            canvas.drawLine(
              pStart,
              pPos,
              Paint()
                ..color = Colors.white.withValues(alpha: alpha * 0.85)
                ..strokeWidth = strokeW * 0.35
                ..strokeCap = StrokeCap.round
                ..strokeJoin = StrokeJoin.round
                ..style = PaintingStyle.stroke,
            );
          }
        }
      }

      // Draw dot for points
      if (i == pts.length - 1 || pts.length == 1) {
        // Outer Glow Aura
        canvas.drawCircle(
          pPos,
          16 * alpha,
          Paint()
            ..color = color.withValues(alpha: alpha * 0.30)
            ..style = PaintingStyle.fill,
        );

        // Mid Halo
        canvas.drawCircle(
          pPos,
          9 * alpha,
          Paint()
            ..color = color.withValues(alpha: alpha * 0.65)
            ..style = PaintingStyle.fill,
        );

        // Bright Center Orb
        canvas.drawCircle(
          pPos,
          5 * alpha,
          Paint()
            ..color = Colors.white.withValues(alpha: alpha * 0.98)
            ..style = PaintingStyle.fill,
        );
      }
    }
  }

  @override
  bool shouldRepaint(FingerTrailPainter old) => true;
}

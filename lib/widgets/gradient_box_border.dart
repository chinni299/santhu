import 'package:flutter/material.dart';

/// A custom BoxBorder that paints a gradient border around a box.
/// Used for glassmorphism chat bubbles with two-color gradient borders.
class GradientBoxBorder extends BoxBorder {
  final Gradient gradient;
  final double width;

  const GradientBoxBorder({
    required this.gradient,
    this.width = 1.0,
  });

  @override
  BorderSide get bottom => BorderSide.none;

  @override
  BorderSide get top => BorderSide.none;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(width);

  @override
  bool get isUniform => true;

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    TextDirection? textDirection,
    BoxShape shape = BoxShape.rectangle,
    BorderRadius? borderRadius,
  }) {
    final paint = Paint()
      ..shader = gradient.createShader(rect)
      ..strokeWidth = width
      ..style = PaintingStyle.stroke;

    if (shape == BoxShape.circle) {
      final center = rect.center;
      final radius = (rect.shortestSide - width) / 2.0;
      canvas.drawCircle(center, radius, paint);
    } else if (borderRadius != null) {
      final rrect = borderRadius
          .resolve(textDirection)
          .toRRect(rect)
          .deflate(width / 2.0);
      canvas.drawRRect(rrect, paint);
    } else {
      final adjustedRect = rect.deflate(width / 2.0);
      canvas.drawRect(adjustedRect, paint);
    }
  }

  @override
  ShapeBorder scale(double t) {
    return GradientBoxBorder(
      gradient: gradient,
      width: width * t,
    );
  }
}

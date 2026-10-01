import 'dart:math';
import 'package:flutter/material.dart';
import 'shared_sky_model.dart';

class ShootingStar {
  double startX;
  double startY;
  double endX;
  double endY;
  double progress; // 0.0 to 1.0
  double speed;
  double length;
  Color color;

  ShootingStar({
    required this.startX,
    required this.startY,
    required this.endX,
    required this.endY,
    required this.progress,
    required this.speed,
    required this.length,
    required this.color,
  });
}

class SharedSkyPainter extends CustomPainter {
  final List<CelestialStar> stars;
  final Map<int, NamedStar> namedStars;
  final int? selectedStarIndex;
  final int? partnerHoverStarIndex;
  final bool partnerIsHere;
  final double animationValue; // 0.0 -> 2*pi
  final List<ShootingStar> shootingStars;

  SharedSkyPainter({
    required this.stars,
    required this.namedStars,
    this.selectedStarIndex,
    this.partnerHoverStarIndex,
    this.partnerIsHere = false,
    required this.animationValue,
    required this.shootingStars,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawDeepSkyBackground(canvas, size);
    _drawNebulaClouds(canvas, size);
    _drawShootingStars(canvas, size);
    _drawStars(canvas, size);
    _drawPartnerHoverEffect(canvas, size);
    _drawSelectedStarIndicator(canvas, size);
    _drawNamedStarBadges(canvas, size);
  }

  void _drawDeepSkyBackground(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF030511), // Deep Cosmic Void
          Color(0xFF080D21), // Midnight Navy
          Color(0xFF0D1432), // Dark Sapphire
          Color(0xFF140C28), // Deep Violet Horizon
        ],
        stops: [0.0, 0.35, 0.70, 1.0],
      ).createShader(rect);

    canvas.drawRect(rect, bgPaint);
  }

  void _drawNebulaClouds(Canvas canvas, Size size) {
    // Subtle cosmic dust clouds
    final nebula1 = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0x286D28D9), // Soft Violet Glow
          Colors.transparent,
        ],
        radius: 0.6,
      ).createShader(Rect.fromCircle(
        center: Offset(size.width * 0.3, size.height * 0.35),
        radius: size.width * 0.5,
      ));
    canvas.drawCircle(Offset(size.width * 0.3, size.height * 0.35), size.width * 0.5, nebula1);

    final nebula2 = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0x221E40AF), // Soft Deep Cyan Glow
          Colors.transparent,
        ],
        radius: 0.5,
      ).createShader(Rect.fromCircle(
        center: Offset(size.width * 0.75, size.height * 0.65),
        radius: size.width * 0.45,
      ));
    canvas.drawCircle(Offset(size.width * 0.75, size.height * 0.65), size.width * 0.45, nebula2);
  }

  void _drawShootingStars(Canvas canvas, Size size) {
    for (final s in shootingStars) {
      if (s.progress <= 0 || s.progress >= 1.0) continue;

      final currentX = s.startX + (s.endX - s.startX) * s.progress;
      final currentY = s.startY + (s.endY - s.startY) * s.progress;

      final tailProgress = (s.progress - s.length).clamp(0.0, 1.0);
      final tailX = s.startX + (s.endX - s.startX) * tailProgress;
      final tailY = s.startY + (s.endY - s.startY) * tailProgress;

      final headOffset = Offset(currentX * size.width, currentY * size.height);
      final tailOffset = Offset(tailX * size.width, tailY * size.height);

      // Fade in at start and fade out at end
      double opacity = 1.0;
      if (s.progress < 0.2) {
        opacity = s.progress / 0.2;
      } else if (s.progress > 0.8) {
        opacity = (1.0 - s.progress) / 0.2;
      }

      final tailPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            s.color.withValues(alpha: 0.0),
            s.color.withValues(alpha: 0.85 * opacity),
            Colors.white.withValues(alpha: 0.95 * opacity),
          ],
          stops: const [0.0, 0.7, 1.0],
        ).createShader(Rect.fromPoints(tailOffset, headOffset))
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(tailOffset, headOffset, tailPaint);

      // Star head glow
      final headGlow = Paint()
        ..color = Colors.white.withValues(alpha: 0.85 * opacity);
      canvas.drawCircle(headOffset, 3.5, headGlow);
    }
  }

  void _drawStars(Canvas canvas, Size size) {
    for (final star in stars) {
      final pos = Offset(star.x * size.width, star.y * size.height);
      final isNamed = namedStars.containsKey(star.index);

      // Twinkle calculation
      final twinkle = sin(animationValue * star.twinkleSpeed + star.twinklePhase);
      final normalizedTwinkle = (twinkle + 1.0) / 2.0; // 0.0 -> 1.0
      final alpha = (star.brightness * (0.45 + 0.55 * normalizedTwinkle)).clamp(0.1, 1.0);

      if (isNamed) {
        // Named Star Aura & Halo
        _drawNamedStarHalo(canvas, pos, star, normalizedTwinkle);
      } else {
        // Normal Twinkling Star
        final starPaint = Paint()..color = star.baseColor.withValues(alpha: alpha);
        final currentRadius = star.radius * (0.85 + 0.3 * normalizedTwinkle);

        // Soft outer glow for medium/large stars
        if (star.radius > 2.0) {
          final glowPaint = Paint()
            ..color = star.baseColor.withValues(alpha: alpha * 0.25);
          canvas.drawCircle(pos, currentRadius * 1.8, glowPaint);
        }

        canvas.drawCircle(pos, currentRadius, starPaint);

        // Diamond Cross Glint for very bright stars
        if (star.radius > 2.8 && normalizedTwinkle > 0.65) {
          _drawStarCrossGlint(canvas, pos, star.baseColor, currentRadius * 2.4, alpha * 0.7);
        }
      }
    }
  }

  void _drawNamedStarHalo(Canvas canvas, Offset pos, CelestialStar star, double twinkle) {
    final pulse = 0.8 + 0.3 * sin(animationValue * 2.5 + star.index);

    // Warm Golden / Rose Cosmic Corona
    final auraPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFFFD700).withValues(alpha: 0.55 * pulse),
          const Color(0xFFFF69B4).withValues(alpha: 0.35 * pulse),
          Colors.transparent,
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(Rect.fromCircle(center: pos, radius: 24 * pulse));
    canvas.drawCircle(pos, 24 * pulse, auraPaint);

    // Golden Core
    final coreGlow = Paint()
      ..color = const Color(0xFFFFF099).withValues(alpha: 0.75);
    canvas.drawCircle(pos, star.radius * 2.0, coreGlow);

    // Brilliant White Center
    final centerPaint = Paint()..color = Colors.white;
    canvas.drawCircle(pos, star.radius * 1.3, centerPaint);

    // Star Diamond Cross Shine
    _drawStarCrossGlint(canvas, pos, const Color(0xFFFFEAA7), 16 * pulse, 0.95);
  }

  void _drawStarCrossGlint(Canvas canvas, Offset center, Color color, double rayLength, double opacity) {
    final rayPaint = Paint()
      ..color = color.withValues(alpha: opacity)
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(center.dx - rayLength, center.dy),
      Offset(center.dx + rayLength, center.dy),
      rayPaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - rayLength),
      Offset(center.dx, center.dy + rayLength),
      rayPaint,
    );
  }

  void _drawPartnerHoverEffect(Canvas canvas, Size size) {
    if (partnerHoverStarIndex == null) return;
    if (partnerHoverStarIndex! < 0 || partnerHoverStarIndex! >= stars.length) return;

    final star = stars[partnerHoverStarIndex!];
    final pos = Offset(star.x * size.width, star.y * size.height);
    final wave = (sin(animationValue * 4.0) + 1.0) / 2.0;

    // Partner Soft Radiant Pulse (Rose / Cyan Love Wave)
    final partnerAura = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFFF4081).withValues(alpha: 0.65),
          const Color(0xFFE040FB).withValues(alpha: 0.35),
          Colors.transparent,
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromCircle(center: pos, radius: 30 + 10 * wave));

    canvas.drawCircle(pos, 30 + 10 * wave, partnerAura);

    // Partner Ring Indicator
    final ringPaint = Paint()
      ..color = const Color(0xFFFF80AB).withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    canvas.drawCircle(pos, 16 + 4 * wave, ringPaint);
  }

  void _drawSelectedStarIndicator(Canvas canvas, Size size) {
    if (selectedStarIndex == null) return;
    if (selectedStarIndex! < 0 || selectedStarIndex! >= stars.length) return;

    final star = stars[selectedStarIndex!];
    final pos = Offset(star.x * size.width, star.y * size.height);
    final rotate = animationValue * 1.5;

    final reticlePaint = Paint()
      ..color = const Color(0xFF64B5F6).withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // Draw interactive target ring with 4 tick marks
    canvas.drawCircle(pos, 15, reticlePaint);

    for (int i = 0; i < 4; i++) {
      final angle = rotate + i * (pi / 2);
      final p1 = Offset(pos.dx + cos(angle) * 12, pos.dy + sin(angle) * 12);
      final p2 = Offset(pos.dx + cos(angle) * 19, pos.dy + sin(angle) * 19);
      canvas.drawLine(p1, p2, reticlePaint);
    }
  }

  void _drawNamedStarBadges(Canvas canvas, Size size) {
    for (final entry in namedStars.entries) {
      final starIdx = entry.key;
      final namedStar = entry.value;
      if (starIdx < 0 || starIdx >= stars.length) continue;

      final star = stars[starIdx];
      final pos = Offset(star.x * size.width, star.y * size.height);

      // Render star name badge below the star
      final textSpan = TextSpan(
        text: '✨ ${namedStar.starName}',
        style: const TextStyle(
          color: Color(0xFFFFF9E6),
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      );

      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout();

      final badgeWidth = textPainter.width + 14;
      final badgeHeight = textPainter.height + 6;
      final badgeRect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(pos.dx, pos.dy + 20),
          width: badgeWidth,
          height: badgeHeight,
        ),
        const Radius.circular(10),
      );

      // Glassmorphic pill badge background
      final pillPaint = Paint()
        ..color = const Color(0xBB0F172A)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(badgeRect, pillPaint);

      final borderPaint = Paint()
        ..color = const Color(0x66FFD700)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8;
      canvas.drawRRect(badgeRect, borderPaint);

      textPainter.paint(
        canvas,
        Offset(pos.dx - textPainter.width / 2, pos.dy + 20 - textPainter.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant SharedSkyPainter oldDelegate) => true;
}

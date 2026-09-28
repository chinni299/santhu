import 'package:flutter/material.dart';

class VoiceWaveformWidget extends StatelessWidget {
  final List<double> amplitudes;
  final double progress; // 0.0 to 1.0
  final Color activeColor;
  final Color inactiveColor;

  const VoiceWaveformWidget({
    super.key,
    required this.amplitudes,
    this.progress = 0.0,
    this.activeColor = const Color(0xFF00B4D8),
    this.inactiveColor = Colors.grey,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(double.infinity, 32),
      painter: _WaveformPainter(
        amplitudes: amplitudes.isEmpty
            ? List.generate(24, (i) => ((i * 7) % 15 + 5) / 20.0)
            : amplitudes,
        progress: progress,
        activeColor: activeColor,
        inactiveColor: inactiveColor,
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> amplitudes;
  final double progress;
  final Color activeColor;
  final Color inactiveColor;

  _WaveformPainter({
    required this.amplitudes,
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (amplitudes.isEmpty) return;

    final barWidth = 3.0;
    final spacing = 2.0;
    final totalBarWidth = barWidth + spacing;
    final count = (size.width / totalBarWidth).floor();

    final activeIndex = (count * progress).floor();

    final paintActive = Paint()
      ..color = activeColor
      ..strokeCap = StrokeCap.round
      ..strokeWidth = barWidth;

    final paintInactive = Paint()
      ..color = inactiveColor.withOpacity(0.4)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = barWidth;

    for (int i = 0; i < count; i++) {
      final amp = amplitudes[i % amplitudes.length].clamp(0.1, 1.0);
      final height = size.height * amp;
      final x = i * totalBarWidth + barWidth / 2;
      final yTop = (size.height - height) / 2;
      final yBottom = yTop + height;

      final p = i <= activeIndex ? paintActive : paintInactive;
      canvas.drawLine(Offset(x, yTop), Offset(x, yBottom), p);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.amplitudes != amplitudes ||
        oldDelegate.activeColor != activeColor;
  }
}

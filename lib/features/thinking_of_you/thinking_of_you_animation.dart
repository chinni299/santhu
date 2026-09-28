import 'dart:math' as math;
import 'package:flutter/material.dart';

class ThinkingOfYouAnimation extends StatefulWidget {
  final VoidCallback onComplete;

  const ThinkingOfYouAnimation({super.key, required this.onComplete});

  @override
  State<ThinkingOfYouAnimation> createState() => _ThinkingOfYouAnimationState();
}

class _ThinkingOfYouAnimationState extends State<ThinkingOfYouAnimation> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final _random = math.Random();
  late List<_HeartParticle> _particles;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );

    _particles = List.generate(16, (index) {
      return _HeartParticle(
        x: _random.nextDouble() * 0.8 + 0.1,
        startY: 1.0,
        speed: _random.nextDouble() * 0.5 + 0.5,
        size: _random.nextDouble() * 20 + 20,
      );
    });

    _controller.forward().then((_) {
      if (mounted) widget.onComplete();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final progress = _controller.value;
          return Stack(
            children: [
              Container(
                color: Colors.pinkAccent.withValues(alpha: (1.0 - progress) * 0.15),
              ),
              ..._particles.map((p) {
                final currentY = p.startY - (progress * p.speed);
                final opacity = (1.0 - progress).clamp(0.0, 1.0);

                return Positioned(
                  left: MediaQuery.of(context).size.width * p.x,
                  top: MediaQuery.of(context).size.height * currentY,
                  child: Opacity(
                    opacity: opacity,
                    child: Icon(
                      Icons.favorite_rounded,
                      color: Colors.pinkAccent,
                      size: p.size,
                    ),
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }
}

class _HeartParticle {
  final double x;
  final double startY;
  final double speed;
  final double size;

  _HeartParticle({
    required this.x,
    required this.startY,
    required this.speed,
    required this.size,
  });
}

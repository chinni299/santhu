import 'package:flutter/material.dart';

class DisappearingTimerWidget extends StatelessWidget {
  final int? expiresAtMs;

  const DisappearingTimerWidget({super.key, this.expiresAtMs});

  @override
  Widget build(BuildContext context) {
    if (expiresAtMs == null) return const SizedBox.shrink();

    final remainingMs = expiresAtMs! - DateTime.now().millisecondsSinceEpoch;
    if (remainingMs <= 0) return const SizedBox.shrink();

    final remainingSecs = (remainingMs / 1000).ceil();
    String text;
    if (remainingSecs < 60) {
      text = '${remainingSecs}s';
    } else if (remainingSecs < 3600) {
      text = '${(remainingSecs / 60).ceil()}m';
    } else {
      text = '${(remainingSecs / 3600).ceil()}h';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timer_outlined, size: 11, color: Colors.white70),
          const SizedBox(width: 3),
          Text(
            text,
            style: const TextStyle(fontSize: 10, color: Colors.white70, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../important_dates/important_date.dart';

class CountdownWidget extends StatefulWidget {
  final ImportantDate targetDate;

  const CountdownWidget({super.key, required this.targetDate});

  @override
  State<CountdownWidget> createState() => _CountdownWidgetState();
}

class _CountdownWidgetState extends State<CountdownWidget> {
  Timer? _timer;
  late Duration _remaining;

  @override
  void initState() {
    super.initState();
    _calculateRemaining();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        _calculateRemaining();
      }
    });
  }

  void _calculateRemaining() {
    final target = widget.targetDate.nextEventDate;
    final now = DateTime.now();
    setState(() {
      _remaining = target.isBefore(now) ? Duration.zero : target.difference(now);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final days = _remaining.inDays;
    final hours = _remaining.inHours % 24;
    final minutes = _remaining.inMinutes % 60;
    final seconds = _remaining.inSeconds % 60;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primaryTeal.withOpacity(0.4)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.hourglass_top, color: AppTheme.primaryTeal, size: 16),
              const SizedBox(width: 6),
              Text(
                widget.targetDate.title,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildTimeUnit(days.toString(), 'Days'),
              _buildTimeUnit(hours.toString().padLeft(2, '0'), 'Hrs'),
              _buildTimeUnit(minutes.toString().padLeft(2, '0'), 'Mins'),
              _buildTimeUnit(seconds.toString().padLeft(2, '0'), 'Secs'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimeUnit(String value, String unit) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppTheme.primaryTeal),
        ),
        Text(
          unit,
          style: const TextStyle(fontSize: 10, color: Colors.grey),
        ),
      ],
    );
  }
}

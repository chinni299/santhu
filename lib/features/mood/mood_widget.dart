import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'mood.dart';

class MoodWidget extends StatelessWidget {
  final UserMood? userMood;
  final VoidCallback? onTap;

  const MoodWidget({
    super.key,
    this.userMood,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (userMood == null || userMood!.moodType == null) return const SizedBox.shrink();

    final mood = userMood!.moodType!;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppTheme.primaryTeal.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(mood.emoji, style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 4),
            Text(
              mood.label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

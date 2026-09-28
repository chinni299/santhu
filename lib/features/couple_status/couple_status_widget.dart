import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'couple_status.dart';

class CoupleStatusWidget extends StatelessWidget {
  final CoupleStatus? status;
  final VoidCallback? onTap;

  const CoupleStatusWidget({
    super.key,
    this.status,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (status == null) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppTheme.primaryTeal.withValues(alpha: 0.4),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(status!.statusType.emoji, style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 4),
            Text(
              status!.statusType == CoupleStatusType.custom && status!.customText != null
                  ? status!.customText!
                  : status!.statusType.label,
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

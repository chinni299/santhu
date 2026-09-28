import 'package:flutter/material.dart';

class ReactionWidget extends StatelessWidget {
  final Map<String, dynamic> reactions;
  final int currentUserId;
  final VoidCallback? onTap;

  const ReactionWidget({
    super.key,
    required this.reactions,
    required this.currentUserId,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (reactions.isEmpty) return const SizedBox.shrink();

    final reactionList = <String>[];
    reactions.forEach((userId, emoji) {
      if (emoji != null && emoji.toString().isNotEmpty) {
        reactionList.add(emoji.toString());
      }
    });

    if (reactionList.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? Colors.white12 : Colors.black12,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              reactionList.join(' '),
              style: const TextStyle(fontSize: 13),
            ),
            if (reactionList.length > 1) ...[
              const SizedBox(width: 4),
              Text(
                '${reactionList.length}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

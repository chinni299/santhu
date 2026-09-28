import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class ReplyMessageWidget extends StatelessWidget {
  final String senderName;
  final String messageText;
  final bool isMe;
  final VoidCallback? onTap;

  const ReplyMessageWidget({
    super.key,
    required this.senderName,
    required this.messageText,
    required this.isMe,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isMe
              ? Colors.black.withValues(alpha: 0.15)
              : AppTheme.primaryTeal.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border(
            left: BorderSide(
              color: isMe ? Colors.white : AppTheme.primaryTeal,
              width: 3.5,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              senderName,
              style: TextStyle(
                color: isMe ? Colors.white : AppTheme.primaryTeal,
                fontWeight: FontWeight.bold,
                fontSize: 11.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              messageText,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isMe ? Colors.white.withValues(alpha: 0.9) : Colors.black87,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

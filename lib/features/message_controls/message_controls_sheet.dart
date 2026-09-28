import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../message_reactions/reaction_picker.dart';

class MessageControlsSheet extends StatelessWidget {
  final Map<String, dynamic> message;
  final int currentUserId;
  final Function(String emoji) onReact;
  final VoidCallback onReply;
  final VoidCallback onCopy;
  final VoidCallback? onEdit;
  final VoidCallback onDeleteForMe;
  final VoidCallback? onDeleteForEveryone;
  final VoidCallback onTogglePin;
  final bool isPinned;

  const MessageControlsSheet({
    super.key,
    required this.message,
    required this.currentUserId,
    required this.onReact,
    required this.onReply,
    required this.onCopy,
    this.onEdit,
    required this.onDeleteForMe,
    this.onDeleteForEveryone,
    required this.onTogglePin,
    required this.isPinned,
  });

  @override
  Widget build(BuildContext context) {
    final senderId = int.tryParse((message['senderId'] ?? message['sender_id'] ?? 0).toString()) ?? 0;
    final isMe = senderId == currentUserId;
    final isDeleted = message['isDeleted'] == true || message['is_deleted'] == true;
    final hasText = message['message'] != null && message['message'].toString().isNotEmpty && !isDeleted;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF1E293B)
            : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle Bar
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Emoji Reaction Bar
            if (!isDeleted)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ReactionPicker(
                  onReactionSelected: (emoji) {
                    Navigator.pop(context);
                    onReact(emoji);
                  },
                ),
              ),

            const Divider(height: 16),

            // Action Options
            ListTile(
              leading: const Icon(Icons.reply_rounded, color: AppTheme.primaryTeal),
              title: const Text('Reply', style: TextStyle(fontWeight: FontWeight.w700)),
              onTap: () {
                Navigator.pop(context);
                onReply();
              },
            ),

            if (hasText)
              ListTile(
                leading: const Icon(Icons.copy_rounded, color: AppTheme.primaryTeal),
                title: const Text('Copy Text', style: TextStyle(fontWeight: FontWeight.w700)),
                onTap: () {
                  Navigator.pop(context);
                  onCopy();
                },
              ),

            if (!isDeleted)
              ListTile(
                leading: Icon(
                  isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                  color: AppTheme.primaryTeal,
                ),
                title: Text(isPinned ? 'Unpin Message' : 'Pin Message', style: const TextStyle(fontWeight: FontWeight.w700)),
                onTap: () {
                  Navigator.pop(context);
                  onTogglePin();
                },
              ),

            if (isMe && hasText && onEdit != null)
              ListTile(
                leading: const Icon(Icons.edit_rounded, color: AppTheme.primaryTeal),
                title: const Text('Edit Message', style: TextStyle(fontWeight: FontWeight.w700)),
                onTap: () {
                  Navigator.pop(context);
                  onEdit!();
                },
              ),

            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: Colors.orangeAccent),
              title: const Text('Delete for Me', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.orangeAccent)),
              onTap: () {
                Navigator.pop(context);
                onDeleteForMe();
              },
            ),

            if (isMe && !isDeleted && onDeleteForEveryone != null)
              ListTile(
                leading: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent),
                title: const Text('Delete for Everyone', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.redAccent)),
                onTap: () {
                  Navigator.pop(context);
                  onDeleteForEveryone!();
                },
              ),
          ],
        ),
      ),
    );
  }
}

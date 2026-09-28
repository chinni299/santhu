import 'package:flutter/material.dart';
import 'message_reaction.dart';

class ReactionPicker extends StatelessWidget {
  final Function(String emoji) onReactionSelected;
  final String? currentReaction;

  const ReactionPicker({
    super.key,
    required this.onReactionSelected,
    this.currentReaction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF1E293B)
            : Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: MessageReaction.supportedEmojis.map((emoji) {
          final isSelected = currentReaction == emoji;
          return GestureDetector(
            onTap: () => onReactionSelected(emoji),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isSelected ? Colors.teal.withValues(alpha: 0.2) : Colors.transparent,
                shape: BoxShape.circle,
              ),
              child: Transform.scale(
                scale: isSelected ? 1.25 : 1.0,
                child: Text(
                  emoji,
                  style: const TextStyle(fontSize: 24),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

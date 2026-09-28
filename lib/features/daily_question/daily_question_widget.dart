import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'daily_question_screen.dart';

class DailyQuestionWidget extends StatelessWidget {
  final String questionText;
  final bool answered;

  const DailyQuestionWidget({
    super.key,
    required this.questionText,
    required this.answered,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const DailyQuestionScreen()),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.primaryTeal.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.help_outline, color: AppTheme.primaryTeal, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                questionText,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(
              answered ? Icons.check_circle : Icons.arrow_forward_ios,
              color: answered ? Colors.green : Colors.grey,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}

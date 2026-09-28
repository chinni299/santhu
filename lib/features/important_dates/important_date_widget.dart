import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'important_date.dart';
import 'important_date_screen.dart';

class ImportantDateWidget extends StatelessWidget {
  final ImportantDate date;

  const ImportantDateWidget({super.key, required this.date});

  @override
  Widget build(BuildContext context) {
    final days = date.daysRemaining;
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ImportantDateScreen()),
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
            const Icon(Icons.favorite, color: Colors.pinkAccent, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                date.title,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.primaryTeal,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                days == 0 ? 'Today!' : '$days d',
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

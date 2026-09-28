import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../important_dates/important_date.dart';
import '../important_dates/important_date_service.dart';
import 'countdown_service.dart';
import 'countdown_widget.dart';

class CountdownScreen extends StatefulWidget {
  const CountdownScreen({super.key});

  @override
  State<CountdownScreen> createState() => _CountdownScreenState();
}

class _CountdownScreenState extends State<CountdownScreen> {
  List<ImportantDate> _dates = [];
  ImportantDate? _selectedTarget;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final dates = await ImportantDateService.getDates();
    final savedId = await CountdownService.getSelectedTargetDateId();
    ImportantDate? target;

    if (savedId != null) {
      target = dates.firstWhere((d) => d.id == savedId, orElse: () => dates.first);
    } else if (dates.isNotEmpty) {
      dates.sort((a, b) => a.daysRemaining.compareTo(b.daysRemaining));
      target = dates.first;
    }

    if (mounted) {
      setState(() {
        _dates = dates;
        _selectedTarget = target;
        _loading = false;
      });
    }
  }

  Future<void> _selectTarget(ImportantDate date) async {
    await CountdownService.setSelectedTargetDateId(date.id);
    setState(() => _selectedTarget = date);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Countdown target set to "${date.title}"')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Couple Countdown ⏳', style: TextStyle(fontWeight: FontWeight.w900)),
        backgroundColor: AppTheme.primaryTeal,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_selectedTarget != null) ...[
                  const Text('Active Countdown', style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  CountdownWidget(targetDate: _selectedTarget!),
                  const SizedBox(height: 24),
                ],
                const Text('Choose Target Event', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                if (_dates.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No important dates created yet. Add one in Important Dates settings.', style: TextStyle(color: Colors.grey)),
                  )
                else
                  ..._dates.map((d) {
                    final isSelected = _selectedTarget?.id == d.id;
                    return Card(
                      color: isSelected ? AppTheme.primaryTeal.withOpacity(0.25) : const Color(0xFF1E293B),
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: isSelected ? AppTheme.primaryTeal : Colors.transparent),
                      ),
                      child: ListTile(
                        onTap: () => _selectTarget(d),
                        leading: Icon(
                          isSelected ? Icons.check_circle : Icons.circle_outlined,
                          color: isSelected ? AppTheme.primaryTeal : Colors.grey,
                        ),
                        title: Text(d.title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                        subtitle: Text('${d.daysRemaining} days remaining', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      ),
                    );
                  }),
              ],
            ),
    );
  }
}

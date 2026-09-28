import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'add_edit_date_screen.dart';
import 'important_date.dart';
import 'important_date_service.dart';

class ImportantDateScreen extends StatefulWidget {
  const ImportantDateScreen({super.key});

  @override
  State<ImportantDateScreen> createState() => _ImportantDateScreenState();
}

class _ImportantDateScreenState extends State<ImportantDateScreen> {
  List<ImportantDate> _dates = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDates();
  }

  Future<void> _loadDates() async {
    setState(() => _loading = true);
    final list = await ImportantDateService.getDates();
    list.sort((a, b) => a.daysRemaining.compareTo(b.daysRemaining));
    if (mounted) {
      setState(() {
        _dates = list;
        _loading = false;
      });
    }
  }

  Future<void> _addDate() async {
    final result = await Navigator.push<ImportantDate>(
      context,
      MaterialPageRoute(builder: (_) => const AddEditDateScreen()),
    );
    if (result != null) {
      _loadDates();
    }
  }

  Future<void> _editDate(ImportantDate date) async {
    final result = await Navigator.push<ImportantDate>(
      context,
      MaterialPageRoute(builder: (_) => AddEditDateScreen(existingDate: date)),
    );
    if (result != null) {
      _loadDates();
    }
  }

  Future<void> _deleteDate(ImportantDate date) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Delete Date?', style: TextStyle(color: Colors.white)),
        content: Text('Are you sure you want to delete "${date.title}"?', style: const TextStyle(color: Colors.grey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ImportantDateService.deleteDate(date.id);
      _loadDates();
    }
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'birthday':
        return Icons.cake;
      case 'anniversary':
        return Icons.favorite;
      case 'first_meeting':
        return Icons.favorite_border;
      case 'custom':
      default:
        return Icons.star;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Important Dates 📅', style: TextStyle(fontWeight: FontWeight.w900)),
        backgroundColor: AppTheme.primaryTeal,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addDate,
        backgroundColor: AppTheme.primaryTeal,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _dates.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.calendar_today, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('No important dates yet', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      SizedBox(height: 8),
                      Text('Tap + to add your anniversary, birthdays, or special moments', style: TextStyle(color: Colors.grey, fontSize: 13)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _dates.length,
                  itemBuilder: (context, index) {
                    final d = _dates[index];
                    final days = d.daysRemaining;
                    String daysText = days == 0
                        ? 'Today! 🎉'
                        : days == 1
                            ? 'Tomorrow!'
                            : '$days days left';

                    return Card(
                      color: const Color(0xFF1E293B),
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppTheme.primaryTeal.withValues(alpha: 0.2),
                          child: Icon(_iconForType(d.dateType), color: AppTheme.primaryTeal),
                        ),
                        title: Text(d.title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                        subtitle: Text(
                          '${d.nextEventDate.year}-${d.nextEventDate.month.toString().padLeft(2, '0')}-${d.nextEventDate.day.toString().padLeft(2, '0')}${d.note != null ? '\n${d.note}' : ''}',
                          style: const TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: days == 0 ? Colors.pink : AppTheme.primaryTeal,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                daysText,
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert, color: Colors.grey),
                              onSelected: (val) {
                                if (val == 'edit') _editDate(d);
                                if (val == 'delete') _deleteDate(d);
                              },
                              itemBuilder: (ctx) => [
                                const PopupMenuItem(value: 'edit', child: Text('Edit', style: TextStyle(color: Colors.white))),
                                const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.red))),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

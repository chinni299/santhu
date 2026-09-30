import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../config/api_config.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

/// Shared Countdown / Anniversary Tracker — dates that matter to the two of
/// you (anniversaries, birthdays, trips...), each shown with a live
/// "X days to go" countdown. Recurring dates count down to their next
/// occurrence every year automatically.
class SpecialDatesScreen extends StatefulWidget {
  final io.Socket? socket;
  final int conversationId;
  final int currentUserId;

  const SpecialDatesScreen({
    super.key,
    required this.socket,
    required this.conversationId,
    required this.currentUserId,
  });

  @override
  State<SpecialDatesScreen> createState() => _SpecialDatesScreenState();
}

class _SpecialDatesScreenState extends State<SpecialDatesScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _dates = [];

  @override
  void initState() {
    super.initState();
    _load();
    widget.socket?.on('specialDateAdded', _onDateAdded);
    widget.socket?.on('specialDateDeleted', _onDateDeleted);
  }

  @override
  void dispose() {
    widget.socket?.off('specialDateAdded', _onDateAdded);
    widget.socket?.off('specialDateDeleted', _onDateDeleted);
    super.dispose();
  }

  void _onDateAdded(dynamic data) {
    if (data == null) return;
    final convId = data['conversationId'];
    if (convId != null && convId.toString() != widget.conversationId.toString()) return;
    final newDate = data['date'];
    if (newDate == null || !mounted) return;
    setState(() {
      _dates.add(Map<String, dynamic>.from(newDate));
      _sortDates();
    });
  }

  void _onDateDeleted(dynamic data) {
    if (data == null) return;
    final convId = data['conversationId'];
    if (convId != null && convId.toString() != widget.conversationId.toString()) return;
    final id = data['id'];
    if (id == null || !mounted) return;
    setState(() {
      _dates.removeWhere((d) => d['id'].toString() == id.toString());
    });
  }

  void _sortDates() {
    _dates.sort((a, b) => _daysUntil(a).compareTo(_daysUntil(b)));
  }

  Future<void> _load() async {
    try {
      final headers = await AuthService.getAuthHeadersForUser(widget.currentUserId);
      final res = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/messages/special-dates/${widget.conversationId}'),
        headers: headers,
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        final List items = data['data'] ?? [];
        if (!mounted) return;
        setState(() {
          _dates = items.cast<Map<String, dynamic>>();
          _sortDates();
          _isLoading = false;
        });
      } else {
        if (!mounted) return;
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  DateTime _nextOccurrence(Map<String, dynamic> d) {
    final raw = DateTime.parse(d['event_date'].toString());
    final bool recurring = d['is_recurring_yearly'] != false;
    if (!recurring) return DateTime(raw.year, raw.month, raw.day);

    final now = DateTime.now();
    var next = DateTime(now.year, raw.month, raw.day);
    final today = DateTime(now.year, now.month, now.day);
    if (next.isBefore(today)) {
      next = DateTime(now.year + 1, raw.month, raw.day);
    }
    return next;
  }

  int _daysUntil(Map<String, dynamic> d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return _nextOccurrence(d).difference(today).inDays;
  }

  int _yearsSince(Map<String, dynamic> d) {
    final raw = DateTime.parse(d['event_date'].toString());
    final next = _nextOccurrence(d);
    return next.year - raw.year;
  }

  void _showAddDialog() {
    final titleController = TextEditingController();
    DateTime? pickedDate;
    bool recurring = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Add Special Date', style: TextStyle(fontWeight: FontWeight.w900)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: titleController,
                decoration: InputDecoration(
                  labelText: 'What is it?',
                  hintText: 'e.g. Our Anniversary',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 14),
              InkWell(
                onTap: () async {
                  final now = DateTime.now();
                  final result = await showDatePicker(
                    context: context,
                    initialDate: pickedDate ?? now,
                    firstDate: DateTime(now.year - 100),
                    lastDate: DateTime(now.year + 10),
                  );
                  if (result != null) {
                    setDialogState(() => pickedDate = result);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade400),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today_rounded, size: 18, color: AppTheme.primaryTeal),
                      const SizedBox(width: 10),
                      Text(
                        pickedDate == null
                            ? 'Pick a date'
                            : '${pickedDate!.day}/${pickedDate!.month}/${pickedDate!.year}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: recurring,
                onChanged: (v) => setDialogState(() => recurring = v ?? true),
                title: const Text('Repeats every year', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryTeal, foregroundColor: Colors.white),
              onPressed: () {
                final title = titleController.text.trim();
                if (title.isEmpty || pickedDate == null) return;
                widget.socket?.emit('addSpecialDate', {
                  'conversationId': widget.conversationId,
                  'title': title,
                  'eventDate': '${pickedDate!.year.toString().padLeft(4, '0')}-${pickedDate!.month.toString().padLeft(2, '0')}-${pickedDate!.day.toString().padLeft(2, '0')}',
                  'isRecurringYearly': recurring,
                });
                Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(Map<String, dynamic> d) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove this date?'),
        content: Text('"${d['title']}" will be removed for both of you.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () {
              widget.socket?.emit('deleteSpecialDate', {
                'conversationId': widget.conversationId,
                'id': d['id'],
              });
              Navigator.pop(ctx);
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F8),
      appBar: AppBar(
        backgroundColor: AppTheme.primaryTeal,
        foregroundColor: Colors.white,
        title: const Text('Anniversaries & Countdowns', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppTheme.primaryTeal,
        onPressed: _showAddDialog,
        child: const Icon(Icons.add_rounded, color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryTeal))
          : _dates.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.cake_outlined, size: 56, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      Text('No special dates yet', style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text('Tap + to add your first one', style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                  itemCount: _dates.length,
                  itemBuilder: (context, i) {
                    final d = _dates[i];
                    final days = _daysUntil(d);
                    final isToday = days == 0;
                    final years = _yearsSince(d);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: isToday
                            ? const LinearGradient(colors: [Color(0xFFFFC107), Color(0xFFFF9800)])
                            : LinearGradient(colors: [AppTheme.primaryTeal.withValues(alpha: 0.9), const Color(0xFF0D8383)]),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8, offset: const Offset(0, 3))],
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  d['title']?.toString() ?? '',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  isToday
                                      ? '🎉 Today is the day!'
                                      : '$days day${days == 1 ? '' : 's'} to go',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 22),
                                ),
                                if (d['is_recurring_yearly'] != false && years > 0)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      '$years year${years == 1 ? '' : 's'}',
                                      style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.white70),
                            onPressed: () => _confirmDelete(d),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
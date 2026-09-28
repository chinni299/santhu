import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'couple_routine_service.dart';

class CoupleRoutineSettingsScreen extends StatefulWidget {
  const CoupleRoutineSettingsScreen({super.key});

  @override
  State<CoupleRoutineSettingsScreen> createState() => _CoupleRoutineSettingsScreenState();
}

class _CoupleRoutineSettingsScreenState extends State<CoupleRoutineSettingsScreen> {
  bool _morningEnabled = false;
  TimeOfDay _morningTime = const TimeOfDay(hour: 8, minute: 0);
  final _morningMsgController = TextEditingController();

  bool _nightEnabled = false;
  TimeOfDay _nightTime = const TimeOfDay(hour: 22, minute: 0);
  final _nightMsgController = TextEditingController();

  bool _soundEnabled = true;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadRoutines();
  }

  Future<void> _loadRoutines() async {
    final r = await CoupleRoutineService.getRoutines();
    if (mounted) {
      if (r != null) {
        setState(() {
          _morningEnabled = r.morningEnabled;
          _morningTime = _parseTime(r.morningTime);
          _morningMsgController.text = r.customMorningMsg ?? 'Good morning ❤️';

          _nightEnabled = r.nightEnabled;
          _nightTime = _parseTime(r.nightTime);
          _nightMsgController.text = r.customNightMsg ?? 'Good night, sleep well 🌙❤️';

          _soundEnabled = r.soundEnabled;
        });
      }
      setState(() => _loading = false);
    }
  }

  TimeOfDay _parseTime(String timeStr) {
    try {
      final parts = timeStr.split(':');
      return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    } catch (_) {
      return const TimeOfDay(hour: 8, minute: 0);
    }
  }

  String _formatTime(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Future<void> _pickTime(bool isMorning) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isMorning ? _morningTime : _nightTime,
    );
    if (picked != null) {
      setState(() {
        if (isMorning) {
          _morningTime = picked;
        } else {
          _nightTime = picked;
        }
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final saved = await CoupleRoutineService.saveRoutines(
      morningEnabled: _morningEnabled,
      morningTime: _formatTime(_morningTime),
      nightEnabled: _nightEnabled,
      nightTime: _formatTime(_nightTime),
      customMorningMsg: _morningMsgController.text.trim().isNotEmpty ? _morningMsgController.text.trim() : null,
      customNightMsg: _nightMsgController.text.trim().isNotEmpty ? _nightMsgController.text.trim() : null,
      soundEnabled: _soundEnabled,
    );

    if (mounted) {
      setState(() => _saving = false);
      if (saved != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Routine settings saved! 🌅🌙')),
        );
      }
    }
  }

  @override
  void dispose() {
    _morningMsgController.dispose();
    _nightMsgController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Good Morning / Night 🌅🌙', style: TextStyle(fontWeight: FontWeight.w900)),
        backgroundColor: AppTheme.primaryTeal,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Good Morning Section
                Card(
                  color: const Color(0xFF1E293B),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Good Morning Routine 🌅', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                          subtitle: const Text('Automatically remind / send morning message', style: TextStyle(fontSize: 12, color: Colors.grey)),
                          value: _morningEnabled,
                          activeTrackColor: AppTheme.primaryTeal,
                          onChanged: (val) => setState(() => _morningEnabled = val),
                        ),
                        if (_morningEnabled) ...[
                          const SizedBox(height: 8),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Reminder Time', style: TextStyle(color: Colors.grey, fontSize: 13)),
                            subtitle: Text(_morningTime.format(context), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                            trailing: const Icon(Icons.access_time, color: AppTheme.primaryTeal),
                            onTap: () => _pickTime(true),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _morningMsgController,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              labelText: 'Custom Message',
                              labelStyle: TextStyle(color: Colors.grey),
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Good Night Section
                Card(
                  color: const Color(0xFF1E293B),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Good Night Routine 🌙', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                          subtitle: const Text('Automatically remind / send night message', style: TextStyle(fontSize: 12, color: Colors.grey)),
                          value: _nightEnabled,
                          activeTrackColor: AppTheme.primaryTeal,
                          onChanged: (val) => setState(() => _nightEnabled = val),
                        ),
                        if (_nightEnabled) ...[
                          const SizedBox(height: 8),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Reminder Time', style: TextStyle(color: Colors.grey, fontSize: 13)),
                            subtitle: Text(_nightTime.format(context), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                            trailing: const Icon(Icons.access_time, color: AppTheme.primaryTeal),
                            onTap: () => _pickTime(false),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _nightMsgController,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              labelText: 'Custom Message',
                              labelStyle: TextStyle(color: Colors.grey),
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Sound Setting
                SwitchListTile(
                  title: const Text('Notification Sound', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                  subtitle: const Text('Play sound with routine notifications', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  value: _soundEnabled,
                  activeTrackColor: AppTheme.primaryTeal,
                  onChanged: (val) => setState(() => _soundEnabled = val),
                ),
                const SizedBox(height: 24),

                ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryTeal,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: _saving
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Save Routines', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
    );
  }
}

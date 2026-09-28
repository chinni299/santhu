import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'smart_notification_settings.dart';
import 'smart_notification_service.dart';

class SmartNotificationSettingsScreen extends StatefulWidget {
  const SmartNotificationSettingsScreen({super.key});

  @override
  State<SmartNotificationSettingsScreen> createState() => _SmartNotificationSettingsScreenState();
}

class _SmartNotificationSettingsScreenState extends State<SmartNotificationSettingsScreen> {
  SmartNotificationSettings _settings = const SmartNotificationSettings();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await SmartNotificationService.loadSettings();
    if (mounted) {
      setState(() {
        _settings = s;
        _loading = false;
      });
    }
  }

  void _update(SmartNotificationSettings updated) async {
    setState(() => _settings = updated);
    await SmartNotificationService.saveSettings(updated);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Notifications', style: TextStyle(fontWeight: FontWeight.w900)),
        backgroundColor: AppTheme.primaryTeal,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryTeal))
          : ListView(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.preview_rounded, color: AppTheme.primaryTeal),
                  title: const Text('Show Message Preview', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('Display message content in push notifications'),
                  value: _settings.showPreview,
                  activeTrackColor: AppTheme.primaryTeal,
                  onChanged: (val) => _update(_settings.copyWith(showPreview: val)),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.person_outline_rounded, color: AppTheme.primaryTeal),
                  title: const Text('Show Sender Name', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('Display sender name in push notifications'),
                  value: _settings.showSender,
                  activeTrackColor: AppTheme.primaryTeal,
                  onChanged: (val) => _update(_settings.copyWith(showSender: val)),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.volume_up_rounded, color: AppTheme.primaryTeal),
                  title: const Text('Notification Sound', style: TextStyle(fontWeight: FontWeight.w700)),
                  value: _settings.soundEnabled,
                  activeTrackColor: AppTheme.primaryTeal,
                  onChanged: (val) => _update(_settings.copyWith(soundEnabled: val)),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.do_not_disturb_on_rounded, color: AppTheme.primaryTeal),
                  title: const Text('Do Not Disturb', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('Mute all incoming alerts'),
                  value: _settings.doNotDisturb,
                  activeTrackColor: AppTheme.primaryTeal,
                  onChanged: (val) => _update(_settings.copyWith(doNotDisturb: val)),
                ),
              ],
            ),
    );
  }
}

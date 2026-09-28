import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../app_lock/biometric_service.dart';
import '../app_lock/pin_setup_screen.dart';
import '../chat_themes/chat_theme_settings_screen.dart';
import '../important_dates/important_date_screen.dart';
import '../countdown/countdown_screen.dart';
import '../daily_question/daily_question_screen.dart';
import '../private_memories/memory_timeline_screen.dart';
import '../shared_notes/shared_notes_screen.dart';
import '../couple_routines/couple_routine_settings_screen.dart';

class SettingsScreen extends StatefulWidget {
  final int currentUserId;
  final VoidCallback? onLogout;

  const SettingsScreen({
    super.key,
    required this.currentUserId,
    this.onLogout,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isBiometricEnabled = false;
  bool _canBiometric = false;
  bool _hideNotificationContent = false;
  bool _enterIsSend = true;
  bool _soundEnabled = true;
  bool _dndEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final bioEnabled = await AuthService.isBiometricEnabled();
    final canBio = await BiometricService.isBiometricAvailable();
    if (mounted) {
      setState(() {
        _isBiometricEnabled = bioEnabled;
        _canBiometric = canBio;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clock Settings', style: TextStyle(fontWeight: FontWeight.w900)),
        backgroundColor: AppTheme.primaryTeal,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        children: [
          // Section: Privacy & App Lock
          _sectionHeader('Privacy & Lock'),
          ListTile(
            leading: const Icon(Icons.lock_reset_rounded, color: AppTheme.primaryTeal),
            title: const Text('Change 4-digit PIN', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('Set a new security PIN for Clock'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PinSetupScreen(
                    onPinSet: () {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('PIN updated successfully ✅')),
                      );
                    },
                  ),
                ),
              );
            },
          ),
          if (_canBiometric)
            SwitchListTile(
              secondary: const Icon(Icons.fingerprint_rounded, color: AppTheme.primaryTeal),
              title: const Text('Biometric Unlock', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Use Fingerprint / Face ID to unlock Clock'),
              value: _isBiometricEnabled,
              activeTrackColor: AppTheme.primaryTeal,
              onChanged: (val) async {
                await AuthService.setBiometricEnabled(val);
                setState(() => _isBiometricEnabled = val);
              },
            ),
          SwitchListTile(
            secondary: const Icon(Icons.visibility_off_rounded, color: AppTheme.primaryTeal),
            title: const Text('Hide Notification Content', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('Show generic alert instead of message text'),
            value: _hideNotificationContent,
            activeTrackColor: AppTheme.primaryTeal,
            onChanged: (val) => setState(() => _hideNotificationContent = val),
          ),

          const Divider(),

          // Section: Appearance
          _sectionHeader('Appearance'),
          ListTile(
            leading: const Icon(Icons.palette_outlined, color: AppTheme.primaryTeal),
            title: const Text('Chat Theme & Wallpaper', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('Themes, colors, and custom wallpaper'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatThemeSettingsScreen()));
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.send_rounded, color: AppTheme.primaryTeal),
            title: const Text('Enter Key Sends Message', style: TextStyle(fontWeight: FontWeight.w700)),
            value: _enterIsSend,
            activeTrackColor: AppTheme.primaryTeal,
            onChanged: (val) => setState(() => _enterIsSend = val),
          ),

          const Divider(),

          // Section: Couple Experience
          _sectionHeader('Couple Experience'),
          ListTile(
            leading: const Icon(Icons.calendar_month_outlined, color: AppTheme.primaryTeal),
            title: const Text('Important Dates', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('Anniversary, birthdays & special moments'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const ImportantDateScreen()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.hourglass_bottom_outlined, color: AppTheme.primaryTeal),
            title: const Text('Countdown', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('Live countdown to special events'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const CountdownScreen()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.quiz_outlined, color: AppTheme.primaryTeal),
            title: const Text('Daily Question', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('Answer daily couple questions together'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const DailyQuestionScreen()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined, color: AppTheme.primaryTeal),
            title: const Text('Private Memories', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('Shared photos & video timeline'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const MemoryTimelineScreen()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.sticky_note_2_outlined, color: AppTheme.primaryTeal),
            title: const Text('Shared Private Notes', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('Notes & lists between User 1 and User 2'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SharedNotesScreen()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.wb_sunny_outlined, color: AppTheme.primaryTeal),
            title: const Text('Good Morning / Night Routines', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('Routine times and custom messages'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const CoupleRoutineSettingsScreen()));
            },
          ),

          const Divider(),

          // Section: Notifications
          _sectionHeader('Notifications'),
          SwitchListTile(
            secondary: const Icon(Icons.volume_up_rounded, color: AppTheme.primaryTeal),
            title: const Text('Notification Sound', style: TextStyle(fontWeight: FontWeight.w700)),
            value: _soundEnabled,
            activeTrackColor: AppTheme.primaryTeal,
            onChanged: (val) => setState(() => _soundEnabled = val),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.do_not_disturb_on_rounded, color: AppTheme.primaryTeal),
            title: const Text('Do Not Disturb', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('Mute all incoming alerts'),
            value: _dndEnabled,
            activeTrackColor: AppTheme.primaryTeal,
            onChanged: (val) => setState(() => _dndEnabled = val),
          ),

          const Divider(),

          // Section: Security & Session
          _sectionHeader('Account & Security'),
          ListTile(
            leading: const Icon(Icons.devices_rounded, color: AppTheme.primaryTeal),
            title: const Text('Active Sessions', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('Private 2-user encrypted session'),
          ),
          ListTile(
            leading: const Icon(Icons.logout_rounded, color: Colors.redAccent),
            title: const Text('Log Out', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.redAccent)),
            onTap: () async {
              final nav = Navigator.of(context);
              await AuthService.logout();
              if (widget.onLogout != null) widget.onLogout!();
              nav.pop();
            },
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, top: 16, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: AppTheme.primaryTeal,
          fontWeight: FontWeight.w900,
          fontSize: 12,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

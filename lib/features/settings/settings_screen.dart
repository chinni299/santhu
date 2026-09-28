import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../app_lock/biometric_service.dart';
import '../app_lock/pin_setup_screen.dart';

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

          // Section: Chat Settings
          _sectionHeader('Chat'),
          ListTile(
            leading: const Icon(Icons.color_lens_rounded, color: AppTheme.primaryTeal),
            title: const Text('Theme & Appearance', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('Dark, Light, Midnight, Love themes'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              _showThemePicker(context);
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
              await AuthService.logout();
              if (mounted) {
                if (widget.onLogout != null) widget.onLogout!();
                Navigator.pop(context);
              }
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

  void _showThemePicker(BuildContext ctx) {
    showModalBottomSheet(
      context: ctx,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Choose Chat Theme', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(Icons.brightness_auto_rounded, color: AppTheme.primaryTeal),
                  title: const Text('System Default'),
                  onTap: () {
                    themeModeNotifier.value = ThemeMode.system;
                    Navigator.pop(context);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.dark_mode_rounded, color: Color(0xFF0F172A)),
                  title: const Text('Midnight Dark'),
                  onTap: () {
                    themeModeNotifier.value = ThemeMode.dark;
                    Navigator.pop(context);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.light_mode_rounded, color: Colors.orange),
                  title: const Text('Light Clean'),
                  onTap: () {
                    themeModeNotifier.value = ThemeMode.light;
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'smart_notification_settings.dart';

class SmartNotificationService {
  static const String _key = 'clock_smart_notification_settings';

  static Future<SmartNotificationSettings> loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final str = prefs.getString(_key);
      if (str != null && str.isNotEmpty) {
        return SmartNotificationSettings.fromJson(jsonDecode(str));
      }
    } catch (_) {}
    return const SmartNotificationSettings();
  }

  static Future<void> saveSettings(SmartNotificationSettings settings) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(settings.toJson()));
    } catch (_) {}
  }

  static String getNotificationTitle(SmartNotificationSettings settings, String senderName) {
    if (settings.doNotDisturb) return '';
    if (!settings.showSender) return 'Clock';
    return senderName;
  }

  static String getNotificationBody(SmartNotificationSettings settings, String messageText) {
    if (settings.doNotDisturb) return '';
    if (!settings.showPreview) return 'New message';
    return messageText;
  }
}

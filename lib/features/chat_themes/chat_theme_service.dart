import 'package:shared_preferences/shared_preferences.dart';
import 'chat_theme.dart';

class ChatThemeService {
  static const String _themeKey = 'selected_chat_theme_mode';
  static const String _wallpaperPathKey = 'custom_wallpaper_local_path';

  static Future<ChatThemeMode> getTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_themeKey);
    return ChatThemeMode.fromString(name);
  }

  static Future<void> setTheme(ChatThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, mode.name);
  }

  static Future<String?> getCustomWallpaperPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_wallpaperPathKey);
  }

  static Future<void> setCustomWallpaperPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_wallpaperPathKey, path);
  }
}

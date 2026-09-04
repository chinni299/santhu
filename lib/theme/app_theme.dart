// theme/app_theme.dart
import 'package:flutter/material.dart';

final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier<ThemeMode>(ThemeMode.light);

class AppTheme {
  static const Color primaryTeal = Color(0xFF149B9B);
  static const Color darkTeal = Color(0xFF0D8383);
  static const Color lightTealBubble = Color(0xFFD2F1EC);
  static const Color darkBubble = Color(0xFF1F2C33);
  static const Color darkSenderBubble = Color(0xFF005C4B);

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      primaryColor: primaryTeal,
      scaffoldBackgroundColor: const Color(0xFFF5F7F8),
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryTeal,
        brightness: Brightness.light,
        primary: primaryTeal,
        surface: Colors.white,
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF111B21)),
        bodyMedium: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF111B21)),
        titleLarge: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF111B21)),
        titleMedium: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF111B21)),
      ),
      iconTheme: const IconThemeData(color: primaryTeal),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      primaryColor: primaryTeal,
      scaffoldBackgroundColor: const Color(0xFF121E24),
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryTeal,
        brightness: Brightness.dark,
        primary: primaryTeal,
        surface: const Color(0xFF1F2C33),
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFFE9EDEF)),
        bodyMedium: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFFE9EDEF)),
        titleLarge: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFFE9EDEF)),
        titleMedium: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFFE9EDEF)),
      ),
      iconTheme: const IconThemeData(color: Colors.white70),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF1F2C33),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
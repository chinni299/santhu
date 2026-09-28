import 'dart:io';
import 'package:flutter/material.dart';
import 'chat_theme.dart';

class ChatWallpaperWidget extends StatelessWidget {
  final ChatThemeMode themeMode;
  final String? customWallpaperPath;
  final Widget child;

  const ChatWallpaperWidget({
    super.key,
    required this.themeMode,
    this.customWallpaperPath,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (themeMode == ChatThemeMode.customWallpaper &&
        customWallpaperPath != null &&
        File(customWallpaperPath!).existsSync()) {
      return Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: FileImage(File(customWallpaperPath!)),
            fit: BoxFit.cover,
          ),
        ),
        child: Container(
          color: Colors.black.withOpacity(0.3), // subtle dark overlay for message legibility
          child: child,
        ),
      );
    }

    BoxDecoration decoration;
    switch (themeMode) {
      case ChatThemeMode.love:
        decoration = const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF2C0B18), Color(0xFF14050C)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        );
        break;
      case ChatThemeMode.dark:
        decoration = const BoxDecoration(color: Color(0xFF121212));
        break;
      case ChatThemeMode.midnight:
        decoration = const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0D1B2A), Color(0xFF070B19)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        );
        break;
      case ChatThemeMode.pink:
        decoration = const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF381528), Color(0xFF1C0A14)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        );
        break;
      case ChatThemeMode.minimal:
        decoration = const BoxDecoration(color: Color(0xFF1E293B));
        break;
      case ChatThemeMode.defaultTheme:
      default:
        decoration = const BoxDecoration(color: Color(0xFF0F172A));
        break;
    }

    return Container(
      decoration: decoration,
      child: child,
    );
  }
}

import 'package:flutter/material.dart';
import '../features/app_lock/app_lock_screen.dart' as feature;

class AppLockScreen extends StatelessWidget {
  final VoidCallback onUnlocked;

  const AppLockScreen({super.key, required this.onUnlocked});

  @override
  Widget build(BuildContext context) {
    return feature.AppLockScreen(onUnlocked: onUnlocked);
  }
}

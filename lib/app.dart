// app.dart
import 'package:flutter/material.dart';
import 'screens/login_screen.dart';
import 'theme/app_theme.dart';

class DuoChatApp extends StatelessWidget {
  const DuoChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'DuoChat',
      theme: AppTheme.lightTheme,
      home: const LoginScreen(),
    );
  }
}
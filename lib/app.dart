import 'package:flutter/material.dart';
import 'screens/app_lock_screen.dart';
import 'screens/conversation_list_screen.dart';
import 'services/app_lock_service.dart';
import 'services/auth_service.dart';
import 'theme/app_theme.dart';

class DuoChatApp extends StatefulWidget {
  const DuoChatApp({super.key});

  @override
  State<DuoChatApp> createState() => _DuoChatAppState();
}

class _DuoChatAppState extends State<DuoChatApp> with WidgetsBindingObserver {
  Map<String, dynamic> _currentUser = {'id': 1, 'name': 'User 1'};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkUserSession();
  }

  Future<void> _checkUserSession() async {
    final user = await AuthService.getUser();
    if (mounted) {
      setState(() {
        _currentUser = user;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      // Auto-lock when app moves to background or is closed
      AppLockService.lockApp();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, currentMode, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'DuoChat',
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: currentMode,
          home: ValueListenableBuilder<bool>(
            valueListenable: AppLockService.isLockedNotifier,
            builder: (context, isLocked, child) {
              if (isLocked) {
                return AppLockScreen(
                  onUnlocked: () async {
                    final user = await AuthService.getUser();
                    if (mounted) {
                      setState(() {
                        _currentUser = user;
                      });
                    }
                  },
                );
              }

              final userId = int.parse((_currentUser['id'] ?? 1).toString());
              return ConversationListScreen(currentUserId: userId);
            },
          ),
        );
      },
    );
  }
}
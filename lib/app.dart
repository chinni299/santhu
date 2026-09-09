import 'package:flutter/material.dart';
import 'screens/app_lock_screen.dart';
import 'screens/conversation_list_screen.dart';
import 'screens/clock_gate_screen.dart';
import 'screens/login_screen.dart';
import 'services/app_lock_service.dart';
import 'services/auth_service.dart';
import 'theme/app_theme.dart';

class ClockApp extends StatefulWidget {
  const ClockApp({super.key});

  @override
  State<ClockApp> createState() => _ClockAppState();
}

class _ClockAppState extends State<ClockApp> with WidgetsBindingObserver {
  // Phase 1: Show Clock (disguise screen)
  // Phase 2: After clock long-press, show Login
  // Phase 3: After login, show PIN lock (setup or verify)
  // Phase 4: After PIN unlock, show chat

  bool _isClockUnlocked = false;   // has clock been long-pressed?
  bool _isLoggedIn = false;         // has the user logged in successfully?
  Map<String, dynamic> _currentUser = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkExistingSession();
  }

  /// On startup: if there's already a saved session, skip Login but keep PIN lock.
  Future<void> _checkExistingSession() async {
    final user = await AuthService.getUser();
    final hasSession = user.isNotEmpty && user['id'] != null;
    if (mounted && hasSession) {
      setState(() {
        _currentUser = user;
        _isLoggedIn = true;
        // isLocked is still true — user must pass PIN/biometric
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
    // When app goes to background or is closed, lock it and reset clock gate
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      AppLockService.lockApp();
      if (mounted) {
        setState(() {
          _isClockUnlocked = false;
          // Keep _isLoggedIn = true so we don't force full re-login,
          // just PIN re-entry on next open.
        });
      }
    }
  }

  void _onClockLongPress(BuildContext ctx) {
    setState(() {
      _isClockUnlocked = true;
    });
  }

  void _onLoginSuccess(Map<String, dynamic> user) {
    setState(() {
      _currentUser = user;
      _isLoggedIn = true;
      // AppLockService.isLockedNotifier is still true → PIN screen will show
    });
  }

  void _onPinUnlocked() async {
    // Refresh user from storage (name might have changed)
    final user = await AuthService.getUser();
    if (mounted) {
      setState(() {
        if (user.isNotEmpty) _currentUser = user;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, currentMode, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Clock',
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: currentMode,
          home: _buildHome(),
        );
      },
    );
  }

  Widget _buildHome() {
    // Phase 1: Clock gate (disguise)
    if (!_isClockUnlocked) {
      return ClockGateScreen(
        onUnlockSecret: _onClockLongPress,
      );
    }

    // Phase 2: Login screen (if not yet logged in)
    if (!_isLoggedIn) {
      return LoginScreen(
        onLoginSuccess: _onLoginSuccess,
      );
    }

    // Phase 3 & 4: PIN lock / Chat
    return ValueListenableBuilder<bool>(
      valueListenable: AppLockService.isLockedNotifier,
      builder: (context, isLocked, _) {
        if (isLocked) {
          return AppLockScreen(
            onUnlocked: _onPinUnlocked,
          );
        }

        final userId = int.tryParse((_currentUser['id'] ?? 1).toString()) ?? 1;
        return ConversationListScreen(currentUserId: userId);
      },
    );
  }
}
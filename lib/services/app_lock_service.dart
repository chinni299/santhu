import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'auth_service.dart';

class AppLockService {
  static final LocalAuthentication _localAuth = LocalAuthentication();
  
  // App lock state notifier
  static final ValueNotifier<bool> isLockedNotifier = ValueNotifier<bool>(true);

  static bool get isLocked => isLockedNotifier.value;

  // Manually lock app
  static void lockApp() {
    isLockedNotifier.value = true;
  }

  // Unlock app
  static void unlockApp() {
    isLockedNotifier.value = false;
  }

  // Check if biometrics hardware is available on device
  static Future<bool> isBiometricAvailable() async {
    if (kIsWeb) return false;
    try {
      final canAuthenticateWithBiometrics = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      return canAuthenticateWithBiometrics && isDeviceSupported;
    } catch (_) {
      return false;
    }
  }

  // Get available biometric types (Fingerprint / Face ID)
  static Future<List<BiometricType>> getAvailableBiometrics() async {
    if (kIsWeb) return [];
    try {
      return await _localAuth.getAvailableBiometrics();
    } catch (_) {
      return [];
    }
  }

  // Authenticate user via Biometrics (Fingerprint / Face)
  static Future<bool> authenticateBiometric() async {
    if (kIsWeb) return false;
    final available = await isBiometricAvailable();
    final enabled = await AuthService.isBiometricEnabled();
    if (!available || !enabled) return false;

    try {
      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Unlock DuoChat to view private messages',
      );
      if (authenticated) {
        unlockApp();
      }
      return authenticated;
    } catch (_) {
      return false;
    }
  }
}

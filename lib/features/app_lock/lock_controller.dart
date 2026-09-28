import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../services/auth_service.dart';
import 'biometric_service.dart';

class LockController {
  static final ValueNotifier<bool> isLockedNotifier = ValueNotifier<bool>(true);
  static final ValueNotifier<int> failedAttemptsNotifier = ValueNotifier<int>(0);
  static final ValueNotifier<int> lockoutSecondsNotifier = ValueNotifier<int>(0);

  static Timer? _lockoutTimer;

  static bool get isLocked => isLockedNotifier.value;

  static void lockApp() {
    isLockedNotifier.value = true;
  }

  static void unlockApp() {
    failedAttemptsNotifier.value = 0;
    lockoutSecondsNotifier.value = 0;
    _lockoutTimer?.cancel();
    isLockedNotifier.value = false;
  }

  static Future<bool> verifyPin(String enteredPin) async {
    if (lockoutSecondsNotifier.value > 0) return false;

    final isValid = await AuthService.verifyPin(enteredPin);
    if (isValid) {
      unlockApp();
      return true;
    } else {
      failedAttemptsNotifier.value += 1;
      if (failedAttemptsNotifier.value >= 5) {
        startLockout(30);
      }
      return false;
    }
  }

  static void startLockout(int seconds) {
    lockoutSecondsNotifier.value = seconds;
    _lockoutTimer?.cancel();
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (lockoutSecondsNotifier.value > 1) {
        lockoutSecondsNotifier.value -= 1;
      } else {
        lockoutSecondsNotifier.value = 0;
        failedAttemptsNotifier.value = 0;
        timer.cancel();
      }
    });
  }

  static Future<bool> tryBiometricUnlock() async {
    if (lockoutSecondsNotifier.value > 0) return false;
    final success = await BiometricService.authenticate();
    if (success) {
      unlockApp();
    }
    return success;
  }
}

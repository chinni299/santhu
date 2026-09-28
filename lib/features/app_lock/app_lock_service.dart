import 'package:flutter/foundation.dart';
import 'lock_controller.dart';
import 'biometric_service.dart';

class AppLockService {
  static ValueNotifier<bool> get isLockedNotifier => LockController.isLockedNotifier;
  static bool get isLocked => LockController.isLocked;

  static void lockApp() => LockController.lockApp();
  static void unlockApp() => LockController.unlockApp();

  static Future<bool> isBiometricAvailable() => BiometricService.isBiometricAvailable();
  static Future<bool> authenticateBiometric() => LockController.tryBiometricUnlock();
}

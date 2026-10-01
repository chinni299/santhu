import 'package:flutter/services.dart';

// Non-web (native Android/iOS) platform implementation for Heartbeat Audio & Vibration

class HeartbeatAudio {
  static const MethodChannel _vibratorChannel = MethodChannel('duochat/vibrator');
  static bool _isMuted = false;

  static void playBeat(String beatType) {
    if (_isMuted) return;
    try {
      _vibratorChannel.invokeMethod('vibrate', {'duration': beatType == 'lub' ? 90 : 50});
    } catch (_) {
      if (beatType == 'lub') {
        HapticFeedback.heavyImpact();
      } else {
        HapticFeedback.mediumImpact();
      }
    }
  }

  static void vibrate(List<int> pattern) {
    try {
      _vibratorChannel.invokeMethod('vibratePattern', {'pattern': pattern});
    } catch (_) {
      HapticFeedback.heavyImpact();
    }
  }

  static void stopVibrate() {
    try {
      _vibratorChannel.invokeMethod('cancel');
    } catch (_) {}
  }

  static void setMuted(bool muted) {
    _isMuted = muted;
  }

  static bool getMuted() {
    return _isMuted;
  }
}

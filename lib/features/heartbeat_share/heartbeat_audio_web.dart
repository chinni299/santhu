// Web platform implementation for Heartbeat Audio & Vibration using JS Interop
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:js' as js;

class HeartbeatAudio {
  static void playBeat(String beatType) {
    try {
      if (js.context.hasProperty('DuoHeartbeat')) {
        js.context['DuoHeartbeat'].callMethod('playBeat', [beatType]);
      }
    } catch (_) {
      // Fallback gracefully without crashing
    }
  }

  static void vibrate(List<int> pattern) {
    try {
      if (js.context.hasProperty('DuoHeartbeat')) {
        js.context['DuoHeartbeat'].callMethod('vibrate', [pattern]);
      }
    } catch (_) {
      // Vibration API unsupported or denied by browser - fallback gracefully
    }
  }

  static void stopVibrate() {
    try {
      if (js.context.hasProperty('DuoHeartbeat')) {
        js.context['DuoHeartbeat'].callMethod('stopVibrate', []);
      }
    } catch (_) {}
  }

  static void setMuted(bool muted) {
    try {
      if (js.context.hasProperty('DuoHeartbeat')) {
        js.context['DuoHeartbeat'].callMethod('setMuted', [muted]);
      }
    } catch (_) {}
  }

  static bool getMuted() {
    try {
      if (js.context.hasProperty('DuoHeartbeat')) {
        return js.context['DuoHeartbeat'].callMethod('getMuted', []) == true;
      }
    } catch (_) {}
    return false;
  }
}

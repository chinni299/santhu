// Non-web (native Android/iOS) platform stub for Heartbeat Audio & Vibration

class HeartbeatAudio {
  static bool _isMuted = false;

  static void playBeat(String beatType) {
    // Audio synthesis fallback on native via system haptic / audio players if needed
  }

  static void vibrate(List<int> pattern) {
    // Vibration handled safely on native
  }

  static void stopVibrate() {
    // Stop vibration
  }

  static void setMuted(bool muted) {
    _isMuted = muted;
  }

  static bool getMuted() {
    return _isMuted;
  }
}

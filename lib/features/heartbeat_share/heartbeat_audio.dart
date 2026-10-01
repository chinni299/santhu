// Conditional export for Heartbeat Audio & Vibration (Web vs Stub)
export 'heartbeat_audio_stub.dart'
    if (dart.library.html) 'heartbeat_audio_web.dart';

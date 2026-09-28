class CoupleRoutine {
  final int userId;
  final bool morningEnabled;
  final String morningTime;
  final bool nightEnabled;
  final String nightTime;
  final String? customMorningMsg;
  final String? customNightMsg;
  final bool soundEnabled;

  CoupleRoutine({
    required this.userId,
    required this.morningEnabled,
    required this.morningTime,
    required this.nightEnabled,
    required this.nightTime,
    this.customMorningMsg,
    this.customNightMsg,
    required this.soundEnabled,
  });

  factory CoupleRoutine.fromJson(Map<String, dynamic> json) {
    return CoupleRoutine(
      userId: json['user_id'] ?? json['userId'] ?? 0,
      morningEnabled: json['morning_enabled'] ?? json['morningEnabled'] ?? false,
      morningTime: json['morning_time'] ?? json['morningTime'] ?? '08:00',
      nightEnabled: json['night_enabled'] ?? json['nightEnabled'] ?? false,
      nightTime: json['night_time'] ?? json['nightTime'] ?? '22:00',
      customMorningMsg: json['custom_morning_msg'] ?? json['customMorningMsg'],
      customNightMsg: json['custom_night_msg'] ?? json['customNightMsg'],
      soundEnabled: json['sound_enabled'] ?? json['soundEnabled'] ?? true,
    );
  }
}

class SmartNotificationSettings {
  final bool showPreview;
  final bool showSender;
  final bool soundEnabled;
  final bool doNotDisturb;

  const SmartNotificationSettings({
    this.showPreview = true,
    this.showSender = true,
    this.soundEnabled = true,
    this.doNotDisturb = false,
  });

  factory SmartNotificationSettings.fromJson(Map<String, dynamic> json) {
    return SmartNotificationSettings(
      showPreview: json['showPreview'] ?? true,
      showSender: json['showSender'] ?? true,
      soundEnabled: json['soundEnabled'] ?? true,
      doNotDisturb: json['doNotDisturb'] ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'showPreview': showPreview,
        'showSender': showSender,
        'soundEnabled': soundEnabled,
        'doNotDisturb': doNotDisturb,
      };

  SmartNotificationSettings copyWith({
    bool? showPreview,
    bool? showSender,
    bool? soundEnabled,
    bool? doNotDisturb,
  }) {
    return SmartNotificationSettings(
      showPreview: showPreview ?? this.showPreview,
      showSender: showSender ?? this.showSender,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      doNotDisturb: doNotDisturb ?? this.doNotDisturb,
    );
  }
}

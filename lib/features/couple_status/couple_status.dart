enum CoupleStatusType {
  online('online', 'Online', '🟢'),
  busy('busy', 'Busy', '🔴'),
  sleeping('sleeping', 'Sleeping', '🌙'),
  gaming('gaming', 'Gaming', '🎮'),
  custom('custom', 'Custom', '✏️');

  final String key;
  final String label;
  final String emoji;

  const CoupleStatusType(this.key, this.label, this.emoji);

  static CoupleStatusType fromKey(String? key) {
    if (key == null) return CoupleStatusType.online;
    return CoupleStatusType.values.firstWhere(
      (e) => e.key == key.toLowerCase(),
      orElse: () => CoupleStatusType.online,
    );
  }
}

class CoupleStatus {
  final int userId;
  final CoupleStatusType statusType;
  final String? customText;
  final DateTime updatedAt;

  const CoupleStatus({
    required this.userId,
    required this.statusType,
    this.customText,
    required this.updatedAt,
  });

  String get displayString {
    if (statusType == CoupleStatusType.custom && customText != null && customText!.isNotEmpty) {
      return '${statusType.emoji} $customText';
    }
    return '${statusType.emoji} ${statusType.label}';
  }

  factory CoupleStatus.fromJson(Map<String, dynamic> json) {
    return CoupleStatus(
      userId: int.tryParse((json['userId'] ?? json['user_id'] ?? 0).toString()) ?? 0,
      statusType: CoupleStatusType.fromKey(json['status']?.toString()),
      customText: json['customText'] ?? json['custom_text'],
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'status': statusType.key,
        'customText': customText,
        'updatedAt': updatedAt.toIso8601String(),
      };
}

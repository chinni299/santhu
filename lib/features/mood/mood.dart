enum MoodType {
  happy('happy', 'Happy', '😊'),
  sad('sad', 'Sad', '😢'),
  angry('angry', 'Angry', '😡'),
  sleepy('sleepy', 'Sleepy', '😴'),
  missingYou('missing_you', 'Missing You', '🥺'),
  needAHug('need_a_hug', 'Need a Hug', '🤗');

  final String key;
  final String label;
  final String emoji;

  const MoodType(this.key, this.label, this.emoji);

  static MoodType? fromKey(String? key) {
    if (key == null || key.isEmpty) return null;
    try {
      return MoodType.values.firstWhere((e) => e.key == key.toLowerCase());
    } catch (_) {
      return null;
    }
  }
}

class UserMood {
  final int userId;
  final MoodType? moodType;
  final DateTime updatedAt;

  const UserMood({
    required this.userId,
    this.moodType,
    required this.updatedAt,
  });

  factory UserMood.fromJson(Map<String, dynamic> json) {
    return UserMood(
      userId: int.tryParse((json['userId'] ?? json['user_id'] ?? 0).toString()) ?? 0,
      moodType: MoodType.fromKey(json['mood']?.toString()),
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'mood': moodType?.key,
        'updatedAt': updatedAt.toIso8601String(),
      };
}

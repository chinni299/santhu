class MessageReaction {
  final int userId;
  final String emoji;

  const MessageReaction({
    required this.userId,
    required this.emoji,
  });

  static const List<String> supportedEmojis = ['❤️', '😂', '😍', '😢', '😡', '👍'];

  factory MessageReaction.fromJson(int userId, String emoji) {
    return MessageReaction(userId: userId, emoji: emoji);
  }

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'emoji': emoji,
      };
}

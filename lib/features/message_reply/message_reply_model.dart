class MessageReplyModel {
  final int id;
  final int senderId;
  final String senderName;
  final String text;
  final String? attachmentType;
  final String? attachmentName;
  final bool isDeleted;

  const MessageReplyModel({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.text,
    this.attachmentType,
    this.attachmentName,
    this.isDeleted = false,
  });

  factory MessageReplyModel.fromMap(Map<String, dynamic> map, int currentUserId, String peerName) {
    final senderId = int.tryParse((map['sender_id'] ?? map['senderId'] ?? 0).toString()) ?? 0;
    final isMe = senderId == currentUserId;
    final name = isMe ? 'You' : (peerName.isNotEmpty ? peerName : 'User');
    final isDeleted = map['is_deleted'] == true || map['isDeleted'] == true;

    String text = (map['message'] ?? '').toString();
    if (isDeleted) {
      text = 'This message was deleted';
    } else if (map['attachmentType'] == 'image' || map['attachment_type'] == 'image') {
      text = '📷 Photo';
    } else if (map['attachmentType'] == 'audio' || map['attachment_type'] == 'audio') {
      text = '🎤 Voice message';
    } else if (map['attachmentType'] == 'location' || map['attachment_type'] == 'location') {
      text = '📍 Location';
    } else if (map['attachmentType'] == 'file' || map['attachment_type'] == 'file') {
      text = '📎 ${map['attachmentName'] ?? map['attachment_name'] ?? 'File'}';
    }

    return MessageReplyModel(
      id: int.tryParse((map['id'] ?? 0).toString()) ?? 0,
      senderId: senderId,
      senderName: name,
      text: text,
      attachmentType: map['attachmentType'] ?? map['attachment_type'],
      attachmentName: map['attachmentName'] ?? map['attachment_name'],
      isDeleted: isDeleted,
    );
  }
}

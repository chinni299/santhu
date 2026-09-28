class MemoryModel {
  final int id;
  final String type; // 'photo', 'video', 'voice'
  final String mediaUrl;
  final String? caption;
  final DateTime memoryDate;
  final int createdBy;
  final DateTime createdAt;

  MemoryModel({
    required this.id,
    required this.type,
    required this.mediaUrl,
    this.caption,
    required this.memoryDate,
    required this.createdBy,
    required this.createdAt,
  });

  factory MemoryModel.fromJson(Map<String, dynamic> json) {
    return MemoryModel(
      id: json['id'],
      type: json['type'] ?? 'photo',
      mediaUrl: json['media_url'] ?? json['mediaUrl'] ?? '',
      caption: json['caption'],
      memoryDate: DateTime.parse(json['memory_date'] ?? json['memoryDate']),
      createdBy: json['created_by'] ?? json['createdBy'] ?? 0,
      createdAt: DateTime.parse(json['created_at'] ?? json['createdAt']),
    );
  }
}

class SharedNote {
  final int id;
  final String title;
  final String content;
  final int createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  SharedNote({
    required this.id,
    required this.title,
    required this.content,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SharedNote.fromJson(Map<String, dynamic> json) {
    return SharedNote(
      id: json['id'],
      title: json['title'],
      content: json['content'],
      createdBy: json['created_by'] ?? json['createdBy'] ?? 0,
      createdAt: DateTime.parse(json['created_at'] ?? json['createdAt']),
      updatedAt: DateTime.parse(json['updated_at'] ?? json['updatedAt']),
    );
  }
}

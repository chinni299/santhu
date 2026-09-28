class ImportantDate {
  final int id;
  final String title;
  final String dateType; // 'birthday', 'anniversary', 'first_meeting', 'custom'
  final DateTime dateValue;
  final String? note;
  final int createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  ImportantDate({
    required this.id,
    required this.title,
    required this.dateType,
    required this.dateValue,
    this.note,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ImportantDate.fromJson(Map<String, dynamic> json) {
    return ImportantDate(
      id: json['id'],
      title: json['title'],
      dateType: json['date_type'] ?? 'custom',
      dateValue: DateTime.parse(json['date_value']),
      note: json['note'],
      createdBy: json['created_by'],
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'date_type': dateType,
      'date_value': dateValue.toIso8601String(),
      'note': note,
      'created_by': createdBy,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Calculates days remaining. Handles annual recurrence for birthdays and anniversaries.
  int get daysRemaining {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (dateType == 'birthday' || dateType == 'anniversary') {
      var nextOccur = DateTime(now.year, dateValue.month, dateValue.day);
      if (nextOccur.isBefore(today)) {
        nextOccur = DateTime(now.year + 1, dateValue.month, dateValue.day);
      }
      return nextOccur.difference(today).inDays;
    } else {
      final target = DateTime(dateValue.year, dateValue.month, dateValue.day);
      return target.difference(today).inDays;
    }
  }

  DateTime get nextEventDate {
    final now = DateTime.now();
    if (dateType == 'birthday' || dateType == 'anniversary') {
      var nextOccur = DateTime(now.year, dateValue.month, dateValue.day);
      if (nextOccur.isBefore(DateTime(now.year, now.month, now.day))) {
        nextOccur = DateTime(now.year + 1, dateValue.month, dateValue.day);
      }
      return nextOccur;
    }
    return dateValue;
  }
}

class SharedMoment {
  final int id;
  final int createdBy;
  final String? caption;
  final String? mediaUrl;
  final double? latitude;
  final double? longitude;
  final bool locationEnabled;
  final DateTime momentDate;
  final DateTime createdAt;
  final DateTime updatedAt;

  SharedMoment({
    required this.id,
    required this.createdBy,
    this.caption,
    this.mediaUrl,
    this.latitude,
    this.longitude,
    required this.locationEnabled,
    required this.momentDate,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SharedMoment.fromJson(Map<String, dynamic> json) {
    return SharedMoment(
      id: json['id'],
      createdBy: json['created_by'] ?? json['createdBy'] ?? 0,
      caption: json['caption'],
      mediaUrl: json['media_url'] ?? json['mediaUrl'],
      latitude: json['latitude'] != null ? (json['latitude'] as num).toDouble() : null,
      longitude: json['longitude'] != null ? (json['longitude'] as num).toDouble() : null,
      locationEnabled: json['location_enabled'] ?? json['locationEnabled'] ?? false,
      momentDate: DateTime.parse(json['moment_date'] ?? json['momentDate']),
      createdAt: DateTime.parse(json['created_at'] ?? json['createdAt']),
      updatedAt: DateTime.parse(json['updated_at'] ?? json['updatedAt']),
    );
  }
}

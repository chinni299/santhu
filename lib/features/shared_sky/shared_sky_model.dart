import 'dart:math';
import 'package:flutter/material.dart';

/// Represents a named star record persisted in the database.
class NamedStar {
  final int id;
  final int conversationId;
  final int starIndex;
  final String starName;
  final int namedByUserId;
  final String? namedByUserName;
  final DateTime createdAt;
  final DateTime updatedAt;

  NamedStar({
    required this.id,
    required this.conversationId,
    required this.starIndex,
    required this.starName,
    required this.namedByUserId,
    this.namedByUserName,
    required this.createdAt,
    required this.updatedAt,
  });

  factory NamedStar.fromJson(Map<String, dynamic> json) {
    return NamedStar(
      id: json['id'] is int ? json['id'] : int.parse(json['id'].toString()),
      conversationId: json['conversation_id'] is int
          ? json['conversation_id']
          : int.parse(json['conversation_id'].toString()),
      starIndex: json['star_index'] is int
          ? json['star_index']
          : int.parse(json['star_index'].toString()),
      starName: json['star_name']?.toString() ?? '',
      namedByUserId: json['named_by_user_id'] is int
          ? json['named_by_user_id']
          : int.parse(json['named_by_user_id'].toString()),
      namedByUserName: json['named_by_user_name']?.toString(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'conversation_id': conversationId,
      'star_index': starIndex,
      'star_name': starName,
      'named_by_user_id': namedByUserId,
      'named_by_user_name': namedByUserName,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

/// Represents a celestial star in the sky field.
class CelestialStar {
  final int index;
  final double x; // Normalized 0.0 -> 1.0
  final double y; // Normalized 0.0 -> 1.0
  final double radius;
  final double twinkleSpeed;
  final double twinklePhase;
  final Color baseColor;
  final double brightness;

  const CelestialStar({
    required this.index,
    required this.x,
    required this.y,
    required this.radius,
    required this.twinkleSpeed,
    required this.twinklePhase,
    required this.baseColor,
    required this.brightness,
  });
}

/// Deterministic Star Field Generator with fixed seed
class SkyGenerator {
  static const int starCount = 180;
  static const int seed = 987654321;

  static List<CelestialStar>? _cachedStars;

  /// Returns the exact same list of stars on every device and platform
  static List<CelestialStar> generateStars() {
    if (_cachedStars != null) return _cachedStars!;

    // Linear Congruential Generator (LCG) for deterministic cross-platform values
    int current = seed;
    double nextRandom() {
      current = (current * 1664525 + 1013904223) & 0xFFFFFFFF;
      return (current & 0x7FFFFFFF) / 0x7FFFFFFF;
    }

    final List<CelestialStar> stars = [];

    // Distinct star colors
    final List<Color> starPalettes = [
      const Color(0xFFFFFFFF), // Pure Brilliant White
      const Color(0xFFE2F1FF), // Diamond Blue-White
      const Color(0xFFFFF7D6), // Golden Warm Starlight
      const Color(0xFFFFEBF5), // Rose Blush Starlight
      const Color(0xFFD4E8FF), // Azure Nebula Glow
      const Color(0xFFFFD1A4), // Warm Amber
    ];

    for (int i = 0; i < starCount; i++) {
      // Keep stars nicely distributed and well-spaced within view
      final double x = 0.05 + nextRandom() * 0.90;
      final double y = 0.08 + nextRandom() * 0.84;
      final double radius = 1.3 + nextRandom() * 2.5;
      final double speed = 1.2 + nextRandom() * 2.8;
      final double phase = nextRandom() * 2 * pi;
      final Color color = starPalettes[(nextRandom() * starPalettes.length).floor() % starPalettes.length];
      final double brightness = 0.65 + nextRandom() * 0.35;

      stars.add(CelestialStar(
        index: i,
        x: x,
        y: y,
        radius: radius,
        twinkleSpeed: speed,
        twinklePhase: phase,
        baseColor: color,
        brightness: brightness,
      ));
    }

    _cachedStars = stars;
    return stars;
  }
}

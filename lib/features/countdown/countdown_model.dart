class CountdownModel {
  final String title;
  final DateTime targetDate;

  CountdownModel({required this.title, required this.targetDate});

  Duration get remainingTime {
    final now = DateTime.now();
    if (targetDate.isBefore(now)) {
      return Duration.zero;
    }
    return targetDate.difference(now);
  }
}

enum DisappearingDuration {
  off(0, 'Off'),
  tenSeconds(10, '10 seconds'),
  oneMinute(60, '1 minute'),
  oneHour(3600, '1 hour'),
  oneDay(86400, '24 hours'),
  sevenDays(604800, '7 days'),
  ninetyDays(7776000, '90 days');

  final int seconds;
  final String label;

  const DisappearingDuration(this.seconds, this.label);

  static DisappearingDuration fromSeconds(int? seconds) {
    if (seconds == null || seconds <= 0) return DisappearingDuration.off;
    return DisappearingDuration.values.firstWhere(
      (d) => d.seconds == seconds,
      orElse: () => DisappearingDuration.off,
    );
  }
}

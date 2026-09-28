class DailyQuestion {
  final int id;
  final String questionText;
  final String questionDate;
  final String? myAnswer;
  final String? partnerAnswer;
  final bool hasPartnerAnswered;
  final bool bothAnswered;

  DailyQuestion({
    required this.id,
    required this.questionText,
    required this.questionDate,
    this.myAnswer,
    this.partnerAnswer,
    required this.hasPartnerAnswered,
    required this.bothAnswered,
  });

  factory DailyQuestion.fromJson(Map<String, dynamic> json) {
    return DailyQuestion(
      id: json['id'],
      questionText: json['questionText'] ?? json['question_text'] ?? '',
      questionDate: json['questionDate'] ?? json['question_date'] ?? '',
      myAnswer: json['myAnswer'],
      partnerAnswer: json['partnerAnswer'],
      hasPartnerAnswered: json['hasPartnerAnswered'] ?? false,
      bothAnswered: json['bothAnswered'] ?? false,
    );
  }
}

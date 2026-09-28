import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'daily_question.dart';
import 'daily_question_service.dart';

class DailyQuestionScreen extends StatefulWidget {
  const DailyQuestionScreen({super.key});

  @override
  State<DailyQuestionScreen> createState() => _DailyQuestionScreenState();
}

class _DailyQuestionScreenState extends State<DailyQuestionScreen> {
  DailyQuestion? _question;
  final _answerController = TextEditingController();
  bool _loading = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadQuestion();
  }

  Future<void> _loadQuestion() async {
    setState(() => _loading = true);
    final q = await DailyQuestionService.getTodayQuestion();
    if (mounted) {
      setState(() {
        _question = q;
        if (q?.myAnswer != null) {
          _answerController.text = q!.myAnswer!;
        }
        _loading = false;
      });
    }
  }

  Future<void> _submitAnswer() async {
    final text = _answerController.text.trim();
    if (text.isEmpty || _question == null) return;

    setState(() => _submitting = true);
    final success = await DailyQuestionService.submitAnswer(
      questionId: _question!.id,
      answerText: text,
    );

    if (mounted) {
      setState(() => _submitting = false);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Answer submitted! ❤️')),
        );
        _loadQuestion();
      }
    }
  }

  @override
  void dispose() {
    _answerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Question ❓', style: TextStyle(fontWeight: FontWeight.w900)),
        backgroundColor: AppTheme.primaryTeal,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _question == null
              ? const Center(child: Text('Could not load today\'s question.', style: TextStyle(color: Colors.white)))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppTheme.primaryTeal.withOpacity(0.4)),
                        ),
                        child: Column(
                          children: [
                            const Icon(Icons.quiz, color: AppTheme.primaryTeal, size: 36),
                            const SizedBox(height: 12),
                            const Text(
                              'TODAY\'S QUESTION',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _question!.questionText,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // My Answer section
                      const Text('Your Answer', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _answerController,
                        style: const TextStyle(color: Colors.white),
                        maxLines: 3,
                        decoration: InputDecoration(
                          hintText: 'Type your answer...',
                          hintStyle: const TextStyle(color: Colors.grey),
                          fillColor: const Color(0xFF1E293B),
                          filled: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _submitting ? null : _submitAnswer,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryTeal,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: _submitting
                            ? const CircularProgressIndicator(color: Colors.white)
                            : Text(
                                _question!.myAnswer != null ? 'Update Answer' : 'Submit Answer',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                      ),

                      const SizedBox(height: 28),
                      // Partner Answer section
                      const Text('Partner\'s Answer', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: _question!.bothAnswered && _question!.partnerAnswer != null
                            ? Text(
                                _question!.partnerAnswer!,
                                style: const TextStyle(color: Colors.pinkAccent, fontSize: 15, fontWeight: FontWeight.w600),
                              )
                            : Row(
                                children: const [
                                  Icon(Icons.lock_clock, color: Colors.amber, size: 20),
                                  SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Waiting for your partner ❤️ (Answers reveal when both answer)',
                                      style: TextStyle(color: Colors.grey, fontSize: 13),
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

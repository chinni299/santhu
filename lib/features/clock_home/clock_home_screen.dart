import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ClockHomeScreen extends StatefulWidget {
  final Function(BuildContext context) onUnlockSecret;
  final VoidCallback? onOpenChat;
  final VoidCallback? onOpenMemories;
  final VoidCallback? onOpenNotes;
  final VoidCallback? onOpenDates;
  final VoidCallback? onOpenSettings;
  final String? coupleStatus;
  final String? mood;
  final String? countdownText;
  final VoidCallback? onThinkingOfYou;

  const ClockHomeScreen({
    super.key,
    required this.onUnlockSecret,
    this.onOpenChat,
    this.onOpenMemories,
    this.onOpenNotes,
    this.onOpenDates,
    this.onOpenSettings,
    this.coupleStatus,
    this.mood,
    this.countdownText,
    this.onThinkingOfYou,
  });

  @override
  State<ClockHomeScreen> createState() => _ClockHomeScreenState();
}

class _ClockHomeScreenState extends State<ClockHomeScreen> with SingleTickerProviderStateMixin {
  late DateTime _currentTime;
  Timer? _timer;
  late AnimationController _pulseController;
  late Animation<double> _pulseScale;

  @override
  void initState() {
    super.initState();
    _currentTime = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _currentTime = DateTime.now();
        });
      }
    });

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    _pulseController.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        HapticFeedback.heavyImpact();
        _pulseController.reset();
        widget.onUnlockSecret(context);
      }
    });

    _pulseScale = Tween<double>(begin: 1.0, end: 1.25).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _onCenterTapDown(TapDownDetails details) {
    _pulseController.forward(from: 0.0);
  }

  void _onCenterTapCancel() {
    _pulseController.reset();
  }

  void _onCenterTapUp(TapUpDetails details) {
    _pulseController.reset();
  }

  @override
  Widget build(BuildContext context) {
    final hourStr = _currentTime.hour.toString().padLeft(2, '0');
    final minStr = _currentTime.minute.toString().padLeft(2, '0');
    final secStr = _currentTime.second.toString().padLeft(2, '0');

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar with Clock Branding and Settings
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.access_time_filled_rounded, color: Color(0xFF0D9488), size: 28),
                      SizedBox(width: 8),
                      Text(
                        'CLOCK',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 20,
                          letterSpacing: 2.0,
                        ),
                      ),
                    ],
                  ),
                  if (widget.onOpenSettings != null)
                    IconButton(
                      icon: const Icon(Icons.settings_rounded, color: Colors.white70),
                      onPressed: widget.onOpenSettings,
                    ),
                ],
              ),
            ),

            // Status & Countdown Pills
            if (widget.countdownText != null || widget.coupleStatus != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    if (widget.coupleStatus != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0D9488).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFF0D9488).withValues(alpha: 0.5)),
                        ),
                        child: Text(
                          widget.coupleStatus!,
                          style: const TextStyle(color: Color(0xFF2DD4BF), fontWeight: FontWeight.w700, fontSize: 12),
                        ),
                      ),
                    if (widget.countdownText != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.pink.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.pink.withValues(alpha: 0.5)),
                        ),
                        child: Text(
                          widget.countdownText!,
                          style: const TextStyle(color: Colors.pinkAccent, fontWeight: FontWeight.w700, fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),

            const Spacer(),

            // Clock Widget with Hold-to-Unlock
            GestureDetector(
              onTapDown: _onCenterTapDown,
              onTapUp: _onCenterTapUp,
              onTapCancel: _onCenterTapCancel,
              child: AnimatedBuilder(
                animation: _pulseScale,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _pulseScale.value,
                    child: Container(
                      width: 240,
                      height: 240,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            const Color(0xFF0D9488).withValues(alpha: 0.25),
                            const Color(0xFF0F172A),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF0D9488).withValues(alpha: 0.3),
                            blurRadius: 30,
                            spreadRadius: 5,
                          ),
                        ],
                        border: Border.all(color: const Color(0xFF0D9488).withValues(alpha: 0.6), width: 3),
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CustomPaint(
                            size: const Size(240, 240),
                            painter: _ClockPainter(time: _currentTime),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '$hourStr:$minStr',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 42,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 2,
                                ),
                              ),
                              Text(
                                secStr,
                                style: const TextStyle(
                                  color: Color(0xFF2DD4BF),
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Hold center to unlock',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  fontSize: 10,
                                  letterSpacing: 1,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            const Spacer(),

            // Thinking of You Action
            if (widget.onThinkingOfYou != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: ElevatedButton.icon(
                  onPressed: widget.onThinkingOfYou,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.pinkAccent.withValues(alpha: 0.2),
                    foregroundColor: Colors.pinkAccent,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                      side: const BorderSide(color: Colors.pinkAccent, width: 1.5),
                    ),
                  ),
                  icon: const Icon(Icons.favorite_rounded, color: Colors.pinkAccent),
                  label: const Text(
                    '❤️ Thinking of You',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                  ),
                ),
              ),

            // Quick Access Dock
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _dockItem(Icons.chat_bubble_rounded, 'Chat', widget.onOpenChat),
                  _dockItem(Icons.photo_library_rounded, 'Memories', widget.onOpenMemories),
                  _dockItem(Icons.note_alt_rounded, 'Notes', widget.onOpenNotes),
                  _dockItem(Icons.calendar_month_rounded, 'Dates', widget.onOpenDates),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dockItem(IconData icon, String label, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: const Color(0xFF2DD4BF), size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClockPainter extends CustomPainter {
  final DateTime time;

  _ClockPainter({required this.time});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    final hourAngle = (time.hour % 12 + time.minute / 60) * (2 * math.pi / 12) - math.pi / 2;
    final minuteAngle = (time.minute + time.second / 60) * (2 * math.pi / 60) - math.pi / 2;
    final secondAngle = time.second * (2 * math.pi / 60) - math.pi / 2;

    final hourHandPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    final minuteHandPaint = Paint()
      ..color = const Color(0xFF2DD4BF)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final secondHandPaint = Paint()
      ..color = Colors.pinkAccent
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      center,
      center + Offset(math.cos(hourAngle) * (radius * 0.5), math.sin(hourAngle) * (radius * 0.5)),
      hourHandPaint,
    );

    canvas.drawLine(
      center,
      center + Offset(math.cos(minuteAngle) * (radius * 0.7), math.sin(minuteAngle) * (radius * 0.7)),
      minuteHandPaint,
    );

    canvas.drawLine(
      center,
      center + Offset(math.cos(secondAngle) * (radius * 0.85), math.sin(secondAngle) * (radius * 0.85)),
      secondHandPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ClockPainter oldDelegate) => true;
}

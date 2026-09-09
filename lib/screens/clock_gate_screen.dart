import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ClockGateScreen extends StatefulWidget {
  final Function(BuildContext context) onUnlockSecret;

  const ClockGateScreen({
    super.key,
    required this.onUnlockSecret,
  });

  @override
  State<ClockGateScreen> createState() => _ClockGateScreenState();
}

class _ClockGateScreenState extends State<ClockGateScreen> with SingleTickerProviderStateMixin {
  late DateTime _currentTime;
  Timer? _timer;
  Timer? _holdTimer;
  late AnimationController _pulseController;
  late Animation<double> _pulseScale;

  int _selectedTab = 0; // 0: Alarm, 1: Clock, 2: Timer, 3: Stopwatch
  bool _isAlarmEnabled = true;

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
      duration: const Duration(milliseconds: 2500),
    );

    _pulseController.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        HapticFeedback.heavyImpact();
        _holdTimer?.cancel();
        _pulseController.reset();
        widget.onUnlockSecret(context);
      }
    });

    _pulseScale = Tween<double>(begin: 1.0, end: 1.35).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.linear),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _holdTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _onPressDown() {
    _holdTimer?.cancel();
    HapticFeedback.lightImpact();
    _pulseController.forward(from: 0.0);

    _holdTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) {
        HapticFeedback.heavyImpact();
        _pulseController.reset();
        widget.onUnlockSecret(context);
      }
    });
  }

  void _onPressUp() {
    _holdTimer?.cancel();
    if (_pulseController.isAnimating || _pulseController.value > 0) {
      _pulseController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bgColor = isDark ? const Color(0xFF0F172A) : const Color(0xFFFAFAFD);
    final cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final primaryPurple = const Color(0xFF7C3AED);
    final accentPurple = const Color(0xFFEDE9FE);
    final textColor = isDark ? Colors.white : const Color(0xFF1E1B4B);
    final subTextColor = isDark ? Colors.grey.shade400 : const Color(0xFF64748B);

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Top Header Bar & Tabs
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: primaryPurple.withValues(alpha: 0.12),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.access_time_filled_rounded,
                                    color: primaryPurple,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'Clock',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w900,
                                    color: textColor,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                              ],
                            ),
                            IconButton(
                              icon: Icon(Icons.more_vert_rounded, color: subTextColor),
                              onPressed: () {},
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),

                        // Navigation Tabs (Alarm, Clock, Timer, Stopwatch)
                        Container(
                          height: 48,
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Row(
                            children: [
                              _buildTabItem(0, 'Alarm', Icons.alarm_rounded, primaryPurple, isDark),
                              _buildTabItem(1, 'Clock', Icons.schedule_rounded, primaryPurple, isDark),
                              _buildTabItem(2, 'Timer', Icons.hourglass_bottom_rounded, primaryPurple, isDark),
                              _buildTabItem(3, 'Stopwatch', Icons.timer_outlined, primaryPurple, isDark),
                            ],
                          ),
                        ),

                        const SizedBox(height: 28),

                        // Center Analog Clock Area
                        Center(
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // Analog Clock Graphic
                              SizedBox(
                                width: 240,
                                height: 240,
                                child: CustomPaint(
                                  painter: AnalogClockPainter(
                                    dateTime: _currentTime,
                                    primaryColor: primaryPurple,
                                    isDark: isDark,
                                  ),
                                ),
                              ),

                              // Secret Gesture Target on Analog Clock Center
                              Listener(
                                behavior: HitTestBehavior.opaque,
                                onPointerDown: (_) => _onPressDown(),
                                onPointerUp: (_) => _onPressUp(),
                                onPointerCancel: (_) => _onPressUp(),
                                child: AnimatedBuilder(
                                  animation: _pulseController,
                                  builder: (context, child) {
                                    return ScaleTransition(
                                      scale: _pulseScale,
                                      child: Container(
                                        width: 140,
                                        height: 140,
                                        decoration: const BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Colors.transparent,
                                        ),
                                        child: Center(
                                          child: Stack(
                                            alignment: Alignment.center,
                                            children: [
                                              if (_pulseController.value > 0)
                                                SizedBox(
                                                  width: 44,
                                                  height: 44,
                                                  child: CircularProgressIndicator(
                                                    value: _pulseController.value,
                                                    strokeWidth: 3.5,
                                                    color: primaryPurple,
                                                    backgroundColor: primaryPurple.withValues(alpha: 0.15),
                                                  ),
                                                ),
                                              Container(
                                                width: 20,
                                                height: 20,
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color: primaryPurple,
                                                  border: Border.all(color: Colors.white, width: 3),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: primaryPurple.withValues(alpha: 0.4),
                                                      blurRadius: 8,
                                                      offset: const Offset(0, 2),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Digital Clock Display
                        Center(
                          child: Column(
                            children: [
                              Text(
                                _formatDigitalTime(_currentTime),
                                style: TextStyle(
                                  fontSize: 38,
                                  fontWeight: FontWeight.w900,
                                  color: textColor,
                                  letterSpacing: -1.0,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _formatDate(_currentTime),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: subTextColor,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 28),

                        // Upcoming Alarm Card
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: cardColor,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 46,
                                height: 46,
                                decoration: BoxDecoration(
                                  color: accentPurple,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(
                                  Icons.alarm_on_rounded,
                                  color: primaryPurple,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '07:00 AM',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w900,
                                        color: textColor,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Alarm • Weekdays (Mon - Fri)',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: subTextColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: _isAlarmEnabled,
                                activeThumbColor: primaryPurple,
                                onChanged: (val) {
                                  setState(() {
                                    _isAlarmEnabled = val;
                                  });
                                },
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 14),

                        // Sleep Schedule Card
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: cardColor,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 46,
                                height: 46,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFCE7F3),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(
                                  Icons.bedtime_rounded,
                                  color: Color(0xFFEC4899),
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Sleep Goal: 8 hrs',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                        color: textColor,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Bedtime 11:00 PM • Wake 07:00 AM',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: subTextColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFDCFCE7),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text(
                                  'Active',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF16A34A),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const Spacer(),

                        // Bottom Floating Add Alarm FAB Mock
                        Center(
                          child: Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [primaryPurple, const Color(0xFF9333EA)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: primaryPurple.withValues(alpha: 0.35),
                                  blurRadius: 14,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.add_rounded,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTabItem(int index, String label, IconData icon, Color activeColor, bool isDark) {
    final isSelected = _selectedTab == index;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedTab = index;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark ? activeColor.withValues(alpha: 0.25) : Colors.white)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            boxShadow: isSelected && !isDark
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [],
          ),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: isSelected ? activeColor : (isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                ),
                if (isSelected) ...[
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: isSelected ? activeColor : (isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDigitalTime(DateTime time) {
    final hour = time.hour == 0 ? 12 : (time.hour > 12 ? time.hour - 12 : time.hour);
    final minute = time.minute.toString().padLeft(2, '0');
    final second = time.second.toString().padLeft(2, '0');
    final period = time.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute:$second $period';
  }

  String _formatDate(DateTime time) {
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final dayName = days[time.weekday - 1];
    final monthName = months[time.month - 1];
    return '$dayName, $monthName ${time.day}';
  }
}

/// CustomPainter that draws the Analog Clock face, hour/minute/second hands, and tick marks.
class AnalogClockPainter extends CustomPainter {
  final DateTime dateTime;
  final Color primaryColor;
  final bool isDark;

  AnalogClockPainter({
    required this.dateTime,
    required this.primaryColor,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // 1. Clock Outer Dial Background & Shadow
    final dialPaint = Paint()
      ..color = isDark ? const Color(0xFF1E293B) : Colors.white
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, radius, dialPaint);

    final borderPaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;

    canvas.drawCircle(center, radius, borderPaint);

    // 2. Hour & Minute Ticks
    final tickPaint = Paint()
      ..color = isDark ? Colors.grey.shade700 : Colors.grey.shade300
      ..strokeWidth = 2;

    final hourTickPaint = Paint()
      ..color = primaryColor
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < 60; i++) {
      final angle = (i * 6) * math.pi / 180;
      final isHourTick = i % 5 == 0;
      final tickLength = isHourTick ? 12.0 : 6.0;

      final startPos = Offset(
        center.dx + (radius - 16) * math.cos(angle),
        center.dy + (radius - 16) * math.sin(angle),
      );
      final endPos = Offset(
        center.dx + (radius - 16 - tickLength) * math.cos(angle),
        center.dy + (radius - 16 - tickLength) * math.sin(angle),
      );

      canvas.drawLine(startPos, endPos, isHourTick ? hourTickPaint : tickPaint);
    }

    // 3. Hour Hand
    final hourAngle = ((dateTime.hour % 12 + dateTime.minute / 60.0) * 30 - 90) * math.pi / 180;
    final hourHandPaint = Paint()
      ..color = isDark ? Colors.white : const Color(0xFF1E1B4B)
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round;

    final hourHandEnd = Offset(
      center.dx + (radius * 0.45) * math.cos(hourAngle),
      center.dy + (radius * 0.45) * math.sin(hourAngle),
    );
    canvas.drawLine(center, hourHandEnd, hourHandPaint);

    // 4. Minute Hand
    final minuteAngle = ((dateTime.minute + dateTime.second / 60.0) * 6 - 90) * math.pi / 180;
    final minuteHandPaint = Paint()
      ..color = primaryColor
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;

    final minuteHandEnd = Offset(
      center.dx + (radius * 0.65) * math.cos(minuteAngle),
      center.dy + (radius * 0.65) * math.sin(minuteAngle),
    );
    canvas.drawLine(center, minuteHandEnd, minuteHandPaint);

    // 5. Second Hand
    final secondAngle = (dateTime.second * 6 - 90) * math.pi / 180;
    final secondHandPaint = Paint()
      ..color = const Color(0xFFEC4899)
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final secondHandEnd = Offset(
      center.dx + (radius * 0.75) * math.cos(secondAngle),
      center.dy + (radius * 0.75) * math.sin(secondAngle),
    );
    canvas.drawLine(center, secondHandEnd, secondHandPaint);

    // 6. Center Cap Outer Ring
    final centerCapPaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 8, centerCapPaint);
  }

  @override
  bool shouldRepaint(covariant AnalogClockPainter oldDelegate) {
    return oldDelegate.dateTime.second != dateTime.second ||
        oldDelegate.isDark != isDark ||
        oldDelegate.primaryColor != primaryColor;
  }
}

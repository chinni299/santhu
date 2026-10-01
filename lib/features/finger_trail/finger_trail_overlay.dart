import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'finger_trail_service.dart';
import 'finger_trail_painter.dart';

/// Full-screen "Touch Together" canvas overlay.
///
/// Shows a dark gradient canvas. Both users draw trails that are synced in
/// real time via [FingerTrailService]. Own trail is the user's accent color;
/// partner's trail is the opposite accent color.
///
/// Call [FingerTrailService.initialize] before pushing this widget.
class FingerTrailOverlay extends StatefulWidget {
  final int currentUserId;
  final VoidCallback onClose;

  const FingerTrailOverlay({
    super.key,
    required this.currentUserId,
    required this.onClose,
  });

  @override
  State<FingerTrailOverlay> createState() => _FingerTrailOverlayState();
}

class _FingerTrailOverlayState extends State<FingerTrailOverlay>
    with SingleTickerProviderStateMixin {
  // ── Trail point lists ─────────────────────────────────────────────────────
  final List<TrailPoint> _myPoints = [];
  final List<TrailPoint> _partnerPoints = [];

  // ── UI state ──────────────────────────────────────────────────────────────
  bool _partnerIsHere = false;

  // ── Ticker for continuous repaint (drives fade animation) ─────────────────
  late Ticker _ticker;
  int _nowMs = DateTime.now().millisecondsSinceEpoch;

  // ── Accent colors ─────────────────────────────────────────────────────────
  late final Color _myColor;
  late final Color _partnerColor;

  static const double _fadeDurationMs = 2500; // a bit longer than fade window

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    // User 1 = teal, User 2 = rose-pink; partner gets the opposite.
    if (widget.currentUserId == 1) {
      _myColor = const Color(0xFF00E5FF);      // Cyan-teal
      _partnerColor = const Color(0xFFFF4081); // Pink
    } else {
      _myColor = const Color(0xFFFF4081);      // Pink
      _partnerColor = const Color(0xFF00E5FF); // Cyan-teal
    }

    // Wire up service callbacks
    FingerTrailService.onPartnerStatus = (isOpen, userId) {
      if (mounted) setState(() => _partnerIsHere = isOpen);
    };

    FingerTrailService.onPartnerPoints = (points) {
      if (!mounted) return;
      setState(() {
        _partnerPoints.addAll(points);
        _pruneExpired();
      });
    };

    // Notify server that this user's overlay is open
    FingerTrailService.openOverlay();

    // Ticker: repaint every frame so the fade is smooth
    _ticker = createTicker((elapsed) {
      if (!mounted) return;
      setState(() {
        _nowMs = DateTime.now().millisecondsSinceEpoch;
        _pruneExpired();
      });
    });
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    FingerTrailService.closeOverlay();
    super.dispose();
  }

  void _pruneExpired() {
    final cutoff = _nowMs - (_fadeDurationMs + 200).toInt();
    _myPoints.removeWhere((p) => p.timestamp < cutoff);
    _partnerPoints.removeWhere((p) => p.timestamp < cutoff);
  }

  // ── Pointer handling ──────────────────────────────────────────────────────

  void _onPanUpdate(DragUpdateDetails d, BoxConstraints constraints) {
    final nx = (d.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
    final ny = (d.localPosition.dy / constraints.maxHeight).clamp(0.0, 1.0);
    final pt = TrailPoint(x: nx, y: ny, timestamp: _nowMs);
    setState(() => _myPoints.add(pt));
    FingerTrailService.addPoint(nx, ny);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── Dark gradient background ────────────────────────────────────
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF0A0F1E),
                  Color(0xFF0D1B2A),
                  Color(0xFF12082A),
                ],
              ),
            ),
          ),

          // ── Subtle star-field texture ───────────────────────────────────
          Positioned.fill(
            child: CustomPaint(painter: _StarFieldPainter()),
          ),

          // ── Gesture + drawing canvas ────────────────────────────────────
          LayoutBuilder(
            builder: (context, constraints) {
              return GestureDetector(
                // Block scroll while drawing
                behavior: HitTestBehavior.opaque,
                onPanStart: (d) => _onPanUpdate(
                  DragUpdateDetails(
                    globalPosition: d.globalPosition,
                    localPosition: d.localPosition,
                    delta: Offset.zero,
                  ),
                  constraints,
                ),
                onPanUpdate: (d) => _onPanUpdate(d, constraints),
                child: RepaintBoundary(
                  child: CustomPaint(
                    size: Size(constraints.maxWidth, constraints.maxHeight),
                    painter: FingerTrailPainter(
                      myPoints: List.unmodifiable(_myPoints),
                      partnerPoints: List.unmodifiable(_partnerPoints),
                      myColor: _myColor,
                      partnerColor: _partnerColor,
                      nowMs: _nowMs,
                    ),
                  ),
                ),
              );
            },
          ),

          // ── Top bar ─────────────────────────────────────────────────────
          Positioned(
            top: 0, left: 0, right: 0,
            child: _buildTopBar(context),
          ),

          // ── Color legend strip ──────────────────────────────────────────
          Positioned(
            bottom: 80, left: 0, right: 0,
            child: _buildLegend(),
          ),

          // ── Bottom hint ─────────────────────────────────────────────────
          Positioned(
            bottom: 36, left: 0, right: 0,
            child: Center(
              child: Text(
                _partnerIsHere ? 'Draw together 💕' : 'Waiting for partner to open…',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.38),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Sub-widgets ───────────────────────────────────────────────────────────

  Widget _buildTopBar(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 10,
        left: 18,
        right: 18,
        bottom: 14,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.72),
            Colors.transparent,
          ],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Icon
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white24, width: 1),
            ),
            child: const Text('✋', style: TextStyle(fontSize: 18)),
          ),
          const SizedBox(width: 12),
          // Title
          const Text(
            'Touch Together',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
          const Spacer(),
          // Partner pill
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _partnerIsHere
                ? _PartnerHerePill(key: const ValueKey('here'))
                : const SizedBox.shrink(key: ValueKey('gone')),
          ),
          const SizedBox(width: 12),
          // Close
          GestureDetector(
            onTap: widget.onClose,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white24, width: 1),
              ),
              child: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _LegendDot(color: _myColor, label: 'You'),
        const SizedBox(width: 20),
        _LegendDot(color: _partnerColor, label: 'Partner'),
      ],
    );
  }
}

// ─── Small widgets ────────────────────────────────────────────────────────────

class _PartnerHerePill extends StatelessWidget {
  const _PartnerHerePill({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.greenAccent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.45), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7, height: 7,
            decoration: const BoxDecoration(
              color: Colors.greenAccent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            'Partner is here',
            style: TextStyle(
              color: Colors.greenAccent,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10, height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ─── Decorative starfield painter ────────────────────────────────────────────

class _StarFieldPainter extends CustomPainter {
  static final List<Offset> _stars = List.generate(
    80,
    (i) {
      final h = (i * 137.5) % 1.0;
      final v = (i * 31.7 + 0.3) % 1.0;
      return Offset(h, v);
    },
  );

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.08);
    for (final s in _stars) {
      canvas.drawCircle(
        Offset(s.dx * size.width, s.dy * size.height),
        1.2,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_StarFieldPainter old) => false;
}

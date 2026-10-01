import 'package:flutter/material.dart';
import 'finger_trail_service.dart';
import 'finger_trail_painter.dart';

/// Full-screen "Touch Together" canvas overlay.
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

  // ── Trail point lists — mutated directly, never via setState ──────────────
  final List<TrailPoint> _myPoints = [];
  final List<TrailPoint> _partnerPoints = [];

  // ── Binary UI state — only this triggers setState ─────────────────────────
  bool _partnerIsHere = false;

  // ── Animation controller drives CustomPainter repaints (no widget rebuild) ─
  late final AnimationController _animCtrl;

  // ── Canvas size — captured from LayoutBuilder, stored for pan handler ─────
  Size _canvasSize = Size.zero;

  // ── Colors ────────────────────────────────────────────────────────────────
  late final Color _myColor;
  late final Color _partnerColor;

  static const double _keepMs = 5000; // prune points older than 5.0 seconds

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    _myColor = widget.currentUserId == 1
        ? const Color(0xFF00E5FF) // Cyan-teal  (user 1)
        : const Color(0xFFFF4081); // Rose-pink  (user 2)
    _partnerColor = widget.currentUserId == 1
        ? const Color(0xFFFF4081)
        : const Color(0xFF00E5FF);

    // AnimationController running at 60fps for silky smooth glowing trails
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(days: 365),
    )..repeat();

    _animCtrl.addListener(_pruneExpired);

    // Partner socket callbacks
    FingerTrailService.onPartnerPoints = (points) {
      if (points.isNotEmpty) {
        _partnerPoints.addAll(points);
        if (!_partnerIsHere && mounted) {
          setState(() => _partnerIsHere = true);
        }
      }
    };

    // Partner presence status
    FingerTrailService.onPartnerStatus = (isOpen, userId) {
      if (mounted) {
        setState(() => _partnerIsHere = isOpen);
      }
    };

    FingerTrailService.openOverlay(widget.currentUserId);
  }

  @override
  void dispose() {
    _animCtrl.removeListener(_pruneExpired);
    _animCtrl.dispose();
    FingerTrailService.closeOverlay();
    FingerTrailService.onPartnerPoints = null;
    FingerTrailService.onPartnerStatus = null;
    super.dispose();
  }

  void _pruneExpired() {
    final cutoff = DateTime.now().millisecondsSinceEpoch - _keepMs.toInt();
    _myPoints.removeWhere((p) => p.timestamp < cutoff);
    _partnerPoints.removeWhere((p) => p.timestamp < cutoff);
  }

  // ── Pointer handling ──────────────────────────────────────────────────────

  void _handlePan(Offset localPosition) {
    if (_canvasSize == Size.zero) return;
    final nx = (localPosition.dx / _canvasSize.width).clamp(0.0, 1.0);
    final ny = (localPosition.dy / _canvasSize.height).clamp(0.0, 1.0);
    _myPoints.add(TrailPoint(
      x: nx,
      y: ny,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    ));
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
          // ── Static dark gradient background ────────────────────────────
          const _Background(),

          // ── Static star-field ──────────────────────────────────────────
          const Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(painter: _StarFieldPainter()),
            ),
          ),

          // ── Gesture layer + canvas ──────────────────────────────────────
          LayoutBuilder(
            builder: (ctx, constraints) {
              _canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
              return Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (e) => _handlePan(e.localPosition),
                onPointerMove: (e) => _handlePan(e.localPosition),
                onPointerHover: (e) {
                  if (e.buttons > 0) {
                    _handlePan(e.localPosition);
                  }
                },
                child: RepaintBoundary(
                  child: CustomPaint(
                    size: _canvasSize,
                    painter: FingerTrailPainter(
                      myPoints: _myPoints,
                      partnerPoints: _partnerPoints,
                      myColor: _myColor,
                      partnerColor: _partnerColor,
                      repaint: _animCtrl,
                    ),
                  ),
                ),
              );
            },
          ),

          // ── UI overlays ────────────────────────────────────────────────
          Positioned(
            top: 0, left: 0, right: 0,
            child: _buildTopBar(context),
          ),
          Positioned(
            bottom: 70, left: 0, right: 0,
            child: _buildLegend(),
          ),
          Positioned(
            bottom: 28, left: 0, right: 0,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: _partnerIsHere
                      ? Colors.tealAccent.withValues(alpha: 0.12)
                      : Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _partnerIsHere
                        ? Colors.tealAccent.withValues(alpha: 0.4)
                        : Colors.white24,
                  ),
                ),
                child: Text(
                  _partnerIsHere
                      ? '💖 Connected with Partner - Draw together!'
                      : '✨ Partner auto-synced... Touch the screen to draw',
                  style: TextStyle(
                    color: _partnerIsHere ? const Color(0xFF64FFDA) : Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
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
            Colors.black.withValues(alpha: 0.85),
            Colors.transparent,
          ],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white24, width: 1),
            ),
            child: const Text('✋', style: TextStyle(fontSize: 18)),
          ),
          const SizedBox(width: 12),
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
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _partnerIsHere
                ? const _PartnerHerePill(key: ValueKey('here'))
                : const _ConnectingPill(key: ValueKey('connecting')),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: widget.onClose,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white30, width: 1),
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
        const SizedBox(width: 24),
        _LegendDot(color: _partnerColor, label: 'Partner'),
      ],
    );
  }
}

// ─── Static dark background ────────────────────────────────────────────────────

class _Background extends StatelessWidget {
  const _Background();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF070B18), Color(0xFF0F172A), Color(0xFF130924)],
        ),
      ),
    );
  }
}

// ─── Small widgets ─────────────────────────────────────────────────────────────

class _PartnerHerePill extends StatelessWidget {
  const _PartnerHerePill({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF00E676).withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: const Color(0xFF00E676).withValues(alpha: 0.6), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: Color(0xFF00E676),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            'Partner Live',
            style: TextStyle(
              color: Color(0xFF00E676),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectingPill extends StatelessWidget {
  const _ConnectingPill({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.4), width: 1),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 8,
            height: 8,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: Colors.amber,
            ),
          ),
          SizedBox(width: 6),
          Text(
            'Live Sync',
            style: TextStyle(
              color: Colors.amber,
              fontSize: 11,
              fontWeight: FontWeight.w600,
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
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.6),
                blurRadius: 6,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.8),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _StarFieldPainter extends CustomPainter {
  const _StarFieldPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final starPaint = Paint()..color = Colors.white.withValues(alpha: 0.35);
    final offsets = [
      Offset(size.width * 0.15, size.height * 0.12),
      Offset(size.width * 0.82, size.height * 0.18),
      Offset(size.width * 0.35, size.height * 0.28),
      Offset(size.width * 0.65, size.height * 0.42),
      Offset(size.width * 0.08, size.height * 0.55),
      Offset(size.width * 0.88, size.height * 0.68),
      Offset(size.width * 0.22, size.height * 0.78),
      Offset(size.width * 0.50, size.height * 0.88),
    ];
    for (final off in offsets) {
      canvas.drawCircle(off, 1.2, starPaint);
    }
  }

  @override
  bool shouldRepaint(_StarFieldPainter old) => false;
}

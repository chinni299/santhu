import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'hug_kiss_service.dart';

// ============================================================================
// 1. WARM HUG ANIMATED OVERLAY (Pop-up Vignette & Floating Hug Animation)
// ============================================================================

class HugAnimatedOverlay extends StatefulWidget {
  final HugData hug;
  final VoidCallback onDismiss;

  const HugAnimatedOverlay({
    super.key,
    required this.hug,
    required this.onDismiss,
  });

  @override
  State<HugAnimatedOverlay> createState() => _HugAnimatedOverlayState();
}

class _HugAnimatedOverlayState extends State<HugAnimatedOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;
  late Animation<double> _fadeAnim;
  final List<_FloatingHeartParticle> _particles = [];
  final Random _rng = Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );

    _scaleAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.2).chain(CurveTween(curve: Curves.easeOutBack)), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 1.2, end: 1.0).chain(CurveTween(curve: Curves.easeInOut)), weight: 15),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 45),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.8).chain(CurveTween(curve: Curves.easeInBack)), weight: 15),
    ]).animate(_controller);

    _fadeAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 15),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 70),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 15),
    ]).animate(_controller);

    // Generate random floating particles
    for (int i = 0; i < 16; i++) {
      _particles.add(_FloatingHeartParticle(
        x: (_rng.nextDouble() - 0.5) * 260,
        y: (_rng.nextDouble() - 0.5) * 260,
        size: 16 + _rng.nextDouble() * 20,
        emoji: ['🤗', '🫂', '💖', '✨', '🌸', '💛'][_rng.nextInt(6)],
        speed: 0.6 + _rng.nextDouble() * 0.8,
      ));
    }

    _controller.forward().then((_) {
      if (mounted) widget.onDismiss();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: false,
        child: GestureDetector(
          onTap: widget.onDismiss,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final fade = _fadeAnim.value;
              final scale = _scaleAnim.value;

              return Container(
                color: const Color(0x77000000).withValues(alpha: fade * 0.45),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Ambient Warm Golden-Pink Vignette Glow
                    Container(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment.center,
                          radius: 0.75,
                          colors: [
                            const Color(0xFFF472B6).withValues(alpha: 0.40 * fade),
                            const Color(0xFFFBBF24).withValues(alpha: 0.25 * fade),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.45, 1.0],
                        ),
                      ),
                    ),

                    // Floating Hug Particles
                    ..._particles.map((p) {
                      final progress = _controller.value;
                      final currentY = p.y - (progress * 120 * p.speed);
                      final particleFade = (1.0 - progress).clamp(0.0, 1.0);

                      return Transform.translate(
                        offset: Offset(p.x, currentY),
                        child: Opacity(
                          opacity: (fade * particleFade).clamp(0.0, 1.0),
                          child: Text(
                            p.emoji,
                            style: TextStyle(fontSize: p.size),
                          ),
                        ),
                      );
                    }),

                    // Center Glassmorphic Hug Card
                    Transform.scale(
                      scale: scale,
                      child: Opacity(
                        opacity: fade.clamp(0.0, 1.0),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 36),
                          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color(0xE62A1B3D),
                                Color(0xE61F172E),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(
                              color: const Color(0xFFFFD54F).withValues(alpha: 0.8),
                              width: 1.8,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFF43F5E).withValues(alpha: 0.35 * fade),
                                blurRadius: 28,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Pulsing Hug Emoji
                              Container(
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(0xFFFFE4E6).withValues(alpha: 0.15),
                                  border: Border.all(
                                    color: const Color(0xFFFFB703),
                                    width: 1.5,
                                  ),
                                ),
                                child: const Text(
                                  '🤗',
                                  style: TextStyle(fontSize: 48),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                '${widget.hug.senderName} sent you a warm hug!',
                                style: const TextStyle(
                                  color: Color(0xFFFFF7ED),
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.3,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                widget.hug.isLive
                                  ? 'Delivered live with love 💖'
                                  : 'Sent while you were away 📬✨',
                                style: TextStyle(
                                  color: const Color(0xFFFBBF24).withValues(alpha: 0.9),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _FloatingHeartParticle {
  final double x;
  final double y;
  final double size;
  final String emoji;
  final double speed;

  _FloatingHeartParticle({
    required this.x,
    required this.y,
    required this.size,
    required this.emoji,
    required this.speed,
  });
}

// ============================================================================
// 2. KISS SYNC INTERACTIVE MODAL / OVERLAY
// ============================================================================

class KissSyncOverlay extends StatefulWidget {
  final int conversationId;
  final int currentUserId;
  final String partnerName;
  final VoidCallback onClose;

  const KissSyncOverlay({
    super.key,
    required this.conversationId,
    required this.currentUserId,
    required this.partnerName,
    required this.onClose,
  });

  @override
  State<KissSyncOverlay> createState() => _KissSyncOverlayState();
}

class _KissSyncOverlayState extends State<KissSyncOverlay>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _holdProgressController;
  late AnimationController _celebrationController;

  bool _isLocalTouching = false;
  bool _isPartnerTouching = false;
  bool _isSyncedMatch = false;
  bool _isKissSuccess = false;
  String _statusMessage = 'Touch & Hold the Kiss circle together';
  Color _statusColor = const Color(0xFFFF80AB);

  final List<_BurstHeart> _burstHearts = [];
  final Random _rng = Random();

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _holdProgressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000), // 1-second hold requirement
    );

    _celebrationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3500),
    );

    _initSocketListeners();
  }

  void _initSocketListeners() {
    HugKissService.onKissPartnerStatus = (isPressing, partnerId) {
      if (!mounted) return;
      setState(() {
        _isPartnerTouching = isPressing;
        if (isPressing && !_isLocalTouching) {
          _statusMessage = '${widget.partnerName} is waiting for your kiss! Touch now 💋';
          _statusColor = const Color(0xFFF43F5E);
        } else if (!isPressing && _isLocalTouching && !_isKissSuccess) {
          _statusMessage = 'Waiting for ${widget.partnerName} to touch within 500ms...';
          _statusColor = const Color(0xFFFFD54F);
        }
      });
    };

    HugKissService.onKissSyncMatched = (syncDiffMs) {
      if (!mounted) return;
      setState(() {
        _isSyncedMatch = true;
        _statusMessage = 'Synchronized! Keep holding for 1 second... ❤️';
        _statusColor = const Color(0xFF10B981);
      });
      _holdProgressController.forward(from: 0.0);
    };

    HugKissService.onKissSuccess = (data) {
      if (!mounted) return;
      _triggerKissSuccessCelebration();
    };

    HugKissService.onKissCancelled = (reason) {
      if (!mounted) return;
      setState(() {
        _isSyncedMatch = false;
        _holdProgressController.reset();
        _statusMessage = '$reason Try holding together!';
        _statusColor = const Color(0xFFEF4444);
      });
    };

    HugKissService.onKissTimeout = (msg) {
      if (!mounted) return;
      setState(() {
        _isLocalTouching = false;
        _isSyncedMatch = false;
        _holdProgressController.reset();
        _statusMessage = msg;
        _statusColor = Colors.white70;
      });
    };

    HugKissService.onKissWindowMissed = (msg) {
      if (!mounted) return;
      setState(() {
        _statusMessage = msg;
        _statusColor = const Color(0xFFFBBF24);
      });
    };
  }

  void _triggerKissSuccessCelebration() {
    setState(() {
      _isKissSuccess = true;
      _isSyncedMatch = false;
      _statusMessage = '💋 SYNCHRONIZED KISS SUCCESS! 💋';
      _statusColor = const Color(0xFFFFD700);
    });

    // Generate bursting hearts from center
    _burstHearts.clear();
    for (int i = 0; i < 45; i++) {
      final angle = _rng.nextDouble() * 2 * pi;
      final distance = 80 + _rng.nextDouble() * 260;
      _burstHearts.add(_BurstHeart(
        targetX: cos(angle) * distance,
        targetY: sin(angle) * distance,
        size: 20 + _rng.nextDouble() * 28,
        emoji: ['💋', '💖', '✨', '💘', '🔥', '🥰', '💕'][_rng.nextInt(7)],
        rotation: (_rng.nextDouble() - 0.5) * 1.5,
      ));
    }

    _celebrationController.forward(from: 0.0).then((_) {
      if (mounted) {
        Timer(const Duration(milliseconds: 1500), () {
          if (mounted) widget.onClose();
        });
      }
    });
  }

  void _handleTouchDown() {
    if (_isKissSuccess) return;
    setState(() {
      _isLocalTouching = true;
      _statusMessage = _isPartnerTouching
          ? 'Connecting kisses...'
          : 'Waiting for ${widget.partnerName} to touch within 500ms...';
      _statusColor = const Color(0xFFFFD54F);
    });
    HugKissService.touchDownKiss();
  }

  void _handleTouchUp() {
    if (_isKissSuccess) return;
    setState(() {
      _isLocalTouching = false;
      _isSyncedMatch = false;
      _holdProgressController.reset();
      _statusMessage = 'Touch & Hold the Kiss circle together';
      _statusColor = const Color(0xFFFF80AB);
    });
    HugKissService.touchUpKiss();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _holdProgressController.dispose();
    _celebrationController.dispose();
    HugKissService.touchUpKiss();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Scaffold(
        backgroundColor: const Color(0xEE090514),
        body: SafeArea(
          child: Stack(
            children: [
              // ── Romantic Gradient Backing ─────────────────────────────────
              Positioned.fill(
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.center,
                      radius: 0.85,
                      colors: [
                        Color(0x33EC4899),
                        Color(0x228B5CF6),
                        Color(0x00000000),
                      ],
                    ),
                  ),
                ),
              ),

              // ── Top Header & Close Button ─────────────────────────────────
              Positioned(
                top: 16,
                left: 20,
                right: 20,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0x33F43F5E),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0x66F43F5E)),
                          ),
                          child: const Text('💋', style: TextStyle(fontSize: 20)),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Kiss Sync',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                            Text(
                              'Hold together within 500ms for 1s',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.6),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 28),
                      onPressed: widget.onClose,
                    ),
                  ],
                ),
              ),

              // ── Main Interactive Center ───────────────────────────────────
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Partner Status Pill
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: _isPartnerTouching
                            ? const Color(0x4410B981)
                            : const Color(0x33334155),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _isPartnerTouching
                              ? const Color(0xFF10B981)
                              : Colors.white12,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _isPartnerTouching
                                  ? const Color(0xFF10B981)
                                  : Colors.grey,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _isPartnerTouching
                                ? '${widget.partnerName} is holding! 💋'
                                : '${widget.partnerName} is ready',
                            style: TextStyle(
                              color: _isPartnerTouching
                                  ? const Color(0xFFA7F3D0)
                                  : Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),

                    // Interactive Glowing Touch-and-Hold Kiss Circle
                    GestureDetector(
                      onTapDown: (_) => _handleTouchDown(),
                      onTapUp: (_) => _handleTouchUp(),
                      onTapCancel: () => _handleTouchUp(),
                      child: AnimatedBuilder(
                        animation: Listenable.merge([_pulseController, _holdProgressController]),
                        builder: (context, child) {
                          final pulse = _pulseController.value;
                          final progress = _holdProgressController.value;

                          return Stack(
                            alignment: Alignment.center,
                            children: [
                              // Outer Glowing Aura Rings
                              Container(
                                width: 220 + 20 * pulse,
                                height: 220 + 20 * pulse,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: (_isSyncedMatch
                                          ? const Color(0xFF10B981)
                                          : const Color(0xFFF43F5E))
                                      .withValues(alpha: _isLocalTouching ? 0.35 : 0.15),
                                ),
                              ),

                              // Progress Arc for 1-Second Hold
                              SizedBox(
                                width: 190,
                                height: 190,
                                child: CircularProgressIndicator(
                                  value: progress > 0 ? progress : null,
                                  strokeWidth: 4.5,
                                  color: _isSyncedMatch
                                      ? const Color(0xFFFFD700)
                                      : const Color(0xFFFF4081),
                                  backgroundColor: Colors.white10,
                                ),
                              ),

                              // Center Core Button
                              Container(
                                width: 160,
                                height: 160,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: _isSyncedMatch
                                        ? [const Color(0xFF059669), const Color(0xFF10B981)]
                                        : _isLocalTouching
                                            ? [const Color(0xFFE11D48), const Color(0xFFFB7185)]
                                            : [const Color(0xFF831843), const Color(0xFFBE185D)],
                                  ),
                                  border: Border.all(
                                    color: _isSyncedMatch
                                        ? const Color(0xFFFFD700)
                                        : const Color(0xFFFF80AB),
                                    width: 2.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: (_isSyncedMatch
                                              ? const Color(0xFF10B981)
                                              : const Color(0xFFF43F5E))
                                          .withValues(alpha: 0.5),
                                      blurRadius: 24,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      _isKissSuccess ? '✨💋✨' : '💋',
                                      style: TextStyle(
                                        fontSize: _isLocalTouching ? 54 : 48,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _isSyncedMatch
                                          ? 'HOLDING...'
                                          : _isLocalTouching
                                              ? 'HOLD'
                                              : 'TOUCH & HOLD',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1.0,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 36),

                    // Status Text Message
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        _statusMessage,
                        style: TextStyle(
                          color: _statusColor,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),

              // ── Bursting Heart Particles on Kiss Success ───────────────────
              if (_isKissSuccess)
                ..._burstHearts.map((heart) {
                  return AnimatedBuilder(
                    animation: _celebrationController,
                    builder: (context, child) {
                      final val = _celebrationController.value;
                      final posX = MediaQuery.of(context).size.width / 2 + heart.targetX * val;
                      final posY = MediaQuery.of(context).size.height / 2 + heart.targetY * val;
                      final alpha = (1.0 - val).clamp(0.0, 1.0);

                      return Positioned(
                        left: posX - heart.size / 2,
                        top: posY - heart.size / 2,
                        child: Transform.rotate(
                          angle: heart.rotation * val * 4,
                          child: Opacity(
                            opacity: alpha,
                            child: Text(
                              heart.emoji,
                              style: TextStyle(fontSize: heart.size),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }
}

class _BurstHeart {
  final double targetX;
  final double targetY;
  final double size;
  final String emoji;
  final double rotation;

  _BurstHeart({
    required this.targetX,
    required this.targetY,
    required this.size,
    required this.emoji,
    required this.rotation,
  });
}

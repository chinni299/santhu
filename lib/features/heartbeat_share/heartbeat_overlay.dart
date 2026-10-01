import 'package:flutter/material.dart';
import 'heartbeat_audio.dart';
import 'heartbeat_service.dart';

class HeartbeatOverlay extends StatefulWidget {
  final VoidCallback? onClose;

  const HeartbeatOverlay({
    super.key,
    this.onClose,
  });

  @override
  State<HeartbeatOverlay> createState() => _HeartbeatOverlayState();
}

class _HeartbeatOverlayState extends State<HeartbeatOverlay> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  bool _isMuted = false;

  @override
  void initState() {
    super.initState();
    _isMuted = HeartbeatAudio.getMuted();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.35).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeOutBack),
    );

    _opacityAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Listen for incoming beat ticks to trigger heart pulse animation
    HeartbeatService.onBeat = (beatType) {
      if (mounted) {
        _pulseController.forward(from: 0.0).then((_) {
          if (mounted) {
            _pulseController.reverse();
          }
        });
      }
    };
  }

  @override
  void dispose() {
    HeartbeatService.onBeat = null;
    _pulseController.dispose();
    super.dispose();
  }

  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
      HeartbeatAudio.setMuted(_isMuted);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // Semi-transparent backdrop blur vignette
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.65),
            ),
          ),

          // Main Pulsing Heart Centered Content
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ScaleTransition(
                  scale: _scaleAnimation,
                  child: FadeTransition(
                    opacity: _opacityAnimation,
                    child: Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.redAccent.shade400,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.redAccent.withValues(alpha: 0.8),
                            blurRadius: 36,
                            spreadRadius: 10,
                          ),
                          BoxShadow(
                            color: Colors.pinkAccent.withValues(alpha: 0.4),
                            blurRadius: 60,
                            spreadRadius: 20,
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.favorite_rounded,
                          color: Colors.white,
                          size: 76,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                const Text(
                  'Sharing Heartbeat... ❤️',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Feel the rhythm of your partner\'s heart',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          // Audio Mute/Unmute Floating Button at Top Right
          Positioned(
            top: 48,
            right: 20,
            child: IconButton(
              onPressed: _toggleMute,
              style: IconButton.styleFrom(
                backgroundColor: Colors.white24,
                padding: const EdgeInsets.all(12),
              ),
              icon: Icon(
                _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                color: Colors.white,
                size: 24,
              ),
              tooltip: _isMuted ? 'Unmute Sound' : 'Mute Sound',
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'heartbeat_service.dart';

class HeartbeatButton extends StatefulWidget {
  final io.Socket? socket;
  final int conversationId;
  final bool isPartnerOnline;

  const HeartbeatButton({
    super.key,
    required this.socket,
    required this.conversationId,
    required this.isPartnerOnline,
  });

  @override
  State<HeartbeatButton> createState() => _HeartbeatButtonState();
}

class _HeartbeatButtonState extends State<HeartbeatButton> with SingleTickerProviderStateMixin {
  bool _isHolding = false;
  late AnimationController _pulseController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _onPressDown() {
    if (_isHolding) return;

    final started = HeartbeatService.startSending(
      socket: widget.socket,
      conversationId: widget.conversationId,
      isPartnerOnline: widget.isPartnerOnline,
      onOffline: _showOfflineSnackbar,
    );

    if (started) {
      setState(() => _isHolding = true);
      _pulseController.repeat(reverse: true);
    }
  }

  void _onPressUp() {
    if (!_isHolding) return;
    HeartbeatService.stopSending(
      socket: widget.socket,
      conversationId: widget.conversationId,
    );
    _stopHoldingState();
  }

  void _stopHoldingState() {
    if (mounted) {
      setState(() => _isHolding = false);
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  void _showOfflineSnackbar() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.heart_broken_rounded, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text(
              'Partner is offline 💔',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ],
        ),
        backgroundColor: Colors.redAccent.shade700,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _onPressDown(),
      onTapUp: (_) => _onPressUp(),
      onTapCancel: () => _onPressUp(),
      onLongPressStart: (_) => _onPressDown(),
      onLongPressEnd: (_) => _onPressUp(),
      onLongPressCancel: () => _onPressUp(),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _isHolding
                ? Colors.redAccent
                : Colors.pink.withValues(alpha: 0.15),
            border: Border.all(
              color: _isHolding
                  ? Colors.red
                  : Colors.pinkAccent.withValues(alpha: 0.4),
              width: _isHolding ? 2 : 1,
            ),
            boxShadow: _isHolding
                ? [
                    BoxShadow(
                      color: Colors.redAccent.withValues(alpha: 0.6),
                      blurRadius: 14,
                      spreadRadius: 3,
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Icon(
              _isHolding ? Icons.favorite_rounded : Icons.monitor_heart_rounded,
              size: _isHolding ? 22 : 19,
              color: _isHolding
                  ? Colors.white
                  : (isDark ? Colors.pink.shade300 : Colors.pinkAccent),
            ),
          ),
        ),
      ),
    );
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'thinking_of_you_service.dart';

class ThinkingOfYouButton extends StatefulWidget {
  final io.Socket? socket;
  final int conversationId;
  final VoidCallback? onSent;

  const ThinkingOfYouButton({
    super.key,
    required this.socket,
    required this.conversationId,
    this.onSent,
  });

  @override
  State<ThinkingOfYouButton> createState() => _ThinkingOfYouButtonState();
}

class _ThinkingOfYouButtonState extends State<ThinkingOfYouButton> {
  Timer? _timer;
  int _cooldownLeft = 0;

  @override
  void initState() {
    super.initState();
    _checkCooldown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _checkCooldown() {
    final left = ThinkingOfYouService.remainingCooldownSeconds;
    if (left > 0) {
      setState(() => _cooldownLeft = left);
      _startTimer();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final left = ThinkingOfYouService.remainingCooldownSeconds;
      if (mounted) {
        setState(() => _cooldownLeft = left);
      }
      if (left <= 0) {
        timer.cancel();
      }
    });
  }

  void _onPress() {
    if (_cooldownLeft > 0) return;
    final sent = ThinkingOfYouService.sendThinkingOfYou(
      socket: widget.socket,
      conversationId: widget.conversationId,
    );
    if (sent) {
      _startTimer();
      if (widget.onSent != null) widget.onSent!();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sent "Thinking of You" ❤️')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDisabled = _cooldownLeft > 0;

    return ElevatedButton.icon(
      onPressed: isDisabled ? null : _onPress,
      style: ElevatedButton.styleFrom(
        backgroundColor: isDisabled ? Colors.grey.withValues(alpha: 0.2) : Colors.pinkAccent.withValues(alpha: 0.2),
        foregroundColor: isDisabled ? Colors.grey : Colors.pinkAccent,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
          side: BorderSide(color: isDisabled ? Colors.grey : Colors.pinkAccent, width: 1.5),
        ),
      ),
      icon: const Icon(Icons.favorite_rounded, size: 18),
      label: Text(
        isDisabled ? 'Thinking of You (${_cooldownLeft}s)' : '❤️ Thinking of You',
        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
      ),
    );
  }
}

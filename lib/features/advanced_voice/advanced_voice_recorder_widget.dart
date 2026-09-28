import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'voice_waveform_widget.dart';

class AdvancedVoiceRecorderWidget extends StatelessWidget {
  final bool isRecording;
  final int seconds;
  final VoidCallback onCancel;
  final VoidCallback onStopAndSend;

  const AdvancedVoiceRecorderWidget({
    super.key,
    required this.isRecording,
    required this.seconds,
    required this.onCancel,
    required this.onStopAndSend,
  });

  @override
  Widget build(BuildContext context) {
    if (!isRecording) return const SizedBox.shrink();

    final mins = seconds ~/ 60;
    final secs = (seconds % 60).toString().padLeft(2, '0');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          const Icon(Icons.mic, color: Colors.redAccent, size: 20),
          const SizedBox(width: 8),
          Text(
            '$mins:$secs',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: VoiceWaveformWidget(
              amplitudes: [0.2, 0.5, 0.8, 0.4, 0.9, 0.6, 0.3, 0.7, 0.5, 0.9],
              progress: 1.0,
              activeColor: Colors.redAccent,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.grey),
            onPressed: onCancel,
          ),
          IconButton(
            icon: const Icon(Icons.send, color: AppTheme.primaryTeal),
            onPressed: onStopAndSend,
          ),
        ],
      ),
    );
  }
}

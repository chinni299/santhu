import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../theme/app_theme.dart';
import 'voice_waveform_widget.dart';

class AdvancedVoicePlayerWidget extends StatefulWidget {
  final String audioUrl;
  final Color activeColor;

  const AdvancedVoicePlayerWidget({
    super.key,
    required this.audioUrl,
    this.activeColor = AppTheme.primaryTeal,
  });

  @override
  State<AdvancedVoicePlayerWidget> createState() => _AdvancedVoicePlayerWidgetState();
}

class _AdvancedVoicePlayerWidgetState extends State<AdvancedVoicePlayerWidget> {
  late AudioPlayer _player;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  double _playbackSpeed = 1.0;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();

    _player.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() => _isPlaying = state == PlayerState.playing);
      }
    });

    _player.onDurationChanged.listen((d) {
      if (mounted) {
        setState(() => _duration = d);
      }
    });

    _player.onPositionChanged.listen((p) {
      if (mounted) {
        setState(() => _position = p);
      }
    });
  }

  Future<void> _togglePlay() async {
    if (_isPlaying) {
      await _player.pause();
    } else {
      await _player.setPlaybackRate(_playbackSpeed);
      await _player.play(UrlSource(widget.audioUrl));
    }
  }

  Future<void> _cycleSpeed() async {
    double nextSpeed = 1.0;
    if (_playbackSpeed == 1.0) {
      nextSpeed = 1.5;
    } else if (_playbackSpeed == 1.5) {
      nextSpeed = 2.0;
    } else {
      nextSpeed = 1.0;
    }

    setState(() => _playbackSpeed = nextSpeed);
    if (_isPlaying) {
      await _player.setPlaybackRate(nextSpeed);
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _duration.inMilliseconds > 0
        ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    final mins = _position.inMinutes;
    final secs = (_position.inSeconds % 60).toString().padLeft(2, '0');
    final timeStr = '$mins:$secs';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black12,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(_isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill),
            iconSize: 32,
            color: widget.activeColor,
            onPressed: _togglePlay,
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 120,
            child: VoiceWaveformWidget(
              amplitudes: const [0.3, 0.6, 0.2, 0.8, 0.5, 0.9, 0.4, 0.7, 0.3, 0.6, 0.8, 0.4],
              progress: progress,
              activeColor: widget.activeColor,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            timeStr,
            style: const TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 6),
          InkWell(
            onTap: _cycleSpeed,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${_playbackSpeed}x',
                style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'heartbeat_audio.dart';

typedef OnBeatCallback = void Function(String beatType);
typedef OnStateCallback = void Function(bool isActive, int? senderId);
typedef OnOfflineCallback = void Function();

class HeartbeatService {
  static Timer? _rhythmTimer;
  static Timer? _tapBurstTimer;
  static bool _isSending = false;
  static bool _isReceiving = false;
  static int? _activeSenderId;

  static OnBeatCallback? onBeat;
  static OnStateCallback? onStateChange;
  static OnOfflineCallback? onPartnerOffline;

  static bool get isSending => _isSending;
  static bool get isReceiving => _isReceiving;
  static int? get activeSenderId => _activeSenderId;

  /// Start sending heartbeat rhythm to partner over socket
  static bool startSending({
    required io.Socket? socket,
    required int conversationId,
    bool isPartnerOnline = true,
    OnOfflineCallback? onOffline,
  }) {
    _tapBurstTimer?.cancel();
    _tapBurstTimer = null;

    if (socket == null || !socket.connected) {
      if (onOffline != null) onOffline();
      return false;
    }
    if (_isSending) return true;

    _isSending = true;
    onPartnerOffline = onOffline;

    debugPrint('[HEARTBEAT SERVICE] EMITTING heartbeat_start to socket');

    // Emit initial start event
    socket.emit('heartbeat_start', {
      'conversationId': conversationId,
      'bpm': 75,
    });

    // Start organic lub-dub rhythm generator (75 BPM => ~800ms cycle)
    _startRhythmLoop(socket, conversationId);
    return true;
  }

  /// Keep sending heartbeat for a 3-second burst after a short tap
  static void extendForTapBurst(io.Socket? socket, int conversationId, [int seconds = 3]) {
    _tapBurstTimer?.cancel();
    _tapBurstTimer = Timer(Duration(seconds: seconds), () {
      stopSending(socket: socket, conversationId: conversationId);
    });
  }

  static void _startRhythmLoop(io.Socket socket, int conversationId) {
    _rhythmTimer?.cancel();

    void emitBeatCycle() {
      if (!_isSending) return;

      // Lub beat at 0ms
      socket.emit('heartbeat_beat', {
        'conversationId': conversationId,
        'beatType': 'lub',
        'bpm': 75,
      });
      HeartbeatAudio.playBeat('lub');
      HeartbeatAudio.vibrate([60, 60, 60, 600]);

      // Dub beat after 140ms
      Timer(const Duration(milliseconds: 140), () {
        if (!_isSending) return;
        socket.emit('heartbeat_beat', {
          'conversationId': conversationId,
          'beatType': 'dub',
          'bpm': 75,
        });
        HeartbeatAudio.playBeat('dub');
      });
    }

    // First beat immediately
    emitBeatCycle();

    // Repeat cycle every 800ms (~75 BPM)
    _rhythmTimer = Timer.periodic(const Duration(milliseconds: 800), (_) {
      if (!_isSending) {
        _rhythmTimer?.cancel();
        return;
      }
      emitBeatCycle();
    });
  }

  /// Stop sending heartbeat rhythm
  static void stopSending({
    required io.Socket? socket,
    required int conversationId,
  }) {
    _tapBurstTimer?.cancel();
    _tapBurstTimer = null;

    if (!_isSending) return;
    _isSending = false;
    _rhythmTimer?.cancel();
    _rhythmTimer = null;

    debugPrint('[HEARTBEAT SERVICE] EMITTING heartbeat_stop to socket');

    if (socket != null && socket.connected) {
      socket.emit('heartbeat_stop', {
        'conversationId': conversationId,
      });
    }
    HeartbeatAudio.stopVibrate();
  }

  /// Listen for incoming heartbeat socket events from partner
  static void listenToSocket(io.Socket? socket) {
    if (socket == null) return;

    socket.off('heartbeat_start');
    socket.off('heartbeat_beat');
    socket.off('heartbeat_stop');
    socket.off('heartbeat_partner_offline');

    socket.on('heartbeat_start', (data) {
      debugPrint('[HEARTBEAT SERVICE] Received heartbeat_start: $data');
      _isReceiving = true;
      _activeSenderId = data != null && data['senderId'] != null ? data['senderId'] as int : null;
      if (onStateChange != null) {
        onStateChange!(true, _activeSenderId);
      }
    });

    socket.on('heartbeat_beat', (data) {
      debugPrint('[HEARTBEAT SERVICE] Received heartbeat_beat: $data');
      if (!_isReceiving) {
        _isReceiving = true;
        _activeSenderId = data != null && data['senderId'] != null ? data['senderId'] as int : null;
        if (onStateChange != null) {
          onStateChange!(true, _activeSenderId);
        }
      }
      final beatType = (data != null && data['beatType'] != null) ? data['beatType'].toString() : 'lub';

      // Trigger Web Audio & Vibration
      HeartbeatAudio.playBeat(beatType);
      HeartbeatAudio.vibrate(beatType == 'lub' ? [70, 90, 70, 600] : [50, 50]);

      if (onBeat != null) {
        onBeat!(beatType);
      }
    });

    socket.on('heartbeat_stop', (data) {
      debugPrint('[HEARTBEAT SERVICE] Received heartbeat_stop');
      _isReceiving = false;
      _activeSenderId = null;
      HeartbeatAudio.stopVibrate();

      if (onStateChange != null) {
        onStateChange!(false, null);
      }
    });

    socket.on('heartbeat_partner_offline', (data) {
      debugPrint('[HEARTBEAT SERVICE] Received heartbeat_partner_offline');
      _isSending = false;
      _rhythmTimer?.cancel();
      _rhythmTimer = null;
      _tapBurstTimer?.cancel();
      _tapBurstTimer = null;
      HeartbeatAudio.stopVibrate();

      if (onPartnerOffline != null) {
        onPartnerOffline!();
      }
    });
  }

  /// Clean up listeners
  static void cleanup(io.Socket? socket) {
    _rhythmTimer?.cancel();
    _rhythmTimer = null;
    _tapBurstTimer?.cancel();
    _tapBurstTimer = null;
    _isSending = false;
    _isReceiving = false;
    _activeSenderId = null;

    if (socket != null) {
      socket.off('heartbeat_start');
      socket.off('heartbeat_beat');
      socket.off('heartbeat_stop');
      socket.off('heartbeat_partner_offline');
    }
  }
}

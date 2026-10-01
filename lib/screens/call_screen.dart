import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../config/webrtc_config.dart';
import '../theme/app_theme.dart';

class CallScreen extends StatefulWidget {
  final io.Socket? socket;
  final int conversationId;
  final int currentUserId;
  final String peerName;
  final bool isVideoCall;
  final bool isCaller;

  const CallScreen({
    super.key,
    required this.socket,
    required this.conversationId,
    required this.currentUserId,
    required this.peerName,
    required this.isVideoCall,
    required this.isCaller,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  bool _isMuted = false;
  bool _isCameraOff = false;
  bool _isFrontCamera = true;
  bool _isSpeakerOn = true;
  bool _isCallConnected = false;
  bool _hasRemoteDescription = false;
  String _callStatus = 'Connecting...';
  String? _permissionError;

  // Call duration timer
  Timer? _callTimer;
  int _callDurationSeconds = 0;

  // Realtime getStats logging timer (every 2 seconds)
  Timer? _statsTimer;

  bool _iceRestartAttempted = false;
  final List<RTCIceCandidate> _pendingIceCandidates = [];

  @override
  void initState() {
    super.initState();
    _callStatus = widget.isCaller ? 'Calling...' : 'Connecting call...';
    _isCameraOff = !widget.isVideoCall;
    // Default speaker to false (earpiece) for audio calls, true for video calls
    _isSpeakerOn = widget.isVideoCall;
    _initCall();
  }

  Future<bool> _requestPermissions() async {
    if (kIsWeb) return true;

    try {
      final permissionsToRequest = <Permission>[
        Permission.microphone,
      ];
      if (widget.isVideoCall) {
        permissionsToRequest.add(Permission.camera);
      }
      // Request Bluetooth Connect on Android 12+ if available
      try {
        permissionsToRequest.add(Permission.bluetoothConnect);
      } catch (_) {}

      final statuses = await permissionsToRequest.request();

      final micGranted = statuses[Permission.microphone]?.isGranted == true;
      final camGranted = !widget.isVideoCall || (statuses[Permission.camera]?.isGranted == true);

      debugPrint("[WEBRTC PERMISSIONS] Mic granted: $micGranted, Camera granted: $camGranted");

      if (!micGranted) {
        setState(() {
          _permissionError = 'Microphone permission is required for calls.';
          _callStatus = 'Permission Denied';
        });
        return false;
      }

      if (widget.isVideoCall && !camGranted) {
        setState(() {
          _permissionError = 'Camera permission is required for video calls.';
          _callStatus = 'Permission Denied';
        });
        return false;
      }

      return true;
    } catch (e, stack) {
      debugPrint("[WEBRTC PERMISSIONS ERROR] $e\n$stack");
      return true; // continue attempt
    }
  }

  Future<void> _initCall() async {
    try {
      final granted = await _requestPermissions();
      if (!granted) {
        debugPrint("[WEBRTC] Aborting call initialization due to missing permissions.");
        return;
      }

      await _localRenderer.initialize();
      await _remoteRenderer.initialize();

      // Constraints test: log exact parameters and test getUserMedia
      final mediaConstraints = <String, dynamic>{
        'audio': true,
        'video': widget.isVideoCall
            ? {
                'facingMode': 'user',
                'width': {'ideal': 640},
                'height': {'ideal': 480},
                'frameRate': {'ideal': 30},
              }
            : false,
      };

      try {
        debugPrint("[WEBRTC MEDIA] Invoking getUserMedia with constraints: $mediaConstraints");
        _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
        debugPrint("[WEBRTC MEDIA] getUserMedia SUCCESS. Audio tracks: ${_localStream?.getAudioTracks().length}, Video tracks: ${_localStream?.getVideoTracks().length}");
      } catch (e, stack) {
        debugPrint("[WEBRTC MEDIA ERROR] Exact getUserMedia Exception: ($e) [Type: ${e.runtimeType}]\n$stack");
        try {
          debugPrint("[WEBRTC MEDIA] Attempting simple constraints fallback...");
          _localStream = await navigator.mediaDevices.getUserMedia({
            'audio': true,
            'video': widget.isVideoCall,
          });
          debugPrint("[WEBRTC MEDIA] Fallback getUserMedia SUCCESS");
        } catch (e2, stack2) {
          debugPrint("[WEBRTC MEDIA ERROR] Fallback getUserMedia Exception: ($e2)\n$stack2");
          _isMuted = true;
          _isCameraOff = true;
          if (mounted) {
            setState(() {
              _permissionError = 'Could not access microphone or camera.';
              _callStatus = 'Media Device Error';
            });
          }
        }
      }

      if (_localStream != null) {
        _localRenderer.srcObject = _localStream;
        for (var track in _localStream!.getAudioTracks()) {
          track.enabled = true;
          debugPrint("[WEBRTC MEDIA] Enabled local audio track: ${track.id}");
        }
        for (var track in _localStream!.getVideoTracks()) {
          track.enabled = !_isCameraOff;
          debugPrint("[WEBRTC MEDIA] Enabled local video track: ${track.id}");
        }
      }

      // Initialize WebRTC PeerConnection with STUN + TURN servers
      final configuration = WebRtcConfig.peerConnectionConfiguration;
      debugPrint("[WEBRTC ICE] Initializing PeerConnection with ${(configuration['iceServers'] as List).length} ICE servers");

      _peerConnection = await createPeerConnection(configuration);

      // Add local stream tracks to PeerConnection
      if (_localStream != null) {
        for (var track in _localStream!.getTracks()) {
          final sender = await _peerConnection?.addTrack(track, _localStream!);
          debugPrint("[WEBRTC TRACK] Added local ${track.kind} track (id: ${track.id}) -> sender: ${sender?.track?.id}");
        }
      }

      // Handle Remote Stream Tracks (Unified Plan)
      _peerConnection?.onTrack = (RTCTrackEvent event) async {
        debugPrint('[WEBRTC TRACK] onTrack received: kind=${event.track.kind}, id=${event.track.id}, streams=${event.streams.length}');
        event.track.enabled = true;

        if (event.streams.isNotEmpty) {
          _remoteStream = event.streams[0];
        } else {
          _remoteStream ??= await createLocalMediaStream('remote_stream_${DateTime.now().millisecondsSinceEpoch}');
          _remoteStream!.addTrack(event.track);
        }

        for (var track in _remoteStream!.getAudioTracks()) {
          track.enabled = true;
        }
        for (var track in _remoteStream!.getVideoTracks()) {
          track.enabled = true;
        }

        if (mounted) {
          setState(() {
            _remoteRenderer.srcObject = _remoteStream;
            _isCallConnected = true;
            _callStatus = 'Connected';
          });
          _startCallTimerIfNeeded();
          _startStatsLogging();
          _applyAudioRouting();
        }
      };

      // Handle Remote Stream (Plan-B fallback)
      _peerConnection?.onAddStream = (MediaStream stream) {
        debugPrint('[WEBRTC TRACK] onAddStream received: id=${stream.id}, audio=${stream.getAudioTracks().length}, video=${stream.getVideoTracks().length}');
        for (var track in stream.getAudioTracks()) {
          track.enabled = true;
        }
        for (var track in stream.getVideoTracks()) {
          track.enabled = true;
        }
        _remoteStream = stream;
        if (mounted) {
          setState(() {
            _remoteRenderer.srcObject = _remoteStream;
            _isCallConnected = true;
            _callStatus = 'Connected';
          });
          _startCallTimerIfNeeded();
          _startStatsLogging();
          _applyAudioRouting();
        }
      };

      // Handle ICE Candidates generated locally
      _peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
        if (candidate.candidate != null && candidate.candidate!.isNotEmpty) {
          debugPrint("[WEBRTC ICE] Generated candidate: ${candidate.candidate?.substring(0, 30)}...");
          widget.socket?.emit('webrtcIceCandidate', {
            'conversationId': widget.conversationId,
            'candidate': candidate.toMap(),
            'senderId': widget.currentUserId,
          });
        }
      };

      // Handle ICE Connection State Changes
      _peerConnection?.onIceConnectionState = (RTCIceConnectionState state) {
        debugPrint("[WEBRTC ICE STATE] Connection state changed: $state");
        if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
            state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
          _iceRestartAttempted = false;
          if (mounted) {
            setState(() {
              _isCallConnected = true;
              _callStatus = 'Connected';
            });
            _startCallTimerIfNeeded();
            _startStatsLogging();
            _applyAudioRouting();
          }
        } else if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
          if (mounted && _isCallConnected) {
            setState(() => _callStatus = 'Reconnecting...');
          }
        } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
          _attemptIceRestart();
        }
      };

      _setupSocketListeners();

      if (widget.isCaller) {
        debugPrint("[WEBRTC] Emitting callUser as Caller (User ${widget.currentUserId})");
        widget.socket?.emit('callUser', {
          'conversationId': widget.conversationId,
          'isVideoCall': widget.isVideoCall,
          'callerId': widget.currentUserId,
          'senderId': widget.currentUserId,
        });
      } else {
        debugPrint("[WEBRTC] Emitting acceptCall as Receiver (User ${widget.currentUserId})");
        widget.socket?.emit('acceptCall', {
          'conversationId': widget.conversationId,
          'userId': widget.currentUserId,
          'senderId': widget.currentUserId,
        });
      }
    } catch (e, stack) {
      debugPrint("[WEBRTC ERROR] Error in _initCall: $e\n$stack");
      if (mounted) {
        setState(() => _callStatus = 'Call Initialization Failed');
      }
    }
  }

  void _applyAudioRouting() {
    if (!kIsWeb) {
      try {
        Helper.setSpeakerphoneOn(_isSpeakerOn);
        debugPrint("[WEBRTC AUDIO] Speakerphone set to: $_isSpeakerOn");
      } catch (e) {
        debugPrint("[WEBRTC AUDIO ERROR] Setting speakerphone failed: $e");
      }
    }
  }

  void _setupSocketListeners() {
    widget.socket?.on('callAccepted', (data) async {
      debugPrint("[WEBRTC SIGNAL] callAccepted received by Caller");
      if (mounted && widget.isCaller) {
        setState(() => _callStatus = 'Connecting media...');
        await _createOffer();
      }
    });

    widget.socket?.on('callRejected', (data) {
      debugPrint("[WEBRTC SIGNAL] callRejected received");
      if (mounted) {
        setState(() => _callStatus = 'Call Declined');
        Future.delayed(const Duration(seconds: 1), _endCallLocal);
      }
    });

    widget.socket?.on('callCancelled', (data) {
      debugPrint("[WEBRTC SIGNAL] callCancelled received");
      if (mounted) {
        setState(() => _callStatus = 'Call Cancelled');
        Future.delayed(const Duration(seconds: 1), _endCallLocal);
      }
    });

    widget.socket?.on('callMissed', (data) {
      debugPrint("[WEBRTC SIGNAL] callMissed received");
      if (mounted) {
        setState(() => _callStatus = 'No Answer');
        Future.delayed(const Duration(seconds: 1), _endCallLocal);
      }
    });

    widget.socket?.on('webrtcOffer', (data) async {
      debugPrint("[WEBRTC SIGNAL] webrtcOffer received");
      if (mounted && !widget.isCaller && data != null && data['sdp'] != null) {
        await _handleOffer(Map<String, dynamic>.from(data['sdp']));
      }
    });

    widget.socket?.on('webrtcAnswer', (data) async {
      debugPrint("[WEBRTC SIGNAL] webrtcAnswer received");
      if (mounted && widget.isCaller && data != null && data['sdp'] != null) {
        await _handleAnswer(Map<String, dynamic>.from(data['sdp']));
      }
    });

    widget.socket?.on('webrtcIceCandidate', (data) async {
      if (mounted && data != null && data['candidate'] != null) {
        final candidateData = Map<String, dynamic>.from(data['candidate']);
        final candidate = RTCIceCandidate(
          candidateData['candidate'],
          candidateData['sdpMid'],
          candidateData['sdpMLineIndex'],
        );

        if (_peerConnection != null && _hasRemoteDescription) {
          try {
            await _peerConnection!.addCandidate(candidate);
            debugPrint("[WEBRTC ICE] Added remote candidate directly");
          } catch (e) {
            debugPrint("[WEBRTC ICE ERROR] Failed to add candidate: $e");
          }
        } else {
          _pendingIceCandidates.add(candidate);
          debugPrint("[WEBRTC ICE] Queued candidate (total pending: ${_pendingIceCandidates.length})");
        }
      }
    });

    widget.socket?.on('callEnded', (data) {
      debugPrint("[WEBRTC SIGNAL] callEnded received");
      if (mounted) {
        setState(() => _callStatus = 'Call Ended');
        Future.delayed(const Duration(milliseconds: 500), _endCallLocal);
      }
    });
  }

  Future<void> _attemptIceRestart() async {
    if (_iceRestartAttempted || _peerConnection == null) {
      if (mounted) setState(() => _callStatus = 'Connection error');
      return;
    }
    _iceRestartAttempted = true;

    if (mounted) setState(() => _callStatus = 'Reconnecting...');
    debugPrint("[WEBRTC ICE] Attempting ICE restart...");

    try {
      if (widget.isCaller) {
        final offer = await _peerConnection!.createOffer({
          'offerToReceiveVideo': widget.isVideoCall,
          'offerToReceiveAudio': true,
          'iceRestart': true,
        });
        await _peerConnection!.setLocalDescription(offer);
        widget.socket?.emit('webrtcOffer', {
          'conversationId': widget.conversationId,
          'sdp': offer.toMap(),
          'senderId': widget.currentUserId,
        });
        debugPrint("[WEBRTC ICE] ICE restart offer sent");
      }
    } catch (e) {
      debugPrint("[WEBRTC ICE ERROR] ICE restart failed: $e");
    }
  }

  Future<void> _createOffer() async {
    try {
      if (_peerConnection == null) return;
      final offer = await _peerConnection!.createOffer({
        'offerToReceiveVideo': widget.isVideoCall,
        'offerToReceiveAudio': true,
      });
      await _peerConnection!.setLocalDescription(offer);

      widget.socket?.emit('webrtcOffer', {
        'conversationId': widget.conversationId,
        'sdp': offer.toMap(),
        'senderId': widget.currentUserId,
      });
      debugPrint("[WEBRTC SIGNAL] Offer created and emitted by User ${widget.currentUserId}");
    } catch (e, stack) {
      debugPrint("[WEBRTC SIGNAL ERROR] Error creating offer: $e\n$stack");
    }
  }

  Future<void> _handleOffer(Map<String, dynamic> sdpMap) async {
    try {
      if (_peerConnection == null) return;
      final description = RTCSessionDescription(sdpMap['sdp'], sdpMap['type']);
      await _peerConnection!.setRemoteDescription(description);
      _hasRemoteDescription = true;
      debugPrint("[WEBRTC SIGNAL] Set remote description (offer) successfully");

      // Flush all pending ICE candidates
      for (var cand in _pendingIceCandidates) {
        try {
          await _peerConnection!.addCandidate(cand);
        } catch (e) {
          debugPrint("[WEBRTC ICE ERROR] Flushing candidate error: $e");
        }
      }
      _pendingIceCandidates.clear();

      final answer = await _peerConnection!.createAnswer({
        'offerToReceiveVideo': widget.isVideoCall,
        'offerToReceiveAudio': true,
      });
      await _peerConnection!.setLocalDescription(answer);

      widget.socket?.emit('webrtcAnswer', {
        'conversationId': widget.conversationId,
        'sdp': answer.toMap(),
        'senderId': widget.currentUserId,
      });
      debugPrint("[WEBRTC SIGNAL] Answer created and emitted by User ${widget.currentUserId}");

      if (mounted) {
        setState(() {
          _isCallConnected = true;
          _callStatus = 'Connected';
        });
        _startCallTimerIfNeeded();
        _startStatsLogging();
        _applyAudioRouting();
      }
    } catch (e, stack) {
      debugPrint("[WEBRTC SIGNAL ERROR] Error handling offer: $e\n$stack");
    }
  }

  Future<void> _handleAnswer(Map<String, dynamic> sdpMap) async {
    try {
      if (_peerConnection == null) return;
      final description = RTCSessionDescription(sdpMap['sdp'], sdpMap['type']);
      await _peerConnection!.setRemoteDescription(description);
      _hasRemoteDescription = true;
      debugPrint("[WEBRTC SIGNAL] Set remote description (answer) successfully");

      for (var cand in _pendingIceCandidates) {
        try {
          await _peerConnection!.addCandidate(cand);
        } catch (e) {
          debugPrint("[WEBRTC ICE ERROR] Flushing candidate error: $e");
        }
      }
      _pendingIceCandidates.clear();

      if (mounted) {
        setState(() {
          _isCallConnected = true;
          _callStatus = 'Connected';
        });
        _startCallTimerIfNeeded();
        _startStatsLogging();
        _applyAudioRouting();
      }
    } catch (e, stack) {
      debugPrint("[WEBRTC SIGNAL ERROR] Error handling answer: $e\n$stack");
    }
  }

  void _startCallTimerIfNeeded() {
    if (_callTimer != null) return;
    _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() => _callDurationSeconds++);
      }
    });
  }

  // Realtime getStats logging every 2 seconds to measure live media throughput
  void _startStatsLogging() {
    if (_statsTimer != null) return;
    _statsTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (_peerConnection == null || !_isCallConnected) return;
      try {
        final stats = await _peerConnection!.getStats();
        num audioBytesSent = 0;
        num audioBytesReceived = 0;
        num videoBytesSent = 0;
        num videoBytesReceived = 0;
        num packetsLost = 0;
        num framesDecoded = 0;
        num framesSent = 0;

        for (var report in stats) {
          final values = report.values;
          if (report.type == 'outbound-rtp') {
            if (values['kind'] == 'audio' || values['mediaType'] == 'audio') {
              audioBytesSent += (values['bytesSent'] as num? ?? 0);
            } else if (values['kind'] == 'video' || values['mediaType'] == 'video') {
              videoBytesSent += (values['bytesSent'] as num? ?? 0);
              framesSent += (values['framesSent'] as num? ?? 0);
            }
          } else if (report.type == 'inbound-rtp') {
            if (values['kind'] == 'audio' || values['mediaType'] == 'audio') {
              audioBytesReceived += (values['bytesReceived'] as num? ?? 0);
              packetsLost += (values['packetsLost'] as num? ?? 0);
            } else if (values['kind'] == 'video' || values['mediaType'] == 'video') {
              videoBytesReceived += (values['bytesReceived'] as num? ?? 0);
              framesDecoded += (values['framesDecoded'] as num? ?? 0);
            }
          }
        }

        debugPrint(
          '[WEBRTC STATS @ ${_callDurationSeconds}s] User: ${widget.currentUserId} | '
          'Audio: Sent=${audioBytesSent}B, Recv=${audioBytesReceived}B, Lost=$packetsLost | '
          'Video: Sent=${videoBytesSent}B, Recv=${videoBytesReceived}B, FramesDecoded=$framesDecoded, FramesSent=$framesSent',
        );
      } catch (e) {
        debugPrint("[WEBRTC STATS ERROR] Error getting stats: $e");
      }
    });
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _toggleMute() {
    if (_localStream != null && _localStream!.getAudioTracks().isNotEmpty) {
      final track = _localStream!.getAudioTracks().first;
      setState(() {
        _isMuted = !_isMuted;
        track.enabled = !_isMuted;
      });
      debugPrint("[WEBRTC] Toggled microphone: isMuted=$_isMuted");
    }
  }

  void _toggleCamera() {
    if (_localStream != null && _localStream!.getVideoTracks().isNotEmpty) {
      final track = _localStream!.getVideoTracks().first;
      setState(() {
        _isCameraOff = !_isCameraOff;
        track.enabled = !_isCameraOff;
      });
      debugPrint("[WEBRTC] Toggled camera: isCameraOff=$_isCameraOff");
    }
  }

  void _switchCamera() async {
    if (_localStream != null && _localStream!.getVideoTracks().isNotEmpty) {
      final track = _localStream!.getVideoTracks().first;
      await Helper.switchCamera(track);
      setState(() {
        _isFrontCamera = !_isFrontCamera;
      });
      debugPrint("[WEBRTC] Switched camera: isFront=$_isFrontCamera");
    }
  }

  void _toggleSpeaker() {
    setState(() {
      _isSpeakerOn = !_isSpeakerOn;
    });
    _applyAudioRouting();
  }

  void _endCall() {
    widget.socket?.emit('endCall', {
      'conversationId': widget.conversationId,
      'duration': _callDurationSeconds,
      'senderId': widget.currentUserId,
    });
    _endCallLocal();
  }

  void _endCallLocal() {
    debugPrint("[WEBRTC] Cleaning up and ending call...");
    _callTimer?.cancel();
    _callTimer = null;

    _statsTimer?.cancel();
    _statsTimer = null;

    _localStream?.getTracks().forEach((track) {
      track.stop();
    });
    _localStream?.dispose();
    _localStream = null;

    _remoteStream?.getTracks().forEach((track) {
      track.stop();
    });
    _remoteStream?.dispose();
    _remoteStream = null;

    _peerConnection?.close();
    _peerConnection?.dispose();
    _peerConnection = null;

    _localRenderer.dispose();
    _remoteRenderer.dispose();

    if (!kIsWeb) {
      try {
        Helper.setSpeakerphoneOn(false);
      } catch (_) {}
    }

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _callTimer?.cancel();
    _statsTimer?.cancel();
    widget.socket?.off('callAccepted');
    widget.socket?.off('callRejected');
    widget.socket?.off('callCancelled');
    widget.socket?.off('callMissed');
    widget.socket?.off('webrtcOffer');
    widget.socket?.off('webrtcAnswer');
    widget.socket?.off('webrtcIceCandidate');
    widget.socket?.off('callEnded');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_permissionError != null) {
      return Scaffold(
        backgroundColor: const Color(0xFF111B21),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_rounded, size: 64, color: Colors.redAccent),
                const SizedBox(height: 20),
                Text(
                  _permissionError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryTeal,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  child: const Text('Go Back'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Remote Video View or Avatar Placeholder
            Positioned.fill(
              child: (widget.isVideoCall && _remoteRenderer.srcObject != null)
                  ? RTCVideoView(
                      _remoteRenderer,
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    )
                  : Container(
                      color: const Color(0xFF111B21),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircleAvatar(
                            radius: 56,
                            backgroundColor: AppTheme.primaryTeal.withValues(alpha: 0.2),
                            child: Text(
                              widget.peerName.isNotEmpty ? widget.peerName[0].toUpperCase() : 'U',
                              style: const TextStyle(
                                fontSize: 44,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryTeal,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            widget.peerName,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _isCallConnected ? _formatDuration(_callDurationSeconds) : _callStatus,
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.white.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),

            // Local Video Floating Preview (For Video Call)
            if (widget.isVideoCall && _localRenderer.srcObject != null && !_isCameraOff)
              Positioned(
                top: 20,
                right: 20,
                width: 110,
                height: 160,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white30, width: 1.5),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: RTCVideoView(
                      _localRenderer,
                      mirror: _isFrontCamera,
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    ),
                  ),
                ),
              ),

            // Header bar
            Positioned(
              top: 20,
              left: 20,
              child: Row(
                children: [
                  Icon(
                    widget.isVideoCall ? Icons.videocam_rounded : Icons.phone_rounded,
                    color: AppTheme.primaryTeal,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.isVideoCall ? "Duo Video Call" : "Duo Audio Call",
                    style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),

            // Controls Bar
            Positioned(
              bottom: 40,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(36),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Mute Microphone
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: _isMuted ? Colors.white : Colors.white24,
                      child: IconButton(
                        icon: Icon(
                          _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                          color: _isMuted ? Colors.black : Colors.white,
                        ),
                        onPressed: _toggleMute,
                      ),
                    ),

                    // Camera On / Off (Video Call Only)
                    if (widget.isVideoCall)
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: _isCameraOff ? Colors.white : Colors.white24,
                        child: IconButton(
                          icon: Icon(
                            _isCameraOff ? Icons.videocam_off_rounded : Icons.videocam_rounded,
                            color: _isCameraOff ? Colors.black : Colors.white,
                          ),
                          onPressed: _toggleCamera,
                        ),
                      ),

                    // Switch Camera (Video Call Only)
                    if (widget.isVideoCall)
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: Colors.white24,
                        child: IconButton(
                          icon: const Icon(
                            Icons.cameraswitch_rounded,
                            color: Colors.white,
                          ),
                          onPressed: _switchCamera,
                        ),
                      ),

                    // Speaker Output Toggle
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: _isSpeakerOn ? AppTheme.primaryTeal : Colors.white24,
                      child: IconButton(
                        icon: Icon(
                          _isSpeakerOn ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                          color: Colors.white,
                        ),
                        onPressed: _toggleSpeaker,
                      ),
                    ),

                    // End Call
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: Colors.redAccent,
                      child: IconButton(
                        icon: const Icon(
                          Icons.call_end_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                        onPressed: _endCall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
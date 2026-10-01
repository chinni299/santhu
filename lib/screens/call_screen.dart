import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
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
  String _callStatus = 'Connecting...';

  // Call duration timer
  Timer? _callTimer;
  int _callDurationSeconds = 0;

  bool _iceRestartAttempted = false;
  final List<RTCIceCandidate> _pendingIceCandidates = [];

  @override
  void initState() {
    super.initState();
    _callStatus = widget.isCaller ? 'Calling...' : 'Connecting call...';
    _isCameraOff = !widget.isVideoCall;
    _initCall();
  }

  Future<void> _requestPermissions() async {
    if (!kIsWeb) {
      await [
        Permission.camera,
        Permission.microphone,
      ].request();
    }
  }

  Future<void> _initCall() async {
    try {
      await _requestPermissions();

      await _localRenderer.initialize();
      await _remoteRenderer.initialize();

      // Create Local Media Stream with robust fallback
      final mediaConstraints = <String, dynamic>{
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
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
        _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      } catch (e1) {
        debugPrint("[CALL] Primary getUserMedia failed ($e1). Retrying fallback constraints...");
        try {
          _localStream = await navigator.mediaDevices.getUserMedia({
            'audio': true,
            'video': widget.isVideoCall ? true : false,
          });
        } catch (e2) {
          debugPrint("[CALL] Fallback to audio-only stream: $e2");
          try {
            _localStream = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': false});
            _isCameraOff = true;
          } catch (e3) {
            debugPrint("[CALL] Camera/Mic unavailable ($e3)");
            _isCameraOff = true;
            _isMuted = true;
            if (mounted) {
              setState(() => _callStatus = 'Microphone/Camera unavailable');
            }
          }
        }
      }

      if (_localStream != null) {
        _localRenderer.srcObject = _localStream;
        for (var track in _localStream!.getAudioTracks()) {
          track.enabled = true;
        }
      }

      // WebRTC Peer Connection Configuration
      final configuration = <String, dynamic>{
        'iceServers': [
          {
            'urls': ['stun:stun.l.google.com:19302', 'stun:stun1.l.google.com:19302', 'stun:stun2.l.google.com:19302'],
          },
          {
            'urls': 'stun:openrelay.metered.ca:80',
          },
          {
            'urls': 'turn:openrelay.metered.ca:80',
            'username': 'openrelayproject',
            'credential': 'openrelayproject',
          },
          {
            'urls': 'turn:openrelay.metered.ca:443',
            'username': 'openrelayproject',
            'credential': 'openrelayproject',
          },
          {
            'urls': 'turn:openrelay.metered.ca:443?transport=tcp',
            'username': 'openrelayproject',
            'credential': 'openrelayproject',
          },
        ],
        'iceTransportPolicy': 'all',
        'sdpSemantics': 'unified-plan',
      };

      _peerConnection = await createPeerConnection(configuration);

      // Add local stream tracks to Peer Connection
      if (_localStream != null) {
        for (var track in _localStream!.getTracks()) {
          await _peerConnection?.addTrack(track, _localStream!);
        }
      }

      // Handle Remote Stream Tracks (Unified Plan)
      _peerConnection?.onTrack = (RTCTrackEvent event) async {
        debugPrint('[WebRTC] onTrack: kind=${event.track.kind}, id=${event.track.id}, streams=${event.streams.length}');
        event.track.enabled = true;

        if (event.streams.isNotEmpty) {
          _remoteStream = event.streams[0];
        } else {
          _remoteStream ??= await createLocalMediaStream('remote_stream_${DateTime.now().millisecondsSinceEpoch}');
          _remoteStream!.addTrack(event.track);
        }

        // Enable all remote audio & video tracks
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
          _applySpeakerphone();
        }
      };

      // Handle Remote Stream (Plan-B / Legacy fallback)
      _peerConnection?.onAddStream = (MediaStream stream) {
        debugPrint('[WebRTC] onAddStream: id=${stream.id}');
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
          _applySpeakerphone();
        }
      };

      // Handle ICE Candidates
      _peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
        if (candidate.candidate != null && candidate.candidate!.isNotEmpty) {
          widget.socket?.emit('webrtcIceCandidate', {
            'conversationId': widget.conversationId,
            'candidate': candidate.toMap(),
            'senderId': widget.currentUserId,
          });
        }
      };

      _peerConnection?.onIceConnectionState = (RTCIceConnectionState state) {
        debugPrint("[WebRTC] ICE Connection State: $state");
        if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
            state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
          _iceRestartAttempted = false;
          if (mounted) {
            setState(() {
              _isCallConnected = true;
              _callStatus = 'Connected';
            });
            _startCallTimerIfNeeded();
            _applySpeakerphone();
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
        widget.socket?.emit('callUser', {
          'conversationId': widget.conversationId,
          'isVideoCall': widget.isVideoCall,
          'callerId': widget.currentUserId,
          'senderId': widget.currentUserId,
        });
      } else {
        widget.socket?.emit('acceptCall', {
          'conversationId': widget.conversationId,
          'userId': widget.currentUserId,
          'senderId': widget.currentUserId,
        });
      }
    } catch (e) {
      debugPrint("[WebRTC] Error initializing WebRTC: $e");
      if (mounted) {
        setState(() => _callStatus = 'Failed to initialize call');
      }
    }
  }

  void _applySpeakerphone() {
    if (!kIsWeb) {
      Helper.setSpeakerphoneOn(_isSpeakerOn);
    }
  }

  void _setupSocketListeners() {
    widget.socket?.on('callAccepted', (data) async {
      if (mounted && widget.isCaller) {
        setState(() => _callStatus = 'Connecting...');
        await _createOffer();
      }
    });

    widget.socket?.on('callRejected', (data) {
      if (mounted) {
        setState(() => _callStatus = 'Call Declined');
        Future.delayed(const Duration(seconds: 1), _endCallLocal);
      }
    });

    widget.socket?.on('callCancelled', (data) {
      if (mounted) {
        setState(() => _callStatus = 'Call Cancelled');
        Future.delayed(const Duration(seconds: 1), _endCallLocal);
      }
    });

    widget.socket?.on('callMissed', (data) {
      if (mounted) {
        setState(() => _callStatus = 'No Answer');
        Future.delayed(const Duration(seconds: 1), _endCallLocal);
      }
    });

    widget.socket?.on('webrtcOffer', (data) async {
      if (mounted && !widget.isCaller && data != null && data['sdp'] != null) {
        await _handleOffer(Map<String, dynamic>.from(data['sdp']));
      }
    });

    widget.socket?.on('webrtcAnswer', (data) async {
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

        if (_peerConnection != null) {
          final desc = await _peerConnection!.getRemoteDescription();
          if (desc != null) {
            await _peerConnection!.addCandidate(candidate);
          } else {
            _pendingIceCandidates.add(candidate);
          }
        }
      }
    });

    widget.socket?.on('callEnded', (data) {
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
      }
    } catch (e) {
      debugPrint("[WebRTC] Error attempting ICE restart: $e");
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
      debugPrint("[WebRTC] Offer sent with senderId ${widget.currentUserId}");
    } catch (e) {
      debugPrint("[WebRTC] Error creating WebRTC offer: $e");
    }
  }

  Future<void> _handleOffer(Map<String, dynamic> sdpMap) async {
    try {
      if (_peerConnection == null) return;
      final description = RTCSessionDescription(sdpMap['sdp'], sdpMap['type']);
      await _peerConnection!.setRemoteDescription(description);

      for (var cand in _pendingIceCandidates) {
        await _peerConnection!.addCandidate(cand);
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
      debugPrint("[WebRTC] Answer sent with senderId ${widget.currentUserId}");

      if (mounted) {
        setState(() {
          _isCallConnected = true;
          _callStatus = 'Connected';
        });
        _startCallTimerIfNeeded();
        _applySpeakerphone();
      }
    } catch (e) {
      debugPrint("[WebRTC] Error handling WebRTC offer: $e");
    }
  }

  Future<void> _handleAnswer(Map<String, dynamic> sdpMap) async {
    try {
      if (_peerConnection == null) return;
      final description = RTCSessionDescription(sdpMap['sdp'], sdpMap['type']);
      await _peerConnection!.setRemoteDescription(description);

      for (var cand in _pendingIceCandidates) {
        await _peerConnection!.addCandidate(cand);
      }
      _pendingIceCandidates.clear();

      if (mounted) {
        setState(() {
          _isCallConnected = true;
          _callStatus = 'Connected';
        });
        _startCallTimerIfNeeded();
        _applySpeakerphone();
      }
    } catch (e) {
      debugPrint("[WebRTC] Error handling WebRTC answer: $e");
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
    }
  }

  void _toggleCamera() {
    if (_localStream != null && _localStream!.getVideoTracks().isNotEmpty) {
      final track = _localStream!.getVideoTracks().first;
      setState(() {
        _isCameraOff = !_isCameraOff;
        track.enabled = !_isCameraOff;
      });
    }
  }

  void _switchCamera() async {
    if (_localStream != null && _localStream!.getVideoTracks().isNotEmpty) {
      final track = _localStream!.getVideoTracks().first;
      await Helper.switchCamera(track);
      setState(() {
        _isFrontCamera = !_isFrontCamera;
      });
    }
  }

  void _toggleSpeaker() {
    setState(() {
      _isSpeakerOn = !_isSpeakerOn;
    });
    _applySpeakerphone();
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
    _callTimer?.cancel();
    _callTimer = null;

    _localStream?.getTracks().forEach((track) => track.stop());
    _localStream?.dispose();
    _localStream = null;

    _remoteStream?.getTracks().forEach((track) => track.stop());
    _remoteStream?.dispose();
    _remoteStream = null;

    _peerConnection?.close();
    _peerConnection?.dispose();

    _localRenderer.dispose();
    _remoteRenderer.dispose();

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _callTimer?.cancel();
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
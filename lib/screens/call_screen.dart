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

  bool _isMuted = false;
  bool _isCameraOff = false;
  bool _isFrontCamera = true;
  bool _isSpeakerOn = true;
  bool _isCallConnected = false;
  String _callStatus = 'Connecting...';

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

      // Create Local Media Stream
      final mediaConstraints = {
        'audio': true,
        'video': widget.isVideoCall
            ? {
                'facingMode': 'user',
                'mandatory': {
                  'minWidth': '640',
                  'minHeight': '480',
                  'minFrameRate': '30',
                },
              }
            : false,
      };

      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      _localRenderer.srcObject = _localStream;

      // Setup WebRTC Peer Connection
      final configuration = <String, dynamic>{
        'iceServers': [
          {'urls': ['stun:stun.l.google.com:19302', 'stun:stun1.l.google.com:19302']}
        ]
      };

      _peerConnection = await createPeerConnection(configuration);

      // Add local stream tracks to Peer Connection
      _localStream?.getTracks().forEach((track) {
        _peerConnection?.addTrack(track, _localStream!);
      });

      // Handle Remote Stream Track
      _peerConnection?.onTrack = (RTCTrackEvent event) {
        if (event.streams.isNotEmpty) {
          setState(() {
            _remoteRenderer.srcObject = event.streams[0];
            _isCallConnected = true;
            _callStatus = 'Connected';
          });
        }
      };

      // Handle ICE Candidates
      _peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
        if (candidate.candidate != null) {
          widget.socket?.emit('webrtcIceCandidate', {
            'conversationId': widget.conversationId,
            'candidate': candidate.toMap(),
          });
        }
      };

      _peerConnection?.onIceConnectionState = (RTCIceConnectionState state) {
        debugPrint("WebRTC ICE State: $state");
        if (state == RTCIceConnectionState.RTCIceConnectionStateConnected) {
          setState(() {
            _isCallConnected = true;
            _callStatus = 'Connected';
          });
        } else if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected ||
            state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
          setState(() {
            _callStatus = 'Connection error';
          });
        }
      };

      _setupSocketListeners();

      if (widget.isCaller) {
        // Emit callUser signal
        widget.socket?.emit('callUser', {
          'conversationId': widget.conversationId,
          'isVideoCall': widget.isVideoCall,
        });
      } else {
        // Callee accepts immediately
        widget.socket?.emit('acceptCall', {
          'conversationId': widget.conversationId,
        });
      }
    } catch (e) {
      debugPrint("Error initializing WebRTC: $e");
      if (mounted) {
        setState(() {
          _callStatus = 'Failed to access camera/mic';
        });
      }
    }
  }

  void _setupSocketListeners() {
    widget.socket?.on('callAccepted', (data) async {
      if (mounted && widget.isCaller) {
        setState(() {
          _callStatus = 'Ringing...';
        });
        await _createOffer();
      }
    });

    widget.socket?.on('callRejected', (data) {
      if (mounted) {
        setState(() {
          _callStatus = 'Call Declined';
        });
        Future.delayed(const Duration(seconds: 1), _endCallLocal);
      }
    });

    widget.socket?.on('callCancelled', (data) {
      if (mounted) {
        setState(() {
          _callStatus = 'Call Cancelled';
        });
        Future.delayed(const Duration(seconds: 1), _endCallLocal);
      }
    });

    widget.socket?.on('webrtcOffer', (data) async {
      if (mounted && !widget.isCaller && data != null && data['sdp'] != null) {
        await _handleOffer(data['sdp']);
      }
    });

    widget.socket?.on('webrtcAnswer', (data) async {
      if (mounted && widget.isCaller && data != null && data['sdp'] != null) {
        await _handleAnswer(data['sdp']);
      }
    });

    widget.socket?.on('webrtcIceCandidate', (data) async {
      if (mounted && data != null && data['candidate'] != null) {
        final candidateData = data['candidate'];
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
        setState(() {
          _callStatus = 'Call Ended';
        });
        Future.delayed(const Duration(milliseconds: 500), _endCallLocal);
      }
    });
  }

  Future<void> _createOffer() async {
    try {
      if (_peerConnection == null) return;
      final offer = await _peerConnection!.createOffer({'offerToReceiveVideo': widget.isVideoCall ? 1 : 0, 'offerToReceiveAudio': 1});
      await _peerConnection!.setLocalDescription(offer);

      widget.socket?.emit('webrtcOffer', {
        'conversationId': widget.conversationId,
        'sdp': offer.toMap(),
      });
    } catch (e) {
      debugPrint("Error creating WebRTC offer: $e");
    }
  }

  Future<void> _handleOffer(Map<String, dynamic> sdpMap) async {
    try {
      if (_peerConnection == null) return;
      final description = RTCSessionDescription(sdpMap['sdp'], sdpMap['type']);
      await _peerConnection!.setRemoteDescription(description);

      // Add any pending ICE candidates
      for (var cand in _pendingIceCandidates) {
        await _peerConnection!.addCandidate(cand);
      }
      _pendingIceCandidates.clear();

      final answer = await _peerConnection!.createAnswer({'offerToReceiveVideo': widget.isVideoCall ? 1 : 0, 'offerToReceiveAudio': 1});
      await _peerConnection!.setLocalDescription(answer);

      widget.socket?.emit('webrtcAnswer', {
        'conversationId': widget.conversationId,
        'sdp': answer.toMap(),
      });

      setState(() {
        _isCallConnected = true;
        _callStatus = 'Connected';
      });
    } catch (e) {
      debugPrint("Error handling WebRTC offer: $e");
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

      setState(() {
        _isCallConnected = true;
        _callStatus = 'Connected';
      });
    } catch (e) {
      debugPrint("Error handling WebRTC answer: $e");
    }
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

  Future<void> _switchCamera() async {
    if (_localStream != null && _localStream!.getVideoTracks().isNotEmpty) {
      final videoTrack = _localStream!.getVideoTracks().first;
      await Helper.switchCamera(videoTrack);
      setState(() {
        _isFrontCamera = !_isFrontCamera;
      });
    }
  }

  void _toggleSpeaker() {
    if (_localStream != null && _localStream!.getAudioTracks().isNotEmpty) {
      final track = _localStream!.getAudioTracks().first;
      setState(() {
        _isSpeakerOn = !_isSpeakerOn;
        track.enableSpeakerphone(_isSpeakerOn);
      });
    }
  }

  void _endCall() {
    if (widget.isCaller && !_isCallConnected) {
      widget.socket?.emit('cancelCall', {'conversationId': widget.conversationId});
    } else {
      widget.socket?.emit('endCall', {'conversationId': widget.conversationId});
    }
    _endCallLocal();
  }

  void _endCallLocal() {
    _localStream?.getTracks().forEach((track) => track.stop());
    _localStream?.dispose();
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
    widget.socket?.off('callAccepted');
    widget.socket?.off('callRejected');
    widget.socket?.off('callCancelled');
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
            // Remote Video or Avatar
            Positioned.fill(
              child: (widget.isVideoCall && _isCallConnected && _remoteRenderer.srcObject != null)
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
                            _callStatus,
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

            // Status Bar Overlay Header
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

            // In-Call Action Control Bar
            Positioned(
              bottom: 40,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(36),
                  border: Border.all(color: Colors.white10),
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

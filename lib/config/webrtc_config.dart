/// WebRTC Network Configuration (STUN / TURN ICE Servers)
///
/// To configure custom TURN servers (e.g. from Metered.ca, Twilio, or self-hosted coturn):
/// Set the [turnUsername] and [turnCredential] or update the servers list below.
class WebRtcConfig {
  // Public OpenRelay / Google STUN & TURN servers by default
  static const String turnUsername = 'openrelayproject';
  static const String turnCredential = 'openrelayproject';

  static Map<String, dynamic> get peerConnectionConfiguration => {
        'iceServers': [
          // Google Public STUN Servers
          {
            'urls': [
              'stun:stun.l.google.com:19302',
              'stun:stun1.l.google.com:19302',
              'stun:stun2.l.google.com:19302',
              'stun:stun3.l.google.com:19302',
              'stun:stun4.l.google.com:19302',
            ],
          },
          // OpenRelay STUN Server
          {
            'urls': 'stun:openrelay.metered.ca:80',
          },
          // OpenRelay TURN UDP (Port 80)
          {
            'urls': 'turn:openrelay.metered.ca:80',
            'username': turnUsername,
            'credential': turnCredential,
          },
          // OpenRelay TURN UDP (Port 443)
          {
            'urls': 'turn:openrelay.metered.ca:443',
            'username': turnUsername,
            'credential': turnCredential,
          },
          // OpenRelay TURN TCP (Port 443 - for strict corporate firewalls & mobile NATs)
          {
            'urls': 'turn:openrelay.metered.ca:443?transport=tcp',
            'username': turnUsername,
            'credential': turnCredential,
          },
        ],
        'iceTransportPolicy': 'all',
        'sdpSemantics': 'unified-plan',
      };
}

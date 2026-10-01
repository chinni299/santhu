import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

/// Call History — every audio/video call between the two of you, with
/// direction, duration and outcome (answered / missed / declined / cancelled).
class CallHistoryScreen extends StatefulWidget {
  final int conversationId;
  final int currentUserId;
  final String peerName;

  const CallHistoryScreen({
    super.key,
    required this.conversationId,
    required this.currentUserId,
    required this.peerName,
  });

  @override
  State<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends State<CallHistoryScreen> {
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _calls = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final headers = await AuthService.getAuthHeadersForUser(widget.currentUserId);
      final res = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/messages/calls/${widget.conversationId}'),
        headers: headers,
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        final List items = data['data'] ?? [];
        if (!mounted) return;
        setState(() {
          _calls = items.cast<Map<String, dynamic>>();
          _isLoading = false;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _error = 'Could not load call history';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load call history';
        _isLoading = false;
      });
    }
  }

  String _formatDateTime(String? raw) {
    if (raw == null) return '';
    try {
      final d = DateTime.parse(raw).toLocal();
      final now = DateTime.now();
      final hour = d.hour == 0 ? 12 : (d.hour > 12 ? d.hour - 12 : d.hour);
      final minute = d.minute.toString().padLeft(2, '0');
      final period = d.hour >= 12 ? 'PM' : 'AM';
      final timeStr = '$hour:$minute $period';
      if (d.year == now.year && d.month == now.month && d.day == now.day) {
        return 'Today, $timeStr';
      }
      if (d.year == now.year && d.month == now.month && d.day == now.day - 1) {
        return 'Yesterday, $timeStr';
      }
      return '${d.day}/${d.month}/${d.year}, $timeStr';
    } catch (_) {
      return '';
    }
  }

  String _formatDuration(dynamic seconds) {
    final s = int.tryParse(seconds?.toString() ?? '0') ?? 0;
    if (s <= 0) return '';
    final m = s ~/ 60;
    final sec = s % 60;
    if (m == 0) return '${sec}s';
    return '${m}m ${sec}s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.primaryTeal,
        foregroundColor: Colors.white,
        title: const Text('Call History', style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryTeal))
          : _error != null
              ? Center(child: Text(_error!))
              : _calls.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.call_outlined, size: 56, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          Text('No calls yet', style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: _calls.length,
                      separatorBuilder: (context, index) => const Divider(height: 1, indent: 72),
                      itemBuilder: (context, i) {
                        final call = _calls[i];
                        final bool isOutgoing = int.tryParse(call['caller_id'].toString()) == widget.currentUserId;
                        final bool isVideo = call['is_video_call'] == true;
                        final String status = call['status']?.toString() ?? '';
                        final bool isMissed = status == 'missed' || (status == 'declined' && !isOutgoing);
                        final duration = _formatDuration(call['duration_seconds']);

                        IconData directionIcon;
                        Color directionColor;
                        if (isMissed) {
                          directionIcon = Icons.call_missed_rounded;
                          directionColor = Colors.redAccent;
                        } else if (isOutgoing) {
                          directionIcon = Icons.call_made_rounded;
                          directionColor = AppTheme.primaryTeal;
                        } else {
                          directionIcon = Icons.call_received_rounded;
                          directionColor = AppTheme.primaryTeal;
                        }

                        String statusLabel;
                        switch (status) {
                          case 'missed':
                            statusLabel = 'Missed';
                            break;
                          case 'declined':
                            statusLabel = isOutgoing ? 'Declined' : 'You declined';
                            break;
                          case 'cancelled':
                            statusLabel = isOutgoing ? 'Cancelled' : 'Missed';
                            break;
                          case 'answered':
                            statusLabel = duration.isNotEmpty ? duration : 'Answered';
                            break;
                          default:
                            statusLabel = status;
                        }

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: (isMissed ? Colors.redAccent : AppTheme.primaryTeal).withValues(alpha: 0.12),
                            child: Icon(isVideo ? Icons.videocam_rounded : Icons.phone_rounded, color: isMissed ? Colors.redAccent : AppTheme.primaryTeal),
                          ),
                          title: Text(
                            isOutgoing ? 'You called ${widget.peerName}' : '${widget.peerName} called you',
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                          ),
                          subtitle: Row(
                            children: [
                              Icon(directionIcon, size: 14, color: directionColor),
                              const SizedBox(width: 4),
                              Text(statusLabel, style: TextStyle(fontSize: 12, color: isMissed ? Colors.redAccent : Colors.grey.shade600, fontWeight: FontWeight.w700)),
                            ],
                          ),
                          trailing: Text(
                            _formatDateTime(call['started_at']?.toString()),
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w600),
                          ),
                        );
                      },
                    ),
    );
  }
}
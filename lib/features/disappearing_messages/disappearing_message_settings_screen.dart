import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../../theme/app_theme.dart';
import 'disappearing_message_duration.dart';
import 'disappearing_message_service.dart';

class DisappearingMessageSettingsScreen extends StatefulWidget {
  final int conversationId;
  final int currentUserId;
  final io.Socket? socket;
  final DisappearingDuration currentDuration;

  const DisappearingMessageSettingsScreen({
    super.key,
    required this.conversationId,
    required this.currentUserId,
    required this.socket,
    required this.currentDuration,
  });

  @override
  State<DisappearingMessageSettingsScreen> createState() => _DisappearingMessageSettingsScreenState();
}

class _DisappearingMessageSettingsScreenState extends State<DisappearingMessageSettingsScreen> {
  late DisappearingDuration _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.currentDuration;
  }

  void _onSelect(DisappearingDuration duration) async {
    setState(() => _selected = duration);
    await DisappearingMessageService.setTimer(
      socket: widget.socket,
      conversationId: widget.conversationId,
      duration: duration,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Disappearing messages set to ${duration.label}')),
      );
      Navigator.pop(context, duration);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Disappearing Messages', style: TextStyle(fontWeight: FontWeight.w900)),
        backgroundColor: AppTheme.primaryTeal,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Text(
              'For more privacy, new messages will disappear from this chat for everyone after the selected duration.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ),
          const Divider(),
          ...DisappearingDuration.values.map((d) {
            return RadioListTile<DisappearingDuration>(
              value: d,
              groupValue: _selected,
              title: Text(d.label, style: const TextStyle(fontWeight: FontWeight.w700)),
              activeColor: AppTheme.primaryTeal,
              onChanged: (val) {
                if (val != null) _onSelect(val);
              },
            );
          }),
        ],
      ),
    );
  }
}

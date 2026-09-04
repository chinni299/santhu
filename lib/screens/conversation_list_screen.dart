import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'chat_screen.dart';
import 'login_screen.dart';

class ConversationListScreen extends StatefulWidget {
  final int currentUserId;

  const ConversationListScreen({
    super.key,
    required this.currentUserId,
  });

  @override
  State<ConversationListScreen> createState() => _ConversationListScreenState();
}

class _ConversationListScreenState extends State<ConversationListScreen> {
  static const String baseUrl = 'http://192.168.0.120:5000';

  List<Map<String, dynamic>> conversations = [];
  bool isLoading = true;
  late io.Socket socket;

  final Map<int, bool> onlineStatusMap = {};

  @override
  void initState() {
    super.initState();
    _initSocket();
    fetchConversations();
  }

  void _initSocket() {
    socket = io.io(
      baseUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .build(),
    );

    socket.onConnect((_) {
      debugPrint("ConversationListSocket connected: ${socket.id}");
      _joinRooms();
    });

    socket.on('newMessage', (data) {
      if (data == null || !mounted) return;

      final convId = data['conversation_id'] ?? data['conversationId'];
      final msg = data['message'] ?? '';
      final rawTime = data['created_at'] != null ? data['created_at'].toString() : '';

      setState(() {
        for (var c in conversations) {
          if (c['conversation_id'].toString() == convId.toString()) {
            c['last_message'] = msg;
            c['last_message_time'] = rawTime;
          }
        }
      });
    });

    socket.on('messageEdited', (data) {
      if (data == null || !mounted) return;
      final convId = data['conversation_id'] ?? data['conversationId'];
      final msg = data['message'] ?? '';

      setState(() {
        for (var c in conversations) {
          if (c['conversation_id'].toString() == convId.toString()) {
            c['last_message'] = msg;
          }
        }
      });
    });

    socket.on('messageDeleted', (data) {
      if (data == null || !mounted) return;
      final convId = data['conversationId'] ?? data['conversation_id'];

      setState(() {
        for (var c in conversations) {
          if (c['conversation_id'].toString() == convId.toString()) {
            c['last_message'] = "This message was deleted";
          }
        }
      });
    });

    socket.on('unreadCountUpdate', (data) {
      if (data == null || !mounted) return;

      final convId = data['conversationId'];
      final count = data['unreadCount'];
      final senderId = data['senderId'];
      final userId = data['userId'];

      if (convId == null) return;

      setState(() {
        for (var c in conversations) {
          if (c['conversation_id'].toString() == convId.toString()) {
            if (userId != null && int.parse(userId.toString()) == widget.currentUserId) {
              c['unread_count'] = 0;
            } else if (senderId != null && int.parse(senderId.toString()) != widget.currentUserId && count != null) {
              c['unread_count'] = int.parse(count.toString());
            }
          }
        }
      });
    });

    socket.on('userOnline', (data) {
      if (data == null || !mounted) return;
      final userId = data['userId'] ?? data['user_id'];
      if (userId != null) {
        final uid = int.tryParse(userId.toString());
        if (uid != null && uid != widget.currentUserId) {
          setState(() {
            onlineStatusMap[uid] = true;
          });
        }
      }
    });

    socket.on('userOffline', (data) {
      if (data == null || !mounted) return;
      final userId = data['userId'] ?? data['user_id'];
      if (userId != null) {
        final uid = int.tryParse(userId.toString());
        if (uid != null && uid != widget.currentUserId) {
          setState(() {
            onlineStatusMap[uid] = false;
          });
        }
      }
    });

    socket.connect();
  }

  void _joinRooms() {
    socket.emit('joinUserRoom', {
      'userId': widget.currentUserId,
    });
  }

  Future<void> fetchConversations() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/messages/conversations/${widget.currentUserId}'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          final List fetched = data['data'];
          if (!mounted) return;

          setState(() {
            conversations = List<Map<String, dynamic>>.from(fetched);
            isLoading = false;
          });

          if (socket.connected) {
            _joinRooms();
          }
          return;
        }
      }
    } catch (e) {
      debugPrint("Error fetching conversations: $e");
    }

    if (mounted) {
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    socket.off('newMessage');
    socket.off('unreadCountUpdate');
    socket.off('userOnline');
    socket.off('userOffline');
    socket.off('messageEdited');
    socket.off('messageDeleted');
    socket.disconnect();
    socket.dispose();
    super.dispose();
  }

  String _formatTime(String rawTime) {
    if (rawTime.isEmpty) return '';
    try {
      final dateTime = DateTime.parse(rawTime).toLocal();
      final hour = dateTime.hour == 0
          ? 12
          : (dateTime.hour > 12
              ? dateTime.hour - 12
              : dateTime.hour);
      final minute = dateTime.minute.toString().padLeft(2, '0');
      final period = dateTime.hour >= 12 ? 'PM' : 'AM';
      return '$hour:$minute $period';
    } catch (_) {
      return rawTime;
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserName = widget.currentUserId == 1 ? 'User 1' : 'User 2';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF075E54), Color(0xFF128C7E)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 6,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 24),
                      const SizedBox(width: 12),
                      Text(
                        'DuoChat ($currentUserName)',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.logout_rounded, color: Colors.white),
                    tooltip: 'Logout',
                    onPressed: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const LoginScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF128C7E)))
          : conversations.isEmpty
              ? const Center(
                  child: Text(
                    'No conversations yet.',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: fetchConversations,
                  color: const Color(0xFF128C7E),
                  child: ListView.separated(
                    itemCount: conversations.length,
                    separatorBuilder: (_, _) => const Divider(height: 1, indent: 76, color: Color(0xFFE9EDEF)),
                    itemBuilder: (context, index) {
                      final item = conversations[index];
                      final otherUserId = item['other_user_id'];
                      final otherUserName = item['other_user_name'] ?? 'User';
                      final lastMessage = item['last_message'] ?? 'No messages yet';
                      final rawTime = item['last_message_time']?.toString() ?? '';
                      final formattedTime = _formatTime(rawTime);
                      final unread = item['unread_count'] ?? 0;
                      final isOnline = (otherUserId != null && onlineStatusMap[int.parse(otherUserId.toString())] == true);

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        leading: Stack(
                          children: [
                            CircleAvatar(
                              radius: 25,
                              backgroundColor: const Color(0xFF128C7E).withValues(alpha: 0.15),
                              child: Text(
                                otherUserName.isNotEmpty ? otherUserName[0].toUpperCase() : 'U',
                                style: const TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF128C7E),
                                ),
                              ),
                            ),
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: isOnline ? const Color(0xFF00E676) : Colors.grey.shade400,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2),
                                ),
                              ),
                            ),
                          ],
                        ),
                        title: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              otherUserName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Color(0xFF111B21),
                              ),
                            ),
                            if (formattedTime.isNotEmpty)
                              Text(
                                formattedTime,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: unread > 0 ? const Color(0xFF25D366) : const Color(0xFF667781),
                                  fontWeight: unread > 0 ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                          ],
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  lastMessage,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    color: unread > 0 ? const Color(0xFF111B21) : const Color(0xFF667781),
                                    fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.normal,
                                  ),
                                ),
                              ),
                              if (unread > 0)
                                Container(
                                  margin: const EdgeInsets.only(left: 8),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF25D366),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '$unread',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        onTap: () async {
                          final convId = item['conversation_id'];
                          if (convId != null) {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ChatScreen(
                                  currentUserId: widget.currentUserId,
                                  conversationId: int.parse(convId.toString()),
                                ),
                              ),
                            );
                            fetchConversations();
                          }
                        },
                      );
                    },
                  ),
                ),
    );
  }
}

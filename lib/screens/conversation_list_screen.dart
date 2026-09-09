import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../config/api_config.dart';
import '../services/app_lock_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/wave_clipper.dart';
import 'chat_screen.dart';
import 'login_screen.dart';
import 'profile_screen.dart';

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
  String get baseUrl => ApiConfig.baseUrl;

  List<Map<String, dynamic>> conversations = [];
  List<Map<String, dynamic>> filteredConversations = [];
  bool isLoading = true;
  io.Socket? socket;
  final TextEditingController searchController = TextEditingController();

  final Map<int, bool> onlineStatusMap = {};
  String currentUserDisplayName = '';
  String? currentUserAvatarPath;
  String? currentUserAvatarUrl;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
    _initSocket();
    fetchConversations();
    searchController.addListener(_filterConversations);
  }

  Future<void> _loadUserProfile() async {
    final user = await AuthService.getUser();
    final localAvatar = await AuthService.getAvatarPath(widget.currentUserId);
    if (mounted) {
      setState(() {
        currentUserDisplayName = user['name'] ?? (widget.currentUserId == 1 ? 'User 1' : 'User 2');
        currentUserAvatarPath = localAvatar ?? user['avatar_path']?.toString();
        currentUserAvatarUrl = user['avatar_url']?.toString() ?? AuthService.getAvatarUrl(widget.currentUserId);
      });
    }
  }

  ImageProvider? _getAvatarImageProvider(String? localPath, String? networkUrl) {
    if (localPath != null && localPath.isNotEmpty) {
      if (localPath.startsWith('http')) {
        return NetworkImage(localPath);
      }
      if (!kIsWeb) {
        final file = File(localPath);
        if (file.existsSync()) {
          return FileImage(file);
        }
      }
    }
    if (networkUrl != null && networkUrl.isNotEmpty) {
      return NetworkImage(networkUrl);
    }
    return null;
  }

  void _filterConversations() {
    final query = searchController.text.toLowerCase().trim();
    setState(() {
      if (query.isEmpty) {
        filteredConversations = List.from(conversations);
      } else {
        filteredConversations = conversations.where((c) {
          final name = (c['other_user_name'] ?? '').toString().toLowerCase();
          final msg = (c['last_message'] ?? '').toString().toLowerCase();
          return name.contains(query) || msg.contains(query);
        }).toList();
      }
    });
  }

  Future<void> _initSocket() async {
    final token = await AuthService.getTokenForUser(widget.currentUserId);
    final socketUrl = baseUrl;

    socket = io.io(
      socketUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          // .forceNew(true) // removed for compatibility with socket_io_client v3
          .disableAutoConnect()
          .build(),
    );

    void joinRooms() {
      debugPrint('âœ… ConversationListSocket joining rooms');
      _joinRooms();
    }

    socket?.onConnect((_) {
      debugPrint('âœ… ConversationListSocket connected: ${socket?.id}');
      joinRooms();
    });

    if (socket?.connected == true) {
      debugPrint('âœ… ConversationListSocket ALREADY connected: ${socket?.id}');
      joinRooms();
    }

    socket?.on('newMessage', (data) {
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
        _filterConversations();
      });
    });

    socket?.on('messageEdited', (data) {
      if (data == null || !mounted) return;
      final convId = data['conversation_id'] ?? data['conversationId'];
      final msg = data['message'] ?? '';

      setState(() {
        for (var c in conversations) {
          if (c['conversation_id'].toString() == convId.toString()) {
            c['last_message'] = msg;
          }
        }
        _filterConversations();
      });
    });

    socket?.on('messageDeleted', (data) {
      if (data == null || !mounted) return;
      final convId = data['conversationId'] ?? data['conversation_id'];

      setState(() {
        for (var c in conversations) {
          if (c['conversation_id'].toString() == convId.toString()) {
            c['last_message'] = "This message was deleted";
          }
        }
        _filterConversations();
      });
    });

    socket?.on('unreadCountUpdate', (data) {
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
        _filterConversations();
      });
    });

    socket?.on('userOnline', (data) {
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

    socket?.on('userOffline', (data) {
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

    socket?.connect();
  }

  void _joinRooms() {
    socket?.emit('joinUserRoom', {
      'userId': widget.currentUserId,
    });
  }

  Future<void> fetchConversations() async {
    try {
      var headers = await AuthService.getAuthHeadersForUser(widget.currentUserId);
      var response = await http.get(
        Uri.parse('$baseUrl/messages/conversations/${widget.currentUserId}'),
        headers: headers,
      );

      // If token expired/invalid (401/403), re-authenticate and retry
      if (response.statusCode == 401 || response.statusCode == 403) {
        final email = widget.currentUserId == 1 ? 'user1@example.com' : 'user2@example.com';
        final loginRes = await AuthService.login(email, 'password123');
        if (loginRes['success'] == true && loginRes['token'] != null) {
          headers = await AuthService.getAuthHeadersForUser(widget.currentUserId);
          response = await http.get(
            Uri.parse('$baseUrl/messages/conversations/${widget.currentUserId}'),
            headers: headers,
          );
        }
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          final List fetched = data['data'];
          if (!mounted) return;

          List<Map<String, dynamic>> loadedConversations = List<Map<String, dynamic>>.from(fetched);

          // If list is empty in 2-user private app, add default conversation tile with other user
          if (loadedConversations.isEmpty) {
            loadedConversations = [
              {
                'conversation_id': 1,
                'other_user_id': widget.currentUserId == 1 ? 2 : 1,
                'other_user_name': widget.currentUserId == 1 ? 'Second User' : 'Test User',
                'other_user_email': widget.currentUserId == 1 ? 'user2@example.com' : 'user1@example.com',
                'last_message': 'Tap to start chatting',
                'last_message_time': '',
                'unread_count': 0,
              }
            ];
          }

          // Apply saved custom aliases & avatars for each contact
          for (var c in loadedConversations) {
            final otherUid = int.tryParse((c['other_user_id'] ?? (widget.currentUserId == 1 ? 2 : 1)).toString()) ?? (widget.currentUserId == 1 ? 2 : 1);
            final alias = await AuthService.getContactAlias(otherUid, widget.currentUserId);
            if (alias != null && alias.isNotEmpty) {
              c['other_user_name'] = alias;
            }
            final localAvatar = await AuthService.getAvatarPath(otherUid);
            if (localAvatar != null && localAvatar.isNotEmpty) {
              c['other_user_avatar'] = localAvatar;
            }
          }

          setState(() {
            conversations = loadedConversations;
            filteredConversations = List.from(conversations);
            isLoading = false;
          });

          if (socket != null && socket!.connected) {
            _joinRooms();
          }
          return;
        }
      }
    } catch (e) {
      debugPrint("Error fetching conversations: $e");
    }

    if (mounted) {
      // Fallback 2-user conversation tile if offline or error occurs
      final otherUid = widget.currentUserId == 1 ? 2 : 1;
      final alias = await AuthService.getContactAlias(otherUid, widget.currentUserId);
      final localAvatar = await AuthService.getAvatarPath(otherUid);

      final fallbackConversations = [
        {
          'conversation_id': 1,
          'other_user_id': otherUid,
          'other_user_name': (alias != null && alias.isNotEmpty) ? alias : (widget.currentUserId == 1 ? 'Second User' : 'Test User'),
          'other_user_email': widget.currentUserId == 1 ? 'user2@example.com' : 'user1@example.com',
          'other_user_avatar': localAvatar,
          'last_message': 'Tap to start chatting',
          'last_message_time': '',
          'unread_count': 0,
        }
      ];

      setState(() {
        conversations = fallbackConversations;
        filteredConversations = List.from(conversations);
        isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    searchController.dispose();
    if (socket != null) {
      socket!.off('newMessage');
      socket!.off('unreadCountUpdate');
      socket!.off('userOnline');
      socket!.off('userOffline');
      socket!.off('messageEdited');
      socket!.off('messageDeleted');
      socket!.disconnect();
      socket!.dispose();
    }
    super.dispose();
  }

  String _formatTime(String rawTime) {
    if (rawTime.isEmpty) return '';
    try {
      final dateTime = DateTime.parse(rawTime).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dateTime);

      if (diff.inMinutes < 60 && diff.inMinutes > 0) {
        return '${diff.inMinutes}mins';
      }

      final hour = dateTime.hour == 0
          ? 12
          : (dateTime.hour > 12
              ? dateTime.hour - 12
              : dateTime.hour);
      final minute = dateTime.minute.toString().padLeft(2, '0');
      final period = dateTime.hour >= 12 ? 'PM' : 'AM';
      return '$hour:$minute$period';
    } catch (_) {
      return rawTime;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121E24) : const Color(0xFFF5F7F8),
      body: SafeArea(
        top: false,
        child: Stack(
          children: [
            Column(
              children: [
                // Top Teal Wave Header Container
                ClipPath(
                  clipper: WaveHeaderClipper(),
                  child: Container(
                    padding: const EdgeInsets.only(top: 50, left: 24, right: 24, bottom: 45),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF0F766E), Color(0xFF149B9B), Color(0xFF0D8383)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Messages',
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: 0.2,
                              ),
                            ),
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.lock_rounded, color: Colors.white, size: 24),
                                  tooltip: 'Lock App',
                                  onPressed: () {
                                    AppLockService.lockApp();
                                  },
                                ),
                                IconButton(
                                  icon: Icon(
                                    isDark ? Icons.light_mode_rounded : Icons.dark_mode_outlined,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                  tooltip: 'Toggle Theme',
                                  onPressed: () {
                                    themeModeNotifier.value = isDark ? ThemeMode.light : ThemeMode.dark;
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.logout_rounded, color: Colors.white, size: 24),
                                  tooltip: 'Logout',
                                  onPressed: () async {
                                    await AuthService.logout();
                                    AppLockService.lockApp();
                                    if (!context.mounted) return;
                                    Navigator.pushReplacement(
                                      context,
                                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                                    );
                                  },
                                ),
                                const SizedBox(width: 4),
                                GestureDetector(
                                  onTap: () async {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ProfileScreen(currentUserId: widget.currentUserId),
                                      ),
                                    );
                                    _loadUserProfile();
                                    fetchConversations();
                                  },
                                  child: Tooltip(
                                    message: 'My Profile',
                                    child: CircleAvatar(
                                      radius: 20,
                                      backgroundColor: Colors.white.withValues(alpha: 0.3),
                                      backgroundImage: _getAvatarImageProvider(currentUserAvatarPath, currentUserAvatarUrl),
                                      child: _getAvatarImageProvider(currentUserAvatarPath, currentUserAvatarUrl) == null
                                          ? Text(
                                              (currentUserDisplayName.isNotEmpty ? currentUserDisplayName[0] : (widget.currentUserId == 1 ? 'U' : 'U')).toUpperCase(),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w900,
                                                color: Colors.white,
                                                fontSize: 18,
                                              ),
                                            )
                                          : null,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        // Search Bar Input
                        Container(
                          height: 46,
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1F2C33) : Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: TextField(
                            controller: searchController,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white : const Color(0xFF111B21),
                            ),
                            decoration: InputDecoration(
                              hintText: 'Search',
                              hintStyle: TextStyle(
                                color: isDark ? Colors.grey.shade400 : Colors.grey.shade500,
                                fontWeight: FontWeight.w700,
                              ),
                              prefixIcon: Icon(
                                Icons.search_rounded,
                                color: isDark ? Colors.grey.shade400 : Colors.grey.shade500,
                                size: 22,
                              ),
                              contentPadding: const EdgeInsets.symmetric(vertical: 10),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Recent Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Recent',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: isDark ? Colors.white : const Color(0xFF111B21),
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.more_horiz_rounded,
                          color: isDark ? Colors.white70 : const Color(0xFF111B21),
                          size: 28,
                        ),
                        onPressed: () {},
                      ),
                    ],
                  ),
                ),

                // Conversation List
                Expanded(
                  child: isLoading
                      ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryTeal))
                      : filteredConversations.isEmpty
                          ? Center(
                              child: Text(
                                'No conversations yet.',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                ),
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: fetchConversations,
                              color: AppTheme.primaryTeal,
                              child: ListView.builder(
                                padding: const EdgeInsets.only(bottom: 90),
                                itemCount: filteredConversations.length,
                                itemBuilder: (context, index) {
                                  final item = filteredConversations[index];
                                  final otherUserId = item['other_user_id'];
                                  final otherUserName = item['other_user_name'] ?? 'User';
                                  final lastMessage = item['last_message'] ?? 'No messages yet';
                                  final rawTime = item['last_message_time']?.toString() ?? '';
                                  final formattedTime = _formatTime(rawTime);
                                  final unread = item['unread_count'] ?? 0;
                                  final isOnline = (otherUserId != null &&
                                      onlineStatusMap[int.parse(otherUserId.toString())] == true);
                                  final otherAvatarPath = item['other_user_avatar']?.toString();
                                  final otherUidInt = otherUserId != null ? int.tryParse(otherUserId.toString()) : (widget.currentUserId == 1 ? 2 : 1);
                                  final otherAvatarUrl = otherUidInt != null ? AuthService.getAvatarUrl(otherUidInt) : null;

                                  return Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                    child: Material(
                                      color: Colors.transparent,
                                      borderRadius: BorderRadius.circular(16),
                                      child: ListTile(
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                        leading: Stack(
                                          children: [
                                            CircleAvatar(
                                              radius: 26,
                                              backgroundColor: AppTheme.primaryTeal.withValues(alpha: 0.15),
                                              backgroundImage: _getAvatarImageProvider(otherAvatarPath, otherAvatarUrl),
                                              child: _getAvatarImageProvider(otherAvatarPath, otherAvatarUrl) == null
                                                  ? Text(
                                                      otherUserName.isNotEmpty ? otherUserName[0].toUpperCase() : 'U',
                                                      style: const TextStyle(
                                                        fontSize: 20,
                                                        fontWeight: FontWeight.w900,
                                                        color: AppTheme.primaryTeal,
                                                      ),
                                                    )
                                                  : null,
                                            ),
                                            if (isOnline)
                                              Positioned(
                                                right: 1,
                                                bottom: 1,
                                                child: Container(
                                                  width: 13,
                                                  height: 13,
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFF00E676),
                                                    shape: BoxShape.circle,
                                                    border: Border.all(
                                                      color: isDark ? const Color(0xFF121E24) : Colors.white,
                                                      width: 2,
                                                    ),
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
                                              style: TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 17,
                                                color: isDark ? Colors.white : const Color(0xFF111B21),
                                              ),
                                            ),
                                            if (formattedTime.isNotEmpty)
                                              Text(
                                                formattedTime,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                  color: unread > 0
                                                      ? const Color(0xFFE53935)
                                                      : (isDark ? Colors.grey.shade400 : Colors.grey.shade500),
                                                ),
                                              ),
                                          ],
                                        ),
                                        subtitle: Padding(
                                          padding: const EdgeInsets.only(top: 4),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  lastMessage,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    color: isDark ? Colors.grey.shade300 : const Color(0xFF667781),
                                                    fontWeight: unread > 0 ? FontWeight.w800 : FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                              if (unread > 0)
                                                Container(
                                                  margin: const EdgeInsets.only(left: 8),
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFFE53935),
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: Text(
                                                    '$unread',
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.w900,
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
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                ),
              ],
            ),

            // Floating Bottom Navigation Bar matching mockup
            Positioned(
              left: 30,
              right: 30,
              bottom: 20,
              child: Container(
                height: 56,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1F2C33) : Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    // Chat pill active button
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryTeal.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(
                        Icons.chat_bubble_rounded,
                        color: AppTheme.primaryTeal,
                        size: 24,
                      ),
                    ),

                    // Add Button
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDark ? Colors.grey.shade600 : const Color(0xFF111B21),
                          width: 1.5,
                        ),
                      ),
                      child: Icon(
                        Icons.add_rounded,
                        color: isDark ? Colors.white : const Color(0xFF111B21),
                        size: 24,
                      ),
                    ),

                    // Call Button
                    Icon(
                      Icons.phone_rounded,
                      color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                      size: 24,
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


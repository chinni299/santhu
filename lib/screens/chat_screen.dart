import 'dart:async';
import 'dart:convert';
import 'dart:io';


import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/foundation.dart' as foundation;
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/api_config.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/wave_clipper.dart';

import 'call_screen.dart';
import 'media_gallery_screen.dart';


class ChatScreen extends StatefulWidget {
  final int currentUserId;
  final int conversationId;

  const ChatScreen({
    super.key,
    this.currentUserId = 1,
    this.conversationId = 1,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final messageController = TextEditingController();
  final scrollController = ScrollController();

  final List<Map<String, dynamic>> messages = [];

  bool isLoading = true;
  Map<String, String> _authHeaders = {};

  // WhatsApp Selection State
  Map<String, dynamic>? selectedMessage;

  // Typing Indicator State
  bool isOtherUserTyping = false;
  String typingText = '';
  Timer? _typingTimer;
  bool _isEmittingTyping = false;

  // Online / Offline / Last Seen State
  bool isOtherUserOnline = false;
  String? otherUserLastSeenText;

  // Emoji Picker State
  bool _showEmojiPicker = false;
  final FocusNode _focusNode = FocusNode();

  // Unread Count State
  int unreadCount = 0;

  // Edit Message State
  int? editingMessageId;

  // Reply Message State
  Map<String, dynamic>? replyingToMessage;

  // 3-Dots Menu & Feature States
  bool isMuted = false;
  String muteDuration = 'Off';
  String disappearingTimer = 'Off';
  bool isFavourite = false;
  String customList = 'None';
  // NEW: Disappearing Messages — raw seconds value synced from the server (null = Off)
  int? disappearingTimerSeconds;
  bool isSearchingInChat = false;
  final inChatSearchController = TextEditingController();
  String inChatSearchQuery = '';

  // NEW: Pinned Messages — at most one pinned message per conversation
  Map<String, dynamic>? pinnedMessage;

  // NEW: Live Location Sharing state
  int? _activeLiveLocationMessageId;
  Timer? _liveLocationTimer;
  DateTime? _liveLocationEndTime;
  bool _isSharingLiveLocation = false;

  // NEW: "On This Day" Memories
  List<Map<String, dynamic>> onThisDayMemories = [];
  bool showOnThisDayBanner = false;

  // WhatsApp-style Document Download Tracking
  final Map<String, String> _downloadedFilePaths = {};
  final Set<String> _downloadingFileIds = {};

  // Instagram Vanish Mode State (Swipe Up Feature)
  bool isVanishMode = false;
  double vanishDragOffset = 0.0;
  bool isVanishThresholdReached = false;

  // Voice Message Recording State
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecordingVoice = false;
  Timer? _recordingTimer;
  int _recordingSeconds = 0;
  String? _recordingFilePath;

  String get baseUrl => ApiConfig.baseUrl;

  io.Socket? socket;
  String peerDisplayName = '';
  String peerAvatarPath = '';
  String peerAvatarUrl = '';
  bool _hasLoggedOffline = false;

  @override
  void initState() {
    super.initState();

    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        setState(() {
          _showEmojiPicker = false;
        });
      }
    });

    // Rebuild input bar so the mic/send icon swaps as soon as text is typed or cleared
    messageController.addListener(() {
      if (mounted) setState(() {});
    });

    _loadPeerProfile();
    _loadAuthHeaders();
    fetchMessages(showLoading: messages.isEmpty);
    _initSocket();
    if (!kIsWeb) {
      _initFCM();
    }
    fetchUnreadCount();
    fetchOtherUserStatus();
    _checkOnThisDayMemories(); // NEW: surface "on this day" memories on open
  }

  Future<void> _loadPeerProfile() async {
    final otherUserId = widget.currentUserId == 1 ? 2 : 1;
    final cachedAlias = await AuthService.getContactAlias(otherUserId, widget.currentUserId);
    if (cachedAlias != null && cachedAlias.isNotEmpty && mounted) {
      setState(() {
        peerDisplayName = cachedAlias;
      });
    }

    final profile = await AuthService.getPeerUserProfile(otherUserId, widget.currentUserId);
    if (mounted) {
      setState(() {
        peerDisplayName = profile['display_name'] ?? (otherUserId == 2 ? 'Leslie' : 'User $otherUserId');
        peerAvatarPath = profile['avatar_path'] ?? '';
        peerAvatarUrl = profile['avatar_url'] ?? AuthService.getAvatarUrl(otherUserId);
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

  void _showEditContactNameDialog() {
    final otherUserId = widget.currentUserId == 1 ? 2 : 1;
    final nameController = TextEditingController(text: peerDisplayName);

    showDialog(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: isDark ? const Color(0xFF1F2C33) : Colors.white,
          title: const Row(
            children: [
              Icon(Icons.edit_rounded, color: AppTheme.primaryTeal),
              SizedBox(width: 10),
              Text("Edit Contact Name", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Set a custom name for this contact like in WhatsApp.",
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: "Custom Display Name",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryTeal,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                final newName = nameController.text.trim();
                if (newName.isNotEmpty) {
                  await AuthService.saveContactAlias(otherUserId, newName, widget.currentUserId);
                  if (mounted) {
                    setState(() {
                      peerDisplayName = newName;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text("Contact renamed to '$newName'! ✅"),
                        backgroundColor: AppTheme.primaryTeal,
                      ),
                    );
                  }
                }
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                }
              },
              child: const Text("Save Name", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  String _decryptMessageIfNeeded(dynamic id, dynamic rawMessage, dynamic nonce, dynamic isEncrypted) {
    if (rawMessage == null || rawMessage.toString().isEmpty) return '';
    return rawMessage.toString();
  }

  Future<void> _loadAuthHeaders() async {
    final headers = await AuthService.getAuthHeadersForUser(widget.currentUserId);
    if (mounted) {
      setState(() {
        _authHeaders = headers;
      });
    }
  }

  String? _getFormattedImageUrl(String? url) {
    if (url == null || url.trim().isEmpty || url.trim() == 'null') return null;
    String cleanUrl = url.trim();
    if (cleanUrl.contains('/uploads/')) {
      cleanUrl = cleanUrl.replaceAll('/uploads/', '/messages/attachments/file/');
    }
    if (cleanUrl.startsWith('/')) {
      cleanUrl = '$baseUrl$cleanUrl';
    }
    cleanUrl = cleanUrl
        .replaceAll('localhost:5000', ApiConfig.formattedHost)
        .replaceAll('127.0.0.1:5000', ApiConfig.formattedHost)
        .replaceAll('192.168.0.120:5000', ApiConfig.formattedHost)
        .replaceAll('192.168.0.116:5000', ApiConfig.formattedHost)
        .replaceAll('http://santhu-swuo.onrender.com', 'https://santhu-swuo.onrender.com');
    return cleanUrl;
  }

  Future<void> _saveImageToGallery(String imageUrl, {bool isLocalFile = false}) async {
    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                ),
                SizedBox(width: 12),
                Text("Saving to Gallery..."),
              ],
            ),
            duration: Duration(seconds: 1),
          ),
        );
      }

      Uint8List? bytes;
      if (isLocalFile && !kIsWeb) {
        bytes = await File(imageUrl).readAsBytes();
      } else {
        final headers = await AuthService.getAuthHeadersForUser(widget.currentUserId);
        final res = await http.get(Uri.parse(imageUrl), headers: headers);
        if (res.statusCode == 200) {
          bytes = res.bodyBytes;
        }
      }

      if (bytes == null || bytes.isEmpty) {
        throw Exception("Could not load image file");
      }

      if (kIsWeb) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Image saved successfully Î“Â£Ã ")),
          );
        }
        return;
      }

      if (Platform.isAndroid) {
        await Permission.storage.request();
        await Permission.photos.request();
      }

      Directory? targetDir;
      if (Platform.isAndroid) {
        final picturesDir = Directory('/storage/emulated/0/Pictures/Clock');
        if (!await picturesDir.exists()) {
          try {
            await picturesDir.create(recursive: true);
          } catch (_) {}
        }
        if (await picturesDir.exists()) {
          targetDir = picturesDir;
        } else {
          final dcimDir = Directory('/storage/emulated/0/DCIM/Clock');
          if (!await dcimDir.exists()) {
            try {
              await dcimDir.create(recursive: true);
            } catch (_) {}
          }
          if (await dcimDir.exists()) {
            targetDir = dcimDir;
          }
        }
      }

      targetDir ??= await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();

      final filename = 'IMG_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final savedFile = File('${targetDir.path}/$filename');
      await savedFile.writeAsBytes(bytes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Saved directly to Gallery ($filename) â‰¡Æ’Ã»â•âˆ©â••Ã…Î“Â£Ã "),
            backgroundColor: AppTheme.primaryTeal,
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: "Open",
              textColor: Colors.white,
              onPressed: () {
                OpenFilex.open(savedFile.path);
              },
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint("Save to gallery error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error saving image: $e")),
        );
      }
    }
  }

  void _openFullImageViewer(String imageUrl, {bool isLocalFile = false}) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: (isLocalFile && !kIsWeb)
                    ? Image.file(File(imageUrl), fit: BoxFit.contain)
                    : Image.network(
                        imageUrl,
                        headers: _authHeaders,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.broken_image_rounded, size: 64, color: Colors.white54),
                            SizedBox(height: 12),
                            Text("Could not load image", style: TextStyle(color: Colors.white70)),
                          ],
                        ),
                      ),
              ),
            ),
            // Top Action Bar with Download / Save to Gallery Button
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 40, 16, 12),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.black87, Colors.transparent],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    CircleAvatar(
                      backgroundColor: Colors.black45,
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryTeal,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          ),
                          icon: const Icon(Icons.download_rounded, size: 20),
                          label: const Text(
                            "Save to Gallery",
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          onPressed: () => _saveImageToGallery(imageUrl, isLocalFile: isLocalFile),
                        ),
                        const SizedBox(width: 8),
                        CircleAvatar(
                          backgroundColor: Colors.black45,
                          child: IconButton(
                            icon: const Icon(Icons.close_rounded, color: Colors.white),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ),
                      ],
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

  String _decodeFileName(String? raw) {
    if (raw == null || raw.isEmpty) return 'Document';
    try {
      if (raw.contains('ð') || raw.contains('â') || raw.contains('Ã') || raw.contains('¥') || raw.contains('¤')) {
        final bytes = latin1.encode(raw);
        final decoded = utf8.decode(bytes, allowMalformed: true);
        if (decoded.isNotEmpty && !decoded.contains('')) {
          return decoded;
        }
      }
    } catch (_) {}
    return raw;
  }

  Future<void> _handleDocumentTap({
    required String? messageId,
    required String rawUrl,
    required String fileName,
    bool isMe = false,
    bool isLocalFile = false,
  }) async {
    final msgIdStr = messageId?.toString() ?? rawUrl;
    final cleanName = _decodeFileName(fileName);

    // 1. If it's already a local file and exists on disk, open it immediately
    if (isLocalFile && !kIsWeb && File(rawUrl).existsSync()) {
      await OpenFilex.open(rawUrl);
      return;
    }

    // 2. If already downloaded, open it on click
    if (_downloadedFilePaths.containsKey(msgIdStr)) {
      final localPath = _downloadedFilePaths[msgIdStr]!;
      if (!kIsWeb && File(localPath).existsSync()) {
        await OpenFilex.open(localPath);
        return;
      }
    }

    // 3. If currently downloading, avoid duplicate triggers
    if (_downloadingFileIds.contains(msgIdStr)) {
      return;
    }

    // 4. Otherwise, download it like WhatsApp (save locally, update state to downloaded)
    setState(() {
      _downloadingFileIds.add(msgIdStr);
    });

    try {
      final formattedUrl = _getFormattedImageUrl(rawUrl);
      if (formattedUrl == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Invalid file URL")),
          );
        }
        return;
      }

      final headers = await AuthService.getAuthHeadersForUser(widget.currentUserId);

      if (!kIsWeb) {
        final response = await http.get(Uri.parse(formattedUrl), headers: headers);
        if (response.statusCode == 200) {
          Uint8List fileBytes = response.bodyBytes;
          final tempDir = await getApplicationDocumentsDirectory();
          final safeName = cleanName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
          final targetPath = '${tempDir.path}/$safeName';
          final file = File(targetPath);
          await file.writeAsBytes(fileBytes);

          if (!mounted) return;
          setState(() {
            _downloadedFilePaths[msgIdStr] = targetPath;
            _downloadingFileIds.remove(msgIdStr);
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Downloaded $cleanName ✅ Tap again to open"),
              backgroundColor: AppTheme.primaryTeal,
              duration: const Duration(seconds: 2),
            ),
          );
        } else {
          throw Exception("Server returned ${response.statusCode}");
        }
      } else {
        // Web fallback
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Downloading $cleanName in browser...")),
          );
        }
      }
    } catch (e) {
      debugPrint("Error downloading file: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Could not download file: $e")),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _downloadingFileIds.remove(msgIdStr);
        });
      }
    }
  }

  Widget _buildEncryptedImageWidget({
    required String url,
    required String? nonce,
    required bool isEncrypted,
    required bool isLocalFile,
  }) {
    if (isLocalFile && !kIsWeb) {
      return Image.file(
        File(url),
        width: double.infinity,
        height: 230,
        fit: BoxFit.cover,
      );
    }

    return Image.network(
      url,
      width: double.infinity,
      height: 230,
      fit: BoxFit.cover,
      headers: _authHeaders,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(
          height: 200,
          color: Colors.black12,
          child: const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppTheme.primaryTeal,
              ),
            ),
          ),
        );
      },
      errorBuilder: (_, _, _) => Container(
        height: 140,
        color: Colors.grey.shade200,
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.broken_image_rounded, size: 36, color: Colors.grey),
            SizedBox(height: 4),
            Text("Could not load image", style: TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  void _copyToClipboard(String text) {
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Copied to clipboard ðŸ“‹"),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _toggleReaction(dynamic messageId, String emoji) {
    if (messageId == null) return;
    socket?.emit('reactToMessage', {
      'conversationId': widget.conversationId,
      'messageId': messageId,
      'userId': widget.currentUserId,
      'emoji': emoji,
    });
    setState(() {
      selectedMessage = null;
    });
  }

  // ==================================================
  // "ON THIS DAY" MEMORIES
  // ==================================================
  Future<void> _checkOnThisDayMemories() async {
    try {
      final headers = await AuthService.getAuthHeadersForUser(widget.currentUserId);
      final response = await http.get(
        Uri.parse('$baseUrl/messages/on-this-day/${widget.conversationId}'),
        headers: headers,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        if (data['success'] == true && data['data'] != null) {
          final List fetched = data['data'];
          if (fetched.isNotEmpty && mounted) {
            setState(() {
              onThisDayMemories = fetched.cast<Map<String, dynamic>>();
              showOnThisDayBanner = true;
            });
          }
        }
      }
    } catch (e) {
      // Silent — memories are a nice-to-have, never block the chat on failure
    }
  }

  void _showOnThisDayDialog() {
    final otherUserName = peerDisplayName.isNotEmpty ? peerDisplayName : (widget.currentUserId == 1 ? 'Leslie' : 'User 1');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.auto_awesome_rounded, color: AppTheme.primaryTeal),
            SizedBox(width: 8),
            Text('On This Day', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: onThisDayMemories.length,
            itemBuilder: (context, index) {
              final mem = onThisDayMemories[index];
              final isMe = int.tryParse((mem['sender_id'] ?? '').toString()) == widget.currentUserId;
              final year = mem['year_sent']?.toString() ?? '';
              final nowYear = DateTime.now().year;
              final yearsAgo = year.isNotEmpty ? (nowYear - int.parse(year)) : null;
              final label = yearsAgo == 1 ? '1 year ago' : '$yearsAgo years ago';
              final attachmentType = mem['attachment_type'];
              final preview = attachmentType == 'image'
                  ? '📷 Photo'
                  : attachmentType == 'audio'
                      ? '🎤 Voice message'
                      : attachmentType == 'file'
                          ? '📎 ${mem['attachment_name'] ?? 'File'}'
                          : (mem['message']?.toString().isNotEmpty == true ? mem['message'].toString() : 'Message');

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: AppTheme.primaryTeal.withValues(alpha: 0.15),
                      child: Text(
                        (isMe ? 'You' : otherUserName).substring(0, 1).toUpperCase(),
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: AppTheme.primaryTeal),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${isMe ? "You" : otherUserName} • $label',
                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: AppTheme.primaryTeal),
                          ),
                          const SizedBox(height: 2),
                          Text(preview, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> fetchOtherUserStatus() async {
    try {
      final otherUserId = widget.currentUserId == 1 ? 2 : 1;
      final headers = await AuthService.getAuthHeadersForUser(widget.currentUserId);
      final response = await http.get(
        Uri.parse('$baseUrl/messages/user-status/$otherUserId'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          final userData = data['data'];
          final bool online = userData['is_online'] == true;
          final rawLastSeen = userData['last_seen_at']?.toString();

          if (mounted) {
            setState(() {
              isOtherUserOnline = online;
              if (online) {
                otherUserLastSeenText = '\u{1F7E2} Online';
              } else if (rawLastSeen != null && rawLastSeen.isNotEmpty) {
                otherUserLastSeenText = '\u{26AB} Last seen ${_formatLastSeenTime(rawLastSeen)}';
              } else {
                otherUserLastSeenText = '\u{26AB} Offline';
              }
            });
          }
        }
      }
    } catch (e) {
      // Silent Î“Ã‡Ã¶ server may be offline
    }
  }

  String _formatLastSeenTime(String rawTime) {
    if (rawTime.isEmpty) return 'recently';
    try {
      final dateTime = DateTime.parse(rawTime).toLocal();
      final now = DateTime.now();
      final difference = now.difference(dateTime);

      final hour = dateTime.hour == 0
          ? 12
          : (dateTime.hour > 12
              ? dateTime.hour - 12
              : dateTime.hour);
      final minute = dateTime.minute.toString().padLeft(2, '0');
      final period = dateTime.hour >= 12 ? 'PM' : 'AM';
      final timeStr = '$hour:$minute $period';

      if (difference.inDays == 0 && now.day == dateTime.day) {
        return 'today at $timeStr';
      } else if (difference.inDays == 1 || (difference.inDays == 0 && now.day != dateTime.day)) {
        return 'yesterday at $timeStr';
      } else {
        return '${dateTime.day}/${dateTime.month}/${dateTime.year} at $timeStr';
      }
    } catch (_) {
      return 'recently';
    }
  }

  // NEW: Pinned Messages — toggle pin state for the given message
  void _togglePinMessage(Map<String, dynamic> messageMap) {
    final messageId = messageMap['id'];
    if (messageId == null) return;

    final bool isCurrentlyPinned = pinnedMessage != null && pinnedMessage!['id'].toString() == messageId.toString();

    if (isCurrentlyPinned) {
      socket?.emit('unpinMessage', {
        'conversationId': widget.conversationId,
        'messageId': messageId,
      });
    } else {
      socket?.emit('pinMessage', {
        'conversationId': widget.conversationId,
        'messageId': messageId,
      });
    }

    setState(() {
      selectedMessage = null;
    });
  }

  void _startReplying(Map<String, dynamic> messageMap) {
    setState(() {
      replyingToMessage = messageMap;
      editingMessageId = null;
      selectedMessage = null;
    });
  }

  void _cancelReplying() {
    setState(() {
      replyingToMessage = null;
    });
  }

  void _scrollToMessage(dynamic targetId) {
    if (targetId == null) return;
    final targetIdStr = targetId.toString();
    final index = messages.indexWhere((m) => m['id'] != null && m['id'].toString() == targetIdStr);
    if (index != -1) {
      final double targetOffset = (index * 85.0).clamp(0.0, scrollController.position.maxScrollExtent);
      scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    }
  }

  String _getReplyPreviewText(dynamic type, dynamic name, dynamic text, bool isDeleted) {
    if (isDeleted) return "This message was deleted";
    if (type == 'image') return "ðŸ“· Photo";
    if (type == 'audio') return "\u{1F3A4} Voice message";
    if (type == 'location') return "\u{1F4CD} Location";
    if (type == 'file') return "ðŸ“Ž ${name ?? 'File'}";
    if (text != null && text.toString().isNotEmpty) return text.toString();
    return "Message";
  }

  String _getReplySenderName(dynamic senderId, dynamic senderName, bool isMe) {
    if (isMe) return "You";
    if (senderName != null && senderName.toString().isNotEmpty) {
      return senderName.toString();
    }
    if (senderId != null) {
      final sId = int.tryParse(senderId.toString());
      if (sId != null) {
        return sId == 1 ? "User 1" : "User 2";
      }
    }
    return "User";
  }

  // IMPORTANT: Must be async. Token is fetched FIRST, then socket is created
  // with .setAuth() at creation time. Setting auth after creation via
  // socket?.io.options?['auth'] does NOT work in socket_io_client v3 on
  // Flutter Web â€” the server always sees no token and rejects with 401.
  Future<void> _initSocket() async {
    final token = await AuthService.ensureToken(widget.currentUserId);

    if (token == null || token.isEmpty) {
      debugPrint('âš  Chat: Could not obtain token â€” running in local mode');
      return;
    }
    debugPrint('âœ… Chat socket: connecting...');
    debugPrint('[CHAT SOCKET] AUTH TOKEN PRESENT: true');
    debugPrint('[CHAT SOCKET] URL: $baseUrl');

    socket = io.io(
      baseUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          // .forceNew(true) // removed for compatibility with socket_io_client v3
          .disableAutoConnect()
          .build(),
    );

    void joinConversation() {
      debugPrint('[CHAT SOCKET] JOINING ROOM: ${widget.conversationId}');
      socket?.emit('joinConversation', {
        'conversationId': widget.conversationId,
        'userId': widget.currentUserId,
        'userName': widget.currentUserId == 1 ? 'User 1' : 'User 2',
      });
      _markDelivered();
      _markSeen();
    }

    socket?.onConnect((_) {
      debugPrint('[CHAT SOCKET] CONNECTED socketId: ${socket?.id}');
      joinConversation();
    });

    if (socket?.connected == true) {
      debugPrint('[CHAT SOCKET] ALREADY CONNECTED socketId: ${socket?.id}');
      joinConversation();
    }

    socket?.onConnectError((err) {
      debugPrint('[CHAT SOCKET] CONNECT ERROR: $err');
      if (!_hasLoggedOffline) {
        _hasLoggedOffline = true;
        debugPrint('âš ï¸ Chat socket connect error: $err');
      }
    });

    socket?.onDisconnect((_) {
      debugPrint('[CHAT SOCKET] DISCONNECTED');
      // Let socket_io handle reconnection with built-in retry limits
    });

    socket?.on('newMessage', (data) async {
      debugPrint('[CHAT SOCKET] RECEIVED newMessage: $data');
      if (data == null) return;

      final rawTime = data['created_at'] != null ? data['created_at'].toString() : '';
      final senderId = data['sender_id'] ?? data['senderId'];
      final messageId = data['id'];
      final bool isRead = data['is_read'] == true || data['isRead'] == true;
      final bool isEdited = data['is_edited'] == true || data['isEdited'] == true;
      final bool isDeleted = data['is_deleted'] == true || data['isDeleted'] == true;
      final nonce = data['nonce'];
      final isEncrypted = data['is_encrypted'] == true || data['isEncrypted'] == true;

      final replyToMessageId = data['reply_to_message_id'] ?? data['replyToMessageId'];
      final replySenderId = data['reply_sender_id'] ?? data['replySenderId'];
      final replySenderName = data['reply_sender_name'] ?? data['replySenderName'];
      final replyMessage = data['reply_message'] ?? data['replyMessage'];
      final replyAttachmentType = data['reply_attachment_type'] ?? data['replyAttachmentType'];
      final replyAttachmentName = data['reply_attachment_name'] ?? data['replyAttachmentName'];
      final bool replyIsDeleted = data['reply_is_deleted'] == true || data['replyIsDeleted'] == true;

      final reactions = data['reactions'] is Map
          ? Map<String, dynamic>.from(data['reactions'])
          : <String, dynamic>{};

      final rawText = data['message'] ?? '';
      final decryptedText = isDeleted
          ? 'This message was deleted'
          : _decryptMessageIfNeeded(messageId, rawText, nonce, isEncrypted);

      final newMessageMap = {
        'id': messageId,
        'message': decryptedText,
        'nonce': nonce,
        'isEncrypted': isEncrypted,
        'is_encrypted': isEncrypted,
        'attachmentUrl': data['attachment_url'] ?? data['attachmentUrl'],
        'attachmentType': data['attachment_type'] ?? data['attachmentType'],
        'attachmentName': data['attachment_name'] ?? data['attachmentName'],
        'attachmentSize': data['attachment_size'] ?? data['attachmentSize'],
        'replyToMessageId': replyToMessageId,
        'reply_to_message_id': replyToMessageId,
        'replySenderId': replySenderId,
        'reply_sender_id': replySenderId,
        'replySenderName': replySenderName,
        'reply_sender_name': replySenderName,
        'replyMessage': replyMessage,
        'reply_message': replyMessage,
        'replyAttachmentType': replyAttachmentType,
        'reply_attachment_type': replyAttachmentType,
        'replyAttachmentName': replyAttachmentName,
        'reply_attachment_name': replyAttachmentName,
        'replyIsDeleted': replyIsDeleted,
        'reply_is_deleted': replyIsDeleted,
        // Strict message ownership based on senderId
        'isMe': senderId != null && int.parse(senderId.toString()) == widget.currentUserId,
        'isDelivered': data['is_delivered'] == true || data['isDelivered'] == true || isRead,
        'is_delivered': data['is_delivered'] == true || data['isDelivered'] == true || isRead,
        'isRead': isRead,
        'is_read': isRead,
        'isEdited': isEdited,
        'is_edited': isEdited,
        'isDeleted': isDeleted,
        'is_deleted': isDeleted,
        'reactions': reactions,
        'time': _formatTime(rawTime),
      };

      if (!mounted) return;

      final tempMsgId = data['tempMsgId'] ?? data['temp_msg_id'];

      final existingIndex = messages.indexWhere(
        (m) {
          // Match by real DB id
          if (messageId != null && m['id'] != null &&
              m['id'].toString() == messageId.toString()) {
            return true;
          }
          // Match by tempMsgId (optimistic message placeholder)
          if (tempMsgId != null && m['id'] != null &&
              m['id'].toString() == tempMsgId.toString()) {
            return true;
          }
          // Match uploading attachment by name
          if (m['isUploading'] == true &&
              m['attachmentName'] == newMessageMap['attachmentName']) {
            return true;
          }
          // Prevent duplicates: same sender + same message text + same time
          if (m['isMe'] == newMessageMap['isMe'] &&
              m['message'] == newMessageMap['message'] &&
              m['time'] == newMessageMap['time'] &&
              m['id'] != null && m['id'].toString().startsWith('temp_') == false) {
            return true;
          }
          return false;
        },
      );

      setState(() {
        if (existingIndex != -1) {
          messages[existingIndex] = {
            ...newMessageMap,
            'isMe': newMessageMap['isMe'],
          };
        } else {
          // New message from the other user (no tempMsgId match)
          messages.add(newMessageMap);
        }
      });

      // NEW: If this is the echo of a live-location message we just started
      // sharing (we don't yet know its server-assigned id), capture it now
      // and kick off the periodic position-update timer.
      if (newMessageMap['isMe'] == true &&
          newMessageMap['attachmentType'] == 'location' &&
          _isSharingLiveLocation &&
          _activeLiveLocationMessageId == null) {
        try {
          final parsed = jsonDecode(newMessageMap['message']?.toString() ?? '{}');
          if (parsed['isLive'] == true) {
            _activeLiveLocationMessageId = int.tryParse(newMessageMap['id'].toString());
            _startLiveLocationUpdateTimer();
          }
        } catch (_) {}
      }

      debugPrint("=== SOCKET MESSAGE CHECK ===");
      debugPrint("Message ID: ${newMessageMap['id']}");
      debugPrint("currentUserId: ${widget.currentUserId}");
      debugPrint("sender_id (raw): ${data['sender_id']}");
      debugPrint("senderId (raw): ${data['senderId']}");
      debugPrint("isMe: ${newMessageMap['isMe']}");
      debugPrint("============================");

      _scrollToBottom();

      if (senderId != null && int.parse(senderId.toString()) != widget.currentUserId) {
        _markDelivered();
        _markSeen();
      }
    });

    socket?.on('messagesSeen', (data) {
      if (data == null) return;

      final readerId = data['readerId'] ?? data['reader_id'];
      if (readerId != null && int.parse(readerId.toString()) == widget.currentUserId) return;

      final List? seenIds = data['seenMessageIds'];

      if (!mounted) return;
      setState(() {
        for (var msg in messages) {
          if (msg['isMe'] == true) {
            if (seenIds == null ||
                seenIds.isEmpty ||
                msg['id'] == null ||
                seenIds.map((e) => e.toString()).contains(msg['id'].toString()) ||
                msg['id'].toString().startsWith('temp_')) {
              msg['isRead'] = true;
              msg['is_read'] = true;
              msg['isDelivered'] = true;
              msg['is_delivered'] = true;
            }
          }
        }
      });
    });

    socket?.on('messagesDelivered', (data) {
      if (data == null) return;

      final recipientId = data['recipientId'] ?? data['recipient_id'];
      if (recipientId != null && int.parse(recipientId.toString()) == widget.currentUserId) return;

      final List? deliveredIds = data['deliveredMessageIds'];

      if (!mounted) return;
      setState(() {
        for (var msg in messages) {
          if (msg['isMe'] == true) {
            if (deliveredIds == null ||
                deliveredIds.isEmpty ||
                msg['id'] == null ||
                deliveredIds.map((e) => e.toString()).contains(msg['id'].toString()) ||
                msg['id'].toString().startsWith('temp_')) {
              msg['isDelivered'] = true;
              msg['is_delivered'] = true;
            }
          }
        }
      });
    });

    socket?.on('messageReaction', (data) {
      if (data == null) return;
      final msgId = data['messageId'] ?? data['message_id'];
      final rawReactions = data['reactions'];
      if (msgId == null) return;

      final Map<String, dynamic> reactionsMap = rawReactions is Map
          ? Map<String, dynamic>.from(rawReactions)
          : <String, dynamic>{};

      if (!mounted) return;
      setState(() {
        for (var msg in messages) {
          if (msg['id'] != null && msg['id'].toString() == msgId.toString()) {
            msg['reactions'] = reactionsMap;
          }
        }
      });
    });

    socket?.on('messageEdited', (data) {
      if (data == null) return;
      final messageId = data['id'] ?? data['messageId'];
      final newMessage = data['message'];
      if (messageId == null || newMessage == null) return;

      if (!mounted) return;
      setState(() {
        for (var msg in messages) {
          if (msg['id'] != null && msg['id'].toString() == messageId.toString()) {
            msg['message'] = newMessage;
            msg['isEdited'] = true;
            msg['is_edited'] = true;
          }
        }
      });
    });

    socket?.on('messageDeleted', (data) {
      if (data == null) return;
      final messageId = data['messageId'] ?? data['id'];
      if (messageId == null) return;

      if (!mounted) return;
      setState(() {
        for (var msg in messages) {
          if (msg['id'] != null && msg['id'].toString() == messageId.toString()) {
            msg['isDeleted'] = true;
            msg['is_deleted'] = true;
            msg['message'] = "This message was deleted";
          }
          if (msg['replyToMessageId'] != null && msg['replyToMessageId'].toString() == messageId.toString()) {
            msg['replyIsDeleted'] = true;
            msg['reply_is_deleted'] = true;
          }
        }
      });
    });

    socket?.on('typing', (data) {
      if (data == null) return;
      final senderId = data['senderId'] ?? data['sender_id'];
      if (senderId != null && int.parse(senderId.toString()) == widget.currentUserId) return;

      final name = data['userName'] ?? (senderId != null && int.parse(senderId.toString()) == 1 ? 'User 1' : 'User 2');

      if (!mounted) return;
      setState(() {
        isOtherUserTyping = true;
        typingText = "$name is typing...";
      });
    });

    socket?.on('stopTyping', (data) {
      if (data == null) return;
      final senderId = data['senderId'] ?? data['sender_id'];
      if (senderId != null && int.parse(senderId.toString()) == widget.currentUserId) return;

      if (!mounted) return;
      setState(() {
        isOtherUserTyping = false;
        typingText = '';
      });
    });

    socket?.on('userOnline', (data) {
      if (data == null) return;
      final userId = data['userId'] ?? data['user_id'];
      if (userId != null && int.parse(userId.toString()) == widget.currentUserId) return;

      if (!mounted) return;
      setState(() {
        isOtherUserOnline = true;
        otherUserLastSeenText = '\u{1F7E2} Online';
      });
    });

    socket?.on('vanishModeToggle', (data) {
      if (data == null) return;
      final bool newVanishState = data['isVanishMode'] == true;
      if (!mounted) return;
      if (isVanishMode != newVanishState) {
        setState(() {
          isVanishMode = newVanishState;
        });
      }
    });

    // NEW: Disappearing Messages — server tells us the conversation's current timer
    socket?.on('disappearingTimerUpdate', (data) {
      if (data == null) return;
      final convId = data['conversationId'];
      if (convId != null && convId.toString() != widget.conversationId.toString()) return;

      final rawSeconds = data['timerSeconds'];
      final int? seconds = rawSeconds != null ? int.tryParse(rawSeconds.toString()) : null;

      if (!mounted) return;
      setState(() {
        disappearingTimerSeconds = (seconds != null && seconds > 0) ? seconds : null;
        disappearingTimer = _disappearingTimerLabel(disappearingTimerSeconds);
      });
    });

    // NEW: Pinned Messages
    socket?.on('messagePinned', (data) {
      if (data == null) return;
      final convId = data['conversationId'];
      if (convId != null && convId.toString() != widget.conversationId.toString()) return;

      final msgData = data['message'];
      if (msgData == null) return;

      if (!mounted) return;
      setState(() {
        pinnedMessage = Map<String, dynamic>.from(msgData);
        for (var m in messages) {
          m['isPinned'] = m['id'] != null && m['id'].toString() == pinnedMessage!['id'].toString();
        }
      });
    });

    socket?.on('messageUnpinned', (data) {
      if (data == null) return;
      final convId = data['conversationId'];
      if (convId != null && convId.toString() != widget.conversationId.toString()) return;

      if (!mounted) return;
      setState(() {
        pinnedMessage = null;
        for (var m in messages) {
          m['isPinned'] = false;
        }
      });
    });

    // NEW: Live Location Sharing
    socket?.on('liveLocationUpdate', (data) {
      if (data == null) return;
      final convId = data['conversationId'];
      if (convId != null && convId.toString() != widget.conversationId.toString()) return;

      final msgId = data['messageId'];
      final lat = data['latitude'];
      final lng = data['longitude'];
      if (msgId == null) return;

      if (!mounted) return;
      setState(() {
        for (var m in messages) {
          if (m['id'] != null && m['id'].toString() == msgId.toString()) {
            m['message'] = jsonEncode({'lat': lat, 'lng': lng, 'isLive': true});
          }
        }
      });
    });

    socket?.on('liveLocationEnded', (data) {
      if (data == null) return;
      final convId = data['conversationId'];
      if (convId != null && convId.toString() != widget.conversationId.toString()) return;

      final msgId = data['messageId'];
      if (msgId == null) return;

      if (!mounted) return;
      setState(() {
        for (var m in messages) {
          if (m['id'] != null && m['id'].toString() == msgId.toString()) {
            try {
              final parsed = jsonDecode(m['message']?.toString() ?? '{}');
              parsed['isLive'] = false;
              m['message'] = jsonEncode(parsed);
            } catch (_) {}
          }
        }
      });
      // If this was our own active share, stop the local update timer too
      // (done outside setState because it calls setState itself)
      if (_activeLiveLocationMessageId != null && _activeLiveLocationMessageId.toString() == msgId.toString()) {
        _stopSharingLiveLocationLocal();
      }
    });

    socket?.on('userOffline', (data) {
      if (data == null) return;
      final userId = data['userId'] ?? data['user_id'];
      if (userId != null && int.parse(userId.toString()) == widget.currentUserId) return;

      final rawLastSeen = data['lastSeenAt'] ?? data['last_seen_at'];

      if (!mounted) return;
      setState(() {
        isOtherUserOnline = false;
        if (rawLastSeen != null && rawLastSeen.toString().isNotEmpty) {
          otherUserLastSeenText = '\u{26AB} Last seen ${_formatLastSeenTime(rawLastSeen.toString())}';
        } else {
          otherUserLastSeenText = '\u{26AB} Offline';
        }
      });
    });

    socket?.on('unreadCountUpdate', (data) {
      if (data == null) return;

      final convId = data['conversationId'];
      if (convId != null && convId.toString() != widget.conversationId.toString()) return;

      final senderId = data['senderId'];
      final userId = data['userId'];

      if (!mounted) return;

      if (userId != null && int.parse(userId.toString()) == widget.currentUserId) {
        setState(() {
          unreadCount = 0;
        });
        return;
      }

      if (senderId != null && int.parse(senderId.toString()) != widget.currentUserId) {
        final count = data['unreadCount'];
        if (count != null) {
          setState(() {
            unreadCount = int.parse(count.toString());
          });
        }
      }
    });

    socket?.on('incomingCall', (data) {
      if (data == null) return;
      final convId = data['conversationId'];
      if (convId != null && convId.toString() != widget.conversationId.toString()) return;

      final callerName = data['callerName'] ?? (widget.currentUserId == 1 ? "Second User" : "Test User");
      final isVideoCall = data['isVideoCall'] == true;

      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogCtx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(
            children: [
              Icon(
                isVideoCall ? Icons.videocam_rounded : Icons.phone_rounded,
                color: AppTheme.primaryTeal,
              ),
              const SizedBox(width: 10),
              Text(
                isVideoCall ? 'Incoming Video Call' : 'Incoming Audio Call',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Text('$callerName is calling you...'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogCtx);
                socket?.emit('rejectCall', {'conversationId': widget.conversationId});
              },
              style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
              child: const Text('Decline'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogCtx);
                _openCallScreen(isVideoCall: isVideoCall, isCaller: false);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryTeal,
                foregroundColor: Colors.white,
              ),
              child: const Text('Accept'),
            ),
          ],
        ),
      );
    });

    socket?.on('callError', (data) {
      if (data != null && data['message'] != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message'].toString())),
        );
      }
    });

    socket?.connect(); // Single connect() Î“Ã‡Ã¶ auth already in socket at creation
  }

  void _openCallScreen({required bool isVideoCall, required bool isCaller}) {
    final otherUserName = widget.currentUserId == 1 ? "Second User" : "Test User";
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => CallScreen(
          socket: socket,
          conversationId: widget.conversationId,
          currentUserId: widget.currentUserId,
          peerName: otherUserName,
          isVideoCall: isVideoCall,
          isCaller: isCaller,
        ),
      ),
    );
  }

  void _markSeen() {
    socket?.emit('markMessagesSeen', {
      'conversationId': widget.conversationId,
      'userId': widget.currentUserId,
    });
    if (mounted) {
      setState(() {
        unreadCount = 0;
      });
    }
  }

  void _markDelivered() {
    socket?.emit('markMessagesDelivered', {
      'conversationId': widget.conversationId,
      'userId': widget.currentUserId,
    });
  }

  void _onTypingChanged(String text) {
    if (text.trim().isEmpty) {
      _stopTypingEmit();
      return;
    }

    if (!_isEmittingTyping) {
      _isEmittingTyping = true;
      socket?.emit('typing', {
        'conversationId': widget.conversationId,
        'senderId': widget.currentUserId,
        'userName': widget.currentUserId == 1 ? 'User 1' : 'User 2',
      });
    }

    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(milliseconds: 1000), () {
      _stopTypingEmit();
    });
  }

  void _stopTypingEmit() {
    _typingTimer?.cancel();
    if (_isEmittingTyping) {
      _isEmittingTyping = false;
      socket?.emit('stopTyping', {
        'conversationId': widget.conversationId,
        'senderId': widget.currentUserId,
      });
    }
  }

  // =========================
  // VOICE MESSAGE RECORDING
  // =========================

  Future<void> _startVoiceRecording() async {
    try {
      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        _showErrorSnackBar("Microphone permission is required to record voice messages");
        return;
      }

      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: filePath,
      );

      if (!mounted) return;
      setState(() {
        _isRecordingVoice = true;
        _recordingFilePath = filePath;
        _recordingSeconds = 0;
      });

      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (mounted) {
          setState(() => _recordingSeconds++);
        }
      });
    } catch (e) {
      debugPrint("Error starting voice recording: $e");
      _showErrorSnackBar("Could not start recording: $e");
    }
  }

  Future<void> _stopVoiceRecordingAndSend({bool cancel = false}) async {
    if (!_isRecordingVoice) return;
    _recordingTimer?.cancel();

    try {
      final path = await _audioRecorder.stop();

      if (!mounted) return;
      setState(() {
        _isRecordingVoice = false;
      });

      if (cancel || path == null) {
        if (path != null && !kIsWeb) {
          final f = File(path);
          if (await f.exists()) {
            try { await f.delete(); } catch (_) {}
          }
        }
        return;
      }

      // Too short a recording is treated as accidental — discard it
      if (_recordingSeconds < 1) {
        if (!kIsWeb) {
          final f = File(path);
          if (await f.exists()) {
            try { await f.delete(); } catch (_) {}
          }
        }
        _showErrorSnackBar("Recording too short");
        return;
      }

      final bytes = await File(path).readAsBytes();
      final fileName = 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

      _uploadAndSendFile(
        filePath: path,
        fileBytes: bytes,
        fileName: fileName,
        attachmentType: 'audio',
        fileSize: bytes.length,
      );
    } catch (e) {
      debugPrint("Error stopping voice recording: $e");
      _showErrorSnackBar("Could not send voice message: $e");
    }
  }

  String _formatRecordingDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _recordingTimer?.cancel();
    _liveLocationTimer?.cancel();
    if (_isRecordingVoice) {
      _audioRecorder.stop();
    }
    _audioRecorder.dispose();
    if (socket != null) {
      // Leaving the chat screen ends any live-location share we started
      if (_isSharingLiveLocation && _activeLiveLocationMessageId != null) {
        socket!.emit('stopLiveLocation', {
          'conversationId': widget.conversationId,
          'messageId': _activeLiveLocationMessageId,
        });
      }
      socket!.off('messagePinned');
      socket!.off('messageUnpinned');
      socket!.off('liveLocationUpdate');
      socket!.off('liveLocationEnded');
      socket!.off('typing');
      socket!.off('stopTyping');
      socket!.off('newMessage');
      socket!.off('messagesSeen');
      socket!.off('messagesDelivered');
      socket!.off('messageEdited');
      socket!.off('messageDeleted');
      socket!.off('messageReaction');
      socket!.off('userOnline');
      socket!.off('userOffline');
      socket!.off('unreadCountUpdate');
      socket!.off('disappearingTimerUpdate');
      socket!.disconnect();
      socket!.dispose();
    }

    messageController.dispose();
    scrollController.dispose();
    inChatSearchController.dispose();
    _focusNode.dispose();

    super.dispose();
  }

  // --- 3-DOTS MENU IMPLEMENTATIONS ---

  void _showThreeDotsMenu() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final otherUserName = peerDisplayName.isNotEmpty ? peerDisplayName : (widget.currentUserId == 1 ? 'Leslie' : 'User 1');

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Material(
          color: isDark ? const Color(0xFF1E293B) : const Color(0xFF1F2C33),
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: Container(
            margin: const EdgeInsets.all(16),
            child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 8),

                _buildMenuItem(
                  icon: Icons.info_outline_rounded,
                  title: 'Contact info',
                  onTap: () {
                    Navigator.pop(ctx);
                    _showContactInfo();
                  },
                ),
                _buildMenuItem(
                  icon: Icons.edit_rounded,
                  iconColor: AppTheme.primaryTeal,
                  title: 'Edit Contact Name',
                  onTap: () {
                    Navigator.pop(ctx);
                    _showEditContactNameDialog();
                  },
                ),
                _buildMenuItem(
                  icon: Icons.security_rounded,
                  iconColor: Colors.amber,
                  title: 'E2EE Safety Number',
                  onTap: () {
                    Navigator.pop(ctx);
                    _showSafetyNumberDialog();
                  },
                ),
                _buildMenuItem(
                  icon: Icons.search_rounded,
                  title: 'Search in chat',
                  onTap: () {
                    Navigator.pop(ctx);
                    _toggleInChatSearch();
                  },
                ),
                _buildMenuItem(
                  icon: Icons.check_box_outlined,
                  title: 'Select messages',
                  onTap: () {
                    Navigator.pop(ctx);
                    _enableSelectMessages();
                  },
                ),
                _buildMenuItem(
                  icon: isMuted ? Icons.notifications_active_outlined : Icons.notifications_off_outlined,
                  title: isMuted ? 'Mute notifications ($muteDuration)' : 'Mute notifications',
                  hasTrailingArrow: true,
                  onTap: () {
                    Navigator.pop(ctx);
                    _showMuteDialog();
                  },
                ),
                _buildMenuItem(
                  icon: Icons.auto_awesome_rounded,
                  iconColor: isVanishMode ? const Color(0xFFE040FB) : Colors.white,
                  title: isVanishMode ? 'Turn off Vanish mode â˜€ï¸' : 'Vanish mode (Swipe up in chat) ðŸ”®',
                  onTap: () {
                    Navigator.pop(ctx);
                    _toggleVanishMode(!isVanishMode);
                  },
                ),
                _buildMenuItem(
                  icon: Icons.timer_outlined,
                  iconColor: disappearingTimerSeconds != null ? AppTheme.primaryTeal : Colors.white,
                  title: 'Disappearing messages ($disappearingTimer)',
                  hasTrailingArrow: true,
                  onTap: () {
                    Navigator.pop(ctx);
                    _showDisappearingTimerDialog();
                  },
                ),
                _buildMenuItem(
                  icon: isFavourite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  iconColor: isFavourite ? Colors.redAccent : Colors.white,
                  title: isFavourite ? 'Remove from favourites' : 'Add to favourites',
                  onTap: () {
                    Navigator.pop(ctx);
                    _toggleFavourites();
                  },
                ),
                _buildMenuItem(
                  icon: Icons.photo_album_outlined,
                  title: 'Add to list ($customList)',
                  hasTrailingArrow: true,
                  onTap: () {
                    Navigator.pop(ctx);
                    _showAddToListDialog();
                  },
                ),
                _buildMenuItem(
                  icon: Icons.file_download_outlined,
                  title: 'Export chat',
                  onTap: () {
                    Navigator.pop(ctx);
                    _exportChatTranscript();
                  },
                ),
                _buildMenuItem(
                  icon: Icons.cancel_outlined,
                  title: 'Close chat',
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.pop(context);
                  },
                ),

                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Divider(color: Colors.white12, height: 1),
                ),

                _buildMenuItem(
                  icon: Icons.link_rounded,
                  title: 'Send call link',
                  onTap: () {
                    Navigator.pop(ctx);
                    _sendCallLink();
                  },
                ),
                _buildMenuItem(
                  icon: Icons.calendar_month_rounded,
                  title: 'Schedule call',
                  onTap: () {
                    Navigator.pop(ctx);
                    _scheduleCallPicker();
                  },
                ),
                _buildMenuItem(
                  icon: Icons.group_add_rounded,
                  title: 'New group call with $otherUserName',
                  onTap: () {
                    Navigator.pop(ctx);
                    _startNewGroupCall();
                  },
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      );
    },
  );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    Color iconColor = Colors.white,
    bool hasTrailingArrow = false,
    required VoidCallback onTap,
  }) {
    return ListTile(
      dense: true,
      horizontalTitleGap: 12,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
      leading: Icon(icon, color: iconColor, size: 22),
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
      trailing: hasTrailingArrow
          ? const Icon(Icons.arrow_right_rounded, color: Colors.white54, size: 20)
          : null,
      onTap: onTap,
    );
  }

  void _showContactInfo() {
    final otherUserName = peerDisplayName.isNotEmpty ? peerDisplayName : (widget.currentUserId == 1 ? 'Leslie' : 'User 1');
    final mediaCount = messages.where((m) => m['attachmentType'] == 'image').length;
    final fileCount = messages.where((m) => m['attachmentType'] == 'file').length;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Material(
          color: isDark ? const Color(0xFF121E24) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          clipBehavior: Clip.antiAlias,
          child: Container(
            height: MediaQuery.of(context).size.height * 0.75,
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(
              children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              CircleAvatar(
                radius: 44,
                backgroundColor: AppTheme.primaryTeal,
                backgroundImage: _getAvatarImageProvider(peerAvatarPath, peerAvatarUrl),
                child: _getAvatarImageProvider(peerAvatarPath, peerAvatarUrl) == null
                    ? Text(
                        otherUserName.isNotEmpty ? otherUserName[0].toUpperCase() : 'U',
                        style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: Colors.white),
                      )
                    : null,
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    otherUserName,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: isDark ? Colors.white : const Color(0xFF111B21),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.verified_rounded, color: AppTheme.primaryTeal, size: 20),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      Navigator.pop(ctx);
                      _showEditContactNameDialog();
                    },
                    child: const Icon(Icons.edit_rounded, color: Colors.grey, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                isOtherUserOnline ? '\u{1F7E2} Online' : '\u{26AB} Offline',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.primaryTeal),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildContactActionButton(Icons.phone_rounded, 'Audio Call', () {
                    Navigator.pop(ctx);
                    _sendCallLink();
                  }),
                  _buildContactActionButton(Icons.videocam_rounded, 'Video Call', () {
                    Navigator.pop(ctx);
                    _sendCallLink();
                  }),
                  _buildContactActionButton(
                    isMuted ? Icons.notifications_active_rounded : Icons.notifications_off_rounded,
                    isMuted ? 'Unmute' : 'Mute',
                    () {
                      Navigator.pop(ctx);
                      _showMuteDialog();
                    },
                  ),
                ],
              ),
              const Divider(height: 32),
              ListTile(
                leading: const Icon(Icons.perm_identity_rounded, color: AppTheme.primaryTeal),
                title: const Text('Phone Number', style: TextStyle(fontWeight: FontWeight.w800)),
                subtitle: const Text('+1 (555) 019-2834', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
              ListTile(
                leading: const Icon(Icons.perm_media_rounded, color: AppTheme.primaryTeal),
                title: const Text('Media & Files', style: TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text('$mediaCount Photos â€¢ $fileCount Documents', style: const TextStyle(fontWeight: FontWeight.w600)),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MediaGalleryScreen(
                        currentUserId: widget.currentUserId,
                        conversationId: widget.conversationId,
                        peerName: peerDisplayName.isNotEmpty ? peerDisplayName : (widget.currentUserId == 1 ? 'Leslie' : 'User 1'),
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.lock_outline_rounded, color: AppTheme.primaryTeal),
                title: const Text('Encryption', style: TextStyle(fontWeight: FontWeight.w800)),
                subtitle: const Text('End-to-end encrypted', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
            ),
        ),
      );
    },
  );
  }

  Widget _buildContactActionButton(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.primaryTeal.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppTheme.primaryTeal, size: 24),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
        ],
      ),
    );
  }

  void _toggleInChatSearch() {
    setState(() {
      isSearchingInChat = !isSearchingInChat;
      if (!isSearchingInChat) {
        inChatSearchController.clear();
        inChatSearchQuery = '';
      }
    });
  }

  void _enableSelectMessages() {
    if (messages.isNotEmpty) {
      setState(() {
        selectedMessage = messages.last;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Message selection enabled. Tap or long-press messages to copy/delete.'),
          backgroundColor: AppTheme.primaryTeal,
        ),
      );
    }
  }

  void _showMuteDialog() {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Mute notifications', style: TextStyle(fontWeight: FontWeight.w900)),
        children: [
          SimpleDialogOption(
            onPressed: () {
              setState(() {
                isMuted = true;
                muteDuration = '8 Hours';
              });
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Notifications muted for 8 Hours'), backgroundColor: AppTheme.primaryTeal),
              );
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('8 Hours', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
          ),
          SimpleDialogOption(
            onPressed: () {
              setState(() {
                isMuted = true;
                muteDuration = '1 Week';
              });
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Notifications muted for 1 Week'), backgroundColor: AppTheme.primaryTeal),
              );
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('1 Week', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
          ),
          SimpleDialogOption(
            onPressed: () {
              setState(() {
                isMuted = true;
                muteDuration = 'Always';
              });
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Notifications muted Always'), backgroundColor: AppTheme.primaryTeal),
              );
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Always', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
          ),
          if (isMuted)
            SimpleDialogOption(
              onPressed: () {
                setState(() {
                  isMuted = false;
                  muteDuration = 'Off';
                });
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Notifications unmuted'), backgroundColor: AppTheme.primaryTeal),
                );
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Unmute', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Colors.redAccent)),
              ),
            ),
        ],
      ),
    );
  }



  void _toggleVanishMode(bool enable) {
    setState(() {
      isVanishMode = enable;
    });
    try {
      socket?.emit('toggleVanishMode', {
        'conversationId': widget.conversationId,
        'isVanishMode': isVanishMode,
        'senderId': widget.currentUserId,
      });
    } catch (_) {}

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isVanishMode ? Icons.auto_awesome_rounded : Icons.wb_sunny_rounded,
              color: isVanishMode ? const Color(0xFFE040FB) : Colors.amber,
            ),
            const SizedBox(width: 10),
            Text(
              isVanishMode ? "Vanish Mode ON ðŸ”® (Swipe up to turn off)" : "Vanish Mode OFF â˜€ï¸",
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ],
        ),
        backgroundColor: isVanishMode ? const Color(0xFF2C1338) : AppTheme.primaryTeal,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ==================================================
  // DISAPPEARING MESSAGES
  // ==================================================

  String _disappearingTimerLabel(int? seconds) {
    if (seconds == null || seconds <= 0) return 'Off';
    if (seconds == 24 * 3600) return '24 Hours';
    if (seconds == 7 * 24 * 3600) return '7 Days';
    if (seconds == 90 * 24 * 3600) return '90 Days';
    // Fallback for any custom value synced from elsewhere
    final days = seconds / (24 * 3600);
    if (days >= 1) return '${days.toStringAsFixed(0)} Days';
    final hours = seconds / 3600;
    return '${hours.toStringAsFixed(0)} Hours';
  }

  void _setDisappearingTimer(int? seconds) {
    socket?.emit('setDisappearingTimer', {
      'conversationId': widget.conversationId,
      'timerSeconds': seconds,
    });
    setState(() {
      disappearingTimerSeconds = seconds;
      disappearingTimer = _disappearingTimerLabel(seconds);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.timer_outlined, color: Colors.white),
            const SizedBox(width: 10),
            Text(
              seconds == null
                  ? "Disappearing messages turned OFF"
                  : "New messages will disappear after ${_disappearingTimerLabel(seconds)}",
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
        backgroundColor: AppTheme.primaryTeal,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showDisappearingTimerDialog() {
    final options = <String, int?>{
      'Off': null,
      '24 Hours': 24 * 3600,
      '7 Days': 7 * 24 * 3600,
      '90 Days': 90 * 24 * 3600,
    };

    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Row(
          children: [
            Icon(Icons.timer_outlined, color: AppTheme.primaryTeal),
            SizedBox(width: 8),
            Text('Disappearing Messages', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          ],
        ),
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Text(
              'Messages sent after turning this on will automatically delete for both of you.',
              style: TextStyle(fontSize: 12.5, color: Colors.grey),
            ),
          ),
          const SizedBox(height: 8),
          ...options.entries.map((entry) {
            final bool isSelected = disappearingTimerSeconds == entry.value;
            return SimpleDialogOption(
              onPressed: () {
                Navigator.pop(ctx);
                _setDisappearingTimer(entry.value);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                      color: isSelected ? AppTheme.primaryTeal : Colors.grey,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      entry.key,
                      style: TextStyle(
                        fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  void _toggleFavourites() {
    setState(() {
      isFavourite = !isFavourite;
    });
    final otherUserName = widget.currentUserId == 1 ? 'Leslie' : 'User 1';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(isFavourite ? 'Added $otherUserName to Favourites â¤ï¸' : 'Removed $otherUserName from Favourites'),
        backgroundColor: AppTheme.primaryTeal,
      ),
    );
  }

  void _showAddToListDialog() {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Add to list', style: TextStyle(fontWeight: FontWeight.w900)),
        children: ['Close Friends', 'Work', 'Family', 'Favorites', 'None'].map((category) {
          return SimpleDialogOption(
            onPressed: () {
              setState(() {
                customList = category;
              });
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Contact added to $category ðŸ–¼ï¸'), backgroundColor: AppTheme.primaryTeal),
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(category, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ),
          );
        }).toList(),
      ),
    );
  }

  void _exportChatTranscript() {
    final otherUserName = peerDisplayName.isNotEmpty ? peerDisplayName : (widget.currentUserId == 1 ? 'Leslie' : 'User 1');
    final StringBuffer transcript = StringBuffer();
    transcript.writeln("=== Clock History Export ===");
    transcript.writeln("Participant: $otherUserName");
    transcript.writeln("Export Date: ${DateTime.now()}\n");

    for (var m in messages) {
      final sender = m['isMe'] == true ? 'You' : otherUserName;
      final text = m['message'] ?? '';
      final time = m['time'] ?? '';
      transcript.writeln("[$time] $sender: $text");
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Export Chat', style: TextStyle(fontWeight: FontWeight.w900)),
        content: SizedBox(
          width: double.maxFinite,
          height: 250,
          child: SingleChildScrollView(
            child: SelectableText(
              transcript.toString(),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: transcript.toString()));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Chat transcript copied to clipboard! ðŸ“¥'), backgroundColor: AppTheme.primaryTeal),
              );
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Copy Transcript'),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryTeal, foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }

  void _showSafetyNumberDialog() async {
    final otherUserName = peerDisplayName.isNotEmpty ? peerDisplayName : (widget.currentUserId == 1 ? 'Leslie' : 'User 1');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const [
            Icon(Icons.verified_user_rounded, color: AppTheme.primaryTeal),
            SizedBox(width: 8),
            Text("E2EE Safety Number", style: TextStyle(fontWeight: FontWeight.w900)),
          ],
        ),
        content: FutureBuilder<http.Response>(
          future: () async {
            final headers = await AuthService.getAuthHeadersForUser(widget.currentUserId);
            return http.get(Uri.parse('$baseUrl/auth/safety-number/${widget.conversationId}'), headers: headers);
          }(),
          builder: (context, snapshot) {
            if (snapshot.hasData && snapshot.data!.statusCode == 200) {
              final data = jsonDecode(snapshot.data!.body);
              final safetyNum = data['safetyNumber'] ?? 'Pending...';
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "To verify end-to-end encryption with $otherUserName, compare the safety numbers below:",
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryTeal.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.primaryTeal.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      safetyNum,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        letterSpacing: 1.5,
                        color: AppTheme.primaryTeal,
                      ),
                    ),
                  ),
                ],
              );
            }
            return const SizedBox(
              height: 100,
              child: Center(child: CircularProgressIndicator(color: AppTheme.primaryTeal)),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  void _sendCallLink() {
    final callRoomId = 'room_${DateTime.now().millisecondsSinceEpoch}';
    final callLinkMsg = "ðŸ”— Join my DuoCall: https://duochat.call/$callRoomId";

    messageController.text = callLinkMsg;
    sendMessage();
  }

  Future<void> _scheduleCallPicker() async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(hours: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
    );

    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );

    if (pickedTime == null || !mounted) return;

    final scheduleText = "\u{1F4C5} Scheduled Duo Call for ${pickedDate.day}/${pickedDate.month}/${pickedDate.year} at ${pickedTime.format(context)}";
    messageController.text = scheduleText;
    sendMessage();
  }

  void _startNewGroupCall() {
    final otherUserName = peerDisplayName.isNotEmpty ? peerDisplayName : (widget.currentUserId == 1 ? 'Leslie' : 'User 1');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.group_add_rounded, color: AppTheme.primaryTeal),
            SizedBox(width: 8),
            Text('New Group Call', style: TextStyle(fontWeight: FontWeight.w900)),
          ],
        ),
        content: Text('Start an instant group call session with $otherUserName and participants?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _sendCallLink();
            },
            icon: const Icon(Icons.call_rounded),
            label: const Text('Start Call'),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryTeal, foregroundColor: Colors.white),
          ),
        ],
      ),
    );
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

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scrollController.hasClients) {
        scrollController.animateTo(
          scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _initFCM() async {
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);

      final token = await messaging.getToken();
      if (token != null) {
        await _sendFCMTokenToServer(token);
      }

      messaging.onTokenRefresh.listen((newToken) {
        _sendFCMTokenToServer(newToken);
      });

      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        _handleNotificationTap(message.data);
      });
    } catch (e) {
      // Silent Î“Ã‡Ã¶ FCM not configured or server offline
    }
  }

  Future<void> _sendFCMTokenToServer(String token) async {
    try {
      await http.post(
        Uri.parse('$baseUrl/auth/fcm-token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userId': widget.currentUserId,
          'fcmToken': token,
        }),
      );
    } catch (e) {
      // Silent Î“Ã‡Ã¶ server may be offline
    }
  }

  void _handleNotificationTap(Map<String, dynamic> data) {
    final rawConvId = data['conversationId'];
    if (rawConvId != null) {
      final targetConvId = int.tryParse(rawConvId.toString());
      if (targetConvId != null && targetConvId != widget.conversationId) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              currentUserId: widget.currentUserId,
              conversationId: targetConvId,
            ),
          ),
        );
      }
    }
  }

  Future<void> fetchUnreadCount() async {
    try {
      final headers = await AuthService.getAuthHeadersForUser(widget.currentUserId);
      final response = await http.get(
        Uri.parse('$baseUrl/messages/unread-count/${widget.conversationId}/${widget.currentUserId}'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        if (data['success'] == true && data['unreadCount'] != null) {
          if (!mounted) return;
          setState(() {
            unreadCount = int.parse(data['unreadCount'].toString());
          });
        }
      }
    } catch (e) {
      // Silent Î“Ã‡Ã¶ server may be offline
    }
  }

  Future<void> fetchMessages({
    bool showLoading = true,
  }) async {
    debugPrint("[CHAT] Loading conversation ID: ${widget.conversationId}");

    if (showLoading && messages.isEmpty) {
      setState(() {
        isLoading = true;
      });
    }

    try {
      var headers = await AuthService.getAuthHeadersForUser(widget.currentUserId);
      var response = await http.get(
        Uri.parse('$baseUrl/messages/${widget.conversationId}'),
        headers: headers,
      );

      // Auto-retry if token is invalid or expired
      if (response.statusCode == 401 || response.statusCode == 403) {
        final email = widget.currentUserId == 1 ? 'user1@example.com' : 'user2@example.com';
        final loginRes = await AuthService.login(email, 'password123');
        if (loginRes['success'] == true && loginRes['token'] != null) {
          headers = await AuthService.getAuthHeadersForUser(widget.currentUserId);
          response = await http.get(
            Uri.parse('$baseUrl/messages/${widget.conversationId}'),
            headers: headers,
          );
        }
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));

        if (data['success'] == true && data['data'] != null) {
          final List fetchedData = data['data'];
          debugPrint("[CHAT] Messages loaded from persistence: ${fetchedData.length}");

          final List<Map<String, dynamic>> parsedMessages = fetchedData.map<Map<String, dynamic>>((item) {
            final rawTime = item['created_at'] != null ? item['created_at'].toString() : '';
            final bool isRead = item['is_read'] == true || item['isRead'] == true;
            final bool isDelivered = isRead || item['is_delivered'] == true || item['isDelivered'] == true;
            final bool isEdited = item['is_edited'] == true || item['isEdited'] == true;
            final bool isDeleted = item['is_deleted'] == true || item['isDeleted'] == true;
            final nonce = item['nonce'];
            final isEncrypted = item['is_encrypted'] == true || item['isEncrypted'] == true;

            final replyToMessageId = item['reply_to_message_id'] ?? item['replyToMessageId'];
            final replySenderId = item['reply_sender_id'] ?? item['replySenderId'];
            final replySenderName = item['reply_sender_name'] ?? item['replySenderName'];
            final replyMessage = item['reply_message'] ?? item['replyMessage'];
            final replyAttachmentType = item['reply_attachment_type'] ?? item['replyAttachmentType'];
            final replyAttachmentName = item['reply_attachment_name'] ?? item['replyAttachmentName'];
            final bool replyIsDeleted = item['reply_is_deleted'] == true;

            final reactions = item['reactions'] is Map
                ? Map<String, dynamic>.from(item['reactions'])
                : <String, dynamic>{};

            final bool isPinnedItem = item['is_pinned'] == true;
            final bool liveStillActive = item['live_location_active'] == true;

            String rawText = (item['message'] ?? '').toString();
            // Live-location messages: the server keeps the last JSON payload with
            // isLive:true even after sharing ends, so trust the DB flag instead.
            if ((item['attachment_type'] ?? item['attachmentType']) == 'location' && !liveStillActive) {
              try {
                final locJson = jsonDecode(rawText);
                if (locJson is Map && locJson['isLive'] == true) {
                  locJson['isLive'] = false;
                  rawText = jsonEncode(locJson);
                }
              } catch (_) {}
            }

            final msgId = item['id'];
            final decryptedText = isDeleted
                ? 'This message was deleted'
                : _decryptMessageIfNeeded(msgId, rawText, nonce, isEncrypted);

            return <String, dynamic>{
              'id': msgId,
              'message': decryptedText,
              'nonce': nonce,
              'isEncrypted': isEncrypted,
              'is_encrypted': isEncrypted,
              'attachmentUrl': item['attachment_url'] ?? item['attachmentUrl'],
              'attachmentType': item['attachment_type'] ?? item['attachmentType'],
              'attachmentName': item['attachment_name'] ?? item['attachmentName'],
              'attachmentSize': item['attachment_size'] ?? item['attachmentSize'],
              'replyToMessageId': replyToMessageId,
              'reply_to_message_id': replyToMessageId,
              'replySenderId': replySenderId,
              'reply_sender_id': replySenderId,
              'replySenderName': replySenderName,
              'reply_sender_name': replySenderName,
              'replyMessage': replyMessage,
              'reply_message': replyMessage,
              'replyAttachmentType': replyAttachmentType,
              'reply_attachment_type': replyAttachmentType,
              'replyAttachmentName': replyAttachmentName,
              'reply_attachment_name': replyAttachmentName,
              'replyIsDeleted': replyIsDeleted,
              'reply_is_deleted': replyIsDeleted,
              // Strict message ownership based on senderId
              'isMe': (item['sender_id'] ?? item['senderId']) != null &&
                     int.parse((item['sender_id'] ?? item['senderId']).toString()) == widget.currentUserId,
              'isDelivered': isDelivered,
              'is_delivered': isDelivered,
              'isRead': isRead,
              'is_read': isRead,
              'isEdited': isEdited,
              'is_edited': isEdited,
              'isDeleted': isDeleted,
              'is_deleted': isDeleted,
              'reactions': reactions,
              'isPinned': isPinnedItem,
              'time': _formatTime(rawTime),
            };
          }).toList();

          debugPrint("=== HISTORY MESSAGE CHECK ===");
          if (parsedMessages.isNotEmpty) {
            final testMsg = parsedMessages.last;
            debugPrint("Message ID: ${testMsg['id']}");
            debugPrint("currentUserId: ${widget.currentUserId}");
            debugPrint("sender_id (raw): ${fetchedData.last['sender_id']}");
            debugPrint("senderId (raw): ${fetchedData.last['senderId']}");
            debugPrint("isMe: ${testMsg['isMe']}");
          }
          debugPrint("=============================");

          if (!mounted) return;

          setState(() {
            messages.clear();
            messages.addAll(parsedMessages);
            isLoading = false;

            // Restore the pinned-message banner after an app restart / reload
            pinnedMessage = null;
            for (final raw in fetchedData) {
              if (raw['is_pinned'] == true && raw['is_deleted'] != true) {
                pinnedMessage = Map<String, dynamic>.from(raw as Map);
                break;
              }
            }
          });

          _scrollToBottom();
          _markDelivered();
          _markSeen();
        } else {
          if (mounted) setState(() => isLoading = false);
        }
      } else {
        if (mounted) setState(() => isLoading = false);
      }
    } catch (e) {
      // Silent Î“Ã‡Ã¶ server may be offline
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  // =========================
  // BULLETPROOF ATTACHMENT ACTIONS & INSTANT PREVIEW
  // =========================

  void _showPermissionDeniedDialog({
    required String title,
    required String message,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF128C7E),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            child: const Text("Open Settings"),
          ),
        ],
      ),
    );
  }

  Future<void> _pickFromCamera() async {
    debugPrint("OPENING CAMERA");

    // 1. Request Camera runtime permission via permission_handler
    PermissionStatus status;
    try {
      status = await Permission.camera.request();
      debugPrint("CAMERA PERMISSION STATUS: $status");
    } catch (e, stackTrace) {
      debugPrint("CAMERA PERMISSION REQUEST EXCEPTION (Native Channel Not Recompiled Yet): $e");
      debugPrint("CAMERA PERMISSION STACK TRACE: $stackTrace");

      // Fallback: If permission_handler channel is missing (needs flutter run rebuild), attempt ImagePicker directly
      try {
        debugPrint("FALLING BACK DIRECTLY TO IMAGE PICKER CAMERA...");
        final picker = ImagePicker();
        final XFile? image = await picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 85,
        );
        debugPrint("CAMERA FALLBACK RESULT: $image");
        if (image != null) {
          _showImagePreviewDialog(image);
        }
        return;
      } catch (e2, stackTrace2) {
        debugPrint("CAMERA DIRECT FALLBACK ERROR: $e2");
        debugPrint("CAMERA DIRECT FALLBACK STACK TRACE: $stackTrace2");
        _showErrorSnackBar("Please stop app in terminal and run 'flutter run' to apply native plugins.");
        return;
      }
    }

    if (status.isGranted) {
      try {
        final picker = ImagePicker();
        final XFile? image = await picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 85,
        );
        debugPrint("CAMERA RESULT: $image");
        if (image != null) {
          _showImagePreviewDialog(image);
        } else {
          debugPrint("CAMERA CANCELLED BY USER");
        }
      } catch (e, stackTrace) {
        debugPrint("CAMERA PICKER ERROR: $e");
        debugPrint("CAMERA PICKER STACK TRACE: $stackTrace");
        _showErrorSnackBar("Could not open camera: $e");
      }
    } else if (status.isPermanentlyDenied || status.isRestricted) {
      debugPrint("CAMERA PERMISSION PERMANENTLY DENIED");
      _showPermissionDeniedDialog(
        title: "Camera Permission Required",
        message: "Camera access has been permanently denied. Please grant Camera permission in App Settings to take photos.",
      );
    } else if (status.isDenied) {
      debugPrint("CAMERA PERMISSION DENIED");
      _showErrorSnackBar("Camera permission denied. Please allow Camera access to take photos.");
    } else {
      debugPrint("CAMERA PERMISSION UNKNOWN STATUS: ${status.name}");
      _showErrorSnackBar("Camera permission status: ${status.name}");
    }
  }

  Future<void> _pickFromGallery() async {
    debugPrint("OPENING GALLERY");

    // Primary Attempt: ImagePicker gallery
    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      debugPrint("GALLERY RESULT (ImagePicker): $image");
      if (image != null) {
        _showImagePreviewDialog(image);
        return;
      }
      debugPrint("GALLERY CANCELLED BY USER (ImagePicker)");
      return;
    } catch (e, stackTrace) {
      debugPrint("GALLERY IMAGE PICKER ERROR: $e");
      debugPrint("GALLERY IMAGE PICKER STACK TRACE: $stackTrace");
    }

    // Fallback: FilePicker (SAF / System Photo Picker)
    try {
      debugPrint("TRYING GALLERY FALLBACK VIA FILE PICKER...");
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );
      debugPrint("GALLERY RESULT (FilePicker): $result");
      if (result != null && result.files.isNotEmpty) {
        final platformFile = result.files.first;
        final bytes = platformFile.bytes;
        final name = platformFile.name;
        final path = kIsWeb ? null : platformFile.path;

        if (bytes != null || path != null) {
          final xfile = bytes != null
              ? XFile.fromData(bytes, name: name)
              : XFile(path!, name: name);
          _showImagePreviewDialog(xfile);
          return;
        }
      }
      debugPrint("GALLERY CANCELLED BY USER (FilePicker)");
    } catch (e2, stackTrace2) {
      debugPrint("GALLERY FILE PICKER FALLBACK ERROR: $e2");
      debugPrint("GALLERY FILE PICKER FALLBACK STACK TRACE: $stackTrace2");
      _showErrorSnackBar("Could not open gallery: $e2");
    }
  }

  Future<void> _pickFile() async {
    debugPrint("OPENING FILE PICKER");

    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: true,
      );
      debugPrint("FILE PICKER RESULT: $result");
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        final bytes = file.bytes;
        final path = kIsWeb ? null : file.path;

        if (bytes != null || path != null) {
          debugPrint("SELECTED FILE: ${file.name} (size: ${file.size})");
          _uploadAndSendFile(
            filePath: path,
            fileBytes: bytes,
            fileName: file.name,
            attachmentType: 'file',
            fileSize: file.size,
          );
        }
      } else {
        debugPrint("FILE PICKER CANCELLED BY USER");
      }
    } catch (e, stackTrace) {
      debugPrint("FILE PICKER ERROR: $e");
      debugPrint("FILE PICKER STACK TRACE: $stackTrace");
      _showErrorSnackBar("Could not open file picker: $e");
    }
  }

  // ==================================================
  // LIVE LOCATION SHARING
  // ==================================================

  Future<bool> _ensureLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showErrorSnackBar("Please turn on Location Services to share your location");
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _showErrorSnackBar("Location permission denied");
        return false;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      _showPermissionDeniedDialog(
        title: "Location Permission Required",
        message: "Location access has been permanently denied. Please grant it in App Settings to share your location.",
      );
      return false;
    }
    return true;
  }

  void _showLocationShareSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1F2C33) : Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2)),
                ),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: AppTheme.primaryTeal,
                    child: Icon(Icons.location_on_rounded, color: Colors.white),
                  ),
                  title: const Text('Share current location', style: TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: const Text('Send your location once, right now'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _shareLocation(durationSeconds: null);
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFF0F766E),
                    child: Icon(Icons.my_location_rounded, color: Colors.white),
                  ),
                  title: const Text('Share live location — 15 min', style: TextStyle(fontWeight: FontWeight.w800)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _shareLocation(durationSeconds: 15 * 60);
                  },
                ),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFF0F766E),
                    child: Icon(Icons.my_location_rounded, color: Colors.white),
                  ),
                  title: const Text('Share live location — 1 hour', style: TextStyle(fontWeight: FontWeight.w800)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _shareLocation(durationSeconds: 60 * 60);
                  },
                ),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFF0F766E),
                    child: Icon(Icons.my_location_rounded, color: Colors.white),
                  ),
                  title: const Text('Share live location — 8 hours', style: TextStyle(fontWeight: FontWeight.w800)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _shareLocation(durationSeconds: 8 * 60 * 60);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _shareLocation({int? durationSeconds}) async {
    if (_isSharingLiveLocation) {
      _showErrorSnackBar("You're already sharing your live location");
      return;
    }

    final hasPermission = await _ensureLocationPermission();
    if (!hasPermission) return;

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );

      final isLive = durationSeconds != null && durationSeconds > 0;
      final payload = jsonEncode({'lat': position.latitude, 'lng': position.longitude, 'isLive': isLive});
      final tempMsgId = 'temp_${DateTime.now().millisecondsSinceEpoch}';

      final tempLocationMsg = {
        'id': tempMsgId,
        'senderId': widget.currentUserId,
        'sender_id': widget.currentUserId,
        'message': payload,
        'attachmentType': 'location',
        'attachment_type': 'location',
        'isMe': true,
        'isDelivered': true,
        'isRead': false,
        'time': _formatTime(DateTime.now().toIso8601String()),
      };

      if (mounted) {
        setState(() {
          if (isLive) {
            _isSharingLiveLocation = true;
            _activeLiveLocationMessageId = null; // learned once the server echoes newMessage
            _liveLocationEndTime = DateTime.now().add(Duration(seconds: durationSeconds));
          }
          messages.add(tempLocationMsg);
        });
        _scrollToBottom();
      }

      socket?.emit('shareLiveLocation', {
        'conversationId': widget.conversationId,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'durationSeconds': durationSeconds,
      });

      if (!isLive) {
        _showErrorSnackBar("Location shared ✅");
      }
    } catch (e) {
      debugPrint("Error sharing location: $e");
      _showErrorSnackBar("Could not get your current location: $e");
      if (mounted) {
        setState(() {
          _isSharingLiveLocation = false;
        });
      }
    }
  }

  void _startLiveLocationUpdateTimer() {
    _liveLocationTimer?.cancel();
    _liveLocationTimer = Timer.periodic(const Duration(seconds: 15), (timer) async {
      if (!_isSharingLiveLocation || _activeLiveLocationMessageId == null) {
        timer.cancel();
        return;
      }
      // Auto-stop once the chosen duration has elapsed (server also enforces this)
      if (_liveLocationEndTime != null && DateTime.now().isAfter(_liveLocationEndTime!)) {
        _stopSharingLiveLocation();
        return;
      }
      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
        );
        socket?.emit('updateLiveLocation', {
          'conversationId': widget.conversationId,
          'messageId': _activeLiveLocationMessageId,
          'latitude': position.latitude,
          'longitude': position.longitude,
        });
      } catch (e) {
        debugPrint("Error updating live location: $e");
      }
    });
  }

  void _stopSharingLiveLocation() {
    if (_activeLiveLocationMessageId != null) {
      socket?.emit('stopLiveLocation', {
        'conversationId': widget.conversationId,
        'messageId': _activeLiveLocationMessageId,
      });
    }
    _stopSharingLiveLocationLocal();
  }

  void _stopSharingLiveLocationLocal() {
    _liveLocationTimer?.cancel();
    _liveLocationTimer = null;
    if (mounted) {
      setState(() {
        _isSharingLiveLocation = false;
        _activeLiveLocationMessageId = null;
        _liveLocationEndTime = null;
      });
    }
  }

  Future<void> _openLocationInMaps(double lat, double lng) async {
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint("Error opening maps: $e");
      _showErrorSnackBar("Could not open maps");
    }
  }

  void _showImagePreviewDialog(XFile image) {
    final captionController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: SafeArea(
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                  const Text(
                    "Send Image",
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: FutureBuilder<Uint8List>(
                    future: image.readAsBytes(),
                    builder: (context, snapshot) {
                      if (snapshot.hasData) {
                        return Image.memory(
                          snapshot.data!,
                          fit: BoxFit.contain,
                        );
                      }
                      return const Center(
                        child: CircularProgressIndicator(color: AppTheme.primaryTeal),
                      );
                    },
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                color: Colors.black87,
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: captionController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: "Add a caption...",
                          hintStyle: TextStyle(color: Colors.grey.shade400),
                          filled: true,
                          fillColor: Colors.grey.shade900,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: const Color(0xFF128C7E),
                      child: IconButton(
                        icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                        onPressed: () async {
                          Navigator.pop(ctx);
                          final bytes = await image.readAsBytes();
                          final path = kIsWeb ? null : image.path;
                          _uploadAndSendFile(
                            filePath: path,
                            fileBytes: bytes,
                            fileName: image.name,
                            attachmentType: 'image',
                            caption: captionController.text.trim(),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _uploadAndSendFile({
    String? filePath,
    Uint8List? fileBytes,
    required String fileName,
    required String attachmentType,
    int? fileSize,
    String caption = '',
  }) async {
    final tempMsgId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final int? replyId = replyingToMessage?['id'] != null
        ? int.tryParse(replyingToMessage!['id'].toString())
        : null;

    final tempMessageMap = {
      'id': tempMsgId,
      'senderId': widget.currentUserId,
      'message': caption,
      'attachmentUrl': filePath ?? fileName,
      'isLocalFile': true,
      'attachmentType': attachmentType,
      'attachmentName': fileName,
      'attachmentSize': fileSize ?? fileBytes?.length,
      'replyToMessageId': replyId,
      'isMe': true,
      'isUploading': true,
      'isDelivered': false,
      'isRead': false,
      'time': _formatTime(DateTime.now().toIso8601String()),
    };

    setState(() {
      messages.add(tempMessageMap);
      replyingToMessage = null;
    });
    _scrollToBottom();

    try {
      final uri = Uri.parse('$baseUrl/messages/upload');
      final request = http.MultipartRequest('POST', uri);
      final token = await AuthService.getTokenForUser(widget.currentUserId);
      if (token != null && token.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      Uint8List? uploadBytes = fileBytes;
      if (uploadBytes == null && filePath != null && !kIsWeb) {
        uploadBytes = await File(filePath).readAsBytes();
      }

      request.fields['conversationId'] = widget.conversationId.toString();
      request.fields['senderId'] = widget.currentUserId.toString();
      request.fields['message'] = caption;
      request.fields['attachmentType'] = attachmentType;
      request.fields['isEncrypted'] = 'false';
      if (replyId != null) {
        request.fields['replyToMessageId'] = replyId.toString();
      }

      if (uploadBytes != null) {
        request.files.add(
          http.MultipartFile.fromBytes(
            'file',
            uploadBytes,
            filename: fileName,
          ),
        );
      } else if (filePath != null) {
        request.files.add(
          await http.MultipartFile.fromPath(
            'file',
            filePath,
            filename: fileName,
          ),
        );
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 201) {
        final resData = jsonDecode(utf8.decode(response.bodyBytes));
        if (resData['success'] == true && resData['data'] != null) {
          final msgData = resData['data'];

          if (mounted) {
            setState(() {
              final idx = messages.indexWhere((m) => m['id'] == tempMsgId);
              if (idx != -1) {
                messages[idx] = {
                  'id': msgData['id'],
                  'message': caption,
                  'nonce': msgData['nonce'],
                  'isEncrypted': false,
                  'is_encrypted': false,
                  'attachmentUrl': msgData['attachment_url'],
                  'attachmentType': msgData['attachment_type'],
                  'attachmentName': msgData['attachment_name'],
                  'attachmentSize': msgData['attachment_size'],
                  'replyToMessageId': replyId,
                  'isMe': true,
                  'isUploading': false,
                  'isDelivered': msgData['is_delivered'] == true,
                  'is_delivered': msgData['is_delivered'] == true,
                  'isRead': msgData['is_read'] == true,
                  'is_read': msgData['is_read'] == true,
                  'time': _formatTime(msgData['created_at']?.toString() ?? DateTime.now().toIso8601String()),
                };
              }
            });
          }

          socket?.emit('sendMessage', {
            'conversationId': widget.conversationId,
            'senderId': widget.currentUserId,
            'message': msgData['message'] ?? caption,
            'attachmentUrl': msgData['attachment_url'],
            'attachmentType': msgData['attachment_type'],
            'attachmentName': msgData['attachment_name'],
            'attachmentSize': msgData['attachment_size'],
            'replyToMessageId': replyId,
            'tempMsgId': tempMsgId,
            'messageId': msgData['id'],
            'nonce': msgData['nonce'],
            'isEncrypted': false,
            'isAlreadySaved': true,
          });
        }
      } else {
        _showErrorSnackBar("Upload failed");
      }
    } catch (e) {
      debugPrint("Error uploading attachment: $e");
      _showErrorSnackBar("Failed to send attachment");
    }
  }

  void _showAttachmentGridSheet() {
    debugPrint("ATTACHMENT BUTTON CLICKED");
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        debugPrint("BOTTOM SHEET OPENED");
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x25000000),
                  blurRadius: 16,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 24),
                Wrap(
                  alignment: WrapAlignment.spaceEvenly,
                  runSpacing: 8,
                  children: [
                    _buildAttachmentGridItem(
                      icon: Icons.camera_alt_rounded,
                      label: "Camera",
                      color: const Color(0xFFAC44CF),
                      onTap: () {
                        debugPrint("CAMERA OPTION CLICKED");
                        Navigator.pop(ctx);
                        _pickFromCamera();
                      },
                    ),
                    _buildAttachmentGridItem(
                      icon: Icons.photo_library_rounded,
                      label: "Gallery",
                      color: const Color(0xFF00C853),
                      onTap: () {
                        debugPrint("GALLERY OPTION CLICKED");
                        Navigator.pop(ctx);
                        _pickFromGallery();
                      },
                    ),
                    _buildAttachmentGridItem(
                      icon: Icons.insert_drive_file_rounded,
                      label: "Document",
                      color: const Color(0xFF0288D1),
                      onTap: () {
                        debugPrint("FILE OPTION CLICKED");
                        Navigator.pop(ctx);
                        _pickFile();
                      },
                    ),
                    _buildAttachmentGridItem(
                      icon: Icons.location_on_rounded,
                      label: "Location",
                      color: const Color(0xFFE53935),
                      onTap: () {
                        debugPrint("LOCATION OPTION CLICKED");
                        Navigator.pop(ctx);
                        _showLocationShareSheet();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAttachmentGridItem({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 28),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatFileSize(dynamic bytes) {
    if (bytes == null) return '';
    final int b = int.tryParse(bytes.toString()) ?? 0;
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  void _startEditing(Map<String, dynamic> messageMap) {
    if (messageMap['isMe'] != true ||
        messageMap['isDeleted'] == true ||
        messageMap['is_deleted'] == true ||
        messageMap['attachmentUrl'] != null) {
      return;
    }
    setState(() {
      editingMessageId = messageMap['id'];
      messageController.text = messageMap['message'] ?? '';
      replyingToMessage = null;
      selectedMessage = null;
    });
  }

  void _cancelEditing() {
    setState(() {
      editingMessageId = null;
      messageController.clear();
    });
  }

  void _confirmDelete(Map<String, dynamic> messageMap) {
    if (messageMap['isMe'] != true ||
        messageMap['isDeleted'] == true ||
        messageMap['is_deleted'] == true) {
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Delete Message"),
        content: const Text("Delete this message for everyone?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => selectedMessage = null);
              socket?.emit('deleteMessage', {
                'conversationId': widget.conversationId,
                'messageId': messageMap['id'],
                'senderId': widget.currentUserId,
              });
            },
            child: const Text("Delete"),
          ),
        ],
      ),
    );
  }

  Future<void> sendMessage() async {
    final text = messageController.text.trim();
    if (text.isEmpty) return;

    _stopTypingEmit();

    if (editingMessageId != null) {
      socket?.emit('editMessage', {
        'conversationId': widget.conversationId,
        'messageId': editingMessageId,
        'senderId': widget.currentUserId,
        'newMessage': text,
      });
      setState(() {
        editingMessageId = null;
      });
      messageController.clear();
    } else {
      final int? replyId = replyingToMessage?['id'] != null
          ? int.tryParse(replyingToMessage!['id'].toString())
          : null;

      final String tempMsgId = 'temp_${DateTime.now().millisecondsSinceEpoch}';

      final optimisticMsg = {
        'id': tempMsgId,
        'senderId': widget.currentUserId,
        'message': text,
        'attachmentUrl': null,
        'attachmentType': null,
        'attachmentName': null,
        'attachmentSize': null,
        'replyToMessageId': replyId,
        'reply_to_message_id': replyId,
        'replySenderId': replyingToMessage?['sender_id'] ?? replyingToMessage?['senderId'],
        'replySenderName': replyingToMessage?['sender_name'] ?? replyingToMessage?['senderName'],
        'replyMessage': replyingToMessage?['message'],
        'replyAttachmentType': replyingToMessage?['attachmentType'] ?? replyingToMessage?['attachment_type'],
        'replyAttachmentName': replyingToMessage?['attachmentName'] ?? replyingToMessage?['attachment_name'],
        'replyIsDeleted': replyingToMessage?['isDeleted'] == true || replyingToMessage?['is_deleted'] == true,
        'isMe': true,
        'isDelivered': false,
        'isRead': false,
        'isEdited': false,
        'isDeleted': false,
        'reactions': {},
        'time': _formatTime(DateTime.now().toIso8601String()),
      };

      setState(() {
        messages.add(optimisticMsg);
      });
      _scrollToBottom();

      debugPrint('[CHAT SOCKET] SEND MESSAGE: $text');
      socket?.emit('sendMessage', {
        'conversationId': widget.conversationId,
        'senderId': widget.currentUserId,
        'message': text,
        'nonce': null,
        'isEncrypted': false,
        'replyToMessageId': replyId,
        'tempMsgId': tempMsgId,
      });
    }

    _cancelReplying();
    messageController.clear();
  }


  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final otherUserName = peerDisplayName.isNotEmpty ? peerDisplayName : (widget.currentUserId == 1 ? 'Leslie' : 'User 1');

    final Color scaffoldBg = isVanishMode
        ? const Color(0xFF0D0B14)
        : (isDark ? const Color(0xFF121E24) : const Color(0xFFF5F7F8));

    return Scaffold(
      backgroundColor: scaffoldBg,
      body: Stack(
        children: [
          // Modern Romantic Wallpaper Background for Both Users
          Positioned.fill(
            child: Image.asset(
              'assets/images/chat_wallpaper.jpg',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(color: scaffoldBg),
            ),
          ),
          // Subtle tint overlay for enhanced text readability and bubble contrast
          Positioned.fill(
            child: Container(
              color: (isDark ? Colors.black : const Color(0xFF0F1A1C)).withValues(alpha: 0.42),
            ),
          ),
          SafeArea(
            top: false,
            child: Column(
              children: [
            // Wave Header App Bar
            if (selectedMessage != null)
              Container(
                height: 95,
                padding: const EdgeInsets.only(top: 40, left: 12, right: 12),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0F766E), Color(0xFF149B9B)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                      onPressed: () => setState(() => selectedMessage = null),
                    ),
                    const Text(
                      "1 Selected",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.reply_rounded, color: Colors.white),
                      tooltip: 'Reply',
                      onPressed: () => _startReplying(selectedMessage!),
                    ),
                    if (selectedMessage!['isDeleted'] != true)
                      IconButton(
                        icon: Icon(
                          (pinnedMessage != null && pinnedMessage!['id'].toString() == selectedMessage!['id'].toString())
                              ? Icons.push_pin_rounded
                              : Icons.push_pin_outlined,
                          color: Colors.white,
                        ),
                        tooltip: (pinnedMessage != null && pinnedMessage!['id'].toString() == selectedMessage!['id'].toString())
                            ? 'Unpin'
                            : 'Pin',
                        onPressed: () => _togglePinMessage(selectedMessage!),
                      ),
                    if (selectedMessage!['message'] != null && selectedMessage!['message'].toString().isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.copy_rounded, color: Colors.white),
                        tooltip: 'Copy',
                        onPressed: () {
                          _copyToClipboard(selectedMessage!['message'].toString());
                          setState(() => selectedMessage = null);
                        },
                      ),
                    if (selectedMessage!['isMe'] == true &&
                        selectedMessage!['attachmentUrl'] == null &&
                        selectedMessage!['isDeleted'] != true)
                      IconButton(
                        icon: const Icon(Icons.edit_rounded, color: Colors.white),
                        tooltip: 'Edit',
                        onPressed: () => _startEditing(selectedMessage!),
                      ),
                    if (selectedMessage!['isMe'] == true && selectedMessage!['isDeleted'] != true)
                      IconButton(
                        icon: const Icon(Icons.delete_rounded, color: Colors.white),
                        tooltip: 'Delete',
                        onPressed: () => _confirmDelete(selectedMessage!),
                      ),
                  ],
                ),
              )
            else
              ClipPath(
                clipper: WaveHeaderClipper(),
                child: Container(
                  padding: const EdgeInsets.only(top: 45, left: 16, right: 16, bottom: 6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isVanishMode
                          ? [const Color(0xFF4A148C), const Color(0xFF8E24AA), const Color(0xFFC2185B)]
                          : [const Color(0xFF0F766E), const Color(0xFF149B9B), const Color(0xFF0D8383)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Row(
                    children: [
                      // Back button
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 22),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 2),
                      // Peer info (takes all remaining space)
                      Expanded(
                        child: GestureDetector(
                          onTap: _showContactInfo,
                          behavior: HitTestBehavior.opaque,
                          child: Row(
                            children: [
                              Stack(
                                children: [
                                  CircleAvatar(
                                    radius: 17,
                                    backgroundColor: Colors.white24,
                                    backgroundImage: _getAvatarImageProvider(peerAvatarPath, peerAvatarUrl),
                                    child: _getAvatarImageProvider(peerAvatarPath, peerAvatarUrl) == null
                                        ? Text(
                                            otherUserName.isNotEmpty ? otherUserName.substring(0, 1).toUpperCase() : 'U',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w900,
                                              fontSize: 15,
                                            ),
                                          )
                                        : null,
                                  ),
                                  if (isOtherUserOnline)
                                    Positioned(
                                      right: 0,
                                      bottom: 0,
                                      child: Container(
                                        width: 9,
                                        height: 9,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF00E676),
                                          shape: BoxShape.circle,
                                          border: Border.all(color: Colors.white, width: 1.5),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Flexible(
                                          child: Text(
                                            otherUserName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w900,
                                              color: Colors.white,
                                              letterSpacing: 0.1,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 3),
                                        const Icon(Icons.verified_rounded, color: Colors.white70, size: 14),
                                      ],
                                    ),
                                    Text(
                                      isOtherUserTyping
                                          ? typingText
                                          : (isOtherUserOnline ? 'online' : (otherUserLastSeenText ?? 'offline')),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isOtherUserTyping
                                            ? const Color(0xFFFFE082)
                                            : (isOtherUserOnline ? const Color(0xFFA7FFEB) : Colors.white70),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                       IconButton(
                         padding: EdgeInsets.zero,
                         constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                         icon: const Icon(Icons.call_rounded, color: Colors.white, size: 19),
                         tooltip: 'Audio Call',
                         onPressed: () => _openCallScreen(isVideoCall: false, isCaller: true),
                       ),
                       IconButton(
                         padding: EdgeInsets.zero,
                         constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                         icon: const Icon(Icons.videocam_rounded, color: Colors.white, size: 20),
                         tooltip: 'Video Call',
                         onPressed: () => _openCallScreen(isVideoCall: true, isCaller: true),
                       ),
                       IconButton(
                         padding: EdgeInsets.zero,
                         constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                         icon: const Icon(Icons.more_vert_rounded, color: Colors.white, size: 22),
                         tooltip: 'Menu',
                         onPressed: _showThreeDotsMenu,
                       ),
                    ],
                  ),
                ),
              ),

            // NEW: Pinned Message Banner
            if (pinnedMessage != null)
              InkWell(
                onTap: () => _scrollToMessage(pinnedMessage!['id']),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  color: isDark ? const Color(0xFF1A252B) : const Color(0xFFE9EDEF),
                  child: Row(
                    children: [
                      const Icon(Icons.push_pin_rounded, color: AppTheme.primaryTeal, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Pinned Message',
                              style: TextStyle(color: AppTheme.primaryTeal, fontWeight: FontWeight.w900, fontSize: 11.5),
                            ),
                            Text(
                              pinnedMessage!['attachment_type'] == 'image'
                                  ? '📷 Photo'
                                  : pinnedMessage!['attachment_type'] == 'audio'
                                      ? '🎤 Voice message'
                                      : pinnedMessage!['attachment_type'] == 'file'
                                          ? '📎 ${pinnedMessage!['attachment_name'] ?? 'File'}'
                                          : pinnedMessage!['attachment_type'] == 'location'
                                              ? '📍 Location'
                                              : (pinnedMessage!['message']?.toString().isNotEmpty == true ? pinnedMessage!['message'].toString() : 'Message'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: isDark ? Colors.white : const Color(0xFF111B21)),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close_rounded, size: 18, color: isDark ? Colors.white70 : const Color(0xFF54656F)),
                        onPressed: () => _togglePinMessage(pinnedMessage!),
                      ),
                    ],
                  ),
                ),
              ),

            // In-Chat Live Search Bar Overlay
            if (isSearchingInChat)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1F2C33) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(color: Color(0x15000000), blurRadius: 6, offset: Offset(0, 2)),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search_rounded, color: AppTheme.primaryTeal, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: inChatSearchController,
                        autofocus: true,
                        style: TextStyle(
                          color: isDark ? Colors.white : const Color(0xFF111B21),
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                        onChanged: (q) {
                          setState(() {
                            inChatSearchQuery = q.toLowerCase().trim();
                          });
                        },
                        decoration: const InputDecoration(
                          hintText: 'Search in conversation...',
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: _toggleInChatSearch,
                    ),
                  ],
                ),
              ),

            // Message List with Instagram Swipe-Up Drag Gesture
            Expanded(
              child: GestureDetector(
                onVerticalDragUpdate: (details) {
                  if (details.delta.dy < -1) {
                    setState(() {
                      vanishDragOffset += (-details.delta.dy);
                      if (vanishDragOffset > 100) vanishDragOffset = 100;
                      isVanishThresholdReached = vanishDragOffset >= 65;
                    });
                  } else if (details.delta.dy > 1 && vanishDragOffset > 0) {
                    setState(() {
                      vanishDragOffset -= details.delta.dy;
                      if (vanishDragOffset < 0) vanishDragOffset = 0;
                      isVanishThresholdReached = vanishDragOffset >= 65;
                    });
                  }
                },
                onVerticalDragEnd: (_) {
                  if (isVanishThresholdReached) {
                    _toggleVanishMode(!isVanishMode);
                  }
                  setState(() {
                    vanishDragOffset = 0.0;
                    isVanishThresholdReached = false;
                  });
                },
                child: isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: AppTheme.primaryTeal),
                      )
                    : Column(
                        children: [
                          // Instagram Vanish Mode Banner Header
                          if (isVanishMode)
                            Container(
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    const Color(0xFF3B1556).withValues(alpha: 0.9),
                                    const Color(0xFF180A2B).withValues(alpha: 0.9),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: const Color(0xFFE040FB).withValues(alpha: 0.6), width: 1.5),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF9C27B0).withValues(alpha: 0.4),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFE040FB),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 18),
                                  ),
                                  const SizedBox(width: 12),
                                  const Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Vanish mode is ON ðŸ”®',
                                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14),
                                        ),
                                        SizedBox(height: 2),
                                        Text(
                                          'Seen messages will disappear when you exit Vanish mode.',
                                          style: TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w600),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          // Disappearing Messages Banner Header
                          if (disappearingTimerSeconds != null)
                            Container(
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryTeal.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: AppTheme.primaryTeal.withValues(alpha: 0.4), width: 1.2),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: const BoxDecoration(
                                      color: AppTheme.primaryTeal,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.timer_outlined, color: Colors.white, size: 18),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Disappearing messages are ON — new messages vanish after $disappearingTimer',
                                      style: const TextStyle(
                                        color: AppTheme.primaryTeal,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          // "On This Day" Memories Banner
                          if (showOnThisDayBanner && onThisDayMemories.isNotEmpty)
                            Container(
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.amber.withValues(alpha: 0.18),
                                    Colors.orange.withValues(alpha: 0.10),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.amber.withValues(alpha: 0.5), width: 1.2),
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: _showOnThisDayDialog,
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: const BoxDecoration(color: Colors.amber, shape: BoxShape.circle),
                                      child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 18),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        'On this day — ${onThisDayMemories.length} memor${onThisDayMemories.length == 1 ? "y" : "ies"} to look back on. Tap to view.',
                                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.close_rounded, size: 18),
                                      onPressed: () => setState(() => showOnThisDayBanner = false),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                          // Centered Today Label (no border, no background)
                        Padding(
                          padding: const EdgeInsets.only(top: 8, bottom: 4),
                          child: Text(
                            'Today',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
                            ),
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            controller: scrollController,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                            itemCount: inChatSearchQuery.isEmpty
                                ? messages.length
                                : messages.where((m) {
                                    final msgStr = (m['message'] ?? '').toString().toLowerCase();
                                    final attachStr = (m['attachmentName'] ?? '').toString().toLowerCase();
                                    return msgStr.contains(inChatSearchQuery) || attachStr.contains(inChatSearchQuery);
                                  }).length,
                            itemBuilder: (context, index) {
                              final displayList = inChatSearchQuery.isEmpty
                                  ? messages
                                  : messages.where((m) {
                                      final msgStr = (m['message'] ?? '').toString().toLowerCase();
                                      final attachStr = (m['attachmentName'] ?? '').toString().toLowerCase();
                                      return msgStr.contains(inChatSearchQuery) || attachStr.contains(inChatSearchQuery);
                                    }).toList();
                              final message = displayList[index];


                              final bool isMe = message['isMe'] == true;
                              final bool isDeleted = message['isDeleted'] == true || message['is_deleted'] == true;
                              final bool isEdited = message['isEdited'] == true || message['is_edited'] == true;
                              final bool isUploading = message['isUploading'] == true;
                              final bool isLocalFile = message['isLocalFile'] == true;

                              final isSelected = selectedMessage != null && selectedMessage!['id'] == message['id'];

                              final String? rawImgUrl = message['attachmentUrl']?.toString();
                              final String? formattedImgUrl = isLocalFile ? rawImgUrl : _getFormattedImageUrl(rawImgUrl);

                              final Map reactions = message['reactions'] is Map ? message['reactions'] : {};

                              return GestureDetector(
                                onLongPress: () {
                                  if (!isDeleted) {
                                    setState(() {
                                      selectedMessage = message;
                                    });
                                  }
                                },
                                onTap: () {
                                  if (selectedMessage != null) {
                                    setState(() {
                                      selectedMessage = isSelected ? null : message;
                                    });
                                  }
                                },
                                child: Column(
                                  crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                  children: [
                                    // Quick Reaction Bar
                                    if (isSelected && !isDeleted) ...[
                                      Container(
                                        margin: const EdgeInsets.only(bottom: 6),
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: isDark ? const Color(0xFF1F2C33) : Colors.white,
                                          borderRadius: BorderRadius.circular(24),
                                          boxShadow: const [
                                            BoxShadow(
                                              color: Color(0x20000000),
                                              blurRadius: 8,
                                              offset: Offset(0, 3),
                                            ),
                                          ],
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: ['â ¤ï¸ ', 'ðŸ‘ ', 'ðŸ˜‚', 'ðŸ˜®', 'ðŸ˜¢', 'ðŸ™ '].map((emoji) {
                                            return GestureDetector(
                                              onTap: () => _toggleReaction(message['id'], emoji),
                                              child: Padding(
                                                padding: const EdgeInsets.symmetric(horizontal: 5),
                                                child: Text(emoji, style: const TextStyle(fontSize: 21)),
                                              ),
                                            );
                                          }).toList(),
                                        ),
                                      ),
                                    ],

                                    Align(
                                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                                      child: Builder(
                                        builder: (context) {
                                          final bool isImageMessage = !isDeleted && formattedImgUrl != null && message['attachmentType'] == 'image';
                                          final bool hasCaption = isImageMessage && message['message'] != null && message['message'].toString().trim().isNotEmpty;
                                          final bool hasReply = message['replyToMessageId'] != null;

                                          return Container(
                                            constraints: BoxConstraints(
                                              maxWidth: isImageMessage ? 295 : 280,
                                              minWidth: isImageMessage ? 200 : 0,
                                            ),
                                            margin: const EdgeInsets.only(bottom: 8),
                                            padding: isImageMessage
                                                ? (hasCaption || hasReply
                                                    ? const EdgeInsets.fromLTRB(4, 4, 4, 6)
                                                    : const EdgeInsets.all(3.5))
                                                : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                            decoration: BoxDecoration(
                                              color: isMe
                                                  ? AppTheme.primaryTeal
                                                  : (isDark ? const Color(0xFF1F2C33) : const Color(0xFFD2F1EC)),
                                              border: isSelected
                                                  ? Border.all(color: Colors.amber, width: 2)
                                                  : null,
                                              borderRadius: BorderRadius.only(
                                                topLeft: const Radius.circular(18),
                                                topRight: const Radius.circular(18),
                                                bottomLeft: Radius.circular(isMe ? 18 : 4),
                                                bottomRight: Radius.circular(isMe ? 4 : 18),
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black.withValues(alpha: 0.08),
                                                  blurRadius: 4,
                                                  offset: const Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                // Quoted Reply Preview Box
                                                if (message['replyToMessageId'] != null) ...[
                                                  GestureDetector(
                                                    onTap: () => _scrollToMessage(message['replyToMessageId']),
                                                    child: Container(
                                                      width: double.infinity,
                                                      margin: const EdgeInsets.only(bottom: 6),
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                                      decoration: BoxDecoration(
                                                        color: isMe
                                                            ? Colors.black.withValues(alpha: 0.15)
                                                            : (isDark ? Colors.black26 : Colors.white54),
                                                        borderRadius: BorderRadius.circular(8),
                                                        border: Border(
                                                          left: BorderSide(
                                                            color: isMe ? Colors.white : AppTheme.primaryTeal,
                                                            width: 3.5,
                                                          ),
                                                        ),
                                                      ),
                                                      child: Column(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          Text(
                                                            _getReplySenderName(
                                                              message['replySenderId'] ?? message['reply_sender_id'],
                                                              message['replySenderName'] ?? message['reply_sender_name'],
                                                              message['replySenderId'] != null &&
                                                                  int.tryParse(message['replySenderId'].toString()) == widget.currentUserId,
                                                            ),
                                                            style: TextStyle(
                                                              fontWeight: FontWeight.w900,
                                                              fontSize: 11.5,
                                                              color: isMe ? Colors.white : AppTheme.primaryTeal,
                                                            ),
                                                          ),
                                                          const SizedBox(height: 2),
                                                          Text(
                                                            _getReplyPreviewText(
                                                              message['replyAttachmentType'] ?? message['reply_attachment_type'],
                                                              message['replyAttachmentName'] ?? message['reply_attachment_name'],
                                                              message['replyMessage'] ?? message['reply_message'],
                                                              message['replyIsDeleted'] == true || message['reply_is_deleted'] == true,
                                                            ),
                                                            maxLines: 2,
                                                            overflow: TextOverflow.ellipsis,
                                                            style: TextStyle(
                                                              fontSize: 11.5,
                                                              fontWeight: FontWeight.w700,
                                                              color: isMe ? Colors.white70 : (isDark ? Colors.grey.shade300 : const Color(0xFF54656F)),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ],

                                                // Attachment / Text
                                                if (isImageMessage) ...[
                                                  GestureDetector(
                                                    onTap: () => _openFullImageViewer(formattedImgUrl, isLocalFile: isLocalFile),
                                                    child: ClipRRect(
                                                      borderRadius: BorderRadius.circular(15),
                                                      child: Stack(
                                                        alignment: Alignment.center,
                                                        children: [
                                                          _buildEncryptedImageWidget(
                                                            url: formattedImgUrl,
                                                            nonce: message['nonce'],
                                                            isEncrypted: message['isEncrypted'] == true || message['is_encrypted'] == true,
                                                            isLocalFile: isLocalFile,
                                                          ),
                                                          if (isUploading)
                                                            Container(
                                                              color: Colors.black38,
                                                              child: const Center(
                                                                child: CircularProgressIndicator(color: Colors.white),
                                                              ),
                                                            ),
                                                          // Sleek floating glass timestamp on bottom-right of image if no caption
                                                          if (!hasCaption && !hasReply)
                                                            Positioned(
                                                              bottom: 6,
                                                              right: 6,
                                                              child: Container(
                                                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                                                decoration: BoxDecoration(
                                                                  color: Colors.black.withValues(alpha: 0.58),
                                                                  borderRadius: BorderRadius.circular(12),
                                                                ),
                                                                child: Row(
                                                                  mainAxisSize: MainAxisSize.min,
                                                                  children: [
                                                                    if (reactions.isNotEmpty) ...[
                                                                      Text(
                                                                        reactions.values.toSet().join(' '),
                                                                        style: const TextStyle(fontSize: 11),
                                                                      ),
                                                                      const SizedBox(width: 4),
                                                                    ],
                                                                    if (isEdited) ...[
                                                                      const Text(
                                                                        'Edited • ',
                                                                        style: TextStyle(
                                                                          color: Colors.white70,
                                                                          fontSize: 10,
                                                                          fontWeight: FontWeight.w600,
                                                                          fontStyle: FontStyle.italic,
                                                                        ),
                                                                      ),
                                                                    ],
                                                                    Text(
                                                                      message['time'].toString(),
                                                                      style: const TextStyle(
                                                                        color: Colors.white,
                                                                        fontSize: 10.5,
                                                                        fontWeight: FontWeight.w700,
                                                                      ),
                                                                    ),
                                                                    if (isMe) ...[
                                                                      const SizedBox(width: 3),
                                                                      Builder(
                                                                        builder: (context) {
                                                                          final bool isSeen = message['isRead'] == true || message['is_read'] == true;
                                                                          final bool isDelivered = isSeen || message['isDelivered'] == true || message['is_delivered'] == true;
                                                                          IconData iconData = isSeen
                                                                              ? Icons.done_all_rounded
                                                                              : (isDelivered ? Icons.done_all_rounded : Icons.check_rounded);
                                                                          Color iconColor = isSeen ? const Color(0xFF80DEEA) : Colors.white;
                                                                          return Icon(iconData, size: 14, color: iconColor);
                                                                        },
                                                                      ),
                                                                    ],
                                                                  ],
                                                                ),
                                                              ),
                                                            ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                  if (hasCaption)
                                                    Padding(
                                                      padding: const EdgeInsets.only(left: 6, right: 6, top: 6),
                                                      child: SelectableText(
                                                        message['message'].toString(),
                                                        style: TextStyle(
                                                          color: isMe ? Colors.white : (isDark ? Colors.white : const Color(0xFF111B21)),
                                                          fontSize: 15,
                                                          fontWeight: FontWeight.w800,
                                                        ),
                                                      ),
                                                    ),
                                                ] else if (!isDeleted && (message['attachmentType'] == 'location' || message['attachment_type'] == 'location')) ...[
                                                  Builder(
                                                    builder: (context) {
                                                      Map<String, dynamic> locData = {};
                                                      try {
                                                        locData = jsonDecode(message['message']?.toString() ?? '{}');
                                                      } catch (_) {}
                                                      final double? lat = (locData['lat'] as num?)?.toDouble();
                                                      final double? lng = (locData['lng'] as num?)?.toDouble();
                                                      final bool isLive = locData['isLive'] == true;
                                                      final Color fg = isMe ? Colors.white : AppTheme.primaryTeal;

                                                      return InkWell(
                                                        borderRadius: BorderRadius.circular(12),
                                                        onTap: (lat != null && lng != null) ? () => _openLocationInMaps(lat, lng) : null,
                                                        child: Container(
                                                          width: 220,
                                                          padding: const EdgeInsets.all(12),
                                                          decoration: BoxDecoration(
                                                            color: isMe ? Colors.black.withValues(alpha: 0.15) : (isDark ? Colors.black26 : Colors.white60),
                                                            borderRadius: BorderRadius.circular(12),
                                                          ),
                                                          child: Column(
                                                            crossAxisAlignment: CrossAxisAlignment.start,
                                                            children: [
                                                              Row(
                                                                children: [
                                                                  Icon(
                                                                    isLive ? Icons.my_location_rounded : Icons.location_on_rounded,
                                                                    color: isLive ? Colors.redAccent : fg,
                                                                    size: 20,
                                                                  ),
                                                                  const SizedBox(width: 6),
                                                                  Text(
                                                                    isLive ? 'Live Location' : 'Location',
                                                                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5, color: fg),
                                                                  ),
                                                                  if (isLive) ...[
                                                                    const SizedBox(width: 6),
                                                                    Container(
                                                                      width: 6,
                                                                      height: 6,
                                                                      decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                                                                    ),
                                                                  ],
                                                                ],
                                                              ),
                                                              const SizedBox(height: 6),
                                                              Text(
                                                                lat != null && lng != null
                                                                    ? '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}'
                                                                    : 'Location unavailable',
                                                                style: TextStyle(fontSize: 11.5, color: fg.withValues(alpha: 0.85), fontWeight: FontWeight.w600),
                                                              ),
                                                              const SizedBox(height: 6),
                                                              Text(
                                                                'Tap to open in Maps',
                                                                style: TextStyle(fontSize: 11, color: fg.withValues(alpha: 0.7), fontStyle: FontStyle.italic),
                                                              ),
                                                              if (isMe && isLive && _activeLiveLocationMessageId != null && _activeLiveLocationMessageId.toString() == message['id'].toString()) ...[
                                                                const SizedBox(height: 8),
                                                                GestureDetector(
                                                                  onTap: _stopSharingLiveLocation,
                                                                  child: Container(
                                                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                                    decoration: BoxDecoration(
                                                                      color: Colors.redAccent,
                                                                      borderRadius: BorderRadius.circular(8),
                                                                    ),
                                                                    child: const Text(
                                                                      'Stop Sharing',
                                                                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11.5),
                                                                    ),
                                                                  ),
                                                                ),
                                                              ],
                                                            ],
                                                          ),
                                                        ),
                                                      );
                                                    },
                                                  ),
                                                ] else if (!isDeleted && message['attachmentUrl'] != null && message['attachmentType'] == 'audio') ...[
                                                  _VoiceMessagePlayer(
                                                    url: formattedImgUrl ?? '',
                                                    isLocalFile: isLocalFile,
                                                    isMe: isMe,
                                                    headers: _authHeaders,
                                                  ),
                                                ] else if (!isDeleted && message['attachmentUrl'] != null && message['attachmentType'] == 'file') ...[
                                                  Builder(
                                                    builder: (context) {
                                                      final msgIdStr = message['id']?.toString() ?? message['attachmentUrl'].toString();
                                                      final bool isDownloading = _downloadingFileIds.contains(msgIdStr);
                                                      final bool isDownloaded = (isLocalFile && !kIsWeb && File(message['attachmentUrl']?.toString() ?? '').existsSync()) ||
                                                          (_downloadedFilePaths.containsKey(msgIdStr) && (!kIsWeb ? File(_downloadedFilePaths[msgIdStr]!).existsSync() : true));
                                                      final String cleanDocName = _decodeFileName(message['attachmentName']?.toString() ?? message['attachment_name']?.toString() ?? 'Document');

                                                      return InkWell(
                                                        onTap: () {
                                                          final rawUrl = message['attachmentUrl'] ?? message['attachment_url'];
                                                          if (rawUrl != null) {
                                                            _handleDocumentTap(
                                                              messageId: message['id']?.toString(),
                                                              rawUrl: rawUrl.toString(),
                                                              fileName: cleanDocName,
                                                              isMe: isMe,
                                                              isLocalFile: isLocalFile,
                                                            );
                                                          }
                                                        },
                                                        borderRadius: BorderRadius.circular(12),
                                                        child: Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                                          decoration: BoxDecoration(
                                                            color: isMe ? Colors.black.withValues(alpha: 0.15) : (isDark ? Colors.black26 : Colors.white60),
                                                            borderRadius: BorderRadius.circular(12),
                                                          ),
                                                          child: Row(
                                                            children: [
                                                              Container(
                                                                width: 40,
                                                                height: 40,
                                                                decoration: BoxDecoration(
                                                                  color: isDownloaded
                                                                      ? (isMe ? Colors.white.withValues(alpha: 0.25) : AppTheme.primaryTeal.withValues(alpha: 0.15))
                                                                      : (isMe ? Colors.black.withValues(alpha: 0.25) : Colors.black12),
                                                                  shape: BoxShape.circle,
                                                                ),
                                                                child: Center(
                                                                  child: isDownloading
                                                                      ? const SizedBox(
                                                                          width: 18,
                                                                          height: 18,
                                                                          child: CircularProgressIndicator(
                                                                            strokeWidth: 2.2,
                                                                            color: Colors.white,
                                                                          ),
                                                                        )
                                                                      : Icon(
                                                                          isDownloaded
                                                                              ? Icons.description_rounded
                                                                              : Icons.arrow_downward_rounded,
                                                                          color: isMe
                                                                              ? Colors.white
                                                                              : (isDownloaded ? AppTheme.primaryTeal : (isDark ? Colors.white70 : const Color(0xFF111B21))),
                                                                          size: 22,
                                                                        ),
                                                                ),
                                                              ),
                                                              const SizedBox(width: 10),
                                                              Expanded(
                                                                child: Column(
                                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                                  children: [
                                                                    Text(
                                                                      cleanDocName,
                                                                      maxLines: 2,
                                                                      overflow: TextOverflow.ellipsis,
                                                                      style: TextStyle(
                                                                        color: isMe ? Colors.white : (isDark ? Colors.white : const Color(0xFF111B21)),
                                                                        fontWeight: FontWeight.w900,
                                                                        fontSize: 13.5,
                                                                      ),
                                                                    ),
                                                                    const SizedBox(height: 2),
                                                                    Row(
                                                                      children: [
                                                                        if (message['attachmentSize'] != null)
                                                                          Text(
                                                                            _formatFileSize(message['attachmentSize']),
                                                                            style: TextStyle(
                                                                              color: isMe ? Colors.white70 : (isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                                                                              fontSize: 11,
                                                                              fontWeight: FontWeight.w700,
                                                                            ),
                                                                          ),
                                                                        if (!isDownloaded && !isDownloading) ...[
                                                                          Text(
                                                                            " • Download",
                                                                            style: TextStyle(
                                                                              color: isMe ? const Color(0xFF80DEEA) : AppTheme.primaryTeal,
                                                                              fontSize: 11,
                                                                              fontWeight: FontWeight.w800,
                                                                            ),
                                                                          ),
                                                                        ] else if (isDownloaded) ...[
                                                                          Text(
                                                                            " • Open",
                                                                            style: TextStyle(
                                                                              color: isMe ? Colors.white60 : Colors.grey.shade500,
                                                                              fontSize: 11,
                                                                              fontWeight: FontWeight.w600,
                                                                            ),
                                                                          ),
                                                                        ],
                                                                      ],
                                                                    ),
                                                                  ],
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      );
                                                    },
                                                  ),
                                                ] else ...[
                                                  SelectableText(
                                                    isDeleted ? 'This message was deleted' : message['message'].toString(),
                                                    style: TextStyle(
                                                      color: isMe
                                                          ? Colors.white
                                                          : (isDeleted
                                                              ? Colors.grey.shade500
                                                              : (isDark ? Colors.white : const Color(0xFF111B21))),
                                                      fontSize: 15,
                                                      height: 1.25,
                                                      fontWeight: isDeleted ? FontWeight.w500 : FontWeight.w800,
                                                      fontStyle: isDeleted ? FontStyle.italic : FontStyle.normal,
                                                    ),
                                                  ),
                                                ],

                                                // Bottom Time & Blue Ticks row (shown for text, files, and images with captions)
                                                if (!(isImageMessage && !hasCaption && !hasReply)) ...[
                                                  const SizedBox(height: 4),
                                                  Row(
                                                    mainAxisAlignment: MainAxisAlignment.end,
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      if (reactions.isNotEmpty) ...[
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                                          decoration: BoxDecoration(
                                                            color: Colors.white,
                                                            borderRadius: BorderRadius.circular(10),
                                                            boxShadow: const [
                                                              BoxShadow(color: Color(0x15000000), blurRadius: 3),
                                                            ],
                                                          ),
                                                          child: Text(
                                                            reactions.values.toSet().join(' '),
                                                            style: const TextStyle(fontSize: 11),
                                                          ),
                                                        ),
                                                        const SizedBox(width: 5),
                                                      ],
                                                      if (isEdited && !isDeleted) ...[
                                                        Text(
                                                          'Edited • ',
                                                          style: TextStyle(
                                                            color: isMe ? Colors.white70 : Colors.grey.shade600,
                                                            fontSize: 10,
                                                            fontWeight: FontWeight.w700,
                                                            fontStyle: FontStyle.italic,
                                                          ),
                                                        ),
                                                      ],
                                                      Text(
                                                        message['time'].toString(),
                                                        style: TextStyle(
                                                          color: isMe ? Colors.white70 : (isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                                                          fontSize: 11,
                                                          fontWeight: FontWeight.w700,
                                                        ),
                                                      ),
                                                      if (isMe && !isDeleted) ...[
                                                        const SizedBox(width: 3),
                                                        Builder(
                                                          builder: (context) {
                                                            final bool isSeen = message['isRead'] == true || message['is_read'] == true;
                                                            final bool isDelivered = isSeen || message['isDelivered'] == true || message['is_delivered'] == true;

                                                            IconData iconData;
                                                            Color iconColor;

                                                            if (isSeen) {
                                                              iconData = Icons.done_all_rounded;
                                                              iconColor = const Color(0xFF80DEEA); // Bright Cyan
                                                            } else if (isDelivered) {
                                                              iconData = Icons.done_all_rounded;
                                                              iconColor = Colors.white70;
                                                            } else {
                                                              iconData = Icons.check_rounded;
                                                              iconColor = Colors.white70;
                                                            }

                                                            return Icon(
                                                              iconData,
                                                              size: 16,
                                                              color: iconColor,
                                                            );
                                                          },
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                ],
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
              ),
            ),
            if (isOtherUserTyping)
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, bottom: 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1F2C33) : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryTeal),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          typingText,
                          style: const TextStyle(
                            fontSize: 13,
                            fontStyle: FontStyle.italic,
                            color: AppTheme.primaryTeal,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            if (replyingToMessage != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                color: isDark ? const Color(0xFF1F2C33) : const Color(0xFFE9EDEF),
                child: Row(
                  children: [
                    const Icon(Icons.reply_rounded, color: AppTheme.primaryTeal, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Replying to ${_getReplySenderName(
                              replyingToMessage!['sender_id'] ?? replyingToMessage!['senderId'],
                              replyingToMessage!['sender_name'] ?? replyingToMessage!['senderName'],
                              replyingToMessage!['isMe'] == true,
                            )}",
                            style: const TextStyle(
                              color: AppTheme.primaryTeal,
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            _getReplyPreviewText(
                              replyingToMessage!['attachmentType'] ?? replyingToMessage!['attachment_type'],
                              replyingToMessage!['attachmentName'] ?? replyingToMessage!['attachment_name'],
                              replyingToMessage!['message'],
                              replyingToMessage!['isDeleted'] == true || replyingToMessage!['is_deleted'] == true,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white : const Color(0xFF111B21),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close_rounded, size: 18, color: isDark ? Colors.white70 : const Color(0xFF54656F)),
                      onPressed: _cancelReplying,
                    ),
                  ],
                ),
              ),

            if (editingMessageId != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                color: isDark ? const Color(0xFF1F2C33) : const Color(0xFFE9EDEF),
                child: Row(
                  children: [
                    const Icon(Icons.edit_rounded, color: AppTheme.primaryTeal, size: 18),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Editing message...',
                        style: TextStyle(
                          color: AppTheme.primaryTeal,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close_rounded, size: 18, color: isDark ? Colors.white70 : const Color(0xFF54656F)),
                      onPressed: _cancelEditing,
                    ),
                  ],
                ),
              ),

            if (_isRecordingVoice)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                color: isDark ? const Color(0xFF1F2C33) : const Color(0xFFE9EDEF),
                child: Row(
                  children: [
                    const Icon(Icons.fiber_manual_record_rounded, color: Colors.redAccent, size: 14),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Recording ${_formatRecordingDuration(_recordingSeconds)} — release mic to send",
                        style: const TextStyle(
                          color: AppTheme.primaryTeal,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _stopVoiceRecordingAndSend(cancel: true),
                      child: const Icon(Icons.close_rounded, size: 18, color: Colors.redAccent),
                    ),
                  ],
                ),
              ),

            // Bottom Wave Footer & Input Pill Bar
            ClipPath(
              clipper: WaveFooterClipper(),
              child: Container(
                padding: const EdgeInsets.only(top: 6, left: 16, right: 16, bottom: 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isVanishMode
                        ? [const Color(0xFF4A148C), const Color(0xFF8E24AA)]
                        : [const Color(0xFF0F766E), const Color(0xFF149B9B)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    color: isVanishMode
                        ? const Color(0xFF1D0F2E)
                        : (isDark ? const Color(0xFF1F2C33) : Colors.white),
                    borderRadius: BorderRadius.circular(26),
                    border: isVanishMode
                        ? Border.all(color: const Color(0xFFE040FB).withValues(alpha: 0.6), width: 1.5)
                        : null,
                    boxShadow: [
                      BoxShadow(
                        color: (isVanishMode ? const Color(0xFFE040FB) : Colors.black).withValues(alpha: 0.15),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      // Emoji Toggle Button
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _showEmojiPicker = !_showEmojiPicker;
                            if (_showEmojiPicker) {
                              _focusNode.unfocus();
                            } else {
                              _focusNode.requestFocus();
                            }
                          });
                        },
                        icon: Icon(
                          _showEmojiPicker ? Icons.keyboard_rounded : Icons.emoji_emotions_outlined,
                          color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          controller: messageController,
                          focusNode: _focusNode,
                          textInputAction: TextInputAction.send,
                          onChanged: _onTypingChanged,
                          onSubmitted: (_) => sendMessage(),
                          style: TextStyle(
                            color: isVanishMode ? Colors.white : (isDark ? Colors.white : const Color(0xFF111B21)),
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                          decoration: InputDecoration(
                            hintText: isVanishMode ? 'Send a vanishing message... \u{1F52E}' : 'Type your message here...',
                            hintStyle: TextStyle(
                              color: isVanishMode
                                  ? const Color(0xFFCE93D8)
                                  : (isDark ? Colors.grey.shade400 : Colors.grey.shade500),
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _pickFromCamera,
                        icon: Icon(
                          Icons.camera_alt_rounded,
                          color: isDark ? Colors.grey.shade300 : const Color(0xFF111B21),
                          size: 22,
                        ),
                      ),
                      IconButton(
                        onPressed: _showAttachmentGridSheet,
                        icon: Icon(
                          Icons.attach_file_rounded,
                          color: isDark ? Colors.grey.shade300 : const Color(0xFF111B21),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 2),
                      (messageController.text.trim().isEmpty && editingMessageId == null)
                          ? GestureDetector(
                              onLongPressStart: (_) => _startVoiceRecording(),
                              onLongPressEnd: (_) => _stopVoiceRecordingAndSend(),
                              onLongPressCancel: () => _stopVoiceRecordingAndSend(cancel: true),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                width: _isRecordingVoice ? 52 : 42,
                                height: _isRecordingVoice ? 52 : 42,
                                margin: const EdgeInsets.only(right: 5),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: _isRecordingVoice
                                        ? [Colors.redAccent, Colors.red.shade700]
                                        : const [Color(0xFF0F766E), Color(0xFF149B9B)],
                                  ),
                                  shape: BoxShape.circle,
                                  boxShadow: _isRecordingVoice
                                      ? [
                                          BoxShadow(
                                            color: Colors.redAccent.withValues(alpha: 0.5),
                                            blurRadius: 12,
                                            spreadRadius: 2,
                                          ),
                                        ]
                                      : null,
                                ),
                                child: Icon(
                                  _isRecordingVoice ? Icons.mic_rounded : Icons.mic_none_rounded,
                                  color: Colors.white,
                                  size: _isRecordingVoice ? 24 : 20,
                                ),
                              ),
                            )
                          : GestureDetector(
                              onTap: sendMessage,
                              child: Container(
                                width: 42,
                                height: 42,
                                margin: const EdgeInsets.only(right: 5),
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [Color(0xFF0F766E), Color(0xFF149B9B)],
                                  ),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.near_me_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                    ],
                  ),
                ),
              ),
            ),

            // Instagram Swipe Up Progress Indicator Pill
            if (vanishDragOffset > 5.0)
              AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                margin: const EdgeInsets.only(bottom: 8, top: 4),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  color: isVanishThresholdReached ? const Color(0xFF9C27B0) : Colors.black87,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: (isVanishThresholdReached ? const Color(0xFFE040FB) : Colors.black).withValues(alpha: 0.4),
                      blurRadius: 14,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        value: (vanishDragOffset / 65.0).clamp(0.0, 1.0),
                        color: isVanishThresholdReached ? Colors.amber : const Color(0xFFE040FB),
                        strokeWidth: 3,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      !isVanishMode
                          ? (isVanishThresholdReached ? "Release to turn on Vanish mode ðŸ”®" : "Swipe up to turn on Vanish mode")
                          : (isVanishThresholdReached ? "Release to turn off Vanish mode â˜€ï¸" : "Swipe up to turn off Vanish mode"),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13),
                    ),
                  ],
                ),
              ),
            
            // Emoji Picker Widget
            if (_showEmojiPicker)
              SizedBox(
                height: 250,
                child: EmojiPicker(
                  textEditingController: messageController,
                  config: Config(
                    height: 250,
                    checkPlatformCompatibility: true,
                    emojiViewConfig: EmojiViewConfig(
                      backgroundColor: isDark ? const Color(0xFF111B21) : const Color(0xFFF0F2F5),
                      columns: 7,
                      emojiSizeMax: 32 * (foundation.defaultTargetPlatform == TargetPlatform.iOS ? 1.30 : 1.0),
                    ),
                    categoryViewConfig: CategoryViewConfig(
                      backgroundColor: isDark ? const Color(0xFF111B21) : const Color(0xFFF0F2F5),
                      indicatorColor: AppTheme.primaryTeal,
                      iconColorSelected: AppTheme.primaryTeal,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ],
  ),
);
  }
}

// =========================
// VOICE MESSAGE PLAYBACK WIDGET
// =========================
class _VoiceMessagePlayer extends StatefulWidget {
  final String url;
  final bool isLocalFile;
  final bool isMe;
  final Map<String, String> headers;

  const _VoiceMessagePlayer({
    required this.url,
    required this.isLocalFile,
    required this.isMe,
    required this.headers,
  });

  @override
  State<_VoiceMessagePlayer> createState() => _VoiceMessagePlayerState();
}

class _VoiceMessagePlayerState extends State<_VoiceMessagePlayer> {
  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;
  bool _isLoaded = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  StreamSubscription? _durationSub;
  StreamSubscription? _positionSub;
  StreamSubscription? _completeSub;
  StreamSubscription? _stateSub;

  @override
  void initState() {
    super.initState();
    _durationSub = _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _positionSub = _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _completeSub = _player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _position = Duration.zero;
        });
      }
    });
    _stateSub = _player.onPlayerStateChanged.listen((s) {
      if (mounted) {
        setState(() => _isPlaying = s == PlayerState.playing);
      }
    });
  }

  Future<void> _togglePlay() async {
    try {
      if (_isPlaying) {
        await _player.pause();
        return;
      }
      if (!_isLoaded) {
        if (widget.isLocalFile && !kIsWeb) {
          await _player.play(DeviceFileSource(widget.url));
        } else {
          await _player.play(UrlSource(widget.url));
        }
        _isLoaded = true;
      } else {
        await _player.resume();
      }
    } catch (e) {
      debugPrint("Error playing voice message: $e");
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _durationSub?.cancel();
    _positionSub?.cancel();
    _completeSub?.cancel();
    _stateSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color fg = widget.isMe ? Colors.white : AppTheme.primaryTeal;
    final double progress = _duration.inMilliseconds > 0
        ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    final bool hasElapsed = _isPlaying || _position.inMilliseconds > 0;

    return SizedBox(
      width: 210,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: _togglePlay,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: widget.isMe
                    ? Colors.white.withValues(alpha: 0.25)
                    : AppTheme.primaryTeal.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: fg,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    backgroundColor: fg.withValues(alpha: 0.2),
                    valueColor: AlwaysStoppedAnimation<Color>(fg),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.mic_rounded, size: 12, color: fg.withValues(alpha: 0.7)),
                    const SizedBox(width: 3),
                    Text(
                      _duration.inMilliseconds > 0
                          ? _fmt(hasElapsed ? _position : _duration)
                          : 'Voice message',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: fg.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
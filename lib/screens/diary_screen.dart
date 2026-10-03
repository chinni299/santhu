import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../config/api_config.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/wave_clipper.dart';

/// Our Diary — a shared journal for the two of you. Either person can add
/// an entry (text, an optional mood, an optional photo); both of you see
/// every entry, in real time, grouped by date. Works in Telugu, English,
/// or any mix — Flutter's text fields are Unicode by default, so no extra
/// setup is needed for that.
class DiaryScreen extends StatefulWidget {
  final io.Socket? socket;
  final int conversationId;
  final int currentUserId;

  const DiaryScreen({
    super.key,
    required this.socket,
    required this.conversationId,
    required this.currentUserId,
  });

  @override
  State<DiaryScreen> createState() => _DiaryScreenState();
}

class _DiaryScreenState extends State<DiaryScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _entries = [];
  Map<String, String> _authHeaders = {};

  final _entryController = TextEditingController();
  String? _selectedMood;
  XFile? _pickedPhoto;
  bool _isSaving = false;

  static const List<String> _moods = ['😊', '🥰', '😢', '😡', '😴', '🤗', '😂', '🥳'];

  @override
  void initState() {
    super.initState();
    _load();
    widget.socket?.on('diaryEntryAdded', _onEntryAdded);
    widget.socket?.on('diaryEntryDeleted', _onEntryDeleted);
  }

  @override
  void dispose() {
    widget.socket?.off('diaryEntryAdded', _onEntryAdded);
    widget.socket?.off('diaryEntryDeleted', _onEntryDeleted);
    _entryController.dispose();
    super.dispose();
  }

  void _onEntryAdded(dynamic data) {
    if (data == null) return;
    final convId = data['conversationId'];
    if (convId != null && convId.toString() != widget.conversationId.toString()) return;
    final entry = data['entry'];
    if (entry == null || !mounted) return;
    setState(() {
      _entries.insert(0, Map<String, dynamic>.from(entry));
    });
  }

  void _onEntryDeleted(dynamic data) {
    if (data == null) return;
    final convId = data['conversationId'];
    if (convId != null && convId.toString() != widget.conversationId.toString()) return;
    final id = data['id'];
    if (id == null || !mounted) return;
    setState(() {
      _entries.removeWhere((e) => e['id'].toString() == id.toString());
    });
  }

  Future<void> _load() async {
    try {
      final headers = await AuthService.getAuthHeadersForUser(widget.currentUserId);
      final res = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/messages/diary/${widget.conversationId}'),
        headers: headers,
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        final List items = data['data'] ?? [];
        if (!mounted) return;
        setState(() {
          _authHeaders = headers;
          _entries = items.cast<Map<String, dynamic>>();
          _isLoading = false;
        });
      } else {
        if (!mounted) return;
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  String? _formatPhotoUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    String clean = url
        .replaceAll('localhost:5000', ApiConfig.formattedHost)
        .replaceAll('127.0.0.1:5000', ApiConfig.formattedHost)
        .replaceAll('http://santhu-swuo.onrender.com', 'https://santhu-swuo.onrender.com');
    return clean;
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (image != null && mounted) {
      setState(() => _pickedPhoto = image);
    }
  }

  Future<String?> _uploadPickedPhoto() async {
    if (_pickedPhoto == null) return null;
    try {
      final bytes = await _pickedPhoto!.readAsBytes();
      final uri = Uri.parse('${ApiConfig.baseUrl}/messages/diary/upload-photo');
      final request = http.MultipartRequest('POST', uri);
      final token = await AuthService.getTokenForUser(widget.currentUserId);
      if (token != null && token.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $token';
      }
      request.fields['conversationId'] = widget.conversationId.toString();
      request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: _pickedPhoto!.name));

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return data['url']?.toString();
      }
    } catch (e) {
      debugPrint('Diary photo upload error: $e');
    }
    return null;
  }

  Future<void> _submitEntry() async {
    final text = _entryController.text.trim();
    if (text.isEmpty && _pickedPhoto == null) return;

    setState(() => _isSaving = true);
    final photoUrl = await _uploadPickedPhoto();

    widget.socket?.emit('addDiaryEntry', {
      'conversationId': widget.conversationId,
      'entryText': text,
      'mood': _selectedMood,
      'photoUrl': photoUrl,
    });

    if (!mounted) return;
    setState(() {
      _entryController.clear();
      _selectedMood = null;
      _pickedPhoto = null;
      _isSaving = false;
    });
    FocusScope.of(context).unfocus();
  }

  void _confirmDelete(Map<String, dynamic> entry) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete this entry?'),
        content: const Text('This will remove it from the shared diary for both of you.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () {
              widget.socket?.emit('deleteDiaryEntry', {
                'conversationId': widget.conversationId,
                'id': entry['id'],
              });
              Navigator.pop(ctx);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  String _formatDateHeader(String rawDate) {
    try {
      final d = DateTime.parse(rawDate);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final entryDay = DateTime(d.year, d.month, d.day);
      if (entryDay == today) return 'Today';
      if (entryDay == today.subtract(const Duration(days: 1))) return 'Yesterday';
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${d.day} ${months[d.month - 1]} ${d.year}';
    } catch (_) {
      return rawDate;
    }
  }

  String _formatTime(String raw) {
    try {
      final d = DateTime.parse(raw).toLocal();
      final hour = d.hour == 0 ? 12 : (d.hour > 12 ? d.hour - 12 : d.hour);
      final minute = d.minute.toString().padLeft(2, '0');
      final period = d.hour >= 12 ? 'PM' : 'AM';
      return '$hour:$minute $period';
    } catch (_) {
      return '';
    }
  }

  Map<String, List<Map<String, dynamic>>> _groupByDate() {
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final e in _entries) {
      final dateKey = (e['entry_date'] ?? '').toString();
      grouped.putIfAbsent(dateKey, () => []).add(e);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final grouped = _groupByDate();
    final dateKeys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121E24) : const Color(0xFFF5F7F8),
      body: Column(
        children: [
          // Teal wave header — matches the chat screen's visual language
          ClipPath(
            clipper: WaveHeaderClipper(),
            child: Container(
              padding: const EdgeInsets.only(top: 45, left: 8, right: 16, bottom: 18),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0F766E), Color(0xFF149B9B), Color(0xFF0D8383)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Icon(Icons.menu_book_rounded, color: Colors.white, size: 22),
                  const SizedBox(width: 8),
                  const Text(
                    'Our Diary',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18),
                  ),
                ],
              ),
            ),
          ),

          // Entry composer
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1F2C33) : Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 3))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _entryController,
                  maxLines: 4,
                  minLines: 1,
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    hintText: 'Write today\'s entry… (తెలుగు లో కూడా రాయవచ్చు)',
                    hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 13.5),
                    border: InputBorder.none,
                  ),
                ),
                if (_pickedPhoto != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: kIsWeb
                              ? Image.network(_pickedPhoto!.path, height: 120, fit: BoxFit.cover)
                              : Image.file(File(_pickedPhoto!.path), height: 120, fit: BoxFit.cover),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: GestureDetector(
                            onTap: () => setState(() => _pickedPhoto = null),
                            child: const CircleAvatar(
                              radius: 12,
                              backgroundColor: Colors.black54,
                              child: Icon(Icons.close_rounded, size: 14, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.image_outlined, color: AppTheme.primaryTeal),
                      onPressed: _pickPhoto,
                      tooltip: 'Add photo',
                    ),
                    ..._moods.map((m) {
                      final bool selected = _selectedMood == m;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedMood = selected ? null : m),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: selected ? AppTheme.primaryTeal.withValues(alpha: 0.18) : Colors.transparent,
                            shape: BoxShape.circle,
                          ),
                          child: Text(m, style: const TextStyle(fontSize: 18)),
                        ),
                      );
                    }),
                    const Spacer(),
                    _isSaving
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryTeal))
                        : GestureDetector(
                            onTap: _submitEntry,
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: const BoxDecoration(color: AppTheme.primaryTeal, shape: BoxShape.circle),
                              child: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                            ),
                          ),
                  ],
                ),
              ],
            ),
          ),

          // Entries, grouped by date
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryTeal))
                : _entries.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.auto_stories_outlined, size: 56, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            Text('No entries yet', style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text('Write your first memory together', style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: dateKeys.length,
                        itemBuilder: (context, i) {
                          final dateKey = dateKeys[i];
                          final entriesForDate = grouped[dateKey]!;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 12, bottom: 8),
                                child: Text(
                                  _formatDateHeader(dateKey),
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w900,
                                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              ...entriesForDate.map((entry) {
                                final bool isMine = int.tryParse(entry['author_id'].toString()) == widget.currentUserId;
                                final photoUrl = _formatPhotoUrl(entry['photo_url']?.toString());
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF1F2C33) : Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border(
                                      left: BorderSide(color: isMine ? AppTheme.primaryTeal : const Color(0xFFE040FB), width: 3.5),
                                    ),
                                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            entry['author_name']?.toString() ?? (isMine ? 'You' : 'Partner'),
                                            style: TextStyle(
                                              fontWeight: FontWeight.w900,
                                              fontSize: 12.5,
                                              color: isMine ? AppTheme.primaryTeal : const Color(0xFFE040FB),
                                            ),
                                          ),
                                          if (entry['mood'] != null) ...[
                                            const SizedBox(width: 6),
                                            Text(entry['mood'].toString(), style: const TextStyle(fontSize: 14)),
                                          ],
                                          const Spacer(),
                                          Text(
                                            _formatTime(entry['created_at']?.toString() ?? ''),
                                            style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500, fontWeight: FontWeight.w600),
                                          ),
                                          GestureDetector(
                                            onTap: () => _confirmDelete(entry),
                                            child: Padding(
                                              padding: const EdgeInsets.only(left: 8),
                                              child: Icon(Icons.close_rounded, size: 15, color: Colors.grey.shade400),
                                            ),
                                          ),
                                        ],
                                      ),
                                      if ((entry['entry_text'] ?? '').toString().trim().isNotEmpty) ...[
                                        const SizedBox(height: 6),
                                        Text(
                                          entry['entry_text'].toString(),
                                          style: TextStyle(
                                            fontSize: 14,
                                            height: 1.4,
                                            color: isDark ? Colors.white : const Color(0xFF111B21),
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                      if (photoUrl != null) ...[
                                        const SizedBox(height: 8),
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(12),
                                          child: Image.network(
                                            photoUrl,
                                            headers: _authHeaders,
                                            height: 180,
                                            width: double.infinity,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, _, _) => Container(
                                              height: 100,
                                              color: Colors.grey.shade200,
                                              child: const Icon(Icons.broken_image_rounded, color: Colors.grey),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                );
                              }),
                            ],
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

/// Shared Media Gallery — every photo, document and voice message
/// exchanged in the conversation, in one place.
class MediaGalleryScreen extends StatefulWidget {
  final int conversationId;
  final int currentUserId;
  final String peerName;

  const MediaGalleryScreen({
    super.key,
    required this.conversationId,
    required this.currentUserId,
    required this.peerName,
  });

  @override
  State<MediaGalleryScreen> createState() => _MediaGalleryScreenState();
}

class _MediaGalleryScreenState extends State<MediaGalleryScreen> {
  bool _isLoading = true;
  String? _error;
  Map<String, String> _authHeaders = {};

  List<Map<String, dynamic>> _photos = [];
  List<Map<String, dynamic>> _files = [];
  List<Map<String, dynamic>> _voice = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  String? _formatUrl(String? url) {
    if (url == null || url.trim().isEmpty || url.trim() == 'null') return null;
    String clean = url.trim();
    if (clean.contains('/uploads/')) {
      clean = clean.replaceAll('/uploads/', '/messages/attachments/file/');
    }
    if (clean.startsWith('/')) {
      clean = '${ApiConfig.baseUrl}$clean';
    }
    clean = clean
        .replaceAll('localhost:5000', ApiConfig.formattedHost)
        .replaceAll('127.0.0.1:5000', ApiConfig.formattedHost)
        .replaceAll('http://santhu-swuo.onrender.com', 'https://santhu-swuo.onrender.com');
    return clean;
  }

  Future<void> _load() async {
    try {
      final headers = await AuthService.getAuthHeadersForUser(widget.currentUserId);
      final res = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/messages/media/${widget.conversationId}'),
        headers: headers,
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        final List items = data['data'] ?? [];
        final photos = <Map<String, dynamic>>[];
        final files = <Map<String, dynamic>>[];
        final voice = <Map<String, dynamic>>[];

        for (final raw in items) {
          final item = Map<String, dynamic>.from(raw as Map);
          switch (item['attachment_type']) {
            case 'image':
              photos.add(item);
              break;
            case 'audio':
              voice.add(item);
              break;
            default:
              files.add(item);
          }
        }

        if (!mounted) return;
        setState(() {
          _authHeaders = headers;
          _photos = photos;
          _files = files;
          _voice = voice;
          _isLoading = false;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _error = 'Could not load media (${res.statusCode})';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load media';
        _isLoading = false;
      });
    }
  }

  String _formatSize(dynamic bytes) {
    final int b = int.tryParse(bytes?.toString() ?? '') ?? 0;
    if (b <= 0) return '';
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatDate(dynamic raw) {
    try {
      final d = DateTime.parse(raw.toString()).toLocal();
      return '${d.day}/${d.month}/${d.year}';
    } catch (_) {
      return '';
    }
  }

  void _openPhoto(String url) {
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
                child: Image.network(
                  url,
                  headers: _authHeaders,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image_rounded, size: 64, color: Colors.white54),
                ),
              ),
            ),
            Positioned(
              top: 40,
              left: 12,
              child: CircleAvatar(
                backgroundColor: Colors.black45,
                child: IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(IconData icon, String text) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(text, style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _buildPhotosTab() {
    if (_photos.isEmpty) return _emptyState(Icons.photo_library_outlined, 'No photos shared yet');
    return GridView.builder(
      padding: const EdgeInsets.all(6),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount: _photos.length,
      itemBuilder: (context, i) {
        final url = _formatUrl(_photos[i]['attachment_url']?.toString());
        if (url == null) return const SizedBox.shrink();
        return GestureDetector(
          onTap: () => _openPhoto(url),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              url,
              headers: _authHeaders,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return Container(color: Colors.black12);
              },
              errorBuilder: (context, error, stackTrace) => Container(
                color: Colors.grey.shade300,
                child: const Icon(Icons.broken_image_rounded, color: Colors.grey),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildListTab(List<Map<String, dynamic>> items, IconData icon, String emptyText) {
    if (items.isEmpty) return _emptyState(icon, emptyText);
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: items.length,
      separatorBuilder: (context, index) => const Divider(height: 1, indent: 72),
      itemBuilder: (context, i) {
        final item = items[i];
        final bool isMine = int.tryParse(item['sender_id'].toString()) == widget.currentUserId;
        final name = item['attachment_name']?.toString() ?? 'Attachment';
        final size = _formatSize(item['attachment_size']);
        final date = _formatDate(item['created_at']);
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: AppTheme.primaryTeal.withValues(alpha: 0.15),
            child: Icon(icon, color: AppTheme.primaryTeal),
          ),
          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text(
            [isMine ? 'You' : widget.peerName, if (size.isNotEmpty) size, date].join(' • '),
            style: const TextStyle(fontSize: 12),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AppTheme.primaryTeal,
          foregroundColor: Colors.white,
          title: const Text('Media & Files', style: TextStyle(fontWeight: FontWeight.w900)),
          bottom: TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(text: 'Photos (${_photos.length})'),
              Tab(text: 'Files (${_files.length})'),
              Tab(text: 'Voice (${_voice.length})'),
            ],
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryTeal))
            : _error != null
                ? Center(child: Text(_error!))
                : TabBarView(
                    children: [
                      _buildPhotosTab(),
                      _buildListTab(_files, Icons.insert_drive_file_rounded, 'No files shared yet'),
                      _buildListTab(_voice, Icons.mic_rounded, 'No voice messages yet'),
                    ],
                  ),
      ),
    );
  }
}
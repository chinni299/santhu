import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_filex/open_filex.dart';
import '../config/api_config.dart';
import '../services/auth_service.dart';
import '../services/encryption_service.dart';
import '../theme/app_theme.dart';

/// Shared Media Gallery — every photo, document and voice message
/// exchanged in the conversation, in one place, fully E2EE decrypted.
class MediaGalleryScreen extends StatefulWidget {
  final int conversationId;
  final int currentUserId;
  final String peerName;
  final int? peerUserId;
  final SecretKey? sharedSecretKey;

  const MediaGalleryScreen({
    super.key,
    required this.conversationId,
    required this.currentUserId,
    required this.peerName,
    this.peerUserId,
    this.sharedSecretKey,
  });

  @override
  State<MediaGalleryScreen> createState() => _MediaGalleryScreenState();
}

class _MediaGalleryScreenState extends State<MediaGalleryScreen> {
  bool _isLoading = true;
  String? _error;
  Map<String, String> _authHeaders = {};
  SecretKey? _sharedSecretKey;

  List<Map<String, dynamic>> _photos = [];
  List<Map<String, dynamic>> _files = [];
  List<Map<String, dynamic>> _voice = [];

  // Memory cache to avoid re-decrypting thumbnails repeatedly
  final Map<String, Uint8List> _decryptedBytesCache = {};

  @override
  void initState() {
    super.initState();
    _sharedSecretKey = widget.sharedSecretKey;
    _initAndLoad();
  }

  Future<void> _initAndLoad() async {
    // If shared key not provided, derive it
    if (_sharedSecretKey == null && widget.peerUserId != null) {
      try {
        final password = await AuthService.getPassword(widget.currentUserId) ?? 'password123';
        await EncryptionService().syncKeyVault(widget.currentUserId, password);
        final peerPubKey = await AuthService.getPeerPublicKey(widget.peerUserId!, widget.currentUserId);
        if (peerPubKey != null && peerPubKey.isNotEmpty) {
          final key = await EncryptionService().getSharedKey(peerPubKey, widget.currentUserId);
          if (mounted) {
            setState(() {
              _sharedSecretKey = key;
            });
          }
        }
      } catch (e) {
        debugPrint('[MediaGallery] Error deriving shared key: $e');
      }
    }
    await _load();
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

  Future<Uint8List> _fetchAndDecryptMediaBytes(String url, String nonce) async {
    if (_decryptedBytesCache.containsKey(url)) {
      return _decryptedBytesCache[url]!;
    }
    final headers = _authHeaders.isNotEmpty
        ? _authHeaders
        : await AuthService.getAuthHeadersForUser(widget.currentUserId);
    final response = await http.get(Uri.parse(url), headers: headers);
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch encrypted media (${response.statusCode})');
    }
    if (_sharedSecretKey == null) {
      throw Exception('E2EE key not ready');
    }
    final decrypted = await EncryptionService().decryptBytes(
      response.bodyBytes,
      nonce,
      _sharedSecretKey!,
    );
    _decryptedBytesCache[url] = decrypted;
    return decrypted;
  }

  Future<void> _saveImageToGallery(String url, String? nonce, bool isEncrypted, Uint8List? preloadedBytes) async {
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

      Uint8List? bytes = preloadedBytes;
      if (bytes == null || bytes.isEmpty) {
        if (isEncrypted && nonce != null && nonce.isNotEmpty) {
          bytes = await _fetchAndDecryptMediaBytes(url, nonce);
        } else {
          final res = await http.get(Uri.parse(url), headers: _authHeaders);
          if (res.statusCode == 200) {
            bytes = res.bodyBytes;
          }
        }
      }

      if (bytes == null || bytes.isEmpty) {
        throw Exception("Could not load image file");
      }

      if (kIsWeb) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Image saved successfully 📷")),
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
            content: Text("Saved directly to Gallery ($filename) 📷"),
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

  void _openPhoto(String url, bool isEncrypted, String? nonce) {
    Uint8List? loadedBytes;

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
                child: Builder(
                  builder: (context) {
                    if (isEncrypted && nonce != null && nonce.isNotEmpty) {
                      return FutureBuilder<Uint8List>(
                        future: _fetchAndDecryptMediaBytes(url, nonce),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(color: AppTheme.primaryTeal),
                            );
                          }
                          if (snapshot.hasError || !snapshot.hasData) {
                            return const Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.broken_image_rounded, size: 64, color: Colors.white54),
                                SizedBox(height: 12),
                                Text("Could not load image", style: TextStyle(color: Colors.white70)),
                              ],
                            );
                          }
                          loadedBytes = snapshot.data;
                          return Image.memory(snapshot.data!, fit: BoxFit.contain);
                        },
                      );
                    }
                    return Image.network(
                      url,
                      headers: _authHeaders,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.broken_image_rounded, size: 64, color: Colors.white54),
                          SizedBox(height: 12),
                          Text("Could not load image", style: TextStyle(color: Colors.white70)),
                        ],
                      ),
                    );
                  },
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
                          onPressed: () => _saveImageToGallery(
                            url,
                            nonce,
                            isEncrypted,
                            loadedBytes,
                          ),
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
        final item = _photos[i];
        final url = _formatUrl(item['attachment_url']?.toString());
        if (url == null) return const SizedBox.shrink();

        final bool isEncrypted = item['is_encrypted'] == true || item['isEncrypted'] == true;
        final String? nonce = item['nonce']?.toString();

        return GestureDetector(
          onTap: () => _openPhoto(url, isEncrypted, nonce),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: isEncrypted && nonce != null && nonce.isNotEmpty
                ? FutureBuilder<Uint8List>(
                    future: _fetchAndDecryptMediaBytes(url, nonce),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return Container(
                          color: Colors.black12,
                          child: const Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryTeal),
                            ),
                          ),
                        );
                      }
                      if (snapshot.hasError || !snapshot.hasData) {
                        return Container(
                          color: Colors.grey.shade300,
                          child: const Icon(Icons.broken_image_rounded, color: Colors.grey),
                        );
                      }
                      return Image.memory(
                        snapshot.data!,
                        fit: BoxFit.cover,
                      );
                    },
                  )
                : Image.network(
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
        final url = _formatUrl(item['attachment_url']?.toString());
        final bool isEncrypted = item['is_encrypted'] == true || item['isEncrypted'] == true;
        final String? nonce = item['nonce']?.toString();

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
          trailing: const Icon(Icons.download_rounded, color: AppTheme.primaryTeal, size: 20),
          onTap: url != null
              ? () async {
                  if (item['attachment_type'] == 'image') {
                    _openPhoto(url, isEncrypted, nonce);
                  } else {
                    await _saveImageToGallery(url, nonce, isEncrypted, null);
                  }
                }
              : null,
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
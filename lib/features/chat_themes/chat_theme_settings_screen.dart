import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../theme/app_theme.dart';
import 'chat_theme.dart';
import 'chat_theme_service.dart';

class ChatThemeSettingsScreen extends StatefulWidget {
  const ChatThemeSettingsScreen({super.key});

  @override
  State<ChatThemeSettingsScreen> createState() => _ChatThemeSettingsScreenState();
}

class _ChatThemeSettingsScreenState extends State<ChatThemeSettingsScreen> {
  ChatThemeMode _selectedMode = ChatThemeMode.defaultTheme;
  String? _customPath;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final mode = await ChatThemeService.getTheme();
    final path = await ChatThemeService.getCustomWallpaperPath();
    if (mounted) {
      setState(() {
        _selectedMode = mode;
        _customPath = path;
        _loading = false;
      });
    }
  }

  Future<void> _selectTheme(ChatThemeMode mode) async {
    if (mode == ChatThemeMode.customWallpaper) {
      final picker = ImagePicker();
      final file = await picker.pickImage(source: ImageSource.gallery);
      if (file == null) return;
      await ChatThemeService.setCustomWallpaperPath(file.path);
      _customPath = file.path;
    }

    await ChatThemeService.setTheme(mode);
    if (mounted) {
      setState(() {
        _selectedMode = mode;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Chat theme set to ${mode.label}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat Theme 🎨', style: TextStyle(fontWeight: FontWeight.w900)),
        backgroundColor: AppTheme.primaryTeal,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Select Chat Wallpaper & Style',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 12),
                ...ChatThemeMode.values.map((mode) {
                  final isSelected = _selectedMode == mode;
                  return Card(
                    color: isSelected ? AppTheme.primaryTeal.withOpacity(0.25) : const Color(0xFF1E293B),
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: isSelected ? AppTheme.primaryTeal : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: ListTile(
                      onTap: () => _selectTheme(mode),
                      leading: Icon(
                        isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                        color: isSelected ? AppTheme.primaryTeal : Colors.grey,
                      ),
                      title: Text(
                        mode.label,
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      subtitle: Text(
                        mode == ChatThemeMode.customWallpaper && _customPath != null
                            ? 'Selected: ${_customPath!.split('/').last}'
                            : mode.description,
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      trailing: mode == ChatThemeMode.customWallpaper
                          ? IconButton(
                              icon: const Icon(Icons.image, color: Colors.white70),
                              onPressed: () => _selectTheme(ChatThemeMode.customWallpaper),
                            )
                          : null,
                    ),
                  );
                }),
              ],
            ),
    );
  }
}

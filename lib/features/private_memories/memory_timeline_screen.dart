import 'package:flutter/material.dart';
import '../../config/api_config.dart';
import '../../theme/app_theme.dart';
import 'add_memory_screen.dart';
import 'memory_model.dart';
import 'memory_service.dart';

class MemoryTimelineScreen extends StatefulWidget {
  const MemoryTimelineScreen({super.key});

  @override
  State<MemoryTimelineScreen> createState() => _MemoryTimelineScreenState();
}

class _MemoryTimelineScreenState extends State<MemoryTimelineScreen> {
  List<MemoryModel> _memories = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadMemories();
  }

  Future<void> _loadMemories() async {
    setState(() => _loading = true);
    final list = await MemoryService.getMemories();
    if (mounted) {
      setState(() {
        _memories = list;
        _loading = false;
      });
    }
  }

  Future<void> _addMemory() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AddMemoryScreen()),
    );
    if (result == true) {
      _loadMemories();
    }
  }

  Future<void> _deleteMemory(MemoryModel memory) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Delete Memory?', style: TextStyle(color: Colors.white)),
        content: const Text('Are you sure you want to delete this memory?', style: TextStyle(color: Colors.grey)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await MemoryService.deleteMemory(memory.id);
      _loadMemories();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Private Memories 🖼️', style: TextStyle(fontWeight: FontWeight.w900)),
        backgroundColor: AppTheme.primaryTeal,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addMemory,
        backgroundColor: AppTheme.primaryTeal,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add_a_photo),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _memories.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.photo_library, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('No memories saved yet', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      SizedBox(height: 8),
                      Text('Tap + to add your special couple memories', style: TextStyle(color: Colors.grey, fontSize: 13)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _memories.length,
                  itemBuilder: (context, index) {
                    final m = _memories[index];
                    final fullUrl = m.mediaUrl.startsWith('http') ? m.mediaUrl : '${ApiConfig.baseUrl}${m.mediaUrl}';
                    return Card(
                      color: const Color(0xFF1E293B),
                      margin: const EdgeInsets.only(bottom: 16),
                      clipBehavior: Clip.antiAlias,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (m.type == 'photo')
                            Image.network(
                              fullUrl,
                              height: 220,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => Container(
                                height: 180,
                                color: Colors.black26,
                                child: const Center(child: Icon(Icons.broken_image, color: Colors.grey, size: 40)),
                              ),
                            )
                          else
                            Container(
                              height: 180,
                              color: Colors.black26,
                              child: const Center(child: Icon(Icons.videocam, color: AppTheme.primaryTeal, size: 48)),
                            ),
                          Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${m.memoryDate.year}-${m.memoryDate.month.toString().padLeft(2, '0')}-${m.memoryDate.day.toString().padLeft(2, '0')}',
                                        style: const TextStyle(color: AppTheme.primaryTeal, fontWeight: FontWeight.bold, fontSize: 12),
                                      ),
                                      if (m.caption != null && m.caption!.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          m.caption!,
                                          style: const TextStyle(color: Colors.white, fontSize: 14),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                  onPressed: () => _deleteMemory(m),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}

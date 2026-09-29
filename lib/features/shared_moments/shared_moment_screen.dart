import 'package:flutter/material.dart';
import '../../config/api_config.dart';
import '../../theme/app_theme.dart';
import 'create_shared_moment_screen.dart';
import 'shared_moment.dart';
import 'shared_moment_service.dart';

class SharedMomentScreen extends StatefulWidget {
  const SharedMomentScreen({super.key});

  @override
  State<SharedMomentScreen> createState() => _SharedMomentScreenState();
}

class _SharedMomentScreenState extends State<SharedMomentScreen> {
  List<SharedMoment> _moments = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadMoments();
  }

  Future<void> _loadMoments() async {
    setState(() => _loading = true);
    final list = await SharedMomentService.getMoments();
    if (mounted) {
      setState(() {
        _moments = list;
        _loading = false;
      });
    }
  }

  Future<void> _addMoment() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const CreateSharedMomentScreen()),
    );
    if (result == true) {
      _loadMoments();
    }
  }

  Future<void> _deleteMoment(SharedMoment moment) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Delete Moment?', style: TextStyle(color: Colors.white)),
        content: const Text('Are you sure you want to delete this shared moment?', style: TextStyle(color: Colors.grey)),
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
      await SharedMomentService.deleteMoment(moment.id);
      _loadMoments();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shared Moments 📍❤️', style: TextStyle(fontWeight: FontWeight.w900)),
        backgroundColor: AppTheme.primaryTeal,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addMoment,
        backgroundColor: AppTheme.primaryTeal,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add_location_alt),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _moments.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.location_on, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('No shared moments yet ❤️', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      SizedBox(height: 8),
                      Text('Save special moments together with optional photos & location', style: TextStyle(color: Colors.grey, fontSize: 13)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _moments.length,
                  itemBuilder: (context, index) {
                    final m = _moments[index];
                    final fullUrl = m.mediaUrl != null
                        ? (m.mediaUrl!.startsWith('http') ? m.mediaUrl! : '${ApiConfig.baseUrl}${m.mediaUrl}')
                        : null;

                    return Card(
                      color: const Color(0xFF1E293B),
                      margin: const EdgeInsets.only(bottom: 16),
                      clipBehavior: Clip.antiAlias,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (fullUrl != null)
                            Image.network(
                              fullUrl,
                              height: 200,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => Container(
                                height: 160,
                                color: Colors.black26,
                                child: const Center(child: Icon(Icons.broken_image, color: Colors.grey, size: 40)),
                              ),
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
                                        '${m.momentDate.year}-${m.momentDate.month.toString().padLeft(2, '0')}-${m.momentDate.day.toString().padLeft(2, '0')}',
                                        style: const TextStyle(color: AppTheme.primaryTeal, fontWeight: FontWeight.bold, fontSize: 12),
                                      ),
                                      if (m.caption != null && m.caption!.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(m.caption!, style: const TextStyle(color: Colors.white, fontSize: 14)),
                                      ],
                                      if (m.locationEnabled && m.latitude != null && m.longitude != null) ...[
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            const Icon(Icons.location_on, color: Colors.pinkAccent, size: 14),
                                            const SizedBox(width: 4),
                                            Text(
                                              '${m.latitude!.toStringAsFixed(3)}, ${m.longitude!.toStringAsFixed(3)}',
                                              style: const TextStyle(color: Colors.white70, fontSize: 11),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                  onPressed: () => _deleteMoment(m),
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

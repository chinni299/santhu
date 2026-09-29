import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import '../../theme/app_theme.dart';
import 'shared_moment_service.dart';

class CreateSharedMomentScreen extends StatefulWidget {
  const CreateSharedMomentScreen({super.key});

  @override
  State<CreateSharedMomentScreen> createState() => _CreateSharedMomentScreenState();
}

class _CreateSharedMomentScreenState extends State<CreateSharedMomentScreen> {
  File? _selectedFile;
  final _captionController = TextEditingController();
  final DateTime _momentDate = DateTime.now();

  bool _shareLocation = false; // DEFAULT: Location sharing = OFF
  double? _latitude;
  double? _longitude;
  bool _fetchingLocation = false;
  bool _saving = false;

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: source);
    if (file != null) {
      setState(() => _selectedFile = File(file.path));
    }
  }

  Future<void> _toggleLocationSharing(bool enable) async {
    if (!enable) {
      setState(() {
        _shareLocation = false;
        _latitude = null;
        _longitude = null;
      });
      return;
    }

    // Explicit opt-in consent dialog
    final consent = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Share Location?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text(
          'Share location with this memory?\nYour location will be saved only for this moment.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Don\'t Share'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.primaryTeal),
            child: const Text('Share'),
          ),
        ],
      ),
    );

    if (consent != true) return;

    setState(() => _fetchingLocation = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
        if (mounted) {
          setState(() {
            _shareLocation = true;
            _latitude = pos.latitude;
            _longitude = pos.longitude;
            _fetchingLocation = false;
          });
        }
      } else {
        if (mounted) {
          setState(() => _fetchingLocation = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permission denied. Saving moment without location.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _fetchingLocation = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not get location: $e')),
        );
      }
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final moment = await SharedMomentService.createMoment(
      file: _selectedFile,
      caption: _captionController.text.trim().isNotEmpty ? _captionController.text.trim() : null,
      latitude: _latitude,
      longitude: _longitude,
      locationEnabled: _shareLocation,
      momentDate: _momentDate,
    );

    if (mounted) {
      setState(() => _saving = false);
      if (moment != null) {
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save shared moment')),
        );
      }
    }
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Shared Moment 📍❤️', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppTheme.primaryTeal,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 180,
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
              ),
              child: _selectedFile != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.file(_selectedFile!, fit: BoxFit.cover, width: double.infinity),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.photo_library, size: 36, color: AppTheme.primaryTeal),
                              onPressed: () => _pickImage(ImageSource.gallery),
                            ),
                            const SizedBox(width: 20),
                            IconButton(
                              icon: const Icon(Icons.camera_alt, size: 36, color: AppTheme.primaryTeal),
                              onPressed: () => _pickImage(ImageSource.camera),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text('Optional Photo', style: TextStyle(color: Colors.grey, fontSize: 13)),
                      ],
                    ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _captionController,
              style: const TextStyle(color: Colors.white),
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Caption / Story',
                labelStyle: TextStyle(color: Colors.grey),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            // Location sharing section (Opt-in explicit choice)
            Card(
              color: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: SwitchListTile(
                title: const Text('Attach Location 📍', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: Text(
                  _shareLocation && _latitude != null
                      ? 'Location attached (${_latitude!.toStringAsFixed(3)}, ${_longitude!.toStringAsFixed(3)})'
                      : 'Default OFF: Tap to share location for this moment',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
                value: _shareLocation,
                activeTrackColor: AppTheme.primaryTeal,
                onChanged: _fetchingLocation ? null : (val) => _toggleLocationSharing(val),
              ),
            ),

            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryTeal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: _saving
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Save Shared Moment', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

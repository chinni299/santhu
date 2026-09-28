import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../theme/app_theme.dart';
import 'memory_service.dart';

class AddMemoryScreen extends StatefulWidget {
  const AddMemoryScreen({super.key});

  @override
  State<AddMemoryScreen> createState() => _AddMemoryScreenState();
}

class _AddMemoryScreenState extends State<AddMemoryScreen> {
  File? _selectedFile;
  String _type = 'photo';
  final _captionController = TextEditingController();
  DateTime _memoryDate = DateTime.now();
  bool _uploading = false;

  Future<void> _pickFile(ImageSource source, bool isVideo) async {
    final picker = ImagePicker();
    if (isVideo) {
      final file = await picker.pickVideo(source: source);
      if (file != null) {
        setState(() {
          _selectedFile = File(file.path);
          _type = 'video';
        });
      }
    } else {
      final file = await picker.pickImage(source: source);
      if (file != null) {
        setState(() {
          _selectedFile = File(file.path);
          _type = 'photo';
        });
      }
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _memoryDate,
      firstDate: DateTime(1990),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppTheme.primaryTeal,
              surface: Color(0xFF1E293B),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _memoryDate = picked);
    }
  }

  Future<void> _upload() async {
    if (_selectedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a photo or video first')),
      );
      return;
    }

    setState(() => _uploading = true);
    final memory = await MemoryService.createMemory(
      file: _selectedFile!,
      type: _type,
      caption: _captionController.text.trim().isNotEmpty ? _captionController.text.trim() : null,
      memoryDate: _memoryDate,
    );

    if (mounted) {
      setState(() => _uploading = false);
      if (memory != null) {
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to upload memory')),
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
        title: const Text('Add Private Memory 🖼️', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppTheme.primaryTeal,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.withOpacity(0.3)),
              ),
              child: _selectedFile != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: _type == 'photo'
                          ? Image.file(_selectedFile!, fit: BoxFit.cover, width: double.infinity)
                          : const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.videocam, size: 48, color: AppTheme.primaryTeal),
                                  SizedBox(height: 8),
                                  Text('Video Selected', style: TextStyle(color: Colors.white)),
                                ],
                              ),
                            ),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.photo_library, size: 36, color: AppTheme.primaryTeal),
                              onPressed: () => _pickFile(ImageSource.gallery, false),
                            ),
                            const SizedBox(width: 20),
                            IconButton(
                              icon: const Icon(Icons.camera_alt, size: 36, color: AppTheme.primaryTeal),
                              onPressed: () => _pickFile(ImageSource.camera, false),
                            ),
                            const SizedBox(width: 20),
                            IconButton(
                              icon: const Icon(Icons.videocam, size: 36, color: AppTheme.primaryTeal),
                              onPressed: () => _pickFile(ImageSource.gallery, true),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text('Tap to choose photo or video', style: TextStyle(color: Colors.grey, fontSize: 13)),
                      ],
                    ),
            ),
            const SizedBox(height: 20),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: Colors.grey),
              ),
              title: const Text('Memory Date', style: TextStyle(color: Colors.grey, fontSize: 12)),
              subtitle: Text(
                '${_memoryDate.year}-${_memoryDate.month.toString().padLeft(2, '0')}-${_memoryDate.day.toString().padLeft(2, '0')}',
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              trailing: const Icon(Icons.calendar_month, color: AppTheme.primaryTeal),
              onTap: _pickDate,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _captionController,
              style: const TextStyle(color: Colors.white),
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Caption / Note',
                labelStyle: TextStyle(color: Colors.grey),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _uploading ? null : _upload,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryTeal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: _uploading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Save Memory', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

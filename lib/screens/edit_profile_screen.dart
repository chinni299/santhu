import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

class EditProfileScreen extends StatefulWidget {
  final int currentUserId;

  const EditProfileScreen({
    super.key,
    required this.currentUserId,
  });

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();

  String _selectedGender = 'Male';
  final List<String> _genderOptions = ['Male', 'Female', 'Other', 'Prefer not to say'];

  bool _isLoading = true;
  File? _avatarFile;
  Uint8List? _avatarBytes;
  String? _avatarPath;
  String? _avatarUrl;
  String? _avatarFilename;

  @override
  void initState() {
    super.initState();
    _loadCurrentProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentProfile() async {
    final user = await AuthService.getUser();

    final defaultEmail = widget.currentUserId == 1 ? 'user1@example.com' : 'user2@example.com';
    final name = user['name'] ?? user['username'] ?? (widget.currentUserId == 1 ? 'Albert Florest' : 'Leslie Alexander');
    final username = user['username_handle'] ?? user['username']?.toString().toLowerCase().replaceAll(' ', '_') ?? 'albertflorest_';
    final gender = user['gender'] ?? 'Male';
    final phone = user['phone'] ?? '+44 1632 960860';
    final email = user['email'] ?? defaultEmail;
    final savedAvatar = await AuthService.getAvatarPath(widget.currentUserId) ?? user['avatar_path'];

    setState(() {
      _nameController.text = name;
      _usernameController.text = username;
      _phoneController.text = phone;
      _emailController.text = email;
      _avatarUrl = user['avatar_url'] ?? AuthService.getAvatarUrl(widget.currentUserId);
      if (_genderOptions.contains(gender)) {
        _selectedGender = gender;
      }
      if (savedAvatar != null && savedAvatar.toString().isNotEmpty) {
        _avatarPath = savedAvatar.toString();
        if (!kIsWeb) {
          final file = File(_avatarPath!);
          if (file.existsSync()) {
            _avatarFile = file;
          }
        }
      }
      _isLoading = false;
    });
  }

  Future<void> _pickAvatarImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      final bytes = await picked.readAsBytes();
      setState(() {
        _avatarBytes = bytes;
        _avatarFilename = picked.name;
        _avatarPath = picked.path;
        if (!kIsWeb) {
          _avatarFile = File(picked.path);
        }
      });
    }
  }

  Future<void> _saveProfile() async {
    final name = _nameController.text.trim();
    final username = _usernameController.text.trim();
    final phone = _phoneController.text.trim();
    final email = _emailController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Name cannot be empty")),
      );
      return;
    }

    if (_avatarBytes != null) {
      await AuthService.uploadAvatar(
        userId: widget.currentUserId,
        bytes: _avatarBytes!,
        filename: _avatarFilename ?? 'avatar.jpg',
        localFilePath: _avatarPath,
      );
    }

    final updatedData = {
      'name': name,
      'username': name,
      'username_handle': username,
      'gender': _selectedGender,
      'phone': phone,
      'email': email,
      'avatar_path': _avatarPath ?? '',
    };

    await AuthService.updateUserProfile(updatedData);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Profile updated successfully! ✅"),
          backgroundColor: AppTheme.primaryTeal,
        ),
      );
      Navigator.pop(context, true);
    }
  }

  Widget _buildLetterAvatar() {
    return Container(
      color: AppTheme.primaryTeal.withValues(alpha: 0.15),
      child: Center(
        child: Text(
          _nameController.text.isNotEmpty
              ? _nameController.text[0].toUpperCase()
              : 'U',
          style: const TextStyle(
            fontSize: 42,
            fontWeight: FontWeight.w900,
            color: AppTheme.primaryTeal,
          ),
        ),
      ),
    );
  }

  Widget _buildFormFieldLabel(String label, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, top: 16.0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white70 : const Color(0xFF111B21),
          ),
        ),
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required bool isDark,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F2C33) : const Color(0xFFF5F6F8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white : const Color(0xFF222222),
        ),
        decoration: const InputDecoration(
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121E24) : Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: Padding(
          padding: const EdgeInsets.all(10.0),
          child: InkWell(
            onTap: () => Navigator.pop(context),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.primaryTeal.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.chevron_left_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
        ),
        title: Text(
          'Edit Profile',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: isDark ? Colors.white : const Color(0xFF111B21),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryTeal))
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Column(
                children: [
                  const SizedBox(height: 10),

                  // Avatar Picker Section
                  Center(
                    child: Stack(
                      children: [
                        Container(
                          width: 110,
                          height: 110,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppTheme.primaryTeal.withValues(alpha: 0.5),
                              width: 3,
                            ),
                          ),
                          child: ClipOval(
                            child: Builder(
                              builder: (context) {
                                if (_avatarBytes != null) {
                                  return Image.memory(_avatarBytes!, fit: BoxFit.cover, width: 110, height: 110);
                                }
                                if (_avatarFile != null && !kIsWeb && _avatarFile!.existsSync()) {
                                  return Image.file(_avatarFile!, fit: BoxFit.cover, width: 110, height: 110);
                                }
                                if (_avatarUrl != null && _avatarUrl!.isNotEmpty) {
                                  return Image.network(
                                    _avatarUrl!,
                                    fit: BoxFit.cover,
                                    width: 110,
                                    height: 110,
                                    errorBuilder: (_, _, _) => _buildLetterAvatar(),
                                  );
                                }
                                return _buildLetterAvatar();
                              },
                            ),
                          ),
                        ),
                        Positioned(
                          right: 2,
                          bottom: 2,
                          child: GestureDetector(
                            onTap: _pickAvatarImage,
                            child: Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: AppTheme.primaryTeal,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isDark ? const Color(0xFF121E24) : Colors.white,
                                  width: 2.5,
                                ),
                              ),
                              child: const Icon(
                                Icons.camera_alt_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Field 1: Name
                  _buildFormFieldLabel('Name', isDark),
                  _buildInputField(controller: _nameController, isDark: isDark),

                  // Field 2: Username
                  _buildFormFieldLabel('Username', isDark),
                  _buildInputField(controller: _usernameController, isDark: isDark),

                  // Field 3: Gender Dropdown
                  _buildFormFieldLabel('Gender', isDark),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1F2C33) : const Color(0xFFF5F6F8),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedGender,
                        icon: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: isDark ? Colors.white70 : const Color(0xFF111B21),
                          size: 26,
                        ),
                        dropdownColor: isDark ? const Color(0xFF1F2C33) : Colors.white,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : const Color(0xFF222222),
                        ),
                        items: _genderOptions.map((String value) {
                          return DropdownMenuItem<String>(
                            value: value,
                            child: Text(value),
                          );
                        }).toList(),
                        onChanged: (newValue) {
                          if (newValue != null) {
                            setState(() {
                              _selectedGender = newValue;
                            });
                          }
                        },
                      ),
                    ),
                  ),

                  // Field 4: Phone Number
                  _buildFormFieldLabel('Phone Number', isDark),
                  _buildInputField(
                    controller: _phoneController,
                    isDark: isDark,
                    keyboardType: TextInputType.phone,
                  ),

                  // Field 5: Email
                  _buildFormFieldLabel('Email', isDark),
                  _buildInputField(
                    controller: _emailController,
                    isDark: isDark,
                    keyboardType: TextInputType.emailAddress,
                  ),

                  const SizedBox(height: 36),

                  // Save Button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryTeal,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _saveProfile,
                      child: const Text(
                        'Save',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../services/auth_service.dart';
import '../services/app_lock_service.dart';
import '../theme/app_theme.dart';
import 'edit_profile_screen.dart';
import 'login_screen.dart';

class ProfileScreen extends StatefulWidget {
  final int currentUserId;

  const ProfileScreen({
    super.key,
    required this.currentUserId,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic> _userData = {};
  bool _isLoading = true;
  bool _notificationsEnabled = true;
  File? _avatarFile;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user = await AuthService.getUser();
    File? avatarFile;
    if (user['avatar_path'] != null && user['avatar_path'].toString().isNotEmpty) {
      final f = File(user['avatar_path'].toString());
      if (f.existsSync()) {
        avatarFile = f;
      }
    }
    setState(() {
      _userData = user.isNotEmpty
          ? user
          : {
              'name': widget.currentUserId == 1 ? 'Albert Florest' : 'Leslie Alexander',
              'username': widget.currentUserId == 1 ? 'Albert Florest' : 'Leslie Alexander',
              'role': 'Buyer',
              'email': widget.currentUserId == 1 ? 'user1@example.com' : 'user2@example.com',
            };
      _avatarFile = avatarFile;
      _isLoading = false;
    });
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _avatarFile = File(image.path);
      });
      await AuthService.updateUserProfile({'avatar_path': image.path});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Profile picture updated successfully!"),
            backgroundColor: AppTheme.primaryTeal,
          ),
        );
      }
    }
  }

  void _showChangePinDialog() {
    final currentPinController = TextEditingController();
    final newPinController = TextEditingController();
    final confirmPinController = TextEditingController();
    String? errorMessage;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              backgroundColor: isDark ? const Color(0xFF1F2C33) : Colors.white,
              title: const Row(
                children: [
                  Icon(Icons.lock_outline_rounded, color: AppTheme.primaryTeal),
                  SizedBox(width: 10),
                  Text("Change App PIN", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "Set or update your 6-digit security PIN used to unlock DuoChat.",
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: currentPinController,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: "Current PIN (default: 123456)",
                        prefixIcon: const Icon(Icons.pin_outlined),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        counterText: "",
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: newPinController,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: "New 6-Digit PIN",
                        prefixIcon: const Icon(Icons.lock_clock_outlined),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        counterText: "",
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: confirmPinController,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: "Confirm New PIN",
                        prefixIcon: const Icon(Icons.check_circle_outline_rounded),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        counterText: "",
                      ),
                    ),
                    if (errorMessage != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        errorMessage!,
                        style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ],
                  ],
                ),
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
                    final curr = currentPinController.text.trim();
                    final next = newPinController.text.trim();
                    final conf = confirmPinController.text.trim();

                    if (curr.length != 6 || next.length != 6 || conf.length != 6) {
                      setDialogState(() {
                        errorMessage = "All PIN fields must be exactly 6 digits!";
                      });
                      return;
                    }

                    final isCurrentValid = await AuthService.verifyPin(curr);
                    if (!isCurrentValid) {
                      setDialogState(() {
                        errorMessage = "Incorrect current PIN!";
                      });
                      return;
                    }

                    if (next != conf) {
                      setDialogState(() {
                        errorMessage = "New PIN and Confirm PIN do not match!";
                      });
                      return;
                    }

                    await AuthService.savePin(next);

                    if (context.mounted) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("6-Digit App PIN updated successfully! 🔒"),
                          backgroundColor: AppTheme.primaryTeal,
                        ),
                      );
                    }
                  },
                  child: const Text("Update PIN", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showNotificationSettingsDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              backgroundColor: isDark ? const Color(0xFF1F2C33) : Colors.white,
              title: const Text("Notifications", style: TextStyle(fontWeight: FontWeight.w900)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    title: const Text("Push Notifications"),
                    subtitle: const Text("Receive alerts for new messages"),
                    activeThumbColor: AppTheme.primaryTeal,
                    value: _notificationsEnabled,
                    onChanged: (val) {
                      setDialogState(() {
                        _notificationsEnabled = val;
                      });
                      setState(() {
                        _notificationsEnabled = val;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("Done"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showAddressDialog() {
    final addressController = TextEditingController(
      text: _userData['address'] ?? "123 Security Blvd, DuoChat Encrypted Zone",
    );
    showDialog(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: isDark ? const Color(0xFF1F2C33) : Colors.white,
          title: const Text("Shipping Address", style: TextStyle(fontWeight: FontWeight.w900)),
          content: TextField(
            controller: addressController,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: "Address",
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
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
                setState(() {
                  _userData['address'] = addressController.text.trim();
                });
                await AuthService.saveSession(
                  await AuthService.getToken() ?? '',
                  _userData,
                );
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                }
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Address saved!"),
                      backgroundColor: AppTheme.primaryTeal,
                    ),
                  );
                }
              },
              child: const Text("Save", style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F2C33) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppTheme.primaryTeal.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: AppTheme.primaryTeal,
            size: 22,
          ),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : const Color(0xFF111B21),
          ),
        ),
        trailing: Icon(
          Icons.chevron_right_rounded,
          color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
          size: 24,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final userName = _userData['name'] ?? _userData['username'] ?? 'User ${widget.currentUserId}';
    final userRole = _userData['role'] ?? _userData['status'] ?? 'Buyer';

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121E24) : const Color(0xFFF7F9FA),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: isDark ? Colors.white : const Color(0xFF111B21),
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Profile',
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

                  // Avatar Picture with Edit Badge
                  Center(
                    child: Stack(
                      children: [
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppTheme.primaryTeal.withValues(alpha: 0.4),
                              width: 3,
                            ),
                          ),
                          child: ClipOval(
                            child: _avatarFile != null
                                ? Image.file(_avatarFile!, fit: BoxFit.cover)
                                : Container(
                                    color: AppTheme.primaryTeal.withValues(alpha: 0.15),
                                    child: Center(
                                      child: Text(
                                        userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
                                        style: const TextStyle(
                                          fontSize: 46,
                                          fontWeight: FontWeight.w900,
                                          color: AppTheme.primaryTeal,
                                        ),
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                        Positioned(
                          right: 2,
                          bottom: 2,
                          child: GestureDetector(
                            onTap: _pickAvatar,
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
                                Icons.edit_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // User Full Name
                  Text(
                    userName,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: isDark ? Colors.white : const Color(0xFF111B21),
                    ),
                  ),

                  const SizedBox(height: 4),

                  // User Subtitle / Role
                  Text(
                    userRole,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                    ),
                  ),

                  const SizedBox(height: 36),

                  // Menu Option 1: Edit Profile
                  _buildMenuItem(
                    icon: Icons.person_outline_rounded,
                    title: 'Edit Profile',
                    isDark: isDark,
                    onTap: () async {
                      final updated = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => EditProfileScreen(
                            currentUserId: widget.currentUserId,
                          ),
                        ),
                      );
                      if (updated == true) {
                        _loadProfile();
                      }
                    },
                  ),

                  // Menu Option 2: Notification
                  _buildMenuItem(
                    icon: Icons.notifications_none_rounded,
                    title: 'Notification',
                    isDark: isDark,
                    onTap: _showNotificationSettingsDialog,
                  ),

                  // Menu Option 3: Shipping Address
                  _buildMenuItem(
                    icon: Icons.location_on_outlined,
                    title: 'Shipping Address',
                    isDark: isDark,
                    onTap: _showAddressDialog,
                  ),

                  // Menu Option 4: Change Password (PIN)
                  _buildMenuItem(
                    icon: Icons.lock_outline_rounded,
                    title: 'Change Password',
                    isDark: isDark,
                    onTap: _showChangePinDialog,
                  ),

                  const SizedBox(height: 28),

                  // Sign Out Button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryTeal,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () async {
                        final nav = Navigator.of(context);
                        await AuthService.logout();
                        AppLockService.lockApp();
                        nav.pushAndRemoveUntil(
                          MaterialPageRoute(builder: (_) => const LoginScreen()),
                          (route) => false,
                        );
                      },
                      icon: const Icon(
                        Icons.logout_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                      label: const Text(
                        'Sign Out',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }
}

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import 'conversation_list_screen.dart';

class LoginScreen extends StatefulWidget {
  final void Function(Map<String, dynamic> user)? onLoginSuccess;

  const LoginScreen({super.key, this.onLoginSuccess});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool obscurePassword = true;
  bool isLoading = false;

  String get baseUrl => ApiConfig.baseUrl;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> handleLogin() async {
    FocusScope.of(context).unfocus();

    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter email and password'),
        ),
      );
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
        }),
      );

      final data = jsonDecode(utf8.decode(response.bodyBytes));

      if (!mounted) return;

      if (response.statusCode == 200 && data['success'] == true) {
        final user = data['user'];
        final token = data['token'];
        final userId = user != null && user['id'] != null
            ? int.parse(user['id'].toString())
            : 1;

        if (token != null && user != null) {
          await AuthService.saveSession(token.toString(), Map<String, dynamic>.from(user), password);
        }

        if (!mounted) return;

        // If a callback is provided (app.dart controls navigation), use it.
        // Otherwise fall back to direct Navigator push (standalone use).
        if (widget.onLoginSuccess != null) {
          widget.onLoginSuccess!(Map<String, dynamic>.from(user ?? {'id': userId}));
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => ConversationListScreen(currentUserId: userId),
            ),
          );
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Welcome ${user?['name'] ?? 'Back'} 👋'),
            backgroundColor: AppTheme.primaryTeal,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['message'] ?? 'Invalid email or password'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not connect to server. Check your connection.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121E24) : const Color(0xFFE8F6F4),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Top Soft Decorative Header Banner
            Container(
              width: double.infinity,
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 20,
                bottom: 20,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? [const Color(0xFF0F4C4C), const Color(0xFF121E24)]
                      : [const Color(0xFFD2F1EC), const Color(0xFFE8F6F4)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Floating Decorative Badges
                  Positioned(
                    left: 35,
                    top: 10,
                    child: _buildFloatingBadge(
                      icon: Icons.chat_bubble_rounded,
                      color: const Color(0xFF149B9B),
                    ),
                  ),
                  Positioned(
                    right: 40,
                    top: 20,
                    child: _buildFloatingBadge(
                      icon: Icons.lock_rounded,
                      color: const Color(0xFF0F766E),
                    ),
                  ),
                  Positioned(
                    right: 85,
                    bottom: 10,
                    child: _buildFloatingBadge(
                      icon: Icons.check_circle_rounded,
                      color: const Color(0xFF00E676),
                    ),
                  ),

                  // Center Logo
                  Column(
                    children: [
                      Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF149B9B).withValues(alpha: 0.35),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: Image.asset(
                            'assets/images/clock_logo.png',
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Clock',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: isDark ? Colors.white : const Color(0xFF0F766E),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Login Card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1F2C33) : Colors.white,
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Card Header
                      Text(
                        'Welcome Back!',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: isDark ? Colors.white : const Color(0xFF111B21),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Login to continue',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                        ),
                      ),

                      const SizedBox(height: 28),

                      // Email Input
                      Container(
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF121E24) : const Color(0xFFF5F7F8),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: TextField(
                          controller: emailController,
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          enableSuggestions: false,
                          textCapitalization: TextCapitalization.none,
                          style: TextStyle(
                            color: isDark ? Colors.white : const Color(0xFF111B21),
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Email',
                            hintStyle: TextStyle(
                              color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                            prefixIcon: const Icon(
                              Icons.person_rounded,
                              color: AppTheme.primaryTeal,
                              size: 22,
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Password Input
                      Container(
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF121E24) : const Color(0xFFF5F7F8),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: TextField(
                          controller: passwordController,
                          obscureText: obscurePassword,
                          autocorrect: false,
                          enableSuggestions: false,
                          textCapitalization: TextCapitalization.none,
                          style: TextStyle(
                            color: isDark ? Colors.white : const Color(0xFF111B21),
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Password',
                            hintStyle: TextStyle(
                              color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                            prefixIcon: const Icon(
                              Icons.lock_rounded,
                              color: AppTheme.primaryTeal,
                              size: 22,
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                size: 20,
                              ),
                              onPressed: () {
                                setState(() {
                                  obscurePassword = !obscurePassword;
                                });
                              },
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          ),
                        ),
                      ),

                      const SizedBox(height: 28),

                      // Login Button
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF0F766E), Color(0xFF149B9B), Color(0xFF0D8383)],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                            borderRadius: BorderRadius.circular(26),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF149B9B).withValues(alpha: 0.3),
                                blurRadius: 12,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            onPressed: isLoading ? null : handleLogin,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(26),
                              ),
                            ),
                            child: isLoading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                                  )
                                : const Text(
                                    'Login',
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Private App Notice
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.shield_rounded,
                            size: 14,
                            color: isDark ? Colors.grey.shade500 : Colors.grey.shade400,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Private. Invite only.',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.grey.shade500 : Colors.grey.shade400,
                            ),
                          ),
                        ],
                      ),
                    ],
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

  Widget _buildFloatingBadge({required IconData icon, required Color color}) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.25),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Icon(icon, color: color, size: 24),
    );
  }
}
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import 'conversation_list_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool isSignUpMode = false;
  bool obscurePassword = true;
  bool isLoading = false;

  String get baseUrl => ApiConfig.baseUrl;

  @override
  void initState() {
    super.initState();
    // Default preset for easy testing
    emailController.text = 'user1@example.com';
    passwordController.text = 'password123';
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> loginWithUserId(int userId) async {
    FocusScope.of(context).unfocus();
    try {
      final email = userId == 1 ? 'user1@example.com' : 'user2@example.com';
      final res = await AuthService.login(email, 'password123');
      if (res['success'] == true && res['token'] != null) {
        debugPrint("Logged in preset user $userId with token ✅");
      }
    } catch (e) {
      debugPrint("Preset login error: $e");
    }

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ConversationListScreen(currentUserId: userId),
      ),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Logged in as User $userId 👋'),
        backgroundColor: AppTheme.primaryTeal,
      ),
    );
  }

  Future<void> handleAuth() async {
    FocusScope.of(context).unfocus();

    final email = emailController.text.trim();
    final password = passwordController.text;

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
      final endpoint = isSignUpMode ? '$baseUrl/auth/register' : '$baseUrl/auth/login';
      final response = await http.post(
        Uri.parse(endpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
          if (isSignUpMode) 'name': email.split('@').first,
        }),
      );

      final data = jsonDecode(response.body);

      if (!mounted) return;

      if ((response.statusCode == 200 || response.statusCode == 201) && data['success'] == true) {
        final user = data['user'];
        final token = data['token'];
        final userId = user != null && user['id'] != null
            ? int.parse(user['id'].toString())
            : 1;

        if (token != null && user != null) {
          await AuthService.saveSession(token.toString(), Map<String, dynamic>.from(user));
        }

        if (!mounted) return;

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ConversationListScreen(currentUserId: userId),
          ),
        );

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Welcome ${user['name'] ?? 'Back'} 👋'),
            backgroundColor: AppTheme.primaryTeal,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['message'] ?? 'Authentication failed'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      // Fallback for offline local dev mode
      final fallbackUserId = email.contains('2') ? 2 : 1;
      loginWithUserId(fallbackUserId);
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

                  // Center 3D Illustration Avatar Stack
                  Column(
                    children: [
                      Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [Color(0xFF0F766E), Color(0xFF149B9B)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF149B9B).withValues(alpha: 0.35),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.person_pin_rounded,
                          color: Colors.white,
                          size: 54,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'DuoChat',
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

            // Floating Claymorphism Card Container
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
                        isSignUpMode ? 'Create Account' : 'Welcome Back!',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: isDark ? Colors.white : const Color(0xFF111B21),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isSignUpMode ? 'Sign up to start chatting' : 'Login to continue',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                        ),
                      ),

                      const SizedBox(height: 28),

                      // Username / Email Input Pill
                      Container(
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF121E24) : const Color(0xFFF5F7F8),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: TextField(
                          controller: emailController,
                          keyboardType: TextInputType.emailAddress,
                          style: TextStyle(
                            color: isDark ? Colors.white : const Color(0xFF111B21),
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Username / Email',
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

                      // Password Input Pill
                      Container(
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF121E24) : const Color(0xFFF5F7F8),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: TextField(
                          controller: passwordController,
                          obscureText: obscurePassword,
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

                      const SizedBox(height: 10),

                      // Forgot Password Link
                      if (!isSignUpMode)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Password reset instructions sent!')),
                              );
                            },
                            child: Text(
                              'Forgot Password?',
                              style: TextStyle(
                                color: isDark ? AppTheme.primaryTeal : const Color(0xFF0F766E),
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),

                      const SizedBox(height: 16),

                      // Action Button (Teal Gradient Pill)
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
                            onPressed: isLoading ? null : handleAuth,
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
                                : Text(
                                    isSignUpMode ? 'Sign Up' : 'Login',
                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Divider "or continue with"
                      Row(
                        children: [
                          Expanded(
                            child: Divider(
                              color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                              thickness: 1,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              'or continue with',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: isDark ? Colors.grey.shade400 : Colors.grey.shade500,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Divider(
                              color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                              thickness: 1,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),

                      // Quick User Presets / Social Login Buttons
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // User 1 Button
                          _buildSocialButton(
                            label: 'User 1',
                            color: const Color(0xFF0F766E),
                            onTap: () => loginWithUserId(1),
                          ),
                          const SizedBox(width: 16),

                          // User 2 Button
                          _buildSocialButton(
                            label: 'User 2',
                            color: const Color(0xFF149B9B),
                            onTap: () => loginWithUserId(2),
                          ),
                          const SizedBox(width: 16),

                          // Google Icon Button
                          _buildSocialButton(
                            label: 'G',
                            color: const Color(0xFFEA4335),
                            isGoogle: true,
                            onTap: () => loginWithUserId(1),
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // Toggle Login vs Sign Up
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            isSignUpMode = !isSignUpMode;
                          });
                        },
                        child: RichText(
                          text: TextSpan(
                            text: isSignUpMode ? "Already have an account? " : "Don't have an account? ",
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                            ),
                            children: [
                              TextSpan(
                                text: isSignUpMode ? 'Login' : 'Sign Up',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                  color: AppTheme.primaryTeal,
                                ),
                              ),
                            ],
                          ),
                        ),
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

  Widget _buildSocialButton({
    required String label,
    required Color color,
    bool isGoogle = false,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF121E24) : Colors.white,
          shape: BoxShape.circle,
          border: Border.all(
            color: isDark ? Colors.grey.shade700 : Colors.grey.shade200,
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: isGoogle ? 20 : 12,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}
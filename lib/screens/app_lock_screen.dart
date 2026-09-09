import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/app_lock_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

class AppLockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;

  const AppLockScreen({
    super.key,
    required this.onUnlocked,
  });

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  String _enteredPin = '';
  String _firstPin = '';
  bool _isSettingUpPin = false;
  bool _isConfirmingPin = false;
  String _errorMessage = '';
  bool _isError = false;
  bool _isBiometricAvailable = false;

  @override
  void initState() {
    super.initState();
    _checkSetupStatus();
  }

  Future<void> _checkSetupStatus() async {
    final hasPin = await AuthService.hasPin();
    final bioAvailable = await AppLockService.isBiometricAvailable();

    if (!mounted) return;

    setState(() {
      _isSettingUpPin = !hasPin;
      _isBiometricAvailable = bioAvailable;
    });

    if (hasPin && bioAvailable) {
      // Auto-trigger biometric prompt on page load
      _triggerBiometric();
    }
  }

  Future<void> _triggerBiometric() async {
    final success = await AppLockService.authenticateBiometric();
    if (success && mounted) {
      widget.onUnlocked();
    }
  }

  void _onKeyPress(String digit) {
    HapticFeedback.lightImpact();
    if (_enteredPin.length < 6) {
      setState(() {
        _enteredPin += digit;
        _errorMessage = '';
      });

      if (_enteredPin.length == 6) {
        _handleCompletePin();
      }
    }
  }

  void _onBackspace() {
    HapticFeedback.selectionClick();
    if (_enteredPin.isNotEmpty) {
      setState(() {
        _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
        _errorMessage = '';
      });
    }
  }

  Future<void> _handleCompletePin() async {
    if (_isSettingUpPin) {
      if (!_isConfirmingPin) {
        // Step 1 done, move to confirmation
        setState(() {
          _firstPin = _enteredPin;
          _enteredPin = '';
          _isConfirmingPin = true;
        });
      } else {
        // Step 2 confirmation check
        if (_enteredPin == _firstPin) {
          await AuthService.savePin(_enteredPin);
          AppLockService.unlockApp();
          if (mounted) widget.onUnlocked();
        } else {
          HapticFeedback.vibrate();
          setState(() {
            _errorMessage = 'PINs do not match. Try again.';
            _enteredPin = '';
            _firstPin = '';
            _isConfirmingPin = false;
          });
        }
      }
    } else {
      // Unlock Mode check
      final isValid = await AuthService.verifyPin(_enteredPin);
      if (isValid) {
        AppLockService.unlockApp();
        if (mounted) widget.onUnlocked();
      } else {
        HapticFeedback.vibrate();
        setState(() {
          _isError = true;
          _errorMessage = 'Invalid PIN. Try again.';
        });
        await Future.delayed(const Duration(milliseconds: 600));
        if (mounted) {
          setState(() {
            _isError = false;
            _enteredPin = '';
          });
        }
      }
    }
  }

  Future<void> _resetPin() async {
    await AuthService.deletePin();
    if (mounted) {
      setState(() {
        _enteredPin = '';
        _firstPin = '';
        _isSettingUpPin = true;
        _isConfirmingPin = false;
        _errorMessage = '';
      });
    }
  }

  String get _titleText {
    if (_isSettingUpPin) {
      return _isConfirmingPin ? 'Confirm 6-Digit PIN' : 'Create 6-Digit PIN';
    }
    return 'Clock Private Lock';
  }

  String get _subtitleText {
    if (_isSettingUpPin) {
      return _isConfirmingPin
          ? 'Re-enter your 6-digit PIN to confirm'
          : 'Set a private PIN to secure your conversations';
    }
    return 'Enter your 6-digit PIN to access private chat';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: false, // Prevent back navigation while locked
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF0F171A) : const Color(0xFFE8F6F4),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight - 16),
                  child: IntrinsicHeight(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 8),

                        // Header Lock Icon & Titles
                        Container(
                          width: 56,
                          height: 56,
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
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.lock_outline_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),

                        const SizedBox(height: 10),

                        Text(
                          _titleText,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: isDark ? Colors.white : const Color(0xFF111B21),
                          ),
                        ),

                        const SizedBox(height: 4),

                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Text(
                            _subtitleText,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                            ),
                          ),
                        ),

                        const SizedBox(height: 14),

                        // 6 PIN Dot Indicators
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(6, (index) {
                            final isFilled = index < _enteredPin.length;
                            final dotColor = _isError
                                ? Colors.redAccent
                                : (isFilled ? AppTheme.primaryTeal : (isDark ? Colors.grey.shade800 : Colors.grey.shade300));
                            final borderColor = _isError
                                ? Colors.redAccent
                                : (isFilled ? AppTheme.primaryTeal : (isDark ? Colors.grey.shade600 : Colors.grey.shade400));

                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              margin: const EdgeInsets.symmetric(horizontal: 5),
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: dotColor,
                                border: Border.all(
                                  color: borderColor,
                                  width: 2,
                                ),
                                boxShadow: (_isError || isFilled)
                                    ? [
                                        BoxShadow(
                                          color: (_isError ? Colors.redAccent : AppTheme.primaryTeal).withValues(alpha: 0.5),
                                          blurRadius: 6,
                                          offset: const Offset(0, 2),
                                        ),
                                      ]
                                    : [],
                              ),
                            );
                          }),
                        ),

                        const SizedBox(height: 8),

                        // Error Message Label
                        SizedBox(
                          height: 18,
                          child: Text(
                            _errorMessage,
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ),

                        const SizedBox(height: 10),

                        // Keypad (3x4 Grid)
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 300),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: ['1', '2', '3'].map((d) => _buildKeyBtn(d, isDark)).toList(),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: ['4', '5', '6'].map((d) => _buildKeyBtn(d, isDark)).toList(),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: ['7', '8', '9'].map((d) => _buildKeyBtn(d, isDark)).toList(),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  // Fingerprint Action Button
                                  if (!_isSettingUpPin && _isBiometricAvailable)
                                    _buildIconButton(
                                      icon: Icons.fingerprint_rounded,
                                      onTap: _triggerBiometric,
                                      isDark: isDark,
                                    )
                                  else
                                    const SizedBox(width: 54, height: 54),

                                  // Zero Button
                                  _buildKeyBtn('0', isDark),

                                  // Backspace Button
                                  _buildIconButton(
                                    icon: Icons.backspace_outlined,
                                    onTap: _onBackspace,
                                    isDark: isDark,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 8),

                        // Reset PIN link (only in unlock mode)
                        if (!_isSettingUpPin)
                          TextButton(
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  backgroundColor: isDark ? const Color(0xFF1F2C33) : Colors.white,
                                  title: Text(
                                    'Reset PIN?',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      color: isDark ? Colors.white : const Color(0xFF111B21),
                                    ),
                                  ),
                                  content: Text(
                                    'This will clear your current PIN and let you set a new one.',
                                    style: TextStyle(
                                      color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                                    ),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.of(ctx).pop(),
                                      child: const Text('Cancel'),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        Navigator.of(ctx).pop();
                                        _resetPin();
                                      },
                                      child: const Text(
                                        'Reset',
                                        style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w900),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                            child: Text(
                              'Forgot PIN? Reset',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: isDark ? Colors.grey.shade400 : Colors.grey.shade500,
                              ),
                            ),
                          ),

                        // Biometric toggle (only in unlock mode, when biometric available)
                        if (!_isSettingUpPin && _isBiometricAvailable)
                          FutureBuilder<bool>(
                            future: AuthService.isBiometricEnabled(),
                            builder: (ctx, snap) {
                              final enabled = snap.data ?? true;
                              return Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.fingerprint_rounded,
                                    size: 16,
                                    color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Fingerprint',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Switch(
                                    value: enabled,
                                    activeThumbColor: AppTheme.primaryTeal,
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    onChanged: (val) async {
                                      await AuthService.setBiometricEnabled(val);
                                      if (mounted) setState(() {});
                                    },
                                  ),
                                ],
                              );
                            },
                          ),

                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildKeyBtn(String digit, bool isDark) {
    return InkWell(
      onTap: () => _onKeyPress(digit),
      borderRadius: BorderRadius.circular(28),
      child: Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isDark ? const Color(0xFF1F2C33) : Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.06),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: Text(
            digit,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white : const Color(0xFF111B21),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(28),
      child: SizedBox(
        width: 54,
        height: 54,
        child: Center(
          child: Icon(
            icon,
            color: AppTheme.primaryTeal,
            size: 22,
          ),
        ),
      ),
    );
  }
}

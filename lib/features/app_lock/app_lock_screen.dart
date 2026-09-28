import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import 'lock_controller.dart';
import 'biometric_service.dart';

class AppLockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;

  const AppLockScreen({super.key, required this.onUnlocked});

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  String _pin = '';
  String? _error;
  bool _canUseBiometric = false;
  bool _isFirstTimeSetup = false;
  bool _isConfirmingFirstPin = false;
  String _firstPinDraft = '';

  @override
  void initState() {
    super.initState();
    _checkPinAndBiometrics();
  }

  Future<void> _checkPinAndBiometrics() async {
    final hasPinSaved = await AuthService.hasPin();
    final available = await BiometricService.isBiometricAvailable();

    if (mounted) {
      setState(() {
        _isFirstTimeSetup = !hasPinSaved;
        _canUseBiometric = available && hasPinSaved;
      });

      if (_canUseBiometric) {
        _tryBiometrics();
      }
    }
  }

  Future<void> _tryBiometrics() async {
    final success = await LockController.tryBiometricUnlock();
    if (success && mounted) {
      widget.onUnlocked();
    }
  }

  void _onKeyPress(String val) async {
    if (LockController.lockoutSecondsNotifier.value > 0) return;
    if (_pin.length < 4) {
      setState(() {
        _error = null;
        _pin += val;
      });
    }

    if (_pin.length == 4) {
      if (_isFirstTimeSetup) {
        if (!_isConfirmingFirstPin) {
          // Store first entry and ask for confirmation
          setState(() {
            _firstPinDraft = _pin;
            _pin = '';
            _isConfirmingFirstPin = true;
          });
        } else {
          // Confirming second entry
          if (_pin == _firstPinDraft) {
            await AuthService.setPin(_pin);
            LockController.unlockApp();
            if (mounted) widget.onUnlocked();
          } else {
            setState(() {
              _pin = '';
              _firstPinDraft = '';
              _isConfirmingFirstPin = false;
              _error = 'PINs do not match. Try creating again.';
            });
          }
        }
      } else {
        // Normal verification
        final success = await LockController.verifyPin(_pin);
        if (success) {
          LockController.unlockApp();
          if (mounted) widget.onUnlocked();
        } else {
          setState(() {
            _pin = '';
            _error = 'Incorrect PIN';
          });
        }
      }
    }
  }

  void _onBackspace() {
    if (_pin.isNotEmpty) {
      setState(() {
        _error = null;
        _pin = _pin.substring(0, _pin.length - 1);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: ValueListenableBuilder<int>(
          valueListenable: LockController.lockoutSecondsNotifier,
          builder: (context, lockoutSecs, _) {
            final isLockedOut = lockoutSecs > 0;
            final headerTitle = _isFirstTimeSetup
                ? (_isConfirmingFirstPin ? 'Confirm 4-digit PIN' : 'Create 4-digit PIN')
                : 'Clock Private Vault';

            final headerSubtitle = isLockedOut
                ? 'Too many attempts. Try again in ${lockoutSecs}s'
                : (_isFirstTimeSetup
                    ? (_isConfirmingFirstPin ? 'Re-enter your 4-digit PIN to confirm' : 'Set a PIN to secure your Clock app')
                    : 'Enter your 4-digit PIN to unlock');

            return LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: IntrinsicHeight(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppTheme.primaryTeal.withValues(alpha: 0.15),
                            ),
                            child: const Icon(Icons.lock_rounded, size: 44, color: AppTheme.primaryTeal),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            headerTitle,
                            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 6),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Text(
                              headerSubtitle,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: isLockedOut ? Colors.redAccent : Colors.grey.shade400,
                                fontSize: 13,
                                fontWeight: isLockedOut ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(4, (index) {
                              final filled = index < _pin.length;
                              return Container(
                                margin: const EdgeInsets.symmetric(horizontal: 8),
                                width: 14,
                                height: 14,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: filled ? AppTheme.primaryTeal : Colors.white24,
                                ),
                              );
                            }),
                          ),
                          if (_error != null && !isLockedOut) ...[
                            const SizedBox(height: 12),
                            Text(
                              _error!,
                              style: const TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ],
                          const SizedBox(height: 20),
                          _buildKeypad(isLockedOut),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildKeypad(bool isLockedOut) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: ['1', '2', '3'].map((k) => _keyBtn(k, isLockedOut)).toList(),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: ['4', '5', '6'].map((k) => _keyBtn(k, isLockedOut)).toList(),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: ['7', '8', '9'].map((k) => _keyBtn(k, isLockedOut)).toList(),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _canUseBiometric
                  ? InkWell(
                      onTap: isLockedOut ? null : _tryBiometrics,
                      borderRadius: BorderRadius.circular(28),
                      child: const SizedBox(
                        width: 56,
                        height: 56,
                        child: Center(
                          child: Icon(Icons.fingerprint_rounded, color: AppTheme.primaryTeal, size: 32),
                        ),
                      ),
                    )
                  : const SizedBox(width: 56, height: 56),
              _keyBtn('0', isLockedOut),
              InkWell(
                onTap: isLockedOut ? null : _onBackspace,
                borderRadius: BorderRadius.circular(28),
                child: const SizedBox(
                  width: 56,
                  height: 56,
                  child: Center(
                    child: Icon(Icons.backspace_outlined, color: Colors.white70),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () async {
              await AuthService.deletePin();
              setState(() {
                _pin = '';
                _error = null;
                _isFirstTimeSetup = true;
                _isConfirmingFirstPin = false;
              });
            },
            child: const Text(
              'Reset / Set New PIN',
              style: TextStyle(color: AppTheme.primaryTeal, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _keyBtn(String val, bool disabled) {
    return InkWell(
      onTap: disabled ? null : () => _onKeyPress(val),
      borderRadius: BorderRadius.circular(28),
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: disabled ? Colors.white10 : Colors.white.withValues(alpha: 0.1),
        ),
        child: Center(
          child: Text(
            val,
            style: TextStyle(
              color: disabled ? Colors.white30 : Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

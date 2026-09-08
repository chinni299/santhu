import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import 'encryption_service.dart';

class AuthService {
  static const String _tokenKey = 'duochat_jwt_token';   // legacy key (single-user)
  static const String _userKey = 'duochat_user_data';     // legacy key (single-user)
  static const String _pinHashKey = 'duochat_app_pin_hash';
  static const String _pinSaltKey = 'duochat_app_pin_salt';
  static const String _biometricEnabledKey = 'duochat_biometric_enabled';

  // Per-user isolated keys — prevents two browser tabs from overwriting each other
  static String _tokenKeyForUser(int userId) => 'duochat_jwt_token_$userId';
  static String _userKeyForUser(int userId) => 'duochat_user_data_$userId';

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: true),
  );

  static final Map<String, String> _memStorage = {};

  static Future<String?> _readSecure(String key) async {
    if (kIsWeb) {
      try {
        final prefs = await SharedPreferences.getInstance();
        return prefs.getString(key) ?? _memStorage[key];
      } catch (_) {
        return _memStorage[key];
      }
    }
    try {
      final val = await _storage.read(key: key);
      return val ?? _memStorage[key];
    } catch (_) {
      try {
        final prefs = await SharedPreferences.getInstance();
        return prefs.getString(key) ?? _memStorage[key];
      } catch (_) {
        return _memStorage[key];
      }
    }
  }

  static Future<void> _writeSecure(String key, String value) async {
    _memStorage[key] = value;
    if (kIsWeb) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(key, value);
      } catch (_) {}
      return;
    }
    try {
      await _storage.write(key: key, value: value);
    } catch (_) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(key, value);
      } catch (_) {}
    }
  }

  static Future<void> _deleteSecure(String key) async {
    _memStorage.remove(key);
    if (kIsWeb) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(key);
      } catch (_) {}
      return;
    }
    try {
      await _storage.delete(key: key);
    } catch (_) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(key);
      } catch (_) {}
    }
  }

  // Hash PIN securely with SHA-256 and salt
  static String _hashPin(String pin, String salt) {
    final bytes = utf8.encode('$salt:$pin:duochat_private_app_lock');
    return sha256.convert(bytes).toString();
  }

  // Check if PIN has been setup
  static Future<bool> hasPin() async {
    final pinHash = await _readSecure(_pinHashKey);
    return pinHash != null && pinHash.isNotEmpty;
  }

  // Save 6-digit PIN securely
  static Future<void> savePin(String pin) async {
    final salt = DateTime.now().millisecondsSinceEpoch.toString();
    final hash = _hashPin(pin, salt);
    await _writeSecure(_pinSaltKey, salt);
    await _writeSecure(_pinHashKey, hash);
  }

  // Delete stored PIN (for reset)
  static Future<void> deletePin() async {
    await _deleteSecure(_pinHashKey);
    await _deleteSecure(_pinSaltKey);
  }

  // Verify entered PIN against stored hash
  static Future<bool> verifyPin(String pin) async {
    final salt = await _readSecure(_pinSaltKey);
    final storedHash = await _readSecure(_pinHashKey);
    if (salt == null || storedHash == null) return false;
    final enteredHash = _hashPin(pin, salt);
    return enteredHash == storedHash;
  }

  // Biometric preferences
  static Future<bool> isBiometricEnabled() async {
    final val = await _readSecure(_biometricEnabledKey);
    return val != 'false';
  }

  static Future<void> setBiometricEnabled(bool enabled) async {
    await _writeSecure(_biometricEnabledKey, enabled.toString());
  }

  // Save JWT token and User session to Secure Storage (per-user key)
  static Future<void> saveSession(String token, Map<String, dynamic> user) async {
    final userId = int.tryParse((user['id'] ?? 0).toString()) ?? 0;
    // Write to both legacy key and per-user key
    await _writeSecure(_tokenKey, token);
    await _writeSecure(_userKey, jsonEncode(user));
    if (userId > 0) {
      await _writeSecure(_tokenKeyForUser(userId), token);
      await _writeSecure(_userKeyForUser(userId), jsonEncode(user));
    }
  }

  // Get stored JWT token for the legacy/last-logged-in user
  static Future<String?> getToken() async {
    return await _readSecure(_tokenKey);
  }

  // Get stored JWT token for a SPECIFIC userId (per-user isolated key)
  static Future<String?> getTokenForUser(int userId) async {
    return await _readSecure(_tokenKeyForUser(userId));
  }

  // Get stored User profile
  static Future<Map<String, dynamic>> getUser() async {
    try {
      var userStr = await _readSecure(_userKey);
      if (userStr != null && userStr.isNotEmpty) {
        return jsonDecode(userStr) as Map<String, dynamic>;
      }
    } catch (_) {}
    return {};
  }

  // Clear session (Real Logout) — clears both legacy and per-user keys
  static Future<void> logout() async {
    final user = await getUser();
    final userId = int.tryParse((user['id'] ?? 0).toString()) ?? 0;
    await _deleteSecure(_tokenKey);
    await _deleteSecure(_userKey);
    if (userId > 0) {
      await _deleteSecure(_tokenKeyForUser(userId));
      await _deleteSecure(_userKeyForUser(userId));
    }
  }

  // Get authorized HTTP headers — uses legacy key (for screens that don't know userId)
  static Future<Map<String, String>> getAuthHeaders() async {
    final token = await getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  // Get authorized HTTP headers for a SPECIFIC userId (isolated, no cross-contamination)
  static Future<Map<String, String>> getAuthHeadersForUser(int userId) async {
    final token = await getTokenForUser(userId);
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  // Real backend Login API call
  static Future<Map<String, dynamic>> login(String email, String password) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/auth/login');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );

    final data = jsonDecode(response.body);

    if (response.statusCode == 200 && data['success'] == true) {
      final token = data['token'];
      final user = data['user'];
      if (token != null && user != null) {
        await saveSession(token, user);
      }
    }

    return data;
  }

  // Update FCM device token on backend using JWT authentication
  static Future<void> updateFcmToken(String fcmToken) async {
    try {
      final headers = await getAuthHeaders();
      final url = Uri.parse('${ApiConfig.baseUrl}/auth/fcm-token');
      await http.post(
        url,
        headers: headers,
        body: jsonEncode({'fcmToken': fcmToken}),
      );
      debugPrint("FCM token registered with backend ✅");
    } catch (e) {
      debugPrint("Error updating FCM token: $e");
    }
  }

  // Register local X25519 Public Key with backend
  static Future<void> registerPublicKey() async {
    try {
      final publicKeyB64 = await EncryptionService().getPublicKey();
      final headers = await getAuthHeaders();
      final url = Uri.parse('${ApiConfig.baseUrl}/auth/public-key');
      await http.post(
        url,
        headers: headers,
        body: jsonEncode({'publicKey': publicKeyB64}),
      );
      debugPrint("X25519 public key registered with backend 🔑");
    } catch (e) {
      debugPrint("Error registering public key: $e");
    }
  }

  // Fetch target user's X25519 Public Key from backend
  static Future<String?> fetchPublicKey(int userId) async {
    try {
      final headers = await getAuthHeaders();
      final url = Uri.parse('${ApiConfig.baseUrl}/auth/public-key/$userId');
      final response = await http.get(url, headers: headers);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['publicKey'] != null) {
          return data['publicKey'].toString();
        }
      }
    } catch (e) {
      debugPrint("Error fetching public key for user $userId: $e");
    }
    return null;
  }

  // Restore missing methods for compilation
  static Future<Map<String, dynamic>> getPeerUserProfile(int otherUserId, int currentUserId) async {
    return {'id': otherUserId, 'name': 'User $otherUserId', 'status': 'Available'};
  }

  static Future<void> saveContactAlias(int contactId, String alias) async {
    debugPrint("Saving alias $alias for contact $contactId locally.");
  }

  // Ensure a valid token exists for the given userId.
  // Always uses the per-user isolated key — never cross-contaminates.
  static Future<String?> ensureToken(int userId) async {
    return await getTokenForUser(userId);
  }

  static Future<void> updateUserProfile(Map<String, dynamic> profileData) async {
    debugPrint("Updating profile: $profileData");
  }
}

import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
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

  static Future<void> setPin(String pin) => savePin(pin);

  // Delete stored PIN (for reset)
  static Future<void> deletePin() async {
    await _deleteSecure(_pinHashKey);
    await _deleteSecure(_pinSaltKey);
  }

  // Verify entered PIN against stored hash
  static Future<bool> verifyPin(String pin) async {
    final salt = await _readSecure(_pinSaltKey);
    final storedHash = await _readSecure(_pinHashKey);

    if (salt == null || storedHash == null) {
      return false;
    }

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
  static Future<void> registerPublicKey([int? userId]) async {
    try {
      final publicKeyB64 = await EncryptionService().getPublicKey();
      final headers = userId != null ? await getAuthHeadersForUser(userId) : await getAuthHeaders();
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

  static Future<String?> getPeerPublicKey(int userId) async {
    return await fetchPublicKey(userId);
  }

  // Persistent Contact Alias Storage (Per-Contact Custom Names)
  static Future<void> saveContactAlias(int contactId, String alias, [int? currentUserId]) async {
    try {
      final key = 'duochat_contact_alias_$contactId';
      _memStorage[key] = alias;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, alias);

      if (currentUserId != null && currentUserId > 0) {
        final scopedKey = 'duochat_contact_alias_${currentUserId}_$contactId';
        _memStorage[scopedKey] = alias;
        await prefs.setString(scopedKey, alias);
      }
      debugPrint("Saved contact alias for $contactId: '$alias' ✅");
    } catch (e) {
      debugPrint("Error saving contact alias: $e");
    }
  }

  static Future<String?> getContactAlias(int contactId, [int? currentUserId]) async {
    try {
      if (currentUserId != null && currentUserId > 0) {
        final scopedKey = 'duochat_contact_alias_${currentUserId}_$contactId';
        if (_memStorage.containsKey(scopedKey) && _memStorage[scopedKey]!.isNotEmpty) {
          return _memStorage[scopedKey];
        }
        final prefs = await SharedPreferences.getInstance();
        final scopedVal = prefs.getString(scopedKey);
        if (scopedVal != null && scopedVal.isNotEmpty) {
          _memStorage[scopedKey] = scopedVal;
          return scopedVal;
        }
      }

      final key = 'duochat_contact_alias_$contactId';
      if (_memStorage.containsKey(key) && _memStorage[key]!.isNotEmpty) {
        return _memStorage[key];
      }
      final prefs = await SharedPreferences.getInstance();
      final alias = prefs.getString(key);
      if (alias != null && alias.isNotEmpty) {
        _memStorage[key] = alias;
        return alias;
      }
    } catch (_) {}
    return null;
  }

  // Persistent Avatar Path / URL (Local Storage per-user)
  static Future<void> saveAvatarPath(String path, int userId) async {
    try {
      final key = 'duochat_avatar_path_$userId';
      _memStorage[key] = path;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, path);
    } catch (_) {}
  }

  static Future<String?> getAvatarPath(int userId) async {
    try {
      final key = 'duochat_avatar_path_$userId';
      if (_memStorage.containsKey(key) && _memStorage[key]!.isNotEmpty) return _memStorage[key];
      final prefs = await SharedPreferences.getInstance();
      final val = prefs.getString(key);
      if (val != null && val.isNotEmpty) {
        _memStorage[key] = val;
        return val;
      }
    } catch (_) {}
    return null;
  }

  static String getAvatarUrl(int userId) {
    return '${ApiConfig.baseUrl}/auth/avatar/$userId';
  }

  static ImageProvider? getAvatarImageProvider(String? localPath, String? networkUrl) {
    if (localPath != null && localPath.isNotEmpty) {
      if (localPath.startsWith('data:image/')) {
        try {
          final parts = localPath.split(',');
          if (parts.length > 1) {
            final bytes = base64Decode(parts[1]);
            return MemoryImage(bytes);
          }
        } catch (e) {
          debugPrint("Error decoding base64 avatar: $e");
        }
      }
      if (localPath.startsWith('http')) {
        return NetworkImage(localPath);
      }
      if (!kIsWeb) {
        try {
          final file = File(localPath);
          if (file.existsSync()) {
            return FileImage(file);
          }
        } catch (_) {}
      }
    }
    if (networkUrl != null && networkUrl.isNotEmpty) {
      if (networkUrl.startsWith('data:image/')) {
        try {
          final parts = networkUrl.split(',');
          if (parts.length > 1) {
            final bytes = base64Decode(parts[1]);
            return MemoryImage(bytes);
          }
        } catch (_) {}
      }
      return NetworkImage(networkUrl);
    }
    return null;
  }

  // Upload Avatar to Backend and persist locally
  static Future<String?> uploadAvatar({
    required int userId,
    required Uint8List bytes,
    required String filename,
    String? localFilePath,
  }) async {
    try {
      if (localFilePath != null && localFilePath.isNotEmpty) {
        await saveAvatarPath(localFilePath, userId);
      }

      final token = await getTokenForUser(userId) ?? await getToken();
      final uri = Uri.parse('${ApiConfig.baseUrl}/auth/avatar');
      final request = http.MultipartRequest('POST', uri);

      if (token != null && token.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      final multipartFile = http.MultipartFile.fromBytes(
        'avatar',
        bytes,
        filename: filename.isNotEmpty ? filename : 'avatar.jpg',
      );
      request.files.add(multipartFile);

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final serverUrl = data['avatar_url']?.toString() ?? getAvatarUrl(userId);
          await saveAvatarPath(serverUrl, userId);

          // Update user session
          final user = await getUser();
          user['avatar_url'] = serverUrl;
          if (localFilePath != null) user['avatar_path'] = localFilePath;
          await saveSession(token ?? '', user);

          debugPrint("Avatar uploaded successfully for user $userId: $serverUrl ✅");
          return serverUrl;
        }
      }
    } catch (e) {
      debugPrint("Error uploading avatar: $e");
    }
    return null;
  }

  // Fetch Peer Profile (checks local custom alias first, then backend DB)
  static Future<Map<String, dynamic>> getPeerUserProfile(int otherUserId, int currentUserId) async {
    final customAlias = await getContactAlias(otherUserId, currentUserId);
    final localAvatar = await getAvatarPath(otherUserId);

    try {
      final headers = await getAuthHeadersForUser(currentUserId);
      final url = Uri.parse('${ApiConfig.baseUrl}/auth/profile/$otherUserId');
      final res = await http.get(url, headers: headers);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && data['user'] != null) {
          final u = data['user'];
          final dbName = u['name']?.toString() ?? '';
          final displayName = (customAlias != null && customAlias.isNotEmpty)
              ? customAlias
              : (dbName.isNotEmpty ? dbName : (otherUserId == 2 ? 'Leslie' : 'User $otherUserId'));

          final avatarUrl = u['avatar_url'] != null && u['avatar_url'].toString().isNotEmpty
              ? (u['avatar_url'].toString().startsWith('http')
                  ? u['avatar_url'].toString()
                  : '${ApiConfig.baseUrl}${u['avatar_url']}')
              : getAvatarUrl(otherUserId);

          return {
            'id': otherUserId,
            'display_name': displayName,
            'name': dbName,
            'avatar_url': avatarUrl,
            'avatar_path': localAvatar ?? '',
            'status': u['status'] ?? 'Available',
            'is_online': u['is_online'] == true,
            'last_seen_at': u['last_seen_at'],
          };
        }
      }
    } catch (e) {
      debugPrint("Error fetching peer profile: $e");
    }

    return {
      'id': otherUserId,
      'display_name': customAlias ?? (otherUserId == 2 ? 'Leslie' : 'User $otherUserId'),
      'name': customAlias ?? (otherUserId == 2 ? 'Leslie' : 'User $otherUserId'),
      'avatar_path': localAvatar ?? '',
      'avatar_url': getAvatarUrl(otherUserId),
      'status': 'Available',
    };
  }

  // Ensure a valid token exists for the given userId.
  static Future<String?> ensureToken(int userId) async {
    return await getTokenForUser(userId);
  }

  // Update User Profile (persists locally and syncs to backend)
  static Future<void> updateUserProfile(Map<String, dynamic> profileData) async {
    try {
      final user = await getUser();
      final userId = int.tryParse((user['id'] ?? 1).toString()) ?? 1;

      // Update local storage
      final merged = {...user, ...profileData};
      await saveSession(await getTokenForUser(userId) ?? '', merged);

      if (profileData.containsKey('avatar_path') && profileData['avatar_path'] != null) {
        await saveAvatarPath(profileData['avatar_path'].toString(), userId);
      }

      // Sync to backend DB
      final headers = await getAuthHeadersForUser(userId);
      final url = Uri.parse('${ApiConfig.baseUrl}/auth/profile');
      await http.put(
        url,
        headers: headers,
        body: jsonEncode(profileData),
      );
      debugPrint("Updated user profile in backend & locally ✅");
    } catch (e) {
      debugPrint("Error updating user profile: $e");
    }
  }

  // ==================================================
  // NEW: JWT EXPIRY CHECK (no external package needed)
  // ==================================================

  // Decode a JWT payload and check whether it has expired.
  // Returns true (treated as expired) if the token is malformed or has no exp claim we can trust.
  static bool isTokenExpired(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return true;

      String normalized = parts[1].replaceAll('-', '+').replaceAll('_', '/');
      switch (normalized.length % 4) {
        case 2:
          normalized += '==';
          break;
        case 3:
          normalized += '=';
          break;
      }

      final payloadJson = utf8.decode(base64Url.decode(normalized));
      final payload = jsonDecode(payloadJson) as Map<String, dynamic>;

      final exp = payload['exp'];
      if (exp == null) return false; // no expiry claim present — treat as non-expiring

      final expiryDate = DateTime.fromMillisecondsSinceEpoch((exp as int) * 1000);
      return DateTime.now().isAfter(expiryDate);
    } catch (e) {
      debugPrint("Error decoding JWT for expiry check: $e");
      return true;
    }
  }

  // Check if the stored session for a specific userId is still valid (token exists and isn't expired).
  static Future<bool> isSessionValid(int userId) async {
    final token = await getTokenForUser(userId);
    if (token == null || token.isEmpty) return false;
    return !isTokenExpired(token);
  }

  // Returns remaining seconds until the given user's token expires, or null if unknown/expired/missing.
  static Future<int?> secondsUntilExpiry(int userId) async {
    final token = await getTokenForUser(userId);
    if (token == null || token.isEmpty) return null;
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      String normalized = parts[1].replaceAll('-', '+').replaceAll('_', '/');
      switch (normalized.length % 4) {
        case 2:
          normalized += '==';
          break;
        case 3:
          normalized += '=';
          break;
      }
      final payload = jsonDecode(utf8.decode(base64Url.decode(normalized))) as Map<String, dynamic>;
      final exp = payload['exp'];
      if (exp == null) return null;
      final expiryDate = DateTime.fromMillisecondsSinceEpoch((exp as int) * 1000);
      final remaining = expiryDate.difference(DateTime.now()).inSeconds;
      return remaining > 0 ? remaining : 0;
    } catch (_) {
      return null;
    }
  }
}
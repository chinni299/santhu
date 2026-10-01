import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'auth_service.dart';

class EncryptionService {
  static final EncryptionService _instance = EncryptionService._internal();
  factory EncryptionService() => _instance;
  EncryptionService._internal();

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: true),
  );
  final _x25519 = X25519();
  final _aesGcm = AesGcm.with256bits();
  final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  final Map<int, KeyPair> _userKeyPairMap = {};
  final Map<int, String> _userPubKeyMap = {};
  final Map<String, SecretKey> _sharedKeyCache = {};
  final Map<String, SecretKey> _vaultKeyCache = {};

  String _privKey(int userId) => 'e2ee_private_key_$userId';
  String _pubKey(int userId) => 'e2ee_public_key_$userId';

  /// Derive 256-bit vault key using PBKDF2-HMAC-SHA256 with 600,000 iterations (cached per salt)
  Future<SecretKey> _deriveVaultKey(String password, List<int> saltBytes) async {
    final cacheKey = '$password:${base64Encode(saltBytes)}';
    if (_vaultKeyCache.containsKey(cacheKey)) {
      return _vaultKeyCache[cacheKey]!;
    }

    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 600000,
      bits: 256,
    );
    final secretKey = SecretKey(utf8.encode(password));
    final derivedSecret = await pbkdf2.deriveKey(
      secretKey: secretKey,
      nonce: saltBytes,
    );
    _vaultKeyCache[cacheKey] = derivedSecret;
    return derivedSecret;
  }

  /// Encrypt private key bytes into an encrypted vault payload using user password
  Future<Map<String, String>> encryptPrivateKeyToVault(
    List<int> privateKeyBytes,
    String password,
    String publicKeyB64,
  ) async {
    final salt = List<int>.generate(16, (i) => (DateTime.now().microsecondsSinceEpoch + i * 37) % 256);
    final vaultKey = await _deriveVaultKey(password, salt);

    final secretBox = await _aesGcm.encrypt(
      privateKeyBytes,
      secretKey: vaultKey,
    );

    final combinedCipher = Uint8List.fromList([...secretBox.cipherText, ...secretBox.mac.bytes]);
    return {
      'encryptedPrivateKey': base64Encode(combinedCipher),
      'salt': base64Encode(salt),
      'nonce': base64Encode(secretBox.nonce),
      'publicKey': publicKeyB64,
    };
  }

  /// Decrypt private key bytes from an encrypted vault payload using user password
  Future<List<int>?> decryptPrivateKeyFromVault(
    Map<String, dynamic> vault,
    String password,
  ) async {
    try {
      final encB64 = vault['encryptedPrivateKey']?.toString();
      final saltB64 = vault['salt']?.toString();
      final nonceB64 = vault['nonce']?.toString();
      if (encB64 == null || saltB64 == null || nonceB64 == null) return null;

      final combinedBytes = base64Decode(encB64);
      final saltBytes = base64Decode(saltB64);
      final nonceBytes = base64Decode(nonceB64);

      if (combinedBytes.length < 16) return null;

      final cipherTextBytes = combinedBytes.sublist(0, combinedBytes.length - 16);
      final macBytes = combinedBytes.sublist(combinedBytes.length - 16);

      final vaultKey = await _deriveVaultKey(password, saltBytes);
      final secretBox = SecretBox(
        cipherTextBytes,
        nonce: nonceBytes,
        mac: Mac(macBytes),
      );

      final privateBytes = await _aesGcm.decrypt(
        secretBox,
        secretKey: vaultKey,
      );

      return privateBytes;
    } catch (e) {
      debugPrint('[E2EE VAULT] Failed to decrypt key vault with provided password: $e');
      return null;
    }
  }

  /// Synchronize X25519 keypair with Server Encrypted Vault
  Future<String> syncKeyVault(int userId, String password) async {
    // 0. Instant Fast-Path: If memory or local storage already has the keypair, return in 0 ms!
    if (_userPubKeyMap.containsKey(userId) && _userKeyPairMap.containsKey(userId)) {
      return _userPubKeyMap[userId]!;
    }

    final privKeyName = _privKey(userId);
    final pubKeyName = _pubKey(userId);

    final storedPrivateB64 = await _storage.read(key: privKeyName);
    final storedPublicB64 = await _storage.read(key: pubKeyName);

    if (storedPrivateB64 != null && storedPublicB64 != null) {
      try {
        final privateBytes = base64Decode(storedPrivateB64);
        final publicBytes = base64Decode(storedPublicB64);

        final keyPair = SimpleKeyPairData(
          privateBytes,
          publicKey: SimplePublicKey(publicBytes, type: KeyPairType.x25519),
          type: KeyPairType.x25519,
        );
        _userKeyPairMap[userId] = keyPair;
        _userPubKeyMap[userId] = storedPublicB64;
        return storedPublicB64;
      } catch (_) {}
    }

    // 1. Check if server already has an encrypted key vault
    try {
      final serverVaultData = await AuthService.fetchKeyVault(userId);
      if (serverVaultData != null && serverVaultData['keyVault'] != null) {
        final vaultMap = Map<String, dynamic>.from(serverVaultData['keyVault']);
        final decryptedPrivBytes = await decryptPrivateKeyFromVault(vaultMap, password);

        if (decryptedPrivBytes != null) {
          final pubB64 = serverVaultData['publicKey']?.toString() ?? '';
          final privB64 = base64Encode(decryptedPrivBytes);

          final keyPair = SimpleKeyPairData(
            decryptedPrivBytes,
            publicKey: SimplePublicKey(base64Decode(pubB64), type: KeyPairType.x25519),
            type: KeyPairType.x25519,
          );

          await _storage.write(key: _privKey(userId), value: privB64);
          await _storage.write(key: _pubKey(userId), value: pubB64);

          _userKeyPairMap[userId] = keyPair;
          _userPubKeyMap[userId] = pubB64;
          debugPrint('[E2EE VAULT] User $userId restored keypair from Server Vault! Fingerprint: ${_fingerprint(pubB64)} 🔐');
          return pubB64;
        }
      }
    } catch (e) {
      debugPrint('[E2EE VAULT] Check server vault failed ($e). Continuing with local fallback.');
    }

    // 2. Check if local secure storage already has a keypair
    final localPublicB64 = await initKeyPair(userId);
    final keyPair = _userKeyPairMap[userId]!;
    final keyPairData = await keyPair.extract() as SimpleKeyPairData;
    final privBytes = keyPairData.bytes;

    // 3. Upload encrypted vault to server if server vault was empty
    try {
      final vaultBlob = await encryptPrivateKeyToVault(privBytes, password, localPublicB64);
      await AuthService.saveKeyVault(userId, vaultBlob, localPublicB64);
      debugPrint('[E2EE VAULT] User $userId registered new encrypted key vault on Server. Fingerprint: ${_fingerprint(localPublicB64)} 🔐');
    } catch (e) {
      debugPrint('[E2EE VAULT] Error uploading vault to server: $e');
    }

    return localPublicB64;
  }

  /// Initialize local device X25519 keypair per-user
  Future<String> initKeyPair([int userId = 1]) async {
    if (_userPubKeyMap.containsKey(userId) && _userKeyPairMap.containsKey(userId)) {
      final fp = _fingerprint(_userPubKeyMap[userId]!);
      debugPrint('[E2EE KEY] User $userId loaded key from memory. Fingerprint: $fp');
      return _userPubKeyMap[userId]!;
    }

    final privKeyName = _privKey(userId);
    final pubKeyName = _pubKey(userId);

    var storedPrivateB64 = await _storage.read(key: privKeyName);
    var storedPublicB64 = await _storage.read(key: pubKeyName);

    if (storedPrivateB64 != null && storedPublicB64 != null) {
      try {
        final privateBytes = base64Decode(storedPrivateB64);
        final publicBytes = base64Decode(storedPublicB64);

        final keyPair = SimpleKeyPairData(
          privateBytes,
          publicKey: SimplePublicKey(publicBytes, type: KeyPairType.x25519),
          type: KeyPairType.x25519,
        );
        _userKeyPairMap[userId] = keyPair;
        _userPubKeyMap[userId] = storedPublicB64;
        final fp = _fingerprint(storedPublicB64);
        debugPrint('[E2EE KEY] User $userId loaded existing key from SecureStorage. Fingerprint: $fp');
        return storedPublicB64;
      } catch (e) {
        debugPrint('[E2EE KEY ERROR] Corrupted local key: $e');
      }
    }

    // Generate new secure keypair for this specific user
    final keyPair = await _x25519.newKeyPair();
    final pk = await keyPair.extractPublicKey();
    final keyPairData = await keyPair.extract();
    final privateBytes = keyPairData.bytes;

    final pubB64 = base64Encode(pk.bytes);
    final privB64 = base64Encode(privateBytes);

    await _storage.write(key: privKeyName, value: privB64);
    await _storage.write(key: pubKeyName, value: pubB64);

    _userKeyPairMap[userId] = keyPair;
    _userPubKeyMap[userId] = pubB64;
    final fp = _fingerprint(pubB64);
    debugPrint('[E2EE KEY] User $userId generated NEW keypair. Fingerprint: $fp');
    return pubB64;
  }

  /// Helper to get a short readable fingerprint of a public key (e.g. "a1b2c3d4...")
  static String _fingerprint(String pubKeyB64) {
    if (pubKeyB64.isEmpty) return 'none';
    final len = pubKeyB64.length;
    return '${pubKeyB64.substring(0, len > 10 ? 10 : len)}...';
  }

  /// Get current public key for specific user
  Future<String> getPublicKey([int userId = 1]) async {
    if (_userPubKeyMap.containsKey(userId)) return _userPubKeyMap[userId]!;
    return await initKeyPair(userId);
  }

  /// Derive shared symmetric key using X25519 + HKDF-SHA256 for specific user
  Future<SecretKey> getSharedKey(String peerPublicKeyB64, [int userId = 1]) async {
    final cacheKey = '$userId:$peerPublicKeyB64';
    if (_sharedKeyCache.containsKey(cacheKey)) {
      return _sharedKeyCache[cacheKey]!;
    }

    if (!_userKeyPairMap.containsKey(userId)) {
      await initKeyPair(userId);
    }

    final peerPublicBytes = base64Decode(peerPublicKeyB64);
    final peerPublicKey = SimplePublicKey(peerPublicBytes, type: KeyPairType.x25519);

    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: _userKeyPairMap[userId]!,
      remotePublicKey: peerPublicKey,
    );

    final derivedKey = await _hkdf.deriveKey(
      secretKey: sharedSecret,
      nonce: utf8.encode('DuoChatE2EESalt'),
    );

    _sharedKeyCache[cacheKey] = derivedKey;
    debugPrint('[E2EE SHARED KEY] Derived shared key with peer (fingerprint: ${_fingerprint(peerPublicKeyB64)})');
    return derivedKey;
  }

  /// Invalidate cache when peer public key changes
  void clearSharedKeyCache() {
    _sharedKeyCache.clear();
  }

  /// Encrypt text message returning map with ciphertext and nonce
  Future<Map<String, String>> encryptText(String text, SecretKey sharedKey) async {
    final bytes = utf8.encode(text);
    final secretBox = await _aesGcm.encrypt(
      bytes,
      secretKey: sharedKey,
    );

    final combinedCipher = Uint8List.fromList([...secretBox.cipherText, ...secretBox.mac.bytes]);
    return {
      'ciphertext': base64Encode(combinedCipher),
      'nonce': base64Encode(secretBox.nonce),
    };
  }

  /// Decrypt ciphertext string using nonce and shared key
  Future<String> decryptText(String ciphertextB64, String nonceB64, SecretKey sharedKey) async {
    try {
      final combinedBytes = base64Decode(ciphertextB64);
      final nonceBytes = base64Decode(nonceB64);

      if (combinedBytes.length < 16) {
        throw Exception('Ciphertext length (${combinedBytes.length}) is shorter than 16-byte MAC');
      }

      final cipherTextBytes = combinedBytes.sublist(0, combinedBytes.length - 16);
      final macBytes = combinedBytes.sublist(combinedBytes.length - 16);

      final secretBox = SecretBox(
        cipherTextBytes,
        nonce: nonceBytes,
        mac: Mac(macBytes),
      );

      final clearBytes = await _aesGcm.decrypt(
        secretBox,
        secretKey: sharedKey,
      );

      return utf8.decode(clearBytes);
    } catch (e) {
      debugPrint('[E2EE DECRYPT EXCEPTION] $e (ciphertext: ${ciphertextB64.substring(0, ciphertextB64.length.clamp(0, 15))}...)');
      return '[Message unavailable]';
    }
  }

  /// Encrypt arbitrary binary payload (e.g. voice, image, media)
  Future<Map<String, dynamic>> encryptBytes(Uint8List clearBytes, SecretKey sharedKey) async {
    final secretBox = await _aesGcm.encrypt(
      clearBytes,
      secretKey: sharedKey,
    );

    final combinedCipher = Uint8List.fromList([...secretBox.cipherText, ...secretBox.mac.bytes]);
    return {
      'bytes': combinedCipher,
      'nonce': base64Encode(secretBox.nonce),
    };
  }

  /// Decrypt binary payload
  Future<Uint8List> decryptBytes(Uint8List cipherBytes, String nonceB64, SecretKey sharedKey) async {
    try {
      final nonceBytes = base64Decode(nonceB64);

      if (cipherBytes.length < 16) {
        throw Exception('Ciphertext too short for media');
      }

      final cipherTextBytes = cipherBytes.sublist(0, cipherBytes.length - 16);
      final macBytes = cipherBytes.sublist(cipherBytes.length - 16);

      final secretBox = SecretBox(
        cipherTextBytes,
        nonce: nonceBytes,
        mac: Mac(macBytes),
      );

      final clearBytes = await _aesGcm.decrypt(
        secretBox,
        secretKey: sharedKey,
      );

      return Uint8List.fromList(clearBytes);
    } catch (e) {
      debugPrint('[E2EE DECRYPT BYTES EXCEPTION] $e');
      rethrow;
    }
  }
}

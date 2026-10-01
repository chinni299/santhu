import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' show sha256;
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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

  String _privKey(int userId) => 'e2ee_private_key_$userId';
  String _pubKey(int userId) => 'e2ee_public_key_$userId';

  /// Initialize local device X25519 keypair per-user
  Future<String> initKeyPair([int userId = 1]) async {
    if (_userPubKeyMap.containsKey(userId) && _userKeyPairMap.containsKey(userId)) {
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
        return storedPublicB64;
      } catch (e) {
        // Corrupted key -> regenerate
      }
    }

    // Generate new secure keypair for this specific user
    final keyPair = await _x25519.newKeyPair();
    final pk = await keyPair.extractPublicKey();
    final privateBytes = await keyPair.extractPrivateKeyBytes();

    final pubB64 = base64Encode(pk.bytes);
    final privB64 = base64Encode(privateBytes);

    await _storage.write(key: privKeyName, value: privB64);
    await _storage.write(key: pubKeyName, value: pubB64);

    _userKeyPairMap[userId] = keyPair;
    _userPubKeyMap[userId] = pubB64;
    return pubB64;
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
    return derivedKey;
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
        throw Exception('Ciphertext too short');
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
      return '[Decryption Error: Invalid Key or Corrupted Ciphertext]';
    }
  }

  /// Encrypt raw bytes (images / attachments)
  Future<Map<String, dynamic>> encryptBytes(Uint8List rawBytes, SecretKey sharedKey) async {
    final secretBox = await _aesGcm.encrypt(
      rawBytes,
      secretKey: sharedKey,
    );

    final combinedCipher = Uint8List.fromList([...secretBox.cipherText, ...secretBox.mac.bytes]);
    return {
      'bytes': combinedCipher,
      'nonce': base64Encode(secretBox.nonce),
    };
  }

  /// Decrypt raw bytes (images / attachments)
  Future<Uint8List> decryptBytes(Uint8List encryptedCombinedBytes, String nonceB64, SecretKey sharedKey) async {
    final nonceBytes = base64Decode(nonceB64);

    if (encryptedCombinedBytes.length < 16) {
      throw Exception('Encrypted bytes too short');
    }

    final cipherTextBytes = encryptedCombinedBytes.sublist(0, encryptedCombinedBytes.length - 16);
    final macBytes = encryptedCombinedBytes.sublist(encryptedCombinedBytes.length - 16);

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
  }

  /// Compute 30-digit Safety Number for E2EE fingerprint verification
  static String computeSafetyNumber(String ownPubKeyB64, String peerPubKeyB64) {
    final keys = [ownPubKeyB64, peerPubKeyB64]..sort();
    final combined = keys.join(":");
    final bytes = utf8.encode(combined);
    final digest = sha256.convert(bytes);
    final hexStr = digest.toString();

    final bigNum = BigInt.parse('0x${hexStr.substring(0, 32)}');
    final numStr = bigNum.toString().padRight(30, '0').substring(0, 30);
    final chunks = <String>[];
    for (var i = 0; i < 30; i += 5) {
      chunks.add(numStr.substring(i, i + 5));
    }
    return chunks.join(' ');
  }
}

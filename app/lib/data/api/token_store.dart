import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists auth tokens and the server URL. Abstract so tests can use memory.
abstract class TokenStore {
  Future<String?> read(String key);
  Future<void> write(String key, String? value);

  static const accessToken = 'access_token';
  static const refreshToken = 'refresh_token';
  static const serverUrl = 'server_url';
  static const deviceId = 'device_id';
  static const userEmail = 'user_email';

  Future<void> clearAuth() async {
    await write(accessToken, null);
    await write(refreshToken, null);
    await write(userEmail, null);
  }
}

class SecureTokenStore extends TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              mOptions: MacOsOptions(accessibility: KeychainAccessibility.first_unlock),
            );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String? value) =>
      value == null ? _storage.delete(key: key) : _storage.write(key: key, value: value);
}

class MemoryTokenStore extends TokenStore {
  final Map<String, String> _m = {};

  @override
  Future<String?> read(String key) async => _m[key];

  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      _m.remove(key);
    } else {
      _m[key] = value;
    }
  }
}

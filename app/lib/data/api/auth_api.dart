import 'api_client.dart';
import 'token_store.dart';

class AuthApi {
  AuthApi(this.client);
  final ApiClient client;

  Future<void> _credentials(String path, String email, String password, String deviceId, String platform) async {
    final data = await client.request('POST', path,
        auth: false,
        body: {
          'email': email,
          'password': password,
          'device_id': deviceId,
          'device_platform': platform,
          'device_name': platform,
        });
    await client.tokens.write(TokenStore.accessToken, data['access_token'] as String);
    await client.tokens.write(TokenStore.refreshToken, data['refresh_token'] as String);
    await client.tokens.write(TokenStore.userEmail, (data['user'] as Map<String, dynamic>)['email'] as String);
  }

  Future<void> login(String email, String password, {required String deviceId, required String platform}) =>
      _credentials('/auth/login', email, password, deviceId, platform);

  Future<void> register(String email, String password, {required String deviceId, required String platform}) =>
      _credentials('/auth/register', email, password, deviceId, platform);

  Future<void> logout() async {
    final refresh = await client.tokens.read(TokenStore.refreshToken);
    if (refresh != null) {
      try {
        await client.request('POST', '/auth/logout', body: {'refresh_token': refresh}, retryOnAuthError: false);
      } catch (_) {
        // best effort; local state is cleared regardless
      }
    }
    await client.tokens.clearAuth();
  }
}

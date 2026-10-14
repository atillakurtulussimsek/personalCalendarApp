
import 'package:uuid/uuid.dart';

import '../api/auth_api.dart';
import '../api/token_store.dart';
import '../db/database.dart';
import '../../core/platform_info.dart';

/// Login/register/logout plus persisted session state.
class AuthRepository {
  AuthRepository(this.api, this.tokens, this.db);

  final AuthApi api;
  final TokenStore tokens;
  final AppDatabase db;

  Future<bool> get isLoggedIn async => (await tokens.read(TokenStore.refreshToken)) != null;

  Future<String?> get email => tokens.read(TokenStore.userEmail);

  Future<String> get serverUrl async => (await tokens.read(TokenStore.serverUrl)) ?? (PlatformInfo.isWeb ? Uri.base.origin : '');

  Future<String> deviceId() async {
    var id = await tokens.read(TokenStore.deviceId);
    if (id == null) {
      id = const Uuid().v4();
      await tokens.write(TokenStore.deviceId, id);
    }
    return id;
  }

  String get platform => PlatformInfo.name;

  Future<void> _prepare(String serverUrl) async {
    var url = serverUrl.trim();
    if (url.endsWith('/')) url = url.substring(0, url.length - 1);
    if (!url.startsWith('http')) url = 'https://$url';
    await tokens.write(TokenStore.serverUrl, url);
  }

  Future<void> login({required String serverUrl, required String email, required String password}) async {
    await _prepare(serverUrl);
    await api.login(email, password, deviceId: await deviceId(), platform: platform);
  }

  Future<void> register({required String serverUrl, required String email, required String password}) async {
    await _prepare(serverUrl);
    await api.register(email, password, deviceId: await deviceId(), platform: platform);
  }

  /// Revokes the session and wipes local data (the server keeps everything).
  Future<void> logout() async {
    await api.logout();
    await db.clearAll();
  }
}

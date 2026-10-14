import 'package:web/web.dart' as web;

import 'token_store.dart';

/// Web: tokens live in localStorage.
///
/// flutter_secure_storage on the web needs a secure context (HTTPS) for
/// WebCrypto and keeps its key in localStorage anyway, so it adds no real
/// protection; plain localStorage also works when the site is served over
/// HTTP. Serve production over HTTPS regardless (see backend/README.md).
TokenStore createPlatformTokenStore() => LocalStorageTokenStore();

class LocalStorageTokenStore extends TokenStore {
  static const _prefix = 'personal_calendar.';

  @override
  Future<String?> read(String key) async => web.window.localStorage.getItem('$_prefix$key');

  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      web.window.localStorage.removeItem('$_prefix$key');
    } else {
      web.window.localStorage.setItem('$_prefix$key', value);
    }
  }
}

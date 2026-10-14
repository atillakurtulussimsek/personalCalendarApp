import 'token_store.dart';

/// Native: tokens live in the Keychain / Android Keystore.
TokenStore createPlatformTokenStore() => SecureTokenStore();

import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../data/api/api_client.dart';
import '../data/api/token_store.dart';
import '../data/sync/sync_service.dart';
import 'background_sync.dart';

/// Firebase Cloud Messaging on Android: receives silent "sync" data messages.
///
/// Configuration comes from --dart-define (no google-services.json needed):
///   FIREBASE_API_KEY, FIREBASE_APP_ID, FIREBASE_SENDER_ID, FIREBASE_PROJECT_ID
/// When they are empty, push is disabled and the app relies on WebSocket + WorkManager.
class PushService {
  PushService(this.client, this.tokens, this.sync);

  final ApiClient client;
  final TokenStore tokens;
  final SyncService sync;

  static const _apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const _appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const _senderId = String.fromEnvironment('FIREBASE_SENDER_ID');
  static const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');

  static bool get configured => _apiKey.isNotEmpty && _appId.isNotEmpty && _senderId.isNotEmpty && _projectId.isNotEmpty;
  static bool get supported => Platform.isAndroid && configured;

  static FirebaseOptions get options => const FirebaseOptions(apiKey: _apiKey, appId: _appId, messagingSenderId: _senderId, projectId: _projectId);

  bool _started = false;

  /// Must run before runApp on Android when configured.
  static Future<void> initFirebase() async {
    if (!supported) return;
    try {
      await Firebase.initializeApp(options: options);
      FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
    } catch (e) {
      debugPrint('firebase init failed: $e');
    }
  }

  Future<void> start() async {
    if (!supported || _started) return;
    _started = true;
    try {
      final fm = FirebaseMessaging.instance;
      await fm.setAutoInitEnabled(true);
      final token = await fm.getToken();
      if (token != null) await _registerToken(token);
      fm.onTokenRefresh.listen(_registerToken);
      FirebaseMessaging.onMessage.listen((m) {
        if (m.data['type'] == 'sync') sync.sync();
      });
    } catch (e) {
      debugPrint('fcm start failed: $e');
    }
  }

  Future<void> _registerToken(String token) async {
    final deviceId = await tokens.read(TokenStore.deviceId);
    if (deviceId == null) return;
    try {
      await client.request('PUT', '/devices/$deviceId', body: {'push_token': token});
    } catch (_) {
      // offline: the next start() retries
    }
  }
}

/// Runs in a background isolate when a data message arrives while the app is
/// killed or in the background: perform one sync with a throwaway stack.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  if (message.data['type'] != 'sync') return;
  await runHeadlessSync();
}

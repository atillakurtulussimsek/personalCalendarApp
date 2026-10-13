import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../data/api/api_client.dart';
import '../data/api/sync_api.dart';
import '../data/api/token_store.dart';
import '../data/db/database.dart';
import '../data/sync/sync_service.dart';

const backgroundSyncTask = 'personal_calendar.sync';

/// One sync with a self-contained stack (DB + API), usable from any isolate.
/// The database is opened with `shareAcrossIsolates`, so the UI isolate and
/// background workers never block each other.
Future<bool> runHeadlessSync() async {
  WidgetsFlutterBinding.ensureInitialized();
  final tokens = SecureTokenStore();
  if (await tokens.read(TokenStore.refreshToken) == null) return true; // logged out
  final db = AppDatabase.open();
  final client = ApiClient(tokens);
  final sync = SyncService(db, HttpSyncApi(client));
  try {
    final r = await sync.sync();
    return r.ok || r.error is NetworkException; // network errors → let WorkManager retry later
  } finally {
    await sync.dispose();
    await db.close();
  }
}

/// WorkManager entry point (Android). Must be a top-level function.
@pragma('vm:entry-point')
void backgroundSyncDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == backgroundSyncTask) {
      try {
        return await runHeadlessSync();
      } catch (e) {
        debugPrint('background sync failed: $e');
        return false;
      }
    }
    return true;
  });
}

/// Registers the periodic background sync (Android only; 15 min is the OS minimum).
class BackgroundSync {
  static bool get supported => Platform.isAndroid;

  static Future<void> register() async {
    if (!supported) return;
    try {
      await Workmanager().initialize(backgroundSyncDispatcher);
      await Workmanager().registerPeriodicTask(
        backgroundSyncTask,
        backgroundSyncTask,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
        backoffPolicy: BackoffPolicy.exponential,
        backoffPolicyDelay: const Duration(minutes: 5),
      );
    } catch (e) {
      debugPrint('workmanager register failed: $e');
    }
  }

  static Future<void> cancel() async {
    if (!supported) return;
    try {
      await Workmanager().cancelByUniqueName(backgroundSyncTask);
    } catch (_) {}
  }
}

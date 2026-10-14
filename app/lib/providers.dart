import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/api/api_client.dart';
import 'data/api/auth_api.dart';
import 'data/api/sync_api.dart';
import 'data/api/token_store.dart';
import 'data/api/token_store_platform_native.dart' if (dart.library.js_interop) 'data/api/token_store_platform_web.dart';
import 'data/db/database.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/ics_service.dart';
import 'data/repositories/repositories.dart';
import 'data/sync/sync_service.dart';
import 'platform/background_sync.dart';
import 'platform/desktop_integration.dart';
import 'platform/live_sync.dart';
import 'platform/push_service.dart';
import 'platform/reminders_service.dart';
import 'platform/widget_publisher.dart';
import 'core/platform_info.dart';

/// Overridden in tests with in-memory implementations.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase.open();
  ref.onDispose(db.close);
  return db;
});

final tokenStoreProvider = Provider<TokenStore>((ref) => createPlatformTokenStore());

final Provider<ApiClient> apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(ref.watch(tokenStoreProvider), onSessionExpired: () {
    ref.read(sessionProvider.notifier).expire();
  }, onTokenRefreshed: () {
    ref.read(liveSyncProvider).reconnect();
  });
});

final Provider<SyncApi> syncApiProvider = Provider<SyncApi>((ref) => HttpSyncApi(ref.watch(apiClientProvider)));

final Provider<SyncService> syncServiceProvider = Provider<SyncService>((ref) {
  final s = SyncService(ref.watch(databaseProvider), ref.watch(syncApiProvider));
  ref.onDispose(s.dispose);
  return s;
});

final syncStatusProvider = StreamProvider<SyncStatus>((ref) {
  final s = ref.watch(syncServiceProvider);
  return s.status;
});

final authRepositoryProvider = Provider<AuthRepository>((ref) => AuthRepository(
      AuthApi(ref.watch(apiClientProvider)),
      ref.watch(tokenStoreProvider),
      ref.watch(databaseProvider),
    ));

final userEmailProvider = FutureProvider<String?>((ref) {
  ref.watch(sessionProvider);
  return ref.watch(authRepositoryProvider).email;
});

final calendarRepositoryProvider =
    Provider<CalendarRepository>((ref) => CalendarRepository(ref.watch(databaseProvider), ref.watch(syncServiceProvider)));
final eventRepositoryProvider =
    Provider<EventRepository>((ref) => EventRepository(ref.watch(databaseProvider), ref.watch(syncServiceProvider)));
final taskRepositoryProvider =
    Provider<TaskRepository>((ref) => TaskRepository(ref.watch(databaseProvider), ref.watch(syncServiceProvider)));
final icsServiceProvider = Provider<IcsService>((ref) => IcsService(ref.watch(calendarRepositoryProvider)));
final noteRepositoryProvider =
    Provider<NoteRepository>((ref) => NoteRepository(ref.watch(databaseProvider), ref.watch(syncServiceProvider)));

enum SessionState { unknown, loggedOut, loggedIn }

/// Whether the user has a session. Drives the root navigation.
class SessionNotifier extends Notifier<SessionState> {
  @override
  SessionState build() {
    _load();
    return SessionState.unknown;
  }

  Future<void> _load() async {
    final ok = await ref.read(authRepositoryProvider).isLoggedIn;
    state = ok ? SessionState.loggedIn : SessionState.loggedOut;
    if (ok) await ref.read(calendarRepositoryProvider).ensureDefault();
  }

  Future<void> login(String server, String email, String password) async {
    await ref.read(authRepositoryProvider).login(serverUrl: server, email: email, password: password);
    await _afterAuth();
  }

  Future<void> register(String server, String email, String password) async {
    await ref.read(authRepositoryProvider).register(serverUrl: server, email: email, password: password);
    await _afterAuth();
  }

  Future<void> _afterAuth() async {
    state = SessionState.loggedIn;
    final sync = ref.read(syncServiceProvider);
    await sync.sync();
    await ref.read(calendarRepositoryProvider).ensureDefault();
  }

  Future<void> logout() async {
    ref.read(syncTriggersProvider).stop();
    await ref.read(remindersServiceProvider).cancelAll();
    await BackgroundSync.cancel();
    await ref.read(authRepositoryProvider).logout();
    state = SessionState.loggedOut;
  }

  void expire() => state = SessionState.loggedOut;
}

final sessionProvider = NotifierProvider<SessionNotifier, SessionState>(SessionNotifier.new);

/// Triggers sync on foreground, connectivity regain and a periodic timer.
class SyncTriggers with WidgetsBindingObserver {
  SyncTriggers(this.sync, this.ics, this.live, this.reminders, this.push);
  final SyncService sync;
  final IcsService ics;
  final LiveSync live;
  final RemindersService reminders;
  final PushService push;
  StreamSubscription<List<ConnectivityResult>>? _conn;
  StreamSubscription<void>? _applied;
  Timer? _periodic;

  void start() {
    WidgetsBinding.instance.addObserver(this);
    _conn = Connectivity().onConnectivityChanged.listen((results) {
      if (results.any((r) => r != ConnectivityResult.none)) {
        sync.sync();
        live.reconnect();
      }
    });
    _periodic = Timer.periodic(const Duration(minutes: 5), (_) {
      sync.sync();
      ics.refreshStale();
    });
    // after remote changes land, reminders of changed/deleted events are re-planned
    _applied = sync.onApplied.listen((_) => reminders.refresh());
    sync.sync();
    ics.refreshStale();
    reminders.init().then((_) => reminders.start());
    live.start();
    push.start();
    BackgroundSync.register();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      sync.sync();
      ics.refreshStale();
      live.start();
    } else if (state == AppLifecycleState.paused && PlatformInfo.isAndroid) {
      // Android: no socket in the background (Doze would kill it); FCM/WorkManager take over
      live.stop();
    }
  }

  void stop() {
    WidgetsBinding.instance.removeObserver(this);
    _conn?.cancel();
    _applied?.cancel();
    _periodic?.cancel();
    live.stop();
  }
}

final syncTriggersProvider = Provider<SyncTriggers>((ref) {
  final t = SyncTriggers(ref.watch(syncServiceProvider), ref.watch(icsServiceProvider), ref.watch(liveSyncProvider),
      ref.watch(remindersServiceProvider), ref.watch(pushServiceProvider));
  ref.onDispose(t.stop);
  return t;
});

final remindersServiceProvider = Provider<RemindersService>((ref) {
  final r = RemindersService(ref.watch(eventRepositoryProvider), ref.watch(calendarRepositoryProvider));
  ref.onDispose(r.dispose);
  return r;
});

final Provider<LiveSync> liveSyncProvider = Provider<LiveSync>((ref) {
  final l = LiveSync(ref.watch(tokenStoreProvider), ref.watch(syncServiceProvider));
  ref.onDispose(l.dispose);
  return l;
});

final liveStateProvider = StreamProvider<LiveState>((ref) => ref.watch(liveSyncProvider).state);

final pushServiceProvider = Provider<PushService>(
    (ref) => PushService(ref.watch(apiClientProvider), ref.watch(tokenStoreProvider), ref.watch(syncServiceProvider)));

final widgetPublisherProvider = Provider<WidgetPublisher>((ref) {
  final w = WidgetPublisher(ref.watch(eventRepositoryProvider), ref.watch(calendarRepositoryProvider));
  ref.onDispose(w.stop);
  return w;
});

/// Labels are injected by the shell once localizations are available.
final desktopLabelsProvider = Provider<DesktopLabels>((ref) =>
    const DesktopLabels(appTitle: 'Takvim', quickCapture: 'Hızlı ekle', noEvents: 'Yaklaşan etkinlik yok', showWindow: 'Pencereyi göster', quit: 'Çıkış'));

final desktopIntegrationProvider = Provider<DesktopIntegration>((ref) {
  final d = DesktopIntegration(ref.watch(eventRepositoryProvider), ref.watch(calendarRepositoryProvider), ref.watch(desktopLabelsProvider));
  ref.onDispose(d.dispose);
  return d;
});

final calendarsProvider = StreamProvider<List<Calendar>>((ref) => ref.watch(calendarRepositoryProvider).watchAll());
final notesProvider = StreamProvider<List<Note>>((ref) => ref.watch(noteRepositoryProvider).watchAll());
final tasksProvider = StreamProvider<List<Task>>((ref) => ref.watch(taskRepositoryProvider).watchAll());

/// Theme mode from the device-local settings ("system" | "light" | "dark").
class ThemeModeNotifier extends Notifier<ThemeMode> {
  static const key = 'setting.theme_mode';

  @override
  ThemeMode build() {
    ref.read(databaseProvider).getState(key).then((v) {
      if (v != null) state = _parse(v);
    });
    return ThemeMode.system;
  }

  static ThemeMode _parse(String v) => switch (v) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  Future<void> set(ThemeMode m) async {
    state = m;
    await ref.read(databaseProvider).setState(key, m.name);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

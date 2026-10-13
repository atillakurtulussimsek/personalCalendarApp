import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/api/api_client.dart';
import 'data/api/auth_api.dart';
import 'data/api/sync_api.dart';
import 'data/api/token_store.dart';
import 'data/db/database.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/ics_service.dart';
import 'data/repositories/repositories.dart';
import 'data/sync/sync_service.dart';

/// Overridden in tests with in-memory implementations.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase.open();
  ref.onDispose(db.close);
  return db;
});

final tokenStoreProvider = Provider<TokenStore>((ref) => SecureTokenStore());

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(ref.watch(tokenStoreProvider), onSessionExpired: () {
    ref.read(sessionProvider.notifier).expire();
  });
});

final syncApiProvider = Provider<SyncApi>((ref) => HttpSyncApi(ref.watch(apiClientProvider)));

final syncServiceProvider = Provider<SyncService>((ref) {
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

final calendarRepositoryProvider =
    Provider<CalendarRepository>((ref) => CalendarRepository(ref.watch(databaseProvider), ref.watch(syncServiceProvider)));
final eventRepositoryProvider =
    Provider<EventRepository>((ref) => EventRepository(ref.watch(databaseProvider), ref.watch(syncServiceProvider)));
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
    await ref.read(authRepositoryProvider).logout();
    state = SessionState.loggedOut;
  }

  void expire() => state = SessionState.loggedOut;
}

final sessionProvider = NotifierProvider<SessionNotifier, SessionState>(SessionNotifier.new);

/// Triggers sync on foreground, connectivity regain and a periodic timer.
class SyncTriggers with WidgetsBindingObserver {
  SyncTriggers(this.sync, this.ics);
  final SyncService sync;
  final IcsService ics;
  StreamSubscription<List<ConnectivityResult>>? _conn;
  Timer? _periodic;

  void start() {
    WidgetsBinding.instance.addObserver(this);
    _conn = Connectivity().onConnectivityChanged.listen((results) {
      if (results.any((r) => r != ConnectivityResult.none)) sync.sync();
    });
    _periodic = Timer.periodic(const Duration(minutes: 5), (_) {
      sync.sync();
      ics.refreshStale();
    });
    sync.sync();
    ics.refreshStale();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      sync.sync();
      ics.refreshStale();
    }
  }

  void stop() {
    WidgetsBinding.instance.removeObserver(this);
    _conn?.cancel();
    _periodic?.cancel();
  }
}

final syncTriggersProvider = Provider<SyncTriggers>((ref) {
  final t = SyncTriggers(ref.watch(syncServiceProvider), ref.watch(icsServiceProvider));
  ref.onDispose(t.stop);
  return t;
});

final calendarsProvider = StreamProvider<List<Calendar>>((ref) => ref.watch(calendarRepositoryProvider).watchAll());
final notesProvider = StreamProvider<List<Note>>((ref) => ref.watch(noteRepositoryProvider).watchAll());

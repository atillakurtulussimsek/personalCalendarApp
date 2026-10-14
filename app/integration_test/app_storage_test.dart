import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:personal_calendar/data/api/token_store.dart';
import 'package:personal_calendar/data/db/database.dart';
import 'package:personal_calendar/data/repositories/repositories.dart';
import 'package:personal_calendar/data/sync/sync_service.dart';

import '../test/fake_sync_api.dart';

/// Runs on a real device/desktop: `flutter test integration_test -d macos`.
/// Covers the platform pieces unit tests cannot: the OS keychain and the
/// on-disk SQLite database (with FTS5) opened the same way the app does.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('secure token store round-trips through the OS keychain', (tester) async {
    final store = SecureTokenStore();
    await store.write('integration_probe', 'value-1');
    expect(await store.read('integration_probe'), 'value-1');
    await store.write('integration_probe', null);
    expect(await store.read('integration_probe'), isNull);
  });

  testWidgets('on-disk database: offline create → search → sync', (tester) async {
    final db = AppDatabase.open();
    final api = FakeSyncApi();
    final sync = SyncService(db, api, debounce: const Duration(days: 1));
    final notes = NoteRepository(db, sync);
    final n = await notes.create(title: 'Entegrasyon', body: 'rehberlik semineri notu');
    expect((await notes.search('semin')).any((x) => x.id == n.id), isTrue);
    final r = await sync.sync();
    expect(r.ok, isTrue);
    expect(api.get('note', n.id)!['title'], 'Entegrasyon');
    await notes.remove(n.id);
    await sync.sync();
    await sync.dispose();
    await db.close();
  });
}

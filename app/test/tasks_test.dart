import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_calendar/core/ics.dart';
import 'package:personal_calendar/core/tz.dart';
import 'package:personal_calendar/data/db/database.dart';
import 'package:personal_calendar/data/repositories/repositories.dart';
import 'package:personal_calendar/data/sync/sync_service.dart';

import 'fake_sync_api.dart';

void main() {
  setUpAll(() => Tz.initForTest());

  test('tasks: local-first create/done/delete and sync both ways', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final api = FakeSyncApi();
    final sync = SyncService(db, api, debounce: const Duration(days: 1));
    final tasks = TaskRepository(db, sync);
    final t = await tasks.create(title: ' Rapor ', dueAt: DateTime(2026, 3, 1, 9));
    await tasks.setDone(t.id, true);
    expect((await tasks.watchAll().first).single.done, isTrue);
    await sync.sync();
    expect(api.get('task', t.id)!['done'], true);
    expect(api.get('task', t.id)!['title'], 'Rapor');
    // remote task arrives
    api.serverWrite('task', 'r1', {'title': 'Uzaktan', 'done': false});
    await sync.sync();
    final all = await tasks.watchAll().first;
    expect(all.first.id, 'r1'); // open first
    expect(all.length, 2);
    await tasks.remove(t.id);
    await sync.sync();
    expect(api.get('task', t.id)!['deleted_at'], isNotNull);
    await sync.dispose();
    await db.close();
  });

  test('ICS writer round-trips through the parser', () {
    final text = writeIcs([
      IcsEvent(uid: 'a', summary: 'Toplantı, uzun; başlık', start: DateTime.utc(2026, 1, 5, 6), end: DateTime.utc(2026, 1, 5, 7), allDay: false, rrule: 'FREQ=WEEKLY;BYDAY=MO', location: 'Salon'),
      IcsEvent(uid: 'b', summary: 'Tatil', start: DateTime.utc(2026, 4, 23), end: DateTime.utc(2026, 4, 24), allDay: true, description: 'çok ' * 40),
    ]);
    expect(text.split('\r\n').every((l) => l.length <= 76), isTrue, reason: 'lines must be folded');
    final back = parseIcs(text);
    expect(back.length, 2);
    expect(back[0].summary, 'Toplantı, uzun; başlık');
    expect(back[0].rrule, 'FREQ=WEEKLY;BYDAY=MO');
    expect(back[0].start, DateTime.utc(2026, 1, 5, 6));
    expect(back[1].allDay, isTrue);
    expect(back[1].description.trim(), ('çok ' * 40).trim());
  });
}

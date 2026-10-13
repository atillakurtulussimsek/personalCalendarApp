import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_calendar/data/db/database.dart';
import 'package:personal_calendar/data/repositories/repositories.dart';
import 'package:personal_calendar/data/sync/mappers.dart';
import 'package:personal_calendar/data/sync/sync_service.dart';

import 'fake_sync_api.dart';

void main() {
  late AppDatabase db;
  late FakeSyncApi api;
  late SyncService sync;
  late NoteRepository notes;
  late EventRepository events;
  late CalendarRepository calendars;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    api = FakeSyncApi();
    sync = SyncService(db, api, debounce: const Duration(days: 1)); // no auto-sync in tests
    notes = NoteRepository(db, sync);
    events = EventRepository(db, sync);
    calendars = CalendarRepository(db, sync);
  });

  tearDown(() async {
    await sync.dispose();
    await db.close();
  });

  Future<Note> noteById(String id) async => (await notes.get(id))!;

  test('offline create → edit → delete → sync pushes a collapsed outbox and pulls tombstones', () async {
    final cal = await calendars.ensureDefault();
    final n = await notes.create(title: 'Fikir', body: 'v1', tags: ['#Fikir', 'fikir']);
    await notes.save((await noteById(n.id)).copyWith(body: 'v2'));
    final e = await events.create(
        calendarId: cal.id, title: 'Seminer', startAt: DateTime.utc(2026, 3, 1, 10), endAt: DateTime.utc(2026, 3, 1, 11), timezone: 'Europe/Istanbul');
    await events.remove(e.id);

    // outbox collapsed: one row per record
    final pending = await db.pendingOutbox();
    expect(pending.map((p) => '${p.entity}:${p.op}'), ['calendar:upsert', 'note:upsert', 'event:delete']);
    expect(pending[1].baseVersion, 0); // started as a new record, stays 0 after the edit
    await Future<void>.delayed(Duration.zero);
    expect(sync.currentStatus.pending, 3);

    final res = await sync.sync();
    expect(res.ok, isTrue);
    expect(res.pushed, 2); // calendar + note; the delete of a never-synced event is "ignored"
    expect(api.get('note', n.id)!['body'], 'v2');
    expect(api.get('note', n.id)!['tags'], ['fikir']);
    expect(api.get('event', e.id), isNull);
    expect(await db.pendingOutbox(), isEmpty);

    // local versions now match the server
    final local = await noteById(n.id);
    expect(local.version, 1);
    expect(local.serverSeq, greaterThan(0));
    expect(await db.lastSeq, api.seq);

    // next sync is a no-op pull
    await sync.sync();
    expect(api.pushCalls, 1); // nothing to push → no call
    expect(api.pullCalls, 2);
  });

  test('pull applies remote changes and tombstones, paginated', () async {
    api.pageSize = 3;
    for (var i = 0; i < 7; i++) {
      api.serverWrite('note', 'n$i', {'title': 'remote $i', 'body': 'b$i'});
    }
    api.serverWrite('note', 'n2', {'title': 'remote 2', 'body': 'b2', 'deleted_at': DateTime.now().toUtc().toIso8601String()});
    final res = await sync.sync();
    expect(res.ok, isTrue);
    expect(res.pulled, 7); // n2 is pulled once, as a tombstone
    expect(api.pullCalls, 3);
    final live = await notes.watchAll().first;
    expect(live.map((n) => n.id).toSet(), {'n0', 'n1', 'n3', 'n4', 'n5', 'n6'});
    expect(await db.lastSeq, api.seq);
    expect((await noteById('n2')).deletedAt, isNotNull);
  });

  test('conflict: server wins → local overwritten with current, conflict copy pulled', () async {
    final n = await notes.create(title: 'N', body: 'v1');
    await sync.sync();
    // other device edits later
    api.serverWrite('note', n.id, {'title': 'N', 'body': 'server v2'}, at: DateTime.now().add(const Duration(minutes: 10)));
    // this device edits "now" (older than the server write), based on version 1
    await notes.save((await noteById(n.id)).copyWith(body: 'my offline text'));
    final res = await sync.sync();
    expect(res.conflicts, 1);
    final local = await noteById(n.id);
    expect(local.body, 'server v2');
    expect(local.version, 2);
    final all = await notes.watchAll().first;
    final copy = all.firstWhere((x) => x.title.startsWith('(çakışan kopya)'));
    expect(copy.body, 'my offline text');
    expect(await db.pendingOutbox(), isEmpty);
  });

  test('conflict: client newer wins → applied, server text kept as copy', () async {
    final n = await notes.create(title: 'N', body: 'v1');
    await sync.sync();
    api.serverWrite('note', n.id, {'title': 'N', 'body': 'server v2'}, at: DateTime.now().subtract(const Duration(minutes: 10)));
    // local base version is still 1 but updated_at is newer than the server's
    await notes.save((await noteById(n.id)).copyWith(body: 'client newer'));
    final res = await sync.sync();
    expect(res.conflicts, 0);
    expect(api.get('note', n.id)!['body'], 'client newer');
    expect(api.get('note', n.id)!['version'], 3);
    expect((await noteById(n.id)).version, 3);
    final copies = (await notes.watchAll().first).where((x) => x.title.startsWith('(çakışan kopya)'));
    expect(copies.single.body, 'server v2');
  });

  test('pull does not clobber a newer pending local edit', () async {
    final n = await notes.create(title: 'N', body: 'v1');
    await sync.sync();
    api.serverWrite('note', n.id, {'title': 'N', 'body': 'remote'}, at: DateTime.now().subtract(const Duration(minutes: 1)));
    await notes.save((await noteById(n.id)).copyWith(body: 'local newer'));
    api.offline = true;
    final res = await sync.sync();
    expect(res.ok, isFalse);
    expect(sync.currentStatus.phase, SyncPhase.offline);
    api.offline = false;
    await sync.sync();
    expect((await noteById(n.id)).body, 'local newer');
    expect(api.get('note', n.id)!['body'], 'local newer');
  });

  test('rejected items are dropped from the outbox with an error, others continue', () async {
    await db.into(db.notes).insert(Note(
        id: 'empty', title: '', body: '', pinned: false, tags: '[]', createdAt: DateTime.now(), updatedAt: DateTime.now(), version: 0, serverSeq: 0));
    await db.enqueue(entity: 'note', op: 'upsert', recordId: 'empty', baseVersion: 0, updatedAt: DateTime.now(), data: {'title': '', 'body': '', 'tags': []});
    final ok = await notes.create(title: 'ok', body: 'x');
    final res = await sync.sync();
    expect(res.rejected, 1);
    expect(res.pushed, 1);
    expect(api.get('note', ok.id), isNotNull);
    expect(await db.pendingOutbox(), isEmpty);
  });

  test('status stream: offline, unauthenticated, idle', () async {
    final phases = <SyncPhase>[];
    final sub = sync.status.listen((s) => phases.add(s.phase));
    api.offline = true;
    await sync.sync();
    api.offline = false;
    api.unauthorized = true;
    await sync.sync();
    api.unauthorized = false;
    await sync.sync();
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(phases, containsAllInOrder([SyncPhase.syncing, SyncPhase.offline, SyncPhase.syncing, SyncPhase.unauthenticated, SyncPhase.syncing, SyncPhase.idle]));
  });

  test('concurrent sync calls share one run', () async {
    await notes.create(title: 'a', body: 'b');
    final f1 = sync.sync();
    final f2 = sync.sync();
    expect(identical(f1, f2), isTrue);
    await f1;
    expect(api.pushCalls, 1);
  });

  test('mappers round-trip an event', () async {
    final cal = await calendars.ensureDefault();
    final e = await events.create(
      calendarId: cal.id,
      title: 'x',
      startAt: DateTime.utc(2026, 3, 1, 10),
      endAt: DateTime.utc(2026, 3, 1, 11),
      timezone: 'Europe/Istanbul',
      rrule: 'FREQ=WEEKLY;BYDAY=MO',
      reminders: [10, 30],
    );
    final json = {...eventToPushData(e), 'id': e.id, 'updated_at': e.updatedAt.toIso8601String(), 'version': 1, 'server_seq': 5};
    final back = eventFromJson(json);
    expect(back.rrule.value, 'FREQ=WEEKLY;BYDAY=MO');
    expect(back.startAt.value, DateTime.utc(2026, 3, 1, 10));
    expect(back.reminders.value, '[10,30]');
    expect(eventReminders(e), [10, 30]);
  });

  test('FTS search finds notes by prefix and ignores deleted ones', () async {
    await notes.create(title: 'Veli toplantısı', body: 'rehberlik semineri');
    final del = await notes.create(title: 'silinecek', body: 'rehberlik');
    await notes.remove(del.id);
    expect((await notes.search('rehber')).map((n) => n.title), ['Veli toplantısı']);
    expect((await notes.search('toplantı semin')).length, 1);
    expect(await notes.search('yok'), isEmpty);
  });
}

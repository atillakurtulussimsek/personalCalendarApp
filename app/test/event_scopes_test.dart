import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_calendar/core/recurrence.dart';
import 'package:personal_calendar/core/tz.dart';
import 'package:personal_calendar/data/db/database.dart';
import 'package:personal_calendar/data/repositories/repositories.dart';
import 'package:personal_calendar/data/sync/sync_service.dart';

import 'fake_sync_api.dart';

void main() {
  late AppDatabase db;
  late FakeSyncApi api;
  late SyncService sync;
  late EventRepository events;
  late CalendarRepository calendars;
  late String calId;
  final start = DateTime.utc(2026, 1, 5, 6); // Monday 09:00 Istanbul

  setUpAll(() => Tz.initForTest());

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    api = FakeSyncApi();
    sync = SyncService(db, api, debounce: const Duration(days: 1));
    events = EventRepository(db, sync);
    calendars = CalendarRepository(db, sync);
    calId = (await calendars.ensureDefault()).id;
  });

  tearDown(() async {
    await sync.dispose();
    await db.close();
  });

  Future<List<Occurrence>> occ() => events.watchOccurrences(DateTime.utc(2026, 1, 1), DateTime.utc(2026, 3, 1)).first;

  Future<Event> weekly({int count = 6}) => events.create(
        calendarId: calId,
        title: 'Toplantı',
        startAt: start,
        endAt: start.add(const Duration(hours: 1)),
        timezone: 'Europe/Istanbul',
        rrule: 'FREQ=WEEKLY;BYDAY=MO;COUNT=$count',
      );

  test('only this: creates an exception row linked to the master', () async {
    final m = await weekly();
    final all = await occ();
    expect(all.length, 6);
    final second = all[1];
    await events.editOccurrence(second, EditScope.onlyThis, (b) => b.copyWith(title: 'Taşındı', startAt: b.startAt.add(const Duration(hours: 5)), endAt: b.endAt.add(const Duration(hours: 5))));
    final after = await occ();
    expect(after.length, 6);
    final ex = after[1];
    expect(ex.isException, isTrue);
    expect(ex.title, 'Taşındı');
    expect(ex.event.recurrenceId, m.id);
    expect(ex.event.originalStart, start.add(const Duration(days: 7)));
    expect(ex.start, start.add(const Duration(days: 7, hours: 5)));
    // editing the exception again just updates the row
    await events.editOccurrence(ex, EditScope.onlyThis, (b) => b.copyWith(title: 'Tekrar'));
    expect((await occ())[1].title, 'Tekrar');
    expect((await db.pendingOutbox()).map((o) => o.entity).toSet(), {'calendar', 'event'});
  });

  test('all: edits the master and keeps instances anchored (delta applied)', () async {
    final m = await weekly();
    final third = (await occ())[2];
    await events.editOccurrence(third, EditScope.all, (b) => b.copyWith(title: 'Yeni ad', startAt: b.startAt.add(const Duration(minutes: 30)), endAt: b.endAt.add(const Duration(minutes: 90))));
    final master = (await events.get(m.id))!;
    expect(master.title, 'Yeni ad');
    expect(master.startAt, start.add(const Duration(minutes: 30)));
    expect(master.endAt.difference(master.startAt), const Duration(hours: 2));
    expect((await occ()).length, 6);
  });

  test('this and following: truncates with UNTIL and starts a new series with remaining COUNT', () async {
    final m = await weekly();
    final fourth = (await occ())[3];
    await events.editOccurrence(fourth, EditScope.thisAndFollowing, (b) => b.copyWith(title: 'Yeni seri', startAt: b.startAt.add(const Duration(hours: 1)), endAt: b.endAt.add(const Duration(hours: 1))));
    final master = (await events.get(m.id))!;
    expect(master.rrule, contains('UNTIL='));
    final all = await occ();
    expect(all.length, 6);
    expect(all.take(3).every((o) => o.seriesId == m.id && o.title == 'Toplantı'), isTrue);
    final rest = all.skip(3).toList();
    expect(rest.every((o) => o.seriesId != m.id && o.title == 'Yeni seri'), isTrue);
    expect(rest.first.start, start.add(const Duration(days: 21, hours: 1)));
    final newMaster = (await events.get(rest.first.seriesId))!;
    expect(newMaster.rrule, contains('COUNT=3'));
  });

  test('this and following from the first instance edits the whole series', () async {
    final m = await weekly();
    final first = (await occ()).first;
    await events.editOccurrence(first, EditScope.thisAndFollowing, (b) => b.copyWith(title: 'Hepsi'));
    expect((await events.get(m.id))!.title, 'Hepsi');
    expect((await occ()).every((o) => o.seriesId == m.id), isTrue);
  });

  test('delete scopes: only this cancels one; following truncates; all removes master + exceptions', () async {
    final m = await weekly();
    final all = await occ();
    await events.deleteOccurrence(all[1], EditScope.onlyThis);
    var now = await occ();
    expect(now.length, 5);
    expect(now.any((o) => o.start == start.add(const Duration(days: 7))), isFalse);

    await events.deleteOccurrence(now[3], EditScope.thisAndFollowing); // 5th original instance (index 3 after cancel)
    now = await occ();
    expect(now.length, 3);

    await events.deleteOccurrence(now.first, EditScope.all);
    expect(await occ(), isEmpty);
    final rows = await db.select(db.events).get();
    expect(rows.where((e) => e.id == m.id).single.deletedAt, isNotNull);
    expect(rows.where((e) => e.recurrenceId == m.id).every((e) => e.deletedAt != null), isTrue);
  });

  test('move occurrence: single event moves both ends; resize changes duration', () async {
    final e = await events.create(calendarId: calId, title: 'Tek', startAt: start, endAt: start.add(const Duration(hours: 1)));
    final o = (await occ()).single;
    await events.moveOccurrence(o, delta: const Duration(days: 1, minutes: 30));
    var r = (await events.get(e.id))!;
    expect(r.startAt, start.add(const Duration(days: 1, minutes: 30)));
    expect(r.endAt.difference(r.startAt), const Duration(hours: 1));
    await events.moveOccurrence((await occ()).single, newDuration: const Duration(minutes: 45));
    r = (await events.get(e.id))!;
    expect(r.endAt.difference(r.startAt), const Duration(minutes: 45));
  });

  test('ICS subscription events are local-only and never pushed', () async {
    final sub = await calendars.subscribe(name: 'Tatiller', url: 'https://example.com/x.ics');
    final n = await calendars.applyFeed(sub, '''BEGIN:VCALENDAR
BEGIN:VEVENT
UID:a
DTSTART;VALUE=DATE:20260123
DTEND;VALUE=DATE:20260124
SUMMARY:Tatil
END:VEVENT
END:VCALENDAR''');
    expect(n, 1);
    final o = await occ();
    expect(o.single.title, 'Tatil');
    expect(o.single.allDay, isTrue);
    await sync.sync();
    expect(api.tables['event'], isEmpty);
    expect(api.tables['calendar']!.values.any((c) => c['name'] == 'Tatiller'), isFalse);
    // re-applying the feed is idempotent (same uid → same id)
    await calendars.applyFeed(sub, '''BEGIN:VCALENDAR
BEGIN:VEVENT
UID:a
DTSTART;VALUE=DATE:20260123
DTEND;VALUE=DATE:20260124
SUMMARY:Tatil 2
END:VEVENT
END:VCALENDAR''');
    expect((await occ()).single.title, 'Tatil 2');
    await calendars.remove(sub.id);
    expect(await occ(), isEmpty);
  });
}

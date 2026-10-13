import 'package:drift/native.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_calendar/core/tz.dart';
import 'package:personal_calendar/data/db/database.dart';
import 'package:personal_calendar/data/repositories/repositories.dart';
import 'package:personal_calendar/data/sync/sync_service.dart';
import 'package:personal_calendar/platform/reminders_service.dart';

import 'fake_sync_api.dart';

void main() {
  late AppDatabase db;
  late SyncService sync;
  late EventRepository events;
  late CalendarRepository calendars;
  late RemindersService reminders;

  setUpAll(() => Tz.initForTest());

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    sync = SyncService(db, FakeSyncApi(), debounce: const Duration(days: 1));
    events = EventRepository(db, sync);
    calendars = CalendarRepository(db, sync);
    reminders = RemindersService(events, calendars, plugin: FlutterLocalNotificationsPlugin());
  });

  tearDown(() async {
    await reminders.dispose();
    await sync.dispose();
    await db.close();
  });

  test('plan: one id per (occurrence, reminder), past ones skipped, stable ids, ICS excluded', () async {
    final cal = await calendars.ensureDefault();
    final now = DateTime.now();
    final start = now.add(const Duration(hours: 2));
    final e = await events.create(calendarId: cal.id, title: 'Dişçi', startAt: start, endAt: start.add(const Duration(hours: 1)), reminders: [30, 180]);
    final weekly = await events.create(
        calendarId: cal.id, title: 'Haftalık', startAt: now.add(const Duration(days: 1)), endAt: now.add(const Duration(days: 1, hours: 1)),
        rrule: 'FREQ=DAILY;COUNT=3', reminders: [10]);
    final sub = await calendars.subscribe(name: 'ics', url: 'x');
    await calendars.applyFeed(sub, 'BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:h\nDTSTART;VALUE=DATE:${_ymd(now.add(const Duration(days: 2)))}\nSUMMARY:Tatil\nEND:VEVENT\nEND:VCALENDAR');

    final occ = await events.watchOccurrences(now, now.add(const Duration(days: 14))).first;
    final plan = await reminders.plan(occ, now: now);
    // dişçi: 30 min before (in 1.5h) ✓, 180 min before (already past) ✗; daily: 3 × 10 min
    expect(plan.length, 4);
    final ids = plan.keys.toSet();
    expect(ids.contains(RemindersService.reminderId(e.id, e.startAt, 30)), isTrue);
    expect(ids.contains(RemindersService.reminderId(e.id, e.startAt, 180)), isFalse);
    expect(plan.values.where((p) => p.occurrence.event.id == weekly.id).length, 3);
    expect(plan.values.any((p) => p.occurrence.title == 'Tatil'), isFalse);
    // ids are deterministic and distinct
    expect(RemindersService.reminderId('a', DateTime.utc(2026), 10), RemindersService.reminderId('a', DateTime.utc(2026), 10));
    expect(RemindersService.reminderId('a', DateTime.utc(2026), 10) == RemindersService.reminderId('a', DateTime.utc(2026), 20), isFalse);
    // a deleted event drops out of the plan
    await events.remove(e.id);
    final occ2 = await events.watchOccurrences(now, now.add(const Duration(days: 14))).first;
    expect((await reminders.plan(occ2, now: now)).length, 3);
  });
}

String _ymd(DateTime d) => '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

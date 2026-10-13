import 'package:flutter_test/flutter_test.dart';
import 'package:personal_calendar/core/recurrence.dart';
import 'package:personal_calendar/core/tz.dart';
import 'package:personal_calendar/data/db/database.dart';

Event ev({
  required String id,
  required DateTime start,
  required DateTime end,
  String tz = 'UTC',
  String? rrule,
  String? recurrenceId,
  DateTime? originalStart,
  DateTime? deletedAt,
}) =>
    Event(
      id: id,
      calendarId: 'c',
      title: id,
      description: '',
      location: '',
      startAt: start,
      endAt: end,
      timezone: tz,
      allDay: false,
      rrule: rrule,
      recurrenceId: recurrenceId,
      originalStart: originalStart,
      reminders: '[]',
      createdAt: start,
      updatedAt: start,
      deletedAt: deletedAt,
      version: 1,
      serverSeq: 1,
    );

void main() {
  setUpAll(() => Tz.initForTest());

  test('weekly rule keeps local wall time across a DST change', () {
    // Monday 09:00 Europe/Berlin (CET, UTC+1) = 08:00Z; after 29 March it is CEST → 07:00Z
    final start = DateTime.utc(2026, 3, 23, 8);
    final e = ev(id: 'm', start: start, end: start.add(const Duration(hours: 1)), tz: 'Europe/Berlin', rrule: 'FREQ=WEEKLY;BYDAY=MO;COUNT=3');
    final occ = expandEvents([e], DateTime.utc(2026, 3, 1), DateTime.utc(2026, 5, 1));
    expect(occ.map((o) => o.start), [
      DateTime.utc(2026, 3, 23, 8),
      DateTime.utc(2026, 3, 30, 7),
      DateTime.utc(2026, 4, 6, 7),
    ]);
  });

  test('exceptions replace and cancel instances; moved exception appears', () {
    final start = DateTime.utc(2026, 1, 5, 10);
    final master = ev(id: 'm', start: start, end: start.add(const Duration(minutes: 30)), rrule: 'FREQ=DAILY;COUNT=5');
    final moved = ev(
        id: 'x1',
        start: start.add(const Duration(days: 1, hours: 5)),
        end: start.add(const Duration(days: 1, hours: 5, minutes: 30)),
        recurrenceId: 'm',
        originalStart: start.add(const Duration(days: 1)));
    final removed = ev(
        id: 'x2',
        start: start.add(const Duration(days: 2)),
        end: start.add(const Duration(days: 2, minutes: 30)),
        recurrenceId: 'm',
        originalStart: start.add(const Duration(days: 2)),
        deletedAt: DateTime.now());
    final occ = expandEvents([master, moved, removed], start.subtract(const Duration(days: 1)), start.add(const Duration(days: 10)));
    expect(occ.length, 4);
    expect(occ[1].event.id, 'x1');
    expect(occ[1].isException, isTrue);
    expect(occ[1].originalStart, start.add(const Duration(days: 1)));
    expect(occ.any((o) => o.start == start.add(const Duration(days: 2))), isFalse);
    expect(occ.where((o) => !o.isException).map((o) => o.originalStart).toList(), [start, start.add(const Duration(days: 3)), start.add(const Duration(days: 4))]);
  });

  test('instance overlapping the window start is included; tombstones skipped', () {
    final start = DateTime.utc(2026, 1, 1, 23);
    final e = ev(id: 'm', start: start, end: start.add(const Duration(hours: 2)), rrule: 'FREQ=DAILY;COUNT=2');
    final occ = expandEvents([e], DateTime.utc(2026, 1, 2), DateTime.utc(2026, 1, 2, 12));
    expect(occ.single.start, start);
    final dead = ev(id: 'd', start: start, end: start.add(const Duration(hours: 1)), deletedAt: DateTime.now());
    expect(expandEvents([dead], DateTime.utc(2026, 1, 1), DateTime.utc(2026, 1, 3)), isEmpty);
  });

  test('monthly by month day and describe', () {
    final start = DateTime.utc(2026, 1, 31, 9);
    final e = ev(id: 'm', start: start, end: start.add(const Duration(hours: 1)), rrule: 'FREQ=MONTHLY;BYMONTHDAY=31');
    final occ = expandEvents([e], DateTime.utc(2026, 1, 1), DateTime.utc(2026, 6, 1));
    expect(occ.map((o) => o.start.month), [1, 3, 5]);
    expect(describeRrule('FREQ=WEEKLY;BYDAY=MO,WE;INTERVAL=2'), 'Her 2 haftada bir: Pzt, Çar');
    expect(describeRrule('FREQ=DAILY;COUNT=3'), 'Her gün, 3 kez');
    expect(describeRrule('garbage'), '');
    expect(parseRrule('RRULE:FREQ=YEARLY')!.frequency.toString(), isNotEmpty);
  });

  test('Tz wall conversions round-trip', () {
    final utc = DateTime.utc(2026, 7, 1, 12);
    final wall = Tz.toWall(utc, 'Europe/Istanbul');
    expect(wall, DateTime.utc(2026, 7, 1, 15));
    expect(Tz.fromWall(wall, 'Europe/Istanbul'), utc);
    expect(Tz.isValid('Mars/Olympus'), isFalse);
  });
}

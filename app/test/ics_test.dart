import 'package:flutter_test/flutter_test.dart';
import 'package:personal_calendar/core/ics.dart';
import 'package:personal_calendar/core/tz.dart';

const sample = '''BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//test//EN
BEGIN:VEVENT
DTSTART;VALUE=DATE:20260423
DTEND;VALUE=DATE:20260424
SUMMARY:Ulusal Egemenlik ve Çocuk Bayramı
UID:holiday-1
DESCRIPTION:Resmi tatil\\, tüm gün
END:VEVENT
BEGIN:VEVENT
DTSTART;TZID=Europe/Istanbul:20260105T090000
DURATION:PT1H
RRULE:FREQ=WEEKLY;BYDAY=MO
SUMMARY:Haftalık
  toplantı
LOCATION:Salon A
UID:weekly-1
END:VEVENT
BEGIN:VEVENT
DTSTART:20260301T100000Z
DTEND:20260301T113000Z
SUMMARY:UTC event
END:VEVENT
END:VCALENDAR
''';

void main() {
  setUpAll(() => Tz.initForTest());

  test('parses dates, zones, durations, folding and escapes', () {
    final events = parseIcs(sample);
    expect(events.length, 3);
    final h = events[0];
    expect(h.allDay, isTrue);
    expect(h.start, DateTime.utc(2026, 4, 23));
    expect(h.end, DateTime.utc(2026, 4, 24));
    expect(h.description, 'Resmi tatil, tüm gün');
    expect(h.uid, 'holiday-1');
    final w = events[1];
    expect(w.summary, 'Haftalık toplantı');
    expect(w.start, DateTime.utc(2026, 1, 5, 6));
    expect(w.end, DateTime.utc(2026, 1, 5, 7));
    expect(w.timezone, 'Europe/Istanbul');
    expect(w.rrule, 'FREQ=WEEKLY;BYDAY=MO');
    expect(w.location, 'Salon A');
    final u = events[2];
    expect(u.start, DateTime.utc(2026, 3, 1, 10));
    expect(u.end, DateTime.utc(2026, 3, 1, 11, 30));
    expect(u.uid, isNotEmpty);
  });
}

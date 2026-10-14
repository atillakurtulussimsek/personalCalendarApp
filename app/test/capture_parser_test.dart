import 'package:flutter_test/flutter_test.dart';
import 'package:personal_calendar/core/capture_parser.dart';

void main() {
  // Wednesday 14 October 2026, 10:30 local
  final now = DateTime(2026, 10, 14, 10, 30);
  final p = CaptureParser(now: () => now);

  test('yarın 15:00 veli toplantısı → tomorrow 15:00–16:00', () {
    final r = p.parse('yarın 15:00 veli toplantısı');
    expect(r.isEvent, isTrue);
    expect(r.title, 'Veli toplantısı');
    expect(r.start, DateTime(2026, 10, 15, 15));
    expect(r.end, DateTime(2026, 10, 15, 16));
    expect(r.allDay, isFalse);
  });

  test('cuma 10-12 rehberlik semineri @konferans salonu → Friday 10–12 with location', () {
    final r = p.parse('cuma 10-12 rehberlik semineri @konferans salonu');
    expect(r.title, 'Rehberlik semineri');
    expect(r.start, DateTime(2026, 10, 16, 10));
    expect(r.end, DateTime(2026, 10, 16, 12));
    expect(r.location, 'konferans salonu');
    expect(p.parse('yarın 10:00 sunum @Konferans Salonu').location, 'Konferans Salonu');
  });

  test('her pazartesi 9:00 haftalık toplantı → weekly RRULE starting next Monday', () {
    final r = p.parse('her pazartesi 9:00 haftalık toplantı');
    expect(r.rrule, 'FREQ=WEEKLY;BYDAY=MO');
    expect(r.start, DateTime(2026, 10, 19, 9));
    expect(r.end, DateTime(2026, 10, 19, 10));
    expect(r.title, 'Haftalık toplantı');
  });

  test('3 kasım saat 14.30 dişçi 30 dk önce hatırlat → date, time and reminder', () {
    final r = p.parse('3 kasım saat 14.30 dişçi 30 dk önce hatırlat');
    expect(r.start, DateTime(2026, 11, 3, 14, 30));
    expect(r.reminders, [30]);
    expect(r.title, 'Dişçi');
  });

  test('bugün akşam market alışverişi → today 19:00', () {
    final r = p.parse('bugün akşam market alışverişi');
    expect(r.start, DateTime(2026, 10, 14, 19));
    expect(r.end, DateTime(2026, 10, 14, 20));
    expect(r.title, 'Market alışverişi');
  });

  test('no date or time → note', () {
    final r = p.parse('Proje fikri: takvim uygulamasına widget ekle');
    expect(r.kind, CaptureKind.note);
    expect(r.title, 'Proje fikri: takvim uygulamasına widget ekle');
    expect(r.start, isNull);
  });

  test('multi-line note keeps the body', () {
    final r = p.parse('Alışveriş\nsüt\nekmek');
    expect(r.kind, CaptureKind.note);
    expect(r.title, 'Alışveriş');
    expect(r.body, 'süt\nekmek');
  });

  test('time only, already passed → tomorrow; still ahead → today', () {
    expect(p.parse('09:00 spor').start, DateTime(2026, 10, 15, 9));
    expect(p.parse('saat 16 spor').start, DateTime(2026, 10, 14, 16));
    expect(p.parse("17'de spor").start, DateTime(2026, 10, 14, 17));
  });

  test('date only → all-day event; numeric dates; past month rolls to next year', () {
    final r = p.parse('25 aralık doğum günü');
    expect(r.allDay, isTrue);
    expect(r.start, DateTime(2026, 12, 25));
    expect(r.end, DateTime(2026, 12, 26));
    expect(p.parse('03.11 sunum').start, DateTime(2026, 11, 3));
    expect(p.parse('03.11.2027 sunum').start, DateTime(2027, 11, 3));
    expect(p.parse('5 mart tatil').start, DateTime(2027, 3, 5));
    expect(p.parse('5 mart 2026 tatil').start, DateTime(2026, 3, 5));
  });

  test('weekday suffixes, same weekday today, next week', () {
    expect(p.parse('cumaya rapor').start, DateTime(2026, 10, 16));
    expect(p.parse('pazartesiye kadar rapor').start, DateTime(2026, 10, 19));
    // today is Wednesday: "çarşamba 16:00" is still ahead → today
    expect(p.parse('çarşamba 16:00 ders').start, DateTime(2026, 10, 14, 16));
    // "çarşamba 09:00" already passed → next Wednesday
    expect(p.parse('çarşamba 09:00 ders').start, DateTime(2026, 10, 21, 9));
    expect(p.parse('haftaya cuma 10:00 toplantı').start, DateTime(2026, 10, 23, 10));
    expect(p.parse('haftaya toplantı').start, DateTime(2026, 10, 21));
    expect(p.parse('öbür gün 11:00 kahve').start, DateTime(2026, 10, 16, 11));
  });

  test('day parts with hours, afternoon shorthand', () {
    expect(p.parse('yarın akşam 7 sinema').start, DateTime(2026, 10, 15, 19));
    expect(p.parse('yarın sabah 8.30 koşu').start, DateTime(2026, 10, 15, 8, 30));
    expect(p.parse('yarın öğleden sonra 2-4 atölye').end, DateTime(2026, 10, 15, 16));
    expect(p.parse('yarın öğlen yemek').start, DateTime(2026, 10, 15, 12));
    expect(p.parse('yarın gece nöbet').start, DateTime(2026, 10, 15, 21));
  });

  test('duration and time ranges', () {
    final r = p.parse('yarın 14:00 2 saat sunum');
    expect(r.end, DateTime(2026, 10, 15, 16));
    expect(r.title, 'Sunum');
    expect(p.parse('yarın 14:00 1,5 saat sunum').end, DateTime(2026, 10, 15, 15, 30));
    expect(p.parse('yarın 14:00 45 dk sunum').end, DateTime(2026, 10, 15, 14, 45));
    expect(p.parse('yarın 10:00-11:30 görüşme').end, DateTime(2026, 10, 15, 11, 30));
    expect(p.parse('yarın 10 ile 11 arası görüşme').end, DateTime(2026, 10, 15, 11));
  });

  test('recurrence variants', () {
    expect(p.parse('her gün 08:00 ilaç').rrule, 'FREQ=DAILY');
    expect(p.parse('her gün 08:00 ilaç').start, DateTime(2026, 10, 15, 8));
    expect(p.parse('her hafta içi 07:30 servis').rrule, 'FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR');
    expect(p.parse('her ay 15:00 kira').rrule, 'FREQ=MONTHLY');
    expect(p.parse('her yıl 1 ocak yeni yıl').rrule, 'FREQ=YEARLY');
    expect(p.parse('her 2 haftada bir cuma 10:00 retro').rrule, 'FREQ=WEEKLY;INTERVAL=2;BYDAY=FR');
    final sabah = p.parse('her sabah koşu');
    expect(sabah.rrule, 'FREQ=DAILY');
    expect(sabah.start, DateTime(2026, 10, 15, 9));
    expect(sabah.title, 'Koşu');
  });

  test('reminder units and multiple reminders', () {
    final r = p.parse('yarın 09:00 uçuş 1 gün önce hatırlat 2 saat önce');
    expect(r.reminders, [120, 1440]);
    expect(r.title, 'Uçuş');
  });

  test('matched parts feed the preview chips', () {
    final r = p.parse('cuma 10-12 rehberlik semineri @konferans salonu 15 dk önce');
    expect(r.matched.map((m) => m.type).toSet(),
        {CapturePartType.date, CapturePartType.time, CapturePartType.location, CapturePartType.reminder});
  });

  test('Turkish capital İ is normalized', () {
    expect(p.parse('YARIN 15:00 İŞ GÖRÜŞMESİ').start, DateTime(2026, 10, 15, 15));
  });
}

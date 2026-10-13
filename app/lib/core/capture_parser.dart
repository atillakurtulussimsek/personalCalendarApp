/// Turkish natural-language parser for quick capture.
///
/// One line of text becomes either an event (when a date and/or time is
/// found) or a note. Recognised pieces:
///
/// * relative days: bugün, yarın, öbür gün, haftaya / gelecek / önümüzdeki `gün`
/// * weekdays with optional dative suffix: cuma, cumaya, pazartesiye …
/// * dates: 3 kasım, 3 kasım 2026, 03.11, 03.11.2026, 3/11
/// * times: 15:00, 15.00, saat 14.30, 15'te, 9'da, 10-12, 10:00-12:00,
///   sabah/öğlen/öğleden sonra/akşam/gece (+ optional hour)
/// * duration: 2 saat, 30 dk, 1,5 saat, 90 dakika
/// * reminder: 30 dk önce (hatırlat), 1 saat önce, 1 gün önce
/// * recurrence: her gün, her hafta, her `gün`, her ay, her yıl, her hafta içi,
///   her 2 haftada bir, her sabah
/// * location: @konferans salonu   (to end of line or until " - "/"," )
/// * all remaining words → title
library;

enum CaptureKind { event, note }

class CaptureResult {
  CaptureResult({
    required this.kind,
    required this.title,
    this.start,
    this.end,
    this.allDay = false,
    this.location = '',
    this.rrule,
    this.reminders = const [],
    this.body = '',
    this.matched = const [],
  });

  final CaptureKind kind;
  final String title;
  final DateTime? start; // local
  final DateTime? end; // local
  final bool allDay;
  final String location;
  final String? rrule;
  final List<int> reminders;
  final String body;

  /// Which parts of the input were consumed (for the preview chips).
  final List<CapturePart> matched;

  bool get isEvent => kind == CaptureKind.event;
}

enum CapturePartType { date, time, duration, reminder, repeat, location }

class CapturePart {
  CapturePart(this.type, this.text);
  final CapturePartType type;
  final String text;

  @override
  String toString() => '$type:$text';
}

class CaptureParser {
  CaptureParser({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  static const _weekdays = {
    'pazartesi': DateTime.monday,
    'salı': DateTime.tuesday,
    'çarşamba': DateTime.wednesday,
    'perşembe': DateTime.thursday,
    'cuma': DateTime.friday,
    'cumartesi': DateTime.saturday,
    'pazar': DateTime.sunday,
  };
  static const _weekdayAbbr = {
    DateTime.monday: 'MO',
    DateTime.tuesday: 'TU',
    DateTime.wednesday: 'WE',
    DateTime.thursday: 'TH',
    DateTime.friday: 'FR',
    DateTime.saturday: 'SA',
    DateTime.sunday: 'SU',
  };
  static const _months = {
    'ocak': 1, 'şubat': 2, 'mart': 3, 'nisan': 4, 'mayıs': 5, 'haziran': 6,
    'temmuz': 7, 'ağustos': 8, 'eylül': 9, 'ekim': 10, 'kasım': 11, 'aralık': 12,
  };
  static const _dayParts = {
    'sabah': 9,
    'öğlen': 12,
    'öğle': 12,
    'öğleden sonra': 14,
    'ikindi': 16,
    'akşam': 19,
    'akşamüstü': 18,
    'gece': 21,
  };

  static const _b0 = r'(?<![\p{L}\p{N}])'; // word start that understands Turkish letters (\b is ASCII-only)
  static const _b1 = r'(?![\p{L}\p{N}])';

  // longest alternatives first so "cumartesi" wins over "cuma"
  static final _weekdayRe = RegExp(
    "$_b0(pazartesi|cumartesi|çarşamba|perşembe|salı|cuma|pazar)(?:'?(?:ya|ye|yı|yi|a|e|ı|i))?$_b1",
    caseSensitive: false,
    unicode: true,
  );
  static final _nextWeekRe = RegExp('$_b0(haftaya|gelecek hafta|önümüzdeki hafta|gelecek|önümüzdeki)$_b1', caseSensitive: false, unicode: true);
  static final _relDayRe = RegExp('$_b0(bugün|yarın|öbür ?gün|yarından sonra|ertesi gün)$_b1', caseSensitive: false, unicode: true);
  static final _textDateRe = RegExp(
    "$_b0(\\d{1,2})\\s+(ocak|şubat|mart|nisan|mayıs|haziran|temmuz|ağustos|eylül|ekim|kasım|aralık)(?:'?(?:da|de|ta|te))?(?:\\s+(\\d{4}))?$_b1",
    caseSensitive: false,
    unicode: true,
  );
  static final _numDateRe = RegExp('$_b0(\\d{1,2})[./](\\d{1,2})(?:[./](\\d{4}|\\d{2}))?$_b1(?![:.]\\d)', unicode: true);
  static final _timeRangeRe = RegExp(
    "$_b0(?:saat\\s+)?(\\d{1,2})(?:[:.](\\d{2}))?\\s*(?:-|–|—|ile|den|dan|'den|'dan)\\s*(\\d{1,2})(?:[:.](\\d{2}))?(?:'?(?:ye|ya|e|a|kadar))?$_b1",
    caseSensitive: false,
    unicode: true,
  );
  static final _timeRe = RegExp(
    "$_b0(?:saat\\s+)?(\\d{1,2})(?:[:.](\\d{2}))(?:'?(?:da|de|ta|te))?$_b1",
    caseSensitive: false,
    unicode: true,
  );
  static final _bareHourRe = RegExp(
    "$_b0(?:saat\\s+(\\d{1,2})|(\\d{1,2})'(?:da|de|ta|te)|(\\d{1,2})(?:da|de|ta|te))$_b1",
    caseSensitive: false,
    unicode: true,
  );
  static final _dayPartRe = RegExp(
    '$_b0(öğleden sonra|akşamüstü|sabah|öğlen|öğle|ikindi|akşam|gece)(?:\\s+(\\d{1,2})(?:[:.](\\d{2}))?)?$_b1',
    caseSensitive: false,
    unicode: true,
  );
  static final _reminderRe = RegExp(
    '$_b0(\\d+)\\s*(dk|dakika|saat|gün)\\s+önce(?:\\s+(?:hatırlat|uyar|bildir))?(?:sın|sin)?$_b1',
    caseSensitive: false,
    unicode: true,
  );
  static final _durationRe = RegExp('$_b0(\\d+(?:[.,]\\d+)?)\\s*(dk|dakika|saat|sa)$_b1(?!\\s+önce)', caseSensitive: false, unicode: true);
  static final _repeatRe = RegExp(
    "${_b0}her\\s+(?:(\\d+)\\s+)?(gün|hafta içi|haftaiçi|hafta sonu|hafta|ay|yıl|sabah|akşam|pazartesi|cumartesi|çarşamba|perşembe|salı|cuma|pazar)(?:da bir|de bir|ta bir|te bir)?$_b1",
    caseSensitive: false,
    unicode: true,
  );
  static final _locationRe = RegExp(r'@\s*([^,@]+?)(?=\s+-\s|,|$)', unicode: true);

  CaptureResult parse(String input) {
    final now = _now();
    var text = ' ${_normalize(input)} ';
    final parts = <CapturePart>[];

    String consume(RegExpMatch m, CapturePartType type) {
      parts.add(CapturePart(type, m.group(0)!.trim()));
      text = '${text.substring(0, m.start)} ${text.substring(m.end)}';
      return m.group(0)!;
    }

    // --- reminder ------------------------------------------------------------
    final reminders = <int>[];
    for (final m in _reminderRe.allMatches(text).toList().reversed) {
      final n = int.parse(m.group(1)!);
      final unit = m.group(2)!.toLowerCase();
      reminders.add(unit.startsWith('d') ? n : (unit == 'saat' ? n * 60 : n * 1440));
      consume(m, CapturePartType.reminder);
    }
    reminders.sort();

    // --- location ------------------------------------------------------------
    var location = '';
    final loc = _locationRe.firstMatch(text);
    if (loc != null) {
      location = loc.group(1)!.trim();
      consume(loc, CapturePartType.location);
    }

    // --- recurrence ----------------------------------------------------------
    String? rrule;
    int? repeatWeekday;
    int? repeatHour;
    final rep = _repeatRe.firstMatch(text);
    if (rep != null) {
      final interval = int.tryParse(rep.group(1) ?? '');
      final unit = rep.group(2)!.toLowerCase();
      final iv = interval != null && interval > 1 ? ';INTERVAL=$interval' : '';
      switch (unit) {
        case 'gün':
          rrule = 'FREQ=DAILY$iv';
        case 'sabah':
          rrule = 'FREQ=DAILY';
          repeatHour = 9;
        case 'akşam':
          rrule = 'FREQ=DAILY';
          repeatHour = 19;
        case 'hafta':
          rrule = 'FREQ=WEEKLY$iv';
        case 'hafta içi':
        case 'haftaiçi':
          rrule = 'FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR';
        case 'hafta sonu':
          rrule = 'FREQ=WEEKLY;BYDAY=SA,SU';
        case 'ay':
          rrule = 'FREQ=MONTHLY$iv';
        case 'yıl':
          rrule = 'FREQ=YEARLY$iv';
        default:
          repeatWeekday = _weekdays[unit];
          if (repeatWeekday != null) rrule = 'FREQ=WEEKLY$iv;BYDAY=${_weekdayAbbr[repeatWeekday]}';
      }
      if (rrule != null) consume(rep, CapturePartType.repeat);
    }

    // --- date ----------------------------------------------------------------
    DateTime? day; // local midnight
    var nextWeek = false;
    var fromWeekday = false;
    final nw = _nextWeekRe.firstMatch(text);
    if (nw != null) {
      nextWeek = true;
      consume(nw, CapturePartType.date);
    }
    final td = _textDateRe.firstMatch(text);
    final nd = _numDateRe.firstMatch(text);
    final rd = _relDayRe.firstMatch(text);
    final wd = _weekdayRe.firstMatch(text);
    if (td != null) {
      final d = int.parse(td.group(1)!);
      final mo = _months[td.group(2)!.toLowerCase()]!;
      var y = int.tryParse(td.group(3) ?? '') ?? now.year;
      if (td.group(3) == null && DateTime(y, mo, d).isBefore(DateTime(now.year, now.month, now.day))) y++;
      day = DateTime(y, mo, d);
      consume(td, CapturePartType.date);
    } else if (nd != null) {
      final d = int.parse(nd.group(1)!);
      final mo = int.parse(nd.group(2)!);
      if (mo >= 1 && mo <= 12 && d >= 1 && d <= 31) {
        var y = int.tryParse(nd.group(3) ?? '') ?? now.year;
        if (y < 100) y += 2000;
        if (nd.group(3) == null && DateTime(y, mo, d).isBefore(DateTime(now.year, now.month, now.day))) y++;
        day = DateTime(y, mo, d);
        consume(nd, CapturePartType.date);
      }
    } else if (rd != null) {
      final w = rd.group(1)!.toLowerCase().replaceAll(' ', '');
      final today = DateTime(now.year, now.month, now.day);
      day = switch (w) {
        'bugün' => today,
        'yarın' => today.add(const Duration(days: 1)),
        _ => today.add(const Duration(days: 2)),
      };
      consume(rd, CapturePartType.date);
    } else if (wd != null) {
      final target = _weekdays[wd.group(1)!.toLowerCase()]!;
      fromWeekday = true;
      day = _nextWeekday(now, target, allowToday: true);
      if (rrule != null && rrule.startsWith('FREQ=WEEKLY') && !rrule.contains('BYDAY')) {
        rrule = '$rrule;BYDAY=${_weekdayAbbr[target]}';
      }
      if (nextWeek) {
        // "haftaya cuma": the Friday of next week
        final thisWeekMonday = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
        day = thisWeekMonday.add(Duration(days: 7 + target - 1));
      }
      consume(wd, CapturePartType.date);
    } else if (nextWeek) {
      day = DateTime(now.year, now.month, now.day).add(const Duration(days: 7));
    }

    // --- time ----------------------------------------------------------------
    int? startHour, startMin, endHour, endMin;
    int? dayPartHour;
    // ranges first so "öğleden sonra 2-4" is not split by the day-part matcher
    final tr = _timeRangeRe.firstMatch(text);
    final hasRange = tr != null && _plausibleHour(tr.group(1)) && _plausibleHour(tr.group(3));
    if (hasRange) {
      startHour = int.parse(tr.group(1)!);
      startMin = int.parse(tr.group(2) ?? '0');
      endHour = int.parse(tr.group(3)!);
      endMin = int.parse(tr.group(4) ?? '0');
      consume(tr, CapturePartType.time);
    }
    final dp = _dayPartRe.firstMatch(text);
    if (dp != null) {
      dayPartHour = _dayParts[dp.group(1)!.toLowerCase()];
      if (dp.group(2) != null && !hasRange) {
        startHour = _to24(int.parse(dp.group(2)!), dayPartHour!);
        startMin = int.parse(dp.group(3) ?? '0');
      }
      consume(dp, CapturePartType.time);
    }
    if (hasRange) {
      if (dayPartHour != null) {
        startHour = _to24(startHour!, dayPartHour);
        endHour = _to24(endHour!, dayPartHour);
      }
      if (endHour! < startHour!) endHour += 12; // "1-3" afternoon shorthand
    } else if (startHour == null) {
      final tm = _timeRe.firstMatch(text);
      final bh = _bareHourRe.firstMatch(text);
      if (tm != null && _plausibleHour(tm.group(1))) {
        startHour = int.parse(tm.group(1)!);
        startMin = int.parse(tm.group(2)!);
        if (dayPartHour != null) startHour = _to24(startHour, dayPartHour);
        consume(tm, CapturePartType.time);
      } else if (bh != null) {
        final h = bh.group(1) ?? bh.group(2) ?? bh.group(3);
        if (_plausibleHour(h)) {
          startHour = int.parse(h!);
          startMin = 0;
          if (dayPartHour != null) startHour = _to24(startHour, dayPartHour);
          consume(bh, CapturePartType.time);
        }
      }
    }
    if (startHour == null && dayPartHour != null) {
      startHour = dayPartHour;
      startMin = 0;
    }
    if (startHour == null && repeatHour != null) {
      startHour = repeatHour;
      startMin = 0;
    }

    // --- duration ------------------------------------------------------------
    Duration? duration;
    final du = _durationRe.firstMatch(text);
    if (du != null) {
      final n = double.parse(du.group(1)!.replaceAll(',', '.'));
      final unit = du.group(2)!.toLowerCase();
      duration = Duration(minutes: (unit.startsWith('d') ? n : n * 60).round());
      consume(du, CapturePartType.duration);
    }

    // --- decide ----------------------------------------------------------------
    final title = _cleanTitle(text);
    final hasDate = day != null;
    final hasTime = startHour != null;
    if (!hasDate && !hasTime && rrule == null) {
      final lines = input.trim().split('\n');
      return CaptureResult(
        kind: CaptureKind.note,
        title: lines.first.trim().length > 80 ? '' : lines.first.trim(),
        body: lines.length > 1 ? lines.skip(1).join('\n').trim() : (lines.first.trim().length > 80 ? input.trim() : ''),
        location: location,
        reminders: reminders,
        matched: parts,
      );
    }

    final today = DateTime(now.year, now.month, now.day);
    var base = day ?? today;
    if (repeatWeekday != null && day == null) base = _nextWeekday(now, repeatWeekday, allowToday: true);
    DateTime start;
    DateTime end;
    var allDay = false;
    if (hasTime) {
      start = DateTime(base.year, base.month, base.day, startHour, startMin ?? 0);
      if (day == null && !start.isAfter(now)) {
        // time only and already passed → tomorrow (or next weekday for recurring)
        start = repeatWeekday != null ? start.add(const Duration(days: 7)) : start.add(const Duration(days: 1));
      } else if (fromWeekday && !start.isAfter(now)) {
        // "çarşamba 09:00" said on a Wednesday afternoon → next Wednesday
        start = start.add(const Duration(days: 7));
      }
      if (endHour != null) {
        end = DateTime(start.year, start.month, start.day, endHour, endMin ?? 0);
        if (!end.isAfter(start)) end = end.add(const Duration(days: 1));
      } else {
        end = start.add(duration ?? const Duration(hours: 1));
      }
    } else {
      allDay = true;
      start = base;
      end = base.add(const Duration(days: 1));
    }

    return CaptureResult(
      kind: CaptureKind.event,
      title: title.isEmpty ? 'Etkinlik' : title,
      start: start,
      end: end,
      allDay: allDay,
      location: location,
      rrule: rrule,
      reminders: reminders,
      matched: parts,
    );
  }

  static bool _plausibleHour(String? s) {
    final h = int.tryParse(s ?? '');
    return h != null && h >= 0 && h <= 23;
  }

  static int _to24(int h, int dayPartHour) {
    if (h < 12 && dayPartHour >= 12) return h + 12;
    return h;
  }

  static DateTime _nextWeekday(DateTime now, int weekday, {required bool allowToday}) {
    final today = DateTime(now.year, now.month, now.day);
    var diff = (weekday - now.weekday) % 7;
    if (diff == 0 && !allowToday) diff = 7;
    return today.add(Duration(days: diff));
  }

  static String _normalize(String s) => s.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  static String _cleanTitle(String s) {
    var t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    t = t.replaceAll(RegExp(r'^[\-–,:]+|[\-–,:]+$'), '').trim();
    t = t.replaceAll(RegExp(r'\b(hatırlat|hatırlatıcı|ekle|etkinlik|kaydet)\b', caseSensitive: false), '').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.isEmpty) return t;
    return t[0].toUpperCase() + t.substring(1);
  }
}

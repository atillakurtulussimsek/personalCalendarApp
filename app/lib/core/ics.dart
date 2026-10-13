import 'dart:convert';

import 'tz.dart';

/// A minimal VEVENT read from an iCalendar feed.
class IcsEvent {
  IcsEvent({
    required this.uid,
    required this.summary,
    required this.start,
    required this.end,
    required this.allDay,
    this.description = '',
    this.location = '',
    this.rrule,
    this.timezone = 'UTC',
  });

  final String uid;
  final String summary;
  final DateTime start; // UTC
  final DateTime end; // UTC
  final bool allDay;
  final String description;
  final String location;
  final String? rrule;
  final String timezone;
}

/// Parses the subset of RFC 5545 needed for subscription calendars
/// (holiday feeds, Google/Apple public calendars): VEVENT with
/// DTSTART/DTEND/DURATION (DATE, UTC or TZID forms), SUMMARY, DESCRIPTION,
/// LOCATION, RRULE, UID. Line unfolding and text escapes are handled.
List<IcsEvent> parseIcs(String text) {
  final lines = _unfold(const LineSplitter().convert(text.replaceAll('\r\n', '\n')));
  final out = <IcsEvent>[];
  Map<String, _Prop>? cur;
  for (final line in lines) {
    if (line == 'BEGIN:VEVENT') {
      cur = {};
      continue;
    }
    if (line == 'END:VEVENT') {
      if (cur != null) {
        final e = _toEvent(cur);
        if (e != null) out.add(e);
      }
      cur = null;
      continue;
    }
    if (cur == null) continue;
    final idx = line.indexOf(':');
    if (idx <= 0) continue;
    final head = line.substring(0, idx);
    final value = line.substring(idx + 1);
    final parts = head.split(';');
    final name = parts.first.toUpperCase();
    final params = <String, String>{};
    for (final p in parts.skip(1)) {
      final eq = p.indexOf('=');
      if (eq > 0) params[p.substring(0, eq).toUpperCase()] = p.substring(eq + 1).replaceAll('"', '');
    }
    cur[name] = _Prop(value, params);
  }
  return out;
}

class _Prop {
  _Prop(this.value, this.params);
  final String value;
  final Map<String, String> params;
}

List<String> _unfold(List<String> raw) {
  final out = <String>[];
  for (final l in raw) {
    if ((l.startsWith(' ') || l.startsWith('\t')) && out.isNotEmpty) {
      out[out.length - 1] = out.last + l.substring(1);
    } else {
      out.add(l);
    }
  }
  return out;
}

String _unescape(String s) =>
    s.replaceAll(r'\n', '\n').replaceAll(r'\N', '\n').replaceAll(r'\,', ',').replaceAll(r'\;', ';').replaceAll(r'\\', r'\');

/// Returns (utc instant, isDate, zone).
(DateTime, bool, String)? _parseDate(_Prop? p) {
  if (p == null) return null;
  final v = p.value.trim();
  final isDate = p.params['VALUE'] == 'DATE' || (v.length == 8 && !v.contains('T'));
  final m = RegExp(r'^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})?(Z)?)?$').firstMatch(v);
  if (m == null) return null;
  final y = int.parse(m[1]!), mo = int.parse(m[2]!), d = int.parse(m[3]!);
  if (isDate) return (DateTime.utc(y, mo, d), true, 'UTC');
  final h = int.parse(m[4] ?? '0'), mi = int.parse(m[5] ?? '0'), s = int.parse(m[6] ?? '0');
  if (m[7] == 'Z') return (DateTime.utc(y, mo, d, h, mi, s), false, 'UTC');
  final zone = p.params['TZID'] ?? Tz.local;
  final wall = DateTime.utc(y, mo, d, h, mi, s);
  return (Tz.fromWall(wall, Tz.isValid(zone) ? zone : Tz.local), false, Tz.isValid(zone) ? zone : Tz.local);
}

Duration? _parseDuration(String? v) {
  if (v == null) return null;
  final m = RegExp(r'^(-)?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$').firstMatch(v.trim());
  if (m == null) return null;
  final d = Duration(
    days: int.parse(m[2] ?? '0') * 7 + int.parse(m[3] ?? '0'),
    hours: int.parse(m[4] ?? '0'),
    minutes: int.parse(m[5] ?? '0'),
    seconds: int.parse(m[6] ?? '0'),
  );
  return m[1] == '-' ? -d : d;
}

IcsEvent? _toEvent(Map<String, _Prop> p) {
  final start = _parseDate(p['DTSTART']);
  if (start == null) return null;
  final (st, isDate, zone) = start;
  var en = _parseDate(p['DTEND'])?.$1;
  final dur = _parseDuration(p['DURATION']?.value);
  en ??= dur != null ? st.add(dur) : (isDate ? st.add(const Duration(days: 1)) : st.add(const Duration(hours: 1)));
  var rrule = p['RRULE']?.value;
  if (rrule != null && rrule.trim().isEmpty) rrule = null;
  return IcsEvent(
    uid: p['UID']?.value ?? '${st.toIso8601String()}-${p['SUMMARY']?.value ?? ''}',
    summary: _unescape(p['SUMMARY']?.value ?? ''),
    description: _unescape(p['DESCRIPTION']?.value ?? ''),
    location: _unescape(p['LOCATION']?.value ?? ''),
    start: st,
    end: en,
    allDay: isDate,
    rrule: rrule,
    timezone: zone,
  );
}

// --- writer ------------------------------------------------------------------

String _icsTime(DateTime d) {
  final u = d.toUtc();
  String p(int n) => n.toString().padLeft(2, '0');
  return '${u.year}${p(u.month)}${p(u.day)}T${p(u.hour)}${p(u.minute)}${p(u.second)}Z';
}

String _icsDate(DateTime d) {
  final u = d.toUtc();
  String p(int n) => n.toString().padLeft(2, '0');
  return '${u.year}${p(u.month)}${p(u.day)}';
}

String _escape(String s) => s.replaceAll(r'\', r'\\').replaceAll(';', r'\;').replaceAll(',', r'\,').replaceAll('\n', r'\n');

String _fold(String line) {
  final units = utf8.encode(line);
  if (units.length <= 75) return '$line\r\n';
  final out = StringBuffer();
  var start = 0;
  var first = true;
  while (start < units.length) {
    var end = start + (first ? 75 : 74);
    if (end > units.length) end = units.length;
    while (end < units.length && end > start && (units[end] & 0xC0) == 0x80) {
      end--;
    }
    out.write(first ? '' : ' ');
    out.write(utf8.decode(units.sublist(start, end)));
    out.write('\r\n');
    start = end;
    first = false;
  }
  return out.toString();
}

/// Serialises events (drift rows) as an iCalendar document.
String writeIcs(Iterable<IcsEvent> events) {
  final b = StringBuffer('BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Personal Calendar//TR\r\nCALSCALE:GREGORIAN\r\n');
  for (final e in events) {
    b.write('BEGIN:VEVENT\r\n');
    b.write(_fold('UID:${e.uid}'));
    b.write(_fold('DTSTAMP:${_icsTime(DateTime.now())}'));
    if (e.allDay) {
      b.write(_fold('DTSTART;VALUE=DATE:${_icsDate(e.start)}'));
      b.write(_fold('DTEND;VALUE=DATE:${_icsDate(e.end)}'));
    } else {
      b.write(_fold('DTSTART:${_icsTime(e.start)}'));
      b.write(_fold('DTEND:${_icsTime(e.end)}'));
    }
    b.write(_fold('SUMMARY:${_escape(e.summary)}'));
    if (e.description.isNotEmpty) b.write(_fold('DESCRIPTION:${_escape(e.description)}'));
    if (e.location.isNotEmpty) b.write(_fold('LOCATION:${_escape(e.location)}'));
    if (e.rrule != null) b.write(_fold('RRULE:${e.rrule}'));
    b.write('END:VEVENT\r\n');
  }
  b.write('END:VCALENDAR\r\n');
  return b.toString();
}

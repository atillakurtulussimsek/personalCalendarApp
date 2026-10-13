import 'package:rrule/rrule.dart';

import '../data/db/database.dart';
import 'tz.dart';

/// One concrete instance of an event in a time range.
class Occurrence {
  Occurrence({
    required this.event,
    required this.start,
    required this.end,
    required this.seriesId,
    this.isException = false,
  });

  /// The row this instance comes from (master for generated instances, the
  /// exception row for exceptions, the event itself for single events).
  final Event event;
  final DateTime start;
  final DateTime end;
  final String seriesId;
  final bool isException;

  bool get isRecurring => event.rrule != null || isException;

  /// The occurrence this instance represents in the master series (= [start]
  /// for generated instances, `originalStart` for exceptions).
  DateTime get originalStart => isException ? (event.originalStart ?? start) : start;

  String get title => event.title;
  String get calendarId => event.calendarId;
  bool get allDay => event.allDay;
}

const maxOccurrencesPerSeries = 1000;

/// Parses an RRULE string (with or without the `RRULE:` prefix). Returns null on error.
RecurrenceRule? parseRrule(String? s) {
  if (s == null || s.trim().isEmpty) return null;
  try {
    final body = s.trim().startsWith('RRULE:') ? s.trim() : 'RRULE:${s.trim()}';
    return RecurrenceRule.fromString(body);
  } catch (_) {
    return null;
  }
}

String rruleToString(RecurrenceRule r) => r.toString().replaceFirst('RRULE:', '');

/// Expands [events] (masters, singles and exception rows) into the occurrences
/// overlapping [from, to), mirroring the server algorithm:
///
/// * recurrence is evaluated in the event's own IANA zone, so local wall time
///   is preserved across DST changes;
/// * exception rows replace the instance at their `originalStart`;
///   a deleted exception cancels that instance;
/// * tombstones are skipped.
List<Occurrence> expandEvents(Iterable<Event> events, DateTime from, DateTime to) {
  from = from.toUtc();
  to = to.toUtc();
  final exceptions = <String, Map<DateTime, Event>>{};
  for (final e in events) {
    if (e.recurrenceId != null && e.originalStart != null) {
      exceptions.putIfAbsent(e.recurrenceId!, () => {})[e.originalStart!.toUtc()] = e;
    }
  }
  final out = <Occurrence>[];
  final placedExceptions = <String>{};

  for (final e in events) {
    if (e.deletedAt != null || e.recurrenceId != null) continue;
    if (e.rrule == null) {
      if (e.startAt.isBefore(to) && e.endAt.isAfter(from)) {
        out.add(Occurrence(event: e, start: e.startAt.toUtc(), end: e.endAt.toUtc(), seriesId: e.id));
      }
      continue;
    }
    final rule = parseRrule(e.rrule);
    if (rule == null) continue;
    final dur = e.endAt.difference(e.startAt);
    final zone = e.timezone;
    final wallStart = Tz.toWall(e.startAt, zone);
    // widen the window by the duration so instances that started earlier but overlap are found
    var wallAfter = Tz.toWall(from.subtract(dur), zone);
    if (wallAfter.isBefore(wallStart)) wallAfter = wallStart;
    final wallBefore = Tz.toWall(to, zone);
    final exFor = exceptions[e.id] ?? const {};
    var n = 0;
    for (final wall in rule.getInstances(start: wallStart, after: wallAfter, includeAfter: true, before: wallBefore)) {
      if (n++ >= maxOccurrencesPerSeries) break;
      final st = Tz.fromWall(wall, zone);
      final en = st.add(dur);
      if (!st.isBefore(to) || !en.isAfter(from)) continue;
      final ex = exFor[st];
      if (ex != null) {
        placedExceptions.add(ex.id);
        if (ex.deletedAt != null) continue;
        if (ex.startAt.isBefore(to) && ex.endAt.isAfter(from)) {
          out.add(Occurrence(event: ex, start: ex.startAt.toUtc(), end: ex.endAt.toUtc(), seriesId: e.id, isException: true));
        }
        continue;
      }
      out.add(Occurrence(event: e, start: st, end: en, seriesId: e.id));
    }
  }
  // exceptions moved into the window from an instance outside it
  for (final e in events) {
    if (e.recurrenceId == null || e.deletedAt != null || placedExceptions.contains(e.id)) continue;
    if (e.startAt.isBefore(to) && e.endAt.isAfter(from)) {
      out.add(Occurrence(event: e, start: e.startAt.toUtc(), end: e.endAt.toUtc(), seriesId: e.recurrenceId!, isException: true));
    }
  }
  out.sort((a, b) => a.start.compareTo(b.start));
  return out;
}

/// Human-readable Turkish description of a rule (for chips and the editor).
String describeRrule(String? s) {
  final r = parseRrule(s);
  if (r == null) return '';
  const dayNames = {
    DateTime.monday: 'Pzt',
    DateTime.tuesday: 'Sal',
    DateTime.wednesday: 'Çar',
    DateTime.thursday: 'Per',
    DateTime.friday: 'Cum',
    DateTime.saturday: 'Cmt',
    DateTime.sunday: 'Paz',
  };
  final i = r.interval ?? 1;
  String base;
  switch (r.frequency) {
    case Frequency.daily:
      base = i == 1 ? 'Her gün' : 'Her $i günde bir';
    case Frequency.weekly:
      base = i == 1 ? 'Her hafta' : 'Her $i haftada bir';
      if (r.byWeekDays.isNotEmpty) {
        base += ': ${r.byWeekDays.map((d) => dayNames[d.day]).join(', ')}';
      }
    case Frequency.monthly:
      base = i == 1 ? 'Her ay' : 'Her $i ayda bir';
      if (r.byMonthDays.isNotEmpty) base += ' (${r.byMonthDays.join(', ')}. gün)';
    case Frequency.yearly:
      base = i == 1 ? 'Her yıl' : 'Her $i yılda bir';
    default:
      base = r.frequency.toString();
  }
  if (r.count != null) base += ', ${r.count} kez';
  if (r.until != null) {
    final u = r.until!;
    base += ', ${u.day}.${u.month}.${u.year} tarihine kadar';
  }
  return base;
}

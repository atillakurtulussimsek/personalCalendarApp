import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:rrule/rrule.dart';
import 'package:uuid/uuid.dart';

import '../../core/ics.dart';
import '../../core/recurrence.dart';
import '../../core/tz.dart';
import '../db/database.dart';
import '../sync/mappers.dart';
import '../sync/sync_service.dart';

const _uuid = Uuid();

/// Base for local-first repositories: write locally, enqueue to outbox, nudge sync.
abstract class LocalRepository {
  LocalRepository(this.db, this.sync);
  final AppDatabase db;
  final SyncService sync;

  DateTime now() => DateTime.now().toUtc();
  String newId() => _uuid.v4();

  Future<void> enqueue(String entity, String op, String id, int baseVersion, DateTime at, [Map<String, dynamic>? data]) async {
    await db.enqueue(entity: entity, op: op, recordId: id, baseVersion: baseVersion, updatedAt: at, data: data);
    sync.scheduleSoon();
  }
}

class CalendarRepository extends LocalRepository {
  CalendarRepository(super.db, super.sync);

  Stream<List<Calendar>> watchAll() => (db.select(db.calendars)
        ..where((t) => t.deletedAt.isNull())
        ..orderBy([(t) => OrderingTerm.desc(t.isDefault), (t) => OrderingTerm.asc(t.source), (t) => OrderingTerm.asc(t.name)]))
      .watch();

  Future<Calendar?> get(String id) => (db.select(db.calendars)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<Calendar?> getDefault() async {
    final all = await (db.select(db.calendars)..where((t) => t.deletedAt.isNull() & t.source.equals('local'))).get();
    if (all.isEmpty) return null;
    return all.firstWhere((c) => c.isDefault, orElse: () => all.first);
  }

  /// Creates a local default calendar when the device has none yet (first offline use).
  Future<Calendar> ensureDefault() async {
    final existing = await getDefault();
    if (existing != null) return existing;
    return create(name: 'Takvim', isDefault: true);
  }

  Future<Calendar> create({required String name, String color = '#3B82F6', bool isDefault = false}) async {
    final t = now();
    final c = Calendar(
      id: newId(), name: name.trim(), color: color, isDefault: isDefault, visible: true, source: 'local',
      createdAt: t, updatedAt: t, version: 0, serverSeq: 0,
    );
    await db.transaction(() async {
      if (isDefault) await _clearDefault(c.id);
      await db.into(db.calendars).insert(c);
    });
    await enqueue('calendar', 'upsert', c.id, 0, t, calendarToPushData(c));
    return c;
  }

  Future<void> _clearDefault(String exceptId) => (db.update(db.calendars)..where((t) => t.id.equals(exceptId).not()))
      .write(const CalendarsCompanion(isDefault: Value(false)));

  Future<void> save(Calendar c) async {
    final t = now();
    final updated = c.copyWith(updatedAt: t, name: c.name.trim());
    await db.transaction(() async {
      if (updated.isDefault) await _clearDefault(c.id);
      await db.update(db.calendars).replace(updated);
    });
    if (c.source == 'local') await enqueue('calendar', 'upsert', c.id, c.version, t, calendarToPushData(updated));
  }

  Future<void> setVisible(String id, bool visible) =>
      (db.update(db.calendars)..where((t) => t.id.equals(id))).write(CalendarsCompanion(visible: Value(visible)));

  /// Soft-deletes a local calendar (and its events locally; the server does the same).
  Future<void> remove(String id) async {
    final c = await get(id);
    if (c == null) return;
    final t = now();
    if (c.source == 'ics') {
      await db.transaction(() async {
        await (db.delete(db.events)..where((e) => e.calendarId.equals(id))).go();
        await (db.delete(db.calendars)..where((x) => x.id.equals(id))).go();
      });
      return;
    }
    await db.transaction(() async {
      await (db.update(db.calendars)..where((x) => x.id.equals(id)))
          .write(CalendarsCompanion(deletedAt: Value(t), updatedAt: Value(t), isDefault: const Value(false)));
      await (db.update(db.events)..where((e) => e.calendarId.equals(id) & e.deletedAt.isNull()))
          .write(EventsCompanion(deletedAt: Value(t), updatedAt: Value(t)));
    });
    await enqueue('calendar', 'delete', id, c.version, t);
  }

  // --- ICS subscriptions (device-local, read-only) -------------------------

  Future<Calendar> subscribe({required String name, required String url, String color = '#EF4444'}) async {
    final t = now();
    final c = Calendar(
      id: newId(), name: name.trim(), color: color, isDefault: false, visible: true, source: 'ics', icsUrl: url.trim(),
      createdAt: t, updatedAt: t, version: 0, serverSeq: 0,
    );
    await db.into(db.calendars).insert(c);
    return c;
  }

  /// Replaces the events of a subscription with the parsed feed contents.
  Future<int> applyFeed(Calendar sub, String icsText) async {
    final events = parseIcs(icsText);
    final t = now();
    await db.transaction(() async {
      await (db.delete(db.events)..where((e) => e.calendarId.equals(sub.id))).go();
      for (final e in events) {
        await db.into(db.events).insert(Event(
          id: _uuid.v5(Namespace.url.value, '${sub.id}/${e.uid}'),
          calendarId: sub.id,
          title: e.summary,
          description: e.description,
          location: e.location,
          startAt: e.start,
          endAt: e.end,
          timezone: e.timezone,
          allDay: e.allDay,
          rrule: e.rrule,
          reminders: '[]',
          createdAt: t,
          updatedAt: t,
          version: 0,
          serverSeq: 0,
        ));
      }
      await (db.update(db.calendars)..where((x) => x.id.equals(sub.id))).write(CalendarsCompanion(lastFetchedAt: Value(t)));
    });
    return events.length;
  }
}

/// Which instances of a recurring series an edit/delete applies to.
enum EditScope { onlyThis, thisAndFollowing, all }

class EventRepository extends LocalRepository {
  EventRepository(super.db, super.sync);

  /// Live rows relevant to [from, to): singles overlapping, recurring masters
  /// starting before `to`, and exception rows of those masters.
  Stream<List<Event>> watchRange(DateTime from, DateTime to) => (db.select(db.events)
        ..where((t) =>
            t.deletedAt.isNull() & t.startAt.isSmallerThanValue(to.toUtc()) & (t.endAt.isBiggerThanValue(from.toUtc()) | t.rrule.isNotNull()))
        ..orderBy([(t) => OrderingTerm.asc(t.startAt)]))
      .watch()
      .asyncMap((rows) async {
        final seriesIds = rows.where((e) => e.rrule != null).map((e) => e.id).toList();
        if (seriesIds.isEmpty) return rows;
        // exceptions (including deleted ones, which cancel instances)
        final ex = await (db.select(db.events)..where((t) => t.recurrenceId.isIn(seriesIds))).get();
        final ids = rows.map((e) => e.id).toSet();
        return [...rows, ...ex.where((e) => !ids.contains(e.id))];
      });

  /// Expanded occurrences in [from, to), filtered by calendar visibility.
  Stream<List<Occurrence>> watchOccurrences(DateTime from, DateTime to) => watchRange(from, to).map((rows) => expandEvents(rows, from, to));

  Future<Event?> get(String id) => (db.select(db.events)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<Event> create({
    required String calendarId,
    required String title,
    required DateTime startAt,
    required DateTime endAt,
    String? timezone,
    String description = '',
    String location = '',
    bool allDay = false,
    String? rrule,
    List<int> reminders = const [],
    String? recurrenceId,
    DateTime? originalStart,
  }) async {
    final t = now();
    final e = Event(
      id: newId(),
      calendarId: calendarId,
      title: title.trim(),
      description: description,
      location: location,
      startAt: startAt.toUtc(),
      endAt: endAt.toUtc(),
      timezone: timezone ?? Tz.local,
      allDay: allDay,
      rrule: rrule,
      recurrenceId: recurrenceId,
      originalStart: originalStart?.toUtc(),
      reminders: jsonEncode(reminders),
      createdAt: t,
      updatedAt: t,
      version: 0,
      serverSeq: 0,
    );
    await db.into(db.events).insert(e);
    await enqueue('event', 'upsert', e.id, 0, t, eventToPushData(e));
    return e;
  }

  Future<Event> save(Event e) async {
    final t = now();
    final updated = e.copyWith(updatedAt: t, title: e.title.trim());
    await db.update(db.events).replace(updated);
    await enqueue('event', 'upsert', e.id, e.version, t, eventToPushData(updated));
    return updated;
  }

  Future<void> remove(String id) async {
    final e = await get(id);
    if (e == null) return;
    final t = now();
    await db.transaction(() async {
      await (db.update(db.events)..where((x) => x.id.equals(id))).write(EventsCompanion(deletedAt: Value(t), updatedAt: Value(t)));
      if (e.rrule != null) {
        // the server deletes exceptions of a deleted master too; mirror it locally
        await (db.update(db.events)..where((x) => x.recurrenceId.equals(id) & x.deletedAt.isNull()))
            .write(EventsCompanion(deletedAt: Value(t), updatedAt: Value(t)));
      }
    });
    await enqueue('event', 'delete', id, e.version, t);
  }

  // --- recurring series edits ---------------------------------------------

  /// Applies [changes] to the occurrence [occ] according to [scope].
  /// [changes] receives the row to edit (a copy) and returns the edited row;
  /// for `onlyThis` the time fields of the returned row are used for the exception.
  Future<void> editOccurrence(Occurrence occ, EditScope scope, Event Function(Event base) changes) async {
    final master = occ.isException ? (await get(occ.seriesId)) : occ.event;
    if (master == null) return;
    switch (scope) {
      case EditScope.all:
        // keep the series anchored: shift start/end by the delta the user applied to this instance
        final edited = changes(occ.event.copyWith(startAt: occ.start, endAt: occ.end));
        final delta = edited.startAt.difference(occ.start);
        final dur = edited.endAt.difference(edited.startAt);
        final newStart = master.startAt.add(delta);
        await save(master.copyWith(
          title: edited.title,
          description: edited.description,
          location: edited.location,
          calendarId: edited.calendarId,
          allDay: edited.allDay,
          reminders: edited.reminders,
          rrule: Value(edited.rrule),
          startAt: newStart,
          endAt: newStart.add(dur),
        ));
      case EditScope.onlyThis:
        if (occ.isException) {
          await save(changes(occ.event));
        } else {
          final edited = changes(occ.event.copyWith(startAt: occ.start, endAt: occ.end));
          await create(
            calendarId: edited.calendarId,
            title: edited.title,
            description: edited.description,
            location: edited.location,
            startAt: edited.startAt,
            endAt: edited.endAt,
            timezone: master.timezone,
            allDay: edited.allDay,
            reminders: eventReminders(edited),
            recurrenceId: master.id,
            originalStart: occ.originalStart,
          );
        }
      case EditScope.thisAndFollowing:
        await _splitSeries(master, occ, changes);
    }
  }

  /// Ends [master] before [occ] and starts a new series from the edited instance.
  Future<void> _splitSeries(Event master, Occurrence occ, Event Function(Event base) changes) async {
    final rule = parseRrule(master.rrule);
    if (rule == null) return;
    final edited = changes(occ.event.copyWith(startAt: occ.start, endAt: occ.end));
    final cut = occ.originalStart;
    if (cut.isAfter(master.startAt)) {
      // UNTIL is inclusive: last allowed instance is the one before `cut` (wall time in the series zone)
      final untilWall = Tz.toWall(cut.subtract(const Duration(seconds: 1)), master.timezone);
      final truncated = RecurrenceRule(
        frequency: rule.frequency,
        interval: rule.interval,
        until: untilWall,
        byWeekDays: rule.byWeekDays,
        byMonthDays: rule.byMonthDays,
        byMonths: rule.byMonths,
        bySetPositions: rule.bySetPositions,
        weekStart: rule.weekStart,
      );
      await save(master.copyWith(rrule: Value(rruleToString(truncated))));
      // exceptions at or after the cut now belong to nobody: drop them
      final later = await (db.select(db.events)
            ..where((t) => t.recurrenceId.equals(master.id) & t.originalStart.isBiggerOrEqualValue(cut) & t.deletedAt.isNull()))
          .get();
      for (final ex in later) {
        await remove(ex.id);
      }
      final dur = edited.endAt.difference(edited.startAt);
      await create(
        calendarId: edited.calendarId,
        title: edited.title,
        description: edited.description,
        location: edited.location,
        startAt: edited.startAt,
        endAt: edited.startAt.add(dur),
        timezone: master.timezone,
        allDay: edited.allDay,
        rrule: edited.rrule == null ? null : _withoutCount(edited.rrule!, rule, master, cut),
        reminders: eventReminders(edited),
      );
    } else {
      // editing from the first instance = editing the whole series
      await editOccurrence(occ, EditScope.all, changes);
    }
  }

  /// COUNT on the original series must be reduced by the instances already consumed.
  String _withoutCount(String newRule, RecurrenceRule original, Event master, DateTime cut) {
    final r = parseRrule(newRule);
    if (r == null || r.count == null) return newRule;
    final used = original
        .getInstances(start: Tz.toWall(master.startAt, master.timezone), before: Tz.toWall(cut, master.timezone))
        .length;
    final remaining = r.count! - used;
    if (remaining <= 0) return newRule;
    return rruleToString(RecurrenceRule(
      frequency: r.frequency,
      interval: r.interval,
      count: remaining,
      byWeekDays: r.byWeekDays,
      byMonthDays: r.byMonthDays,
      byMonths: r.byMonths,
      bySetPositions: r.bySetPositions,
      weekStart: r.weekStart,
    ));
  }

  Future<void> deleteOccurrence(Occurrence occ, EditScope scope) async {
    switch (scope) {
      case EditScope.all:
        await remove(occ.seriesId);
      case EditScope.onlyThis:
        if (occ.isException) {
          await remove(occ.event.id);
        } else {
          // a deleted exception row = cancelled instance
          final ex = await create(
            calendarId: occ.event.calendarId,
            title: occ.event.title,
            startAt: occ.start,
            endAt: occ.end,
            timezone: occ.event.timezone,
            recurrenceId: occ.seriesId,
            originalStart: occ.originalStart,
          );
          await remove(ex.id);
        }
      case EditScope.thisAndFollowing:
        final master = await get(occ.seriesId);
        if (master == null) return;
        if (!occ.originalStart.isAfter(master.startAt)) {
          await remove(master.id);
          return;
        }
        final rule = parseRrule(master.rrule);
        if (rule == null) return;
        final untilWall = Tz.toWall(occ.originalStart.subtract(const Duration(seconds: 1)), master.timezone);
        await save(master.copyWith(
            rrule: Value(rruleToString(RecurrenceRule(
          frequency: rule.frequency,
          interval: rule.interval,
          until: untilWall,
          byWeekDays: rule.byWeekDays,
          byMonthDays: rule.byMonthDays,
          byMonths: rule.byMonths,
          bySetPositions: rule.bySetPositions,
          weekStart: rule.weekStart,
        )))));
        final later = await (db.select(db.events)
              ..where((t) => t.recurrenceId.equals(master.id) & t.originalStart.isBiggerOrEqualValue(occ.originalStart) & t.deletedAt.isNull()))
            .get();
        for (final ex in later) {
          await remove(ex.id);
        }
    }
  }

  /// Moves an occurrence by [delta] and/or changes its duration (drag & drop).
  Future<void> moveOccurrence(Occurrence occ, {Duration delta = Duration.zero, Duration? newDuration, EditScope scope = EditScope.onlyThis}) {
    return editOccurrence(occ, occ.isRecurring ? scope : EditScope.all, (base) {
      final start = base.startAt.add(delta);
      final end = newDuration != null ? start.add(newDuration) : base.endAt.add(delta);
      return base.copyWith(startAt: start, endAt: end);
    });
  }
}

class NoteRepository extends LocalRepository {
  NoteRepository(super.db, super.sync);

  Stream<List<Note>> watchAll() => (db.select(db.notes)
        ..where((t) => t.deletedAt.isNull())
        ..orderBy([(t) => OrderingTerm.desc(t.pinned), (t) => OrderingTerm.desc(t.updatedAt)]))
      .watch();

  Stream<List<Note>> watchByEvent(String eventId) =>
      (db.select(db.notes)..where((t) => t.deletedAt.isNull() & t.eventId.equals(eventId))).watch();

  Future<List<Note>> search(String query) => db.searchNotes(query);

  Future<Note?> get(String id) => (db.select(db.notes)..where((t) => t.id.equals(id))).getSingleOrNull();

  Stream<Note?> watch(String id) => (db.select(db.notes)..where((t) => t.id.equals(id))).watchSingleOrNull();

  static List<String> normalizeTags(Iterable<String> tags) {
    final seen = <String>{};
    for (final raw in tags) {
      final t = raw.trim().replaceFirst(RegExp(r'^#'), '').toLowerCase();
      if (t.isNotEmpty) seen.add(t);
    }
    return seen.toList();
  }

  Future<Note> create({String title = '', String body = '', List<String> tags = const [], String? eventId, bool pinned = false}) async {
    final t = now();
    final n = Note(
      id: newId(),
      title: title.trim(),
      body: body,
      pinned: pinned,
      eventId: eventId,
      tags: jsonEncode(normalizeTags(tags)),
      createdAt: t,
      updatedAt: t,
      version: 0,
      serverSeq: 0,
    );
    await db.into(db.notes).insert(n);
    await enqueue('note', 'upsert', n.id, 0, t, noteToPushData(n));
    return n;
  }

  Future<void> save(Note n) async {
    final t = now();
    final updated = n.copyWith(updatedAt: t, title: n.title.trim(), tags: jsonEncode(normalizeTags(noteTags(n))));
    await db.update(db.notes).replace(updated);
    await enqueue('note', 'upsert', n.id, n.version, t, noteToPushData(updated));
  }

  Future<void> remove(String id) async {
    final n = await get(id);
    if (n == null) return;
    final t = now();
    await (db.update(db.notes)..where((x) => x.id.equals(id))).write(NotesCompanion(deletedAt: Value(t), updatedAt: Value(t)));
    await enqueue('note', 'delete', id, n.version, t);
  }
}

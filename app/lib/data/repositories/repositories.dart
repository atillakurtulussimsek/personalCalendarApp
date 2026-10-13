import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

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
        ..orderBy([(t) => OrderingTerm.desc(t.isDefault), (t) => OrderingTerm.asc(t.name)]))
      .watch();

  Future<Calendar?> getDefault() async {
    final all = await (db.select(db.calendars)..where((t) => t.deletedAt.isNull())).get();
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
        id: newId(), name: name, color: color, isDefault: isDefault, visible: true, createdAt: t, updatedAt: t, version: 0, serverSeq: 0);
    await db.into(db.calendars).insert(c);
    await enqueue('calendar', 'upsert', c.id, 0, t, calendarToPushData(c));
    return c;
  }

  Future<void> setVisible(String id, bool visible) =>
      (db.update(db.calendars)..where((t) => t.id.equals(id))).write(CalendarsCompanion(visible: Value(visible)));
}

class EventRepository extends LocalRepository {
  EventRepository(super.db, super.sync);

  /// Live events overlapping [from, to) (recurring masters included when they start before `to`).
  Stream<List<Event>> watchRange(DateTime from, DateTime to) => (db.select(db.events)
        ..where((t) =>
            t.deletedAt.isNull() &
            t.startAt.isSmallerThanValue(to.toUtc()) &
            (t.endAt.isBiggerThanValue(from.toUtc()) | t.rrule.isNotNull()))
        ..orderBy([(t) => OrderingTerm.asc(t.startAt)]))
      .watch();

  Future<Event?> get(String id) => (db.select(db.events)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<Event> create({
    required String calendarId,
    required String title,
    required DateTime startAt,
    required DateTime endAt,
    required String timezone,
    String description = '',
    String location = '',
    bool allDay = false,
    String? rrule,
    List<int> reminders = const [],
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
      timezone: timezone,
      allDay: allDay,
      rrule: rrule,
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

  Future<void> save(Event e) async {
    final t = now();
    final updated = e.copyWith(updatedAt: t, title: e.title.trim());
    await db.update(db.events).replace(updated);
    await enqueue('event', 'upsert', e.id, e.version, t, eventToPushData(updated));
  }

  Future<void> remove(String id) async {
    final e = await get(id);
    if (e == null) return;
    final t = now();
    await (db.update(db.events)..where((x) => x.id.equals(id))).write(EventsCompanion(deletedAt: Value(t), updatedAt: Value(t)));
    await enqueue('event', 'delete', id, e.version, t);
  }
}

class NoteRepository extends LocalRepository {
  NoteRepository(super.db, super.sync);

  Stream<List<Note>> watchAll() => (db.select(db.notes)
        ..where((t) => t.deletedAt.isNull())
        ..orderBy([(t) => OrderingTerm.desc(t.pinned), (t) => OrderingTerm.desc(t.updatedAt)]))
      .watch();

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

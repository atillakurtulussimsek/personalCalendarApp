import 'dart:convert';

import 'package:drift/drift.dart';

import '../db/database.dart';

/// JSON <-> drift conversions for the sync protocol. Server JSON uses
/// snake_case and RFC 3339 UTC timestamps.

DateTime _dt(dynamic v) => DateTime.parse(v as String).toUtc();
DateTime? _dtn(dynamic v) => v == null ? null : _dt(v);
String _iso(DateTime d) => d.toUtc().toIso8601String();
String? _ison(DateTime? d) => d == null ? null : _iso(d);

// --- calendars --------------------------------------------------------------

CalendarsCompanion calendarFromJson(Map<String, dynamic> j, {bool? visible}) => CalendarsCompanion(
      id: Value(j['id'] as String),
      name: Value(j['name'] as String),
      color: Value(j['color'] as String? ?? '#3B82F6'),
      isDefault: Value(j['is_default'] as bool? ?? false),
      visible: visible == null ? const Value.absent() : Value(visible),
      source: const Value('local'),
      createdAt: Value(_dt(j['created_at'])),
      updatedAt: Value(_dt(j['updated_at'])),
      deletedAt: Value(_dtn(j['deleted_at'])),
      version: Value((j['version'] as num?)?.toInt() ?? 0),
      serverSeq: Value((j['server_seq'] as num?)?.toInt() ?? 0),
    );

/// The payload sent in a push item (server-managed fields omitted).
Map<String, dynamic> calendarToPushData(Calendar c) => {
      'name': c.name,
      'color': c.color,
      'is_default': c.isDefault,
      'created_at': _iso(c.createdAt),
    };

// --- events -----------------------------------------------------------------

EventsCompanion eventFromJson(Map<String, dynamic> j) => EventsCompanion(
      id: Value(j['id'] as String),
      calendarId: Value(j['calendar_id'] as String),
      title: Value(j['title'] as String),
      description: Value(j['description'] as String? ?? ''),
      location: Value(j['location'] as String? ?? ''),
      startAt: Value(_dt(j['start_at'])),
      endAt: Value(_dt(j['end_at'])),
      timezone: Value(j['timezone'] as String? ?? 'UTC'),
      allDay: Value(j['all_day'] as bool? ?? false),
      rrule: Value(j['rrule'] as String?),
      recurrenceId: Value(j['recurrence_id'] as String?),
      originalStart: Value(_dtn(j['original_start'])),
      reminders: Value(jsonEncode(j['reminders'] ?? const [])),
      createdAt: Value(_dt(j['created_at'])),
      updatedAt: Value(_dt(j['updated_at'])),
      deletedAt: Value(_dtn(j['deleted_at'])),
      version: Value((j['version'] as num?)?.toInt() ?? 0),
      serverSeq: Value((j['server_seq'] as num?)?.toInt() ?? 0),
    );

Map<String, dynamic> eventToPushData(Event e) => {
      'calendar_id': e.calendarId,
      'title': e.title,
      'description': e.description,
      'location': e.location,
      'start_at': _iso(e.startAt),
      'end_at': _iso(e.endAt),
      'timezone': e.timezone,
      'all_day': e.allDay,
      'rrule': e.rrule,
      'recurrence_id': e.recurrenceId,
      'original_start': _ison(e.originalStart),
      'reminders': jsonDecode(e.reminders),
      'created_at': _iso(e.createdAt),
    };

// --- notes ------------------------------------------------------------------

NotesCompanion noteFromJson(Map<String, dynamic> j) => NotesCompanion(
      id: Value(j['id'] as String),
      title: Value(j['title'] as String? ?? ''),
      body: Value(j['body'] as String? ?? ''),
      pinned: Value(j['pinned'] as bool? ?? false),
      eventId: Value(j['event_id'] as String?),
      tags: Value(jsonEncode(j['tags'] ?? const [])),
      createdAt: Value(_dt(j['created_at'])),
      updatedAt: Value(_dt(j['updated_at'])),
      deletedAt: Value(_dtn(j['deleted_at'])),
      version: Value((j['version'] as num?)?.toInt() ?? 0),
      serverSeq: Value((j['server_seq'] as num?)?.toInt() ?? 0),
    );

Map<String, dynamic> noteToPushData(Note n) => {
      'title': n.title,
      'body': n.body,
      'pinned': n.pinned,
      'event_id': n.eventId,
      'tags': jsonDecode(n.tags),
      'created_at': _iso(n.createdAt),
    };

List<String> noteTags(Note n) => (jsonDecode(n.tags) as List<dynamic>).cast<String>();
List<int> eventReminders(Event e) => (jsonDecode(e.reminders) as List<dynamic>).cast<int>();

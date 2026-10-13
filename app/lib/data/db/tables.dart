import 'package:drift/drift.dart';

/// Shared sync columns. All DateTime values are stored as ISO-8601 UTC text.
mixin SyncColumns on Table {
  TextColumn get id => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get version => integer().withDefault(const Constant(0))();
  IntColumn get serverSeq => integer().withDefault(const Constant(0))();
}

class Calendars extends Table with SyncColumns {
  TextColumn get name => text()();
  TextColumn get color => text().withDefault(const Constant('#3B82F6'))();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
  BoolColumn get visible => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

class Events extends Table with SyncColumns {
  TextColumn get calendarId => text()();
  TextColumn get title => text()();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get location => text().withDefault(const Constant(''))();
  DateTimeColumn get startAt => dateTime()();
  DateTimeColumn get endAt => dateTime()();
  TextColumn get timezone => text()();
  BoolColumn get allDay => boolean().withDefault(const Constant(false))();
  TextColumn get rrule => text().nullable()();
  TextColumn get recurrenceId => text().nullable()();
  DateTimeColumn get originalStart => dateTime().nullable()();

  /// JSON array of minutes-before-start.
  TextColumn get reminders => text().withDefault(const Constant('[]'))();

  @override
  Set<Column> get primaryKey => {id};
}

class Notes extends Table with SyncColumns {
  TextColumn get title => text()();
  TextColumn get body => text()();
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
  TextColumn get eventId => text().nullable()();

  /// JSON array of strings.
  TextColumn get tags => text().withDefault(const Constant('[]'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Pending local changes waiting to be pushed. One row per record: a newer
/// change for the same record replaces the older row (keeping base version).
class Outbox extends Table {
  IntColumn get seq => integer().autoIncrement()();
  TextColumn get entity => text()();
  TextColumn get op => text()();
  TextColumn get recordId => text()();
  IntColumn get baseVersion => integer()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get data => text().nullable()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
        {entity, recordId},
      ];
}

/// Small key/value store: last_seq, last_sync_at, …
class SyncState extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

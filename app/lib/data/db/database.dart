import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables.dart';

part 'database.g.dart';

const kLastSeq = 'last_seq';
const kLastSyncAt = 'last_sync_at';

@DriftDatabase(tables: [Calendars, Events, Notes, Tasks, Outbox, SyncState])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  AppDatabase.open()
      : super(driftDatabase(
          name: 'personal_calendar',
          native: const DriftNativeOptions(shareAcrossIsolates: true),
        ));

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _createFts();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(calendars, calendars.source);
            await m.addColumn(calendars, calendars.icsUrl);
            await m.addColumn(calendars, calendars.lastFetchedAt);
          }
          if (from < 3) {
            await m.createTable(tasks);
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
          await customStatement('PRAGMA journal_mode = WAL');
        },
      );

  /// FTS5 index over live notes, kept in sync with triggers.
  Future<void> _createFts() async {
    await customStatement('''
      CREATE VIRTUAL TABLE notes_fts USING fts5(
        title, body, tags, content='notes', content_rowid='rowid',
        tokenize='unicode61 remove_diacritics 2'
      )''');
    await customStatement('''
      CREATE TRIGGER notes_ai AFTER INSERT ON notes BEGIN
        INSERT INTO notes_fts(rowid, title, body, tags) VALUES (new.rowid, new.title, new.body, new.tags);
      END''');
    await customStatement('''
      CREATE TRIGGER notes_ad AFTER DELETE ON notes BEGIN
        INSERT INTO notes_fts(notes_fts, rowid, title, body, tags) VALUES ('delete', old.rowid, old.title, old.body, old.tags);
      END''');
    await customStatement('''
      CREATE TRIGGER notes_au AFTER UPDATE ON notes BEGIN
        INSERT INTO notes_fts(notes_fts, rowid, title, body, tags) VALUES ('delete', old.rowid, old.title, old.body, old.tags);
        INSERT INTO notes_fts(rowid, title, body, tags) VALUES (new.rowid, new.title, new.body, new.tags);
      END''');
  }

  // --- sync state ----------------------------------------------------------

  Future<String?> getState(String key) async {
    final row = await (select(syncState)..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> setState(String key, String value) =>
      into(syncState).insertOnConflictUpdate(SyncStateCompanion(key: Value(key), value: Value(value)));

  Future<int> get lastSeq async => int.tryParse(await getState(kLastSeq) ?? '0') ?? 0;

  // --- outbox --------------------------------------------------------------

  /// Enqueue a change, collapsing with any pending change for the same record.
  Future<void> enqueue({
    required String entity,
    required String op,
    required String recordId,
    required int baseVersion,
    required DateTime updatedAt,
    Map<String, dynamic>? data,
  }) async {
    await transaction(() async {
      final existing = await (select(outbox)
            ..where((t) => t.entity.equals(entity) & t.recordId.equals(recordId)))
          .getSingleOrNull();
      // keep the base version the client originally started from
      final base = existing?.baseVersion ?? baseVersion;
      if (existing != null) {
        await (delete(outbox)..where((t) => t.seq.equals(existing.seq))).go();
      }
      await into(outbox).insert(OutboxCompanion.insert(
        entity: entity,
        op: op,
        recordId: recordId,
        baseVersion: base,
        updatedAt: updatedAt.toUtc(),
        data: Value(data == null ? null : jsonEncode(data)),
      ));
    });
  }

  Future<List<OutboxData>> pendingOutbox({int limit = 500}) =>
      (select(outbox)..orderBy([(t) => OrderingTerm.asc(t.seq)])..limit(limit)).get();

  Stream<int> watchOutboxCount() {
    final c = outbox.seq.count();
    return (selectOnly(outbox)..addColumns([c])).map((r) => r.read(c) ?? 0).watchSingle();
  }

  Future<void> removeOutbox(Iterable<int> seqs) =>
      (delete(outbox)..where((t) => t.seq.isIn(seqs))).go();

  Future<void> markOutboxError(int seq, String error) => (update(outbox)..where((t) => t.seq.equals(seq))).write(
        OutboxCompanion(attempts: Value(0), lastError: Value(error)),
      );

  /// Wipes everything (logout).
  Future<void> clearAll() => transaction(() async {
        for (final t in allTables) {
          await delete(t).go();
        }
      });

  // --- notes search --------------------------------------------------------

  /// Full-text search over live notes; every word becomes a prefix term.
  Future<List<Note>> searchNotes(String query) async {
    final terms = query
        .split(RegExp(r'\s+'))
        .map((w) => w.replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), ''))
        .where((w) => w.isNotEmpty)
        .map((w) => '"$w"*')
        .join(' ');
    if (terms.isEmpty) return [];
    final rows = await customSelect(
      'SELECT n.* FROM notes n JOIN notes_fts f ON n.rowid = f.rowid '
      'WHERE notes_fts MATCH ? AND n.deleted_at IS NULL '
      'ORDER BY n.pinned DESC, bm25(notes_fts), n.updated_at DESC LIMIT 200',
      variables: [Variable.withString(terms)],
      readsFrom: {notes},
    ).get();
    return rows.map((r) => notes.map(r.data)).toList();
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';

import '../api/api_client.dart';
import '../api/sync_api.dart';
import '../db/database.dart';
import 'mappers.dart';

enum SyncPhase { idle, syncing, offline, error, unauthenticated }

class SyncStatus {
  const SyncStatus({this.phase = SyncPhase.idle, this.pending = 0, this.lastSyncAt, this.error});

  final SyncPhase phase;
  final int pending;
  final DateTime? lastSyncAt;
  final String? error;

  SyncStatus copyWith({SyncPhase? phase, int? pending, DateTime? lastSyncAt, String? error}) => SyncStatus(
        phase: phase ?? this.phase,
        pending: pending ?? this.pending,
        lastSyncAt: lastSyncAt ?? this.lastSyncAt,
        error: error,
      );
}

class SyncResult {
  SyncResult({this.pushed = 0, this.conflicts = 0, this.rejected = 0, this.pulled = 0, this.error});
  final int pushed;
  final int conflicts;
  final int rejected;
  final int pulled;
  final Object? error;
  bool get ok => error == null;
}

/// Push the outbox, then pull everything newer than last_seq.
///
/// Runs are single-flight: concurrent [sync] calls share the running one.
/// Local writes never wait for the network; they only call [scheduleSoon].
class SyncService {
  SyncService(this.db, this.api, {this.debounce = const Duration(seconds: 2), DateTime Function()? now})
      : _now = now ?? DateTime.now {
    _pendingSub = db.watchOutboxCount().listen((n) {
      _status = _status.copyWith(pending: n);
      _emit();
    });
  }

  final AppDatabase db;
  final SyncApi api;
  final Duration debounce;
  final DateTime Function() _now;

  final _controller = StreamController<SyncStatus>.broadcast();
  SyncStatus _status = const SyncStatus();
  StreamSubscription<int>? _pendingSub;
  Future<SyncResult>? _running;
  Timer? _debounceTimer;

  /// Fired after a pull applied changes (reminder rescheduling, UI refresh).
  final _applied = StreamController<void>.broadcast();
  Stream<void> get onApplied => _applied.stream;

  Stream<SyncStatus> get status => _controller.stream;
  SyncStatus get currentStatus => _status;

  void _emit() {
    if (!_controller.isClosed) _controller.add(_status);
  }

  /// Debounced trigger used after local writes.
  void scheduleSoon() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () => sync());
  }

  Future<SyncResult> sync() {
    final running = _running;
    if (running != null) return running;
    final f = _run().whenComplete(() => _running = null);
    _running = f;
    return f;
  }

  Future<SyncResult> _run() async {
    _status = _status.copyWith(phase: SyncPhase.syncing);
    _emit();
    try {
      final pushRes = await _push();
      final pulled = await _pull();
      final at = _now().toUtc();
      await db.setState(kLastSyncAt, at.toIso8601String());
      _status = _status.copyWith(phase: SyncPhase.idle, lastSyncAt: at);
      _emit();
      return SyncResult(pushed: pushRes.$1, conflicts: pushRes.$2, rejected: pushRes.$3, pulled: pulled);
    } on NetworkException catch (e) {
      _status = _status.copyWith(phase: SyncPhase.offline);
      _emit();
      return SyncResult(error: e);
    } on ApiException catch (e) {
      _status = _status.copyWith(phase: e.isAuthError ? SyncPhase.unauthenticated : SyncPhase.error, error: e.message);
      _emit();
      return SyncResult(error: e);
    } catch (e) {
      _status = _status.copyWith(phase: SyncPhase.error, error: e.toString());
      _emit();
      return SyncResult(error: e);
    }
  }

  /// Returns (applied, conflicts, rejected).
  Future<(int, int, int)> _push() async {
    var applied = 0, conflicts = 0, rejected = 0;
    while (true) {
      final rows = await db.pendingOutbox(limit: 200);
      if (rows.isEmpty) break;
      final items = rows
          .map((r) => PushItem(
                entity: r.entity,
                op: r.op,
                id: r.recordId,
                baseVersion: r.baseVersion,
                updatedAt: r.updatedAt,
                data: r.data == null ? null : _decode(r.data!),
              ))
          .toList();
      final res = await api.push(items);
      final done = <int>[];
      for (var i = 0; i < res.results.length && i < rows.length; i++) {
        final r = res.results[i];
        final row = rows[i];
        switch (r.status) {
          case 'applied':
            applied++;
            await _bumpLocalVersion(r.entity, r.id, r.version, r.serverSeq);
            done.add(row.seq);
          case 'conflict':
            conflicts++;
            if (r.current != null) await _applyRecord(r.entity, r.current!);
            done.add(row.seq);
          case 'ignored':
            done.add(row.seq);
          case 'rejected':
            rejected++;
            // Keep the data locally but stop retrying this item; the UI can surface lastError.
            await db.markOutboxError(row.seq, r.error ?? 'rejected');
            done.add(row.seq);
          default:
            done.add(row.seq);
        }
      }
      await db.removeOutbox(done);
      if (rows.length < 200) break;
    }
    return (applied, conflicts, rejected);
  }

  Map<String, dynamic> _decode(String s) => (jsonDecodeMap(s));

  Future<int> _pull() async {
    var total = 0;
    var since = await db.lastSeq;
    while (true) {
      final res = await api.pull(since);
      await db.transaction(() async {
        for (final c in res.calendars) {
          await _applyRecord('calendar', c);
        }
        for (final e in res.events) {
          await _applyRecord('event', e);
        }
        for (final n in res.notes) {
          await _applyRecord('note', n);
        }
        for (final t in res.tasks) {
          await _applyRecord('task', t);
        }
        await db.setState(kLastSeq, res.lastSeq.toString());
      });
      total += res.calendars.length + res.events.length + res.notes.length + res.tasks.length;
      since = res.lastSeq;
      if (!res.hasMore) break;
    }
    if (total > 0 && !_applied.isClosed) _applied.add(null);
    return total;
  }

  /// Writes a server record locally unless a newer local change is still pending.
  Future<void> _applyRecord(String entity, Map<String, dynamic> j) async {
    final id = j['id'] as String;
    final pending = await (db.select(db.outbox)
          ..where((t) => t.entity.equals(entity) & t.recordId.equals(id)))
        .getSingleOrNull();
    if (pending != null) {
      final serverUpdated = DateTime.parse(j['updated_at'] as String).toUtc();
      if (!serverUpdated.isAfter(pending.updatedAt)) return; // local edit is newer; it will be pushed
      // server is newer: drop the stale local change (server policy would reject it anyway)
      await db.removeOutbox([pending.seq]);
    }
    switch (entity) {
      case 'calendar':
        final existing = await (db.select(db.calendars)..where((t) => t.id.equals(id))).getSingleOrNull();
        await db.into(db.calendars).insertOnConflictUpdate(calendarFromJson(j, visible: existing?.visible));
      case 'event':
        await db.into(db.events).insertOnConflictUpdate(eventFromJson(j));
      case 'note':
        await db.into(db.notes).insertOnConflictUpdate(noteFromJson(j));
      case 'task':
        await db.into(db.tasks).insertOnConflictUpdate(taskFromJson(j));
    }
  }

  Future<void> _bumpLocalVersion(String entity, String id, int version, int serverSeq) async {
    switch (entity) {
      case 'calendar':
        await (db.update(db.calendars)..where((t) => t.id.equals(id)))
            .write(CalendarsCompanion(version: Value(version), serverSeq: Value(serverSeq)));
      case 'event':
        await (db.update(db.events)..where((t) => t.id.equals(id)))
            .write(EventsCompanion(version: Value(version), serverSeq: Value(serverSeq)));
      case 'note':
        await (db.update(db.notes)..where((t) => t.id.equals(id)))
            .write(NotesCompanion(version: Value(version), serverSeq: Value(serverSeq)));
      case 'task':
        await (db.update(db.tasks)..where((t) => t.id.equals(id)))
            .write(TasksCompanion(version: Value(version), serverSeq: Value(serverSeq)));
    }
  }

  Future<void> dispose() async {
    _debounceTimer?.cancel();
    await _pendingSub?.cancel();
    await _controller.close();
    await _applied.close();
  }
}

Map<String, dynamic> jsonDecodeMap(String s) => (const JsonCodec().decode(s) as Map).cast<String, dynamic>();

import 'package:personal_calendar/data/api/api_client.dart';
import 'package:personal_calendar/data/api/sync_api.dart';

/// In-memory server that mirrors the backend's sync semantics closely enough
/// for client tests: versions, server_seq, last-writer-wins, note conflict copies.
class FakeSyncApi implements SyncApi {
  final Map<String, Map<String, Map<String, dynamic>>> tables = {'calendar': {}, 'event': {}, 'note': {}};
  int seq = 0;
  bool offline = false;
  bool unauthorized = false;
  int pushCalls = 0;
  int pullCalls = 0;
  final List<List<PushItem>> pushed = [];
  int pageSize = 500;

  Map<String, dynamic>? get(String entity, String id) => tables[entity]![id];

  void _check() {
    if (offline) throw NetworkException('offline');
    if (unauthorized) throw ApiException(401, 'unauthorized', 'expired');
  }

  /// Simulates another device writing on the server.
  Map<String, dynamic> serverWrite(String entity, String id, Map<String, dynamic> data, {DateTime? at}) {
    final now = (at ?? DateTime.now()).toUtc().toIso8601String();
    final cur = tables[entity]![id];
    final rec = <String, dynamic>{
      ...?cur,
      ...data,
      'id': id,
      'created_at': cur?['created_at'] ?? now,
      'updated_at': now,
      'deleted_at': data['deleted_at'],
      'version': ((cur?['version'] as int?) ?? 0) + 1,
      'server_seq': ++seq,
    };
    tables[entity]![id] = rec;
    return rec;
  }

  @override
  Future<PushResponse> push(List<PushItem> items) async {
    _check();
    pushCalls++;
    pushed.add(items);
    final results = <Map<String, dynamic>>[];
    for (final it in items) {
      final table = tables[it.entity];
      if (table == null) {
        results.add({'entity': it.entity, 'id': it.id, 'status': 'rejected', 'error': 'unknown entity'});
        continue;
      }
      final cur = table[it.id];
      if (cur == null) {
        if (it.op == 'delete') {
          results.add({'entity': it.entity, 'id': it.id, 'status': 'ignored'});
          continue;
        }
        if (it.entity == 'note' && (it.data!['title'] as String).isEmpty && (it.data!['body'] as String).isEmpty) {
          results.add({'entity': it.entity, 'id': it.id, 'status': 'rejected', 'error': 'empty'});
          continue;
        }
        final rec = serverWrite(it.entity, it.id, {...?it.data}, at: it.updatedAt);
        results.add({'entity': it.entity, 'id': it.id, 'status': 'applied', 'version': rec['version'], 'server_seq': rec['server_seq']});
        continue;
      }
      final curUpdated = DateTime.parse(cur['updated_at'] as String);
      final stale = it.baseVersion != cur['version'];
      final apply = !stale || it.updatedAt.toUtc().isAfter(curUpdated);
      String? copyId;
      if (stale && it.entity == 'note' && it.op == 'upsert' && it.data!['body'] != cur['body']) {
        final losing = apply ? cur : {...it.data!};
        copyId = 'copy-${it.id}-${++seq}';
        serverWrite('note', copyId, {'title': '(çakışan kopya) ${losing['title']}', 'body': losing['body'], 'pinned': false, 'tags': losing['tags'] ?? []});
      }
      if (!apply) {
        results.add({
          'entity': it.entity, 'id': it.id, 'status': 'conflict', 'version': cur['version'], 'server_seq': cur['server_seq'],
          'current': cur, 'conflict_copy_id': ?copyId,
        });
        continue;
      }
      final rec = it.op == 'delete'
          ? serverWrite(it.entity, it.id, {'deleted_at': it.updatedAt.toUtc().toIso8601String()}, at: it.updatedAt)
          : serverWrite(it.entity, it.id, {...it.data!}, at: it.updatedAt);
      results.add({
        'entity': it.entity, 'id': it.id, 'status': 'applied', 'version': rec['version'], 'server_seq': rec['server_seq'],
        'conflict_copy_id': ?copyId,
      });
    }
    return PushResponse.fromJson({'results': results, 'last_seq': seq});
  }

  @override
  Future<PullResponse> pull(int since, {int limit = 500}) async {
    _check();
    pullCalls++;
    final all = <(int, String, Map<String, dynamic>)>[];
    for (final e in tables.entries) {
      for (final r in e.value.values) {
        if ((r['server_seq'] as int) > since) all.add((r['server_seq'] as int, e.key, r));
      }
    }
    all.sort((a, b) => a.$1.compareTo(b.$1));
    final page = all.take(pageSize).toList();
    final hasMore = all.length > pageSize;
    final lastSeq = hasMore ? page.last.$1 : seq;
    Map<String, dynamic> full(String entity, Map<String, dynamic> r) => {
          'description': '', 'location': '', 'timezone': 'UTC', 'all_day': false, 'reminders': [], 'tags': [], 'pinned': false,
          'title': '', 'body': '', 'color': '#3B82F6', 'is_default': false, ...r,
        };
    return PullResponse.fromJson({
      'calendars': [for (final p in page) if (p.$2 == 'calendar') full('calendar', p.$3)],
      'events': [for (final p in page) if (p.$2 == 'event') full('event', p.$3)],
      'notes': [for (final p in page) if (p.$2 == 'note') full('note', p.$3)],
      'last_seq': lastSeq,
      'has_more': hasMore,
    });
  }
}

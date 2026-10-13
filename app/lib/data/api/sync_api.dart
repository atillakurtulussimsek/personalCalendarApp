import 'api_client.dart';

/// One outbox item as sent to POST /sync.
class PushItem {
  PushItem({
    required this.entity,
    required this.op,
    required this.id,
    required this.baseVersion,
    required this.updatedAt,
    this.data,
  });

  final String entity;
  final String op;
  final String id;
  final int baseVersion;
  final DateTime updatedAt;
  final Map<String, dynamic>? data;

  Map<String, dynamic> toJson() => {
        'entity': entity,
        'op': op,
        'id': id,
        'base_version': baseVersion,
        'updated_at': updatedAt.toUtc().toIso8601String(),
        if (data != null) 'data': data,
      };
}

class PushResult {
  PushResult.fromJson(Map<String, dynamic> j)
      : entity = j['entity'] as String,
        id = j['id'] as String,
        status = j['status'] as String,
        version = (j['version'] as num?)?.toInt() ?? 0,
        serverSeq = (j['server_seq'] as num?)?.toInt() ?? 0,
        conflictCopyId = j['conflict_copy_id'] as String?,
        current = j['current'] as Map<String, dynamic>?,
        error = j['error'] as String?;

  final String entity;
  final String id;
  final String status;
  final int version;
  final int serverSeq;
  final String? conflictCopyId;
  final Map<String, dynamic>? current;
  final String? error;
}

class PushResponse {
  PushResponse.fromJson(Map<String, dynamic> j)
      : results = (j['results'] as List<dynamic>).map((e) => PushResult.fromJson(e as Map<String, dynamic>)).toList(),
        lastSeq = (j['last_seq'] as num).toInt();

  final List<PushResult> results;
  final int lastSeq;
}

class PullResponse {
  PullResponse.fromJson(Map<String, dynamic> j)
      : calendars = _list(j['calendars']),
        events = _list(j['events']),
        notes = _list(j['notes']),
        tasks = _list(j['tasks']),
        lastSeq = (j['last_seq'] as num).toInt(),
        hasMore = j['has_more'] as bool? ?? false;

  static List<Map<String, dynamic>> _list(dynamic v) =>
      (v as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();

  final List<Map<String, dynamic>> calendars;
  final List<Map<String, dynamic>> events;
  final List<Map<String, dynamic>> notes;
  final List<Map<String, dynamic>> tasks;
  final int lastSeq;
  final bool hasMore;
}

/// The sync endpoints. Abstract so the sync service can be unit tested.
abstract class SyncApi {
  Future<PushResponse> push(List<PushItem> items);
  Future<PullResponse> pull(int since, {int limit = 500});
}

class HttpSyncApi implements SyncApi {
  HttpSyncApi(this.client);
  final ApiClient client;

  @override
  Future<PushResponse> push(List<PushItem> items) async {
    final data = await client.request('POST', '/sync', body: {'items': items.map((e) => e.toJson()).toList()});
    return PushResponse.fromJson(data);
  }

  @override
  Future<PullResponse> pull(int since, {int limit = 500}) async {
    final data = await client.request('GET', '/sync', query: {'since': since, 'limit': limit});
    return PullResponse.fromJson(data);
  }
}

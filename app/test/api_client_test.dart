import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_calendar/data/api/api_client.dart';
import 'package:personal_calendar/data/api/token_store.dart';

/// Fake HTTP layer: a queue of scripted responses.
class _Adapter implements HttpClientAdapter {
  final List<(int, String)> script = [];
  final List<RequestOptions> seen = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream, Future<void>? cancelFuture) async {
    seen.add(options);
    if (script.isEmpty) throw DioException.connectionError(requestOptions: options, reason: 'no script');
    final (status, body) = script.removeAt(0);
    return ResponseBody.fromString(body, status, headers: {
      'content-type': ['application/json']
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late MemoryTokenStore tokens;
  late _Adapter adapter;
  late ApiClient client;
  var expired = 0;

  setUp(() async {
    tokens = MemoryTokenStore();
    await tokens.write(TokenStore.serverUrl, 'http://x');
    await tokens.write(TokenStore.accessToken, 'old-access');
    await tokens.write(TokenStore.refreshToken, 'old-refresh');
    adapter = _Adapter();
    expired = 0;
    client = ApiClient(tokens, dio: Dio()..httpClientAdapter = adapter, onSessionExpired: () => expired++);
  });

  test('adds bearer header and parses the error envelope', () async {
    adapter.script.add((422, '{"error":{"code":"validation_error","message":"bad"}}'));
    await expectLater(
      client.request('POST', '/notes', body: {}),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'validation_error').having((e) => e.statusCode, 'status', 422)),
    );
    expect(adapter.seen.single.headers['Authorization'], 'Bearer old-access');
    expect(adapter.seen.single.uri.toString(), 'http://x/notes');
  });

  test('refreshes once on 401 and retries with the new token', () async {
    adapter.script.addAll([
      (401, '{"error":{"code":"unauthorized","message":"expired"}}'),
      (200, '{"access_token":"new-access","refresh_token":"new-refresh"}'),
      (200, '{"notes":[]}'),
    ]);
    final data = await client.request('GET', '/notes');
    expect(data['notes'], isEmpty);
    expect(adapter.seen.length, 3);
    expect(adapter.seen[1].uri.path, '/auth/refresh');
    expect(adapter.seen[2].headers['Authorization'], 'Bearer new-access');
    expect(await tokens.read(TokenStore.refreshToken), 'new-refresh');
    expect(expired, 0);
  });

  test('failed refresh clears auth and signals session expiry', () async {
    adapter.script.addAll([
      (401, '{"error":{"code":"unauthorized","message":"expired"}}'),
      (401, '{"error":{"code":"unauthorized","message":"invalid refresh token"}}'),
    ]);
    await expectLater(client.request('GET', '/notes'), throwsA(isA<ApiException>()));
    expect(await tokens.read(TokenStore.accessToken), isNull);
    expect(expired, 1);
  });

  test('connection errors become NetworkException', () async {
    await expectLater(client.request('GET', '/healthz', auth: false), throwsA(isA<NetworkException>()));
  });
}

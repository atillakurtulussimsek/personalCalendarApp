import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_calendar/data/api/token_store.dart';
import 'package:personal_calendar/data/db/database.dart';
import 'package:personal_calendar/data/sync/sync_service.dart';
import 'package:personal_calendar/platform/live_sync.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'fake_sync_api.dart';

/// A scripted in-memory WebSocket.
class FakeChannel extends StreamChannelMixin<dynamic> implements WebSocketChannel {
  FakeChannel(this.uri);
  final Uri uri;
  final incoming = StreamController<dynamic>();
  final outgoing = StreamController<dynamic>();

  @override
  Future<void> get ready async {}
  @override
  Stream<dynamic> get stream => incoming.stream;
  @override
  WebSocketSink get sink => _FakeSink(outgoing, incoming);
  @override
  int? get closeCode => null;
  @override
  String? get closeReason => null;
  @override
  String? get protocol => null;
}

class _FakeSink implements WebSocketSink {
  _FakeSink(this.out, this.inc);
  final StreamController<dynamic> out;
  final StreamController<dynamic> inc;
  @override
  void add(dynamic data) => out.add(data);
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  Future<void> addStream(Stream<dynamic> stream) => out.addStream(stream);
  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    if (!inc.isClosed) await inc.close();
  }
  @override
  Future<void> get done => out.done;
}

void main() {
  test('live sync connects with the token, syncs on signals and reconnects after loss', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final api = FakeSyncApi();
    final sync = SyncService(db, api, debounce: const Duration(days: 1));
    final tokens = MemoryTokenStore();
    await tokens.write(TokenStore.serverUrl, 'https://takvim.example.com');
    await tokens.write(TokenStore.accessToken, 'tok');
    final channels = <FakeChannel>[];
    final live = LiveSync(tokens, sync, connect: (uri) {
      final c = FakeChannel(uri);
      channels.add(c);
      return c;
    });
    final states = <LiveState>[];
    live.state.listen(states.add);

    await live.start();
    await Future<void>.delayed(Duration.zero);
    expect(channels.single.uri.toString(), 'wss://takvim.example.com/ws?token=tok');
    expect(live.current, LiveState.connected);

    channels.single.incoming.add(jsonEncode({'type': 'hello', 'seq': 0}));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    channels.single.incoming.add(jsonEncode({'type': 'sync', 'seq': 5}));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(api.pullCalls, 2); // sync runs are single-flight, so each signal is awaited separately

    // server drops the connection → disconnected, retry scheduled
    await channels.single.incoming.close();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(live.current, LiveState.disconnected);

    // a token refresh forces an immediate reconnect with the new token
    await tokens.write(TokenStore.accessToken, 'tok2');
    await live.reconnect();
    await Future<void>.delayed(Duration.zero);
    expect(channels.length, 2);
    expect(channels.last.uri.queryParameters['token'], 'tok2');
    expect(live.current, LiveState.connected);

    await live.dispose();
    await sync.dispose();
    await db.close();
    expect(states, containsAllInOrder([LiveState.connecting, LiveState.connected, LiveState.disconnected, LiveState.connecting, LiveState.connected]));
  });
}

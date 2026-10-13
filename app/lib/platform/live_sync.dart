import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../data/api/token_store.dart';
import '../data/sync/sync_service.dart';

enum LiveState { disconnected, connecting, connected }

/// Keeps a WebSocket to GET /ws open and runs a sync whenever the server
/// signals that another device changed something. Reconnects with backoff.
class LiveSync {
  LiveSync(this.tokens, this.sync, {WebSocketChannel Function(Uri)? connect}) : _connect = connect ?? WebSocketChannel.connect;

  final TokenStore tokens;
  final SyncService sync;
  final WebSocketChannel Function(Uri) _connect;

  final _state = StreamController<LiveState>.broadcast();
  Stream<LiveState> get state => _state.stream;
  LiveState current = LiveState.disconnected;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _retry;
  int _attempt = 0;
  bool _enabled = false;

  Future<void> start() async {
    _enabled = true;
    _attempt = 0;
    await _open();
  }

  Future<void> stop() async {
    _enabled = false;
    _retry?.cancel();
    await _close();
    _set(LiveState.disconnected);
  }

  void _set(LiveState s) {
    current = s;
    if (!_state.isClosed) _state.add(s);
  }

  Future<Uri?> _uri() async {
    final base = await tokens.read(TokenStore.serverUrl);
    final token = await tokens.read(TokenStore.accessToken);
    if (base == null || token == null) return null;
    final u = Uri.parse(base);
    return u.replace(scheme: u.scheme == 'https' ? 'wss' : 'ws', path: '/ws', queryParameters: {'token': token});
  }

  Future<void> _open() async {
    if (!_enabled || _channel != null) return;
    final uri = await _uri();
    if (uri == null) {
      _scheduleRetry();
      return;
    }
    _set(LiveState.connecting);
    try {
      final ch = _connect(uri);
      _channel = ch;
      await ch.ready;
      _attempt = 0;
      _set(LiveState.connected);
      _sub = ch.stream.listen(_onMessage, onError: (_) => _lost(), onDone: _lost, cancelOnError: true);
    } catch (_) {
      _lost();
    }
  }

  void _onMessage(dynamic raw) {
    try {
      final m = jsonDecode(raw as String) as Map<String, dynamic>;
      switch (m['type']) {
        case 'sync':
          sync.sync();
        case 'hello':
          // the server's current seq; a cheap way to catch up after a reconnect
          sync.sync();
      }
    } catch (_) {}
  }

  /// Detaches synchronously (so a new connection can open at once) and cleans
  /// up the old one in the background, never waiting on a dead socket.
  Future<void> _close() async {
    final sub = _sub;
    final ch = _channel;
    _sub = null;
    _channel = null;
    if (sub != null) {
      unawaited(sub.cancel().timeout(const Duration(seconds: 2), onTimeout: () {}).catchError((_) {}));
    }
    if (ch != null) {
      unawaited(ch.sink.close().timeout(const Duration(seconds: 2), onTimeout: () {}).catchError((_) {}));
    }
  }

  void _lost() {
    _close();
    _set(LiveState.disconnected);
    _scheduleRetry();
  }

  void _scheduleRetry() {
    if (!_enabled) return;
    _retry?.cancel();
    final secs = min(60, 2 << min(_attempt, 5)) + Random().nextInt(3);
    _attempt++;
    _retry = Timer(Duration(seconds: secs), () async {
      // the access token may have been refreshed meanwhile; _uri() re-reads it
      await _open();
    });
  }

  /// Call after a token refresh so the socket re-authenticates.
  Future<void> reconnect() async {
    await _close();
    _attempt = 0;
    await _open();
  }

  Future<void> dispose() async {
    await stop();
    await _state.close();
  }
}

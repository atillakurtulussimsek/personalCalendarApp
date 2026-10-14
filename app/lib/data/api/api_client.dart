import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'token_store.dart';

/// Error returned by the API in the `{ "error": { code, message } }` envelope.
class ApiException implements Exception {
  ApiException(this.statusCode, this.code, this.message);

  final int statusCode;
  final String code;
  final String message;

  bool get isAuthError => statusCode == 401;

  @override
  String toString() => 'ApiException($statusCode $code: $message)';
}

/// Thrown when the server could not be reached at all.
class NetworkException implements Exception {
  NetworkException(this.cause);
  final Object cause;

  @override
  String toString() => 'NetworkException($cause)';
}

/// Dio wrapper: base URL from [TokenStore], bearer header, single-flight
/// refresh on 401, uniform error mapping.
class ApiClient {
  ApiClient(this.tokens, {Dio? dio, this.onSessionExpired, this.onTokenRefreshed}) : dio = dio ?? Dio() {
    this.dio.options
      ..connectTimeout = const Duration(seconds: 10)
      ..receiveTimeout = const Duration(seconds: 30)
      ..headers['Content-Type'] = 'application/json'
      ..validateStatus = (_) => true;
  }

  final TokenStore tokens;
  final Dio dio;
  final void Function()? onSessionExpired;
  final void Function()? onTokenRefreshed;

  Future<void>? _refreshing;

  Future<String> get baseUrl async => (await tokens.read(TokenStore.serverUrl)) ?? (kIsWeb ? Uri.base.origin : 'http://localhost:8080');

  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    bool auth = true,
    bool retryOnAuthError = true,
  }) async {
    final base = await baseUrl;
    final headers = <String, dynamic>{};
    if (auth) {
      final token = await tokens.read(TokenStore.accessToken);
      if (token != null) headers['Authorization'] = 'Bearer $token';
    }
    Response<dynamic> res;
    try {
      res = await dio.request<dynamic>(
        '$base$path',
        data: body,
        queryParameters: query,
        options: Options(method: method, headers: headers),
      );
    } on DioException catch (e) {
      throw NetworkException(e);
    }
    final status = res.statusCode ?? 0;
    if (status == 401 && auth && retryOnAuthError) {
      final ok = await _refresh();
      if (ok) {
        return request(method, path, body: body, query: query, auth: auth, retryOnAuthError: false);
      }
      onSessionExpired?.call();
    }
    final data = res.data;
    if (status >= 200 && status < 300) {
      if (data is Map<String, dynamic>) return data;
      return const {};
    }
    if (data is Map<String, dynamic> && data['error'] is Map<String, dynamic>) {
      final err = data['error'] as Map<String, dynamic>;
      throw ApiException(status, err['code'] as String? ?? 'error', err['message'] as String? ?? '');
    }
    throw ApiException(status, 'http_error', 'HTTP $status');
  }

  /// Refreshes the access token once, even if several requests fail together.
  Future<bool> _refresh() async {
    if (_refreshing != null) {
      await _refreshing;
      return (await tokens.read(TokenStore.accessToken)) != null;
    }
    final completer = Completer<void>();
    _refreshing = completer.future;
    try {
      final refresh = await tokens.read(TokenStore.refreshToken);
      if (refresh == null) return false;
      final data = await request('POST', '/auth/refresh',
          body: {'refresh_token': refresh}, auth: false, retryOnAuthError: false);
      await tokens.write(TokenStore.accessToken, data['access_token'] as String);
      await tokens.write(TokenStore.refreshToken, data['refresh_token'] as String);
      onTokenRefreshed?.call();
      return true;
    } on ApiException catch (e) {
      if (e.isAuthError) await tokens.clearAuth();
      return false;
    } on NetworkException {
      return false;
    } finally {
      completer.complete();
      _refreshing = null;
    }
  }
}

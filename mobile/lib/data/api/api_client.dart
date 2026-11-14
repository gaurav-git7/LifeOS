// HTTP client for the LifeOS API (ARCHITECTURE.md §9, §18).
//
// - Adds the access token to every request.
// - On 401 "token expired" it refreshes once (single-flight, rotating refresh
//   token) and retries; if refreshing fails the session ends.
// - Server errors {"error": {code, message}} become ApiException.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Base URL of the API. Override with --dart-define=API_URL=http://10.0.2.2:8000/api/v1
const apiBaseUrl = String.fromEnvironment('API_URL', defaultValue: 'https://lifeos-api-xxrp.onrender.com/api/v1');

class ApiException implements Exception {
  const ApiException(this.code, this.message, {this.status = 0, this.details = const {}});

  final String code;
  final String message;
  final int status;
  final Map<String, dynamic> details;

  bool get isNetwork => code == 'network';

  @override
  String toString() => 'ApiException($status $code: $message)';
}

/// Access + refresh tokens. Stored in the Android Keystore via flutter_secure_storage.
class TokenStore {
  TokenStore({FlutterSecureStorage? storage, bool inMemory = false})
      : _storage = inMemory ? null : (storage ?? const FlutterSecureStorage());

  final FlutterSecureStorage? _storage;
  final Map<String, String> _memory = {};

  static const _access = 'lifeos_access_token';
  static const _refresh = 'lifeos_refresh_token';

  String? _cachedAccess;

  Future<String?> _read(String k) async => _storage == null ? _memory[k] : _storage.read(key: k);

  Future<void> _write(String k, String v) async =>
      _storage == null ? _memory[k] = v : await _storage.write(key: k, value: v);

  Future<void> _delete(String k) async => _storage == null ? _memory.remove(k) : await _storage.delete(key: k);

  Future<String?> get access async => _cachedAccess ??= await _read(_access);
  Future<String?> get refresh => _read(_refresh);

  Future<void> save(String access, String refresh) async {
    _cachedAccess = access;
    await _write(_access, access);
    await _write(_refresh, refresh);
  }

  Future<void> clear() async {
    _cachedAccess = null;
    await _delete(_access);
    await _delete(_refresh);
  }
}

class ApiClient {
  ApiClient({required this.tokens, String baseUrl = apiBaseUrl, HttpClientAdapter? adapter}) {
    final options = BaseOptions(
      baseUrl: baseUrl,
      // Render's free instance can take ~30–60 s to wake up.
      connectTimeout: const Duration(seconds: 60),
      receiveTimeout: const Duration(seconds: 60),
      contentType: Headers.jsonContentType,
      responseType: ResponseType.json,
    );
    _dio = Dio(options);
    _refreshDio = Dio(options);
    if (adapter != null) {
      _dio.httpClientAdapter = adapter;
      _refreshDio.httpClientAdapter = adapter;
    }
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (o, h) async {
        if (o.extra['auth'] != false) {
          final token = await tokens.access;
          if (token != null) o.headers['Authorization'] = 'Bearer $token';
        }
        h.next(o);
      },
      onError: (e, h) async {
        final res = e.response;
        final code = _errorCode(res?.data);
        final canRetry = res?.statusCode == 401 &&
            e.requestOptions.extra['auth'] != false &&
            e.requestOptions.extra['retried'] != true &&
            (code == 'token_expired' || code == 'invalid_token');
        if (!canRetry) return h.next(e);
        try {
          await _refreshOnce();
          final o = e.requestOptions..extra['retried'] = true;
          o.headers['Authorization'] = 'Bearer ${await tokens.access}';
          return h.resolve(await _dio.fetch(o));
        } catch (_) {
          return h.next(e);
        }
      },
    ));
  }

  final TokenStore tokens;
  late final Dio _dio;
  late final Dio _refreshDio;

  /// Called when the session can't be renewed (refresh token expired or reused).
  void Function()? onSessionExpired;

  Future<void>? _refreshing;

  Future<void> _refreshOnce() {
    return _refreshing ??= () async {
      try {
        final refresh = await tokens.refresh;
        if (refresh == null) throw const ApiException('not_authenticated', 'Signed out.', status: 401);
        final r = await _refreshDio.post<Map<String, dynamic>>('/auth/refresh', data: {'refresh_token': refresh});
        await tokens.save(r.data!['access_token'] as String, r.data!['refresh_token'] as String);
      } catch (e) {
        await tokens.clear();
        onSessionExpired?.call();
        rethrow;
      } finally {
        _refreshing = null;
      }
    }();
  }

  static String? _errorCode(Object? data) {
    if (data is Map && data['error'] is Map) return (data['error'] as Map)['code'] as String?;
    return null;
  }

  static ApiException _map(DioException e) {
    final res = e.response;
    final data = res?.data;
    if (data is Map && data['error'] is Map) {
      final err = data['error'] as Map;
      return ApiException(
        (err['code'] ?? 'error') as String,
        (err['message'] ?? 'Something went wrong.') as String,
        status: res!.statusCode ?? 0,
        details: Map<String, dynamic>.from((err['details'] as Map?) ?? const {}),
      );
    }
    if (res == null) {
      return const ApiException('network', 'Can’t reach the LifeOS server. Check your connection and try again.');
    }
    return ApiException('http_${res.statusCode}', 'Server error (${res.statusCode}).', status: res.statusCode ?? 0);
  }

  Future<T> _call<T>(Future<Response<dynamic>> Function() f) async {
    try {
      final r = await f();
      return r.data as T;
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Options _opts(bool auth) => Options(extra: {'auth': auth});

  Future<T> get<T>(String path, {Map<String, dynamic>? query, bool auth = true}) =>
      _call(() => _dio.get<dynamic>(path, queryParameters: query, options: _opts(auth)));

  Future<T> post<T>(String path, {Object? data, Map<String, dynamic>? query, bool auth = true}) =>
      _call(() => _dio.post<dynamic>(path, data: data, queryParameters: query, options: _opts(auth)));

  Future<T> patch<T>(String path, {Object? data, bool auth = true}) =>
      _call(() => _dio.patch<dynamic>(path, data: data, options: _opts(auth)));

  Future<T> put<T>(String path, {Object? data}) => _call(() => _dio.put<dynamic>(path, data: data));

  Future<void> delete(String path) => _call<dynamic>(() => _dio.delete<dynamic>(path));

  /// Wakes a sleeping free-tier server without needing auth.
  Future<bool> ping() async {
    try {
      await Dio(BaseOptions(baseUrl: _dio.options.baseUrl.replaceFirst('/api/v1', ''), connectTimeout: const Duration(seconds: 60)))
          .get<dynamic>('/health');
      return true;
    } catch (_) {
      return false;
    }
  }
}

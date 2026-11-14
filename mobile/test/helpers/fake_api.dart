// In-memory stand-in for the LifeOS API, plugged into Dio as an HttpClientAdapter.
// Implements just enough of auth, sync, progression and the agent for tests.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifeos/data/api/api_client.dart';
import 'package:lifeos/data/stores.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeApi implements HttpClientAdapter {
  final Map<String, Map<String, Map<String, dynamic>>> rows = {};
  final Map<String, Map<String, dynamic>> proposals = {};
  final List<String> calls = [];
  int totalXp = 0;
  int _n = 0;
  bool offline = false;

  static const user = {
    'id': '00000000-0000-4000-8000-000000000001',
    'email': 'me@example.com',
    'display_name': 'Gaurav',
    'timezone': 'Asia/Kolkata',
    'role': 'admin',
    'level': 1,
    'total_xp': 0,
    'email_verified_at': null,
    'created_at': '2026-11-01T00:00:00Z',
  };

  Map<String, dynamic> get _tokens =>
      {'access_token': 'a${_n++}', 'refresh_token': 'r$_n', 'token_type': 'bearer', 'expires_in': 900, 'user': user};

  Iterable<Map<String, dynamic>> live(String entity) => (rows[entity] ?? {}).values.where((r) => r['deleted_at'] == null);

  /// Simulates a change made on another device / by the server.
  void serverInsert(String entity, String id, Map<String, dynamic> data) {
    (rows[entity] ??= {})[id] = {
      ...data,
      'id': id,
      'version': 1,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'deleted_at': null,
    };
  }

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    calls.add('${o.method} ${o.path}');
    if (offline) {
      throw DioException.connectionError(requestOptions: o, reason: 'offline');
    }
    final body = o.data is Map ? Map<String, dynamic>.from(o.data as Map) : <String, dynamic>{};
    final (status, out) = _route(o.method, o.path, body);
    return ResponseBody.fromString(jsonEncode(out), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  (int, Object?) _route(String method, String path, Map<String, dynamic> body) {
    final now = DateTime.now().toUtc().toIso8601String();
    switch ((method, path)) {
      case ('POST', '/auth/register') || ('POST', '/auth/login'):
        if (body['password'] == 'wrong-password') {
          return (401, {'error': {'code': 'invalid_credentials', 'message': 'Email or password is incorrect.'}});
        }
        return (200, _tokens);
      case ('POST', '/auth/logout'):
        return (200, {'message': 'Signed out.'});
      case ('GET', '/users/me'):
        return (200, user);
      case ('GET', '/users/me/preferences'):
        return (200, {'ai_enabled': true, 'daily_review_time': '21:00:00'});
      case ('PATCH', '/users/me/preferences') || ('PATCH', '/users/me'):
        return (200, user);
      case ('GET', '/progression'):
        return (200, {'total_xp': totalXp, 'achievements': <Object>[]});
      case ('GET', '/progression/xp-history'):
        return (200, <Object>[]);
      case ('GET', '/agent/memories') || ('GET', '/agent/conversations'):
        return (200, <Object>[]);
      case ('GET', '/agent/proposals'):
        return (200, proposals.values.where((p) => p['status'] == 'pending').toList());
      case ('POST', '/sync/push'):
        final results = <Map<String, dynamic>>[];
        for (final c in (body['changes'] as List).cast<Map<String, dynamic>>()) {
          final table = rows[c['entity'] as String] ??= {};
          final id = c['id'] as String;
          final existing = table[id];
          if (c['op'] == 'delete') {
            if (existing != null) {
              existing['deleted_at'] = now;
              existing['version'] = (existing['version'] as int) + 1;
              existing['updated_at'] = now;
            }
          } else {
            table[id] = {
              ...?existing,
              ...(c['data'] as Map).cast<String, dynamic>(),
              'id': id,
              'version': (existing?['version'] as int? ?? 0) + 1,
              'created_at': existing?['created_at'] ?? now,
              'updated_at': now,
              'deleted_at': null,
            };
            if (c['entity'] == 'tasks' && c['data']['status'] == 'done' && existing?['status'] != 'done') totalXp += 10;
          }
          results.add({'change_id': c['change_id'], 'status': 'applied', 'id': id, 'version': table[id]?['version']});
        }
        return (200, results);
      case ('GET', '/sync/pull'):
        return (200, {
          'cursor': now,
          'has_more': false,
          'changes': {for (final e in rows.entries) e.key: e.value.values.toList()},
        });
      case ('POST', '/agent/chat'):
        final p = {
          'id': '00000000-0000-4000-8000-0000000000a${proposals.length}',
          'group_id': null,
          'conversation_id': '00000000-0000-4000-8000-0000000000c1',
          'origin': 'chat',
          'action_type': 'create_task',
          'summary': 'Create task “Revise graphs”',
          'reason': 'You asked for it.',
          'payload': {'title': 'Revise graphs', 'priority': 'high', 'due_date': '2099-01-01'},
          'payload_hash': 'hash-1',
          'status': 'pending',
          'result': null,
          'error': null,
          'expires_at': '2099-01-01T00:00:00Z',
          'created_at': now,
        };
        proposals[p['id'] as String] = p;
        return (200, {
          'conversation_id': p['conversation_id'],
          'message_id': '00000000-0000-4000-8000-0000000000m1',
          'intent': 'create_task',
          'message': 'Here it is — approve to add it.',
          'proposals': [p],
          'memory_suggestions': <Object>[],
          'follow_up_question': null,
          'used_ai': false,
        });
    }
    final approve = RegExp(r'^/agent/proposals/([^/]+)/approve$').firstMatch(path);
    if (method == 'POST' && approve != null) {
      final p = proposals[approve.group(1)]!;
      if (body['payload_hash'] != p['payload_hash']) {
        return (409, {'error': {'code': 'stale_proposal', 'message': 'This suggestion changed.'}});
      }
      p['status'] = 'executed';
      final pl = p['payload'] as Map<String, dynamic>;
      serverInsert('tasks', '00000000-0000-4000-8000-0000000000t${_n++}', {...pl, 'status': 'todo', 'tags': <String>[]});
      return (200, p);
    }
    final topic = RegExp(r'^/learning/topics/([^/]+)/complete$').firstMatch(path);
    if (method == 'POST' && topic != null) {
      final t = rows['learning_topics']![topic.group(1)]!;
      t['status'] = 'done';
      t['version'] = (t['version'] as int) + 1;
      t['updated_at'] = now;
      return (200, t);
    }
    return (404, {'error': {'code': 'not_found', 'message': 'No fake route for $method $path'}});
  }

  @override
  void close({bool force = false}) {}
}

/// A container wired to [api] with in-memory tokens and empty shared preferences.
ProviderContainer fakeLiveContainer(FakeApi api) {
  SharedPreferences.setMockInitialValues({});
  return ProviderContainer(overrides: [
    tokenStoreProvider.overrideWithValue(TokenStore(inMemory: true)),
    apiClientProvider.overrideWith((ref) {
      final c = ApiClient(tokens: ref.watch(tokenStoreProvider), adapter: api);
      c.onSessionExpired = () => ref.read(authProvider.notifier).sessionExpired();
      return c;
    }),
  ]);
}

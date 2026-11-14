// Free crash reporting: uncaught errors go to the LifeOS backend
// (app.client_reports), not a paid service. Same error is sent once per run.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../app_info.dart';
import '../stores.dart';

class CrashReporter {
  CrashReporter(this.ref);

  final Ref ref;
  final Set<String> _sent = {};
  final List<(Object, StackTrace?)> _early = []; // errors before sign-in finished

  static const _maxPerRun = 20;

  /// Hook Flutter's error handlers. Call once at startup.
  void install() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      previous?.call(details);
      report(details.exception, details.stack);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      report(error, stack);
      return false; // keep the default behaviour (log it)
    };
  }

  void report(Object error, StackTrace? stack) {
    if (kDebugMode) return; // you see these in the console while developing
    final key = '${error.runtimeType}: $error'.split('\n').first;
    if (_sent.contains(key) || _sent.length >= _maxPerRun) return;
    if (!ref.read(authProvider).live) {
      if (_early.length < 5) _early.add((error, stack));
      return;
    }
    _sent.add(key);
    unawaited(ref
        .read(apiClientProvider)
        .post<dynamic>('/client-errors', data: {
          'message': key.length > 2000 ? key.substring(0, 2000) : key,
          'stack': stack?.toString().split('\n').take(40).join('\n'),
          'app_version': appVersion,
        })
        .then<void>((_) {}, onError: (_) {}));
  }

  /// Sends errors that happened before the session was ready.
  void flush() {
    final early = List.of(_early);
    _early.clear();
    for (final (e, s) in early) {
      report(e, s);
    }
  }

  /// "Send feedback" in Settings. Returns an error message or null.
  Future<String?> sendFeedback(String kind, String message, {String? screen}) async {
    if (!ref.read(authProvider).live) return 'Sign in to send feedback.';
    try {
      await ref.read(apiClientProvider).post<dynamic>('/feedback', data: {
        'kind': kind,
        'message': message,
        'app_version': appVersion,
        'screen': ?screen,
      });
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }
}

final crashReporterProvider = Provider<CrashReporter>((ref) => CrashReporter(ref));

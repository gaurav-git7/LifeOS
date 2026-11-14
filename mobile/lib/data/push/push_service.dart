// Server push (Firebase Cloud Messaging): daily/weekly review ready, new
// suggestions, achievements, feedback for the admin, and "update available".
// Phone reminders don't use this — they're scheduled locally.
//
// Uses the classic FCM registration token (getToken/onTokenRefresh). The newer
// register()/onRegistered API returns an installation ID for "direct send",
// which the server's firebase-admin multicast doesn't take yet.
// ignore_for_file: deprecated_member_use

import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/routing/routes.dart';
import '../app_info.dart';
import '../reminders/reminder_planner.dart' show reviewRoute;
import '../reminders/reminder_service.dart';
import '../stores.dart';

class PushService {
  PushService(this.ref);

  final Ref ref;
  bool _ready = false;
  StreamSubscription<String>? _tokenSub;
  StreamSubscription<RemoteMessage>? _msgSub;
  StreamSubscription<RemoteMessage>? _openSub;

  static const _deviceKey = 'lifeos_device_id';

  /// Where tapping a push should go, from the server's `kind` (+ url for updates).
  static String? targetFor(Map<String, dynamic> data) {
    final url = data['url'] as String?;
    if (url != null && url.startsWith('https://')) return url;
    return switch (data['kind']) {
      'review' => reviewRoute,
      'proposal' || 'agent_job' => '${Routes.assistant}?tab=suggestions',
      'achievement' || 'level_up' || 'celebration' => Routes.achievements,
      _ => null,
    };
  }

  Future<void> start() async {
    if (!ReminderService.supported || _ready) return;
    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint('Push disabled (no Firebase config): $e');
      return;
    }
    _ready = true;
    final fm = FirebaseMessaging.instance;
    final reminders = ref.read(reminderServiceProvider);

    // In the foreground Android doesn't show FCM notifications; show them ourselves.
    _msgSub = FirebaseMessaging.onMessage.listen((m) {
      final n = m.notification;
      if (n == null) return;
      reminders.showPush(
        title: n.title ?? 'LifeOS',
        body: n.body ?? '',
        channel: m.notification?.android?.channelId ?? 'updates',
        target: targetFor(m.data),
      );
    });
    _openSub = FirebaseMessaging.onMessageOpenedApp.listen((m) => reminders.open(targetFor(m.data)));
    final initial = await fm.getInitialMessage();
    if (initial != null) {
      Future<void>.delayed(const Duration(milliseconds: 800), () => reminders.open(targetFor(initial.data)));
    }
    _tokenSub = fm.onTokenRefresh.listen((t) => unawaited(_register(t)));
    await registerIfSignedIn();
  }

  /// Tell the server where to send this user's pushes (after sign-in / app start).
  Future<void> registerIfSignedIn() async {
    if (!_ready || !ref.read(authProvider).live) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _register(token);
    } catch (e) {
      debugPrint('FCM token failed: $e');
    }
  }

  Future<void> _register(String token) async {
    if (!ref.read(authProvider).live) return;
    try {
      final r = await ref
          .read(apiClientProvider)
          .post<Map<String, dynamic>>('/devices', data: {'fcm_token': token, 'app_version': appVersion});
      (await SharedPreferences.getInstance()).setString(_deviceKey, r['id'] as String);
    } catch (_) {
      // offline: next app start tries again
    }
  }

  /// Before signing out: stop pushes for this account on this phone.
  Future<void> unregister() async {
    if (!_ready) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString(_deviceKey);
      if (id != null) {
        await ref.read(apiClientProvider).delete('/devices/$id').timeout(const Duration(seconds: 4));
        await prefs.remove(_deviceKey);
      }
    } catch (_) {}
    try {
      await FirebaseMessaging.instance.deleteToken(); // the next account gets a fresh token
    } catch (_) {}
  }

  void dispose() {
    _tokenSub?.cancel();
    _msgSub?.cancel();
    _openSub?.cancel();
  }
}

final pushServiceProvider = Provider<PushService>((ref) {
  final s = PushService(ref);
  ref.onDispose(s.dispose);
  return s;
});

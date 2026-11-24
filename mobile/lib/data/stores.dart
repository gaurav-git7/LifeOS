// App state. Two data modes:
// - live: signed in to the LifeOS API. Data comes from the sync engine
//   (offline cache + background push/pull); the assistant, memories,
//   preferences and XP talk to the server.
// - sample: "Explore with sample data" — everything stays on the phone.
// Screens don't care which mode is active.

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../core/theme/colors.dart';
import '../shell/quick_capture_parser.dart';
import 'api/api_client.dart';
import 'models.dart';
import 'seed.dart';
import 'push/push_service.dart';
import 'schedule.dart';
import 'social/social_store.dart';
import 'sync/sync_engine.dart';

const _uuid = Uuid();
String newId() => _uuid.v4();

// =====================================================================
// API, auth & settings
// =====================================================================

final tokenStoreProvider = Provider<TokenStore>((ref) => TokenStore());

final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient(tokens: ref.watch(tokenStoreProvider));
  client.onSessionExpired = () => ref.read(authProvider.notifier).sessionExpired();
  return client;
});

/// The sync engine when signed in to the server, otherwise null (sample mode).
SyncEngine? liveSync(Ref ref) => ref.read(authProvider).live ? ref.read(syncEngineProvider) : null;

enum AuthStatus { unknown, signedOut, signedIn }

class AuthState {
  const AuthState({
    this.status = AuthStatus.signedOut,
    this.onboarded = false,
    this.live = false,
    this.name = 'there',
    this.email = '',
    this.emailVerified = true,
    this.notice,
  });
  final AuthStatus status;
  final bool onboarded;
  final bool live; // signed in to the server (vs. sample data)
  final String name;
  final String email;
  final bool emailVerified;
  final String? notice; // shown on the sign-in screen (e.g. "session expired")

  bool get signedIn => status == AuthStatus.signedIn;

  AuthState copyWith({
    AuthStatus? status,
    bool? onboarded,
    bool? live,
    String? name,
    String? email,
    bool? emailVerified,
    String? notice,
    bool clearNotice = false,
  }) =>
      AuthState(
        status: status ?? this.status,
        onboarded: onboarded ?? this.onboarded,
        live: live ?? this.live,
        name: name ?? this.name,
        email: email ?? this.email,
        emailVerified: emailVerified ?? this.emailVerified,
        notice: clearNotice ? null : (notice ?? this.notice),
      );
}

/// Every provider holding user data — reset when the data mode changes.
List<ProviderOrFamily> get _dataProviders => [
      tasksProvider,
      goalsProvider,
      habitsProvider,
      scheduleProvider,
      learningProvider,
      journalProvider,
      memoriesProvider,
      assistantProvider,
      progressionProvider,
      achievementsProvider,
      prefsProvider,
      reviewsProvider,
      socialProvider,
      syncStatusProvider,
    ];

class AuthNotifier extends Notifier<AuthState> {
  static const _startSignedIn = bool.fromEnvironment('START_SIGNED_IN');
  static const _modeKey = 'lifeos_mode';
  static const _onboardedKey = 'lifeos_onboarded';

  @override
  AuthState build() {
    if (_startSignedIn) return const AuthState(status: AuthStatus.signedIn, onboarded: true, name: 'Gaurav');
    Future.microtask(_restore);
    return const AuthState(status: AuthStatus.unknown);
  }

  ApiClient get _api => ref.read(apiClientProvider);

  /// App start: reopen the last session (works offline from the cache).
  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final onboarded = prefs.getBool(_onboardedKey) ?? false;
      final mode = prefs.getString(_modeKey);
      final hasSession = mode == 'live' && await ref.read(tokenStoreProvider).refresh != null;
      if (!ref.mounted || state.status != AuthStatus.unknown) return; // signed in meanwhile
      if (hasSession) {
        state = AuthState(
          status: AuthStatus.signedIn,
          onboarded: true,
          live: true,
          name: prefs.getString('lifeos_name') ?? 'there',
          email: prefs.getString('lifeos_email') ?? '',
        );
        await _startLive(fromCache: true);
        unawaited(_refreshMe());
        return;
      }
      if (mode == 'sample') {
        state = const AuthState(status: AuthStatus.signedIn, onboarded: true, name: 'Gaurav');
        return;
      }
      state = AuthState(status: AuthStatus.signedOut, onboarded: onboarded);
    } catch (_) {
      if (ref.mounted && state.status == AuthStatus.unknown) state = const AuthState(status: AuthStatus.signedOut);
    }
  }

  Future<void> _saveMode(String? mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_onboardedKey, true);
      if (mode == null) {
        await prefs.remove(_modeKey);
      } else {
        await prefs.setString(_modeKey, mode);
      }
      await prefs.setString('lifeos_name', state.name);
      await prefs.setString('lifeos_email', state.email);
    } catch (_) {}
  }

  void _resetData() {
    for (final p in _dataProviders) {
      ref.invalidate(p);
    }
  }

  Future<void> _startLive({bool fromCache = false}) async {
    _resetData();
    final sync = ref.read(syncEngineProvider);
    if (fromCache) await sync.loadCache();
    sync.publish();
    unawaited(() async {
      await sync.syncNow();
      if (!ref.mounted) return;
      await Future.wait([
        ref.read(prefsProvider.notifier).load(),
        ref.read(memoriesProvider.notifier).load(),
        ref.read(assistantProvider.notifier).load(),
        ref.read(reviewsProvider.notifier).load(),
        ref.read(socialProvider.notifier).load(),
      ]);
    }());
  }

  void _applyUser(Map<String, dynamic> u) {
    state = state.copyWith(
      name: (u['display_name'] as String?) ?? state.name,
      email: (u['email'] as String?) ?? state.email,
      emailVerified: u['email_verified_at'] != null,
    );
  }

  Future<void> _refreshMe() async {
    try {
      _applyUser(await _api.get<Map<String, dynamic>>('/users/me'));
      await _saveMode('live');
    } on ApiException {
      // offline: keep using the cache
    }
  }

  Future<String?> _signedIn(Map<String, dynamic> tokens) async {
    await ref.read(tokenStoreProvider).save(tokens['access_token'] as String, tokens['refresh_token'] as String);
    state = const AuthState(status: AuthStatus.signedIn, onboarded: true, live: true);
    _applyUser(Map<String, dynamic>.from(tokens['user'] as Map));
    await ref.read(syncEngineProvider).clear();
    await _saveMode('live');
    await _startLive();
    return null;
  }

  void completeOnboarding() {
    state = state.copyWith(onboarded: true);
    unawaited(SharedPreferences.getInstance().then((p) => p.setBool(_onboardedKey, true)).catchError((_) => false));
  }

  Future<String?> signIn(String email, String password) async {
    try {
      final r = await _api.post<Map<String, dynamic>>('/auth/login',
          auth: false, data: {'email': email, 'password': password, 'device_label': 'LifeOS Android'});
      return _signedIn(r);
    } on ApiException catch (e) {
      return e.message;
    }
  }

  Future<String?> register(String name, String email, String password, {String? inviteCode}) async {
    try {
      String tz = 'UTC';
      try {
        tz = (await FlutterTimezone.getLocalTimezone().timeout(const Duration(milliseconds: 800))).identifier;
      } catch (_) {}
      final r = await _api.post<Map<String, dynamic>>('/auth/register', auth: false, data: {
        'email': email,
        'password': password,
        'display_name': name,
        'timezone': tz,
        'device_label': 'LifeOS Android',
        if (inviteCode != null && inviteCode.isNotEmpty) 'invite_code': inviteCode,
      });
      return _signedIn(r);
    } on ApiException catch (e) {
      return e.message;
    }
  }

  /// Returns an error message, or null when the email was sent.
  Future<String?> forgotPassword(String email) async {
    try {
      await _api.post<dynamic>('/auth/forgot-password', auth: false, data: {'email': email});
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }

  Future<String?> resendVerification() async {
    try {
      await _api.post<dynamic>('/auth/resend-verification', data: {'email': state.email});
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }

  /// "Explore with sample data" — no account, nothing leaves the phone.
  void useSampleData() {
    _resetData();
    state = const AuthState(status: AuthStatus.signedIn, onboarded: true, name: 'Gaurav');
    unawaited(_saveMode('sample'));
  }

  Future<void> signOut() async {
    if (state.live) {
      await ref.read(pushServiceProvider).unregister(); // no more pushes for this account here
      final tokens = ref.read(tokenStoreProvider);
      final refresh = await tokens.refresh;
      final sync = ref.read(syncEngineProvider);
      // Last chance to send unsynced changes (best effort, don't block on a slow server).
      await sync.push().timeout(const Duration(seconds: 5), onTimeout: () {});
      if (refresh != null) {
        // Revoke this device's refresh token (best effort).
        try {
          await _api.post<dynamic>('/auth/logout', data: {'refresh_token': refresh}).timeout(const Duration(seconds: 4));
        } catch (_) {}
      }
      await tokens.clear();
      await sync.clear();
    }
    state = AuthState(status: AuthStatus.signedOut, onboarded: true, email: state.email);
    await _saveMode(null);
    _resetData();
  }

  /// Returns an error message or null.
  Future<String?> changePassword(String current, String next) async {
    try {
      await _api.post<dynamic>('/auth/change-password', data: {'current_password': current, 'new_password': next});
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }

  /// Ends every session (all phones), including this one. Returns an error message or null.
  Future<String?> signOutEverywhere() async {
    final sync = ref.read(syncEngineProvider);
    await sync.push().timeout(const Duration(seconds: 5), onTimeout: () {});
    await ref.read(pushServiceProvider).unregister();
    try {
      await _api.post<dynamic>('/auth/logout-all');
    } on ApiException catch (e) {
      return e.message;
    }
    await ref.read(tokenStoreProvider).clear();
    await sync.clear();
    state = AuthState(status: AuthStatus.signedOut, onboarded: true, email: state.email);
    await _saveMode(null);
    _resetData();
    return null;
  }

  /// Permanently deletes the account on the server. Returns an error message or null.
  Future<String?> deleteAccount() async {
    if (state.live) {
      try {
        await _api.delete('/users/me');
      } on ApiException catch (e) {
        return e.message;
      }
      await ref.read(tokenStoreProvider).clear();
      await ref.read(syncEngineProvider).clear();
    }
    state = const AuthState(status: AuthStatus.signedOut, onboarded: true);
    await _saveMode(null);
    _resetData();
    return null;
  }

  /// Refresh token rejected (expired, revoked, or "sign out everywhere").
  void sessionExpired() {
    if (!state.live) return;
    unawaited(ref.read(syncEngineProvider).clear());
    state = AuthState(
      status: AuthStatus.signedOut,
      onboarded: true,
      email: state.email,
      notice: 'Your session ended. Please sign in again.',
    );
    unawaited(_saveMode(null));
    _resetData();
  }

  void rename(String name) {
    state = state.copyWith(name: name);
    if (state.live) {
      unawaited(_api.patch<dynamic>('/users/me', data: {'display_name': name}).then<void>((_) {}, onError: (_) {}));
    }
    unawaited(_saveMode(state.live ? 'live' : 'sample'));
  }

  /// For tests / previews.
  @visibleForTesting
  void debugSignIn() => state = state.copyWith(status: AuthStatus.signedIn, onboarded: true, live: false, name: 'Gaurav');
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);

class Prefs {
  const Prefs({
    this.reviewTime = const TimeOfDay(hour: 21, minute: 0),
    this.dailyReview = true,
    this.weeklyReview = true,
    this.notifications = true,
    this.quietHours = true,
    this.aiEnabled = true,
    this.aiMemory = true,
    this.moodAi = false,
    this.journalAi = false,
    this.appLock = false,
    this.journalLock = false,
    this.dailyBudget = 0.10,
    this.studyGoalMinutes = 60,
  });

  final TimeOfDay reviewTime;
  final bool dailyReview;
  final bool weeklyReview;
  final bool notifications;
  final bool quietHours;
  final bool aiEnabled;
  final bool aiMemory;
  final bool moodAi;
  final bool journalAi;
  final bool appLock;
  final bool journalLock;
  final double dailyBudget;
  final int studyGoalMinutes; // daily study target for the Today ring (kept on this phone)

  Prefs copyWith({
    TimeOfDay? reviewTime,
    bool? dailyReview,
    bool? weeklyReview,
    bool? notifications,
    bool? quietHours,
    bool? aiEnabled,
    bool? aiMemory,
    bool? moodAi,
    bool? journalAi,
    bool? appLock,
    bool? journalLock,
    double? dailyBudget,
    int? studyGoalMinutes,
  }) =>
      Prefs(
        reviewTime: reviewTime ?? this.reviewTime,
        dailyReview: dailyReview ?? this.dailyReview,
        weeklyReview: weeklyReview ?? this.weeklyReview,
        notifications: notifications ?? this.notifications,
        quietHours: quietHours ?? this.quietHours,
        aiEnabled: aiEnabled ?? this.aiEnabled,
        aiMemory: aiMemory ?? this.aiMemory,
        moodAi: moodAi ?? this.moodAi,
        journalAi: journalAi ?? this.journalAi,
        appLock: appLock ?? this.appLock,
        journalLock: journalLock ?? this.journalLock,
        dailyBudget: dailyBudget ?? this.dailyBudget,
        studyGoalMinutes: studyGoalMinutes ?? this.studyGoalMinutes,
      );
}

String _hhmm(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';
TimeOfDay? _tod(Object? v) =>
    v is String && v.length >= 5 ? TimeOfDay(hour: int.parse(v.substring(0, 2)), minute: int.parse(v.substring(3, 5))) : null;

class PrefsNotifier extends Notifier<Prefs> {
  static const _studyGoalKey = 'lifeos_study_goal';
  // Locks are about this phone, so they're kept here, not on the server.
  static const _appLockKey = 'lifeos_app_lock';
  static const _journalLockKey = 'lifeos_journal_lock';

  @override
  Prefs build() {
    Future.microtask(() async {
      try {
        final p = await SharedPreferences.getInstance();
        if (!ref.mounted) return;
        state = state.copyWith(
          studyGoalMinutes: p.getInt(_studyGoalKey),
          appLock: p.getBool(_appLockKey),
          journalLock: p.getBool(_journalLockKey),
        );
      } catch (_) {}
    });
    return const Prefs();
  }

  static Map<String, Object?> _toApi(Prefs p) => {
        'daily_review_enabled': p.dailyReview,
        'daily_review_time': _hhmm(p.reviewTime),
        'weekly_review_enabled': p.weeklyReview,
        'notifications_enabled': p.notifications,
        'quiet_hours_start': p.quietHours ? '22:30:00' : null,
        'quiet_hours_end': p.quietHours ? '07:00:00' : null,
        'ai_enabled': p.aiEnabled,
        'ai_memory_enabled': p.aiMemory,
        'mood_ai_enabled': p.moodAi,
        'journal_ai_enabled': p.journalAi,
        'ai_daily_budget_usd': p.dailyBudget,
      };

  void update(Prefs Function(Prefs) f) {
    final before = _toApi(state);
    final goalBefore = state.studyGoalMinutes;
    state = f(state);
    final locks = (state.appLock, state.journalLock);
    unawaited(SharedPreferences.getInstance()
        .then((p) async {
          await p.setBool(_appLockKey, locks.$1);
          await p.setBool(_journalLockKey, locks.$2);
        })
        .then<void>((_) {}, onError: (_) {}));
    if (state.studyGoalMinutes != goalBefore) {
      final v = state.studyGoalMinutes;
      unawaited(SharedPreferences.getInstance().then((p) => p.setInt(_studyGoalKey, v)).then<void>((_) {}, onError: (_) {}));
    }
    if (liveSync(ref) == null) return;
    final after = _toApi(state);
    final diff = {for (final e in after.entries) if (before[e.key] != e.value) e.key: e.value};
    if (diff.isEmpty) return;
    unawaited(ref.read(apiClientProvider).patch<dynamic>('/users/me/preferences', data: diff).then<void>((_) {}, onError: (_) {}));
  }

  /// Live mode: read preferences from the server.
  Future<void> load() async {
    try {
      final r = await ref.read(apiClientProvider).get<Map<String, dynamic>>('/users/me/preferences');
      if (!ref.mounted) return;
      state = Prefs(
        reviewTime: _tod(r['daily_review_time']) ?? state.reviewTime,
        dailyReview: r['daily_review_enabled'] as bool? ?? true,
        weeklyReview: r['weekly_review_enabled'] as bool? ?? true,
        notifications: r['notifications_enabled'] as bool? ?? true,
        quietHours: r['quiet_hours_start'] != null,
        aiEnabled: r['ai_enabled'] as bool? ?? true,
        aiMemory: r['ai_memory_enabled'] as bool? ?? true,
        moodAi: r['mood_ai_enabled'] as bool? ?? false,
        journalAi: r['journal_ai_enabled'] as bool? ?? false,
        appLock: state.appLock,
        journalLock: state.journalLock,
        studyGoalMinutes: state.studyGoalMinutes,
        dailyBudget: (r['ai_daily_budget_usd'] as num?)?.toDouble() ?? state.dailyBudget,
      );
    } on ApiException {
      // keep defaults
    }
  }
}

final prefsProvider = NotifierProvider<PrefsNotifier, Prefs>(PrefsNotifier.new);

// =====================================================================
// Progression (XP / levels) — same rules as backend progression/service.py
// =====================================================================

int xpForNext(int level) => (100 * math.pow(level, 1.5)).round();

class LevelInfo {
  const LevelInfo(this.level, this.into, this.forNext, this.rank);
  final int level;
  final int into;
  final int forNext;
  final String rank;
  double get progress => forNext == 0 ? 0 : into / forNext;
}

LevelInfo levelInfo(int total) {
  var level = 1, rest = total;
  while (rest >= xpForNext(level)) {
    rest -= xpForNext(level);
    level++;
  }
  final rank = level >= 30
      ? 'Architect'
      : level >= 20
          ? 'Master'
          : level >= 15
              ? 'Expert'
              : level >= 10
                  ? 'Specialist'
                  : level >= 5
                      ? 'Adept'
                      : 'Initiate';
  return LevelInfo(level, rest, xpForNext(level), rank);
}

class Progression {
  const Progression({required this.totalXp, required this.todayXp, this.lastGain = 0, this.gainTick = 0, this.levelUps = 0});
  final int totalXp;
  final int todayXp;
  final int lastGain;
  final int gainTick; // increments on every gain (drives "+XP" animations)
  final int levelUps; // increments on level-up (drives the level-up overlay)
  LevelInfo get info => levelInfo(totalXp);
}

class ProgressionNotifier extends Notifier<Progression> {
  @override
  Progression build() =>
      ref.read(authProvider).live ? const Progression(totalXp: 0, todayXp: 0) : const Progression(totalXp: 5531, todayXp: 120);

  /// Live mode: the server's XP ledger is the source of truth. Local awards only
  /// drive instant feedback; this corrects the totals afterwards.
  Future<void> refreshFromServer() async {
    if (!ref.read(authProvider).live) return;
    try {
      final api = ref.read(apiClientProvider);
      final results = await Future.wait([
        api.get<Map<String, dynamic>>('/progression'),
        api.get<List<dynamic>>('/progression/xp-history', query: {'limit': 200}),
      ]);
      if (!ref.mounted) return;
      final p = results[0] as Map<String, dynamic>;
      final history = (results[1] as List).cast<Map<String, dynamic>>();
      final today = dateOnly(DateTime.now());
      final todayXp = history
          .where((h) => sameDay(DateTime.parse(h['created_at'] as String).toLocal(), today))
          .fold<int>(0, (a, h) => a + (h['amount'] as int));
      final total = p['total_xp'] as int;
      final before = state.info.level;
      state = Progression(
        totalXp: total,
        todayXp: math.max(0, todayXp),
        gainTick: state.gainTick,
        levelUps: state.levelUps + (levelInfo(total).level > before && state.totalXp > 0 ? 1 : 0),
      );
      ref.read(achievementsProvider.notifier).fromServer((p['achievements'] as List).cast<Map<String, dynamic>>());
    } on ApiException {
      // offline
    }
  }

  void award(int xp) {
    if (xp <= 0) return;
    final before = state.info.level;
    final total = state.totalXp + xp;
    state = Progression(
      totalXp: total,
      todayXp: state.todayXp + xp,
      lastGain: xp,
      gainTick: state.gainTick + 1,
      levelUps: state.levelUps + (levelInfo(total).level > before ? 1 : 0),
    );
  }

  void revoke(int xp) => state = Progression(
        totalXp: math.max(0, state.totalXp - xp),
        todayXp: math.max(0, state.todayXp - xp),
        gainTick: state.gainTick,
        levelUps: state.levelUps,
      );
}

final progressionProvider = NotifierProvider<ProgressionNotifier, Progression>(ProgressionNotifier.new);

// =====================================================================
// Tasks, goals, habits, schedule
// =====================================================================

class TasksNotifier extends Notifier<List<Task>> {
  @override
  List<Task> build() => ref.read(authProvider).live ? const [] : Seed.tasks();

  void replaceAll(List<Task> tasks) => state = tasks;

  Task? byId(String id) => state.where((t) => t.id == id).firstOrNull;

  void add(Task t) {
    state = [...state, t];
    liveSync(ref)?.saveTask(t);
  }

  void update(Task t) {
    final before = byId(t.id);
    state = [for (final x in state) x.id == t.id ? t : x];
    liveSync(ref)?.saveTask(t, before: before);
  }

  void delete(String id) {
    final t = byId(id);
    state = state.where((t) => t.id != id).toList();
    final s = liveSync(ref);
    if (s != null && t != null) {
      for (final sub in t.subtasks) {
        s.queue('tasks', sub.id, const {}, delete: true);
      }
      s.queue('tasks', id, const {}, delete: true);
    }
  }

  /// Returns the XP awarded (0 when un-completing).
  int toggle(String id) {
    final t = byId(id);
    if (t == null) return 0;
    final xp = ref.read(progressionProvider.notifier);
    if (t.done) {
      update(t.copyWith(done: false, clearCompleted: true));
      xp.revoke(t.priority.xp);
      return 0;
    }
    update(t.copyWith(done: true, completedAt: DateTime.now()));
    xp.award(t.priority.xp);
    // Repeating task: the next one appears (the server does this in live mode).
    final next = t.due == null ? null : t.repeat.nextAfter(t.due!);
    if (next != null && liveSync(ref) == null) {
      add(Task(
        id: newId(),
        title: t.title,
        description: t.description,
        priority: t.priority,
        due: next,
        hasTime: t.hasTime,
        estimatedMinutes: t.estimatedMinutes,
        goalId: t.goalId,
        tags: t.tags,
        repeat: t.repeat,
      ));
    }
    return t.priority.xp;
  }

  void toggleSubtask(String taskId, String subId) {
    final t = byId(taskId);
    if (t == null) return;
    update(t.copyWith(subtasks: [for (final s in t.subtasks) s.id == subId ? s.copyWith(done: !s.done) : s]));
  }

  void reschedule(String id, DateTime due, {bool hasTime = false}) {
    final t = byId(id);
    if (t != null) update(t.copyWith(due: due, hasTime: hasTime));
  }
}

final tasksProvider = NotifierProvider<TasksNotifier, List<Task>>(TasksNotifier.new);

class GoalsNotifier extends Notifier<List<Goal>> {
  @override
  List<Goal> build() => ref.read(authProvider).live ? const [] : Seed.goals();

  void replaceAll(List<Goal> goals) => state = goals;

  void add(Goal g) {
    state = [...state, g];
    final s = liveSync(ref);
    if (s == null) return;
    s.queue('goals', g.id, {
      'title': g.title,
      'category': g.category.toLowerCase(),
      'progress_type': g.progressType.name,
      'target_value': g.target,
      'current_value': g.current,
      'unit': g.unit,
      'target_date': g.targetDate == null ? null : dateStr(g.targetDate!),
    });
    for (final (i, m) in g.milestones.indexed) {
      s.saveMilestone(g.id, m, i);
    }
  }

  void remove(String id) {
    state = state.where((g) => g.id != id).toList();
    liveSync(ref)?.queue('goals', id, const {}, delete: true);
  }

  void addMilestone(String goalId, Milestone m) {
    final count = state.where((g) => g.id == goalId).firstOrNull?.milestones.length ?? 0;
    state = [for (final g in state) g.id == goalId ? g.copyWith(milestones: [...g.milestones, m]) : g];
    liveSync(ref)?.saveMilestone(goalId, m, count);
  }

  void toggleMilestone(String goalId, String milestoneId) {
    state = [
      for (final g in state)
        if (g.id == goalId)
          g.copyWith(milestones: [
            for (final m in g.milestones)
              if (m.id == milestoneId) () {
                if (!m.done) ref.read(progressionProvider.notifier).award(100);
                liveSync(ref)?.queue('goal_milestones', m.id, {'completed_at': m.done ? null : utcIso(DateTime.now())});
                return m.copyWith(done: !m.done);
              }() else m,
          ])
        else
          g,
    ];
  }

  void setCurrent(String goalId, double value) {
    state = [for (final g in state) g.id == goalId ? g.copyWith(current: value) : g];
    liveSync(ref)?.queue('goals', goalId, {'current_value': value});
  }
}

final goalsProvider = NotifierProvider<GoalsNotifier, List<Goal>>(GoalsNotifier.new);

/// 0..1 — same rules as backend goals/router.py goal_progress().
double goalProgress(Goal g, List<Task> tasks) {
  if (g.completed) return 1;
  switch (g.progressType) {
    case GoalProgressType.numeric:
      return (g.target ?? 0) == 0 ? 0 : ((g.current ?? 0) / g.target!).clamp(0, 1).toDouble();
    case GoalProgressType.milestones:
      return g.milestones.isEmpty ? 0 : g.milestones.where((m) => m.done).length / g.milestones.length;
    case GoalProgressType.tasks:
      // Milestones and linked tasks both count, so a goal never shows 0% while
      // milestones are ticked.
      final linked = tasks.where((t) => t.goalId == g.id).toList();
      final total = linked.length + g.milestones.length;
      if (total == 0) return 0;
      final done = linked.where((t) => t.done).length + g.milestones.where((m) => m.done).length;
      return done / total;
  }
}

class HabitsNotifier extends Notifier<List<Habit>> {
  @override
  List<Habit> build() => ref.read(authProvider).live ? const [] : Seed.habits();

  void replaceAll(List<Habit> habits) => state = habits;

  void add(Habit h) {
    state = [...state, h];
    liveSync(ref)?.queue('habits', h.id, {
      'title': h.title,
      'reminder_time': h.reminder == null ? null : _hhmm(h.reminder!),
      'recurrence_rule': h.schedule.toRRule() ?? 'FREQ=DAILY',
      'target_per_period': h.schedule.target,
      'visibility': h.shared ? 'friends' : 'private',
    });
  }

  void setShared(String id, bool shared) {
    state = [for (final h in state) h.id == id ? h.copyWith(shared: shared) : h];
    liveSync(ref)?.queue('habits', id, {'visibility': shared ? 'friends' : 'private'});
  }

  void setSchedule(String id, Schedule s) {
    state = [for (final h in state) h.id == id ? h.copyWith(schedule: s) : h];
    liveSync(ref)?.queue('habits', id, {'recurrence_rule': s.toRRule() ?? 'FREQ=DAILY', 'target_per_period': s.target});
  }

  /// null clears the reminder.
  void setReminder(String id, TimeOfDay? time) {
    state = [for (final h in state) h.id == id ? h.copyWith(reminder: time, clearReminder: time == null) : h];
    liveSync(ref)?.queue('habits', id, {'reminder_time': time == null ? null : _hhmm(time)});
  }

  void toggle(String id, [DateTime? day]) {
    final d = dateOnly(day ?? DateTime.now());
    state = [
      for (final h in state)
        if (h.id == id) () {
          final days = {...h.doneDays};
          final done = !days.remove(d);
          if (done) {
            days.add(d);
            ref.read(progressionProvider.notifier).award(5);
          } else {
            ref.read(progressionProvider.notifier).revoke(5);
          }
          final s = liveSync(ref);
          if (s != null) {
            // Habit logs are keyed by (habit, day) on the server; last write wins.
            s.queue('habit_logs', s.habitLogId(id, d) ?? newId(),
                {'habit_id': id, 'log_date': dateStr(d), 'status': done ? 'done' : 'skipped'},
                sendBase: false);
          }
          return h.copyWith(doneDays: days);
        }() else h,
    ];
  }
}

final habitsProvider = NotifierProvider<HabitsNotifier, List<Habit>>(HabitsNotifier.new);

class ScheduleNotifier extends Notifier<List<ScheduleBlock>> {
  @override
  List<ScheduleBlock> build() => ref.read(authProvider).live ? const [] : Seed.schedule();

  void replaceAll(List<ScheduleBlock> blocks) => state = blocks;

  void add(ScheduleBlock b) {
    state = [...state, b]..sort((a, b) => a.start.compareTo(b.start));
    liveSync(ref)?.queue('schedule_blocks', b.id, {
      'title': b.title,
      'start_at': utcIso(b.start),
      'end_at': utcIso(b.end),
      'block_type': SyncEngine.blockTypeName(b.type),
    });
  }

  void remove(String id) {
    state = state.where((b) => b.id != id).toList();
    liveSync(ref)?.queue('schedule_blocks', id, const {}, delete: true);
  }
}

final scheduleProvider = NotifierProvider<ScheduleNotifier, List<ScheduleBlock>>(ScheduleNotifier.new);

// =====================================================================
// Growth
// =====================================================================

class LearningState {
  const LearningState({required this.paths, required this.skills, required this.sessions, required this.projects});
  final List<LearningPath> paths;
  final List<Skill> skills;
  final List<StudySession> sessions;
  final List<Project> projects;

  Skill? skill(String? id) => skills.where((s) => s.id == id).firstOrNull;

  int minutesOn(DateTime day) => sessions.where((s) => sameDay(s.start, day)).fold(0, (a, s) => a + s.minutes);

  LearningState copyWith({List<LearningPath>? paths, List<Skill>? skills, List<StudySession>? sessions, List<Project>? projects}) =>
      LearningState(
        paths: paths ?? this.paths,
        skills: skills ?? this.skills,
        sessions: sessions ?? this.sessions,
        projects: projects ?? this.projects,
      );
}

class LearningNotifier extends Notifier<LearningState> {
  static const revisionIntervals = [1, 3, 7, 21];

  @override
  LearningState build() => ref.read(authProvider).live
      ? const LearningState(paths: [], skills: [], sessions: [], projects: [])
      : LearningState(paths: Seed.paths(), skills: Seed.skills(), sessions: Seed.sessions(), projects: Seed.projects());

  void replaceAll(LearningState s) => state = s;

  void _updateTopic(String pathId, String topicId, Topic Function(Topic) f) {
    state = state.copyWith(paths: [
      for (final p in state.paths)
        p.id == pathId ? p.copyWith(topics: [for (final t in p.topics) t.id == topicId ? f(t) : t]) : p,
    ]);
  }

  void _skillXp(String? skillId, int xp) {
    if (skillId == null) return;
    state = state.copyWith(skills: [for (final s in state.skills) s.id == skillId ? s.copyWith(xp: s.xp + xp) : s]);
  }

  void completeTopic(String pathId, String topicId) {
    final path = state.paths.firstWhere((p) => p.id == pathId);
    final topic = path.topics.firstWhere((t) => t.id == topicId);
    if (topic.status == TopicStatus.done) return;
    _updateTopic(pathId, topicId, (t) => t.copyWith(
          status: TopicStatus.done,
          nextRevision: dateOnly(DateTime.now()).add(Duration(days: revisionIntervals.first)),
        ));
    ref.read(progressionProvider.notifier).award(topic.difficulty.xp);
    _skillXp(path.skillId, topic.difficulty.xp);
    liveSync(ref)?.callAndSync((api) => api.post<dynamic>('/learning/topics/$topicId/complete'));
  }

  void startTopic(String pathId, String topicId) {
    _updateTopic(pathId, topicId, (t) => t.status == TopicStatus.notStarted ? t.copyWith(status: TopicStatus.inProgress) : t);
    liveSync(ref)?.queue('learning_topics', topicId, {'status': 'in_progress'});
  }

  void reviseTopic(String pathId, String topicId) {
    liveSync(ref)?.callAndSync((api) => api.post<dynamic>('/learning/topics/$topicId/revise'));
    _updateTopic(pathId, topicId, (t) {
      final n = t.revisionCount + 1;
      final interval = revisionIntervals[math.min(n, revisionIntervals.length - 1)];
      return t.copyWith(revisionCount: n, nextRevision: dateOnly(DateTime.now()).add(Duration(days: interval)));
    });
    ref.read(progressionProvider.notifier).award(15);
  }

  /// Records a study session (e.g. from the focus timer). XP: 1/min, max 180/day.
  int addSession(StudySession s) {
    final already = state.minutesOn(s.start);
    final xp = math.max(0, math.min(s.minutes, 180 - already));
    state = state.copyWith(sessions: [s, ...state.sessions]);
    if (s.skillId != null) {
      state = state.copyWith(skills: [
        for (final k in state.skills)
          if (k.id == s.skillId)
            k.copyWith(xp: k.xp + xp, weekMinutes: [...k.weekMinutes.skip(1), k.weekMinutes.last + s.minutes])
          else
            k,
      ]);
    }
    if (s.topicId != null) {
      for (final p in state.paths) {
        if (p.topics.any((t) => t.id == s.topicId)) {
          _updateTopic(p.id, s.topicId!, (t) => t.copyWith(
                sessions: t.sessions + 1,
                status: t.status == TopicStatus.notStarted ? TopicStatus.inProgress : t.status,
              ));
        }
      }
    }
    ref.read(progressionProvider.notifier).award(xp);
    liveSync(ref)?.queue('study_sessions', s.id, {
      'skill_id': s.skillId,
      'topic_id': s.topicId,
      'started_at': utcIso(s.start),
      'ended_at': utcIso(s.start.add(Duration(minutes: s.minutes))),
      'duration_minutes': s.minutes,
      'problems_solved': s.problems == 0 ? null : s.problems,
      'notes': s.label,
      'source': 'focus_timer',
    });
    return xp;
  }

  void addPath(LearningPath p) {
    state = state.copyWith(paths: [...state.paths, p]);
    final s = liveSync(ref);
    if (s == null) return;
    s.queue('learning_paths', p.id, {
      'title': p.title,
      'target_date': p.targetDate == null ? null : dateStr(p.targetDate!),
    });
    for (final (i, t) in p.topics.indexed) {
      s.saveTopic(p.id, p.skillId, t, i);
    }
  }

  void removePath(String id) {
    state = state.copyWith(paths: state.paths.where((p) => p.id != id).toList());
    liveSync(ref)?.queue('learning_paths', id, const {}, delete: true);
  }

  void addTopic(String pathId, Topic t) {
    final path = state.paths.where((p) => p.id == pathId).firstOrNull;
    state = state.copyWith(paths: [
      for (final p in state.paths) p.id == pathId ? p.copyWith(topics: [...p.topics, t]) : p,
    ]);
    liveSync(ref)?.saveTopic(pathId, path?.skillId, t, path?.topics.length ?? 0);
  }

  void addSkill(Skill s) {
    state = state.copyWith(skills: [...state.skills, s]);
    liveSync(ref)?.queue('skills', s.id, {'name': s.name, 'current_level': s.level, 'target_level': s.target});
  }

  void removeSkill(String id) {
    state = state.copyWith(skills: state.skills.where((s) => s.id != id).toList());
    liveSync(ref)?.queue('skills', id, const {}, delete: true);
  }

  void addProject(Project p) {
    state = state.copyWith(projects: [...state.projects, p]);
    final s = liveSync(ref);
    if (s == null) return;
    s.queue('projects', p.id, {
      'name': p.name,
      'description': p.description,
      'tech_stack': p.stack,
      'target_date': p.deadline == null ? null : dateStr(p.deadline!),
    });
    for (final (i, m) in p.milestones.indexed) {
      s.saveProjectMilestone(p.id, m, i);
    }
  }

  void removeProject(String id) {
    final p = state.projects.where((p) => p.id == id).firstOrNull;
    state = state.copyWith(projects: state.projects.where((p) => p.id != id).toList());
    final s = liveSync(ref);
    if (s == null) return;
    for (final m in p?.milestones ?? const <Milestone>[]) {
      s.queue('tasks', m.id, const {}, delete: true);
    }
    s.queue('projects', id, const {}, delete: true);
  }

  void addProjectMilestone(String projectId, Milestone m) {
    final count = state.projects.where((p) => p.id == projectId).firstOrNull?.milestones.length ?? 0;
    state = state.copyWith(projects: [
      for (final p in state.projects)
        if (p.id == projectId) () {
          final ms = [...p.milestones, m];
          return p.copyWith(milestones: ms, progress: ms.where((x) => x.done).length / ms.length);
        }() else p,
    ]);
    liveSync(ref)?.saveProjectMilestone(projectId, m, count);
  }

  void toggleProjectMilestone(String projectId, String milestoneId) {
    state = state.copyWith(projects: [
      for (final p in state.projects)
        if (p.id == projectId) () {
          final ms = [for (final m in p.milestones) m.id == milestoneId ? m.copyWith(done: !m.done) : m];
          final done = ms.where((m) => m.done).length;
          final was = p.milestones.firstWhere((m) => m.id == milestoneId).done;
          if (!was) ref.read(progressionProvider.notifier).award(80);
          liveSync(ref)?.queue('tasks', milestoneId, {'status': was ? 'todo' : 'done'});
          return p.copyWith(milestones: ms, progress: ms.isEmpty ? p.progress : done / ms.length);
        }() else p,
    ]);
  }
}

final learningProvider = NotifierProvider<LearningNotifier, LearningState>(LearningNotifier.new);

class AchievementsNotifier extends Notifier<List<Achievement>> {
  @override
  List<Achievement> build() {
    final catalog = Seed.achievements();
    return ref.read(authProvider).live
        ? [
            for (final a in catalog)
              Achievement(code: a.code, title: a.title, description: a.description, icon: a.icon, color: a.color),
          ]
        : catalog;
  }

  void fromServer(List<Map<String, dynamic>> rows) {
    final looks = {for (final a in Seed.achievements()) a.code: a};
    state = [
      for (final r in rows)
        Achievement(
          code: r['code'] as String,
          title: r['title'] as String,
          description: r['description'] as String,
          icon: looks[r['code']]?.icon ?? LucideIcons.award,
          color: looks[r['code']]?.color ?? LifeColors.amber,
          unlockedAt: r['unlocked_at'] == null ? null : DateTime.parse(r['unlocked_at'] as String).toLocal(),
        ),
    ];
  }
}

final achievementsProvider = NotifierProvider<AchievementsNotifier, List<Achievement>>(AchievementsNotifier.new);

// =====================================================================
// Journal & mood
// =====================================================================

class JournalState {
  const JournalState({required this.entries, required this.moods});
  final List<JournalEntry> entries;
  final List<MoodEntry> moods;

  MoodEntry? moodOn(DateTime day) => moods.where((m) => sameDay(m.day, day)).firstOrNull;

  JournalState copyWith({List<JournalEntry>? entries, List<MoodEntry>? moods}) =>
      JournalState(entries: entries ?? this.entries, moods: moods ?? this.moods);
}

class JournalNotifier extends Notifier<JournalState> {
  @override
  JournalState build() => ref.read(authProvider).live
      ? const JournalState(entries: [], moods: [])
      : JournalState(entries: Seed.journal(), moods: Seed.moods());

  void replaceAll(JournalState s) => state = s;

  void saveMood(MoodEntry m) {
    final existing = state.moodOn(m.day);
    state = state.copyWith(moods: [m, ...state.moods.where((x) => !sameDay(x.day, m.day))]);
    if (existing == null) ref.read(progressionProvider.notifier).award(5);
    final s = liveSync(ref);
    if (s == null) return;
    final data = <String, dynamic>{
      'mood': m.mood + 1,
      'energy': m.energy.clamp(1, 10),
      'motivation': m.motivation.clamp(1, 10),
      'tags': m.tags,
    };
    final id = s.moodIdFor(m.day);
    if (id != null) {
      s.queue('mood_entries', id, data);
    } else {
      final now = DateTime.now();
      final at = sameDay(m.day, now) ? now : m.day.add(const Duration(hours: 12));
      s.queue('mood_entries', newId(), {...data, 'recorded_at': utcIso(at)});
    }
  }

  void upsertEntry(JournalEntry e) {
    final exists = state.entries.any((x) => x.id == e.id);
    state = state.copyWith(entries: exists ? [for (final x in state.entries) x.id == e.id ? e : x] : [e, ...state.entries]);
    if (!exists && !state.entries.any((x) => x.id != e.id && sameDay(x.day, e.day))) {
      ref.read(progressionProvider.notifier).award(5);
    }
    liveSync(ref)?.queue('journal_entries', e.id, {
      'entry_date': dateStr(e.day),
      'title': e.title,
      'content': e.content,
      'ai_allowed': e.aiAllowed,
    });
  }

  void deleteEntry(String id) {
    state = state.copyWith(entries: state.entries.where((e) => e.id != id).toList());
    liveSync(ref)?.queue('journal_entries', id, const {}, delete: true);
  }
}

final journalProvider = NotifierProvider<JournalNotifier, JournalState>(JournalNotifier.new);

// =====================================================================
// Memories
// =====================================================================

class MemoriesNotifier extends Notifier<List<Memory>> {
  @override
  List<Memory> build() => ref.read(authProvider).live ? const [] : Seed.memories();

  bool get _live => ref.read(authProvider).live;
  ApiClient get _api => ref.read(apiClientProvider);

  static Memory fromApi(Map<String, dynamic> r) => Memory(
        id: r['id'] as String,
        type: MemoryType.values.asNameMap()[r['memory_type']] ?? MemoryType.preference,
        content: r['content'] as String,
        proposed: r['status'] == 'proposed',
      );

  Future<void> load() async {
    if (!_live) return;
    try {
      final rows = await _api.get<List<dynamic>>('/agent/memories');
      if (!ref.mounted) return;
      final all = [for (final r in rows) fromApi(Map<String, dynamic>.from(r as Map))];
      state = [...all.where((m) => m.proposed), ...all.where((m) => !m.proposed)];
    } on ApiException {
      // offline
    }
  }

  void _bg(Future<dynamic> Function() f) => unawaited(f().then<void>((_) {}, onError: (_) => load()));

  void add(Memory m) {
    state = [m, ...state];
    if (_live) {
      _bg(() async {
        final r = await _api.post<Map<String, dynamic>>('/agent/memories', data: {'memory_type': m.type.name, 'content': m.content});
        state = [for (final x in state) x.id == m.id ? fromApi(r) : x];
      });
    }
  }

  void keep(String id) {
    state = [for (final m in state) m.id == id ? m.copyWith(proposed: false) : m];
    if (_live) _bg(() => _api.post<dynamic>('/agent/memories/$id/accept'));
  }

  void edit(String id, String content) {
    state = [for (final m in state) m.id == id ? m.copyWith(content: content) : m];
    if (_live) _bg(() => _api.patch<dynamic>('/agent/memories/$id', data: {'content': content}));
  }

  void remove(String id) {
    state = state.where((m) => m.id != id).toList();
    if (_live) _bg(() => _api.delete('/agent/memories/$id'));
  }

  /// Suggestions that arrive with a chat reply.
  void addSuggested(List<Memory> ms) => state = [...ms.where((m) => !state.any((x) => x.id == m.id)), ...state];
}

final memoriesProvider = NotifierProvider<MemoriesNotifier, List<Memory>>(MemoriesNotifier.new);

// =====================================================================
// Assistant (mock agent: canned replies + streaming + proposals)
// =====================================================================

class AssistantState {
  const AssistantState({required this.messages, required this.proposals, this.thinking = false});
  final List<ChatMessage> messages;
  final List<Proposal> proposals;
  final bool thinking;

  List<Proposal> get pending => proposals.where((p) => p.status == ProposalStatus.pending).toList();
  Proposal? proposal(String id) => proposals.where((p) => p.id == id).firstOrNull;

  AssistantState copyWith({List<ChatMessage>? messages, List<Proposal>? proposals, bool? thinking}) => AssistantState(
        messages: messages ?? this.messages,
        proposals: proposals ?? this.proposals,
        thinking: thinking ?? this.thinking,
      );
}

class AssistantNotifier extends Notifier<AssistantState> {
  Timer? _stream;
  String? _conversationId;
  static const _proposalsCacheKey = 'lifeos_cached_proposals';

  @override
  AssistantState build() {
    ref.onDispose(() => _stream?.cancel());
    if (ref.read(authProvider).live) {
      Future.microtask(_restoreCachedProposals);
      return const AssistantState(messages: [], proposals: []);
    }
    return AssistantState(messages: Seed.messages(), proposals: Seed.proposals());
  }

  Future<void> _restoreCachedProposals() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_proposalsCacheKey);
      if (raw == null || !ref.mounted) return;
      final list = jsonDecode(raw) as List<dynamic>;
      final proposals = [for (final p in list) fromApi(Map<String, dynamic>.from(p as Map))];
      if (state.proposals.isEmpty) {
        state = state.copyWith(proposals: proposals);
      }
    } catch (_) {}
  }

  void _saveCachedProposals(List<dynamic> rawPending) {
    unawaited(SharedPreferences.getInstance().then((p) {
      p.setString(_proposalsCacheKey, jsonEncode(rawPending));
    }).catchError((_) {}));
  }

  bool get _live => ref.read(authProvider).live;
  ApiClient get _api => ref.read(apiClientProvider);

  static final _fmt = DateFormat('EEE d MMM');
  static final _time = DateFormat('HH:mm');

  /// Server proposal → card. "changes" are derived from the payload.
  static Proposal fromApi(Map<String, dynamic> r) {
    final pl = Map<String, Object?>.from(r['payload'] as Map);
    String day(Object? v) => _fmt.format(DateTime.parse(v! as String).toLocal());
    String dayTime(Object? v) => '${day(v)} · ${_time.format(DateTime.parse(v! as String).toLocal())}';
    final changes = <ProposalChange>[
      if (pl['due_at'] != null) ProposalChange('Due', dayTime(pl['due_at'])),
      if (pl['due_at'] == null && pl['due_date'] != null) ProposalChange('Due', day(pl['due_date'])),
      if (pl['start_at'] != null && pl['end_at'] != null)
        ProposalChange('When', '${dayTime(pl['start_at'])}–${_time.format(DateTime.parse(pl['end_at']! as String).toLocal())}'),
      if (pl['remind_at'] != null) ProposalChange('When', dayTime(pl['remind_at'])),
      if (pl['priority'] != null) ProposalChange('Priority', categoryCase(pl['priority']! as String)),
      if (pl['estimated_minutes'] != null) ProposalChange('Estimate', '${pl['estimated_minutes']} min'),
      if (pl['target_date'] != null) ProposalChange('Target', day(pl['target_date'])),
      if (pl['category'] != null) ProposalChange('Category', categoryCase(pl['category']! as String)),
      if (pl['reminder_time'] != null) ProposalChange('Reminder', (pl['reminder_time']! as String).substring(0, 5)),
      for (final (i, t) in ((pl['topics'] as List?) ?? const []).indexed)
        ProposalChange('Topic ${i + 1}', (t as Map)['title'] as String),
      for (final it in ((pl['items'] as List?) ?? const []))
        ProposalChange('New date', (it as Map)['due_at'] != null ? dayTime(it['due_at']) : day(it['due_date'])),
    ];
    return Proposal(
      id: r['id'] as String,
      groupId: r['group_id'] as String?,
      actionType: r['action_type'] as String,
      summary: r['summary'] as String,
      reason: (r['reason'] as String?) ?? '',
      origin: r['origin'] as String,
      payload: pl,
      payloadHash: r['payload_hash'] as String,
      status: switch (r['status']) {
        'executed' || 'approved' => ProposalStatus.executed,
        'rejected' || 'expired' || 'failed' => ProposalStatus.rejected,
        _ => ProposalStatus.pending,
      },
      changes: changes,
    );
  }

  static String categoryCase(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).replaceAll('_', ' ');

  /// Live mode: pending suggestions + the latest conversation.
  Future<void> load() async {
    if (!_live) return;
    try {
      final pending = await _api.get<List<dynamic>>('/agent/proposals');
      _saveCachedProposals(pending);
      if (!ref.mounted) return;
      final convs = await _api.get<List<dynamic>>('/agent/conversations', query: {'limit': 1});
      if (!ref.mounted) return;
      var messages = <ChatMessage>[];
      if (convs.isNotEmpty) {
        _conversationId = (convs.first as Map)['id'] as String;
        final rows = await _api.get<List<dynamic>>('/agent/conversations/$_conversationId/messages', query: {'limit': 60});
        if (!ref.mounted) return;
        messages = [
          for (final m in rows.cast<Map<String, dynamic>>())
            if (m['role'] == 'user' || m['role'] == 'assistant')
              ChatMessage(
                id: m['id'] as String,
                role: m['role'] == 'user' ? ChatRole.user : ChatRole.assistant,
                text: (m['content'] as String?) ?? '',
              ),
        ];
      }
      state = state.copyWith(
        messages: state.thinking ? state.messages : messages,
        proposals: [for (final p in pending) fromApi(Map<String, dynamic>.from(p as Map))],
      );
    } on ApiException {
      // offline
    }
  }

  void _say(String text, {List<String> proposalIds = const []}) {
    final msg = ChatMessage(id: newId(), role: ChatRole.assistant, text: '', streaming: true, proposalIds: proposalIds);
    state = state.copyWith(messages: [...state.messages, msg], thinking: false);
    final words = text.split(' ');
    var i = 0;
    _stream?.cancel();
    _stream = Timer.periodic(const Duration(milliseconds: 30), (t) {
      i++;
      final done = i >= words.length;
      state = state.copyWith(messages: [
        for (final m in state.messages) m.id == msg.id ? m.copyWith(text: words.take(i).join(' '), streaming: !done) : m,
      ]);
      if (done) t.cancel();
    });
  }

  Future<void> _sendLive(String text) async {
    try {
      // Let the assistant see the latest local changes first.
      await ref.read(syncEngineProvider).push();
      final r = await _api.post<Map<String, dynamic>>('/agent/chat', data: {
        'message': text,
        'conversation_id': ?_conversationId,
      });
      _conversationId = r['conversation_id'] as String?;
      final proposals = [for (final p in (r['proposals'] as List)) fromApi(Map<String, dynamic>.from(p as Map))];
      final memories = [
        for (final m in (r['memory_suggestions'] as List)) MemoriesNotifier.fromApi(Map<String, dynamic>.from(m as Map)),
      ];
      if (memories.isNotEmpty) ref.read(memoriesProvider.notifier).addSuggested(memories);
      state = state.copyWith(proposals: [...state.proposals, ...proposals]);
      final follow = r['follow_up_question'] as String?;
      _say([r['message'] as String, ?follow].join('\n\n'), proposalIds: [for (final p in proposals) p.id]);
    } on ApiException catch (e) {
      _say(e.isNetwork ? 'I can’t reach the server right now. Try again in a moment.' : e.message);
    }
  }

  Future<void> send(String text) async {
    if (text.trim().isEmpty || state.thinking) return;
    final user = ChatMessage(id: newId(), role: ChatRole.user, text: text.trim());
    state = state.copyWith(messages: [...state.messages, user], thinking: true);
    if (_live) return _sendLive(text.trim());
    await Future<void>.delayed(const Duration(milliseconds: 900));

    final (reply, proposals) = _reply(text.trim());
    final msg = ChatMessage(
      id: newId(),
      role: ChatRole.assistant,
      text: '',
      streaming: true,
      proposalIds: [for (final p in proposals) p.id],
    );
    state = state.copyWith(messages: [...state.messages, msg], proposals: [...state.proposals, ...proposals], thinking: false);

    // Stream the reply word by word.
    final words = reply.split(' ');
    var i = 0;
    _stream?.cancel();
    _stream = Timer.periodic(const Duration(milliseconds: 38), (t) {
      i++;
      final done = i >= words.length;
      state = state.copyWith(messages: [
        for (final m in state.messages)
          m.id == msg.id ? m.copyWith(text: words.take(i).join(' '), streaming: !done) : m,
      ]);
      if (done) t.cancel();
    });
  }

  (String, List<Proposal>) _reply(String text) {
    final lower = text.toLowerCase();
    final now = DateTime.now();
    final tomorrow = dateOnly(now).add(const Duration(days: 1));
    final fmt = DateFormat('EEE d MMM');

    // Rule path: "add task …" / "remind me …" (no AI needed)
    final cmd = RegExp(r'^(add|create|new)\s+(a\s+)?task[:\s]+(.+)$', caseSensitive: false).firstMatch(text) ??
        RegExp(r'^remind me (to )?(.+)$', caseSensitive: false).firstMatch(text);
    if (cmd != null) {
      final p = QuickCaptureParser.parse(cmd.group(cmd.groupCount)!);
      final due = p.due;
      return (
        'Here it is — approve to add it.',
        [
          Proposal(
            id: newId(),
            actionType: 'create_task',
            summary: 'Create task “${p.title}”${p.dueLabel != null ? ' · ${p.dueLabel}' : ''}',
            reason: 'You asked for this.',
            origin: 'chat',
            payload: {'title': p.title, 'due': due?.toIso8601String(), 'has_time': p.hasTime, 'priority': 'medium'},
            changes: [ProposalChange('Due', p.dueLabel ?? 'No date'), const ProposalChange('Priority', 'Medium')],
          ),
        ]
      );
    }

    if (RegExp(r'\b(learn|roadmap|master)\b').hasMatch(lower)) {
      final subject = RegExp(r'(?:learn|roadmap for|master)\s+(.+)$', caseSensitive: false)
              .firstMatch(text)
              ?.group(1)
              ?.replaceAll(RegExp(r'[?.!]+$'), '') ??
          'Kubernetes';
      final name = subject.isEmpty ? 'Kubernetes' : subject[0].toUpperCase() + subject.substring(1);
      final topics = ['$name fundamentals', 'Core concepts', 'Hands-on lab', 'Common patterns', 'Debugging & tooling', 'Mini project'];
      return (
        'Here’s a 4-week $name roadmap sized for about 6 hours a week. It starts hands-on, then builds up to a small project. Approve it and I’ll add it to Growth.',
        [
          Proposal(
            id: newId(),
            actionType: 'create_learning_path',
            summary: 'Create roadmap “$name in 4 weeks” with ${topics.length} topics',
            reason: 'Matches your hands-on learning preference and ~6 free hours a week.',
            origin: 'chat',
            payload: {'title': '$name in 4 weeks', 'topics': topics},
            changes: [for (final (i, t) in topics.indexed) ProposalChange('Topic ${i + 1}', t)],
          ),
        ]
      );
    }

    if (RegExp(r'\b(plan|tomorrow|schedule)\b').hasMatch(lower)) {
      final tasks = ref.read(tasksProvider);
      final overdue = tasks.where((t) => t.isOverdue(now)).toList();
      final gid = newId();
      final out = <Proposal>[
        Proposal(
          id: newId(),
          groupId: gid,
          actionType: 'schedule_block',
          summary: 'Block 9:00–10:30 ${fmt.format(tomorrow)} for deep work',
          reason: 'Your best focus is in the morning.',
          origin: 'chat',
          payload: {
            'title': 'Deep work · DSA',
            'start': tomorrow.add(const Duration(hours: 9)).toIso8601String(),
            'end': tomorrow.add(const Duration(hours: 10, minutes: 30)).toIso8601String(),
            'type': 'focus',
          },
          changes: [ProposalChange('When', '${fmt.format(tomorrow)} · 9:00–10:30')],
        ),
        if (overdue.isNotEmpty)
          Proposal(
            id: newId(),
            groupId: gid,
            actionType: 'reschedule_task',
            summary: 'Move “${overdue.first.title}” to ${fmt.format(tomorrow)}',
            reason: 'It’s overdue; tomorrow afternoon is free.',
            origin: 'chat',
            payload: {'task_id': overdue.first.id, 'due': tomorrow.toIso8601String()},
            changes: [ProposalChange('Due', fmt.format(tomorrow), before: 'Overdue')],
          ),
        Proposal(
          id: newId(),
          groupId: gid,
          actionType: 'create_task',
          summary: 'Create task “Evening revision · 30 min”',
          reason: 'Keeps revision light after a deep-work morning.',
          origin: 'chat',
          payload: {'title': 'Evening revision · 30 min', 'due': tomorrow.toIso8601String(), 'priority': 'low'},
          changes: [ProposalChange('Due', fmt.format(tomorrow))],
        ),
      ];
      return ('Here’s a realistic plan for tomorrow: one protected deep-work block, the overdue item moved, and a light revision slot. Accept all or pick what you want.', out);
    }

    if (RegExp(r'how am i|progress|doing|week').hasMatch(lower)) {
      final learning = ref.read(learningProvider);
      final weekMinutes = [for (var i = 0; i < 7; i++) learning.minutesOn(now.subtract(Duration(days: i)))].fold(0, (a, b) => a + b);
      final done = ref.read(tasksProvider).where((t) => t.done).length;
      final streak = ref.read(habitsProvider).map((h) => h.streak).fold(0, math.max);
      return (
        'This week you studied ${weekMinutes ~/ 60}h ${weekMinutes % 60}m and finished $done tasks. Your best habit streak is $streak days. DSA is moving well; Docker has slowed down — a short session tomorrow would keep it warm.',
        <Proposal>[]
      );
    }

    if (RegExp(r'feel|tired|unmotivated|demotivated|stress|overwhelm').hasMatch(lower)) {
      return (
        'That’s okay — some days are heavier. Let’s make the next step tiny: one 25-minute focus session on something easy. Momentum usually follows.',
        [
          Proposal(
            id: newId(),
            actionType: 'schedule_block',
            summary: 'A 25-minute easy focus session in 15 minutes',
            reason: 'Small wins rebuild momentum.',
            origin: 'chat',
            payload: {
              'title': 'Small win · 25 min',
              'start': now.add(const Duration(minutes: 15)).toIso8601String(),
              'end': now.add(const Duration(minutes: 40)).toIso8601String(),
              'type': 'focus',
            },
            changes: [ProposalChange('When', '${DateFormat('HH:mm').format(now.add(const Duration(minutes: 15)))} · 25 min')],
          ),
        ]
      );
    }

    return (
      'I can plan your day, build learning roadmaps, review your progress or turn notes into tasks. Try “Plan tomorrow” or “Make a roadmap for Kubernetes”.',
      <Proposal>[]
    );
  }

  void _apply(Proposal p) {
    final pl = p.payload;
    DateTime? date(String k) => pl[k] == null ? null : DateTime.tryParse(pl[k]! as String);
    switch (p.actionType) {
      case 'create_task':
        ref.read(tasksProvider.notifier).add(Task(
              id: newId(),
              title: pl['title']! as String,
              due: date('due'),
              hasTime: pl['has_time'] == true,
              priority: Priority.values.byName((pl['priority'] as String?) ?? 'medium'),
              estimatedMinutes: pl['minutes'] as int?,
            ));
      case 'reschedule_task':
        ref.read(tasksProvider.notifier).reschedule(pl['task_id']! as String, date('due')!);
      case 'schedule_block':
        ref.read(scheduleProvider.notifier).add(ScheduleBlock(
              id: newId(),
              title: pl['title']! as String,
              start: date('start')!,
              end: date('end')!,
              type: pl['type'] == 'focus' ? BlockType.focus : BlockType.study,
            ));
      case 'create_learning_path':
        final topics = (pl['topics']! as List).cast<String>();
        ref.read(learningProvider.notifier).addPath(LearningPath(
              id: newId(),
              title: pl['title']! as String,
              skillId: 'sk6',
              topics: [
                for (final (i, t) in topics.indexed)
                  Topic(id: newId(), title: t, difficulty: i < 2 ? Difficulty.easy : (i < 4 ? Difficulty.medium : Difficulty.hard)),
              ],
            ));
      case 'create_habit':
        ref.read(habitsProvider.notifier).add(Habit(
              id: newId(),
              title: pl['title']! as String,
              icon: LucideIcons.sparkle,
              color: LifeColors.coral,
              startedOn: dateOnly(DateTime.now()),
            ));
    }
  }

  void _setStatus(Iterable<String> ids, ProposalStatus status) => state = state.copyWith(proposals: [
        for (final p in state.proposals) ids.contains(p.id) ? p.copyWith(status: status) : p,
      ]);

  /// Live mode: run a server call; on failure put the cards back and explain.
  void _live2(Iterable<String> ids, Future<void> Function() call) {
    unawaited(() async {
      try {
        await ref.read(syncEngineProvider).push();
        await call();
        await ref.read(syncEngineProvider).pull();
      } on ApiException catch (e) {
        _setStatus(ids, ProposalStatus.pending);
        _say(e.isNetwork ? 'Couldn’t reach the server — the suggestion is still waiting for you.' : 'That didn’t work: ${e.message}');
        if (e.code == 'stale_proposal' || e.code == 'proposal_expired' || e.status == 409) unawaited(load());
      }
    }());
  }

  void approve(String id) {
    final p = state.proposal(id);
    if (p == null || p.status != ProposalStatus.pending) return;
    _setStatus([id], ProposalStatus.executed);
    if (_live) {
      return _live2([id], () => _api.post<dynamic>('/agent/proposals/$id/approve', data: {'payload_hash': p.payloadHash}));
    }
    _apply(p);
  }

  void approveGroup(String groupId, Set<String> excluded) {
    final group = state.proposals.where((p) => p.groupId == groupId && p.status == ProposalStatus.pending).toList();
    final chosen = group.where((p) => !excluded.contains(p.id)).toList();
    _setStatus(chosen.map((p) => p.id), ProposalStatus.executed);
    _setStatus(excluded, ProposalStatus.rejected);
    if (_live) {
      if (chosen.isEmpty) {
        for (final id in excluded) {
          unawaited(_api.post<dynamic>('/agent/proposals/$id/reject').then<void>((_) {}, onError: (_) {}));
        }
        return;
      }
      return _live2(
        chosen.map((p) => p.id),
        () => _api.post<dynamic>('/agent/proposal-groups/$groupId/approve', data: {
          'payload_hashes': {for (final p in chosen) p.id: p.payloadHash},
          'exclude': excluded.toList(),
        }),
      );
    }
    for (final p in chosen) {
      _apply(p);
    }
  }

  void reject(String id) {
    _setStatus([id], ProposalStatus.rejected);
    if (_live) unawaited(_api.post<dynamic>('/agent/proposals/$id/reject').then<void>((_) {}, onError: (_) {}));
  }

  /// "Modify": edit the title before approving — no AI call needed.
  void editTitle(String id, String title) {
    final p = state.proposal(id);
    if (p == null) return;
    final summary = p.summary.replaceFirst(RegExp(r'“[^”]*”'), '“$title”');
    state = state.copyWith(proposals: [
      for (final x in state.proposals) x.id == id ? x.copyWith(payload: {...x.payload, 'title': title}, summary: summary) : x,
    ]);
    if (_live) {
      unawaited(() async {
        try {
          final r = await _api.patch<Map<String, dynamic>>('/agent/proposals/$id', data: {
            'arguments': {'title': title},
          });
          final fresh = fromApi(r);
          state = state.copyWith(proposals: [for (final x in state.proposals) x.id == id ? fresh : x]);
        } on ApiException catch (e) {
          _say('Couldn’t change that suggestion: ${e.message}');
          unawaited(load());
        }
      }());
    }
  }

  void clearChat() {
    _conversationId = null;
    state = state.copyWith(messages: _live ? const [] : Seed.messages());
  }
}

final assistantProvider = NotifierProvider<AssistantNotifier, AssistantState>(AssistantNotifier.new);

// =====================================================================
// Reviews (daily insight + weekly report from the server)
// =====================================================================

class Reviews {
  const Reviews({
    this.insight,
    this.highlights = const [],
    this.attention = const [],
    this.weeklyReport,
    this.recommendations = const [],
    this.busy = false,
  });
  final String? insight;
  final List<String> highlights;
  final List<String> attention;
  final String? weeklyReport;
  final List<String> recommendations;
  final bool busy;
}

class ReviewsNotifier extends Notifier<Reviews> {
  static const _cacheKey = 'lifeos_cached_reviews';

  @override
  Reviews build() {
    Future.microtask(_restoreCache);
    return const Reviews();
  }

  Future<void> _restoreCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null || !ref.mounted) return;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      state = Reviews(
        insight: m['insight'] as String?,
        highlights: _strings(m['highlights']),
        attention: _strings(m['attention']),
        weeklyReport: m['weeklyReport'] as String?,
        recommendations: _strings(m['recommendations']),
      );
    } catch (_) {}
  }

  void _saveCache() {
    unawaited(SharedPreferences.getInstance().then((p) {
      p.setString(
        _cacheKey,
        jsonEncode({
          'insight': state.insight,
          'highlights': state.highlights,
          'attention': state.attention,
          'weeklyReport': state.weeklyReport,
          'recommendations': state.recommendations,
        }),
      );
    }).catchError((_) {}));
  }

  ApiClient get _api => ref.read(apiClientProvider);

  static List<String> _strings(Object? v) => [for (final x in (v as List?) ?? const []) '$x'];

  void _daily(Map<String, dynamic> d, Reviews s) {
    state = Reviews(
      insight: d['available'] == true ? d['insight'] as String? : s.insight,
      highlights: d['available'] == true ? _strings(d['highlights']) : s.highlights,
      attention: d['available'] == true ? _strings(d['attention']) : s.attention,
      weeklyReport: s.weeklyReport,
      recommendations: s.recommendations,
    );
    _saveCache();
  }

  void _weekly(Map<String, dynamic> w, Reviews s) {
    state = Reviews(
      insight: s.insight,
      highlights: s.highlights,
      attention: s.attention,
      weeklyReport: w['available'] == true ? w['report'] as String? : s.weeklyReport,
      recommendations: w['available'] == true ? _strings(w['recommendations']) : s.recommendations,
    );
    _saveCache();
  }

  Future<void> load() async {
    if (!ref.read(authProvider).live) return;
    try {
      final d = await _api.get<Map<String, dynamic>>('/agent/reviews/daily');
      if (!ref.mounted) return;
      _daily(d, state);
      final w = await _api.get<Map<String, dynamic>>('/agent/reviews/weekly');
      if (!ref.mounted) return;
      _weekly(w, state);
    } on ApiException {
      // offline
    }
  }

  /// "Generate now" for the weekly report. Returns an error message or null.
  Future<String?> runWeekly() async {
    final before = state;
    state = Reviews(
      insight: before.insight,
      highlights: before.highlights,
      attention: before.attention,
      weeklyReport: before.weeklyReport,
      recommendations: before.recommendations,
      busy: true,
    );
    try {
      final w = await _api.post<Map<String, dynamic>>('/agent/reviews/weekly/run');
      if (!ref.mounted) return null;
      _weekly(w, before);
      unawaited(ref.read(assistantProvider.notifier).load()); // new suggestions
      return null;
    } on ApiException catch (e) {
      if (ref.mounted) state = before;
      return e.message;
    }
  }
}

final reviewsProvider = NotifierProvider<ReviewsNotifier, Reviews>(ReviewsNotifier.new);

/// Which Assistant tab to show (set by "Suggestions" banners elsewhere).
class AssistantTabNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void set(int i) => state = i;
}

final assistantTabProvider = NotifierProvider<AssistantTabNotifier, int>(AssistantTabNotifier.new);

/// Habit dots color helper.
Color habitColor(Habit h) => h.color;

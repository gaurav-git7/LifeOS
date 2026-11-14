// Schedules the planned reminders as Android notifications and opens the right
// screen when one is tapped. Re-plans (debounced) whenever the data changes.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:url_launcher/url_launcher.dart';

import '../../core/routing/router.dart';
import '../../core/routing/routes.dart';
import '../../core/theme/colors.dart';
import '../focus/focus_controller.dart';
import '../stores.dart';
import 'reminder_actions.dart';
import 'reminder_planner.dart';

class ReminderStatus {
  const ReminderStatus({this.permitted, this.exact, this.scheduled = 0});
  final bool? permitted; // null = unknown / not asked yet
  final bool? exact; // on-the-minute alarms allowed
  final int scheduled;
}

class ReminderStatusNotifier extends Notifier<ReminderStatus> {
  @override
  ReminderStatus build() => const ReminderStatus();
  void set(ReminderStatus s) => state = s;
}

final reminderStatusProvider = NotifierProvider<ReminderStatusNotifier, ReminderStatus>(ReminderStatusNotifier.new);

class ReminderService {
  ReminderService(this.ref);

  final Ref ref;
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  Timer? _debounce;
  final List<ProviderSubscription<Object?>> _subs = [];

  /// Not available in widget tests (no platform plugin there).
  static bool get supported => !kIsWeb && Platform.isAndroid && !Platform.environment.containsKey('FLUTTER_TEST');

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  static const _channels = {
    ReminderChannel.reminders: AndroidNotificationChannel(
      'reminders',
      'Reminders',
      description: 'Tasks, habits and focus blocks at the time you set',
      importance: Importance.high,
    ),
    ReminderChannel.summaries: AndroidNotificationChannel(
      'summaries',
      'Daily plan & review',
      description: 'Morning plan, evening review and revisions',
    ),
  };

  /// Channels for server pushes (FCM). Names show in Android's notification settings.
  static const _pushChannels = [
    AndroidNotificationChannel('reviews', 'Reviews', description: 'Your daily and weekly review is ready'),
    AndroidNotificationChannel('agent', 'Assistant', description: 'New suggestions from the assistant'),
    AndroidNotificationChannel('achievements', 'Achievements', description: 'Level-ups and badges'),
    AndroidNotificationChannel('updates', 'App updates & feedback', description: 'New versions of LifeOS'),
    AndroidNotificationChannel(
      'focus',
      'Focus timer',
      description: 'Time left in a focus session',
      importance: Importance.low,
      playSound: false,
      enableVibration: false,
    ),
  ];

  static const _focusOngoingId = 900001;
  static const _focusDoneId = 900002;

  /// Live countdown while a focus session runs, plus an alert when it ends.
  Future<void> showFocus(DateTime endsAt, String label) async {
    if (!_ready) return;
    await _plugin.show(
      id: _focusOngoingId,
      title: 'Focusing · $label',
      body: 'Ends at ${endsAt.hour.toString().padLeft(2, '0')}:${endsAt.minute.toString().padLeft(2, '0')}',
      payload: Routes.focus,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'focus',
          'Focus timer',
          channelDescription: 'Time left in a focus session',
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          autoCancel: false,
          onlyAlertOnce: true,
          showWhen: true,
          when: endsAt.millisecondsSinceEpoch,
          usesChronometer: true,
          chronometerCountDown: true,
          timeoutAfter: endsAt.difference(DateTime.now()).inMilliseconds,
          color: LifeColors.mint,
          icon: 'ic_stat_lifeos',
          category: AndroidNotificationCategory.progress,
        ),
      ),
    );
    await _plugin.zonedSchedule(
      id: _focusDoneId,
      scheduledDate: tz.TZDateTime.from(endsAt, tz.local),
      title: 'Session complete',
      body: '$label · tap to save it',
      payload: Routes.focus,
      androidScheduleMode: (await _android?.canScheduleExactNotifications() ?? false)
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      notificationDetails: reminderDetails(),
    );
  }

  Future<void> cancelFocus() async {
    if (!_ready) return;
    await _plugin.cancel(id: _focusOngoingId);
    await _plugin.cancel(id: _focusDoneId);
  }

  Future<void> start() async {
    if (!supported || _ready) return;
    try {
      tzdata.initializeTimeZones();
      try {
        final local = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(local.identifier));
      } catch (_) {
        tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
      }
      await _plugin.initialize(
        settings: const InitializationSettings(android: AndroidInitializationSettings('ic_stat_lifeos')),
        onDidReceiveNotificationResponse: _onResponse,
        onDidReceiveBackgroundNotificationResponse: onBackgroundNotificationAction,
      );
      for (final c in [..._channels.values, ..._pushChannels]) {
        await _android?.createNotificationChannel(c);
      }
      _ready = true;

      // Opened by tapping a notification while the app was closed.
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        Future<void>.delayed(const Duration(milliseconds: 600), () => open(launch!.notificationResponse?.payload));
      }

      void watch<T>(ProviderListenable<T> p) => _subs.add(ref.listen<T>(p, (_, _) => schedule()));
      watch(tasksProvider);
      watch(habitsProvider);
      watch(scheduleProvider);
      watch(learningProvider.select((l) => l.paths));
      watch(prefsProvider);
      watch(authProvider.select((a) => a.signedIn));
      // Apply buttons pressed while the app was closed, once data is there.
      _subs.add(ref.listen(tasksProvider, (_, _) => unawaited(applyPendingActions())));
      await applyPendingActions();
      schedule();
    } catch (e) {
      debugPrint('Reminders unavailable: $e');
    }
  }

  void dispose() {
    _debounce?.cancel();
    for (final s in _subs) {
      s.close();
    }
  }

  void _onResponse(NotificationResponse r) {
    final p = decodePayload(r.payload);
    if (r.actionId != null && p != null) {
      unawaited(_apply(r.actionId!, p['subject'] as String, p));
    } else {
      open(r.payload);
    }
  }

  /// Done / Snooze / Tomorrow pressed on a reminder.
  /// Returns false when the task/habit isn't loaded (yet).
  Future<bool> _apply(String action, String subject, [Map<String, dynamic>? payload]) async {
    if (action == actSnooze) {
      if (payload != null) await snooze(_plugin, payload);
      return true;
    }
    final parts = subject.split(':');
    if (parts.first == 'task') {
      final tasks = ref.read(tasksProvider.notifier);
      final t = tasks.byId(parts[1]);
      if (t == null) return false;
      if (action == actDone && !t.done) tasks.toggle(t.id);
      if (action == actTomorrow && t.due != null) {
        tasks.reschedule(t.id, t.due!.add(const Duration(days: 1)), hasTime: t.hasTime);
      }
    } else if (parts.first == 'habit' && action == actDone) {
      final day = DateTime.parse(parts[2]);
      final h = ref.read(habitsProvider).where((x) => x.id == parts[1]).firstOrNull;
      if (h == null) return false;
      if (!h.doneOn(day)) ref.read(habitsProvider.notifier).toggle(h.id, day);
    }
    await clearSnooze(_plugin, subject);
    return true;
  }

  /// Actions pressed while the app was closed (saved by the background handler).
  Future<void> applyPendingActions() async {
    if (!_ready || !ref.read(authProvider).signedIn) return;
    final later = <(String, String)>[];
    for (final (action, subject) in await takePendingActions()) {
      if (!await _apply(action, subject)) later.add((action, subject));
    }
    await putBackPending(later); // data not loaded yet: try again after the next sync
  }

  /// Opens what a notification points at: a screen in the app, or a web page
  /// (the GitHub release for "update available").
  void open(String? target) {
    target = decodePayload(target)?['route'] as String? ?? target;
    if (target == null || target.isEmpty) return;
    if (target.startsWith('https://')) {
      unawaited(launchUrl(Uri.parse(target), mode: LaunchMode.externalApplication));
      return;
    }
    final router = ref.read(routerProvider);
    if (target == reviewRoute) {
      ref.read(assistantTabProvider.notifier).set(1);
      router.go(Routes.assistant);
    } else if (target == '${Routes.assistant}?tab=suggestions') {
      ref.read(assistantTabProvider.notifier).set(2);
      router.go(Routes.assistant);
    } else if (target == Routes.achievements) {
      router.push(target);
    } else {
      router.go(target);
    }
  }

  /// A server push that arrived while the app is open.
  Future<void> showPush({required String title, required String body, required String channel, String? target}) async {
    if (!_ready) return;
    final c = _pushChannels.where((x) => x.id == channel).firstOrNull ?? _pushChannels.last;
    await _plugin.show(
      id: DateTime.now().millisecondsSinceEpoch & 0x7fffffff,
      title: title,
      body: body,
      payload: target,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          c.id,
          c.name,
          channelDescription: c.description,
          color: LifeColors.iris,
          icon: 'ic_stat_lifeos',
        ),
      ),
    );
  }

  /// Re-plan soon (changes often come in bursts, e.g. after a sync).
  void schedule() {
    if (!_ready) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 1), () => unawaited(_reschedule()));
  }

  Future<void> _reschedule() async {
    try {
      final auth = ref.read(authProvider);
      final prefs = ref.read(prefsProvider);
      await _plugin.cancelAllPendingNotifications();
      if (!auth.signedIn || !prefs.notifications) {
        _setStatus(scheduled: 0);
        return;
      }
      final plan = planReminders(
        now: DateTime.now(),
        prefs: prefs,
        tasks: ref.read(tasksProvider),
        habits: ref.read(habitsProvider),
        blocks: ref.read(scheduleProvider),
        paths: ref.read(learningProvider).paths,
      );
      final exact = await _android?.canScheduleExactNotifications() ?? false;
      for (final r in plan) {
        final c = _channels[r.channel]!;
        final mode = exact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle;
        if (r.subject != null) {
          await _plugin.zonedSchedule(
            id: r.id,
            scheduledDate: tz.TZDateTime.from(r.at, tz.local),
            title: r.title,
            body: r.body,
            payload: actionPayload(route: r.route, subject: r.subject!, title: r.title, body: r.body),
            androidScheduleMode: mode,
            notificationDetails: reminderDetails(actions: actionsFor(r.subject!)),
          );
          continue;
        }
        await _plugin.zonedSchedule(
          id: r.id,
          scheduledDate: tz.TZDateTime.from(r.at, tz.local),
          title: r.title,
          body: r.body,
          payload: r.route,
          androidScheduleMode: mode,
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              c.id,
              c.name,
              channelDescription: c.description,
              importance: c.importance,
              priority: c.importance == Importance.high ? Priority.high : Priority.defaultPriority,
              color: LifeColors.iris,
              icon: 'ic_stat_lifeos',
              category: AndroidNotificationCategory.reminder,
            ),
          ),
        );
      }
      await restoreSnoozes(_plugin);
      final focus = ref.read(focusProvider); // its "complete" alert was cancelled above too
      if (focus.running && focus.endsAt!.isAfter(DateTime.now())) {
        await showFocus(focus.endsAt!, focus.label ?? 'Focus session');
      }
      final permitted = await _android?.areNotificationsEnabled();
      _setStatus(scheduled: plan.length, exact: exact, permitted: permitted);
    } catch (e) {
      debugPrint('Scheduling reminders failed: $e');
    }
  }

  void _setStatus({required int scheduled, bool? exact, bool? permitted}) {
    final s = ref.read(reminderStatusProvider);
    ref.read(reminderStatusProvider.notifier).set(ReminderStatus(
          scheduled: scheduled,
          exact: exact ?? s.exact,
          permitted: permitted ?? s.permitted,
        ));
  }

  /// Android 13+ shows the system "Allow notifications?" dialog (only the first times).
  Future<bool> requestPermission() async {
    if (!_ready) return false;
    final ok = await _android?.requestNotificationsPermission() ?? false;
    _setStatus(scheduled: ref.read(reminderStatusProvider).scheduled, permitted: ok);
    schedule();
    return ok;
  }

  /// Opens the system screen for "Alarms & reminders" (on-the-minute reminders).
  Future<void> requestExact() async {
    if (!_ready) return;
    await _android?.requestExactAlarmsPermission();
    schedule();
  }

  Future<void> test() async {
    if (!_ready) return;
    final c = _channels[ReminderChannel.reminders]!;
    await _plugin.show(
      id: 1,
      title: 'Reminders are working',
      body: 'This is how LifeOS will nudge you.',
      payload: Routes.home,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          c.id,
          c.name,
          channelDescription: c.description,
          importance: Importance.high,
          priority: Priority.high,
          color: LifeColors.iris,
          icon: 'ic_stat_lifeos',
        ),
      ),
    );
  }
}

final reminderServiceProvider = Provider<ReminderService>((ref) {
  final s = ReminderService(ref);
  ref.onDispose(s.dispose);
  return s;
});

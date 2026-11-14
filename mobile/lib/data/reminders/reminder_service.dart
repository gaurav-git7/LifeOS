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

import '../../core/routing/router.dart';
import '../../core/routing/routes.dart';
import '../../core/theme/colors.dart';
import '../stores.dart';
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
        onDidReceiveNotificationResponse: (r) => _open(r.payload),
      );
      for (final c in _channels.values) {
        await _android?.createNotificationChannel(c);
      }
      _ready = true;

      // Opened by tapping a notification while the app was closed.
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        Future<void>.delayed(const Duration(milliseconds: 600), () => _open(launch!.notificationResponse?.payload));
      }

      void watch<T>(ProviderListenable<T> p) => _subs.add(ref.listen<T>(p, (_, _) => schedule()));
      watch(tasksProvider);
      watch(habitsProvider);
      watch(scheduleProvider);
      watch(learningProvider.select((l) => l.paths));
      watch(prefsProvider);
      watch(authProvider.select((a) => a.signedIn));
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

  void _open(String? route) {
    if (route == null || route.isEmpty) return;
    final router = ref.read(routerProvider);
    if (route == reviewRoute) {
      ref.read(assistantTabProvider.notifier).set(1);
      router.go(Routes.assistant);
    } else {
      router.go(route);
    }
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
        await _plugin.zonedSchedule(
          id: r.id,
          scheduledDate: tz.TZDateTime.from(r.at, tz.local),
          title: r.title,
          body: r.body,
          payload: r.route,
          androidScheduleMode: exact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle,
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

// Done / Snooze / Tomorrow buttons on reminder notifications.
//
// When the app is open the action is applied right away. When it's closed,
// Android runs [onBackgroundNotificationAction] in a separate isolate: it
// saves the action on the phone (and handles Snooze itself), and the app
// applies saved actions the next time it starts or comes to the foreground.

import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

const _pendingKey = 'lifeos_pending_notification_actions';
const _snoozeKey = 'lifeos_snoozed_reminders';

const actDone = 'done';
const actSnooze = 'snooze';
const actTomorrow = 'tomorrow';

/// Payload of an actionable reminder.
String actionPayload({required String route, required String subject, required String title, required String body}) =>
    jsonEncode({'route': route, 'subject': subject, 'title': title, 'body': body});

Map<String, dynamic>? decodePayload(String? p) {
  if (p == null || !p.startsWith('{')) return null;
  try {
    return Map<String, dynamic>.from(jsonDecode(p) as Map);
  } catch (_) {
    return null;
  }
}

List<AndroidNotificationAction> actionsFor(String subject) => subject.startsWith('task:')
    ? const [
        AndroidNotificationAction(actDone, 'Done', cancelNotification: true),
        AndroidNotificationAction(actSnooze, 'Snooze 15 min', cancelNotification: true),
        AndroidNotificationAction(actTomorrow, 'Tomorrow', cancelNotification: true),
      ]
    : const [
        AndroidNotificationAction(actDone, 'Done', cancelNotification: true),
        AndroidNotificationAction(actSnooze, 'Later (30 min)', cancelNotification: true),
      ];

NotificationDetails reminderDetails({List<AndroidNotificationAction>? actions}) => NotificationDetails(
      android: AndroidNotificationDetails(
        'reminders',
        'Reminders',
        channelDescription: 'Tasks, habits and focus blocks at the time you set',
        importance: Importance.high,
        priority: Priority.high,
        color: const Color(0xFF8E7CFF),
        icon: 'ic_stat_lifeos',
        category: AndroidNotificationCategory.reminder,
        actions: actions,
      ),
    );

int _snoozeId(String subject) => (subject.hashCode & 0x3fffffff) | 0x40000000;

/// Schedules the same reminder again later, and remembers it so re-planning keeps it.
Future<void> snooze(FlutterLocalNotificationsPlugin plugin, Map<String, dynamic> payload) async {
  final subject = payload['subject'] as String;
  final minutes = subject.startsWith('task:') ? 15 : 30;
  final at = DateTime.now().add(Duration(minutes: minutes));
  final prefs = await SharedPreferences.getInstance();
  final list = [
    for (final s in prefs.getStringList(_snoozeKey) ?? const <String>[])
      if ((jsonDecode(s) as Map)['subject'] != subject) s,
    jsonEncode({...payload, 'at': at.toIso8601String()}),
  ];
  await prefs.setStringList(_snoozeKey, list);
  await _scheduleSnooze(plugin, payload, at);
}

Future<void> _scheduleSnooze(FlutterLocalNotificationsPlugin plugin, Map<String, dynamic> p, DateTime at) =>
    plugin.zonedSchedule(
      id: _snoozeId(p['subject'] as String),
      scheduledDate: tz.TZDateTime.from(at, tz.local),
      title: p['title'] as String?,
      body: 'Snoozed · ${p['body']}',
      payload: actionPayload(
        route: p['route'] as String,
        subject: p['subject'] as String,
        title: p['title'] as String,
        body: p['body'] as String,
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      notificationDetails: reminderDetails(actions: actionsFor(p['subject'] as String)),
    );

/// Re-adds snoozes that are still ahead (re-planning cancels all pending notifications).
Future<void> restoreSnoozes(FlutterLocalNotificationsPlugin plugin) async {
  final prefs = await SharedPreferences.getInstance();
  final now = DateTime.now();
  final keep = <String>[];
  for (final s in prefs.getStringList(_snoozeKey) ?? const <String>[]) {
    final p = Map<String, dynamic>.from(jsonDecode(s) as Map);
    final at = DateTime.parse(p['at'] as String);
    if (!at.isAfter(now)) continue;
    keep.add(s);
    await _scheduleSnooze(plugin, p, at);
  }
  await prefs.setStringList(_snoozeKey, keep);
}

/// Saved while the app was closed; applied by the app on its next start.
Future<List<(String action, String subject)>> takePendingActions() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload(); // written by the background isolate
  final raw = prefs.getStringList(_pendingKey) ?? const <String>[];
  await prefs.remove(_pendingKey);
  return [
    for (final r in raw)
      (r.split('|').first, r.substring(r.indexOf('|') + 1)),
  ];
}

/// Actions whose task/habit isn't loaded yet go back in the queue.
Future<void> putBackPending(List<(String, String)> items) async {
  if (items.isEmpty) return;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setStringList(_pendingKey, [
    ...prefs.getStringList(_pendingKey) ?? const <String>[],
    for (final (a, s) in items) '$a|$s',
  ]);
}

@pragma('vm:entry-point')
Future<void> onBackgroundNotificationAction(NotificationResponse r) async {
  WidgetsFlutterBinding.ensureInitialized();
  final payload = decodePayload(r.payload);
  final action = r.actionId;
  if (payload == null || action == null) return;
  if (action == actSnooze) {
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation((await FlutterTimezone.getLocalTimezone()).identifier));
    } catch (_) {}
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(settings: const InitializationSettings(android: AndroidInitializationSettings('ic_stat_lifeos')));
    await snooze(plugin, payload);
    return;
  }
  final prefs = await SharedPreferences.getInstance();
  final list = prefs.getStringList(_pendingKey) ?? <String>[];
  list.add('$action|${payload['subject']}');
  await prefs.setStringList(_pendingKey, list);
}

/// Forget a snooze (the task/habit was done).
Future<void> clearSnooze(FlutterLocalNotificationsPlugin plugin, String subject) async {
  final prefs = await SharedPreferences.getInstance();
  final list = prefs.getStringList(_snoozeKey) ?? const <String>[];
  await prefs.setStringList(_snoozeKey, [
    for (final s in list)
      if ((jsonDecode(s) as Map)['subject'] != subject) s,
  ]);
  await plugin.cancel(id: _snoozeId(subject));
}

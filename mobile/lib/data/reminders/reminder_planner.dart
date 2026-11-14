// Decides which reminders to show and when. Pure function, so it's easy to test;
// reminder_service.dart hands the result to Android.
//
// Everything runs on the phone: no server, works offline, and is re-planned
// whenever tasks, habits, the calendar or settings change.

import '../../core/routing/routes.dart';
import '../models.dart';
import '../stores.dart';

enum ReminderChannel { reminders, summaries }

class PlannedReminder {
  const PlannedReminder({
    required this.key,
    required this.at,
    required this.title,
    required this.body,
    required this.route,
    this.channel = ReminderChannel.reminders,
    this.ignoresQuietHours = false,
  });

  /// Stable identity, so re-planning replaces instead of duplicating.
  final String key;
  final DateTime at;
  final String title;
  final String body;
  final String route; // where tapping the notification goes
  final ReminderChannel channel;
  final bool ignoresQuietHours; // a time the user picked explicitly

  /// Android notification id (31-bit, stable for the same key).
  int get id {
    var h = 0x811c9dc5;
    for (final c in key.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0x7fffffff;
    }
    return h;
  }

  @override
  String toString() => '$at $title';
}

/// Route used for "open the Reviews tab".
const reviewRoute = '${Routes.assistant}?tab=reviews';

const _horizon = Duration(days: 7);
const maxReminders = 60; // Android caps alarms per app; stay well below

bool _inQuietHours(DateTime t) {
  final m = t.hour * 60 + t.minute;
  return m >= 22 * 60 + 30 || m < 7 * 60; // 22:30–07:00, same as the server default
}

List<PlannedReminder> planReminders({
  required DateTime now,
  required Prefs prefs,
  required List<Task> tasks,
  required List<Habit> habits,
  required List<ScheduleBlock> blocks,
  required List<LearningPath> paths,
}) {
  if (!prefs.notifications) return const [];
  final today = dateOnly(now);
  final end = now.add(_horizon);
  final out = <PlannedReminder>[];
  DateTime at(DateTime day, int hour, [int minute = 0]) => DateTime(day.year, day.month, day.day, hour, minute);

  // Tasks with a time: 15 minutes before (or at the time if that's sooner).
  for (final t in tasks) {
    if (t.done || !t.hasTime || t.due == null) continue;
    final due = t.due!;
    if (!due.isAfter(now) || due.isAfter(end)) continue;
    final early = due.subtract(const Duration(minutes: 15));
    final soon = early.isAfter(now);
    out.add(PlannedReminder(
      key: 'task:${t.id}',
      at: soon ? early : due,
      title: t.title,
      body: soon ? 'In 15 minutes' : 'Due now',
      route: Routes.plan,
      ignoresQuietHours: true,
    ));
  }

  // Morning plan at 8:00 for today (if still ahead) and tomorrow.
  for (var d = 0; d < 2; d++) {
    final day = today.add(Duration(days: d));
    final when = at(day, 8);
    if (!when.isAfter(now)) continue;
    final dueThatDay = tasks.where((t) => !t.done && (t.isDueOn(day) || (d == 0 && t.isOverdue(now)))).toList()
      ..sort((a, b) => b.priority.index.compareTo(a.priority.index));
    if (dueThatDay.isEmpty) continue;
    final names = dueThatDay.take(3).map((t) => t.title).join(' · ');
    out.add(PlannedReminder(
      key: 'morning:${day.toIso8601String()}',
      at: when,
      title: '${dueThatDay.length} thing${dueThatDay.length == 1 ? '' : 's'} on today',
      body: names,
      route: Routes.home,
      channel: ReminderChannel.summaries,
    ));
  }

  // Habits at their reminder time, on days they aren't done yet.
  for (final h in habits) {
    final r = h.reminder;
    if (r == null) continue;
    for (var d = 0; d < 7; d++) {
      final day = today.add(Duration(days: d));
      final when = at(day, r.hour, r.minute);
      if (!when.isAfter(now) || h.doneOn(day)) continue;
      final streak = d == 0 ? h.streak : 0;
      out.add(PlannedReminder(
        key: 'habit:${h.id}:${day.toIso8601String()}',
        at: when,
        title: h.title,
        body: streak > 1 ? 'Keep your $streak-day streak going' : 'A small step counts',
        route: Routes.plan,
        ignoresQuietHours: true,
      ));
    }
  }

  // Focus / study blocks: 5 minutes before they start.
  for (final b in blocks) {
    if (b.type != BlockType.focus && b.type != BlockType.study) continue;
    final when = b.start.subtract(const Duration(minutes: 5));
    if (!when.isAfter(now) || when.isAfter(end)) continue;
    out.add(PlannedReminder(
      key: 'block:${b.id}',
      at: when,
      title: b.title,
      body: 'Starts in 5 minutes',
      route: Routes.plan,
      ignoresQuietHours: true,
    ));
  }

  // Spaced-repetition revisions due today: one nudge at 18:00.
  final revisions = paths.expand((p) => p.topics).where((t) => t.revisionDue).length;
  final revisionAt = at(today, 18);
  if (revisions > 0 && revisionAt.isAfter(now)) {
    out.add(PlannedReminder(
      key: 'revision:${today.toIso8601String()}',
      at: revisionAt,
      title: '$revisions topic${revisions == 1 ? '' : 's'} to revise',
      body: 'A quick review keeps it from fading',
      route: Routes.growth,
      channel: ReminderChannel.summaries,
    ));
  }

  // Evening review at the time chosen in Settings.
  if (prefs.dailyReview) {
    for (var d = 0; d < 7; d++) {
      final when = at(today.add(Duration(days: d)), prefs.reviewTime.hour, prefs.reviewTime.minute);
      if (!when.isAfter(now)) continue;
      out.add(PlannedReminder(
        key: 'review:${dateOnly(when).toIso8601String()}',
        at: when,
        title: 'Close the day',
        body: 'Two minutes to look back and set up tomorrow',
        route: reviewRoute,
        channel: ReminderChannel.summaries,
        ignoresQuietHours: true,
      ));
    }
  }

  final kept = [
    for (final r in out)
      if (!prefs.quietHours || r.ignoresQuietHours || !_inQuietHours(r.at)) r,
  ]..sort((a, b) => a.at.compareTo(b.at));
  return kept.take(maxReminders).toList();
}

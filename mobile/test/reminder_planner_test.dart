import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeos/data/models.dart';
import 'package:lifeos/data/reminders/reminder_planner.dart';
import 'package:lifeos/data/stores.dart';

void main() {
  // Monday 10:00
  final now = DateTime(2026, 11, 16, 10);
  final today = dateOnly(now);

  List<PlannedReminder> plan({
    Prefs prefs = const Prefs(),
    List<Task> tasks = const [],
    List<Habit> habits = const [],
    List<ScheduleBlock> blocks = const [],
  }) =>
      planReminders(now: now, prefs: prefs, tasks: tasks, habits: habits, blocks: blocks, paths: const []);

  Habit habit({TimeOfDay? at, Set<DateTime> done = const {}}) => Habit(
        id: 'h1',
        title: 'Read',
        icon: Icons.book,
        color: Colors.orange,
        startedOn: today.subtract(const Duration(days: 10)),
        reminder: at,
        doneDays: done,
      );

  test('nothing when notifications are off', () {
    final r = plan(prefs: const Prefs(notifications: false), habits: [habit(at: const TimeOfDay(hour: 20, minute: 0))]);
    expect(r, isEmpty);
  });

  test('timed task: 15 minutes before; past and done tasks skipped', () {
    final r = plan(prefs: const Prefs(dailyReview: false), tasks: [
      Task(id: 'a', title: 'Call bank', due: today.add(const Duration(hours: 15)), hasTime: true),
      Task(id: 'b', title: 'Old', due: today.add(const Duration(hours: 8)), hasTime: true),
      Task(id: 'c', title: 'Done', due: today.add(const Duration(hours: 16)), hasTime: true, done: true),
    ]);
    final t = r.where((x) => x.key.startsWith('task:')).toList();
    expect(t.single.title, 'Call bank');
    expect(t.single.at, today.add(const Duration(hours: 14, minutes: 45)));
  });

  test('habit reminders skip days already done', () {
    final r = plan(
      prefs: const Prefs(dailyReview: false),
      habits: [habit(at: const TimeOfDay(hour: 20, minute: 0), done: {today})],
    );
    final h = r.where((x) => x.key.startsWith('habit:')).toList();
    expect(h, hasLength(6)); // tomorrow … +6 days, not today
    expect(h.first.at, today.add(const Duration(days: 1, hours: 20)));
  });

  test('morning plan for tomorrow lists the most important tasks', () {
    final tomorrow = today.add(const Duration(days: 1));
    final r = plan(prefs: const Prefs(dailyReview: false), tasks: [
      Task(id: 'a', title: 'Low thing', due: tomorrow, priority: Priority.low),
      Task(id: 'b', title: 'Big thing', due: tomorrow, priority: Priority.high),
    ]);
    final m = r.singleWhere((x) => x.key.startsWith('morning:'));
    expect(m.at, tomorrow.add(const Duration(hours: 8)));
    expect(m.title, '2 things on today');
    expect(m.body, startsWith('Big thing'));
  });

  test('quiet hours drop summaries but keep times the user chose', () {
    final r = plan(
      prefs: const Prefs(reviewTime: TimeOfDay(hour: 23, minute: 0)),
      tasks: [Task(id: 'late', title: 'Late call', due: today.add(const Duration(hours: 23, minutes: 30)), hasTime: true)],
    );
    expect(r.where((x) => x.key.startsWith('task:')), hasLength(1));
    expect(r.where((x) => x.key.startsWith('review:')), hasLength(7)); // the review time was chosen too
  });

  test('focus blocks get a 5-minute heads-up; ids are stable', () {
    final start = today.add(const Duration(hours: 14));
    final blocks = [ScheduleBlock(id: 'b1', title: 'Deep work', start: start, end: start.add(const Duration(hours: 1)), type: BlockType.focus)];
    final a = plan(prefs: const Prefs(dailyReview: false), blocks: blocks);
    final b = plan(prefs: const Prefs(dailyReview: false), blocks: blocks);
    expect(a.single.at, start.subtract(const Duration(minutes: 5)));
    expect(a.single.id, b.single.id);
  });

  test('never more than the cap', () {
    final tasks = [
      for (var i = 0; i < 100; i++)
        Task(id: 't$i', title: 'T$i', due: now.add(Duration(hours: 1 + i)), hasTime: true),
    ];
    expect(plan(tasks: tasks), hasLength(maxReminders));
  });
}

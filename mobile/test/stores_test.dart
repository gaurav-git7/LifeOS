import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeos/data/models.dart';
import 'package:lifeos/data/stores.dart';

void main() {
  late ProviderContainer c;
  setUp(() => c = ProviderContainer());
  tearDown(() => c.dispose());

  test('level math matches the backend (100 * n^1.5)', () {
    expect(xpForNext(1), 100);
    expect(xpForNext(5), 1118);
    final info = levelInfo(5531);
    expect(info.level, 7);
    expect(info.into, 1240);
    expect(info.rank, 'Adept');
  });

  test('completing a task awards XP by priority; reopening revokes it', () {
    final before = c.read(progressionProvider).totalXp;
    final xp = c.read(tasksProvider.notifier).toggle('t1'); // high priority
    expect(xp, 30);
    expect(c.read(progressionProvider).totalXp, before + 30);
    expect(c.read(tasksProvider.notifier).byId('t1')!.done, isTrue);
    c.read(tasksProvider.notifier).toggle('t1');
    expect(c.read(progressionProvider).totalXp, before);
  });

  test('habit toggle updates streak and XP', () {
    final h = c.read(habitsProvider).firstWhere((h) => h.id == 'h4'); // not done today
    final streak = h.streak;
    c.read(habitsProvider.notifier).toggle('h4');
    expect(c.read(habitsProvider).firstWhere((h) => h.id == 'h4').streak, streak + 1);
  });

  test('study XP is capped at 180 per day', () {
    final l = c.read(learningProvider.notifier);
    final already = c.read(learningProvider).minutesOn(DateTime.now());
    final xp = l.addSession(StudySession(id: 'x', start: DateTime.now(), minutes: 300, skillId: 'sk2'));
    expect(xp, (180 - already).clamp(0, 180));
  });

  test('goal progress follows its progress type', () {
    final goals = c.read(goalsProvider);
    final tasks = c.read(tasksProvider);
    final numeric = goals.firstWhere((g) => g.progressType == GoalProgressType.numeric);
    expect(goalProgress(numeric, tasks), closeTo(8 / 12, 0.001));
    final ms = goals.firstWhere((g) => g.id == 'g2');
    expect(goalProgress(ms, tasks), 0.25);
  });

  test('assistant: rule command creates a pending proposal; approve creates the task', () async {
    final a = c.read(assistantProvider.notifier);
    await a.send('add task buy milk tomorrow');
    final p = c.read(assistantProvider).proposals.last;
    expect(p.actionType, 'create_task');
    expect(p.status, ProposalStatus.pending);
    expect(c.read(tasksProvider).any((t) => t.title == 'Buy milk'), isFalse); // nothing until approval
    a.approve(p.id);
    expect(c.read(tasksProvider).any((t) => t.title == 'Buy milk'), isTrue);
    expect(c.read(assistantProvider).proposal(p.id)!.status, ProposalStatus.executed);
  });

  test('assistant: group approval skips excluded items', () async {
    final a = c.read(assistantProvider.notifier);
    final blocksBefore = c.read(scheduleProvider).length;
    a.approveGroup('grp-daily', {'pp3'}); // seed group: block + reschedule + task
    final s = c.read(assistantProvider);
    expect(s.proposal('pp1')!.status, ProposalStatus.executed);
    expect(s.proposal('pp3')!.status, ProposalStatus.rejected);
    expect(c.read(scheduleProvider).length, blocksBefore + 1);
    expect(dateOnly(c.read(tasksProvider.notifier).byId('t10')!.due!), dateOnly(DateTime.now().add(const Duration(days: 1))));
  });

  test('journal: mood XP once per day', () {
    final before = c.read(progressionProvider).totalXp;
    final j = c.read(journalProvider.notifier);
    final today = dateOnly(DateTime.now());
    j.saveMood(MoodEntry(day: today, mood: 3));
    j.saveMood(MoodEntry(day: today, mood: 4));
    expect(c.read(progressionProvider).totalXp, before + 5);
    expect(c.read(journalProvider).moodOn(today)!.mood, 4);
  });
}

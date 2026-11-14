// Live mode against an in-memory fake of the API: auth, push/pull, offline
// queueing, the assistant's approve flow and sign-out.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeos/data/models.dart';
import 'package:lifeos/data/stores.dart';
import 'package:lifeos/data/sync/sync_engine.dart';

import 'helpers/fake_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeApi api;
  late ProviderContainer c;

  setUp(() async {
    api = FakeApi();
    c = fakeLiveContainer(api);
    c.read(authProvider); // start restore (finds no session)
    await Future<void>.delayed(Duration.zero);
    expect(await c.read(authProvider.notifier).register('Gaurav', 'me@example.com', 'correct-horse-battery'), isNull);
    await c.read(syncEngineProvider).syncNow();
  });
  tearDown(() => c.dispose());

  Task task(String title) => Task(id: newId(), title: title, priority: Priority.medium, due: dateOnly(DateTime.now()));

  test('register starts live with empty data', () {
    final a = c.read(authProvider);
    expect(a.live, isTrue);
    expect(a.signedIn, isTrue);
    expect(a.name, 'Gaurav');
    expect(c.read(tasksProvider), isEmpty);
    expect(c.read(goalsProvider), isEmpty);
  });

  test('local changes are pushed; server XP wins after sync', () async {
    final t = task('Write tests');
    c.read(tasksProvider.notifier).add(t);
    await c.read(syncEngineProvider).syncNow();
    expect(api.live('tasks').single['title'], 'Write tests');

    c.read(tasksProvider.notifier).toggle(t.id);
    await c.read(syncEngineProvider).syncNow();
    expect(api.rows['tasks']![t.id]!['status'], 'done');
    expect(c.read(progressionProvider).totalXp, 10); // server value, not the local guess
    expect(c.read(tasksProvider).single.done, isTrue);
  });

  test('changes from elsewhere arrive on pull', () async {
    api.serverInsert('goals', '00000000-0000-4000-8000-00000000g001', {
      'title': 'Land an internship',
      'category': 'career',
      'progress_type': 'milestones',
      'status': 'active',
    });
    api.serverInsert('goal_milestones', '00000000-0000-4000-8000-00000000m001', {
      'goal_id': '00000000-0000-4000-8000-00000000g001',
      'title': 'Polish resume',
      'sort_order': 0,
      'completed_at': '2026-11-10T10:00:00Z',
    });
    await c.read(syncEngineProvider).syncNow();
    final g = c.read(goalsProvider).single;
    expect(g.title, 'Land an internship');
    expect(g.category, 'Career');
    expect(g.milestones.single.done, isTrue);
    expect(goalProgress(g, const []), 1);
  });

  test('offline changes wait in the outbox and go out later', () async {
    api.offline = true;
    c.read(tasksProvider.notifier).add(task('Offline task'));
    await c.read(syncEngineProvider).syncNow();
    expect(c.read(syncStatusProvider).phase, SyncPhase.offline);
    expect(c.read(syncStatusProvider).pending, 1);
    expect(c.read(tasksProvider).single.title, 'Offline task'); // still visible locally

    api.offline = false;
    await c.read(syncEngineProvider).syncNow();
    expect(c.read(syncStatusProvider).pending, 0);
    expect(api.live('tasks').single['title'], 'Offline task');
  });

  test('habits, journal, mood, projects and study sessions sync', () async {
    final h = Habit(id: newId(), title: 'Read', icon: Icons.book, color: Colors.orange, startedOn: dateOnly(DateTime.now()));
    c.read(habitsProvider.notifier).add(h);
    c.read(habitsProvider.notifier).toggle(h.id);
    c.read(journalProvider.notifier).upsertEntry(JournalEntry(id: newId(), day: dateOnly(DateTime.now()), content: 'A good day'));
    c.read(journalProvider.notifier).saveMood(MoodEntry(day: dateOnly(DateTime.now()), mood: 3));
    final p = Project(id: newId(), name: 'LifeOS', stack: const ['Flutter'], progress: 0, color: Colors.blue);
    c.read(learningProvider.notifier).addProject(p);
    c.read(learningProvider.notifier).addProjectMilestone(p.id, Milestone(id: newId(), title: 'Ship APK'));
    c.read(learningProvider.notifier).addSession(StudySession(id: newId(), start: DateTime.now(), minutes: 25, label: 'Focus'));
    await c.read(syncEngineProvider).syncNow();

    expect(api.live('habit_logs').single['status'], 'done');
    expect(api.live('journal_entries').single['content'], 'A good day');
    expect(api.live('mood_entries').single['mood'], 4); // app 0..4 → server 1..5
    expect(api.live('tasks').single['tags'], [projectMilestoneTag]);
    expect(api.live('study_sessions').single['duration_minutes'], 25);

    // After the round trip the app still shows the same things.
    expect(c.read(habitsProvider).single.doneOn(DateTime.now()), isTrue);
    expect(c.read(journalProvider).moodOn(DateTime.now())!.mood, 3);
    expect(c.read(learningProvider).projects.single.milestones.single.title, 'Ship APK');
    expect(c.read(tasksProvider), isEmpty); // project milestones aren't shown as tasks

    // Un-ticking a habit doesn't create a second log for the day.
    c.read(habitsProvider.notifier).toggle(h.id);
    await c.read(syncEngineProvider).syncNow();
    expect(api.live('habit_logs').single['status'], 'skipped');
    expect(c.read(habitsProvider).single.doneOn(DateTime.now()), isFalse);
  });

  test('journal: autosave edits and a late pull never create conflict copies', () async {
    final e = JournalEntry(id: newId(), day: dateOnly(DateTime.now()), title: 'Day', content: 'one');
    final journal = c.read(journalProvider.notifier);
    final sync = c.read(syncEngineProvider);
    journal.upsertEntry(e);
    await sync.syncNow();

    // A pull whose reply is built now but arrives after the next push.
    api.pullDelay = const Duration(milliseconds: 300);
    final latePull = sync.pull();
    api.pullDelay = Duration.zero;
    journal.upsertEntry(e.copyWith(content: 'one two'));
    journal.upsertEntry(e.copyWith(content: 'one two three')); // merged with the previous edit
    expect(sync.outbox, hasLength(1));
    await sync.push();
    await latePull;

    // Reopen and edit again: must apply cleanly.
    journal.upsertEntry(e.copyWith(content: 'one two three four'));
    await sync.syncNow();
    expect(api.conflicts, 0);
    expect(api.live('journal_entries').single['content'], 'one two three four');
    expect(c.read(journalProvider).entries.single.content, 'one two three four');
  });

  test('assistant: chat → approve creates the task on the server', () async {
    await c.read(assistantProvider.notifier).send('add task revise graphs');
    final p = c.read(assistantProvider).pending.single;
    expect(p.payloadHash, 'hash-1');
    expect(p.changes.map((x) => x.label), containsAll(['Due', 'Priority']));

    c.read(assistantProvider.notifier).approve(p.id);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await c.read(syncEngineProvider).pull();
    expect(c.read(tasksProvider).single.title, 'Revise graphs');
    expect(c.read(tasksProvider).single.priority, Priority.high);
  });

  test('sign out clears tokens and the offline cache', () async {
    c.read(tasksProvider.notifier).add(task('Secret'));
    await c.read(authProvider.notifier).signOut();
    expect(c.read(authProvider).signedIn, isFalse);
    expect(await c.read(tokenStoreProvider).refresh, isNull);
    expect(c.read(syncEngineProvider).rows('tasks'), isEmpty);
    expect(api.calls, contains('POST /auth/logout'));
  });
}

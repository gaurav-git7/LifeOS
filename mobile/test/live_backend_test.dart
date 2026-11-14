// Runs the app's data layer against a real LifeOS API (not part of the normal run).
//
//   LIFEOS_LIVE_API=http://127.0.0.1:8000/api/v1 flutter test test/live_backend_test.dart
//
// Checks that every write the app makes is accepted by the backend's schemas
// and comes back the same after a pull.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeos/data/api/api_client.dart';
import 'package:lifeos/data/models.dart';
import 'package:lifeos/data/stores.dart';
import 'package:lifeos/data/sync/sync_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _url = Platform.environment['LIFEOS_LIVE_API'];

void main() {
  if (_url == null) {
    test('live backend check', () {}, skip: 'Set LIFEOS_LIVE_API to run against a real server');
    return;
  }
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null; // flutter_test blocks real HTTP by default

  late ProviderContainer c;

  ProviderContainer container() {
    SharedPreferences.setMockInitialValues({});
    return ProviderContainer(overrides: [
      tokenStoreProvider.overrideWithValue(TokenStore(inMemory: true)),
      apiClientProvider.overrideWith((ref) => ApiClient(tokens: ref.watch(tokenStoreProvider), baseUrl: _url!)),
    ]);
  }

  Future<void> sync() => c.read(syncEngineProvider).syncNow();

  void expectSynced() {
    final s = c.read(syncStatusProvider);
    expect(s.phase, SyncPhase.idle, reason: s.message);
    expect(s.pending, 0);
  }

  setUpAll(() async {
    c = container();
    c.read(authProvider);
    await Future<void>.delayed(Duration.zero);
    final email = 'live${DateTime.now().millisecondsSinceEpoch}@example.com';
    expect(await c.read(authProvider.notifier).register('Live Check', email, 'correct-horse-battery'), isNull);
    await sync();
  });

  tearDownAll(() async {
    await c.read(authProvider.notifier).deleteAccount();
    c.dispose();
  });

  test('tasks with subtasks, completion and delete', () async {
    final today = dateOnly(DateTime.now());
    final t = Task(
      id: newId(),
      title: 'Live task',
      priority: Priority.high,
      due: today.add(const Duration(hours: 18)),
      hasTime: true,
      estimatedMinutes: 30,
      subtasks: [Subtask(id: newId(), title: 'Step 1')],
      tags: const ['dsa'],
    );
    c.read(tasksProvider.notifier).add(t);
    await sync();
    expectSynced();
    var back = c.read(tasksProvider).single;
    expect(back.title, 'Live task');
    expect(back.hasTime, isTrue);
    expect(back.subtasks.single.title, 'Step 1');

    c.read(tasksProvider.notifier).toggleSubtask(t.id, t.subtasks.single.id);
    c.read(tasksProvider.notifier).toggle(t.id);
    await sync();
    expectSynced();
    back = c.read(tasksProvider).single;
    expect(back.done, isTrue);
    expect(back.subtasks.single.done, isTrue);
    expect(c.read(progressionProvider).totalXp, greaterThan(0));

    c.read(tasksProvider.notifier).delete(t.id);
    await sync();
    expectSynced();
    expect(c.read(tasksProvider), isEmpty);
  });

  test('goals + milestones, habits, schedule', () async {
    final g = Goal(
      id: newId(),
      title: 'Live goal',
      category: 'Career',
      icon: Icons.flag,
      color: Colors.blue,
      progressType: GoalProgressType.milestones,
      milestones: [Milestone(id: newId(), title: 'M1')],
    );
    c.read(goalsProvider.notifier).add(g);
    final h = Habit(id: newId(), title: 'Read 10 pages', icon: Icons.book, color: Colors.orange, startedOn: dateOnly(DateTime.now()));
    c.read(habitsProvider.notifier).add(h);
    final start = DateTime.now().add(const Duration(days: 1));
    c.read(scheduleProvider.notifier).add(ScheduleBlock(
          id: newId(),
          title: 'Deep work',
          start: start,
          end: start.add(const Duration(hours: 1)),
          type: BlockType.focus,
        ));
    await sync();
    expectSynced();

    c.read(goalsProvider.notifier).toggleMilestone(g.id, g.milestones.single.id);
    c.read(habitsProvider.notifier).toggle(h.id);
    await sync();
    expectSynced();
    final goal = c.read(goalsProvider).single;
    expect(goal.milestones.single.done, isTrue);
    expect(goalProgress(goal, const []), 1);
    expect(c.read(habitsProvider).single.doneOn(DateTime.now()), isTrue);
    expect(c.read(scheduleProvider).single.type, BlockType.focus);

    c.read(habitsProvider.notifier).toggle(h.id); // untick
    await sync();
    expectSynced();
    expect(c.read(habitsProvider).single.doneOn(DateTime.now()), isFalse);
  });

  test('growth: skills, roadmap topics, sessions, projects', () async {
    final skill = Skill(id: newId(), name: 'Docker', icon: Icons.code, color: Colors.teal, level: 1, target: 3);
    c.read(learningProvider.notifier).addSkill(skill);
    final path = LearningPath(
      id: newId(),
      title: 'Docker in 4 weeks',
      skillId: skill.id,
      topics: [Topic(id: newId(), title: 'Images', difficulty: Difficulty.easy)],
    );
    c.read(learningProvider.notifier).addPath(path);
    final project = Project(id: newId(), name: 'LifeOS', stack: const ['Flutter'], progress: 0, color: Colors.blue);
    c.read(learningProvider.notifier).addProject(project);
    c.read(learningProvider.notifier).addProjectMilestone(project.id, Milestone(id: newId(), title: 'Ship APK'));
    c.read(learningProvider.notifier).addSession(StudySession(
          id: newId(),
          start: DateTime.now().subtract(const Duration(minutes: 30)),
          minutes: 25,
          skillId: skill.id,
          topicId: path.topics.single.id,
          label: 'Images',
        ));
    await sync();
    expectSynced();

    c.read(learningProvider.notifier).completeTopic(path.id, path.topics.single.id);
    c.read(learningProvider.notifier).toggleProjectMilestone(project.id, c.read(learningProvider).projects.single.milestones.single.id);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await sync();
    expectSynced();

    final l = c.read(learningProvider);
    expect(l.skills.single.name, 'Docker');
    expect(l.paths.single.topics.single.status, TopicStatus.done);
    expect(l.paths.single.topics.single.nextRevision, isNotNull);
    expect(l.sessions.single.minutes, 25);
    expect(l.projects.single.milestones.single.done, isTrue);
    expect(l.projects.single.progress, 1);
    expect(c.read(tasksProvider), isEmpty);
  });

  test('journal and mood', () async {
    final today = dateOnly(DateTime.now());
    final e = JournalEntry(id: newId(), day: today, title: 'Day one', content: 'Synced to the server', aiAllowed: false);
    c.read(journalProvider.notifier).upsertEntry(e);
    c.read(journalProvider.notifier).saveMood(MoodEntry(day: today, mood: 3, energy: 7));
    await sync();
    c.read(journalProvider.notifier).saveMood(MoodEntry(day: today, mood: 4, energy: 8, tags: const ['calm']));
    c.read(journalProvider.notifier).upsertEntry(e.copyWith(content: 'Edited on the phone'));
    await sync();
    expectSynced();
    final j = c.read(journalProvider);
    expect(j.entries.single.content, 'Edited on the phone');
    expect(j.moods.length, 1);
    expect(j.moodOn(today)!.mood, 4);
    expect(j.moodOn(today)!.tags, ['calm']);
  });

  test('assistant chat, proposal approve, memories, preferences', () async {
    await c.read(assistantProvider.notifier).send('add task call the bank tomorrow');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final a = c.read(assistantProvider);
    expect(a.messages.last.role, ChatRole.assistant);
    final pending = a.pending;
    if (pending.isNotEmpty) {
      c.read(assistantProvider.notifier).approve(pending.first.id);
      await Future<void>.delayed(const Duration(seconds: 1));
      await sync();
      expect(c.read(tasksProvider).map((t) => t.title.toLowerCase()), anyElement(contains('bank')));
    }

    c.read(memoriesProvider.notifier).add(Memory(id: newId(), type: MemoryType.preference, content: 'I study best in the morning'));
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await c.read(memoriesProvider.notifier).load();
    expect(c.read(memoriesProvider).map((m) => m.content), contains('I study best in the morning'));

    c.read(prefsProvider.notifier).update((p) => p.copyWith(moodAi: true));
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await c.read(prefsProvider.notifier).load(); // read back from the server
    expect(c.read(prefsProvider).moodAi, isTrue);
  });
}

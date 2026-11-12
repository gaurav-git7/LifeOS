// Believable sample data (relative to today) used until the app talks to the API.
// See docs/UI_UX.md §17.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/theme/colors.dart';
import 'models.dart';

abstract final class Seed {
  static DateTime get _now => DateTime.now();
  static DateTime get _today => dateOnly(_now);
  static DateTime _at(int dayOffset, int hour, [int minute = 0]) =>
      DateTime(_today.year, _today.month, _today.day + dayOffset, hour, minute);
  static DateTime _day(int offset) => DateTime(_today.year, _today.month, _today.day + offset);

  // ---------- productivity ----------

  static List<Task> tasks() => [
        Task(
          id: 't1',
          title: 'Solve 3 sliding-window problems',
          priority: Priority.high,
          due: _at(0, 20),
          hasTime: true,
          estimatedMinutes: 45,
          goalId: 'g1',
          tags: const ['dsa'],
          subtasks: const [
            Subtask(id: 's1', title: 'Longest substring without repeats', done: true),
            Subtask(id: 's2', title: 'Minimum window substring'),
            Subtask(id: 's3', title: 'Sliding window maximum'),
          ],
        ),
        Task(id: 't2', title: 'Write your first Dockerfile', priority: Priority.medium, due: _day(0), estimatedMinutes: 60, goalId: 'g2', description: 'Containerise the LifeOS FastAPI backend.'),
        Task(id: 't3', title: 'Revise SQL joins', priority: Priority.low, due: _day(0), estimatedMinutes: 30),
        Task(id: 't4', title: 'Morning standup notes', priority: Priority.low, due: _at(0, 9, 30), hasTime: true, done: true, completedAt: _at(0, 9, 40)),
        Task(id: 't5', title: 'Read chapter 4 of DDIA', priority: Priority.medium, due: _day(0), done: true, completedAt: _at(0, 11)),
        Task(id: 't6', title: 'Gym — upper body', priority: Priority.medium, due: _at(0, 7), hasTime: true, done: true, completedAt: _at(0, 8)),
        Task(id: 't7', title: 'Reply to internship email', priority: Priority.high, due: _day(0), done: true, completedAt: _at(0, 12, 30)),
        Task(id: 't8', title: 'Clean up GitHub README', priority: Priority.low, due: _day(0), done: true, completedAt: _at(0, 14)),
        Task(id: 't9', title: 'Finish binary search notes', priority: Priority.medium, due: _day(-2), goalId: 'g1'),
        Task(id: 't10', title: 'Update resume projects section', priority: Priority.high, due: _day(-1)),
        Task(id: 't11', title: 'Kubernetes: pods vs deployments', priority: Priority.medium, due: _day(1), estimatedMinutes: 50, goalId: 'g2'),
        Task(id: 't12', title: 'Mock interview with Arjun', priority: Priority.high, due: _at(2, 18), hasTime: true, estimatedMinutes: 60),
        Task(id: 't13', title: 'Plan LifeOS sync screen', priority: Priority.medium, due: _day(3), goalId: 'g3'),
        Task(id: 't14', title: 'Buy a new notebook', priority: Priority.low),
        Task(id: 't15', title: 'Trees: level-order traversal', priority: Priority.medium, due: _day(4), goalId: 'g1'),
      ];

  static List<Goal> goals() => [
        Goal(
          id: 'g1',
          title: 'Crack DSA interviews',
          category: 'Career',
          icon: LucideIcons.brain,
          color: LifeColors.iris,
          targetDate: _day(34),
          milestones: const [
            Milestone(id: 'm1', title: 'Arrays & hashing', done: true),
            Milestone(id: 'm2', title: 'Two pointers & sliding window', done: true),
            Milestone(id: 'm3', title: 'Trees & graphs'),
            Milestone(id: 'm4', title: 'Dynamic programming'),
          ],
        ),
        Goal(
          id: 'g2',
          title: 'Docker & Kubernetes fundamentals',
          category: 'Learning',
          icon: LucideIcons.layers,
          color: LifeColors.sky,
          progressType: GoalProgressType.milestones,
          targetDate: _day(21),
          milestones: const [
            Milestone(id: 'm5', title: 'Images and containers', done: true),
            Milestone(id: 'm6', title: 'Dockerfiles'),
            Milestone(id: 'm7', title: 'Compose & networking'),
            Milestone(id: 'm8', title: 'Deploy to a cluster'),
          ],
        ),
        Goal(
          id: 'g3',
          title: 'Ship LifeOS v1',
          category: 'Personal',
          icon: LucideIcons.rocket,
          color: LifeColors.coral,
          progressType: GoalProgressType.milestones,
          targetDate: _day(60),
          milestones: const [
            Milestone(id: 'm9', title: 'Architecture', done: true),
            Milestone(id: 'm10', title: 'UI shell', done: true),
            Milestone(id: 'm11', title: 'Backend', done: true),
            Milestone(id: 'm12', title: 'Connect app to API'),
            Milestone(id: 'm13', title: 'Daily driver on my phone'),
          ],
        ),
        Goal(
          id: 'g4',
          title: 'Read 12 books this year',
          category: 'Personal',
          icon: LucideIcons.bookOpen,
          color: LifeColors.mint,
          progressType: GoalProgressType.numeric,
          target: 12,
          current: 8,
          unit: 'books',
          targetDate: DateTime(_today.year, 12, 31),
        ),
      ];

  static Set<DateTime> _streak(int days, {Set<int> gaps = const {}, int startOffset = 0}) => {
        for (var i = startOffset; i < days + startOffset; i++)
          if (!gaps.contains(i)) _day(-i),
      };

  static List<Habit> habits() => [
        Habit(id: 'h1', title: 'Read', icon: LucideIcons.bookOpen, color: LifeColors.coral, startedOn: _day(-60), doneDays: _streak(12)),
        Habit(id: 'h2', title: 'Gym', icon: LucideIcons.activity, color: LifeColors.coral, startedOn: _day(-60), doneDays: _streak(20, gaps: {4, 9, 15})),
        Habit(id: 'h3', title: 'DSA', icon: LucideIcons.brain, color: LifeColors.coral, startedOn: _day(-45), doneDays: _streak(26, gaps: {13})),
        Habit(id: 'h4', title: 'Sleep by 11', icon: LucideIcons.moon, color: LifeColors.coral, startedOn: _day(-30), doneDays: _streak(9, startOffset: 1, gaps: {3})),
        Habit(id: 'h5', title: 'Water', icon: LucideIcons.zap, color: LifeColors.coral, startedOn: _day(-30), doneDays: _streak(30, gaps: {2, 7, 8, 20})),
      ];

  static List<ScheduleBlock> schedule() => [
        ScheduleBlock(id: 'b1', title: 'Gym', start: _at(0, 7), end: _at(0, 8), type: BlockType.other),
        ScheduleBlock(id: 'b2', title: 'Docker basics', start: _at(0, 14), end: _at(0, 15, 30), type: BlockType.study),
        ScheduleBlock(id: 'b3', title: 'DSA · Sliding window', start: _at(0, 19), end: _at(0, 20, 30), type: BlockType.focus),
        ScheduleBlock(id: 'b4', title: 'Daily review', start: _at(0, 21), end: _at(0, 21, 15), type: BlockType.other),
        ScheduleBlock(id: 'b5', title: 'Kubernetes intro', start: _at(1, 10), end: _at(1, 11, 30), type: BlockType.study),
        ScheduleBlock(id: 'b6', title: 'Mock interview', start: _at(2, 18), end: _at(2, 19), type: BlockType.task),
      ];

  // ---------- growth ----------

  static List<Skill> skills() => const [
        Skill(id: 'sk1', name: 'Java', icon: LucideIcons.coffee, color: LifeColors.coral, level: 4, target: 5, xp: 2340, weekMinutes: [40, 30, 0, 50, 20, 60, 30]),
        Skill(id: 'sk2', name: 'DSA', icon: LucideIcons.brain, color: LifeColors.iris, level: 3, target: 5, xp: 1980, weekMinutes: [60, 45, 30, 90, 40, 75, 55]),
        Skill(id: 'sk3', name: 'SQL', icon: LucideIcons.database, color: LifeColors.sky, level: 3, target: 4, xp: 910, weekMinutes: [0, 20, 0, 0, 25, 0, 15]),
        Skill(id: 'sk4', name: 'Flutter', icon: LucideIcons.smartphone, color: LifeColors.sky, level: 3, target: 4, xp: 1420, weekMinutes: [30, 0, 60, 40, 0, 90, 20]),
        Skill(id: 'sk5', name: 'Docker', icon: LucideIcons.container, color: LifeColors.mint, level: 2, target: 4, xp: 380, weekMinutes: [0, 0, 25, 0, 45, 0, 30]),
        Skill(id: 'sk6', name: 'Kubernetes', icon: LucideIcons.ship, color: LifeColors.mint, level: 1, target: 3, xp: 90, weekMinutes: [0, 0, 0, 0, 0, 20, 0]),
        Skill(id: 'sk7', name: 'Python', icon: LucideIcons.code, color: LifeColors.amber, level: 3, target: 4, xp: 1150, weekMinutes: [20, 40, 30, 0, 60, 0, 10]),
        Skill(id: 'sk8', name: 'Cloud', icon: LucideIcons.cloud, color: LifeColors.lilac, level: 2, target: 4, xp: 420, weekMinutes: [0, 15, 0, 20, 0, 0, 0]),
      ];

  static List<LearningPath> paths() => [
        LearningPath(
          id: 'p1',
          title: 'Java DSA roadmap',
          skillId: 'sk2',
          targetDate: _day(34),
          topics: [
            Topic(id: 'tp1', title: 'Arrays & hashing', difficulty: Difficulty.easy, status: TopicStatus.done, revisionCount: 2, nextRevision: _day(9), sessions: 4),
            Topic(id: 'tp2', title: 'Two pointers', difficulty: Difficulty.easy, status: TopicStatus.done, prerequisites: const ['tp1'], revisionCount: 1, nextRevision: _day(0), sessions: 3),
            Topic(id: 'tp3', title: 'Sliding window', difficulty: Difficulty.medium, status: TopicStatus.inProgress, prerequisites: const ['tp2'], sessions: 3, description: 'Fixed and variable windows, monotonic deque.'),
            const Topic(id: 'tp4', title: 'Stacks & monotonic stacks', prerequisites: ['tp2']),
            const Topic(id: 'tp5', title: 'Binary search', prerequisites: ['tp1']),
            const Topic(id: 'tp6', title: 'Trees & BST', prerequisites: ['tp4']),
            const Topic(id: 'tp7', title: 'Graphs: BFS / DFS', difficulty: Difficulty.hard, prerequisites: ['tp6']),
            const Topic(id: 'tp8', title: 'Dynamic programming', difficulty: Difficulty.hard, prerequisites: ['tp6', 'tp5']),
          ],
        ),
        LearningPath(
          id: 'p2',
          title: 'Docker → Kubernetes',
          skillId: 'sk5',
          targetDate: _day(21),
          topics: [
            Topic(id: 'tp9', title: 'Images and containers', difficulty: Difficulty.easy, status: TopicStatus.done, nextRevision: _day(2), sessions: 2),
            const Topic(id: 'tp10', title: 'Writing Dockerfiles', status: TopicStatus.inProgress, prerequisites: ['tp9'], sessions: 1),
            const Topic(id: 'tp11', title: 'Compose & networking', prerequisites: ['tp10']),
            const Topic(id: 'tp12', title: 'Pods & deployments', difficulty: Difficulty.hard, prerequisites: ['tp11']),
            const Topic(id: 'tp13', title: 'Services & ingress', difficulty: Difficulty.hard, prerequisites: ['tp12']),
          ],
        ),
      ];

  static List<StudySession> sessions() {
    final out = <StudySession>[];
    const pattern = [100, 75, 95, 140, 60, 120, 45, 80, 30, 110, 90, 70, 50, 130];
    for (var i = 0; i < pattern.length; i++) {
      out.add(StudySession(
        id: 'ss$i',
        start: _at(-i, i.isEven ? 19 : 14),
        minutes: i == 0 ? 130 : pattern[i],
        skillId: i % 3 == 0 ? 'sk2' : (i % 3 == 1 ? 'sk5' : 'sk4'),
        label: i % 3 == 0 ? 'Sliding window practice' : (i % 3 == 1 ? 'Docker basics' : 'Flutter UI'),
        problems: i % 3 == 0 ? 3 : 0,
      ));
    }
    return out;
  }

  static List<Project> projects() => [
        Project(
          id: 'pr1',
          name: 'LifeOS',
          stack: const ['Flutter', 'FastAPI', 'Postgres', 'Gemini'],
          progress: 0.45,
          color: LifeColors.iris,
          nextMilestone: 'Connect app to API',
          deadline: _day(60),
          description: 'Personal life OS with an approval-based AI agent.',
          milestones: const [
            Milestone(id: 'pm1', title: 'Architecture & UI plan', done: true),
            Milestone(id: 'pm2', title: 'Flutter UI shell', done: true),
            Milestone(id: 'pm3', title: 'Backend + tests', done: true),
            Milestone(id: 'pm4', title: 'Connect app to API'),
            Milestone(id: 'pm5', title: 'Release APK'),
          ],
        ),
        Project(
          id: 'pr2',
          name: 'K8s home lab',
          stack: const ['Docker', 'Kubernetes', 'Helm'],
          progress: 0.1,
          color: LifeColors.mint,
          nextMilestone: 'Run a 3-node kind cluster',
          deadline: _day(30),
          milestones: const [
            Milestone(id: 'pm6', title: 'Containerise a demo app', done: true),
            Milestone(id: 'pm7', title: 'Run a 3-node kind cluster'),
            Milestone(id: 'pm8', title: 'Deploy with Helm'),
          ],
        ),
        Project(
          id: 'pr3',
          name: 'Portfolio site',
          stack: const ['Next.js', 'Tailwind'],
          progress: 0.8,
          color: LifeColors.amber,
          nextMilestone: 'Add case studies',
          deadline: _day(10),
        ),
      ];

  // ---------- journal ----------

  static List<MoodEntry> moods() {
    const pattern = [3, 2, 3, 4, 1, 2, 3, 3, 4, 2, 3, 2, 1, 3, 4, 3, 2, 3, 3, 4, 2];
    return [
      for (var i = 1; i < pattern.length; i++)
        MoodEntry(day: _day(-i), mood: pattern[i], energy: 4 + pattern[i], motivation: 3 + pattern[i]),
    ];
  }

  static List<JournalEntry> journal() => [
        JournalEntry(
          id: 'j1',
          day: _day(-1),
          title: 'Finally understood DP',
          content:
              'Spent an hour on climbing stairs and house robber variations. Drawing the recurrence first, then the table, made it click. Want to try knapsack tomorrow.',
        ),
        JournalEntry(
          id: 'j2',
          day: _day(-3),
          title: 'Low energy but shipped',
          content: 'Didn’t sleep well. Still pushed the backend tests over the line. Small wins count.',
        ),
        JournalEntry(
          id: 'j3',
          day: _day(-6),
          content: 'Long day. The Docker networking docs are confusing — need a diagram before I continue.',
        ),
      ];

  // ---------- assistant ----------

  static List<Proposal> proposals() => [
        Proposal(
          id: 'pp1',
          groupId: 'grp-daily',
          actionType: 'schedule_block',
          summary: 'Block 9:00–10:30 tomorrow for sliding-window practice',
          reason: 'You finish most deep work before 1 PM.',
          origin: 'daily_review',
          payload: {'title': 'DSA · Sliding window', 'start': _at(1, 9).toIso8601String(), 'end': _at(1, 10, 30).toIso8601String(), 'type': 'focus'},
          changes: const [ProposalChange('When', 'Tomorrow · 9:00–10:30'), ProposalChange('Type', 'Focus block')],
        ),
        Proposal(
          id: 'pp2',
          groupId: 'grp-daily',
          actionType: 'reschedule_task',
          summary: 'Move “Update resume projects section” to tomorrow',
          reason: 'It’s overdue and high priority — tomorrow afternoon is free.',
          origin: 'daily_review',
          payload: {'task_id': 't10', 'due': _day(1).toIso8601String()},
          changes: const [ProposalChange('Due', 'Tomorrow', before: 'Yesterday')],
        ),
        Proposal(
          id: 'pp3',
          groupId: 'grp-daily',
          actionType: 'create_task',
          summary: 'Create task “Revise two pointers”',
          reason: 'Its spaced revision is due today.',
          origin: 'daily_review',
          payload: {'title': 'Revise two pointers', 'priority': 'low', 'due': _day(1).toIso8601String(), 'minutes': 20},
          changes: const [ProposalChange('Due', 'Tomorrow'), ProposalChange('Estimate', '20 min')],
        ),
      ];

  static List<ChatMessage> messages() => const [
        ChatMessage(
          id: 'c0',
          role: ChatRole.assistant,
          text: 'Hi Gaurav. You studied 8h 40m this week — your best week this month. I left three suggestions for tomorrow in Suggestions.',
        ),
      ];

  static List<Memory> memories() => const [
        Memory(id: 'mem1', type: MemoryType.profile, content: 'Software developer focusing on Java DSA, DevOps and Flutter.'),
        Memory(id: 'mem2', type: MemoryType.profile, content: 'Preparing for software engineering interviews next month.'),
        Memory(id: 'mem3', type: MemoryType.preference, content: 'Prefers step-by-step learning with small hands-on projects.'),
        Memory(id: 'mem4', type: MemoryType.preference, content: 'Studies best in the morning; evenings are for revision.'),
        Memory(id: 'mem5', type: MemoryType.episodic, content: 'Finished the LifeOS backend with 37 passing tests.'),
        Memory(id: 'mem6', type: MemoryType.summary, content: 'Last week: strong on DSA (5h), behind on Docker, habits steady at 82%.'),
        Memory(id: 'mem7', type: MemoryType.preference, content: 'Wants reviews to be short and specific.', proposed: true),
      ];

  static List<Achievement> achievements() => [
        Achievement(code: 'first_light', title: 'First Light', description: 'Complete your first task', icon: LucideIcons.sparkles, color: LifeColors.amber, unlockedAt: _day(-40)),
        Achievement(code: 'week_warrior', title: 'Week Warrior', description: 'Reach a 7-day habit streak', icon: LucideIcons.flame, color: LifeColors.coral, unlockedAt: _day(-20)),
        Achievement(code: 'deep_diver', title: 'Deep Diver', description: 'Study 3 hours in one day', icon: LucideIcons.timer, color: LifeColors.mint, unlockedAt: _day(-9)),
        Achievement(code: 'shipper', title: 'Shipper', description: 'Complete a project milestone', icon: LucideIcons.rocket, color: LifeColors.iris, unlockedAt: _day(-2)),
        const Achievement(code: 'consistent', title: 'Consistent', description: 'Reach a 30-day habit streak', icon: LucideIcons.calendarCheck, color: LifeColors.coral),
        const Achievement(code: 'pathfinder', title: 'Pathfinder', description: 'Finish a learning roadmap', icon: LucideIcons.map, color: LifeColors.sky),
        const Achievement(code: 'century', title: 'Century', description: 'Solve 100 problems', icon: LucideIcons.brain, color: LifeColors.iris),
        const Achievement(code: 'reflective', title: 'Reflective', description: 'Write 20 journal entries', icon: LucideIcons.notebookPen, color: LifeColors.rose),
      ];

  static const prompts = [
    'What drained your energy today?',
    'What’s one thing you learned today?',
    'What would make tomorrow a good day?',
    'What are you avoiding, and why?',
    'What went better than you expected?',
    'Who helped you this week?',
  ];

  static const moodTags = ['focused', 'tired', 'calm', 'anxious', 'motivated', 'social', 'sick', 'grateful'];
}

extension BlockTypeX on BlockType {
  Color get color => switch (this) {
        BlockType.study => LifeColors.mint,
        BlockType.focus => LifeColors.iris,
        BlockType.task => LifeColors.sky,
        BlockType.breakTime => LifeColors.amber,
        BlockType.other => LifeColors.rose,
      };

  String get label => switch (this) {
        BlockType.study => 'Study',
        BlockType.focus => 'Focus',
        BlockType.task => 'Task',
        BlockType.breakTime => 'Break',
        BlockType.other => 'Other',
      };
}

extension PriorityX on Priority {
  Color get color => switch (this) {
        Priority.high => LifeColors.priorityHigh,
        Priority.medium => LifeColors.priorityMedium,
        Priority.low => LifeColors.priorityLow,
      };

  String get label => switch (this) {
        Priority.high => 'High',
        Priority.medium => 'Medium',
        Priority.low => 'Low',
      };

  int get xp => switch (this) {
        Priority.high => 30,
        Priority.medium => 20,
        Priority.low => 10,
      };
}

extension DifficultyX on Difficulty {
  String get label => switch (this) {
        Difficulty.easy => 'Easy',
        Difficulty.medium => 'Medium',
        Difficulty.hard => 'Hard',
      };

  Color get color => switch (this) {
        Difficulty.easy => LifeColors.mint,
        Difficulty.medium => LifeColors.amber,
        Difficulty.hard => LifeColors.coral,
      };

  int get xp => switch (this) {
        Difficulty.easy => 30,
        Difficulty.medium => 40,
        Difficulty.hard => 60,
      };
}

/// Fallback icon when an IconData is needed for an unknown value.
const fallbackIcon = Icons.circle_outlined;

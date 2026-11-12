// In-memory app state backed by sample data. Each notifier mirrors a backend
// module; swapping these for API/Drift-backed repositories won't change screens.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:uuid/uuid.dart';

import '../core/theme/colors.dart';
import '../shell/quick_capture_parser.dart';
import 'models.dart';
import 'seed.dart';

const _uuid = Uuid();
String newId() => _uuid.v4();

// =====================================================================
// Auth & settings
// =====================================================================

class AuthState {
  const AuthState({this.signedIn = false, this.onboarded = false, this.name = 'Gaurav', this.email = ''});
  final bool signedIn;
  final bool onboarded;
  final String name;
  final String email;
  AuthState copyWith({bool? signedIn, bool? onboarded, String? name, String? email}) => AuthState(
        signedIn: signedIn ?? this.signedIn,
        onboarded: onboarded ?? this.onboarded,
        name: name ?? this.name,
        email: email ?? this.email,
      );
}

class AuthNotifier extends Notifier<AuthState> {
  static const _startSignedIn = bool.fromEnvironment('START_SIGNED_IN');

  @override
  AuthState build() => const AuthState(signedIn: _startSignedIn, onboarded: _startSignedIn, email: 'you@example.com');

  void completeOnboarding() => state = state.copyWith(onboarded: true);

  /// Mock sign-in (replaced by POST /auth/login).
  Future<String?> signIn(String email, String password) async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (password.length < 10) return 'Email or password is incorrect.';
    state = state.copyWith(signedIn: true, onboarded: true, email: email);
    return null;
  }

  /// Mock registration (replaced by POST /auth/register).
  Future<String?> register(String name, String email, String password) async {
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (password.length < 10) return 'Password must be at least 10 characters.';
    state = state.copyWith(signedIn: true, onboarded: true, name: name, email: email);
    return null;
  }

  void signOut() => state = state.copyWith(signedIn: false);

  void rename(String name) => state = state.copyWith(name: name);

  /// For tests / previews.
  void debugSignIn() => state = state.copyWith(signedIn: true, onboarded: true);
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
      );
}

class PrefsNotifier extends Notifier<Prefs> {
  @override
  Prefs build() => const Prefs();
  void update(Prefs Function(Prefs) f) => state = f(state);
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
  Progression build() => const Progression(totalXp: 5531, todayXp: 120);

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
  List<Task> build() => Seed.tasks();

  Task? byId(String id) => state.where((t) => t.id == id).firstOrNull;

  void add(Task t) => state = [...state, t];

  void update(Task t) => state = [for (final x in state) x.id == t.id ? t : x];

  void delete(String id) => state = state.where((t) => t.id != id).toList();

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
  List<Goal> build() => Seed.goals();

  void add(Goal g) => state = [...state, g];

  void toggleMilestone(String goalId, String milestoneId) {
    state = [
      for (final g in state)
        if (g.id == goalId)
          g.copyWith(milestones: [
            for (final m in g.milestones)
              if (m.id == milestoneId) () {
                if (!m.done) ref.read(progressionProvider.notifier).award(100);
                return m.copyWith(done: !m.done);
              }() else m,
          ])
        else
          g,
    ];
  }

  void setCurrent(String goalId, double value) =>
      state = [for (final g in state) g.id == goalId ? g.copyWith(current: value) : g];
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
      final linked = tasks.where((t) => t.goalId == g.id).toList();
      if (linked.isEmpty) {
        return g.milestones.isEmpty ? 0 : g.milestones.where((m) => m.done).length / g.milestones.length;
      }
      return linked.where((t) => t.done).length / linked.length;
  }
}

class HabitsNotifier extends Notifier<List<Habit>> {
  @override
  List<Habit> build() => Seed.habits();

  void add(Habit h) => state = [...state, h];

  void toggle(String id, [DateTime? day]) {
    final d = dateOnly(day ?? DateTime.now());
    state = [
      for (final h in state)
        if (h.id == id) () {
          final days = {...h.doneDays};
          if (days.remove(d)) {
            ref.read(progressionProvider.notifier).revoke(5);
          } else {
            days.add(d);
            ref.read(progressionProvider.notifier).award(5);
          }
          return h.copyWith(doneDays: days);
        }() else h,
    ];
  }
}

final habitsProvider = NotifierProvider<HabitsNotifier, List<Habit>>(HabitsNotifier.new);

class ScheduleNotifier extends Notifier<List<ScheduleBlock>> {
  @override
  List<ScheduleBlock> build() => Seed.schedule();
  void add(ScheduleBlock b) => state = [...state, b]..sort((a, b) => a.start.compareTo(b.start));
  void remove(String id) => state = state.where((b) => b.id != id).toList();
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
  LearningState build() =>
      LearningState(paths: Seed.paths(), skills: Seed.skills(), sessions: Seed.sessions(), projects: Seed.projects());

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
  }

  void startTopic(String pathId, String topicId) =>
      _updateTopic(pathId, topicId, (t) => t.status == TopicStatus.notStarted ? t.copyWith(status: TopicStatus.inProgress) : t);

  void reviseTopic(String pathId, String topicId) {
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
    return xp;
  }

  void addPath(LearningPath p) => state = state.copyWith(paths: [...state.paths, p]);

  void toggleProjectMilestone(String projectId, String milestoneId) {
    state = state.copyWith(projects: [
      for (final p in state.projects)
        if (p.id == projectId) () {
          final ms = [for (final m in p.milestones) m.id == milestoneId ? m.copyWith(done: !m.done) : m];
          final done = ms.where((m) => m.done).length;
          final was = p.milestones.firstWhere((m) => m.id == milestoneId).done;
          if (!was) ref.read(progressionProvider.notifier).award(80);
          return p.copyWith(milestones: ms, progress: ms.isEmpty ? p.progress : done / ms.length);
        }() else p,
    ]);
  }
}

final learningProvider = NotifierProvider<LearningNotifier, LearningState>(LearningNotifier.new);

final achievementsProvider = Provider<List<Achievement>>((ref) => Seed.achievements());

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
  JournalState build() => JournalState(entries: Seed.journal(), moods: Seed.moods());

  void saveMood(MoodEntry m) {
    final existing = state.moodOn(m.day);
    state = state.copyWith(moods: [m, ...state.moods.where((x) => !sameDay(x.day, m.day))]);
    if (existing == null) ref.read(progressionProvider.notifier).award(5);
  }

  void upsertEntry(JournalEntry e) {
    final exists = state.entries.any((x) => x.id == e.id);
    state = state.copyWith(entries: exists ? [for (final x in state.entries) x.id == e.id ? e : x] : [e, ...state.entries]);
    if (!exists && !state.entries.any((x) => x.id != e.id && sameDay(x.day, e.day))) {
      ref.read(progressionProvider.notifier).award(5);
    }
  }

  void deleteEntry(String id) => state = state.copyWith(entries: state.entries.where((e) => e.id != id).toList());
}

final journalProvider = NotifierProvider<JournalNotifier, JournalState>(JournalNotifier.new);

// =====================================================================
// Memories
// =====================================================================

class MemoriesNotifier extends Notifier<List<Memory>> {
  @override
  List<Memory> build() => Seed.memories();
  void add(Memory m) => state = [m, ...state];
  void keep(String id) => state = [for (final m in state) m.id == id ? m.copyWith(proposed: false) : m];
  void edit(String id, String content) => state = [for (final m in state) m.id == id ? m.copyWith(content: content) : m];
  void remove(String id) => state = state.where((m) => m.id != id).toList();
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

  @override
  AssistantState build() {
    ref.onDispose(() => _stream?.cancel());
    return AssistantState(messages: Seed.messages(), proposals: Seed.proposals());
  }

  Future<void> send(String text) async {
    if (text.trim().isEmpty || state.thinking) return;
    final user = ChatMessage(id: newId(), role: ChatRole.user, text: text.trim());
    state = state.copyWith(messages: [...state.messages, user], thinking: true);
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

  void approve(String id) {
    final p = state.proposal(id);
    if (p == null || p.status != ProposalStatus.pending) return;
    _apply(p);
    _setStatus([id], ProposalStatus.executed);
  }

  void approveGroup(String groupId, Set<String> excluded) {
    final group = state.proposals.where((p) => p.groupId == groupId && p.status == ProposalStatus.pending).toList();
    for (final p in group.where((p) => !excluded.contains(p.id))) {
      _apply(p);
    }
    _setStatus(group.where((p) => !excluded.contains(p.id)).map((p) => p.id), ProposalStatus.executed);
    _setStatus(excluded, ProposalStatus.rejected);
  }

  void reject(String id) => _setStatus([id], ProposalStatus.rejected);

  /// "Modify": edit the title/summary before approving — no AI call needed.
  void editTitle(String id, String title) {
    final p = state.proposal(id);
    if (p == null) return;
    final summary = p.summary.replaceFirst(RegExp(r'“[^”]*”'), '“$title”');
    state = state.copyWith(proposals: [
      for (final x in state.proposals) x.id == id ? x.copyWith(payload: {...x.payload, 'title': title}, summary: summary) : x,
    ]);
  }

  /// Daily-review "Plan tomorrow" (mock: re-adds the review suggestions if all handled).
  void clearChat() => state = state.copyWith(messages: Seed.messages());
}

final assistantProvider = NotifierProvider<AssistantNotifier, AssistantState>(AssistantNotifier.new);

/// Which Assistant tab to show (set by "Suggestions" banners elsewhere).
class AssistantTabNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void set(int i) => state = i;
}

final assistantTabProvider = NotifierProvider<AssistantTabNotifier, int>(AssistantTabNotifier.new);

/// Habit dots color helper.
Color habitColor(Habit h) => h.color;

// Domain models for the UI. Shapes mirror the backend API (ARCHITECTURE.md §8)
// so the sample stores can later be swapped for API/Drift-backed ones.

import 'package:flutter/material.dart';

import 'schedule.dart';

enum Priority { low, medium, high }

enum BlockType { task, study, focus, breakTime, other }

enum TopicStatus { notStarted, inProgress, done }

enum Difficulty { easy, medium, hard }

enum GoalProgressType { tasks, milestones, numeric }

enum ProposalStatus { pending, executed, rejected }

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

class Subtask {
  const Subtask({required this.id, required this.title, this.done = false});
  final String id;
  final String title;
  final bool done;
  Subtask copyWith({bool? done}) => Subtask(id: id, title: title, done: done ?? this.done);
}

class Task {
  const Task({
    required this.id,
    required this.title,
    this.description,
    this.priority = Priority.medium,
    this.due,
    this.hasTime = false,
    this.estimatedMinutes,
    this.goalId,
    this.done = false,
    this.completedAt,
    this.subtasks = const [],
    this.tags = const [],
    this.repeat = Schedule.once,
  });

  final String id;
  final String title;
  final String? description;
  final Schedule repeat; // repeating task: completing it creates the next one
  final Priority priority;
  final DateTime? due;
  final bool hasTime;
  final int? estimatedMinutes;
  final String? goalId;
  final bool done;
  final DateTime? completedAt;
  final List<Subtask> subtasks;
  final List<String> tags;

  bool isOverdue(DateTime now) {
    if (done || due == null) return false;
    return hasTime ? due!.isBefore(now) : dateOnly(due!).isBefore(dateOnly(now));
  }

  bool isDueOn(DateTime day) => due != null && sameDay(due!, day);

  Task copyWith({
    String? title,
    String? description,
    Priority? priority,
    DateTime? due,
    bool clearDue = false,
    bool? hasTime,
    int? estimatedMinutes,
    String? goalId,
    bool? done,
    DateTime? completedAt,
    bool clearCompleted = false,
    List<Subtask>? subtasks,
    Schedule? repeat,
  }) =>
      Task(
        id: id,
        title: title ?? this.title,
        description: description ?? this.description,
        priority: priority ?? this.priority,
        due: clearDue ? null : (due ?? this.due),
        hasTime: hasTime ?? this.hasTime,
        estimatedMinutes: estimatedMinutes ?? this.estimatedMinutes,
        goalId: goalId ?? this.goalId,
        done: done ?? this.done,
        completedAt: clearCompleted ? null : (completedAt ?? this.completedAt),
        subtasks: subtasks ?? this.subtasks,
        tags: tags,
        repeat: repeat ?? this.repeat,
      );
}

class Milestone {
  const Milestone({required this.id, required this.title, this.done = false, this.targetDate});
  final String id;
  final String title;
  final bool done;
  final DateTime? targetDate;
  Milestone copyWith({bool? done}) => Milestone(id: id, title: title, done: done ?? this.done, targetDate: targetDate);
}

class Goal {
  const Goal({
    required this.id,
    required this.title,
    required this.category,
    required this.icon,
    required this.color,
    this.progressType = GoalProgressType.tasks,
    this.target,
    this.current,
    this.unit,
    this.targetDate,
    this.milestones = const [],
    this.completed = false,
  });

  final String id;
  final String title;
  final String category;
  final IconData icon;
  final Color color;
  final GoalProgressType progressType;
  final double? target;
  final double? current;
  final String? unit;
  final DateTime? targetDate;
  final List<Milestone> milestones;
  final bool completed;

  Goal copyWith({List<Milestone>? milestones, double? current, bool? completed}) => Goal(
        id: id,
        title: title,
        category: category,
        icon: icon,
        color: color,
        progressType: progressType,
        target: target,
        current: current ?? this.current,
        unit: unit,
        targetDate: targetDate,
        milestones: milestones ?? this.milestones,
        completed: completed ?? this.completed,
      );
}

class Habit {
  const Habit({
    required this.id,
    required this.title,
    required this.icon,
    required this.color,
    required this.startedOn,
    this.doneDays = const {},
    this.reminder,
    this.schedule = Schedule.daily,
  });

  final String id;
  final String title;
  final IconData icon;
  final Color color;
  final DateTime startedOn;
  final Set<DateTime> doneDays; // date-only
  final TimeOfDay? reminder;
  final Schedule schedule;

  bool doneOn(DateTime day) => doneDays.contains(dateOnly(day));

  static DateTime _weekOf(DateTime d) => dateOnly(d).subtract(Duration(days: d.weekday - 1));

  int doneInWeekOf(DateTime day) {
    final start = _weekOf(day);
    return doneDays.where((d) => !d.isBefore(start) && d.isBefore(start.add(const Duration(days: 7)))).length;
  }

  /// Should it show up as "to do" on [day]? ("N× a week" stops once the week's target is met.)
  bool isDueOn(DateTime day) {
    if (!schedule.isDueOn(day, startedOn)) return false;
    if (schedule.countsWeeks) return doneOn(day) || doneInWeekOf(day) < schedule.perWeek;
    return true;
  }

  /// "day" or "week" — what [streak] counts.
  String get streakUnit => schedule.countsWeeks ? 'week' : 'day';

  /// Days (or weeks for "N× a week") in a row on schedule. Today / this week not
  /// done yet doesn't break it; days the habit isn't scheduled are skipped.
  int get streak => _runEndingAt(DateTime.now(), allowOpen: true);

  int get bestStreak {
    var best = 0;
    final today = dateOnly(DateTime.now());
    for (var d = dateOnly(startedOn); !d.isAfter(today); d = d.add(Duration(days: schedule.countsWeeks ? 7 : 1))) {
      final run = _runEndingAt(d, allowOpen: false);
      if (run > best) best = run;
    }
    return best;
  }

  int _runEndingAt(DateTime end, {required bool allowOpen}) {
    final start = dateOnly(startedOn).subtract(const Duration(days: 7));
    var n = 0;
    if (schedule.countsWeeks) {
      var wk = _weekOf(end);
      var first = true;
      while (!wk.isBefore(_weekOf(start))) {
        if (doneInWeekOf(wk) >= schedule.perWeek) {
          n++;
        } else if (!(first && allowOpen)) {
          break;
        }
        first = false;
        wk = wk.subtract(const Duration(days: 7));
      }
      return n;
    }
    final last = dateOnly(end);
    var day = last;
    for (var i = 0; i < 800 && !day.isBefore(start); i++, day = day.subtract(const Duration(days: 1))) {
      if (!schedule.isDueOn(day, startedOn) && !doneOn(day)) continue;
      if (doneOn(day)) {
        n++;
      } else if (!(allowOpen && day == last)) {
        break; // a scheduled day was missed (today doesn't count yet)
      }
    }
    return n;
  }

  Habit copyWith({Set<DateTime>? doneDays, TimeOfDay? reminder, bool clearReminder = false, Schedule? schedule}) => Habit(
        id: id,
        title: title,
        icon: icon,
        color: color,
        startedOn: startedOn,
        doneDays: doneDays ?? this.doneDays,
        reminder: clearReminder ? null : (reminder ?? this.reminder),
        schedule: schedule ?? this.schedule,
      );
}

class ScheduleBlock {
  const ScheduleBlock({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    this.type = BlockType.task,
  });

  final String id;
  final String title;
  final DateTime start;
  final DateTime end;
  final BlockType type;
}

class Skill {
  const Skill({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    required this.level,
    this.target = 4,
    this.xp = 0,
    this.weekMinutes = const [0, 0, 0, 0, 0, 0, 0],
  });

  final String id;
  final String name;
  final IconData icon;
  final Color color;
  final int level; // 1..5
  final int target;
  final int xp;
  final List<int> weekMinutes; // last 7 days

  int get skillPoints => xp ~/ 100;

  Skill copyWith({int? xp, List<int>? weekMinutes}) => Skill(
        id: id,
        name: name,
        icon: icon,
        color: color,
        level: level,
        target: target,
        xp: xp ?? this.xp,
        weekMinutes: weekMinutes ?? this.weekMinutes,
      );
}

class Topic {
  const Topic({
    required this.id,
    required this.title,
    this.difficulty = Difficulty.medium,
    this.status = TopicStatus.notStarted,
    this.prerequisites = const [],
    this.revisionCount = 0,
    this.nextRevision,
    this.sessions = 0,
    this.estimatedMinutes = 60,
    this.description,
  });

  final String id;
  final String title;
  final Difficulty difficulty;
  final TopicStatus status;
  final List<String> prerequisites;
  final int revisionCount;
  final DateTime? nextRevision;
  final int sessions;
  final int estimatedMinutes;
  final String? description;

  bool get revisionDue => nextRevision != null && !dateOnly(nextRevision!).isAfter(dateOnly(DateTime.now()));

  Topic copyWith({TopicStatus? status, int? revisionCount, DateTime? nextRevision, int? sessions}) => Topic(
        id: id,
        title: title,
        difficulty: difficulty,
        status: status ?? this.status,
        prerequisites: prerequisites,
        revisionCount: revisionCount ?? this.revisionCount,
        nextRevision: nextRevision ?? this.nextRevision,
        sessions: sessions ?? this.sessions,
        estimatedMinutes: estimatedMinutes,
        description: description,
      );
}

class LearningPath {
  const LearningPath({
    required this.id,
    required this.title,
    required this.skillId,
    required this.topics,
    this.targetDate,
  });

  final String id;
  final String title;
  final String? skillId;
  final List<Topic> topics;
  final DateTime? targetDate;

  double get progress =>
      topics.isEmpty ? 0 : topics.where((t) => t.status == TopicStatus.done).length / topics.length;

  Topic? get nextTopic => topics.where((t) => t.status != TopicStatus.done).firstOrNull;

  LearningPath copyWith({List<Topic>? topics}) =>
      LearningPath(id: id, title: title, skillId: skillId, topics: topics ?? this.topics, targetDate: targetDate);
}

class StudySession {
  const StudySession({
    required this.id,
    required this.start,
    required this.minutes,
    this.skillId,
    this.topicId,
    this.label = 'Study',
    this.problems = 0,
  });

  final String id;
  final DateTime start;
  final int minutes;
  final String? skillId;
  final String? topicId;
  final String label;
  final int problems;
}

class Project {
  const Project({
    required this.id,
    required this.name,
    required this.stack,
    required this.progress,
    required this.color,
    this.nextMilestone,
    this.deadline,
    this.description,
    this.milestones = const [],
  });

  final String id;
  final String name;
  final List<String> stack;
  final double progress;
  final Color color;
  final String? nextMilestone;
  final DateTime? deadline;
  final String? description;
  final List<Milestone> milestones;

  Project copyWith({List<Milestone>? milestones, double? progress}) => Project(
        id: id,
        name: name,
        stack: stack,
        progress: progress ?? this.progress,
        color: color,
        nextMilestone: nextMilestone,
        deadline: deadline,
        description: description,
        milestones: milestones ?? this.milestones,
      );
}

class MoodEntry {
  const MoodEntry({required this.day, required this.mood, this.energy = 5, this.motivation = 5, this.tags = const []});
  final DateTime day; // date-only
  final int mood; // 0..4
  final int energy; // 1..10
  final int motivation; // 1..10
  final List<String> tags;

  MoodEntry copyWith({int? mood, int? energy, int? motivation, List<String>? tags}) => MoodEntry(
        day: day,
        mood: mood ?? this.mood,
        energy: energy ?? this.energy,
        motivation: motivation ?? this.motivation,
        tags: tags ?? this.tags,
      );
}

class JournalEntry {
  const JournalEntry({
    required this.id,
    required this.day,
    required this.content,
    this.title,
    this.aiAllowed = false,
    this.prompt,
  });

  final String id;
  final DateTime day;
  final String? title;
  final String content;
  final bool aiAllowed;
  final String? prompt;

  int get wordCount => content.trim().isEmpty ? 0 : content.trim().split(RegExp(r'\s+')).length;

  JournalEntry copyWith({String? title, String? content, bool? aiAllowed}) => JournalEntry(
        id: id,
        day: day,
        title: title ?? this.title,
        content: content ?? this.content,
        aiAllowed: aiAllowed ?? this.aiAllowed,
        prompt: prompt,
      );
}

/// One field change shown on an approval card ("before → after").
class ProposalChange {
  const ProposalChange(this.label, this.after, {this.before});
  final String label;
  final String? before;
  final String after;
}

class Proposal {
  const Proposal({
    required this.id,
    required this.actionType,
    required this.summary,
    required this.reason,
    required this.origin,
    required this.payload,
    this.groupId,
    this.status = ProposalStatus.pending,
    this.changes = const [],
    this.payloadHash = '',
  });

  final String id;
  final String? groupId;
  final String payloadHash; // approval is bound to exactly what the user saw
  final String actionType; // create_task | create_learning_path | schedule_block | create_habit | reschedule_task
  final String summary;
  final String reason;
  final String origin; // chat | daily_review | weekly_review | quick_capture
  final Map<String, Object?> payload;
  final ProposalStatus status;
  final List<ProposalChange> changes;

  Proposal copyWith({ProposalStatus? status, Map<String, Object?>? payload, String? summary, List<ProposalChange>? changes}) =>
      Proposal(
        id: id,
        groupId: groupId,
        actionType: actionType,
        summary: summary ?? this.summary,
        reason: reason,
        origin: origin,
        payload: payload ?? this.payload,
        status: status ?? this.status,
        changes: changes ?? this.changes,
        payloadHash: payloadHash,
      );
}

enum ChatRole { user, assistant }

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    this.proposalIds = const [],
    this.streaming = false,
  });

  final String id;
  final ChatRole role;
  final String text;
  final List<String> proposalIds;
  final bool streaming;

  ChatMessage copyWith({String? text, bool? streaming}) => ChatMessage(
        id: id,
        role: role,
        text: text ?? this.text,
        proposalIds: proposalIds,
        streaming: streaming ?? this.streaming,
      );
}

enum MemoryType { profile, preference, episodic, summary }

class Memory {
  const Memory({required this.id, required this.type, required this.content, this.proposed = false});
  final String id;
  final MemoryType type;
  final String content;
  final bool proposed;
  Memory copyWith({String? content, bool? proposed}) =>
      Memory(id: id, type: type, content: content ?? this.content, proposed: proposed ?? this.proposed);
}

class Achievement {
  const Achievement({
    required this.code,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    this.unlockedAt,
  });

  final String code;
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final DateTime? unlockedAt;
}

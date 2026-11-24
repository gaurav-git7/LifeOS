// Offline-first sync with the LifeOS API (ARCHITECTURE.md §15).
//
// The engine keeps a *mirror* of the server rows (same shape as the API),
// cached on the phone. Screens read app models built from that mirror.
// Every change is written to the mirror immediately, queued in an outbox,
// and pushed in the background with the version it was based on. Pulls merge
// server changes (except rows with changes still waiting to be sent).

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/colors.dart';
import '../api/api_client.dart';
import '../models.dart';
import '../schedule.dart';
import '../stores.dart';
import '../styles.dart';

const projectMilestoneTag = 'project-milestone';

final _dateFmt = DateFormat('yyyy-MM-dd');
String dateStr(DateTime d) => _dateFmt.format(d);
String utcIso(DateTime d) => d.toUtc().toIso8601String();

DateTime? _parseDt(Object? v) => v == null ? null : DateTime.parse(v as String).toLocal();
DateTime? _parseDate(Object? v) => v == null ? null : DateTime.parse(v as String);
bool _deleted(Map<String, dynamic> r) => r['deleted_at'] != null;

enum SyncPhase { idle, syncing, offline, error }

class SyncStatus {
  const SyncStatus({this.phase = SyncPhase.idle, this.lastSync, this.pending = 0, this.message});
  final SyncPhase phase;
  final DateTime? lastSync;
  final int pending;
  final String? message;
}

class SyncStatusNotifier extends Notifier<SyncStatus> {
  @override
  SyncStatus build() => const SyncStatus();
  void set(SyncStatus s) => state = s;
}

final syncStatusProvider = NotifierProvider<SyncStatusNotifier, SyncStatus>(SyncStatusNotifier.new);

const syncEntities = [
  'tasks', 'goals', 'goal_milestones', 'habits', 'habit_logs', 'reminders', 'schedule_blocks', 'mood_entries',
  'journal_entries', 'learning_paths', 'skills', 'learning_topics', 'study_sessions', 'projects',
];

class SyncEngine {
  SyncEngine(this.ref);

  final Ref ref;
  final Map<String, Map<String, Map<String, dynamic>>> mirror = {for (final e in syncEntities) e: {}};
  final List<Map<String, dynamic>> outbox = [];
  String? cursor;
  Timer? _pushTimer;
  bool _pushing = false;
  final Set<String> _inFlight = {}; // change_ids sent and awaiting a reply
  Future<void>? _pulling;

  static const _cacheKey = 'lifeos_sync_cache_v1';
  static const _diagKey = 'lifeos_sync_diagnostics';

  ApiClient get api => ref.read(apiClientProvider);

  Future<void> _logDiagnostic({
    required String action,
    required int count,
    required int durationMs,
    required bool success,
    String? error,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_diagKey) ?? <String>[];
      final entry = jsonEncode({
        'at': DateTime.now().toUtc().toIso8601String(),
        'action': action,
        'count': count,
        'duration_ms': durationMs,
        'success': success,
        ...error == null ? const <String, dynamic>{} : {'error': error},
      });
      final updated = [entry, ...raw];
      if (updated.length > 30) updated.removeRange(30, updated.length);
      await prefs.setStringList(_diagKey, updated);
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> getDiagnostics() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_diagKey) ?? const [];
      return [for (final r in raw) Map<String, dynamic>.from(jsonDecode(r) as Map)];
    } catch (_) {
      return [];
    }
  }

  // ------------------------------------------------------------- cache

  Future<void> loadCache() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    if (raw == null) return;
    try {
      final d = jsonDecode(raw) as Map<String, dynamic>;
      cursor = d['cursor'] as String?;
      final m = d['mirror'] as Map<String, dynamic>;
      // Changes queued before the cache finished loading (e.g. at app start) are kept.
      final early = List.of(outbox);
      for (final e in syncEntities) {
        final keep = {for (final c in early.where((c) => c['entity'] == e)) c['id'] as String: mirror[e]![c['id']]};
        mirror[e] = {
          for (final r in ((m[e] as Map?) ?? {}).entries) r.key as String: Map<String, dynamic>.from(r.value as Map),
          for (final k in keep.entries)
            if (k.value != null) k.key: k.value!,
        };
      }
      outbox
        ..clear()
        ..addAll([for (final c in (d['outbox'] as List? ?? [])) Map<String, dynamic>.from(c as Map)])
        ..addAll(early);
    } catch (_) {
      // corrupt cache: start fresh
    }
  }

  Future<void> _saveCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheKey, jsonEncode({'cursor': cursor, 'mirror': mirror, 'outbox': outbox}));
  }

  Future<void> clear() async {
    _pushTimer?.cancel();
    for (final e in syncEntities) {
      mirror[e] = {};
    }
    outbox.clear();
    cursor = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheKey);
  }

  // ------------------------------------------------------------- reads

  Iterable<Map<String, dynamic>> rows(String entity) => mirror[entity]!.values.where((r) => !_deleted(r));

  Map<String, dynamic>? row(String entity, String id) => mirror[entity]![id];

  // ------------------------------------------------------------- writes

  /// Records a change locally and schedules a push. [data] uses API field names.
  /// [sendBase] false = last write wins (used for habit logs, keyed by day on the server).
  void queue(String entity, String id, Map<String, dynamic> data, {bool delete = false, bool sendBase = true}) {
    final existing = mirror[entity]![id];
    final base = existing?['version'] as int?;
    final now = utcIso(DateTime.now());
    if (delete) {
      if (existing == null) return;
      existing['deleted_at'] = now;
    } else {
      mirror[entity]![id] = {
        ...?existing,
        ...data,
        'id': id,
        'updated_at': now,
        'created_at': existing?['created_at'] ?? now,
        'deleted_at': null,
      };
    }
    // Several quick edits to the same item (e.g. journal autosave) become one
    // change, as long as that change hasn't been sent yet. Only the newest
    // change is merged into, so the order of changes is kept.
    final last = outbox.lastOrNull;
    if (!delete &&
        last != null &&
        last['entity'] == entity &&
        last['id'] == id &&
        last['op'] == 'upsert' &&
        !_inFlight.contains(last['change_id'])) {
      last['data'] = {...(last['data'] as Map).cast<String, dynamic>(), ...data};
      _afterQueue();
      return;
    }
    mirror[entity]![id]!['version'] = (base ?? 0) + 1;
    outbox.add({
      'change_id': 'c-${DateTime.now().microsecondsSinceEpoch}-${outbox.length}',
      'entity': entity,
      'op': delete ? 'delete' : 'upsert',
      'id': id,
      'base_version': sendBase ? base : null,
      'data': delete ? <String, dynamic>{} : data,
    });
    _afterQueue();
  }

  void _afterQueue() {
    _status();
    _pushTimer?.cancel();
    _pushTimer = Timer(const Duration(milliseconds: 400), push);
    unawaited(_saveCache());
  }

  void _status({SyncPhase? phase, String? message}) {
    final current = ref.read(syncStatusProvider);
    ref.read(syncStatusProvider.notifier).set(SyncStatus(
          phase: phase ?? current.phase,
          lastSync: current.lastSync,
          pending: outbox.length,
          message: message,
        ));
  }

  // ------------------------------------------------------------- entity helpers

  void saveTask(Task t, {Task? before}) {
    queue('tasks', t.id, taskData(t));
    for (final (i, s) in t.subtasks.indexed) {
      final old = before?.subtasks.where((x) => x.id == s.id).firstOrNull;
      if (old != null && old.done == s.done && old.title == s.title) continue;
      queue('tasks', s.id, {
        'title': s.title,
        'status': s.done ? 'done' : 'todo',
        'sort_order': i,
        if (old == null) 'parent_task_id': t.id,
      });
    }
    for (final s in before?.subtasks ?? const <Subtask>[]) {
      if (!t.subtasks.any((x) => x.id == s.id)) queue('tasks', s.id, const {}, delete: true);
    }
  }

  void saveMilestone(String goalId, Milestone m, int order) => queue('goal_milestones', m.id, {
        'goal_id': goalId,
        'title': m.title,
        'target_date': m.targetDate == null ? null : dateStr(m.targetDate!),
        'sort_order': order,
        'completed_at': m.done ? utcIso(DateTime.now()) : null,
      });

  void saveTopic(String pathId, String? skillId, Topic t, int order) => queue('learning_topics', t.id, {
        'learning_path_id': pathId,
        'skill_id': skillId,
        'title': t.title,
        'description': t.description,
        'difficulty': t.difficulty.name,
        'sort_order': order,
        'estimated_minutes': t.estimatedMinutes,
      });

  void saveProjectMilestone(String projectId, Milestone m, int order) => queue('tasks', m.id, {
        'title': m.title,
        'project_id': projectId,
        'tags': [projectMilestoneTag],
        'status': m.done ? 'done' : 'todo',
        'sort_order': order,
      });

  /// For actions with their own endpoint (topic complete/revise): send pending
  /// changes first so the row exists, call, then pull the results.
  void callAndSync(Future<dynamic> Function(ApiClient api) call) {
    unawaited(() async {
      try {
        await push();
        await call(api);
        await pull();
      } on ApiException catch (e) {
        _status(phase: e.isNetwork ? SyncPhase.offline : SyncPhase.error, message: e.message);
      }
    }());
  }

  // ------------------------------------------------------------- network

  Future<void> push() async {
    if (_pushing || outbox.isEmpty) return;
    _pushing = true;
    final batch = List<Map<String, dynamic>>.from(outbox.take(200));
    _inFlight.addAll(batch.map((c) => c['change_id'] as String));
    var needsPull = false;
    final sw = Stopwatch()..start();
    try {
      _status(phase: SyncPhase.syncing);
      final results = await api.post<List<dynamic>>('/sync/push', data: {'changes': batch});
      if (!ref.mounted) return;
      for (final r in results.cast<Map<String, dynamic>>()) {
        final entity = batch.firstWhere((c) => c['change_id'] == r['change_id'])['entity'] as String;
        final id = r['id'] as String;
        switch (r['status']) {
          case 'applied':
            // Keep the higher number: newer local edits may already be queued on top.
            final row = mirror[entity]![id];
            final v = r['version'] as int?;
            if (row != null && v != null && v > (row['version'] as int? ?? 0)) row['version'] = v;
          case 'conflict':
            if (r['server'] != null) mirror[entity]![id] = Map<String, dynamic>.from(r['server'] as Map);
            needsPull = true;
          default: // rejected: the server's copy wins on the next pull
            mirror[entity]!.remove(id);
            needsPull = true;
            _status(message: 'A change couldn’t be saved: ${r['error'] ?? 'rejected'}');
        }
      }
      outbox.removeWhere((c) => batch.any((b) => b['change_id'] == c['change_id']));
      await _saveCache();
      _status(phase: SyncPhase.idle);
      unawaited(_logDiagnostic(action: 'push', count: batch.length, durationMs: sw.elapsedMilliseconds, success: true));
      // Server-side effects (XP, streaks, next recurring task) arrive via pull.
      // A pull that started before this push may carry older rows: wait for it,
      // then pull again.
      await _pulling;
      await pull();
      if (needsPull) publish();
    } on ApiException catch (e) {
      unawaited(_logDiagnostic(action: 'push', count: batch.length, durationMs: sw.elapsedMilliseconds, success: false, error: e.message));
      if (ref.mounted) _status(phase: e.isNetwork ? SyncPhase.offline : SyncPhase.error, message: e.isNetwork ? null : e.message);
    } finally {
      _pushing = false;
      _inFlight.removeAll(batch.map((c) => c['change_id']));
    }
    if (ref.mounted && outbox.isNotEmpty && ref.read(syncStatusProvider).phase == SyncPhase.idle) {
      _pushTimer = Timer(const Duration(milliseconds: 200), push);
    }
  }

  Future<void> pull() => _pulling ??= _pull().whenComplete(() => _pulling = null);

  Future<void> _pull() async {
    final sw = Stopwatch()..start();
    var pulledCount = 0;
    try {
      _status(phase: SyncPhase.syncing);
      var more = true;
      while (more) {
        final res = await api.get<Map<String, dynamic>>('/sync/pull', query: {'since': ?cursor});
        if (!ref.mounted) return;
        final changes = res['changes'] as Map<String, dynamic>;
        final pendingIds = {for (final c in outbox) '${c['entity']}/${c['id']}'};
        for (final e in syncEntities) {
          for (final r in (changes[e] as List? ?? const [])) {
            pulledCount++;
            final row = Map<String, dynamic>.from(r as Map);
            final id = row['id'] as String;
            if (pendingIds.contains('$e/$id')) continue; // local change not sent yet wins for now
            // Never step back to an older copy (a reply that crossed a newer push).
            final local = mirror[e]![id];
            if (local != null && (local['version'] as int? ?? 0) > (row['version'] as int? ?? 0)) continue;
            mirror[e]![id] = row;
          }
        }
        cursor = res['cursor'] as String?;
        more = res['has_more'] == true;
      }
      await _saveCache();
      if (!ref.mounted) return;
      publish();
      await ref.read(progressionProvider.notifier).refreshFromServer();
      if (!ref.mounted) return;
      ref.read(syncStatusProvider.notifier).set(SyncStatus(lastSync: DateTime.now(), pending: outbox.length));
      unawaited(_logDiagnostic(action: 'pull', count: pulledCount, durationMs: sw.elapsedMilliseconds, success: true));
    } on ApiException catch (e) {
      unawaited(_logDiagnostic(action: 'pull', count: pulledCount, durationMs: sw.elapsedMilliseconds, success: false, error: e.message));
      if (ref.mounted) _status(phase: e.isNetwork ? SyncPhase.offline : SyncPhase.error, message: e.isNetwork ? null : e.message);
    }
  }

  /// Push anything waiting, then pull. Used at sign-in, app resume and pull-to-refresh.
  Future<void> syncNow() async {
    await push();
    await pull();
  }

  // ------------------------------------------------------------- server rows → app models

  void publish() {
    final sessions = rows('study_sessions').map(_session).toList()..sort((a, b) => b.start.compareTo(a.start));
    final allTasks = rows('tasks').toList();
    ref.read(tasksProvider.notifier).replaceAll(_tasks(allTasks));
    ref.read(goalsProvider.notifier).replaceAll(_goals());
    ref.read(habitsProvider.notifier).replaceAll(_habits());
    ref.read(scheduleProvider.notifier).replaceAll(_blocks());
    ref.read(learningProvider.notifier).replaceAll(LearningState(
          paths: _paths(sessions),
          skills: _skills(sessions),
          sessions: sessions,
          projects: _projects(allTasks),
        ));
    ref.read(journalProvider.notifier).replaceAll(JournalState(entries: _journal(), moods: _moods()));
  }

  List<Task> _tasks(List<Map<String, dynamic>> all) {
    final children = <String, List<Subtask>>{};
    for (final r in all.where((r) => r['parent_task_id'] != null)) {
      children.putIfAbsent(r['parent_task_id'] as String, () => []).add(
            Subtask(id: r['id'] as String, title: r['title'] as String, done: r['status'] == 'done'),
          );
    }
    return [
      for (final r in all)
        if (r['parent_task_id'] == null && !((r['tags'] as List?) ?? const []).contains(projectMilestoneTag))
          taskFromRow(r, children[r['id']] ?? const []),
    ];
  }

  static Task taskFromRow(Map<String, dynamic> r, List<Subtask> subtasks) {
    final dueAt = _parseDt(r['due_at']);
    return Task(
      id: r['id'] as String,
      title: r['title'] as String,
      description: r['description'] as String?,
      priority: Priority.values.asNameMap()[r['priority']] ?? Priority.medium,
      due: dueAt ?? _parseDate(r['due_date']),
      hasTime: dueAt != null,
      estimatedMinutes: r['estimated_minutes'] as int?,
      goalId: r['goal_id'] as String?,
      done: r['status'] == 'done',
      completedAt: _parseDt(r['completed_at']),
      subtasks: subtasks,
      tags: [for (final t in (r['tags'] as List? ?? const [])) t as String],
      repeat: Schedule.fromRRule(r['recurrence_rule'] as String?),
    );
  }

  static Map<String, dynamic> taskData(Task t, {String? projectId, String? parentId}) => {
        'title': t.title,
        'description': t.description,
        'priority': t.priority.name,
        'due_at': t.hasTime && t.due != null ? utcIso(t.due!) : null,
        'due_date': !t.hasTime && t.due != null ? dateStr(t.due!) : null,
        'estimated_minutes': t.estimatedMinutes,
        'goal_id': t.goalId,
        'status': t.done ? 'done' : 'todo',
        'tags': t.tags,
        'recurrence_rule': t.repeat.toRRule(),
        'project_id': ?projectId,
        'parent_task_id': ?parentId,
      };

  List<Goal> _goals() {
    final ms = <String, List<Map<String, dynamic>>>{};
    for (final m in rows('goal_milestones')) {
      ms.putIfAbsent(m['goal_id'] as String, () => []).add(m);
    }
    return [
      for (final r in rows('goals'))
        if (r['status'] != 'archived')
          () {
            final (icon, color) = goalStyle((r['category'] as String?) ?? 'other');
            final list = (ms[r['id']] ?? [])..sort((a, b) => (a['sort_order'] as int? ?? 0).compareTo(b['sort_order'] as int? ?? 0));
            return Goal(
              id: r['id'] as String,
              title: r['title'] as String,
              category: categoryLabel((r['category'] as String?) ?? 'other'),
              icon: icon,
              color: color,
              progressType: switch (r['progress_type']) {
                'numeric' => GoalProgressType.numeric,
                'milestones' => GoalProgressType.milestones,
                _ => GoalProgressType.tasks,
              },
              target: (r['target_value'] as num?)?.toDouble(),
              current: (r['current_value'] as num?)?.toDouble(),
              unit: r['unit'] as String?,
              targetDate: _parseDate(r['target_date']),
              completed: r['status'] == 'completed',
              milestones: [
                for (final m in list)
                  Milestone(
                    id: m['id'] as String,
                    title: m['title'] as String,
                    done: m['completed_at'] != null,
                    targetDate: _parseDate(m['target_date']),
                  ),
              ],
            );
          }(),
    ];
  }

  List<Habit> _habits() {
    final done = <String, Set<DateTime>>{};
    for (final l in rows('habit_logs').where((l) => l['status'] == 'done')) {
      done.putIfAbsent(l['habit_id'] as String, () => {}).add(_parseDate(l['log_date'])!);
    }
    return [
      for (final r in rows('habits'))
        if (r['active'] != false)
          Habit(
            id: r['id'] as String,
            title: r['title'] as String,
            icon: habitIcon(r['title'] as String),
            color: LifeColors.coral,
            startedOn: dateOnly(_parseDt(r['created_at']) ?? DateTime.now()),
            doneDays: done[r['id']] ?? {},
            shared: r['visibility'] == 'friends',
            schedule: Schedule.fromRRule(r['recurrence_rule'] as String? ?? 'FREQ=DAILY', target: r['target_per_period'] as int? ?? 1),
            reminder: r['reminder_time'] == null
                ? null
                : TimeOfDay(
                    hour: int.parse((r['reminder_time'] as String).substring(0, 2)),
                    minute: int.parse((r['reminder_time'] as String).substring(3, 5)),
                  ),
          ),
    ];
  }

  /// Id of the habit_logs row for (habit, day), if any.
  String? habitLogId(String habitId, DateTime day) {
    final d = dateStr(day);
    for (final l in mirror['habit_logs']!.values) {
      if (l['habit_id'] == habitId && l['log_date'] == d) return l['id'] as String;
    }
    return null;
  }

  static const _blockTypes = {'break': BlockType.breakTime};

  List<ScheduleBlock> _blocks() => [
        for (final r in rows('schedule_blocks'))
          ScheduleBlock(
            id: r['id'] as String,
            title: r['title'] as String,
            start: _parseDt(r['start_at'])!,
            end: _parseDt(r['end_at'])!,
            type: _blockTypes[r['block_type']] ?? BlockType.values.asNameMap()[r['block_type']] ?? BlockType.other,
          ),
      ]..sort((a, b) => a.start.compareTo(b.start));

  static String blockTypeName(BlockType t) => t == BlockType.breakTime ? 'break' : t.name;

  StudySession _session(Map<String, dynamic> r) => StudySession(
        id: r['id'] as String,
        start: _parseDt(r['started_at'])!,
        minutes: r['duration_minutes'] as int? ?? 0,
        skillId: r['skill_id'] as String?,
        topicId: r['topic_id'] as String?,
        label: (r['notes'] as String?) ?? 'Study session',
        problems: r['problems_solved'] as int? ?? 0,
      );

  List<Skill> _skills(List<StudySession> sessions) {
    final today = dateOnly(DateTime.now());
    return [
      for (final r in rows('skills'))
        () {
          final (icon, color) = skillStyle(r['name'] as String);
          final week = [
            for (var i = 6; i >= 0; i--)
              sessions
                  .where((s) => s.skillId == r['id'] && sameDay(s.start, today.subtract(Duration(days: i))))
                  .fold(0, (a, s) => a + s.minutes),
          ];
          return Skill(
            id: r['id'] as String,
            name: r['name'] as String,
            icon: icon,
            color: color,
            level: (r['current_level'] as int? ?? 1).clamp(1, 5),
            target: (r['target_level'] as int? ?? 3).clamp(1, 5),
            xp: r['skill_xp'] as int? ?? 0,
            weekMinutes: week,
          );
        }(),
    ];
  }

  List<LearningPath> _paths(List<StudySession> sessions) {
    final topics = <String, List<Map<String, dynamic>>>{};
    for (final t in rows('learning_topics')) {
      topics.putIfAbsent(t['learning_path_id'] as String, () => []).add(t);
    }
    return [
      for (final p in rows('learning_paths'))
        if (p['status'] != 'archived')
          () {
            final list = (topics[p['id']] ?? [])
              ..sort((a, b) => (a['sort_order'] as int? ?? 0).compareTo(b['sort_order'] as int? ?? 0));
            return LearningPath(
              id: p['id'] as String,
              title: p['title'] as String,
              skillId: list.map((t) => t['skill_id'] as String?).whereType<String>().firstOrNull,
              targetDate: _parseDate(p['target_date']),
              topics: [
                for (final t in list)
                  Topic(
                    id: t['id'] as String,
                    title: t['title'] as String,
                    description: t['description'] as String?,
                    difficulty: Difficulty.values.asNameMap()[t['difficulty']] ?? Difficulty.medium,
                    status: switch (t['status']) {
                      'done' => TopicStatus.done,
                      'in_progress' => TopicStatus.inProgress,
                      _ => TopicStatus.notStarted,
                    },
                    prerequisites: [for (final x in (t['prerequisite_ids'] as List? ?? const [])) x as String],
                    revisionCount: t['revision_count'] as int? ?? 0,
                    nextRevision: _parseDate(t['next_revision_at']),
                    sessions: sessions.where((s) => s.topicId == t['id']).length,
                    estimatedMinutes: t['estimated_minutes'] as int? ?? 60,
                  ),
              ],
            );
          }(),
    ];
  }

  List<Project> _projects(List<Map<String, dynamic>> allTasks) {
    final byProject = <String, List<Map<String, dynamic>>>{};
    for (final t in allTasks.where((t) => ((t['tags'] as List?) ?? const []).contains(projectMilestoneTag))) {
      final pid = t['project_id'] as String?;
      if (pid != null) byProject.putIfAbsent(pid, () => []).add(t);
    }
    return [
      for (final r in rows('projects'))
        if (r['status'] != 'archived')
          () {
            final ms = (byProject[r['id']] ?? [])
              ..sort((a, b) => (a['sort_order'] as int? ?? 0).compareTo(b['sort_order'] as int? ?? 0));
            final milestones = [
              for (final m in ms) Milestone(id: m['id'] as String, title: m['title'] as String, done: m['status'] == 'done'),
            ];
            final done = milestones.where((m) => m.done).length;
            return Project(
              id: r['id'] as String,
              name: r['name'] as String,
              description: r['description'] as String?,
              stack: [for (final s in (r['tech_stack'] as List? ?? const [])) s as String],
              progress: milestones.isEmpty ? (r['progress_pct'] as int? ?? 0) / 100 : done / milestones.length,
              color: projectColor(r['name'] as String),
              deadline: _parseDate(r['target_date']),
              nextMilestone: milestones.where((m) => !m.done).firstOrNull?.title,
              milestones: milestones,
            );
          }(),
    ];
  }

  List<MoodEntry> _moods() {
    final byDay = <DateTime, Map<String, dynamic>>{};
    for (final r in rows('mood_entries')) {
      final day = dateOnly(_parseDt(r['recorded_at'])!);
      final prev = byDay[day];
      if (prev == null || (r['recorded_at'] as String).compareTo(prev['recorded_at'] as String) > 0) byDay[day] = r;
    }
    return [
      for (final e in byDay.entries)
        MoodEntry(
          day: e.key,
          mood: ((e.value['mood'] as int? ?? 3) - 1).clamp(0, 4),
          energy: e.value['energy'] as int? ?? 5,
          motivation: e.value['motivation'] as int? ?? 5,
          tags: [for (final t in (e.value['tags'] as List? ?? const [])) t as String],
        ),
    ];
  }

  /// Id of the mood row for a local day (one check-in per day in the app).
  String? moodIdFor(DateTime day) {
    for (final r in rows('mood_entries')) {
      if (sameDay(_parseDt(r['recorded_at'])!, day)) return r['id'] as String;
    }
    return null;
  }

  List<JournalEntry> _journal() => [
        for (final r in rows('journal_entries'))
          JournalEntry(
            id: r['id'] as String,
            day: _parseDate(r['entry_date']) ?? dateOnly(DateTime.now()),
            title: r['title'] as String?,
            content: (r['content'] as String?) ?? '',
            aiAllowed: r['ai_allowed'] == true,
          ),
      ];
}

final syncEngineProvider = Provider<SyncEngine>((ref) {
  final engine = SyncEngine(ref);
  ref.onDispose(() => engine._pushTimer?.cancel());
  return engine;
});

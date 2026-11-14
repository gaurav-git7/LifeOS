// The focus timer, kept outside the screen so it survives leaving the screen,
// the app, or a restart. Time is computed from saved start/end times, not by
// counting ticks. While running: a live countdown notification, a "session
// complete" alert at the end, and (optionally) Do Not Disturb.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import '../reminders/reminder_service.dart';
import '../stores.dart';
import '../system_channel.dart';

class FocusState {
  const FocusState({
    this.minutes = 25,
    this.skillId,
    this.topicId,
    this.label,
    this.startedAt,
    this.accumulated = 0,
    this.dnd = false,
  });

  final int minutes;
  final String? skillId;
  final String? topicId;
  final String? label;
  final DateTime? startedAt; // set while running
  final int accumulated; // seconds before the current run
  final bool dnd; // Do Not Disturb while focusing (remembered)

  bool get running => startedAt != null;
  int get total => minutes * 60;
  int elapsedAt(DateTime now) =>
      (accumulated + (startedAt == null ? 0 : now.difference(startedAt!).inSeconds)).clamp(0, total);
  int get elapsed => elapsedAt(DateTime.now());
  bool get active => running || accumulated > 0;
  DateTime? get endsAt => startedAt?.add(Duration(seconds: total - accumulated));

  FocusState copyWith({
    int? minutes,
    String? skillId,
    String? topicId,
    String? label,
    DateTime? startedAt,
    bool clearStart = false,
    int? accumulated,
    bool? dnd,
  }) =>
      FocusState(
        minutes: minutes ?? this.minutes,
        skillId: skillId ?? this.skillId,
        topicId: topicId ?? this.topicId,
        label: label ?? this.label,
        startedAt: clearStart ? null : (startedAt ?? this.startedAt),
        accumulated: accumulated ?? this.accumulated,
        dnd: dnd ?? this.dnd,
      );

  Map<String, Object?> toJson() => {
        'minutes': minutes,
        'skillId': skillId,
        'topicId': topicId,
        'label': label,
        'startedAt': startedAt?.toIso8601String(),
        'accumulated': accumulated,
        'dnd': dnd,
      };

  static FocusState fromJson(Map<String, dynamic> j) => FocusState(
        minutes: j['minutes'] as int? ?? 25,
        skillId: j['skillId'] as String?,
        topicId: j['topicId'] as String?,
        label: j['label'] as String?,
        startedAt: j['startedAt'] == null ? null : DateTime.parse(j['startedAt'] as String),
        accumulated: j['accumulated'] as int? ?? 0,
        dnd: j['dnd'] as bool? ?? false,
      );
}

/// Result of a finished session (for the "Session saved" sheet).
typedef FocusResult = ({int minutes, int xp, String? topic});

class FocusController extends Notifier<FocusState> {
  static const _key = 'lifeos_focus_session';

  @override
  FocusState build() {
    Future.microtask(_restore);
    return const FocusState();
  }

  Future<void> _restore() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw == null || !ref.mounted) return;
      state = FocusState.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
      // Ended while the app was closed: save it so the study time isn't lost.
      if (state.running && state.elapsed >= state.total) finish();
    } catch (_) {}
  }

  void _save() {
    final json = jsonEncode(state.toJson());
    unawaited(SharedPreferences.getInstance().then((p) => p.setString(_key, json)).then<void>((_) {}, onError: (_) {}));
  }

  ReminderService get _notify => ref.read(reminderServiceProvider);

  /// Choose what to study (only before starting).
  void setup({int? minutes, String? skillId, String? topicId, String? label}) {
    if (state.active) return;
    state = state.copyWith(minutes: minutes, skillId: skillId, topicId: topicId, label: label);
    _save();
  }

  void setDnd(bool on) {
    state = state.copyWith(dnd: on);
    _save();
    if (state.running) unawaited(SystemChannel.setDnd(on, until: state.endsAt));
  }

  void start() {
    if (state.running || state.elapsed >= state.total) return;
    state = state.copyWith(startedAt: DateTime.now());
    _save();
    final end = state.endsAt!;
    unawaited(_notify.showFocus(end, state.label ?? 'Focus session'));
    if (state.dnd) unawaited(SystemChannel.setDnd(true, until: end));
  }

  void pause() {
    if (!state.running) return;
    state = state.copyWith(accumulated: state.elapsed, clearStart: true);
    _save();
    _stopSideEffects();
  }

  void reset() {
    state = FocusState(minutes: state.minutes, skillId: state.skillId, dnd: state.dnd);
    _save();
    _stopSideEffects();
  }

  void _stopSideEffects() {
    unawaited(_notify.cancelFocus());
    if (state.dnd) unawaited(SystemChannel.setDnd(false));
  }

  /// Saves the study session (if at least a minute) and resets. Returns null if too short.
  FocusResult? finish() {
    final seconds = state.elapsed;
    final s = state;
    reset();
    final minutes = (seconds / 60).round();
    if (minutes < 1) return null;
    final learning = ref.read(learningProvider);
    final skill = learning.skill(s.skillId);
    final xp = ref.read(learningProvider.notifier).addSession(StudySession(
          id: newId(),
          start: DateTime.now().subtract(Duration(seconds: seconds)),
          minutes: minutes,
          skillId: s.skillId,
          topicId: s.topicId,
          label: s.label ?? '${skill?.name ?? 'Study'} focus',
        ));
    return (minutes: minutes, xp: xp, topic: s.label);
  }
}

final focusProvider = NotifierProvider<FocusController, FocusState>(FocusController.new);

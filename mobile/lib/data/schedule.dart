// How often a task repeats or a habit is due. Stored on the server as an
// RFC 5545 RRULE (+ target_per_period for "N times a week"), same as the backend.

import 'models.dart' show dateOnly;

enum Repeat { none, daily, weekdays, days, everyN, perWeek, monthly }

class Schedule {
  const Schedule(this.kind, {this.days = const {}, this.interval = 2, this.perWeek = 3});

  static const once = Schedule(Repeat.none);
  static const daily = Schedule(Repeat.daily);

  final Repeat kind;
  final Set<int> days; // 1 = Monday … 7 = Sunday (Repeat.days)
  final int interval; // every N days (Repeat.everyN)
  final int perWeek; // N times a week (Repeat.perWeek)

  static const _codes = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];
  static const dayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  Schedule copyWith({Repeat? kind, Set<int>? days, int? interval, int? perWeek}) => Schedule(
        kind ?? this.kind,
        days: days ?? this.days,
        interval: interval ?? this.interval,
        perWeek: perWeek ?? this.perWeek,
      );

  /// Server target_per_period.
  int get target => kind == Repeat.perWeek ? perWeek : 1;

  bool get countsWeeks => kind == Repeat.perWeek;

  String? toRRule() => switch (kind) {
        Repeat.none => null,
        Repeat.daily => 'FREQ=DAILY',
        Repeat.weekdays => 'FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR',
        Repeat.days => days.isEmpty
            ? 'FREQ=DAILY'
            : 'FREQ=WEEKLY;BYDAY=${(days.toList()..sort()).map((d) => _codes[d - 1]).join(',')}',
        Repeat.everyN => 'FREQ=DAILY;INTERVAL=$interval',
        Repeat.perWeek => 'FREQ=WEEKLY',
        Repeat.monthly => 'FREQ=MONTHLY',
      };

  static Schedule fromRRule(String? rule, {int target = 1}) {
    if (rule == null || rule.trim().isEmpty) return once;
    final parts = {
      for (final p in rule.toUpperCase().replaceFirst('RRULE:', '').split(';'))
        if (p.contains('=')) p.split('=')[0]: p.split('=')[1],
    };
    final interval = int.tryParse(parts['INTERVAL'] ?? '') ?? 1;
    switch (parts['FREQ']) {
      case 'DAILY':
        return interval > 1 ? Schedule(Repeat.everyN, interval: interval) : daily;
      case 'WEEKLY':
        final by = parts['BYDAY'];
        if (by == null) return Schedule(Repeat.perWeek, perWeek: target.clamp(1, 7));
        final days = {for (final c in by.split(',')) _codes.indexOf(c.replaceAll(RegExp(r'[^A-Z]'), '')) + 1}..remove(0);
        if (days.length == 5 && days.containsAll({1, 2, 3, 4, 5})) return const Schedule(Repeat.weekdays);
        if (days.length == 7) return daily;
        return Schedule(Repeat.days, days: days);
      case 'MONTHLY':
        return const Schedule(Repeat.monthly);
    }
    return daily;
  }

  String get label => switch (kind) {
        Repeat.none => 'Once',
        Repeat.daily => 'Every day',
        Repeat.weekdays => 'Weekdays',
        Repeat.days => days.isEmpty ? 'Every day' : (days.toList()..sort()).map((d) => _dayNames[d - 1]).join(', '),
        Repeat.everyN => 'Every $interval days',
        Repeat.perWeek => '$perWeek× a week',
        Repeat.monthly => 'Monthly',
      };

  /// Is something with this schedule (starting on [start]) planned for [day]?
  /// "N times a week" can be done any day, so every day counts.
  bool isDueOn(DateTime day, DateTime start) {
    final d = dateOnly(day), s = dateOnly(start);
    if (d.isBefore(s)) return false;
    return switch (kind) {
      Repeat.none => d == s,
      Repeat.daily || Repeat.perWeek => true,
      Repeat.weekdays => d.weekday <= 5,
      Repeat.days => days.isEmpty || days.contains(d.weekday),
      Repeat.everyN => d.difference(s).inDays % interval == 0,
      Repeat.monthly => d.day == s.day,
    };
  }

  /// Next date after [from] for a repeating task (null for one-off).
  DateTime? nextAfter(DateTime from) {
    if (kind == Repeat.none) return null;
    if (kind == Repeat.monthly) {
      final m = DateTime(from.year, from.month + 1, from.day, from.hour, from.minute);
      return m;
    }
    var d = from.add(Duration(days: kind == Repeat.everyN ? interval : 1));
    for (var i = 0; i < 8 && !isDueOn(d, from); i++) {
      d = d.add(const Duration(days: 1));
    }
    return d;
  }

  @override
  bool operator ==(Object other) => other is Schedule && other.toRRule() == toRRule() && other.target == target;

  @override
  int get hashCode => Object.hash(toRRule(), target);
}

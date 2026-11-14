import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/widgets/widgets.dart';
import '../../../data/models.dart';
import '../../../data/schedule.dart';
import '../../../data/stores.dart';
import '../../../data/styles.dart';
import '../../../shared/schedule_picker.dart';

/// Habits tab: 7-day dot rows (tap any day), streaks, month heat-map in detail.
class HabitsView extends ConsumerWidget {
  const HabitsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final habits = ref.watch(habitsProvider);
    final today = dateOnly(DateTime.now());
    final days = [for (var i = 6; i >= 0; i--) today.subtract(Duration(days: i))];
    final d = Motion.of(context, Motion.check);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.screen),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, h) in habits.indexed)
            StaggeredEntry(
              index: i,
              child: Padding(
                padding: const EdgeInsets.only(bottom: Space.cardGap),
                child: GlassCard(
                  padding: const EdgeInsets.all(Space.lg),
                  onTap: () => showGlassSheet<void>(context, builder: (_) => _HabitDetail(habitId: h.id)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          IconChip(icon: h.icon, color: h.color, size: 40),
                          const SizedBox(width: Space.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(h.title, style: LifeText.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                                Row(
                                  children: [
                                    const Icon(LucideIcons.flame, size: 13, color: LifeColors.amber),
                                    const SizedBox(width: 3),
                                    Flexible(
                                      child: Text(
                                        '${h.streak}-${h.streakUnit} streak · ${h.schedule.label}',
                                        style: LifeText.mono,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          // Big target for today's check-in
                          Semantics(
                            button: true,
                            checked: h.doneOn(today),
                            label: '${h.title} today',
                            child: GestureDetector(
                              onTap: () => ref.read(habitsProvider.notifier).toggle(h.id),
                              child: AnimatedContainer(
                                duration: d,
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: h.doneOn(today) ? h.color : LifeColors.glassHigh,
                                  border: Border.all(color: h.doneOn(today) ? Colors.transparent : Colors.white38, width: 1.4),
                                ),
                                child: Icon(
                                  Icons.check_rounded,
                                  size: 22,
                                  color: h.doneOn(today) ? LifeColors.onLight : LifeColors.text3,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: Space.md),
                      Row(
                        children: [
                          for (final day in days)
                            Expanded(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => ref.read(habitsProvider.notifier).toggle(h.id, day),
                                child: Column(
                                  children: [
                                    Text(
                                      DateFormat('E').format(day).substring(0, 1),
                                      style: LifeText.caption.copyWith(
                                        fontSize: 11,
                                        color: sameDay(day, today) ? LifeColors.text : LifeColors.text3,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    AnimatedContainer(
                                      duration: d,
                                      width: 20,
                                      height: 20,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: h.doneOn(day) ? h.color : Colors.transparent,
                                        border: Border.all(
                                          color: h.doneOn(day) ? Colors.transparent : LifeColors.glassBorder,
                                          width: 1.4,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          GradientButton(
            label: 'New habit',
            icon: LucideIcons.plus,
            variant: ButtonVariant.glass,
            expand: true,
            onPressed: () => _newHabit(context, ref),
          ),
        ],
      ),
    );
  }

  void _newHabit(BuildContext context, WidgetRef ref) {
    final c = TextEditingController();
    TimeOfDay? remind;
    var schedule = Schedule.daily;
    showGlassSheet<void>(
      context,
      title: 'New habit',
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, setSheet) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(controller: c, autofocus: true, decoration: const InputDecoration(hintText: 'e.g. Meditate 10 minutes')),
            const SizedBox(height: Space.md),
            SchedulePicker(forHabit: true, value: schedule, onChanged: (s) => setSheet(() => schedule = s)),
            const SizedBox(height: Space.md),
            ReminderTimeRow(
              time: remind,
              onChanged: (t) => setSheet(() => remind = t),
            ),
            const SizedBox(height: Space.lg),
            GradientButton(
              label: 'Start habit',
              expand: true,
              onPressed: () {
                if (c.text.trim().isEmpty) return;
                ref.read(habitsProvider.notifier).add(Habit(
                      id: newId(),
                      title: c.text.trim(),
                      icon: habitIcon(c.text.trim()),
                      color: LifeColors.coral,
                      startedOn: dateOnly(DateTime.now()),
                      reminder: remind,
                      schedule: schedule,
                    ));
                Navigator.of(sheet).pop();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _HabitDetail extends ConsumerWidget {
  const _HabitDetail({required this.habitId});

  final String habitId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = ref.watch(habitsProvider).firstWhere((x) => x.id == habitId);
    final today = dateOnly(DateTime.now());
    final first = DateTime(today.year, today.month, 1);
    final daysInMonth = DateTime(today.year, today.month + 1, 0).day;
    final lead = first.weekday - 1;
    final done = h.doneDays.where((d) => d.month == today.month && d.year == today.year).length;
    // Share of this month's scheduled days (so far) that were done.
    final dueSoFar = [
      for (var day = 1; day <= today.day; day++)
        if (h.schedule.isDueOn(DateTime(today.year, today.month, day), h.startedOn)) day,
    ].length;
    final pct = h.schedule.countsWeeks
        ? (done / ((today.day / 7) * h.schedule.perWeek).clamp(1, 31) * 100).round().clamp(0, 100)
        : dueSoFar == 0
            ? 0
            : (done / dueSoFar * 100).round().clamp(0, 100);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconChip(icon: h.icon, color: h.color, size: 44),
            const SizedBox(width: Space.md),
            Expanded(child: Text(h.title, style: LifeText.h2)),
          ],
        ),
        const SizedBox(height: Space.xl),
        Row(
          children: [
            Expanded(child: _Stat(label: 'Current streak', value: '${h.streak}', unit: '${h.streakUnit}s')),
            Expanded(child: _Stat(label: 'Best streak', value: '${h.bestStreak}', unit: '${h.streakUnit}s')),
            Expanded(child: _Stat(label: 'This month', value: '$pct', unit: '%')),
          ],
        ),
        const SizedBox(height: Space.lg),
        GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
          onTap: () => showGlassSheet<void>(
            context,
            title: 'How often?',
            builder: (_) => Consumer(
              builder: (context, ref, _) {
                final cur = ref.watch(habitsProvider).where((x) => x.id == h.id).firstOrNull;
                if (cur == null) return const SizedBox.shrink();
                return SchedulePicker(
                  forHabit: true,
                  value: cur.schedule,
                  onChanged: (s) => ref.read(habitsProvider.notifier).setSchedule(h.id, s),
                );
              },
            ),
          ),
          child: Row(
            children: [
              const Icon(LucideIcons.repeat, size: 18, color: LifeColors.lilac),
              const SizedBox(width: Space.md),
              Expanded(child: Text(h.schedule.label, style: LifeText.body)),
              Text('Change', style: LifeText.label.copyWith(color: LifeColors.lilac)),
            ],
          ),
        ),
        const SizedBox(height: Space.sm),
        ReminderTimeRow(time: h.reminder, onChanged: (t) => ref.read(habitsProvider.notifier).setReminder(h.id, t)),
        const SizedBox(height: Space.lg),
        Text(DateFormat('MMMM yyyy').format(today), style: LifeText.eyebrow),
        const SizedBox(height: Space.md),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (var i = 0; i < lead; i++) const SizedBox.shrink(),
            for (var day = 1; day <= daysInMonth; day++)
              Builder(builder: (context) {
                final date = DateTime(today.year, today.month, day);
                final isDone = h.doneOn(date);
                final future = date.isAfter(today);
                return GestureDetector(
                  onTap: future ? null : () => ref.read(habitsProvider.notifier).toggle(h.id, date),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDone ? h.color.withValues(alpha: 0.85) : LifeColors.glass,
                      borderRadius: BorderRadius.circular(8),
                      border: sameDay(date, today) ? Border.all(color: Colors.white70) : null,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$day',
                      style: LifeText.caption.copyWith(
                        color: isDone ? LifeColors.onLight : (future ? LifeColors.text3.withValues(alpha: 0.4) : LifeColors.text2),
                      ),
                    ),
                  ),
                );
              }),
          ],
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.unit});

  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: LifeText.caption),
          Text.rich(TextSpan(children: [
            TextSpan(text: value, style: LifeText.stat),
            TextSpan(text: ' $unit', style: LifeText.caption),
          ])),
        ],
      );
}

/// "Remind me at …" with a time picker and a clear button.
class ReminderTimeRow extends StatelessWidget {
  const ReminderTimeRow({super.key, required this.time, required this.onChanged});

  final TimeOfDay? time;
  final ValueChanged<TimeOfDay?> onChanged;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.sm),
      onTap: () async {
        final t = await showTimePicker(context: context, initialTime: time ?? const TimeOfDay(hour: 8, minute: 0));
        if (t != null) onChanged(t);
      },
      child: Row(
        children: [
          Icon(time == null ? LucideIcons.bellOff : LucideIcons.bellRing, size: 18, color: time == null ? LifeColors.text3 : LifeColors.coral),
          const SizedBox(width: Space.md),
          Expanded(
            child: Text(
              time == null ? 'No reminder' : 'Remind me at ${time!.format(context)}',
              style: LifeText.body,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (time != null)
            IconButton(
              tooltip: 'Remove reminder',
              icon: const Icon(LucideIcons.x, size: 16, color: LifeColors.text3),
              onPressed: () => onChanged(null),
            )
          else
            Text('Set', style: LifeText.label.copyWith(color: LifeColors.lilac)),
        ],
      ),
    );
  }
}

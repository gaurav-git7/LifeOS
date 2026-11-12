import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/widgets/widgets.dart';
import '../../../data/models.dart';
import '../../../data/seed.dart';
import '../../../data/stores.dart';
import '../../../shared/task_editor_sheet.dart';
import '../../../shared/task_tile.dart';
import '../../../shared/week_strip.dart';

/// Calendar tab: swipeable week strip + the selected day's agenda.
class CalendarView extends ConsumerStatefulWidget {
  const CalendarView({super.key});

  @override
  ConsumerState<CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends ConsumerState<CalendarView> {
  late DateTime _selected = dateOnly(DateTime.now());
  late DateTime _weekStart = _selected.subtract(Duration(days: _selected.weekday - 1));

  void _shiftWeek(int weeks) => setState(() {
        _weekStart = _weekStart.add(Duration(days: 7 * weeks));
        _selected = _weekStart;
      });

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(tasksProvider);
    final blocks = ref.watch(scheduleProvider);
    final markers = <DateTime, List<Color>>{};
    for (final t in tasks.where((t) => t.due != null && !t.done)) {
      markers.putIfAbsent(dateOnly(t.due!), () => []).add(t.priority.color);
    }
    for (final b in blocks) {
      markers.putIfAbsent(dateOnly(b.start), () => []).add(b.type.color);
    }

    final dayBlocks = blocks.where((b) => sameDay(b.start, _selected)).toList();
    final timed = tasks.where((t) => t.isDueOn(_selected) && t.hasTime).toList();
    final untimed = tasks.where((t) => t.isDueOn(_selected) && !t.hasTime).toList();
    final agenda = <(DateTime, Widget)>[
      for (final b in dayBlocks) (b.start, _BlockRow(block: b)),
      for (final t in timed) (t.due!, _TimedTask(task: t)),
    ]..sort((a, b) => a.$1.compareTo(b.$1));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.screen),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(DateFormat('MMMM yyyy').format(_weekStart), style: LifeText.title)),
              IconGlassButton(icon: LucideIcons.chevronLeft, size: 36, onPressed: () => _shiftWeek(-1)),
              IconGlassButton(icon: LucideIcons.chevronRight, size: 36, onPressed: () => _shiftWeek(1)),
            ],
          ),
          const SizedBox(height: Space.md),
          GestureDetector(
            onHorizontalDragEnd: (d) {
              final v = d.primaryVelocity ?? 0;
              if (v.abs() > 200) _shiftWeek(v < 0 ? 1 : -1);
            },
            child: GlassCard(
              padding: const EdgeInsets.all(Space.sm),
              child: WeekStrip(
                weekStart: _weekStart,
                selected: _selected,
                markers: markers,
                onSelected: (d) => setState(() => _selected = d),
              ),
            ),
          ),
          const SizedBox(height: Space.section),
          SectionHeader(
            title: DateFormat('EEEE, d MMMM').format(_selected),
            action: '+ Add',
            onAction: () => showTaskEditor(context, defaultDue: _selected),
          ),
          if (agenda.isEmpty && untimed.isEmpty)
            const GlassCard(child: EmptyState(icon: LucideIcons.calendarDays, title: 'A free day', message: 'Nothing scheduled yet.'))
          else ...[
            if (agenda.isNotEmpty)
              GlassCard(
                padding: const EdgeInsets.all(Space.lg),
                child: Column(children: [for (final a in agenda) a.$2]),
              ),
            if (untimed.isNotEmpty) ...[
              const SizedBox(height: Space.lg),
              Text('Anytime', style: LifeText.eyebrow),
              const SizedBox(height: Space.sm),
              TaskGroupCard(tasks: untimed),
            ],
          ],
        ],
      ),
    );
  }
}

class _BlockRow extends StatelessWidget {
  const _BlockRow({required this.block});

  final ScheduleBlock block;

  @override
  Widget build(BuildContext context) {
    final f = DateFormat('h:mm');
    final past = block.end.isBefore(DateTime.now());
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
      child: Row(
        children: [
          SizedBox(width: 56, child: Text(DateFormat('h:mm a').format(block.start), style: LifeText.mono)),
          Container(width: 3, height: 40, decoration: BoxDecoration(color: block.type.color, borderRadius: Radii.rPill)),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(block.title, style: LifeText.bodyStrong.copyWith(color: past ? LifeColors.text3 : LifeColors.text)),
                Text('${f.format(block.start)}–${f.format(block.end)} · ${block.type.label}', style: LifeText.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TimedTask extends StatelessWidget {
  const _TimedTask({required this.task});

  final Task task;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 56, child: Text(DateFormat('h:mm a').format(task.due!), style: LifeText.mono)),
        Expanded(child: TaskTile(task: task)),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/widgets/widgets.dart';
import '../../../data/models.dart';
import '../../../data/stores.dart';
import '../../../shared/task_tile.dart';

/// Tasks tab: filters, grouped lists, swipe right = complete, swipe left = reschedule.
class TasksView extends ConsumerStatefulWidget {
  const TasksView({super.key});

  @override
  ConsumerState<TasksView> createState() => _TasksViewState();
}

class _TasksViewState extends ConsumerState<TasksView> {
  int _filter = 0;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final tasks = ref.watch(tasksProvider);
    final today = tasks.where((t) => t.isDueOn(now) && !t.done).toList();
    final upcoming = tasks.where((t) => !t.done && (t.due == null || dateOnly(t.due!).isAfter(dateOnly(now)))).toList();
    final overdue = tasks.where((t) => t.isOverdue(now)).toList();
    final done = tasks.where((t) => t.done).toList()
      ..sort((a, b) => (b.completedAt ?? now).compareTo(a.completedAt ?? now));

    final groups = <(String, List<Task>)>[];
    switch (_filter) {
      case 0:
        int bucket(Task t) => !t.hasTime ? 3 : (t.due!.hour < 12 ? 0 : (t.due!.hour < 17 ? 1 : 2));
        const names = ['Morning', 'Afternoon', 'Evening', 'Anytime today'];
        for (var b = 0; b < 4; b++) {
          final list = today.where((t) => bucket(t) == b).toList()
            ..sort((x, y) => y.priority.index.compareTo(x.priority.index));
          if (list.isNotEmpty) groups.add((names[b], list));
        }
      case 1:
        final dated = upcoming.where((t) => t.due != null).toList()..sort((a, b) => a.due!.compareTo(b.due!));
        final byDay = <DateTime, List<Task>>{};
        for (final t in dated) {
          byDay.putIfAbsent(dateOnly(t.due!), () => []).add(t);
        }
        for (final e in byDay.entries) {
          final label = sameDay(e.key, now.add(const Duration(days: 1)))
              ? 'Tomorrow'
              : DateFormat('EEEE, d MMM').format(e.key);
          groups.add((label, e.value));
        }
        final someday = upcoming.where((t) => t.due == null).toList();
        if (someday.isNotEmpty) groups.add(('Someday', someday));
      case 2:
        if (overdue.isNotEmpty) groups.add(('Overdue', overdue..sort((a, b) => a.due!.compareTo(b.due!))));
      case 3:
        if (done.isNotEmpty) groups.add(('Completed', done.take(30).toList()));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilterChipRow(
          selected: _filter,
          onSelected: (i) => setState(() => _filter = i),
          chips: [
            FilterChipData('Today', count: today.length),
            FilterChipData('Upcoming', count: upcoming.length),
            FilterChipData('Overdue', count: overdue.length, accent: LifeColors.coral),
            const FilterChipData('Done'),
          ],
        ),
        const SizedBox(height: Space.xl),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.screen),
          child: groups.isEmpty
              ? GlassCard(
                  child: EmptyState(
                    icon: _filter == 2 ? LucideIcons.partyPopper : LucideIcons.circleCheck,
                    title: _filter == 2 ? 'Nothing overdue' : 'All clear',
                    message: _filter == 3 ? 'Completed tasks will show up here.' : 'Enjoy it — or add something with +.',
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, g) in groups.indexed)
                      StaggeredEntry(
                        index: i,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: Space.section),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SectionHeader(title: g.$1, action: '${g.$2.length}'),
                              _SwipeList(tasks: g.$2, showDay: _filter >= 2),
                            ],
                          ),
                        ),
                      ),
                    Text(
                      'Swipe right to complete · left to reschedule',
                      textAlign: TextAlign.center,
                      style: LifeText.caption.copyWith(color: LifeColors.text3),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _SwipeList extends ConsumerWidget {
  const _SwipeList({required this.tasks, this.showDay = false});

  final List<Task> tasks;
  final bool showDay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: Space.xs, horizontal: Space.sm),
      child: Column(
        children: [
          for (var i = 0; i < tasks.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 56, endIndent: Space.md),
            Dismissible(
              key: ValueKey('swipe-${tasks[i].id}'),
              background: _swipeBg(LifeColors.iris, LucideIcons.check, 'Done', Alignment.centerLeft),
              secondaryBackground: _swipeBg(LifeColors.amber, LucideIcons.calendarClock, 'Reschedule', Alignment.centerRight),
              confirmDismiss: (dir) async {
                HapticFeedback.mediumImpact();
                if (dir == DismissDirection.startToEnd) {
                  ref.read(tasksProvider.notifier).toggle(tasks[i].id);
                } else {
                  await showReschedule(context, ref, tasks[i]);
                }
                return false;
              },
              child: TaskTile(task: tasks[i], showDay: showDay),
            ),
          ],
        ],
      ),
    );
  }

  Widget _swipeBg(Color c, IconData icon, String label, Alignment align) => Container(
        alignment: align,
        padding: const EdgeInsets.symmetric(horizontal: Space.xl),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.22), borderRadius: Radii.rMd),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [Icon(icon, size: 18, color: c), const SizedBox(width: 6), Text(label, style: LifeText.label.copyWith(color: c))],
        ),
      );
}

Future<void> showReschedule(BuildContext context, WidgetRef ref, Task task) {
  final now = dateOnly(DateTime.now());
  final options = <(String, DateTime)>[
    ('Today', now),
    ('Tomorrow', now.add(const Duration(days: 1))),
    ('In 2 days', now.add(const Duration(days: 2))),
    ('Next week', now.add(Duration(days: 8 - now.weekday))),
  ];
  return showGlassSheet<void>(
    context,
    title: 'Move “${task.title}”',
    builder: (sheetContext) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final o in options)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: GlassCard(
              padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
              onTap: () {
                final keepTime = task.hasTime && task.due != null;
                final due = keepTime ? DateTime(o.$2.year, o.$2.month, o.$2.day, task.due!.hour, task.due!.minute) : o.$2;
                ref.read(tasksProvider.notifier).reschedule(task.id, due, hasTime: keepTime);
                Navigator.of(sheetContext).pop();
              },
              child: Row(
                children: [
                  Expanded(child: Text(o.$1, style: LifeText.bodyStrong)),
                  Text(DateFormat('EEE d MMM').format(o.$2), style: LifeText.mono),
                ],
              ),
            ),
          ),
        GradientButton(
          label: 'Pick a date',
          icon: LucideIcons.calendarDays,
          variant: ButtonVariant.glass,
          expand: true,
          onPressed: () async {
            final picked = await showDatePicker(
              context: sheetContext,
              firstDate: now,
              lastDate: DateTime(now.year + 2),
              initialDate: now.add(const Duration(days: 1)),
            );
            if (picked != null) {
              ref.read(tasksProvider.notifier).reschedule(task.id, picked);
              if (sheetContext.mounted) Navigator.of(sheetContext).pop();
            }
          },
        ),
      ],
    ),
  );
}

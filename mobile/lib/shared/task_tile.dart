import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/widgets/widgets.dart';
import '../data/models.dart';
import '../data/seed.dart';
import '../data/stores.dart';
import 'task_editor_sheet.dart';

String taskMeta(Task t, {bool includeDay = false}) {
  final parts = <String>[];
  if (t.estimatedMinutes != null) parts.add(formatMinutes(t.estimatedMinutes!.toDouble()));
  if (t.due != null) {
    final now = DateTime.now();
    final day = sameDay(t.due!, now)
        ? 'Today'
        : sameDay(t.due!, now.add(const Duration(days: 1)))
            ? 'Tomorrow'
            : DateFormat('EEE d MMM').format(t.due!);
    if (t.hasTime) {
      parts.add('${includeDay || day != 'Today' ? '$day ' : 'Due '}${DateFormat('h:mm a').format(t.due!)}');
    } else if (includeDay || day != 'Today') {
      parts.add(day);
    }
  }
  if (t.subtasks.isNotEmpty) parts.add('${t.subtasks.where((s) => s.done).length}/${t.subtasks.length} steps');
  return parts.isEmpty ? 'Anytime' : parts.join(' · ');
}

/// Compact task row: animated check, title (strikes through when done), mono meta, priority dot.
class TaskTile extends ConsumerWidget {
  const TaskTile({super.key, required this.task, this.showDay = false, this.onCompleted});

  final Task task;
  final bool showDay;

  /// Called after a task is completed (not when re-opened).
  final VoidCallback? onCompleted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = Motion.of(context, Motion.check);
    final overdue = task.isOverdue(DateTime.now());
    return Pressable(
      scale: 0.99,
      onTap: () => showTaskEditor(context, task: task),
      child: Row(
        children: [
          AnimatedCheck(
            checked: task.done,
            color: LifeColors.iris,
            onChanged: (_) {
              final xp = ref.read(tasksProvider.notifier).toggle(task.id);
              if (xp > 0) onCompleted?.call();
            },
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedDefaultTextStyle(
                    duration: d,
                    style: LifeText.bodyStrong.copyWith(
                      color: task.done ? LifeColors.text3 : LifeColors.text,
                      decoration: task.done ? TextDecoration.lineThrough : TextDecoration.none,
                      decorationColor: LifeColors.text3,
                    ),
                    child: Text(task.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    overdue ? 'Overdue · ${taskMeta(task, includeDay: true)}' : taskMeta(task, includeDay: showDay),
                    style: LifeText.mono.copyWith(color: overdue ? LifeColors.coral : LifeColors.text2),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: Space.sm),
          Container(
            width: 7,
            height: 7,
            margin: const EdgeInsets.only(right: Space.md),
            decoration: BoxDecoration(color: task.priority.color, shape: BoxShape.circle),
          ),
        ],
      ),
    );
  }
}

/// Divided list of tasks inside one glass card.
class TaskGroupCard extends StatelessWidget {
  const TaskGroupCard({super.key, required this.tasks, this.showDay = false, this.onCompleted});

  final List<Task> tasks;
  final bool showDay;
  final VoidCallback? onCompleted;

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) {
      return const GlassCard(
        child: EmptyState(icon: LucideIcons.circleCheck, title: 'All clear', message: 'Nothing here — enjoy it, or add a task.'),
      );
    }
    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: Space.xs, horizontal: Space.sm),
      child: Column(
        children: [
          for (var i = 0; i < tasks.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 56, endIndent: Space.md),
            TaskTile(key: ValueKey(tasks[i].id), task: tasks[i], showDay: showDay, onCompleted: onCompleted),
          ],
        ],
      ),
    );
  }
}

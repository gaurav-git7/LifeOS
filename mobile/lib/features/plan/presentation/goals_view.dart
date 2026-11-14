import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/widgets/widgets.dart';
import '../../../data/models.dart';
import '../../../data/stores.dart';
import '../../../shared/create_sheets.dart';
import '../../../shared/task_tile.dart';

/// Goals tab: progress per goal; tap for milestones and linked tasks.
class GoalsView extends ConsumerWidget {
  const GoalsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goals = ref.watch(goalsProvider);
    final tasks = ref.watch(tasksProvider);
    final now = dateOnly(DateTime.now());
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.screen),
      child: Column(
        children: [
          for (final (i, g) in goals.indexed)
            StaggeredEntry(
              index: i,
              child: Padding(
                padding: const EdgeInsets.only(bottom: Space.cardGap),
                child: GlassCard(
                  onTap: () => _openGoal(context, g.id),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          IconChip(icon: g.icon, color: g.color, size: 36),
                          const SizedBox(width: Space.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(g.title, style: LifeText.title),
                                Text(
                                  [
                                    g.category,
                                    if (g.targetDate != null) '${g.targetDate!.difference(now).inDays} days left',
                                  ].join(' · '),
                                  style: LifeText.caption,
                                ),
                              ],
                            ),
                          ),
                          Text('${(goalProgress(g, tasks) * 100).round()}%', style: LifeText.stat.copyWith(fontSize: 20)),
                        ],
                      ),
                      const SizedBox(height: Space.lg),
                      GlowBar(value: goalProgress(g, tasks), color: g.color),
                      if (g.milestones.isNotEmpty) ...[
                        const SizedBox(height: Space.md),
                        Row(
                          children: [
                            for (final m in g.milestones)
                              Container(
                                width: 8,
                                height: 8,
                                margin: const EdgeInsets.only(right: 6),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: m.done ? g.color : Colors.transparent,
                                  border: Border.all(color: m.done ? g.color : LifeColors.text3),
                                ),
                              ),
                            const SizedBox(width: Space.xs),
                            Text(
                              '${g.milestones.where((m) => m.done).length}/${g.milestones.length} milestones',
                              style: LifeText.mono,
                            ),
                          ],
                        ),
                      ],
                      if (g.progressType == GoalProgressType.numeric) ...[
                        const SizedBox(height: Space.md),
                        Text('${g.current?.round() ?? 0} of ${g.target?.round() ?? 0} ${g.unit ?? ''}', style: LifeText.mono),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          GradientButton(
            label: 'New goal',
            icon: LucideIcons.plus,
            variant: ButtonVariant.glass,
            expand: true,
            onPressed: () => showGoalEditor(context),
          ),
        ],
      ),
    );
  }

  void _openGoal(BuildContext context, String goalId) {
    showGlassSheet<void>(context, builder: (_) => _GoalDetail(goalId: goalId));
  }
}

class _GoalDetail extends ConsumerWidget {
  const _GoalDetail({required this.goalId});

  final String goalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = ref.watch(goalsProvider).where((x) => x.id == goalId).firstOrNull;
    if (g == null) return const SizedBox.shrink();
    final tasks = ref.watch(tasksProvider);
    final linked = tasks.where((t) => t.goalId == g.id).toList();
    final progress = goalProgress(g, tasks);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                AnimatedProgressRing(
                  value: progress,
                  color: g.color,
                  size: 72,
                  stroke: 8,
                  child: Text('${(progress * 100).round()}%', style: LifeText.label),
                ),
                const SizedBox(width: Space.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(g.title, style: LifeText.h2),
                      if (g.targetDate != null)
                        Text('Target ${DateFormat('d MMM yyyy').format(g.targetDate!)}', style: LifeText.caption),
                    ],
                  ),
                ),
              ],
            ),
            if (g.progressType == GoalProgressType.numeric) ...[
              const SizedBox(height: Space.xl),
              Row(
                children: [
                  Expanded(child: Text('${g.current?.round() ?? 0} / ${g.target?.round() ?? 0} ${g.unit ?? ''}', style: LifeText.title)),
                  IconGlassButton(
                    icon: LucideIcons.minus,
                    onPressed: () => ref.read(goalsProvider.notifier).setCurrent(g.id, ((g.current ?? 0) - 1).clamp(0, g.target ?? 999)),
                  ),
                  IconGlassButton(
                    icon: LucideIcons.plus,
                    onPressed: () => ref.read(goalsProvider.notifier).setCurrent(g.id, ((g.current ?? 0) + 1).clamp(0, g.target ?? 999)),
                  ),
                ],
              ),
            ],
            if (g.milestones.isNotEmpty) ...[
              const SizedBox(height: Space.xl),
              Text('Milestones', style: LifeText.eyebrow),
              for (final m in g.milestones)
                Row(
                  children: [
                    AnimatedCheck(
                      checked: m.done,
                      color: g.color,
                      onChanged: (_) => ref.read(goalsProvider.notifier).toggleMilestone(g.id, m.id),
                    ),
                    Expanded(
                      child: Text(
                        m.title,
                        style: LifeText.body.copyWith(
                          color: m.done ? LifeColors.text3 : LifeColors.text,
                          decoration: m.done ? TextDecoration.lineThrough : null,
                          decorationColor: LifeColors.text3,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
            if (g.progressType != GoalProgressType.numeric)
              Align(
                alignment: Alignment.centerLeft,
                child: GradientButton(
                  label: 'Add milestone',
                  icon: LucideIcons.plus,
                  variant: ButtonVariant.ghost,
                  compact: true,
                  onPressed: () => showMilestoneAdder(context, goalId: g.id),
                ),
              ),
            if (linked.isNotEmpty) ...[
              const SizedBox(height: Space.xl),
              Text('Linked tasks', style: LifeText.eyebrow),
              const SizedBox(height: Space.sm),
              TaskGroupCard(tasks: linked, showDay: true),
            ],
            const SizedBox(height: Space.xl),
            GradientButton(
              label: 'Delete goal',
              icon: LucideIcons.trash2,
              variant: ButtonVariant.danger,
              expand: true,
              onPressed: () async {
                final ok = await showGlassConfirm(
                  context,
                  title: 'Delete this goal?',
                  message: 'Its milestones are removed. Linked tasks stay.',
                );
                if (!ok || !context.mounted) return;
                ref.read(goalsProvider.notifier).remove(g.id);
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }
}

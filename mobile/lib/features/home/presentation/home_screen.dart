import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/routing/routes.dart';
import '../../../core/widgets/layout/tab_scaffold.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/models.dart';
import '../../../data/seed.dart';
import '../../../data/stores.dart';
import '../../../shared/task_tile.dart';


/// Daily Command Center. See docs/UI_UX.md §9.1.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _burst = 0;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final tasks = ref.watch(tasksProvider);
    final habits = ref.watch(habitsProvider);
    final learning = ref.watch(learningProvider);
    final pending = ref.watch(assistantProvider.select((s) => s.pending.length));

    final today = tasks.where((t) => t.isDueOn(now)).toList();
    final todayDone = today.where((t) => t.done).length;
    final habitsToday = habits.where((h) => h.isDueOn(now) || h.doneOn(now)).toList();
    final habitsDone = habitsToday.where((h) => h.doneOn(now)).length;
    final studyMin = learning.minutesOn(now);

    final priorities = tasks.where((t) => !t.done && (t.isDueOn(now) || t.isOverdue(now))).toList()
      ..sort((a, b) {
        final p = b.priority.index.compareTo(a.priority.index);
        if (p != 0) return p;
        return (a.due ?? now).compareTo(b.due ?? now);
      });

    void onCompleted() {
      final t = ref.read(tasksProvider).where((t) => t.isDueOn(DateTime.now()));
      if (t.isNotEmpty && t.every((x) => x.done)) setState(() => _burst++);
    }

    return TabScaffold(
      header: const _Header(),
      slivers: [
        SliverSection(
          bottom: Space.cardGap,
          child: StaggeredEntry(
            index: 0,
            child: _TodayCard(
              tasks: (todayDone, today.length),
              habits: (habitsDone, habitsToday.length),
              studyMinutes: studyMin,
              burst: _burst,
            ),
          ),
        ),
        SliverSection(child: StaggeredEntry(index: 1, child: _InsightCard(pending: pending))),
        SliverSection(
          child: StaggeredEntry(
            index: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeader(title: 'Priorities', action: 'See all', onAction: () => context.go(Routes.plan)),
                TaskGroupCard(tasks: priorities.take(3).toList(), onCompleted: onCompleted),
              ],
            ),
          ),
        ),
        SliverSection(
          child: StaggeredEntry(
            index: 3,
            child: GlassCard(
              padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.sm),
              child: Column(
                children: [
                  _ScheduleSection(),
                  const Divider(height: Space.lg),
                  _HabitsSection(),
                  const Divider(height: Space.lg),
                  _LearningSection(),
                ],
              ),
            ),
          ),
        ),
        if (kDebugMode)
          SliverSection(
            child: Center(
              child: GradientButton(
                label: 'Component gallery',
                icon: LucideIcons.layoutGrid,
                variant: ButtonVariant.ghost,
                compact: true,
                onPressed: () => context.push(Routes.gallery),
              ),
            ),
          ),
      ],
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header();

  String _greeting(int hour) => switch (hour) {
        < 5 => 'Good night',
        < 12 => 'Good morning',
        < 17 => 'Good afternoon',
        _ => 'Good evening',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final name = ref.watch(authProvider.select((a) => a.name));
    // Rebuild the badge when anything it counts changes.
    ref.watch(tasksProvider);
    ref.watch(habitsProvider);
    ref.watch(assistantProvider.select((s) => s.pending.length));
    final hasNews = _notifications(ref).isNotEmpty;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(DateFormat('EEEE, d MMMM').format(now), style: LifeText.eyebrow),
              const SizedBox(height: Space.xs),
              Text('${_greeting(now.hour)},', style: LifeText.titleSerif.copyWith(fontSize: 34, height: 1.05)),
              Text(name, style: LifeText.titleSerifItalic.copyWith(fontSize: 34, height: 1.05, color: LifeColors.text2)),
            ],
          ),
        ),
        IconGlassButton(
          icon: LucideIcons.bell,
          badge: hasNews,
          semanticLabel: 'Notifications',
          onPressed: () => _showNotifications(context, ref),
        ),
        const SizedBox(width: Space.xs),
        Pressable(
          onTap: () => context.push(Routes.settings),
          semanticLabel: 'Profile and settings',
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Container(
              width: Sizes.avatar,
              height: Sizes.avatar,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [Color(0xFFFFB38A), LifeColors.rose]),
              ),
              alignment: Alignment.center,
              child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
                  style: LifeText.title.copyWith(color: LifeColors.onLight)),
            ),
          ),
        ),
      ],
    );
  }

  /// Built from what's actually going on, so it's right in both data modes.
  List<(IconData, Color, String, String, String)> _notifications(WidgetRef ref) {
    final now = DateTime.now();
    final pending = ref.read(assistantProvider).pending.length;
    final overdue = ref.read(tasksProvider).where((t) => t.isOverdue(now)).length;
    final habits = ref.read(habitsProvider);
    final atRisk = habits.where((h) => h.streak > 1 && h.isDueOn(now) && !h.doneOn(now)).toList()..sort((a, b) => b.streak.compareTo(a.streak));
    final revisions = ref.read(learningProvider).paths.expand((p) => p.topics).where((t) => t.revisionDue).length;
    final recent = ref
        .read(achievementsProvider)
        .where((a) => a.unlockedAt != null && now.difference(a.unlockedAt!).inDays < 7)
        .toList()
      ..sort((a, b) => b.unlockedAt!.compareTo(a.unlockedAt!));
    return [
      if (pending > 0)
        (LucideIcons.sparkles, LifeColors.iris, '$pending suggestion${pending == 1 ? '' : 's'} waiting', 'From your assistant', 'Now'),
      if (overdue > 0) (LucideIcons.clockAlert, LifeColors.danger, '$overdue overdue task${overdue == 1 ? '' : 's'}', 'Reschedule or let them go', 'Today'),
      if (atRisk.isNotEmpty)
        (LucideIcons.flame, LifeColors.coral, '${atRisk.first.streak}-${atRisk.first.streakUnit} ${atRisk.first.title} streak', 'Not done yet today', 'Today'),
      if (revisions > 0)
        (LucideIcons.repeat, LifeColors.sky, '$revisions topic${revisions == 1 ? '' : 's'} to revise', 'Spaced repetition keeps it fresh', 'Today'),
      for (final a in recent.take(2))
        (LucideIcons.trophy, LifeColors.amber, 'Achievement unlocked', a.title, DateFormat('d MMM').format(a.unlockedAt!)),
    ];
  }

  void _showNotifications(BuildContext context, WidgetRef ref) {
    final items = _notifications(ref);
    showGlassSheet<void>(
      context,
      title: 'Notifications',
      builder: (_) => Column(
        children: [
          if (items.isEmpty)
            const EmptyState(icon: LucideIcons.bellOff, title: 'All caught up', message: 'Nothing needs you right now.'),
          for (final i in items)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.md),
              child: Row(
                children: [
                  IconChip(icon: i.$1, color: i.$2, size: 36),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [Text(i.$3, style: LifeText.bodyStrong), Text(i.$4, style: LifeText.caption)],
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  Text(i.$5, style: LifeText.mono),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TodayCard extends ConsumerWidget {
  const _TodayCard({required this.tasks, required this.habits, required this.studyMinutes, required this.burst});

  final (int, int) tasks;
  final (int, int) habits;
  final int studyMinutes;
  final int burst;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prog = ref.watch(progressionProvider);
    final goal = ref.watch(prefsProvider.select((p) => p.studyGoalMinutes));
    final taskRatio = tasks.$2 == 0 ? 0.0 : tasks.$1 / tasks.$2;
    final habitRatio = habits.$2 == 0 ? 0.0 : habits.$1 / habits.$2;
    final studyRatio = (studyMinutes / goal).clamp(0.0, 1.0);
    // Average only what applies today: no tasks due shouldn't count as "done".
    final parts = [if (tasks.$2 > 0) taskRatio, if (habits.$2 > 0) habitRatio, studyRatio];
    final overall = parts.fold(0.0, (a, b) => a + b) / parts.length;
    final left = [
      if (tasks.$2 - tasks.$1 > 0) '${tasks.$2 - tasks.$1} task${tasks.$2 - tasks.$1 == 1 ? '' : 's'}',
      if (habits.$2 - habits.$1 > 0) '${habits.$2 - habits.$1} habit${habits.$2 - habits.$1 == 1 ? '' : 's'}',
      if (studyMinutes < goal) '${formatMinutes((goal - studyMinutes).toDouble())} of study',
    ];
    final summary = left.isEmpty
        ? 'Everything for today is done'
        : '${left.length == 1 ? left.first : '${left.sublist(0, left.length - 1).join(', ')} and ${left.last}'} left';

    return GlassCard(
      radius: Radii.xl,
      onTap: () => context.go(Routes.assistant),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Today', style: LifeText.eyebrow),
                    const SizedBox(height: Space.xs),
                    AnimatedCounter(value: overall * 100, suffix: '%', style: LifeText.statHero),
                    const SizedBox(height: Space.xs),
                    Text('of today done', style: LifeText.caption),
                    const SizedBox(height: Space.sm),
                    Text(summary, style: LifeText.body.copyWith(color: LifeColors.text2)),
                  ],
                ),
              ),
              Stack(
                alignment: Alignment.center,
                children: [
                  ActivityRings(
                    size: 120,
                    stroke: 12,
                    rings: [
                      RingData(taskRatio, LifeColors.tasks, label: 'Tasks'),
                      RingData(habitRatio, LifeColors.habits, label: 'Habits'),
                      RingData(studyRatio, LifeColors.learning, label: 'Study'),
                    ],
                  ),
                  GlowBurst(trigger: burst, size: 190),
                ],
              ),
            ],
          ),
          const SizedBox(height: Space.xl),
          Row(
            children: [
              Expanded(child: _Legend(color: LifeColors.tasks, label: 'Tasks', value: '${tasks.$1}/${tasks.$2}')),
              Expanded(child: _Legend(color: LifeColors.habits, label: 'Habits', value: '${habits.$1}/${habits.$2}')),
              Expanded(
                child: _Legend(
                  color: LifeColors.learning,
                  label: 'Study',
                  value: '${formatMinutes(studyMinutes.toDouble())}/${formatMinutes(goal.toDouble())}',
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.lg),
          const Divider(height: 1),
          const SizedBox(height: Space.lg),
          Row(
            children: [
              Text('Level ${prog.info.level}', style: LifeText.label),
              const SizedBox(width: Space.md),
              Expanded(
                child: GlowBar(
                  value: prog.info.progress,
                  height: 5,
                  gradient: const LinearGradient(colors: [LifeColors.iris, LifeColors.rose]),
                ),
              ),
              const SizedBox(width: Space.md),
              Text('+${prog.todayXp} XP', style: LifeText.mono.copyWith(color: LifeColors.text)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label, required this.value});

  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(label, style: LifeText.caption),
          ],
        ),
        const SizedBox(height: 2),
        Text(value, style: LifeText.stat.copyWith(fontSize: 19)),
      ],
    );
  }
}

class _InsightCard extends ConsumerStatefulWidget {
  const _InsightCard({required this.pending});

  final int pending;

  @override
  ConsumerState<_InsightCard> createState() => _InsightCardState();
}

class _InsightCardState extends ConsumerState<_InsightCard> {
  bool _dismissed = false;

  /// The server's daily insight when there is one; otherwise a plain summary.
  String _insight() {
    final live = ref.watch(authProvider.select((a) => a.live));
    if (!live) {
      return 'You finish most tasks before 1 PM. Put tomorrow’s hardest DSA problem first and keep the evening for revision.';
    }
    final fromReview = ref.watch(reviewsProvider.select((r) => r.insight));
    if (fromReview != null && fromReview.isNotEmpty) return fromReview;
    final now = DateTime.now();
    final tasks = ref.watch(tasksProvider);
    final today = tasks.where((t) => t.isDueOn(now) || t.isOverdue(now)).toList();
    if (tasks.isEmpty) return 'Start small: add one task for today, or ask me to plan your week.';
    final left = today.where((t) => !t.done).length;
    if (left == 0) return 'Everything due today is done. Ask me to plan tomorrow while it’s fresh.';
    return '$left thing${left == 1 ? '' : 's'} left today. Your evening review will suggest what to move if the day runs out.';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: Motion.size(context, Motion.card),
      curve: Motion.inOut,
      child: _dismissed
          ? const SizedBox(width: double.infinity)
          : GlassCard(
              ai: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const AiMark(size: 26),
                      const SizedBox(width: Space.sm),
                      Expanded(child: Text('Assistant', style: LifeText.label, overflow: TextOverflow.ellipsis)),
                      Flexible(child: Text('Daily insight', style: LifeText.mono, overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                  const SizedBox(height: Space.md),
                  Text(_insight(), style: LifeText.body),
                  const SizedBox(height: Space.lg),
                  Wrap(
                    spacing: Space.sm,
                    runSpacing: Space.sm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      GradientButton(
                        label: widget.pending > 0 ? 'Review ${widget.pending} suggestions' : 'Plan tomorrow',
                        compact: true,
                        onPressed: () {
                          if (widget.pending > 0) {
                            ref.read(assistantTabProvider.notifier).set(2);
                          } else {
                            ref.read(assistantTabProvider.notifier).set(0);
                            ref.read(assistantProvider.notifier).send('Plan tomorrow');
                          }
                          context.go(Routes.assistant);
                        },
                      ),
                      GradientButton(
                        label: 'Later',
                        compact: true,
                        variant: ButtonVariant.ghost,
                        onPressed: () => setState(() => _dismissed = true),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}

class _ScheduleSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final blocks = ref.watch(scheduleProvider).where((b) => sameDay(b.start, now)).toList();
    final next = blocks.where((b) => b.end.isAfter(now)).firstOrNull;
    final fmt = DateFormat('h:mm a');
    return CollapsibleSection(
      title: 'Schedule',
      icon: LucideIcons.calendarDays,
      accent: LifeColors.sky,
      summary: Text(blocks.isEmpty
          ? 'Nothing planned'
          : '${blocks.length} blocks${next != null ? ' · next at ${fmt.format(next.start)}' : ' · all done'}'),
      child: Padding(
        padding: const EdgeInsets.only(left: 42, bottom: Space.sm),
        child: Column(
          children: [
            for (final b in blocks)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.sm),
                child: Row(
                  children: [
                    SizedBox(width: 68, child: Text(fmt.format(b.start), style: LifeText.mono)),
                    Container(width: 3, height: 30, decoration: BoxDecoration(color: b.type.color, borderRadius: Radii.rPill)),
                    const SizedBox(width: Space.md),
                    Expanded(
                      child: Text(
                        b.title,
                        style: LifeText.body.copyWith(color: b.end.isBefore(now) ? LifeColors.text3 : LifeColors.text),
                      ),
                    ),
                    if (!b.start.isAfter(now) && b.end.isAfter(now))
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: LifeColors.mint.withValues(alpha: 0.2), borderRadius: Radii.rPill),
                        child: Text('Now', style: LifeText.caption.copyWith(color: LifeColors.mint)),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HabitsSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final habits = ref.watch(habitsProvider).where((h) => h.isDueOn(now) || h.doneOn(now)).toList();
    final done = habits.where((h) => h.doneOn(now)).length;
    final best = habits.fold(0, (a, h) => h.streak > a ? h.streak : a);
    final d = Motion.of(context, Motion.check);
    return CollapsibleSection(
      title: 'Habits',
      icon: LucideIcons.flame,
      accent: LifeColors.coral,
      summary: Text(habits.isEmpty ? 'Nothing due today' : '$done of ${habits.length} today · best streak $best'),
      child: Padding(
        padding: const EdgeInsets.only(bottom: Space.sm),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final h in habits.take(5))
              Pressable(
                onTap: () => ref.read(habitsProvider.notifier).toggle(h.id),
                haptic: true,
                semanticLabel: h.title,
                child: Column(
                  children: [
                    AnimatedContainer(
                      duration: d,
                      curve: Motion.standard,
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: h.doneOn(now) ? h.color : LifeColors.glassHigh,
                        border: Border.all(color: h.doneOn(now) ? Colors.transparent : LifeColors.glassBorder),
                      ),
                      child: Icon(h.icon, size: 19, color: h.doneOn(now) ? LifeColors.onLight : LifeColors.text2),
                    ),
                    const SizedBox(height: Space.xs),
                    Text(h.title, style: LifeText.caption.copyWith(fontSize: 11)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LearningSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final learning = ref.watch(learningProvider);
    final path = learning.paths.firstOrNull;
    final minutes = learning.minutesOn(DateTime.now());
    return CollapsibleSection(
      title: 'Learning',
      icon: LucideIcons.bookOpen,
      accent: LifeColors.mint,
      summary: Text(path == null
          ? 'No roadmap yet'
          : '${path.title} · ${(path.progress * 100).round()}% · ${formatMinutes(minutes.toDouble())} today'),
      child: path == null
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.only(left: 42, bottom: Space.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(path.title, style: LifeText.body)),
                      Text('${(path.progress * 100).round()}%', style: LifeText.mono.copyWith(color: LifeColors.mint)),
                    ],
                  ),
                  const SizedBox(height: Space.sm),
                  GlowBar(value: path.progress, color: LifeColors.mint, height: 5),
                  const SizedBox(height: Space.md),
                  if (path.nextTopic != null)
                    Text('Next: ${path.nextTopic!.title} · ${path.nextTopic!.difficulty.label.toLowerCase()}',
                        style: LifeText.caption),
                  const SizedBox(height: Space.md),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: GradientButton(
                      label: 'Start focus',
                      icon: LucideIcons.timer,
                      compact: true,
                      variant: ButtonVariant.glass,
                      onPressed: () => context.push(Routes.focus),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

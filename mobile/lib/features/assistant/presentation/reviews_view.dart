import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/widgets/widgets.dart';
import '../../../data/models.dart';
import '../../../data/stores.dart';
import 'approval_cards.dart';

/// Daily + weekly reviews. Stats are computed locally; the text is the
/// assistant's (mocked until the API is connected). UI_UX.md §9.5.
class ReviewsView extends ConsumerStatefulWidget {
  const ReviewsView({super.key});

  @override
  ConsumerState<ReviewsView> createState() => _ReviewsViewState();
}

class _ReviewsViewState extends ConsumerState<ReviewsView> {
  int _which = 0;

  @override
  Widget build(BuildContext context) {
    final navSpace = Sizes.navHeight + 30 + MediaQuery.paddingOf(context).bottom;
    return ListView(
      padding: EdgeInsets.fromLTRB(Space.screen, 0, Space.screen, navSpace),
      children: [
        FilterChipRow(
          padding: EdgeInsets.zero,
          selected: _which,
          onSelected: (i) => setState(() => _which = i),
          chips: const [FilterChipData('Today'), FilterChipData('This week')],
        ),
        const SizedBox(height: Space.lg),
        if (_which == 0) const _Daily() else const _Weekly(),
      ],
    );
  }
}

class _Daily extends ConsumerWidget {
  const _Daily();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final tasks = ref.watch(tasksProvider);
    final habits = ref.watch(habitsProvider);
    final learning = ref.watch(learningProvider);
    final proposals = ref.watch(assistantProvider.select((s) => s.proposals.where((p) => p.origin == 'daily_review').toList()));
    final doneToday = tasks.where((t) => t.done && t.completedAt != null && sameDay(t.completedAt!, now)).toList();
    final overdue = tasks.where((t) => t.isOverdue(now)).toList();
    final habitsDone = habits.where((h) => h.doneOn(now)).length;
    final study = learning.minutesOn(now);
    final live = ref.watch(authProvider.select((a) => a.live));
    final review = ref.watch(reviewsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassCard(
          ai: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const AiMark(size: 26),
                  const SizedBox(width: Space.sm),
                  Expanded(child: Text('Daily review', style: LifeText.label, overflow: TextOverflow.ellipsis)),
                  Text(DateFormat('EEE d MMM').format(now), style: LifeText.mono),
                ],
              ),
              const SizedBox(height: Space.md),
              Text(
                live && review.insight != null
                    ? review.insight!
                    : '${doneToday.isEmpty ? 'A quiet day so far' : 'Solid day'} — ${doneToday.length} tasks done and ${formatMinutes(study.toDouble())} of study. '
                        '${overdue.isEmpty ? 'Nothing is overdue.' : '${overdue.length} item${overdue.length == 1 ? '' : 's'} slipped${live ? '.' : '; I suggested a realistic fix for tomorrow.'}'}',
                style: LifeText.titleSerif.copyWith(fontSize: 22, height: 1.25),
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.cardGap),
        Row(
          children: [
            Expanded(child: AnimatedStatCard(label: 'Tasks done', value: doneToday.length, icon: LucideIcons.squareCheck)),
            const SizedBox(width: Space.cardGap),
            Expanded(
              child: AnimatedStatCard(
                label: 'Study',
                value: study,
                icon: LucideIcons.timer,
                accent: LifeColors.mint,
                format: formatMinutes,
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.cardGap),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Habits · $habitsDone of ${habits.length}', style: LifeText.title),
              const SizedBox(height: Space.md),
              Row(
                children: [
                  for (final h in habits)
                    Padding(
                      padding: const EdgeInsets.only(right: Space.sm),
                      child: Tooltip(
                        message: h.title,
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: h.doneOn(now) ? h.color : LifeColors.glassHigh,
                          ),
                          child: Icon(h.icon, size: 14, color: h.doneOn(now) ? LifeColors.onLight : LifeColors.text3),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.cardGap),
        _ListCard(
          title: 'Went well',
          icon: LucideIcons.sparkles,
          color: LifeColors.mint,
          items: live && review.highlights.isNotEmpty
              ? review.highlights
              : [
                  for (final t in doneToday.take(3)) t.title,
                  if (study >= 60) 'Over an hour of focused study',
                ],
        ),
        if (overdue.isNotEmpty || (live && review.attention.isNotEmpty)) ...[
          const SizedBox(height: Space.cardGap),
          _ListCard(
            title: 'Needs care',
            icon: LucideIcons.circleAlert,
            color: LifeColors.amber,
            items: live && review.attention.isNotEmpty ? review.attention : [for (final t in overdue) '${t.title} (overdue)'],
          ),
        ],
        if (proposals.isNotEmpty) ...[
          const SizedBox(height: Space.section),
          const SectionHeader(title: 'For tomorrow'),
          ProposalsBlock(ids: [for (final p in proposals) p.id]),
        ],
      ],
    );
  }
}

class _Weekly extends ConsumerWidget {
  const _Weekly();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final tasks = ref.watch(tasksProvider);
    final learning = ref.watch(learningProvider);
    final habits = ref.watch(habitsProvider);
    final live = ref.watch(authProvider.select((a) => a.live));
    final review = ref.watch(reviewsProvider);
    final days = [for (var i = 6; i >= 0; i--) dateOnly(now.subtract(Duration(days: i)))];
    final perDay = [
      for (final d in days)
        tasks.where((t) => t.done && t.completedAt != null && sameDay(t.completedAt!, d)).length.toDouble() +
            // sample mode pads past days so the chart has a shape
            (live || d == days.last ? 0 : (3 + d.day % 4)),
    ];
    const sampleNext = [
      'Keep DSA mornings — finish sliding window, start stacks.',
      'Two 45-minute Docker sessions (Tue, Thu).',
      'Move resume updates to Monday afternoon.',
      'Protect sleep before the mock interview.',
    ];
    final next = live ? review.recommendations : sampleNext;
    final study = days.fold(0, (a, d) => a + learning.minutesOn(d));
    final consistency = habits.isEmpty
        ? 0.0
        : habits.fold(0, (a, h) => a + days.where(h.doneOn).length) / (habits.length * days.length);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassCard(
          ai: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const AiMark(size: 26),
                  const SizedBox(width: Space.sm),
                  Expanded(child: Text('Weekly review', style: LifeText.label, overflow: TextOverflow.ellipsis)),
                  Flexible(
                    child: Text(
                      '${DateFormat('d MMM').format(days.first)} – ${DateFormat('d MMM').format(days.last)}',
                      style: LifeText.mono,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.md),
              Text(
                live
                    ? (review.weeklyReport ??
                        'This week: ${formatMinutes(study.toDouble())} of study and ${perDay.fold(0.0, (a, b) => a + b).round()} tasks done. '
                            'Habits held at ${(consistency * 100).round()}%. Your full weekly review arrives on Sunday evening.')
                    : 'Your best study week this month: ${formatMinutes(study.toDouble())}, mostly DSA. '
                        'Habits held at ${(consistency * 100).round()}%. Docker slowed down mid-week — two short sessions would get it moving again.',
                style: LifeText.body,
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.cardGap),
        Row(
          children: [
            Expanded(child: AnimatedStatCard(label: 'Study', value: study, icon: LucideIcons.timer, accent: LifeColors.mint, format: formatMinutes, trend: live ? null : 0.18)),
            const SizedBox(width: Space.cardGap),
            Expanded(child: AnimatedStatCard(label: 'Habits', value: consistency * 100, suffix: '%', icon: LucideIcons.flame, accent: LifeColors.coral, trend: live ? null : 0.04)),
          ],
        ),
        const SizedBox(height: Space.cardGap),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Tasks completed', style: LifeText.title),
              const SizedBox(height: Space.lg),
              LineAreaChart(
                values: perDay,
                labels: [for (final d in days) DateFormat('E').format(d).substring(0, 1)],
                color: LifeColors.iris,
                height: 140,
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.cardGap),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Next week', style: LifeText.title),
              const SizedBox(height: Space.md),
              if (next.isEmpty)
                GradientButton(
                  label: 'Generate my weekly review',
                  icon: LucideIcons.sparkles,
                  variant: ButtonVariant.glass,
                  expand: true,
                  loading: review.busy,
                  onPressed: () async {
                    final err = await ref.read(reviewsProvider.notifier).runWeekly();
                    if (err != null && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                    }
                  },
                ),
              for (final (i, r) in next.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.md),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(color: LifeColors.glassHigh, shape: BoxShape.circle),
                        child: Text('${i + 1}', style: LifeText.caption.copyWith(color: LifeColors.text)),
                      ),
                      const SizedBox(width: Space.md),
                      Expanded(child: Text(r, style: LifeText.body)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ListCard extends StatelessWidget {
  const _ListCard({required this.title, required this.icon, required this.color, required this.items});

  final String title;
  final IconData icon;
  final Color color;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return GlassCard(
      tint: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Icon(icon, size: 16, color: color), const SizedBox(width: Space.sm), Text(title, style: LifeText.title)]),
          const SizedBox(height: Space.sm),
          for (final i in items)
            Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: Text('· $i', style: LifeText.body.copyWith(color: LifeColors.text2)),
            ),
        ],
      ),
    );
  }
}

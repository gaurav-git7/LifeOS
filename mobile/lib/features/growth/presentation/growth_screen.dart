import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/routing/routes.dart';
import '../../../core/widgets/layout/tab_scaffold.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/models.dart';
import '../../../data/stores.dart';
import '../../../shared/create_sheets.dart';
import 'growth_widgets.dart';

/// Skills, roadmaps, study and projects. See docs/UI_UX.md §9.3.
class GrowthScreen extends ConsumerStatefulWidget {
  const GrowthScreen({super.key});

  @override
  ConsumerState<GrowthScreen> createState() => _GrowthScreenState();
}

class _GrowthScreenState extends ConsumerState<GrowthScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final info = ref.watch(progressionProvider).info;
    final body = switch (_tab) {
      0 => const _Overview(),
      1 => const _SkillsTab(),
      2 => const _RoadmapsTab(),
      3 => const _StudyTab(),
      _ => const _ProjectsTab(),
    };
    return TabScaffold(
      title: 'Growth',
      subtitle: '${info.rank} · Level ${info.level}',
      actions: [
        IconGlassButton(
          icon: LucideIcons.trophy,
          semanticLabel: 'Achievements',
          onPressed: () => context.push(Routes.achievements),
        ),
      ],
      slivers: [
        const SliverSection(bottom: Space.lg, child: _LevelCard()),
        // Five sections don't fit a segmented control on a phone; chips scroll.
        SliverPadding(
          padding: const EdgeInsets.only(bottom: Space.lg),
          sliver: SliverToBoxAdapter(
            child: FilterChipRow(
              selected: _tab,
              onSelected: (i) => setState(() => _tab = i),
              chips: const [
                FilterChipData('Overview', icon: LucideIcons.layoutGrid),
                FilterChipData('Skills', icon: LucideIcons.gem),
                FilterChipData('Roadmaps', icon: LucideIcons.map),
                FilterChipData('Study', icon: LucideIcons.timer),
                FilterChipData('Projects', icon: LucideIcons.folderGit2),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: Space.screen),
          sliver: SliverToBoxAdapter(
            child: AnimatedSwitcher(
              duration: Motion.of(context, Motion.card),
              transitionBuilder: (c, a) => FadeTransition(opacity: a, child: c),
              child: KeyedSubtree(key: ValueKey(_tab), child: body),
            ),
          ),
        ),
      ],
    );
  }
}

class _LevelCard extends ConsumerWidget {
  const _LevelCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prog = ref.watch(progressionProvider);
    final info = prog.info;
    final habits = ref.watch(habitsProvider);
    final skills = ref.watch(learningProvider.select((s) => s.skills));
    final badges = ref.watch(achievementsProvider).where((a) => a.unlockedAt != null).length;
    final best = habits.fold(0, (a, h) => h.streak > a ? h.streak : a);
    final sp = skills.fold(0, (a, s) => a + s.skillPoints);
    final f = NumberFormat.decimalPattern();
    return GlassCard(
      tint: LifeColors.mint,
      child: Column(
        children: [
          Row(
            children: [
              AnimatedProgressRing(
                value: info.progress,
                color: LifeColors.mint,
                size: 76,
                stroke: 8,
                child: Text('${info.level}', style: LifeText.stat),
              ),
              const SizedBox(width: Space.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(info.rank, style: LifeText.titleSerifItalic.copyWith(fontSize: 24)),
                    const SizedBox(height: Space.sm),
                    GlowBar(value: info.progress, gradient: const LinearGradient(colors: [LifeColors.mint, LifeColors.sky])),
                    const SizedBox(height: Space.xs),
                    Text('${f.format(info.into)} / ${f.format(info.forNext)} XP to level ${info.level + 1}', style: LifeText.mono),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.lg),
          Row(
            children: [
              _Pill(icon: LucideIcons.flame, color: LifeColors.amber, text: '$best-day streak'),
              const SizedBox(width: Space.sm),
              _Pill(icon: LucideIcons.gem, color: LifeColors.sky, text: '$sp SP'),
              const SizedBox(width: Space.sm),
              _Pill(icon: LucideIcons.award, color: LifeColors.rose, text: '$badges badges'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(color: LifeColors.glass, borderRadius: Radii.rPill, border: Border.all(color: LifeColors.hairline)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 5),
              Flexible(child: Text(text, style: LifeText.caption.copyWith(color: LifeColors.text), overflow: TextOverflow.ellipsis)),
            ],
          ),
        ),
      );
}

// ---------------------------------------------------------------- overview

class _Overview extends ConsumerWidget {
  const _Overview();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = ref.watch(learningProvider);
    final skills = [...l.skills]..sort((a, b) => b.level.compareTo(a.level));
    final now = DateTime.now();
    final days = [for (var i = 6; i >= 0; i--) now.subtract(Duration(days: i))];
    final minutes = [for (final d in days) l.minutesOn(d).toDouble()];
    final total = minutes.fold(0.0, (a, b) => a + b);
    final achievements = ref.watch(achievementsProvider).where((a) => a.unlockedAt != null).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Skill profile', style: LifeText.title),
              Text('Current level vs. target', style: LifeText.caption),
              const SizedBox(height: Space.md),
              SkillRadar(skills: skills),
            ],
          ),
        ),
        const SizedBox(height: Space.cardGap),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Study this week', style: LifeText.eyebrow),
                        AnimatedCounter(value: total, format: formatMinutes, style: LifeText.statLarge),
                      ],
                    ),
                  ),
                  const TrendLabel(trend: 0.18),
                ],
              ),
              const SizedBox(height: Space.lg),
              LineAreaChart(
                values: minutes,
                labels: [for (final d in days) DateFormat('E').format(d).substring(0, 1)],
                color: LifeColors.mint,
                format: formatMinutes,
                height: 140,
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.cardGap),
        if (l.paths.isNotEmpty) _PathCard(path: l.paths.first),
        const SizedBox(height: Space.cardGap),
        if (achievements.isNotEmpty)
          GlassCard(
            onTap: () => context.push(Routes.achievements),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text('Recent achievements', style: LifeText.title)),
                    const Icon(LucideIcons.chevronRight, size: 18, color: LifeColors.text3),
                  ],
                ),
                const SizedBox(height: Space.md),
                Row(
                  children: [
                    for (final a in achievements.take(4))
                      Padding(
                        padding: const EdgeInsets.only(right: Space.md),
                        child: Tooltip(message: a.title, child: IconChip(icon: a.icon, color: a.color, size: 44)),
                      ),
                  ],
                ),
              ],
            ),
          ),
        const SizedBox(height: Space.xl),
        GradientButton(
          label: 'Start focus session',
          icon: LucideIcons.timer,
          expand: true,
          onPressed: () => context.push(Routes.focus),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- skills

class _SkillsTab extends ConsumerWidget {
  const _SkillsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skills = ref.watch(learningProvider.select((s) => s.skills));
    return Column(
      children: [
        for (final (i, s) in skills.indexed)
          StaggeredEntry(
            index: i,
            child: Padding(
              padding: const EdgeInsets.only(bottom: Space.cardGap),
              child: GlassCard(
                padding: const EdgeInsets.all(Space.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        IconChip(icon: s.icon, color: s.color, size: 38),
                        const SizedBox(width: Space.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s.name, style: LifeText.title),
                              Text('${levelNames[s.level - 1]} · ${s.skillPoints} SP', style: LifeText.caption),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Sparkline(values: s.weekMinutes, color: s.color),
                            Text(formatMinutes(s.weekMinutes.fold(0, (a, b) => a + b).toDouble()), style: LifeText.mono),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: Space.md),
                    LevelSegments(level: s.level, target: s.target, color: s.color),
                  ],
                ),
              ),
            ),
          ),
        GradientButton(
          label: 'Track a skill',
          icon: LucideIcons.plus,
          variant: ButtonVariant.glass,
          expand: true,
          onPressed: () => showSkillEditor(context),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- roadmaps

class _PathCard extends StatelessWidget {
  const _PathCard({required this.path});

  final LearningPath path;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: () => context.push(Routes.roadmap(path.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(path.title, style: LifeText.title)),
              Text('${(path.progress * 100).round()}%', style: LifeText.stat.copyWith(fontSize: 18, color: LifeColors.mint)),
            ],
          ),
          const SizedBox(height: Space.md),
          Row(
            children: [
              for (final t in path.topics)
                Expanded(
                  child: Container(
                    height: 6,
                    margin: const EdgeInsets.only(right: 3),
                    decoration: BoxDecoration(
                      borderRadius: Radii.rPill,
                      color: switch (t.status) {
                        TopicStatus.done => LifeColors.mint,
                        TopicStatus.inProgress => LifeColors.mint.withValues(alpha: 0.45),
                        TopicStatus.notStarted => LifeColors.track,
                      },
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: Space.md),
          Text(
            path.nextTopic == null ? 'Completed 🎉' : 'Next: ${path.nextTopic!.title}',
            style: LifeText.caption,
          ),
        ],
      ),
    );
  }
}

class _RoadmapsTab extends ConsumerWidget {
  const _RoadmapsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paths = ref.watch(learningProvider.select((s) => s.paths));
    final due = [for (final p in paths) ...p.topics.where((t) => t.revisionDue).map((t) => (p, t))];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (due.isNotEmpty) ...[
          GlassCard(
            tint: LifeColors.amber,
            padding: const EdgeInsets.all(Space.lg),
            child: Row(
              children: [
                const IconChip(icon: LucideIcons.refreshCw, color: LifeColors.amber),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Text('${due.length} topic${due.length == 1 ? '' : 's'} due for revision: ${due.map((e) => e.$2.title).join(', ')}',
                      style: LifeText.body),
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.cardGap),
        ],
        for (final (i, p) in paths.indexed)
          StaggeredEntry(index: i, child: Padding(padding: const EdgeInsets.only(bottom: Space.cardGap), child: _PathCard(path: p))),
        GradientButton(
          label: 'New roadmap',
          icon: LucideIcons.plus,
          variant: ButtonVariant.glass,
          expand: true,
          onPressed: () => showRoadmapEditor(context),
        ),
        const SizedBox(height: Space.sm),
        GradientButton(
          label: 'Ask the assistant to plan one',
          icon: LucideIcons.sparkles,
          variant: ButtonVariant.ghost,
          expand: true,
          onPressed: () {
            ref.read(assistantTabProvider.notifier).set(0);
            context.go(Routes.assistant);
          },
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- study

class _StudyTab extends ConsumerWidget {
  const _StudyTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = ref.watch(learningProvider);
    final now = DateTime.now();
    final days = [for (var i = 6; i >= 0; i--) now.subtract(Duration(days: i))];
    final perSkill = <Skill, int>{};
    for (final s in l.sessions.where((s) => now.difference(s.start).inDays < 7)) {
      final k = l.skill(s.skillId);
      if (k != null) perSkill[k] = (perSkill[k] ?? 0) + s.minutes;
    }
    final maxSkill = perSkill.values.fold(1, (a, b) => b > a ? b : a);
    final recent = [...l.sessions]..sort((a, b) => b.start.compareTo(a.start));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassCard(
          tint: LifeColors.mint,
          onTap: () => context.push(Routes.focus),
          child: Row(
            children: [
              AnimatedProgressRing(
                value: (l.minutesOn(now) / 180).clamp(0, 1),
                color: LifeColors.mint,
                size: 64,
                stroke: 7,
                child: const Icon(LucideIcons.timer, size: 22, color: LifeColors.mint),
              ),
              const SizedBox(width: Space.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${formatMinutes(l.minutesOn(now).toDouble())} today', style: LifeText.h2),
                    Text('Tap to start a focus session', style: LifeText.caption),
                  ],
                ),
              ),
              const Icon(LucideIcons.chevronRight, color: LifeColors.text2),
            ],
          ),
        ),
        const SizedBox(height: Space.cardGap),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Daily study', style: LifeText.title),
              Text('Minutes per day', style: LifeText.caption),
              const SizedBox(height: Space.lg),
              GlowBarChart(
                values: [for (final d in days) l.minutesOn(d).toDouble()],
                labels: [for (final d in days) DateFormat('E').format(d).substring(0, 1)],
                highlightIndex: 6,
                color: LifeColors.mint,
                format: formatMinutes,
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.cardGap),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('By skill · 7 days', style: LifeText.title),
              const SizedBox(height: Space.md),
              for (final e in (perSkill.entries.toList()..sort((a, b) => b.value.compareTo(a.value))))
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.md),
                  child: Row(
                    children: [
                      SizedBox(width: 80, child: Text(e.key.name, style: LifeText.label)),
                      Expanded(child: GlowBar(value: e.value / maxSkill, color: e.key.color, height: 8)),
                      SizedBox(width: 60, child: Text(formatMinutes(e.value.toDouble()), textAlign: TextAlign.right, style: LifeText.mono)),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: Space.section),
        const SectionHeader(title: 'Sessions'),
        GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.sm),
          child: Column(
            children: [
              for (final (i, s) in recent.take(8).indexed) ...[
                if (i > 0) const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.md),
                  child: Row(
                    children: [
                      IconChip(icon: l.skill(s.skillId)?.icon ?? LucideIcons.bookOpen, color: l.skill(s.skillId)?.color ?? LifeColors.mint),
                      const SizedBox(width: Space.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.label, style: LifeText.bodyStrong),
                            Text(DateFormat('EEE d MMM · h:mm a').format(s.start), style: LifeText.caption),
                          ],
                        ),
                      ),
                      Text(formatMinutes(s.minutes.toDouble()), style: LifeText.mono.copyWith(color: LifeColors.text)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- projects

class _ProjectsTab extends ConsumerWidget {
  const _ProjectsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(learningProvider.select((s) => s.projects));
    final today = dateOnly(DateTime.now());
    return Column(
      children: [
        for (final (i, p) in projects.indexed)
          StaggeredEntry(
            index: i,
            child: Padding(
              padding: const EdgeInsets.only(bottom: Space.cardGap),
              child: GlassCard(
                onTap: () => showGlassSheet<void>(context, builder: (_) => _ProjectDetail(projectId: p.id)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        IconChip(icon: LucideIcons.folderGit2, color: p.color, size: 38),
                        const SizedBox(width: Space.md),
                        Expanded(child: Text(p.name, style: LifeText.title)),
                        Text('${(p.progress * 100).round()}%', style: LifeText.stat.copyWith(fontSize: 18)),
                      ],
                    ),
                    const SizedBox(height: Space.md),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final s in p.stack)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                            decoration: BoxDecoration(color: LifeColors.glassHigh, borderRadius: Radii.rPill),
                            child: Text(s, style: LifeText.caption.copyWith(color: LifeColors.text)),
                          ),
                      ],
                    ),
                    const SizedBox(height: Space.md),
                    GlowBar(value: p.progress, color: p.color),
                    const SizedBox(height: Space.md),
                    Row(
                      children: [
                        Expanded(child: Text('Next: ${p.nextMilestone ?? '—'}', style: LifeText.caption, overflow: TextOverflow.ellipsis)),
                        if (p.deadline != null) Text('${p.deadline!.difference(today).inDays}d left', style: LifeText.mono),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        GradientButton(
          label: 'New project',
          icon: LucideIcons.plus,
          variant: ButtonVariant.glass,
          expand: true,
          onPressed: () => showProjectEditor(context),
        ),
      ],
    );
  }
}

class _ProjectDetail extends ConsumerWidget {
  const _ProjectDetail({required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(learningProvider).projects.where((x) => x.id == projectId).firstOrNull;
    if (p == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(p.name, style: LifeText.titleSerif),
        if (p.description != null) ...[
          const SizedBox(height: Space.xs),
          Text(p.description!, style: LifeText.body.copyWith(color: LifeColors.text2)),
        ],
        const SizedBox(height: Space.lg),
        GlowBar(value: p.progress, color: p.color),
        const SizedBox(height: Space.xl),
        Text('Milestones', style: LifeText.eyebrow),
        if (p.milestones.isEmpty) Padding(padding: const EdgeInsets.only(top: Space.sm), child: Text('No milestones yet.', style: LifeText.caption)),
        for (final m in p.milestones)
          Row(
            children: [
              AnimatedCheck(
                checked: m.done,
                color: p.color,
                onChanged: (_) => ref.read(learningProvider.notifier).toggleProjectMilestone(p.id, m.id),
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
        Align(
          alignment: Alignment.centerLeft,
          child: GradientButton(
            label: 'Add milestone',
            icon: LucideIcons.plus,
            variant: ButtonVariant.ghost,
            compact: true,
            onPressed: () => showMilestoneAdder(context, projectId: p.id),
          ),
        ),
        const SizedBox(height: Space.lg),
        GradientButton(
          label: 'Delete project',
          icon: LucideIcons.trash2,
          variant: ButtonVariant.danger,
          expand: true,
          onPressed: () {
            ref.read(learningProvider.notifier).removeProject(p.id);
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
}

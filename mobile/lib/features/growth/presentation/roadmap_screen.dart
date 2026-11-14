import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/routing/routes.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/models.dart';
import '../../../data/seed.dart';
import '../../../data/stores.dart';
import '../../../shared/create_sheets.dart';

/// A learning path as a vertical progression. See docs/UI_UX.md §9.3 (Roadmaps).
class RoadmapScreen extends ConsumerWidget {
  const RoadmapScreen({super.key, required this.pathId});

  final String pathId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = ref.watch(learningProvider).paths.where((p) => p.id == pathId).firstOrNull;
    return Scaffold(
      backgroundColor: LifeColors.bg,
      body: Stack(
        children: [
          const Positioned.fill(child: AmbientBackground(mode: AmbientMode.growth)),
          SafeArea(
            child: path == null
                ? const Center(child: EmptyState(title: 'Roadmap not found', message: 'It may have been removed.'))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(Space.screen, Space.lg, Space.screen, 60),
                    children: [
                      Row(
                        children: [
                          IconGlassButton(icon: Icons.arrow_back_rounded, semanticLabel: 'Back', onPressed: () => context.pop()),
                          const Spacer(),
                          IconGlassButton(
                            icon: LucideIcons.trash2,
                            semanticLabel: 'Delete roadmap',
                            onPressed: () async {
                              final ok = await showDialog<bool>(
                                context: context,
                                builder: (c) => AlertDialog(
                                  backgroundColor: LifeColors.surfaceHigh,
                                  title: Text('Delete this roadmap?', style: LifeText.h2),
                                  content: Text('Its topics and progress are removed.', style: LifeText.body),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                                    TextButton(
                                      onPressed: () => Navigator.pop(c, true),
                                      child: const Text('Delete', style: TextStyle(color: LifeColors.danger)),
                                    ),
                                  ],
                                ),
                              );
                              if (ok == true && context.mounted) {
                                ref.read(learningProvider.notifier).removePath(pathId);
                                context.pop();
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: Space.lg),
                      Text('Roadmap', style: LifeText.eyebrow),
                      Text(path.title, style: LifeText.display),
                      const SizedBox(height: Space.md),
                      Row(
                        children: [
                          Expanded(child: GlowBar(value: path.progress, color: LifeColors.mint, height: 6)),
                          const SizedBox(width: Space.md),
                          Text(
                            '${path.topics.where((t) => t.status == TopicStatus.done).length}/${path.topics.length}',
                            style: LifeText.mono.copyWith(color: LifeColors.text),
                          ),
                        ],
                      ),
                      if (path.targetDate != null) ...[
                        const SizedBox(height: Space.xs),
                        Text('Target ${DateFormat('d MMM').format(path.targetDate!)}', style: LifeText.caption),
                      ],
                      const SizedBox(height: Space.xxl),
                      for (final (i, t) in path.topics.indexed)
                        StaggeredEntry(
                          index: i,
                          child: _TopicNode(
                            path: path,
                            topic: t,
                            isLast: i == path.topics.length - 1,
                            locked: t.prerequisites.any(
                              (id) => path.topics.where((x) => x.id == id).firstOrNull?.status != TopicStatus.done,
                            ),
                          ),
                        ),
                      const SizedBox(height: Space.md),
                      GradientButton(
                        label: 'Add topic',
                        icon: LucideIcons.plus,
                        variant: ButtonVariant.glass,
                        expand: true,
                        onPressed: () => showTopicAdder(context, path.id),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _TopicNode extends ConsumerWidget {
  const _TopicNode({required this.path, required this.topic, required this.isLast, required this.locked});

  final LearningPath path;
  final Topic topic;
  final bool isLast;
  final bool locked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final done = topic.status == TopicStatus.done;
    final active = topic.status == TopicStatus.inProgress;
    final color = done || active ? LifeColors.mint : (locked ? LifeColors.text3 : LifeColors.text2);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 34,
            child: Column(
              children: [
                const SizedBox(height: 16),
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: done ? LifeColors.mint : Colors.transparent,
                    border: Border.all(color: color, width: 2),
                    boxShadow: done || active ? LifeShadows.halo(LifeColors.mint, 0.8) : null,
                  ),
                  child: done
                      ? const Icon(Icons.check_rounded, size: 15, color: LifeColors.onLight)
                      : active
                          ? Center(
                              child: Container(
                                width: 9,
                                height: 9,
                                decoration: const BoxDecoration(color: LifeColors.mint, shape: BoxShape.circle),
                              ),
                            )
                          : (locked ? const Icon(LucideIcons.lock, size: 11, color: LifeColors.text3) : null),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: done ? LifeColors.mint.withValues(alpha: 0.6) : LifeColors.hairline,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: Space.md),
              child: Opacity(
                opacity: locked ? 0.55 : 1,
                child: GlassCard(
                  padding: const EdgeInsets.all(Space.lg),
                  onTap: () => _openTopic(context, ref),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(topic.title, style: LifeText.bodyStrong)),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(color: topic.difficulty.color.withValues(alpha: 0.16), borderRadius: Radii.rPill),
                            child: Text(topic.difficulty.label, style: LifeText.caption.copyWith(color: topic.difficulty.color)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (done) 'Done',
                          if (active) 'In progress',
                          if (locked) 'Locked · needs prerequisites',
                          if (!done && !active && !locked) 'Not started',
                          if (topic.sessions > 0) '${topic.sessions} sessions',
                          if (topic.revisionCount > 0) 'revised ${topic.revisionCount}×',
                        ].join(' · '),
                        style: LifeText.caption,
                      ),
                      if (topic.revisionDue) ...[
                        const SizedBox(height: Space.sm),
                        Row(
                          children: [
                            const Icon(LucideIcons.refreshCw, size: 13, color: LifeColors.amber),
                            const SizedBox(width: 4),
                            Text('Revision due', style: LifeText.caption.copyWith(color: LifeColors.amber)),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openTopic(BuildContext context, WidgetRef ref) {
    final prereqs = path.topics.where((t) => topic.prerequisites.contains(t.id)).toList();
    showGlassSheet<void>(
      context,
      title: topic.title,
      builder: (sheet) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (topic.description != null) ...[
            Text(topic.description!, style: LifeText.body.copyWith(color: LifeColors.text2)),
            const SizedBox(height: Space.lg),
          ],
          Row(
            children: [
              IconChip(icon: LucideIcons.gauge, color: topic.difficulty.color),
              const SizedBox(width: Space.sm),
              Text(topic.difficulty.label, style: LifeText.label),
              const SizedBox(width: Space.lg),
              const IconChip(icon: LucideIcons.clock, color: LifeColors.sky),
              const SizedBox(width: Space.sm),
              Text('~${formatMinutes(topic.estimatedMinutes.toDouble())}', style: LifeText.label),
            ],
          ),
          if (prereqs.isNotEmpty) ...[
            const SizedBox(height: Space.lg),
            Text('Needs', style: LifeText.eyebrow),
            for (final p in prereqs)
              Padding(
                padding: const EdgeInsets.only(top: Space.xs),
                child: Row(
                  children: [
                    Icon(
                      p.status == TopicStatus.done ? LucideIcons.circleCheck : LucideIcons.circleDashed,
                      size: 16,
                      color: p.status == TopicStatus.done ? LifeColors.mint : LifeColors.text3,
                    ),
                    const SizedBox(width: Space.sm),
                    Text(p.title, style: LifeText.body),
                  ],
                ),
              ),
          ],
          if (topic.nextRevision != null) ...[
            const SizedBox(height: Space.lg),
            Text('Next revision ${DateFormat('EEE d MMM').format(topic.nextRevision!)}', style: LifeText.mono),
          ],
          const SizedBox(height: Space.xl),
          GradientButton(
            label: 'Start focus on this',
            icon: LucideIcons.timer,
            expand: true,
            onPressed: () {
              Navigator.of(sheet).pop();
              ref.read(learningProvider.notifier).startTopic(path.id, topic.id);
              context.push(Routes.focusFor(topic.id));
            },
          ),
          const SizedBox(height: Space.sm),
          if (topic.status != TopicStatus.done)
            GradientButton(
              label: 'Mark as done',
              icon: LucideIcons.check,
              variant: ButtonVariant.glass,
              expand: true,
              onPressed: () {
                ref.read(learningProvider.notifier).completeTopic(path.id, topic.id);
                Navigator.of(sheet).pop();
              },
            )
          else
            GradientButton(
              label: 'Mark revised',
              icon: LucideIcons.refreshCw,
              variant: ButtonVariant.glass,
              expand: true,
              onPressed: () {
                ref.read(learningProvider.notifier).reviseTopic(path.id, topic.id);
                Navigator.of(sheet).pop();
              },
            ),
        ],
      ),
    );
  }
}


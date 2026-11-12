import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/widgets/widgets.dart';

/// Every design-system component in one place (debug builds only).
/// See docs/UI_UX.md §12 and §18 step 4.
class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  AiState _ai = AiState.idle;
  double _ring = 0.62;
  int _burst = 0;
  int _xp = 1240;
  int _segment = 0;
  int _chip = 0;
  double _slider = 6;
  bool _loading = false;
  final _tasks = <String, bool>{
    'Solve 3 sliding-window problems': false,
    'Write first Dockerfile': true,
    'Revise SQL joins': false,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LifeColors.bg,
      body: Stack(
        children: [
          const Positioned.fill(child: AmbientBackground(mode: AmbientMode.home)),
          SafeArea(
            bottom: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(Space.screen, Space.lg, Space.screen, 80),
              children: [
                Row(
                  children: [
                    IconGlassButton(icon: Icons.arrow_back_rounded, onPressed: () => context.pop(), semanticLabel: 'Back'),
                    const SizedBox(width: Space.sm),
                    Text('Components', style: LifeText.titleSerif),
                  ],
                ),

                _section('AI mark + AI border'),
                GlassCard(
                  ai: true,
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          AiMark(size: 96, state: _ai),
                          const AiMark(size: 40),
                          const AiMark(size: 24),
                        ],
                      ),
                      const SizedBox(height: Space.lg),
                      SegmentedGlass(
                        segments: const ['Idle', 'Thinking'],
                        index: _ai.index,
                        onChanged: (i) => setState(() => _ai = AiState.values[i]),
                      ),
                    ],
                  ),
                ),

                _section('Activity rings + burst'),
                GlassCard(
                  child: Column(
                    children: [
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          ActivityRings(
                            size: 170,
                            stroke: 16,
                            rings: [
                              RingData(_ring, LifeColors.iris),
                              RingData(_ring * 0.8, LifeColors.coral),
                              RingData(_ring * 0.6, LifeColors.mint),
                            ],
                          ),
                          GlowBurst(trigger: _burst, size: 230),
                        ],
                      ),
                      Slider(
                        value: _ring,
                        onChanged: (v) => setState(() => _ring = v),
                        activeColor: Colors.white,
                        inactiveColor: LifeColors.track,
                      ),
                      GradientButton(
                        label: 'Celebrate',
                        icon: LucideIcons.sparkles,
                        compact: true,
                        onPressed: () => setState(() {
                          _ring = 1;
                          _burst++;
                        }),
                      ),
                    ],
                  ),
                ),

                _section('Stats + XP'),
                const Row(
                  children: [
                    Expanded(
                      child: AnimatedStatCard(
                        label: 'Study',
                        value: 520,
                        icon: LucideIcons.timer,
                        accent: LifeColors.mint,
                        format: formatMinutes,
                        trend: 0.18,
                      ),
                    ),
                    SizedBox(width: Space.cardGap),
                    Expanded(
                      child: AnimatedStatCard(
                        label: 'Tasks done',
                        value: 23,
                        icon: LucideIcons.squareCheck,
                        trend: -0.05,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Space.cardGap),
                GlassCard(
                  child: Column(
                    children: [
                      XpBar(level: 7, xp: _xp, xpForNext: 1600),
                      const SizedBox(height: Space.lg),
                      GradientButton(
                        label: '+40 XP',
                        compact: true,
                        variant: ButtonVariant.glass,
                        onPressed: () => setState(() => _xp = (_xp + 40) % 1600),
                      ),
                    ],
                  ),
                ),

                _section('Buttons'),
                Wrap(
                  spacing: Space.sm,
                  runSpacing: Space.sm,
                  children: [
                    GradientButton(label: 'Primary', icon: LucideIcons.check, onPressed: () {}),
                    GradientButton(label: 'Accent', variant: ButtonVariant.accent, onPressed: () {}),
                    GradientButton(label: 'Glass', variant: ButtonVariant.glass, onPressed: () {}),
                    GradientButton(label: 'Ghost', variant: ButtonVariant.ghost, onPressed: () {}),
                    GradientButton(label: 'Delete', variant: ButtonVariant.danger, onPressed: () {}),
                    GradientButton(
                      label: _loading ? 'Saving' : 'Tap to load',
                      loading: _loading,
                      variant: ButtonVariant.glass,
                      onPressed: () {
                        setState(() => _loading = true);
                        Future.delayed(const Duration(seconds: 2), () {
                          if (mounted) setState(() => _loading = false);
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: Space.md),
                const Row(
                  children: [
                    IconGlassButton(icon: LucideIcons.bell, badge: true),
                    IconGlassButton(icon: LucideIcons.search),
                    IconGlassButton(icon: LucideIcons.settings),
                  ],
                ),

                _section('Inputs'),
                SegmentedGlass(
                  segments: const ['Tasks', 'Goals', 'Habits', 'Calendar'],
                  index: _segment,
                  badges: const {1: 2},
                  onChanged: (i) => setState(() => _segment = i),
                ),
                const SizedBox(height: Space.md),
                FilterChipRow(
                  padding: EdgeInsets.zero,
                  selected: _chip,
                  onSelected: (i) => setState(() => _chip = i),
                  chips: const [
                    FilterChipData('Today', count: 5),
                    FilterChipData('Upcoming', count: 12),
                    FilterChipData('Overdue', count: 2, accent: LifeColors.coral),
                    FilterChipData('Done'),
                  ],
                ),
                const SizedBox(height: Space.md),
                GlassCard(
                  child: GlassSlider(label: 'Energy', value: _slider, accent: LifeColors.amber, onChanged: (v) => setState(() => _slider = v)),
                ),
                const SizedBox(height: Space.md),
                const TextField(decoration: InputDecoration(hintText: 'Text field')),
                const SizedBox(height: Space.md),
                GlassCard(
                  padding: const EdgeInsets.symmetric(vertical: Space.xs, horizontal: Space.sm),
                  child: Column(
                    children: [
                      for (final e in _tasks.entries)
                        Row(
                          children: [
                            AnimatedCheck(checked: e.value, onChanged: (v) => setState(() => _tasks[e.key] = v)),
                            Expanded(
                              child: AnimatedDefaultTextStyle(
                                duration: Motion.check,
                                style: LifeText.body.copyWith(
                                  color: e.value ? LifeColors.text3 : LifeColors.text,
                                  decoration: e.value ? TextDecoration.lineThrough : null,
                                  decorationColor: LifeColors.text3,
                                ),
                                child: Text(e.key),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),

                _section('Charts'),
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Study this week', style: LifeText.eyebrow),
                      Text('8h 40m', style: LifeText.statLarge),
                      const TrendLabel(trend: 0.18),
                      const SizedBox(height: Space.lg),
                      const LineAreaChart(
                        values: [45, 80, 60, 120, 95, 140, 100],
                        labels: ['M', 'T', 'W', 'T', 'F', 'S', 'S'],
                        color: LifeColors.iris,
                        format: _minutes,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Space.cardGap),
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Problems solved', style: LifeText.eyebrow),
                      Text('31', style: LifeText.statLarge),
                      const SizedBox(height: Space.lg),
                      const GlowBarChart(
                        values: [3, 5, 2, 6, 4, 7, 4],
                        labels: ['M', 'T', 'W', 'T', 'F', 'S', 'S'],
                        highlightIndex: 6,
                        color: LifeColors.sky,
                      ),
                    ],
                  ),
                ),

                _section('Surfaces'),
                Row(
                  children: [
                    for (final t in [
                      ('Glass', GlassTier.glass, null),
                      ('Tinted', GlassTier.glass, LifeColors.mint),
                      ('Solid', GlassTier.solid, null),
                    ]) ...[
                      Expanded(
                        child: GlassCard(
                          tier: t.$2,
                          tint: t.$3,
                          padding: const EdgeInsets.all(Space.lg),
                          child: SizedBox(height: 60, child: Center(child: Text(t.$1, style: LifeText.label))),
                        ),
                      ),
                      if (t.$1 != 'Solid') const SizedBox(width: Space.sm),
                    ],
                  ],
                ),

                _section('Feedback'),
                GlassCard(
                  padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.sm),
                  child: Column(
                    children: [
                      CollapsibleSection(
                        title: 'Habits',
                        icon: LucideIcons.flame,
                        accent: LifeColors.coral,
                        summary: const Text('4 of 5 · 12-day streak'),
                        child: Text('Expanded content goes here.', style: LifeText.body),
                      ),
                      const Divider(height: Space.lg),
                      const CollapsibleSection(
                        title: 'Loading',
                        icon: LucideIcons.hourglass,
                        summary: Text('Skeleton placeholders'),
                        initiallyOpen: true,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SkeletonBox(width: 180),
                            SizedBox(height: Space.sm),
                            SkeletonBox(),
                            SizedBox(height: Space.sm),
                            SkeletonBox(width: 120),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Space.cardGap),
                const GlassCard(
                  child: EmptyState(
                    icon: LucideIcons.squareCheck,
                    title: 'No tasks today',
                    message: 'Enjoy it — or add one.',
                    actionLabel: 'Add a task',
                  ),
                ),

                _section('Bottom sheet'),
                GradientButton(
                  label: 'Open glass sheet',
                  expand: true,
                  variant: ButtonVariant.glass,
                  onPressed: () => showGlassSheet<void>(
                    context,
                    title: 'Glass sheet',
                    builder: (_) => Text(
                      'Frosted surface with backdrop blur. Drag down to close.',
                      style: LifeText.body.copyWith(color: LifeColors.text2),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _minutes(double y) => formatMinutes(y);

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(top: Space.section + 4, bottom: Space.md),
        child: Text(title, style: LifeText.title),
      );
}

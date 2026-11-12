import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/widgets/widgets.dart';
import '../../../data/models.dart';
import '../../../data/stores.dart';

/// 30-day mood/energy trends + tags. Computed on the device, no AI.
class JournalInsightsScreen extends ConsumerWidget {
  const JournalInsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final j = ref.watch(journalProvider);
    final learning = ref.watch(learningProvider);
    final aiMood = ref.watch(prefsProvider.select((p) => p.moodAi));
    final today = dateOnly(DateTime.now());
    final days = [for (var i = 20; i >= 0; i--) today.subtract(Duration(days: i))];
    final moods = [for (final d in days) j.moodOn(d)];
    final withData = moods.whereType<MoodEntry>().toList();
    final avgMood = withData.isEmpty ? 0.0 : withData.fold(0, (a, m) => a + m.mood) / withData.length;

    // "best days" correlation: study minutes on good vs. low days
    final good = withData.where((m) => m.mood >= 3).map((m) => learning.minutesOn(m.day)).toList();
    final low = withData.where((m) => m.mood <= 1).map((m) => learning.minutesOn(m.day)).toList();
    double avg(List<int> l) => l.isEmpty ? 0 : l.fold(0, (a, b) => a + b) / l.length;

    final tagCounts = <String, int>{};
    for (final m in j.moods) {
      for (final t in m.tags) {
        tagCounts[t] = (tagCounts[t] ?? 0) + 1;
      }
    }

    return Scaffold(
      backgroundColor: LifeColors.bg,
      body: Stack(
        children: [
          const Positioned.fill(child: AmbientBackground(mode: AmbientMode.journal)),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(Space.screen, Space.lg, Space.screen, 60),
              children: [
                Row(children: [IconGlassButton(icon: Icons.arrow_back_rounded, semanticLabel: 'Back', onPressed: () => context.pop())]),
                const SizedBox(height: Space.lg),
                Text('Last 3 weeks', style: LifeText.eyebrow),
                Text('Mood insights', style: LifeText.display),
                const SizedBox(height: Space.xl),
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Average mood', style: LifeText.eyebrow),
                      Text(withData.isEmpty ? '—' : '${avgMood.toStringAsFixed(1)} / 4', style: LifeText.statLarge),
                      const SizedBox(height: Space.lg),
                      LineAreaChart(
                        values: [for (final m in moods) (m?.mood ?? avgMood.round()).toDouble() + 1],
                        labels: [for (final d in days) d.day % 5 == 0 ? DateFormat('d').format(d) : ''],
                        color: LifeColors.rose,
                        format: (v) => ['Low', 'Meh', 'Okay', 'Good', 'Great'][(v.round() - 1).clamp(0, 4)],
                        height: 150,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Space.cardGap),
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Energy', style: LifeText.eyebrow),
                      const SizedBox(height: Space.lg),
                      GlowBarChart(
                        values: [for (final m in moods.skip(14)) (m?.energy ?? 0).toDouble()],
                        labels: [for (final d in days.skip(14)) DateFormat('E').format(d).substring(0, 1)],
                        color: LifeColors.amber,
                        highlightIndex: 6,
                        height: 130,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Space.cardGap),
                GlassCard(
                  tint: LifeColors.mint,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const IconChip(icon: LucideIcons.lightbulb, color: LifeColors.mint),
                      const SizedBox(width: Space.md),
                      Expanded(
                        child: Text(
                          good.isEmpty || low.isEmpty
                              ? 'Keep checking in — patterns show up after a couple of weeks.'
                              : 'On good days you study about ${formatMinutes(avg(good))}; on low days ${formatMinutes(avg(low))}. '
                                  'Protecting sleep and mornings seems to pay off.',
                          style: LifeText.body,
                        ),
                      ),
                    ],
                  ),
                ),
                if (tagCounts.isNotEmpty) ...[
                  const SizedBox(height: Space.cardGap),
                  GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Tags', style: LifeText.eyebrow),
                        const SizedBox(height: Space.md),
                        Wrap(
                          spacing: Space.sm,
                          runSpacing: Space.sm,
                          children: [
                            for (final e in tagCounts.entries) GlassChip(data: FilterChipData(e.key, count: e.value), selected: false),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: Space.xl),
                Row(
                  children: [
                    Icon(aiMood ? LucideIcons.sparkles : LucideIcons.lock, size: 14, color: LifeColors.text3),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: Text(
                        aiMood
                            ? 'Mood trends are shared with your assistant for reviews.'
                            : 'Computed on your phone. Mood data stays out of AI unless you turn it on in Settings.',
                        style: LifeText.caption,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

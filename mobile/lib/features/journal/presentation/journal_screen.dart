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
import '../../../data/security/app_lock.dart';
import '../../../data/stores.dart';
import '../../../shared/lock_views.dart';
import 'mood_widgets.dart';

/// Calm, personal space. See docs/UI_UX.md §9.4.
class JournalScreen extends ConsumerStatefulWidget {
  const JournalScreen({super.key});

  @override
  ConsumerState<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends ConsumerState<JournalScreen> {
  int _prompt = DateTime.now().day % Seed.prompts.length;

  @override
  Widget build(BuildContext context) {
    final locked = ref.watch(prefsProvider.select((p) => p.journalLock)) && !ref.watch(lockProvider.select((l) => l.journalUnlocked));
    if (locked) return const JournalLockedView();
    final journal = ref.watch(journalProvider);
    final today = dateOnly(DateTime.now());
    final entries = [...journal.entries]..sort((a, b) => b.day.compareTo(a.day));

    return TabScaffold(
      title: 'Journal',
      subtitle: 'A quiet place to check in',
      actions: [
        IconGlassButton(
          icon: LucideIcons.chartSpline,
          semanticLabel: 'Mood insights',
          onPressed: () => context.push(Routes.journalInsights),
        ),
      ],
      slivers: [
        const SliverSection(child: StaggeredEntry(index: 0, child: _CheckInCard())),
        SliverSection(
          child: StaggeredEntry(
            index: 1,
            child: GlassCard(
              tint: LifeColors.rose,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(LucideIcons.quote, size: 16, color: LifeColors.rose),
                      const SizedBox(width: Space.sm),
                      Expanded(child: Text('Reflection prompt', style: LifeText.eyebrow, overflow: TextOverflow.ellipsis)),
                      IconGlassButton(
                        icon: LucideIcons.refreshCw,
                        size: 34,
                        semanticLabel: 'Another prompt',
                        onPressed: () => setState(() => _prompt = (_prompt + 1) % Seed.prompts.length),
                      ),
                    ],
                  ),
                  AnimatedSwitcher(
                    duration: Motion.of(context, Motion.card),
                    child: Text(
                      Seed.prompts[_prompt],
                      key: ValueKey(_prompt),
                      style: LifeText.titleSerifItalic.copyWith(fontSize: 26),
                    ),
                  ),
                  const SizedBox(height: Space.lg),
                  GradientButton(
                    label: 'Write',
                    icon: LucideIcons.penLine,
                    compact: true,
                    onPressed: () => context.push(Routes.journalNew(prompt: Seed.prompts[_prompt])),
                  ),
                ],
              ),
            ),
          ),
        ),
        SliverSection(
          child: StaggeredEntry(
            index: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeader(title: DateFormat('MMMM').format(today)),
                GlassCard(
                  child: MoodCalendar(
                    month: today,
                    moods: journal.moods,
                    entries: journal.entries,
                    onDay: (d) => _openDay(context, d),
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverSection(
          child: StaggeredEntry(
            index: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeader(title: 'Entries', action: 'New', onAction: () => context.push(Routes.journalNew())),
                if (entries.isEmpty)
                  const GlassCard(
                    child: EmptyState(icon: LucideIcons.notebookPen, title: 'No entries yet', message: 'Your first one can be a single line.'),
                  ),
                for (final e in entries.take(10))
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.cardGap),
                    child: _EntryCard(entry: e, mood: journal.moodOn(e.day)),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _openDay(BuildContext context, DateTime day) {
    final j = ref.read(journalProvider);
    final mood = j.moodOn(day);
    final entries = j.entries.where((e) => sameDay(e.day, day)).toList();
    showGlassSheet<void>(
      context,
      title: DateFormat('EEEE, d MMMM').format(day),
      builder: (sheet) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (mood != null)
            Row(
              children: [
                MoodFace(mood: mood.mood, size: 40, selected: true),
                const SizedBox(width: Space.md),
                Text('${moodLabels[mood.mood]} · energy ${mood.energy} · motivation ${mood.motivation}', style: LifeText.body),
              ],
            )
          else
            Text('No check-in this day.', style: LifeText.caption),
          const SizedBox(height: Space.lg),
          for (final e in entries)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: _EntryCard(entry: e, mood: mood, onOpen: () => Navigator.of(sheet).pop()),
            ),
          if (entries.isEmpty)
            GradientButton(
              label: 'Write about this day',
              variant: ButtonVariant.glass,
              expand: true,
              onPressed: () {
                Navigator.of(sheet).pop();
                context.push(Routes.journalNew(day: day));
              },
            ),
        ],
      ),
    );
  }
}

class _CheckInCard extends ConsumerWidget {
  const _CheckInCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = dateOnly(DateTime.now());
    final mood = ref.watch(journalProvider.select((j) => j.moodOn(today)));
    final notifier = ref.read(journalProvider.notifier);
    MoodEntry base() => mood ?? MoodEntry(day: today, mood: 2);

    return GlassCard(
      tint: mood == null ? null : LifeColors.mood[mood.mood],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('How are you today?', style: LifeText.titleSerif.copyWith(fontSize: 26))),
              AnimatedOpacity(
                opacity: mood == null ? 0 : 1,
                duration: Motion.of(context, Motion.card),
                child: Row(
                  children: [
                    const Icon(LucideIcons.check, size: 14, color: LifeColors.mint),
                    const SizedBox(width: 3),
                    Text('Saved', style: LifeText.caption.copyWith(color: LifeColors.mint)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.lg),
          MoodSelector(value: mood?.mood, onChanged: (m) => notifier.saveMood(base().copyWith(mood: m))),
          if (mood != null) ...[
            const SizedBox(height: Space.xl),
            GlassSlider(
              label: 'Energy',
              value: mood.energy.toDouble(),
              accent: LifeColors.amber,
              onChanged: (v) => notifier.saveMood(mood.copyWith(energy: v.round())),
            ),
            GlassSlider(
              label: 'Motivation',
              value: mood.motivation.toDouble(),
              accent: LifeColors.rose,
              onChanged: (v) => notifier.saveMood(mood.copyWith(motivation: v.round())),
            ),
            const SizedBox(height: Space.md),
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                for (final t in Seed.moodTags)
                  GlassChip(
                    data: FilterChipData(t),
                    selected: mood.tags.contains(t),
                    onTap: () => notifier.saveMood(mood.copyWith(
                      tags: mood.tags.contains(t) ? (mood.tags.toList()..remove(t)) : [...mood.tags, t],
                    )),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry, this.mood, this.onOpen});

  final JournalEntry entry;
  final MoodEntry? mood;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(Space.lg),
      onTap: () {
        onOpen?.call();
        context.push(Routes.journalEntry(entry.id));
      },
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Text(DateFormat('d').format(entry.day), style: LifeText.stat.copyWith(fontSize: 22)),
              Text(DateFormat('MMM').format(entry.day), style: LifeText.caption),
            ],
          ),
          const SizedBox(width: Space.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (entry.title != null && entry.title!.isNotEmpty) Text(entry.title!, style: LifeText.bodyStrong),
                Text(
                  entry.content,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: LifeText.body.copyWith(color: LifeColors.text2),
                ),
                const SizedBox(height: Space.xs),
                Row(
                  children: [
                    Text('${entry.wordCount} words', style: LifeText.mono.copyWith(fontSize: 11)),
                    const SizedBox(width: Space.sm),
                    Icon(entry.aiAllowed ? LucideIcons.sparkles : LucideIcons.lock, size: 12, color: LifeColors.text3),
                  ],
                ),
              ],
            ),
          ),
          if (mood != null) MoodFace(mood: mood!.mood, size: 28, selected: true),
        ],
      ),
    );
  }
}

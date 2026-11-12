import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/widgets/widgets.dart';
import '../../../data/models.dart';

const moodLabels = ['Low', 'Meh', 'Okay', 'Good', 'Great'];
const moodIcons = [LucideIcons.frown, LucideIcons.annoyed, LucideIcons.meh, LucideIcons.smile, LucideIcons.laugh];

/// One mood "orb": colored when selected, glass otherwise.
class MoodFace extends StatelessWidget {
  const MoodFace({super.key, required this.mood, this.size = 50, this.selected = false});

  final int mood;
  final double size;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final d = Motion.of(context, Motion.card);
    return AnimatedContainer(
      duration: d,
      curve: Motion.standard,
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? LifeColors.mood[mood] : LifeColors.glassHigh,
        border: Border.all(color: selected ? Colors.transparent : LifeColors.glassBorder),
        boxShadow: selected && size > 40 ? LifeShadows.halo(LifeColors.mood[mood]) : null,
      ),
      child: Icon(moodIcons[mood], size: size * 0.45, color: selected ? LifeColors.onLight : LifeColors.text2),
    );
  }
}

/// Five mood orbs; the chosen one grows, the others shrink slightly. UI_UX.md §9.4.
class MoodSelector extends StatelessWidget {
  const MoodSelector({super.key, required this.value, required this.onChanged});

  final int? value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final d = Motion.of(context, Motion.card);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var i = 0; i < 5; i++)
          Semantics(
            button: true,
            selected: value == i,
            label: 'Mood ${moodLabels[i]}',
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                onChanged(i);
              },
              child: Column(
                children: [
                  AnimatedScale(
                    scale: value == i ? 1.14 : (value == null ? 1 : 0.9),
                    duration: d,
                    curve: Motion.emphasized,
                    child: MoodFace(mood: i, selected: value == i),
                  ),
                  const SizedBox(height: Space.sm),
                  AnimatedDefaultTextStyle(
                    duration: d,
                    style: LifeText.caption.copyWith(color: value == i ? LifeColors.text : LifeColors.text3),
                    child: Text(moodLabels[i]),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Month grid where each day is tinted by that day's mood; dots mark journal entries.
class MoodCalendar extends StatelessWidget {
  const MoodCalendar({super.key, required this.month, required this.moods, required this.entries, this.onDay});

  final DateTime month;
  final List<MoodEntry> moods;
  final List<JournalEntry> entries;
  final ValueChanged<DateTime>? onDay;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month, 1);
    final days = DateTime(month.year, month.month + 1, 0).day;
    final today = dateOnly(DateTime.now());
    final moodByDay = {for (final m in moods) dateOnly(m.day): m.mood};
    final entryDays = {for (final e in entries) dateOnly(e.day)};
    return Column(
      children: [
        Row(
          children: [
            for (final l in ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
              Expanded(child: Text(l, textAlign: TextAlign.center, style: LifeText.caption.copyWith(color: LifeColors.text3))),
          ],
        ),
        const SizedBox(height: Space.sm),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          children: [
            for (var i = 0; i < first.weekday - 1; i++) const SizedBox.shrink(),
            for (var d = 1; d <= days; d++)
              Builder(builder: (context) {
                final date = DateTime(month.year, month.month, d);
                final mood = moodByDay[date];
                final future = date.isAfter(today);
                return GestureDetector(
                  onTap: future ? null : () => onDay?.call(date),
                  child: Container(
                    decoration: BoxDecoration(
                      color: mood != null ? LifeColors.mood[mood].withValues(alpha: 0.85) : LifeColors.glass,
                      borderRadius: BorderRadius.circular(9),
                      border: sameDay(date, today) ? Border.all(color: Colors.white70, width: 1.2) : null,
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Text(
                          '$d',
                          style: LifeText.caption.copyWith(
                            color: mood != null
                                ? LifeColors.onLight
                                : (future ? LifeColors.text3.withValues(alpha: 0.4) : LifeColors.text2),
                          ),
                        ),
                        if (entryDays.contains(date))
                          Positioned(
                            bottom: 4,
                            child: Container(
                              width: 4,
                              height: 4,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: mood != null ? LifeColors.onLight : LifeColors.rose,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      ],
    );
  }
}

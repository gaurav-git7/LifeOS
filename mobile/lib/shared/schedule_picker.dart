import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/widgets/widgets.dart';
import '../data/schedule.dart';

/// Picks how often something repeats. Tasks offer "Once"; habits offer "N× a week".
class SchedulePicker extends StatelessWidget {
  const SchedulePicker({super.key, required this.value, required this.onChanged, this.forHabit = false});

  final Schedule value;
  final ValueChanged<Schedule> onChanged;
  final bool forHabit;

  List<(Repeat, String)> get _options => [
        if (!forHabit) (Repeat.none, 'Once'),
        (Repeat.daily, 'Every day'),
        (Repeat.weekdays, 'Weekdays'),
        (Repeat.days, 'Pick days'),
        if (forHabit) (Repeat.perWeek, '× a week'),
        (Repeat.everyN, 'Every N days'),
        if (!forHabit) (Repeat.monthly, 'Monthly'),
      ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [
            for (final (k, label) in _options)
              GlassChip(
                data: FilterChipData(label, icon: k == Repeat.none ? null : LucideIcons.repeat),
                selected: value.kind == k,
                onTap: () => onChanged(value.copyWith(
                  kind: k,
                  days: k == Repeat.days && value.days.isEmpty ? {DateTime.now().weekday} : null,
                )),
              ),
          ],
        ),
        if (value.kind == Repeat.days) ...[
          const SizedBox(height: Space.md),
          Row(
            children: [
              for (var d = 1; d <= 7; d++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Pressable(
                      semanticLabel: 'Day $d',
                      onTap: () {
                        final days = {...value.days};
                        if (!days.remove(d)) days.add(d);
                        if (days.isNotEmpty) onChanged(value.copyWith(days: days));
                      },
                      child: AnimatedContainer(
                        duration: Motion.of(context, Motion.check),
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: value.days.contains(d) ? LifeColors.iris : LifeColors.glassHigh,
                          borderRadius: Radii.rPill,
                        ),
                        child: Text(
                          Schedule.dayLetters[d - 1],
                          style: LifeText.label.copyWith(color: value.days.contains(d) ? Colors.white : LifeColors.text2),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
        if (value.kind == Repeat.perWeek)
          _Stepper(
            label: '${value.perWeek} times a week, any days',
            value: value.perWeek,
            min: 1,
            max: 6,
            onChanged: (v) => onChanged(value.copyWith(perWeek: v)),
          ),
        if (value.kind == Repeat.everyN)
          _Stepper(
            label: 'Every ${value.interval} days',
            value: value.interval,
            min: 2,
            max: 30,
            onChanged: (v) => onChanged(value.copyWith(interval: v)),
          ),
      ],
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.label, required this.value, required this.min, required this.max, required this.onChanged});

  final String label;
  final int value, min, max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: Space.md),
        child: Row(
          children: [
            Expanded(child: Text(label, style: LifeText.body)),
            IconGlassButton(
              icon: LucideIcons.minus,
              size: 36,
              semanticLabel: 'Less',
              onPressed: value > min ? () => onChanged(value - 1) : null,
            ),
            const SizedBox(width: Space.sm),
            IconGlassButton(
              icon: LucideIcons.plus,
              size: 36,
              semanticLabel: 'More',
              onPressed: value < max ? () => onChanged(value + 1) : null,
            ),
          ],
        ),
      );
}

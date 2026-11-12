import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/widgets/widgets.dart';
import '../data/models.dart';

/// Horizontal week of days. Today has a white ring; the selected day is solid white.
class WeekStrip extends StatelessWidget {
  const WeekStrip({
    super.key,
    required this.weekStart,
    required this.selected,
    required this.onSelected,
    this.markers = const {},
  });

  final DateTime weekStart;
  final DateTime selected;
  final ValueChanged<DateTime> onSelected;

  /// date-only → dot color(s) under the day
  final Map<DateTime, List<Color>> markers;

  @override
  Widget build(BuildContext context) {
    final today = dateOnly(DateTime.now());
    final d = Motion.of(context, Motion.check);
    return Row(
      children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Builder(builder: (context) {
              final day = weekStart.add(Duration(days: i));
              final isSel = sameDay(day, selected);
              final isToday = sameDay(day, today);
              final dots = markers[dateOnly(day)] ?? const [];
              return Pressable(
                onTap: () => onSelected(day),
                scale: 0.92,
                child: AnimatedContainer(
                  duration: d,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  padding: const EdgeInsets.symmetric(vertical: Space.sm),
                  decoration: BoxDecoration(
                    color: isSel ? Colors.white : Colors.transparent,
                    borderRadius: Radii.rMd,
                    border: Border.all(color: isToday && !isSel ? Colors.white54 : Colors.transparent),
                  ),
                  child: Column(
                    children: [
                      Text(
                        DateFormat('E').format(day).substring(0, 2),
                        style: LifeText.caption.copyWith(color: isSel ? LifeColors.onLight.withValues(alpha: 0.6) : LifeColors.text3),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${day.day}',
                        style: LifeText.title.copyWith(color: isSel ? LifeColors.onLight : LifeColors.text),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: 5,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (final c in dots.take(3))
                              Container(
                                width: 5,
                                height: 5,
                                margin: const EdgeInsets.symmetric(horizontal: 1),
                                decoration: BoxDecoration(shape: BoxShape.circle, color: isSel ? LifeColors.onLight : c),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
      ],
    );
  }
}

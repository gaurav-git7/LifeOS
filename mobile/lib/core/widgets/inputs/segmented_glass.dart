import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../motion/motion.dart';
import '../../theme/app_theme.dart';
import '../glass/glass_card.dart';

/// Glass segmented control with a sliding lighter-glass capsule (iOS style).
class SegmentedGlass extends StatelessWidget {
  const SegmentedGlass({
    super.key,
    required this.segments,
    required this.index,
    required this.onChanged,
    this.badges = const {},
  });

  final List<String> segments;
  final int index;
  final ValueChanged<int> onChanged;

  /// segment index → count
  final Map<int, int> badges;

  @override
  Widget build(BuildContext context) {
    final duration = Motion.of(context, Motion.nav);
    return GlassSurface(
      radius: Radii.pill,
      child: SizedBox(
        height: 42,
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: LayoutBuilder(
            builder: (context, c) {
              final w = c.maxWidth / segments.length;
              return Stack(
                children: [
                  AnimatedPositioned(
                    duration: duration,
                    curve: Motion.emphasized,
                    left: w * index,
                    top: 0,
                    bottom: 0,
                    width: w,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(color: LifeColors.glassActive, borderRadius: Radii.rPill),
                      child: CustomPaint(painter: GlassRimPainter(radius: Radii.pill)),
                    ),
                  ),
                  Row(
                    children: [
                      for (var i = 0; i < segments.length; i++)
                        SizedBox(
                          width: w,
                          child: Semantics(
                            button: true,
                            selected: i == index,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                if (i != index) HapticFeedback.selectionClick();
                                onChanged(i);
                              },
                              child: Center(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: AnimatedDefaultTextStyle(
                                        duration: duration,
                                        style: LifeText.label.copyWith(
                                          color: i == index ? LifeColors.text : LifeColors.text2,
                                          fontWeight: i == index ? FontWeight.w600 : FontWeight.w500,
                                        ),
                                        child: Text(segments[i], maxLines: 1, overflow: TextOverflow.ellipsis),
                                      ),
                                    ),
                                    if ((badges[i] ?? 0) > 0) ...[
                                      const SizedBox(width: 5),
                                      _CountBadge(badges[i]!),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge(this.count);

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: const BoxDecoration(gradient: LifeGradients.aiLinear, borderRadius: Radii.rPill),
      child: Text('$count', style: LifeText.mono.copyWith(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w600)),
    );
  }
}

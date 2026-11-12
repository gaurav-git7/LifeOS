import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../motion/motion.dart';
import '../../theme/app_theme.dart';

/// Thin rounded progress bar. Used for XP, goals, skills and roadmaps.
class GlowBar extends StatelessWidget {
  const GlowBar({
    super.key,
    required this.value,
    this.height = 6,
    this.color = LifeColors.iris,
    this.gradient,
  });

  /// 0..1
  final double value;
  final double height;
  final Color color;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.clamp(0, 1)),
      duration: Motion.of(context, Motion.ring),
      curve: Motion.standard,
      builder: (context, v, _) => LayoutBuilder(
        builder: (context, c) => Container(
          height: height,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: Radii.rPill),
          alignment: Alignment.centerLeft,
          child: Container(
            width: c.maxWidth * v,
            decoration: BoxDecoration(
              gradient: gradient ?? LifeGradients.accent(color),
              borderRadius: Radii.rPill,
            ),
          ),
        ),
      ),
    );
  }
}

/// Level + XP progress. See docs/UI_UX.md §10.
class XpBar extends StatelessWidget {
  const XpBar({
    super.key,
    required this.level,
    required this.xp,
    required this.xpForNext,
    this.showLabels = true,
  });

  final int level;
  final int xp;
  final int xpForNext;
  final bool showLabels;

  @override
  Widget build(BuildContext context) {
    final f = NumberFormat.decimalPattern();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showLabels) ...[
          Row(
            children: [
              Text('Level $level', style: LifeText.label),
              const Spacer(),
              Text('${f.format(xp)} / ${f.format(xpForNext)} XP', style: LifeText.mono),
            ],
          ),
          const SizedBox(height: Space.sm),
        ],
        GlowBar(
          value: xpForNext == 0 ? 0 : xp / xpForNext,
          gradient: const LinearGradient(colors: [LifeColors.iris, LifeColors.rose]),
          color: LifeColors.iris,
        ),
      ],
    );
  }
}

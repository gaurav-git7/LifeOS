import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../glass/glass_card.dart';
import 'animated_counter.dart';

/// Small stat tile: colored icon chip, label, counting number, trend.
class AnimatedStatCard extends StatelessWidget {
  const AnimatedStatCard({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.accent = LifeColors.iris,
    this.suffix = '',
    this.format,
    this.trend,
  });

  final String label;
  final num value;
  final IconData? icon;
  final Color accent;
  final String suffix;
  final String Function(double v)? format;

  /// Change vs previous period, e.g. 0.18 → "+18%".
  final double? trend;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                IconChip(icon: icon!, color: accent),
                const SizedBox(width: Space.sm),
              ],
              Expanded(child: Text(label, style: LifeText.eyebrow, overflow: TextOverflow.ellipsis)),
            ],
          ),
          const SizedBox(height: Space.md),
          AnimatedCounter(value: value, suffix: suffix, format: format),
          if (trend != null) ...[
            const SizedBox(height: 2),
            TrendLabel(trend: trend!),
          ],
        ],
      ),
    );
  }
}

/// Rounded-square icon on a soft tint of its color.
class IconChip extends StatelessWidget {
  const IconChip({super.key, required this.icon, required this.color, this.size = 28});

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(icon, size: size * 0.55, color: color),
    );
  }
}

class TrendLabel extends StatelessWidget {
  const TrendLabel({super.key, required this.trend});

  final double trend;

  @override
  Widget build(BuildContext context) {
    final up = trend >= 0;
    return Text(
      '${up ? '+' : '−'}${(trend.abs() * 100).round()}% vs last week',
      style: LifeText.mono.copyWith(color: up ? LifeColors.mint : LifeColors.amber, fontSize: 11),
    );
  }
}

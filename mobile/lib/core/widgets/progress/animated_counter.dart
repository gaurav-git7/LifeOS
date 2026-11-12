import 'package:flutter/material.dart';

import '../../motion/motion.dart';
import '../../theme/app_theme.dart';

/// Number that counts up (or down) to [value]. Uses tabular figures so the
/// width doesn't jitter while counting.
class AnimatedCounter extends StatelessWidget {
  const AnimatedCounter({
    super.key,
    required this.value,
    this.style,
    this.prefix = '',
    this.suffix = '',
    this.decimals = 0,
    this.format,
  });

  final num value;
  final TextStyle? style;
  final String prefix;
  final String suffix;
  final int decimals;

  /// Custom formatter (e.g. minutes → "2h 10m").
  final String Function(double v)? format;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: Motion.of(context, Motion.countUp),
      curve: Motion.standard,
      builder: (context, v, _) {
        final text = format?.call(v) ?? v.toStringAsFixed(decimals);
        return Text('$prefix$text$suffix', style: style ?? LifeText.stat);
      },
    );
  }
}

/// "2h 10m" style formatter for minute counters.
String formatMinutes(double minutes) {
  final m = minutes.round();
  if (m < 60) return '${m}m';
  final h = m ~/ 60;
  final rest = m % 60;
  return rest == 0 ? '${h}h' : '${h}h ${rest}m';
}

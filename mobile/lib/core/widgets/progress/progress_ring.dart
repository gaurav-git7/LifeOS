import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../motion/motion.dart';
import '../../theme/app_theme.dart';

@immutable
class RingData {
  const RingData(this.value, this.color, {this.label});

  /// 0..1
  final double value;
  final Color color;
  final String? label;
}

/// Concentric activity rings (outer → inner), Apple Fitness style.
/// Each ring animates from its previous value. See docs/UI_UX.md §9.1.
class ActivityRings extends StatelessWidget {
  const ActivityRings({
    super.key,
    required this.rings,
    this.size = 132,
    this.stroke = 13,
    this.gap = 4,
    this.child,
    this.semanticLabel,
  });

  final List<RingData> rings;
  final double size;
  final double stroke;
  final double gap;
  final Widget? child;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel ??
          rings.map((r) => '${r.label ?? ''} ${(r.value * 100).round()} percent').join(', '),
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            for (var i = 0; i < rings.length; i++)
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: rings[i].value.clamp(0, 1)),
                duration: Motion.of(context, Motion.ring + Motion.stagger * (i * 3)),
                curve: Motion.standard,
                builder: (context, v, _) => CustomPaint(
                  painter: _RingPainter(
                    value: v,
                    color: rings[i].color,
                    stroke: stroke,
                    inset: i * (stroke + gap),
                  ),
                ),
              ),
            if (child != null) Center(child: child),
          ],
        ),
      ),
    );
  }
}

/// Single ring. Thin wrapper over [ActivityRings].
class AnimatedProgressRing extends StatelessWidget {
  const AnimatedProgressRing({
    super.key,
    required this.value,
    this.color = LifeColors.iris,
    this.size = 160,
    this.stroke = 12,
    this.child,
    this.semanticLabel,
  });

  final double value;
  final Color color;
  final double size;
  final double stroke;
  final Widget? child;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => ActivityRings(
        rings: [RingData(value, color)],
        size: size,
        stroke: stroke,
        semanticLabel: semanticLabel,
        child: child,
      );
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.value, required this.color, required this.stroke, required this.inset});

  final double value;
  final Color color;
  final double stroke;
  final double inset;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = (size.shortestSide - stroke) / 2 - inset;
    if (r <= 0) return;
    final rect = Rect.fromCircle(center: c, radius: r);

    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = color.withValues(alpha: 0.18),
    );
    if (value <= 0) return;

    const start = -math.pi / 2;
    final sweep = math.pi * 2 * value;
    final light = Color.lerp(color, Colors.white, 0.3)!;
    canvas.drawArc(
      rect,
      start,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          colors: [color, light],
          stops: [0, value.clamp(0.01, 1)],
          transform: const GradientRotation(start),
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value || old.color != color;
}

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../motion/motion.dart';
import '../../theme/app_theme.dart';

/// One-shot celebratory burst. Increment [trigger] to play it.
/// Used for milestones only — never more than once per action.
class GlowBurst extends StatefulWidget {
  const GlowBurst({
    super.key,
    required this.trigger,
    this.size = 160,
    this.color = Colors.white,
  });

  final int trigger;
  final double size;
  final Color color;

  @override
  State<GlowBurst> createState() => _GlowBurstState();
}

class _GlowBurstState extends State<GlowBurst> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: Motion.burst);

  @override
  void didUpdateWidget(GlowBurst oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trigger != oldWidget.trigger && !MotionScope.reducedOf(context)) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox.square(
        dimension: widget.size,
        child: CustomPaint(painter: _BurstPainter(_c, widget.color)),
      ),
    );
  }
}

class _BurstPainter extends CustomPainter {
  _BurstPainter(this.t, this.color) : super(repaint: t);

  final Animation<double> t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (t.value == 0 || t.value == 1) return;
    final c = size.center(Offset.zero);
    final p = Curves.easeOutCubic.transform(t.value);
    final fade = 1 - t.value;
    final maxR = size.shortestSide / 2;

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = color.withValues(alpha: 0.6 * fade);
    canvas.drawCircle(c, maxR * 0.4 + maxR * 0.6 * p, ring);

    final dot = Paint();
    for (var i = 0; i < 12; i++) {
      final a = i / 12 * math.pi * 2;
      final r = maxR * 0.3 + maxR * 0.65 * p;
      final pos = c + Offset(math.cos(a), math.sin(a)) * r;
      dot.color = (i.isEven ? color : LifeColors.rose).withValues(alpha: fade);
      canvas.drawCircle(pos, 2.5 * fade + 0.5, dot);
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => false;
}

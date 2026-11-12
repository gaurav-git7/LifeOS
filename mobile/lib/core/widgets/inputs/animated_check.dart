import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../motion/motion.dart';
import '../../theme/app_theme.dart';

/// Round checkbox that morphs: outline → filled circle → check path draws.
/// See docs/UI_UX.md §7.2 (task completion).
class AnimatedCheck extends StatefulWidget {
  const AnimatedCheck({
    super.key,
    required this.checked,
    this.onChanged,
    this.color = LifeColors.iris,
    this.size = 24,
  });

  final bool checked;
  final ValueChanged<bool>? onChanged;
  final Color color;
  final double size;

  @override
  State<AnimatedCheck> createState() => _AnimatedCheckState();
}

class _AnimatedCheckState extends State<AnimatedCheck> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Motion.check,
    value: widget.checked ? 1 : 0,
  );

  @override
  void didUpdateWidget(AnimatedCheck oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.checked != oldWidget.checked) {
      if (MotionScope.reducedOf(context)) {
        _c.value = widget.checked ? 1 : 0;
      } else {
        widget.checked ? _c.forward() : _c.reverse();
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      checked: widget.checked,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onChanged == null
            ? null
            : () {
                HapticFeedback.lightImpact();
                widget.onChanged!(!widget.checked);
              },
        child: SizedBox.square(
          dimension: Sizes.touch,
          child: Center(
            child: SizedBox.square(
              dimension: widget.size,
              child: CustomPaint(painter: _CheckPainter(_c, widget.color)),
            ),
          ),
        ),
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  _CheckPainter(this.t, this.color) : super(repaint: t);

  final Animation<double> t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final fill = Curves.easeOutCubic.transform((t.value / 0.6).clamp(0, 1));
    final draw = Curves.easeOutCubic.transform(((t.value - 0.4) / 0.6).clamp(0, 1));

    // outline
    canvas.drawCircle(
      c,
      r - 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = Color.lerp(LifeColors.text3, color, fill)!,
    );

    // fill grows from the center
    if (fill > 0) {
      canvas.drawCircle(c, (r - 1) * fill, Paint()..color = color);
      canvas.drawCircle(
        c,
        r + 3,
        Paint()..color = color.withValues(alpha: 0.18 * fill),
      );
    }

    // check path draws
    if (draw > 0) {
      final path = Path()
        ..moveTo(size.width * 0.28, size.height * 0.52)
        ..lineTo(size.width * 0.44, size.height * 0.67)
        ..lineTo(size.width * 0.73, size.height * 0.36);
      final metric = path.computeMetrics().first;
      final partial = metric.extractPath(0, metric.length * draw);
      canvas.drawPath(
        partial,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.color != color;
}

import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../motion/motion.dart';
import '../../theme/app_theme.dart';

enum AiState { idle, thinking }

/// The assistant's mark: a flat iridescent disc with a slowly turning
/// spectrum and a white spark. No 3D gloss. See docs/UI_UX.md §1.
class AiMark extends StatefulWidget {
  const AiMark({super.key, this.size = 28, this.state = AiState.idle, this.showSpark = true});

  final double size;
  final AiState state;
  final bool showSpark;

  @override
  State<AiMark> createState() => _AiMarkState();
}

class _AiMarkState extends State<AiMark> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 8));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MotionScope.reducedOf(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final big = s >= 64;
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: s,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final speed = widget.state == AiState.thinking ? 3 : 1;
            final angle = _c.value * math.pi * 2 * speed;
            final disc = DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(
                  colors: LifeGradients.aiColors,
                  transform: GradientRotation(angle),
                ),
              ),
            );
            return Stack(
              alignment: Alignment.center,
              children: [
                if (big)
                  // soft aura behind large marks
                  ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: s * 0.22, sigmaY: s * 0.22),
                    child: Opacity(opacity: 0.7, child: SizedBox.square(dimension: s * 0.9, child: disc)),
                  ),
                SizedBox.square(dimension: big ? s * 0.78 : s, child: disc),
                // inner frosted face so it reads as an object, not a pie chart
                Container(
                  width: (big ? s * 0.78 : s) * 0.72,
                  height: (big ? s * 0.78 : s) * 0.72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.18),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 0.8),
                  ),
                ),
                if (widget.showSpark)
                  Icon(LucideIcons.sparkle, size: s * (big ? 0.3 : 0.46), color: Colors.white),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Animated iridescent border for AI surfaces (insight card, AI input,
/// proposals). The one place the app uses glow.
class AiGlowBorder extends StatefulWidget {
  const AiGlowBorder({
    super.key,
    required this.child,
    this.radius = Radii.lg,
    this.width = 1.5,
    this.glow = true,
  });

  final Widget child;
  final double radius;
  final double width;
  final bool glow;

  @override
  State<AiGlowBorder> createState() => _AiGlowBorderState();
}

class _AiGlowBorderState extends State<AiGlowBorder> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 6));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MotionScope.reducedOf(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _AiBorderPainter(_c, widget.radius, widget.width, widget.glow),
      child: widget.child,
    );
  }
}

class _AiBorderPainter extends CustomPainter {
  _AiBorderPainter(this.t, this.radius, this.width, this.glow) : super(repaint: t);

  final Animation<double> t;
  final double radius;
  final double width;
  final bool glow;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(width / 2);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final shader = SweepGradient(
      colors: LifeGradients.aiColors,
      transform: GradientRotation(t.value * math.pi * 2),
    ).createShader(rect);

    if (glow) {
      canvas.drawRRect(
        rrect,
        Paint()
          ..shader = shader
          ..style = PaintingStyle.stroke
          ..strokeWidth = width * 4
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10)
          ..color = Colors.white.withValues(alpha: 0.35),
      );
    }
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = shader
        ..style = PaintingStyle.stroke
        ..strokeWidth = width,
    );
  }

  @override
  bool shouldRepaint(_AiBorderPainter old) => false;
}

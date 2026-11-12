import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../motion/motion.dart';
import '../../theme/app_theme.dart';

/// Background palette per screen. See docs/UI_UX.md §6.
enum AmbientMode { home, plan, growth, journal, assistant }

/// Four mesh blob colors + how strongly the lower page is darkened.
@immutable
class MeshPalette {
  const MeshPalette(this.colors, {this.strength = 1});

  final List<Color> colors;
  final double strength;

  static const _palettes = {
    AmbientMode.home: MeshPalette([LifeColors.iris, LifeColors.sky, LifeColors.rose, Color(0xFF3D2AE0)]),
    AmbientMode.plan: MeshPalette([LifeColors.sky, Color(0xFF3A4FD8), LifeColors.iris, Color(0xFF1E6F8F)], strength: 0.75),
    AmbientMode.growth: MeshPalette([LifeColors.mint, LifeColors.sky, Color(0xFF2E7D6B), LifeColors.iris], strength: 0.85),
    AmbientMode.journal: MeshPalette([LifeColors.rose, LifeColors.coral, LifeColors.amber, Color(0xFF7A3FD1)], strength: 0.8),
    AmbientMode.assistant: MeshPalette([LifeColors.iris, LifeColors.rose, LifeColors.sky, LifeColors.mint]),
  };

  static MeshPalette of(AmbientMode mode) => _palettes[mode]!;

  static MeshPalette lerp(MeshPalette a, MeshPalette b, double t) => MeshPalette(
        [for (var i = 0; i < 4; i++) Color.lerp(a.colors[i], b.colors[i], t)!],
        strength: ui.lerpDouble(a.strength, b.strength, t)!,
      );
}

class _MeshTween extends Tween<MeshPalette> {
  _MeshTween({super.begin, super.end});

  @override
  MeshPalette lerp(double t) => MeshPalette.lerp(begin!, end!, t);
}

/// Slowly morphing mesh gradient + film grain. Switching [mode] blends the
/// colors smoothly instead of swapping backgrounds.
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({super.key, required this.mode});

  final AmbientMode mode;

  @override
  Widget build(BuildContext context) {
    final intensity = MotionScope.ambientOf(context);
    final target = MeshPalette.of(mode);
    return RepaintBoundary(
      child: ColoredBox(
        color: LifeColors.bg,
        child: Stack(
          fit: StackFit.expand,
          children: [
            TweenAnimationBuilder<MeshPalette>(
              tween: _MeshTween(begin: target, end: target),
              duration: const Duration(milliseconds: 700),
              curve: Motion.inOut,
              builder: (context, palette, _) => _MeshLayer(palette: palette, intensity: intensity),
            ),
            const RepaintBoundary(child: CustomPaint(painter: _GrainPainter())),
          ],
        ),
      ),
    );
  }
}

class _MeshLayer extends StatefulWidget {
  const _MeshLayer({required this.palette, required this.intensity});

  final MeshPalette palette;
  final AmbientIntensity intensity;

  @override
  State<_MeshLayer> createState() => _MeshLayerState();
}

class _MeshLayerState extends State<_MeshLayer> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 24));

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_MeshLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.intensity != widget.intensity) _sync();
  }

  void _sync() {
    if (widget.intensity == AmbientIntensity.off) {
      _c
        ..stop()
        ..value = 0.2;
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
      painter: _MeshPainter(
        t: _c,
        palette: widget.palette,
        strength: widget.palette.strength * (widget.intensity == AmbientIntensity.low ? 0.7 : 1),
      ),
      size: Size.infinite,
    );
  }
}

class _MeshPainter extends CustomPainter {
  _MeshPainter({required this.t, required this.palette, required this.strength}) : super(repaint: t);

  final Animation<double> t;
  final MeshPalette palette;
  final double strength;
  final Paint _p = Paint();

  // Each blob drifts on its own slow Lissajous path (relative coords).
  static const _paths = [
    (0.15, 0.10, 0.12, 0.06, 1.0, 0.0, 0.95),
    (0.90, 0.05, 0.10, 0.08, 1.0, 1.7, 0.85),
    (0.70, 0.42, 0.14, 0.07, 2.0, 3.1, 0.80),
    (0.10, 0.62, 0.10, 0.10, 1.0, 4.4, 0.75),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final phi = t.value * math.pi * 2;
    final w = size.width;
    final h = size.height;

    for (var i = 0; i < 4; i++) {
      final (x, y, ax, ay, f, ph, r) = _paths[i];
      final c = Offset(
        (x + ax * math.sin(phi * f + ph)) * w,
        (y + ay * math.cos(phi + ph)) * h,
      );
      final radius = r * w * (1 + 0.08 * math.sin(phi * 2 + ph));
      final color = palette.colors[i];
      _p.shader = RadialGradient(
        colors: [
          color.withValues(alpha: 0.62 * strength),
          color.withValues(alpha: 0.22 * strength),
          color.withValues(alpha: 0),
        ],
        stops: const [0, 0.45, 1],
      ).createShader(Rect.fromCircle(center: c, radius: radius));
      canvas.drawCircle(c, radius, _p);
    }

    // Readability veil: colorful top, deep bottom where lists live.
    final rect = Offset.zero & size;
    _p.shader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0x1A07070B), Color(0x6607070B), Color(0xB307070B)],
      stops: [0, 0.5, 0.9],
    ).createShader(rect);
    canvas.drawRect(rect, _p);
    _p.shader = null;
  }

  @override
  bool shouldRepaint(_MeshPainter old) => old.palette != palette || old.strength != strength;
}

/// Static film grain — adds the tactile, premium texture flat gradients lack.
class _GrainPainter extends CustomPainter {
  const _GrainPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(3);
    final count = (size.width * size.height / 90).clamp(0, 12000).toInt();
    final light = <Offset>[];
    final dark = <Offset>[];
    for (var i = 0; i < count; i++) {
      final o = Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height);
      (i.isEven ? light : dark).add(o);
    }
    canvas.drawPoints(ui.PointMode.points, light, Paint()..color = const Color(0x0DFFFFFF)..strokeWidth = 1);
    canvas.drawPoints(ui.PointMode.points, dark, Paint()..color = const Color(0x14000000)..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(_GrainPainter old) => false;
}

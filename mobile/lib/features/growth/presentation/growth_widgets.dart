import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/widgets/widgets.dart';
import '../../../data/models.dart';

/// Skill profile radar (top skills by level). UI_UX.md §11.2.
class SkillRadar extends StatelessWidget {
  const SkillRadar({super.key, required this.skills, this.height = 230});

  final List<Skill> skills;
  final double height;

  @override
  Widget build(BuildContext context) {
    final top = skills.take(6).toList();
    if (top.length < 3) return const SizedBox.shrink();
    return SizedBox(
      height: height,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Motion.of(context, Motion.chart),
        curve: Motion.standard,
        builder: (context, t, _) => RadarChart(
          RadarChartData(
            radarShape: RadarShape.polygon,
            tickCount: 4,
            ticksTextStyle: const TextStyle(color: Colors.transparent, fontSize: 1),
            tickBorderData: const BorderSide(color: LifeColors.grid),
            gridBorderData: const BorderSide(color: LifeColors.hairline),
            radarBorderData: const BorderSide(color: LifeColors.hairline),
            radarBackgroundColor: Colors.transparent,
            borderData: FlBorderData(show: false),
            titlePositionPercentageOffset: 0.12,
            titleTextStyle: LifeText.caption.copyWith(color: LifeColors.text2),
            getTitle: (i, _) => RadarChartTitle(text: top[i].name),
            dataSets: [
              RadarDataSet(
                dataEntries: [for (final s in top) RadarEntry(value: s.target.toDouble())],
                fillColor: Colors.transparent,
                borderColor: LifeColors.text3.withValues(alpha: 0.5),
                borderWidth: 1,
                entryRadius: 0,
              ),
              RadarDataSet(
                dataEntries: [for (final s in top) RadarEntry(value: math.max(0.2, s.level * t))],
                fillColor: LifeColors.mint.withValues(alpha: 0.22),
                borderColor: LifeColors.mint,
                borderWidth: 2,
                entryRadius: 3,
              ),
              // fixed scale anchor
              RadarDataSet(
                dataEntries: [for (final _ in top) const RadarEntry(value: 5)],
                fillColor: Colors.transparent,
                borderColor: Colors.transparent,
                borderWidth: 0,
                entryRadius: 0,
              ),
            ],
          ),
          duration: Duration.zero,
        ),
      ),
    );
  }
}

/// Tiny trend line for skill cards.
class Sparkline extends StatelessWidget {
  const Sparkline({super.key, required this.values, required this.color, this.width = 64, this.height = 24});

  final List<int> values;
  final Color color;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) =>
      SizedBox(width: width, height: height, child: CustomPaint(painter: _SparkPainter(values, color)));
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.values, this.color);

  final List<int> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final maxV = values.reduce(math.max).clamp(1, 1 << 30).toDouble();
    final dx = size.width / (values.length - 1);
    final pts = [
      for (var i = 0; i < values.length; i++) Offset(i * dx, size.height - values[i] / maxV * (size.height - 3) - 1.5),
    ];
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      final c = Offset((pts[i - 1].dx + pts[i].dx) / 2, pts[i - 1].dy);
      final c2 = Offset((pts[i - 1].dx + pts[i].dx) / 2, pts[i].dy);
      path.cubicTo(c.dx, c.dy, c2.dx, c2.dy, pts[i].dx, pts[i].dy);
    }
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()..shader = LifeGradients.chartFill(color).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
    canvas.drawCircle(pts.last, 2.5, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_SparkPainter old) => old.values != values || old.color != color;
}

/// Five segments for skill level 1..5.
class LevelSegments extends StatelessWidget {
  const LevelSegments({super.key, required this.level, required this.target, required this.color});

  final int level;
  final int target;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 1; i <= 5; i++)
          Expanded(
            child: Container(
              height: 6,
              margin: EdgeInsets.only(right: i < 5 ? 4 : 0),
              decoration: BoxDecoration(
                borderRadius: Radii.rPill,
                color: i <= level ? color : (i <= target ? color.withValues(alpha: 0.18) : LifeColors.track),
              ),
            ),
          ),
      ],
    );
  }
}

const levelNames = ['Aware', 'Beginner', 'Comfortable', 'Proficient', 'Expert'];

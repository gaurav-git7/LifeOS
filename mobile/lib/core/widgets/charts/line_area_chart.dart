import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../motion/motion.dart';
import '../../theme/app_theme.dart';
import 'chart_theme.dart';

/// Smooth luminous line with a gradient area. Draws itself left → right
/// on first build. See docs/UI_UX.md §11.
class LineAreaChart extends StatelessWidget {
  const LineAreaChart({
    super.key,
    required this.values,
    required this.labels,
    this.color = LifeColors.iris,
    this.height = 160,
    this.format,
    this.minY = 0,
  });

  final List<double> values;
  final List<String> labels;
  final Color color;
  final double height;
  final double minY;
  final String Function(double y)? format;

  @override
  Widget build(BuildContext context) {
    final spots = [for (var i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i])];
    final maxY = values.fold<double>(0, (a, b) => b > a ? b : a) * 1.2 + 0.001;

    LineChartBarData line({required double width, required double alpha, bool area = false}) =>
        LineChartBarData(
          spots: spots,
          isCurved: true,
          curveSmoothness: 0.35,
          preventCurveOverShooting: true,
          color: color.withValues(alpha: alpha),
          barWidth: width,
          isStrokeCapRound: true,
          belowBarData: BarAreaData(show: area, gradient: LifeGradients.chartFill(color)),
          dotData: FlDotData(
            show: area,
            checkToShowDot: (spot, _) => spot.x == spots.last.x,
            getDotPainter: (_, _, _, _) => FlDotCirclePainter(
              radius: 4,
              color: Colors.white,
              strokeWidth: 5,
              strokeColor: color.withValues(alpha: 0.35),
            ),
          ),
        );

    final chart = LineChart(
      LineChartData(
        minY: minY,
        maxY: maxY,
        minX: 0,
        maxX: (values.length - 1).toDouble(),
        gridData: ChartStyle.grid(interval: maxY / 3),
        titlesData: ChartStyle.bottomTitles(labels),
        borderData: ChartStyle.noBorder,
        lineTouchData: LineTouchData(
          touchTooltipData: lineTooltip(format ?? (y) => y.toStringAsFixed(0)),
          getTouchedSpotIndicator: (bar, idx) => [
            for (final _ in idx)
              TouchedSpotIndicatorData(
                FlLine(color: color.withValues(alpha: 0.3), strokeWidth: 1, dashArray: [3, 3]),
                FlDotData(
                  getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                    radius: 4,
                    color: Colors.white,
                    strokeWidth: 4,
                    strokeColor: color.withValues(alpha: 0.4),
                  ),
                ),
              ),
          ],
        ),
        lineBarsData: [
          line(width: 2, alpha: 1, area: true),
        ],
      ),
      duration: Duration.zero,
    );

    return SizedBox(
      height: height,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Motion.of(context, Motion.chart),
        curve: Motion.standard,
        builder: (context, p, child) => ClipRect(
          clipper: _RevealClipper(p),
          child: child,
        ),
        child: chart,
      ),
    );
  }
}

class _RevealClipper extends CustomClipper<Rect> {
  _RevealClipper(this.p);

  final double p;

  @override
  Rect getClip(Size size) => Rect.fromLTWH(-8, -8, (size.width + 16) * p, size.height + 16);

  @override
  bool shouldReclip(_RevealClipper old) => old.p != p;
}

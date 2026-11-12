import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../motion/motion.dart';
import '../../theme/app_theme.dart';
import 'chart_theme.dart';

/// Rounded gradient bars that rise from the bottom (30 ms stagger).
class GlowBarChart extends StatelessWidget {
  const GlowBarChart({
    super.key,
    required this.values,
    required this.labels,
    this.color = LifeColors.mint,
    this.highlightIndex,
    this.height = 160,
    this.format,
  });

  final List<double> values;
  final List<String> labels;
  final Color color;

  /// Bar drawn at full brightness (e.g. today). Others are dimmer.
  final int? highlightIndex;
  final double height;
  final String Function(double y)? format;

  @override
  Widget build(BuildContext context) {
    final maxY = values.fold<double>(0, (a, b) => b > a ? b : a) * 1.15 + 0.001;
    final n = values.length;
    final total = Motion.chart + Motion.stagger * n;

    return SizedBox(
      height: height,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Motion.of(context, total),
        builder: (context, p, _) {
          return BarChart(
            BarChartData(
              maxY: maxY,
              minY: 0,
              alignment: BarChartAlignment.spaceAround,
              gridData: ChartStyle.grid(interval: maxY / 3),
              titlesData: ChartStyle.bottomTitles(labels),
              borderData: ChartStyle.noBorder,
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => LifeColors.surfaceHigh,
                  tooltipBorderRadius: Radii.rSm,
                  getTooltipItem: (group, _, rod, _) => BarTooltipItem(
                    format?.call(values[group.x]) ?? values[group.x].toStringAsFixed(0),
                    LifeText.label.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              barGroups: [
                for (var i = 0; i < n; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: values[i] * _stagger(p, i, n),
                        width: 14,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(6), bottom: Radius.circular(3)),
                        gradient: LifeGradients.bar(
                          (highlightIndex == null || highlightIndex == i)
                              ? color
                              : color.withValues(alpha: 0.45),
                        ),
                        backDrawRodData: BackgroundBarChartRodData(
                          show: true,
                          toY: maxY,
                          color: color.withValues(alpha: 0.07),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            duration: Duration.zero,
          );
        },
      ),
    );
  }

  /// Each bar starts slightly later than the previous one.
  static double _stagger(double p, int i, int n) {
    final start = i / (n + 8);
    final local = ((p - start) / (1 - start)).clamp(0.0, 1.0);
    return Curves.easeOutCubic.transform(local);
  }
}

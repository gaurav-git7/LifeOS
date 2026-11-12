import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Shared chart styling. See docs/UI_UX.md §11.1.
abstract final class ChartStyle {
  static FlGridData grid({double? interval}) => FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: interval,
        getDrawingHorizontalLine: (_) => const FlLine(color: LifeColors.grid, strokeWidth: 1),
      );

  static final axisLabel = LifeText.mono.copyWith(color: LifeColors.text3, fontSize: 11);

  static FlTitlesData bottomTitles(List<String> labels, {bool showLeft = false}) => FlTitlesData(
        topTitles: const AxisTitles(),
        rightTitles: const AxisTitles(),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: showLeft,
            reservedSize: 28,
            getTitlesWidget: (v, meta) => SideTitleWidget(
              meta: meta,
              child: Text(meta.formattedValue, style: axisLabel),
            ),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 24,
            interval: 1,
            getTitlesWidget: (v, meta) {
              final i = v.round();
              if (i < 0 || i >= labels.length || v != i.toDouble()) {
                return const SizedBox.shrink();
              }
              return SideTitleWidget(meta: meta, child: Text(labels[i], style: axisLabel));
            },
          ),
        ),
      );

  static FlBorderData get noBorder => FlBorderData(show: false);
}

/// Small tooltip used by all charts.
LineTouchTooltipData lineTooltip(String Function(double y) format) => LineTouchTooltipData(
      getTooltipColor: (_) => LifeColors.surfaceHigh,
      tooltipBorderRadius: Radii.rSm,
      tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      getTooltipItems: (spots) => [
        for (final s in spots)
          LineTooltipItem(format(s.y), LifeText.label.copyWith(fontWeight: FontWeight.w600)),
      ],
    );

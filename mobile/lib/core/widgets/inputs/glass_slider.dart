import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Labelled slider used for energy / motivation (1–10).
class GlassSlider extends StatelessWidget {
  const GlassSlider({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 1,
    this.max = 10,
    this.accent = LifeColors.iris,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final double min;
  final double max;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 92, child: Text(label, style: LifeText.label.copyWith(color: LifeColors.text2))),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 6,
              activeTrackColor: accent,
              inactiveTrackColor: accent.withValues(alpha: 0.16),
              thumbColor: Colors.white,
              tickMarkShape: SliderTickMarkShape.noTickMark,
              overlayColor: accent.withValues(alpha: 0.15),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9, elevation: 0, pressedElevation: 0),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
              trackShape: const RoundedRectSliderTrackShape(),
              showValueIndicator: ShowValueIndicator.never,
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: (max - min).round(),
              onChanged: onChanged,
              semanticFormatterCallback: (v) => '$label ${v.round()}',
            ),
          ),
        ),
        SizedBox(
          width: 28,
          child: Text('${value.round()}', textAlign: TextAlign.right, style: LifeText.title.copyWith(color: accent)),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import 'colors.dart';

/// Shared gradients. See docs/UI_UX.md §4.2.
abstract final class LifeGradients {
  /// The AI signature: iridescent, used only for assistant elements.
  static const aiColors = [
    LifeColors.iris,
    LifeColors.rose,
    LifeColors.amber,
    LifeColors.mint,
    LifeColors.sky,
    LifeColors.iris,
  ];

  static const ai = SweepGradient(colors: aiColors);

  static const aiLinear = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [LifeColors.iris, LifeColors.rose, LifeColors.sky],
  );

  /// Glass fill: brighter top-left, fading to bottom-right.
  static const glassFill = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x1FFFFFFF), Color(0x0DFFFFFF), Color(0x08FFFFFF)],
    stops: [0, 0.5, 1],
  );

  /// Specular rim: bright on the top-left and bottom-right edges.
  static const glassRim = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x66FFFFFF), Color(0x14FFFFFF), Color(0x0AFFFFFF), Color(0x33FFFFFF)],
    stops: [0, 0.35, 0.7, 1],
  );

  /// Accent progress fill: color → lighter tint.
  static LinearGradient accent(Color c) => LinearGradient(
        colors: [c, Color.lerp(c, Colors.white, 0.35)!],
      );

  static LinearGradient chartFill(Color c) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [c.withValues(alpha: 0.28), c.withValues(alpha: 0)],
      );

  static LinearGradient bar(Color c) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color.lerp(c, Colors.white, 0.2)!, c],
      );
}

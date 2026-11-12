import 'package:flutter/material.dart';

/// Shadows. Glow is reserved for AI elements (see AiGlowBorder).
abstract final class LifeShadows {
  /// Soft lift under glass panels.
  static const glass = [
    BoxShadow(color: Color(0x33000000), blurRadius: 30, offset: Offset(0, 12)),
  ];

  /// Floating elements: nav bar, FAB, sheets.
  static const float = [
    BoxShadow(color: Color(0x59000000), blurRadius: 32, offset: Offset(0, 14)),
  ];

  /// Colored halo, used sparingly (AI, active progress heads).
  static List<BoxShadow> halo(Color color, [double strength = 1]) => [
        BoxShadow(
          color: color.withValues(alpha: 0.4 * strength),
          blurRadius: 20,
          spreadRadius: -6,
        ),
      ];
}

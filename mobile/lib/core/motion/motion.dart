import 'package:flutter/widgets.dart';

import 'motion_scope.dart';

export 'motion_scope.dart';

/// Motion tokens. See docs/UI_UX.md §7.1.
abstract final class Motion {
  // Durations
  static const press = Duration(milliseconds: 120);
  static const release = Duration(milliseconds: 180);
  static const check = Duration(milliseconds: 220);
  static const card = Duration(milliseconds: 300);
  static const nav = Duration(milliseconds: 320);
  static const modal = Duration(milliseconds: 300);
  static const modalExit = Duration(milliseconds: 200);
  static const page = Duration(milliseconds: 350);
  static const countUp = Duration(milliseconds: 800);
  static const chart = Duration(milliseconds: 900);
  static const ring = Duration(milliseconds: 1000);
  static const burst = Duration(milliseconds: 700);
  static const stagger = Duration(milliseconds: 40);
  static const ambient = Duration(seconds: 12);

  // Curves
  static const standard = Curves.easeOutCubic;
  static const inOut = Curves.easeInOutCubic;
  static const emphasized = Cubic(0.2, 0, 0, 1);
  static const exit = Curves.easeInCubic;

  /// Returns [d], or zero when the user prefers reduced motion.
  static Duration of(BuildContext context, Duration d) =>
      MotionScope.reducedOf(context) ? Duration.zero : d;

  /// Like [of], but never zero. AnimatedSize asserts when given a zero
  /// duration, so size animations use 1 ms when motion is reduced.
  static Duration size(BuildContext context, Duration d) =>
      MotionScope.reducedOf(context) ? const Duration(milliseconds: 1) : d;
}

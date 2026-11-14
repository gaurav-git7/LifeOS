import 'package:flutter/material.dart';

/// Spacing (4-pt grid), radii and sizes. See docs/UI_UX.md §4.4.
abstract final class Space {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const xxxl = 32.0;
  static const huge = 40.0;

  static const screen = 20.0;
  static const cardGap = 12.0;
  static const section = 24.0;

  /// Bottom padding so content clears the floating nav bar (64 + 10)
  /// and the + button above it (56 + 12), plus breathing room.
  static const navClearance = 160.0;
}

abstract final class Radii {
  static const sm = 12.0;
  static const md = 18.0;
  static const lg = 24.0;
  static const xl = 30.0;
  static const pill = 999.0;

  static const rSm = BorderRadius.all(Radius.circular(sm));
  static const rMd = BorderRadius.all(Radius.circular(md));
  static const rLg = BorderRadius.all(Radius.circular(lg));
  static const rXl = BorderRadius.all(Radius.circular(xl));
  static const rPill = BorderRadius.all(Radius.circular(pill));
}

abstract final class Sizes {
  static const touch = 48.0;
  static const iconSm = 20.0;
  static const iconNav = 22.0;
  static const icon = 24.0;
  static const navHeight = 64.0;
  static const avatar = 44.0;
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'colors.dart';

/// Type system (v2). See docs/UI_UX.md §4.3.
///
/// - Instrument Serif: large editorial titles and the greeting.
/// - Geist: all UI text and big numbers (tight tracking).
/// - Geist Mono: small numeric meta (durations, times, counts).
///
/// google_fonts fetches and caches fonts on first launch. To bundle them for
/// offline first launch, drop the .ttf files into assets/google_fonts/.
abstract final class LifeText {
  static const _tabular = [FontFeature.tabularFigures()];

  static TextStyle _serif(double size, double height, {bool italic = false}) =>
      GoogleFonts.instrumentSerif(
        fontSize: size,
        height: height / size,
        fontWeight: FontWeight.w400,
        fontStyle: italic ? FontStyle.italic : FontStyle.normal,
        color: LifeColors.text,
        letterSpacing: -0.4,
      );

  static TextStyle _sans(double size, double height, FontWeight w, {double tracking = 0}) =>
      GoogleFonts.geist(
        fontSize: size,
        height: height / size,
        fontWeight: w,
        color: LifeColors.text,
        letterSpacing: tracking,
      );

  // Editorial
  static final display = _serif(40, 44);
  static final displayItalic = _serif(40, 44, italic: true);
  static final titleSerif = _serif(30, 34);
  static final titleSerifItalic = _serif(30, 34, italic: true);

  // UI
  static final h2 = _sans(20, 26, FontWeight.w600, tracking: -0.4);
  static final title = _sans(16, 22, FontWeight.w600, tracking: -0.2);
  static final body = _sans(15, 22, FontWeight.w400, tracking: -0.1);
  static final bodyStrong = _sans(15, 22, FontWeight.w500, tracking: -0.1);
  static final label = _sans(13, 18, FontWeight.w500);
  static final caption = _sans(12, 16, FontWeight.w400).copyWith(color: LifeColors.text2);

  /// Small sentence-case label above a section or value.
  static final eyebrow = _sans(13, 18, FontWeight.w500).copyWith(color: LifeColors.text2);

  // Numbers
  static final statHero = _sans(48, 50, FontWeight.w600, tracking: -2).copyWith(fontFeatures: _tabular);
  static final statLarge = _sans(36, 40, FontWeight.w600, tracking: -1.4).copyWith(fontFeatures: _tabular);
  static final stat = _sans(22, 26, FontWeight.w600, tracking: -0.6).copyWith(fontFeatures: _tabular);

  /// Monospaced meta: "45m · 8:00 PM", "1,240 / 1,600".
  static final mono = GoogleFonts.geistMono(
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w500,
    color: LifeColors.text2,
  );

  static TextTheme textTheme() => TextTheme(
        displayLarge: display,
        headlineMedium: titleSerif,
        headlineSmall: h2,
        titleMedium: title,
        bodyLarge: body,
        bodyMedium: body,
        labelLarge: label,
        labelMedium: label,
        bodySmall: caption,
      );
}

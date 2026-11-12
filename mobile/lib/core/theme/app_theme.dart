import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'colors.dart';
import 'spacing.dart';
import 'typography.dart';

export 'colors.dart';
export 'gradients.dart';
export 'shadows.dart';
export 'spacing.dart';
export 'typography.dart';

/// Material 3 base, fully re-skinned. Dark only for v1.
abstract final class AppTheme {
  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      primary: LifeColors.iris,
      onPrimary: Colors.white,
      secondary: LifeColors.sky,
      onSecondary: LifeColors.onLight,
      tertiary: LifeColors.mint,
      surface: LifeColors.solid,
      onSurface: LifeColors.text,
      onSurfaceVariant: LifeColors.text2,
      surfaceContainerHighest: LifeColors.surfaceHigh,
      error: LifeColors.danger,
      outline: LifeColors.glassBorder,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: LifeColors.bg,
      canvasColor: LifeColors.bg,
      textTheme: LifeText.textTheme(),
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      splashColor: Colors.transparent,
      iconTheme: const IconThemeData(color: LifeColors.text, size: Sizes.icon),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: LifeText.h2,
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: LifeColors.glass,
        hintStyle: LifeText.body.copyWith(color: LifeColors.text3),
        contentPadding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: 15),
        border: const OutlineInputBorder(
          borderRadius: Radii.rMd,
          borderSide: BorderSide(color: LifeColors.glassBorder),
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: Radii.rMd,
          borderSide: BorderSide(color: LifeColors.glassBorder),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: Radii.rMd,
          borderSide: BorderSide(color: Color(0x80FFFFFF)),
        ),
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: LifeColors.text,
        selectionColor: Color(0x668E7CFF),
        selectionHandleColor: LifeColors.iris,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? LifeColors.mint : LifeColors.glassActive,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: LifeColors.surfaceHigh,
        contentTextStyle: LifeText.label,
        shape: const RoundedRectangleBorder(borderRadius: Radii.rMd),
      ),
      dividerTheme: const DividerThemeData(color: LifeColors.hairline, thickness: 1),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {TargetPlatform.android: FadeForwardsPageTransitionsBuilder()},
      ),
    );
  }
}

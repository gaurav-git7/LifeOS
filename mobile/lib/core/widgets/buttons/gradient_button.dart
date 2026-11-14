import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../glass/glass_card.dart';
import 'pressable.dart';

enum ButtonVariant {
  /// White pill, dark text — the main action on a screen.
  primary,

  /// Solid iris — for AI / accent actions.
  accent,

  /// Glass pill — secondary actions.
  glass,

  /// Text only.
  ghost,

  /// Destructive.
  danger,
}

/// Pill button. (Kept the name for compatibility; v2 buttons are mostly
/// solid white or glass, not gradients.)
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.variant = ButtonVariant.primary,
    this.loading = false,
    this.expand = false,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final ButtonVariant variant;
  final bool loading;
  final bool expand;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final height = compact ? 38.0 : 50.0;
    final fg = switch (variant) {
      ButtonVariant.primary => LifeColors.onLight,
      ButtonVariant.accent => Colors.white,
      ButtonVariant.glass => LifeColors.text,
      ButtonVariant.ghost => LifeColors.text2,
      ButtonVariant.danger => LifeColors.danger,
    };

    final row = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
        else if (icon != null)
          Icon(icon, size: 17, color: fg),
        if (loading || icon != null) const SizedBox(width: Space.sm),
        // Flexible: on narrow screens a long label shortens instead of overflowing.
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: LifeText.label.copyWith(color: fg, fontWeight: FontWeight.w600, fontSize: compact ? 13 : 15),
          ),
        ),
      ],
    );

    final padded = SizedBox(
      height: height,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: compact ? Space.lg : Space.xxl),
        child: row,
      ),
    );

    final Widget body = switch (variant) {
      ButtonVariant.primary => DecoratedBox(
          decoration: const BoxDecoration(color: Colors.white, borderRadius: Radii.rPill),
          child: padded,
        ),
      ButtonVariant.accent => DecoratedBox(
          decoration: BoxDecoration(
            color: LifeColors.iris,
            borderRadius: Radii.rPill,
            boxShadow: LifeShadows.halo(LifeColors.iris, 0.8),
          ),
          child: padded,
        ),
      ButtonVariant.glass => GlassSurface(radius: Radii.pill, child: padded),
      ButtonVariant.ghost => padded,
      ButtonVariant.danger => DecoratedBox(
          decoration: BoxDecoration(
            color: LifeColors.danger.withValues(alpha: 0.12),
            borderRadius: Radii.rPill,
          ),
          child: padded,
        ),
    };

    return Opacity(
      opacity: enabled || loading ? 1 : 0.4,
      child: Pressable(
        onTap: enabled ? onPressed : null,
        haptic: variant == ButtonVariant.primary || variant == ButtonVariant.accent,
        semanticLabel: label,
        child: body,
      ),
    );
  }
}

/// Round glass icon button with an optional notification dot.
class IconGlassButton extends StatelessWidget {
  const IconGlassButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.badge = false,
    this.size = 42,
    this.semanticLabel,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final bool badge;
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onPressed,
      scale: 0.9,
      semanticLabel: semanticLabel,
      child: SizedBox.square(
        dimension: size < Sizes.touch ? Sizes.touch : size,
        child: Center(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              SizedBox.square(
                dimension: size,
                child: GlassSurface(
                  radius: size / 2,
                  child: Center(child: Icon(icon, size: 19, color: LifeColors.text)),
                ),
              ),
              if (badge)
                Positioned(
                  right: 1,
                  top: 1,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: LifeColors.coral,
                      border: Border.all(color: LifeColors.bg, width: 1.5),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

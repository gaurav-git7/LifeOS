import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../buttons/pressable.dart';
import '../effects/ai_mark.dart';

/// Surface styles. See docs/UI_UX.md §5.
enum GlassTier {
  /// Opaque dark card. For dense lists.
  solid,

  /// Liquid glass: real blur (shared via BackdropGroup), white-tinted fill,
  /// specular rim. The default.
  glass,
}

/// Paints the liquid-glass rim: a 1 px gradient stroke that is bright on the
/// top-left and bottom-right edges, like light catching a glass edge.
class GlassRimPainter extends CustomPainter {
  const GlassRimPainter({required this.radius, this.gradient = LifeGradients.glassRim});

  final double radius;
  final Gradient gradient;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(0.5);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = gradient.createShader(rect),
    );
  }

  @override
  bool shouldRepaint(GlassRimPainter old) => old.radius != radius || old.gradient != gradient;
}

/// Frosted glass panel with blur + tint + rim. Used directly by cards, the
/// nav bar, buttons and sheets so every glass surface looks the same.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    required this.radius,
    this.tint,
    this.blur = 24,
  });

  final Widget child;
  final double radius;
  final Color? tint;
  final double blur;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    final fill = tint == null
        ? LifeGradients.glassFill
        : LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.alphaBlend(tint!.withValues(alpha: 0.22), const Color(0x14FFFFFF)),
              tint!.withValues(alpha: 0.08),
              const Color(0x08FFFFFF),
            ],
          );

    return ClipRRect(
      borderRadius: r,
      child: BackdropFilter.grouped(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration: BoxDecoration(borderRadius: r, gradient: fill),
          child: CustomPaint(
            foregroundPainter: GlassRimPainter(radius: radius),
            child: child,
          ),
        ),
      ),
    );
  }
}

class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.tier = GlassTier.glass,
    this.tint,
    this.ai = false,
    this.padding = const EdgeInsets.all(Space.xl),
    this.radius = Radii.lg,
    this.onTap,
    this.onLongPress,
    this.heroTag,
    this.width,
  });

  final Widget child;
  final GlassTier tier;

  /// Optional accent tint for the glass (e.g. mint on a learning card).
  final Color? tint;

  /// Adds the animated iridescent AI border.
  final bool ai;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Object? heroTag;
  final double? width;

  @override
  Widget build(BuildContext context) {
    Widget content = Padding(padding: padding, child: child);

    content = switch (tier) {
      GlassTier.solid => DecoratedBox(
          decoration: BoxDecoration(
            color: LifeColors.solid,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: LifeColors.hairline),
          ),
          child: content,
        ),
      GlassTier.glass => GlassSurface(radius: radius, tint: tint, child: content),
    };

    if (ai) content = AiGlowBorder(radius: radius, child: content);
    if (width != null) content = SizedBox(width: width, child: content);

    if (heroTag != null) {
      content = Hero(
        tag: heroTag!,
        child: Material(type: MaterialType.transparency, child: content),
      );
    }

    if (onTap != null || onLongPress != null) {
      content = Pressable(onTap: onTap, onLongPress: onLongPress, scale: 0.985, child: content);
    }

    return content;
  }
}

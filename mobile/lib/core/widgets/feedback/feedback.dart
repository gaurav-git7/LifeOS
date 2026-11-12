import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../motion/motion.dart';
import '../../theme/app_theme.dart';
import '../buttons/gradient_button.dart';
import '../glass/glass_card.dart';
import '../progress/stat_card.dart';

/// Section title with an optional trailing action ("See all").
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.action, this.onAction});

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md, left: 2, right: 2),
      child: Row(
        children: [
          Expanded(child: Text(title, style: LifeText.title)),
          if (action != null)
            GestureDetector(
              onTap: onAction,
              child: Text(action!, style: LifeText.label.copyWith(color: LifeColors.text2)),
            ),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.message,
    this.icon = LucideIcons.sparkles,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xxl, horizontal: Space.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 52,
            child: GlassSurface(radius: 26, child: Icon(icon, size: 22, color: LifeColors.text)),
          ),
          const SizedBox(height: Space.lg),
          Text(title, style: LifeText.title, textAlign: TextAlign.center),
          const SizedBox(height: Space.xs),
          Text(message, style: LifeText.body.copyWith(color: LifeColors.text2), textAlign: TextAlign.center),
          if (actionLabel != null) ...[
            const SizedBox(height: Space.xl),
            GradientButton(label: actionLabel!, onPressed: onAction, variant: ButtonVariant.glass, compact: true),
          ],
        ],
      ),
    );
  }
}

/// Shimmering placeholder block for loading states.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({super.key, this.width, this.height = 14, this.radius = 7});

  final double? width;
  final double height;
  final double radius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!MotionScope.reducedOf(context) && !_c.isAnimating) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final x = -1.5 + _c.value * 3;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(x - 1, 0),
              end: Alignment(x + 1, 0),
              colors: const [Color(0x12FFFFFF), Color(0x29FFFFFF), Color(0x12FFFFFF)],
            ),
          ),
        );
      },
    );
  }
}

/// Header row with a one-line summary; tap to expand the body.
/// See docs/UI_UX.md §9.1 (collapsed sections on Home).
class CollapsibleSection extends StatefulWidget {
  const CollapsibleSection({
    super.key,
    required this.title,
    required this.summary,
    required this.child,
    this.icon,
    this.accent = LifeColors.iris,
    this.initiallyOpen = false,
    this.onToggle,
  });

  final String title;
  final Widget summary;
  final Widget child;
  final IconData? icon;
  final Color accent;
  final bool initiallyOpen;
  final ValueChanged<bool>? onToggle;

  @override
  State<CollapsibleSection> createState() => _CollapsibleSectionState();
}

class _CollapsibleSectionState extends State<CollapsibleSection> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final d = Motion.of(context, Motion.card);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: _open,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              setState(() => _open = !_open);
              widget.onToggle?.call(_open);
            },
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: Sizes.touch),
              child: Row(
                children: [
                  if (widget.icon != null) ...[
                    IconChip(icon: widget.icon!, color: widget.accent, size: 30),
                    const SizedBox(width: Space.md),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.title, style: LifeText.bodyStrong),
                        DefaultTextStyle(
                          style: LifeText.caption,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          child: widget.summary,
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: d,
                    curve: Motion.inOut,
                    child: const Icon(LucideIcons.chevronDown, size: 18, color: LifeColors.text3),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: Motion.size(context, Motion.card),
          curve: Motion.inOut,
          alignment: Alignment.topCenter,
          child: _open
              ? Padding(padding: const EdgeInsets.only(top: Space.md), child: widget.child)
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

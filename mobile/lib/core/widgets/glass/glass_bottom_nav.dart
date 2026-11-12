import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../motion/motion.dart';
import '../../theme/app_theme.dart';
import 'glass_card.dart';

class GlassNavItem {
  const GlassNavItem({required this.icon, required this.label, this.badge = false});

  final IconData icon;
  final String label;
  final bool badge;
}

/// Floating liquid-glass tab bar with a sliding lighter-glass capsule.
/// See docs/UI_UX.md §8.2.
class GlassBottomNav extends StatelessWidget {
  const GlassBottomNav({
    super.key,
    required this.items,
    required this.index,
    required this.onChanged,
  });

  final List<GlassNavItem> items;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final duration = Motion.of(context, Motion.nav);
    return DecoratedBox(
      decoration: const BoxDecoration(borderRadius: Radii.rPill, boxShadow: LifeShadows.float),
      child: GlassSurface(
        radius: Radii.pill,
        blur: 28,
        child: SizedBox(
          height: Sizes.navHeight,
          child: LayoutBuilder(
            builder: (context, c) {
              const inset = 5.0;
              final w = (c.maxWidth - inset * 2) / items.length;
              return Stack(
                children: [
                  AnimatedPositioned(
                    duration: duration,
                    curve: Motion.emphasized,
                    left: inset + w * index,
                    top: inset,
                    bottom: inset,
                    width: w,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(color: LifeColors.glassActive, borderRadius: Radii.rPill),
                      child: CustomPaint(painter: GlassRimPainter(radius: Radii.pill)),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: inset),
                    child: Row(
                      children: [
                        for (var i = 0; i < items.length; i++)
                          SizedBox(
                            width: w,
                            child: _NavButton(
                              key: ValueKey('nav-${items[i].label}'),
                              item: items[i],
                              active: i == index,
                              duration: duration,
                              onTap: () {
                                if (i != index) HapticFeedback.selectionClick();
                                onChanged(i);
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    super.key,
    required this.item,
    required this.active,
    required this.duration,
    required this.onTap,
  });

  final GlassNavItem item;
  final bool active;
  final Duration duration;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? LifeColors.text : LifeColors.text2;
    return Semantics(
      button: true,
      selected: active,
      label: item.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                TweenAnimationBuilder<Color?>(
                  tween: ColorTween(end: color),
                  duration: duration,
                  builder: (context, c, _) => Icon(item.icon, size: Sizes.iconNav, color: c),
                ),
                if (item.badge)
                  Positioned(
                    right: -3,
                    top: -2,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LifeGradients.aiLinear,
                        border: Border.all(color: const Color(0xFF1A1A22), width: 1.5),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: duration,
              style: LifeText.caption.copyWith(
                fontSize: 10.5,
                color: color,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
              ),
              child: Text(item.label, maxLines: 1, overflow: TextOverflow.fade, softWrap: false),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../motion/motion.dart';
import '../../theme/app_theme.dart';
import '../glass/glass_card.dart';

class FilterChipData {
  const FilterChipData(this.label, {this.count, this.icon, this.accent});

  final String label;
  final int? count;
  final IconData? icon;
  final Color? accent;
}

/// Horizontally scrolling single-select chips with optional counts.
class FilterChipRow extends StatelessWidget {
  const FilterChipRow({
    super.key,
    required this.chips,
    required this.selected,
    required this.onSelected,
    this.padding = const EdgeInsets.symmetric(horizontal: Space.screen),
  });

  final List<FilterChipData> chips;
  final int selected;
  final ValueChanged<int> onSelected;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        // Chip rows are short: build every chip so all are reachable (and announced by screen readers).
        cacheExtent: 2000,
        padding: padding,
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: Space.sm),
        itemBuilder: (context, i) => GlassChip(
          data: chips[i],
          selected: i == selected,
          onTap: () {
            HapticFeedback.selectionClick();
            onSelected(i);
          },
        ),
      ),
    );
  }
}

/// Selected = solid white with dark text. Unselected = glass.
class GlassChip extends StatelessWidget {
  const GlassChip({super.key, required this.data, required this.selected, this.onTap});

  final FilterChipData data;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final duration = Motion.of(context, Motion.check);
    final fg = selected ? LifeColors.onLight : LifeColors.text;
    final iconColor = selected ? LifeColors.onLight : (data.accent ?? LifeColors.text2);

    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (data.icon != null) ...[
            Icon(data.icon, size: 15, color: iconColor),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              data.label,
              style: LifeText.label.copyWith(color: fg),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (data.count != null) ...[
            const SizedBox(width: 6),
            Text(
              '${data.count}',
              style: LifeText.mono.copyWith(
                color: selected ? LifeColors.onLight.withValues(alpha: 0.55) : (data.accent ?? LifeColors.text3),
              ),
            ),
          ],
        ],
      ),
    );

    return GestureDetector(
      onTap: onTap,
      child: AnimatedSwitcher(
        duration: duration,
        child: selected
            ? DecoratedBox(
                key: const ValueKey(true),
                decoration: const BoxDecoration(color: Colors.white, borderRadius: Radii.rPill),
                child: SizedBox(height: 38, child: content),
              )
            : GlassSurface(
                key: const ValueKey(false),
                radius: Radii.pill,
                child: SizedBox(height: 38, child: content),
              ),
      ),
    );
  }
}

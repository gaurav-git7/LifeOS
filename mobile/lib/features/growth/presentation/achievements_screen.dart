import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/widgets/widgets.dart';
import '../../../data/stores.dart';

/// Badges grid: unlocked ones glow in their color, locked ones show a hint.
class AchievementsScreen extends ConsumerWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(achievementsProvider);
    final unlocked = all.where((a) => a.unlockedAt != null).length;
    return Scaffold(
      backgroundColor: LifeColors.bg,
      body: Stack(
        children: [
          const Positioned.fill(child: AmbientBackground(mode: AmbientMode.growth)),
          SafeArea(
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(Space.screen, Space.lg, Space.screen, Space.xxl),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        IconGlassButton(icon: Icons.arrow_back_rounded, semanticLabel: 'Back', onPressed: () => context.pop()),
                        const SizedBox(height: Space.lg),
                        Text('$unlocked of ${all.length} unlocked', style: LifeText.eyebrow),
                        Text('Achievements', style: LifeText.display),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(Space.screen, 0, Space.screen, 60),
                  sliver: SliverGrid.count(
                    crossAxisCount: 2,
                    mainAxisSpacing: Space.cardGap,
                    crossAxisSpacing: Space.cardGap,
                    childAspectRatio: 0.78,
                    children: [
                      for (final (i, a) in all.indexed)
                        StaggeredEntry(
                          index: i,
                          child: GlassCard(
                            tint: a.unlockedAt != null ? a.color : null,
                            padding: const EdgeInsets.all(Space.lg),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 52,
                                  height: 52,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    color: a.unlockedAt != null ? a.color : LifeColors.glassHigh,
                                    boxShadow: a.unlockedAt != null ? LifeShadows.halo(a.color) : null,
                                  ),
                                  child: Icon(
                                    a.unlockedAt != null ? a.icon : LucideIcons.lock,
                                    color: a.unlockedAt != null ? LifeColors.onLight : LifeColors.text3,
                                  ),
                                ),
                                const Spacer(),
                                Text(a.title, style: LifeText.title.copyWith(color: a.unlockedAt != null ? LifeColors.text : LifeColors.text2)),
                                const SizedBox(height: 2),
                                Text(a.description, style: LifeText.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
                                const SizedBox(height: Space.sm),
                                Text(
                                  a.unlockedAt != null ? DateFormat('d MMM yyyy').format(a.unlockedAt!) : 'Locked',
                                  style: LifeText.mono.copyWith(fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

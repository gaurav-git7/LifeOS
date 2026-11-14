import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/widgets/widgets.dart';
import '../data/stores.dart';
import '../data/sync/sync_engine.dart';
import 'quick_add_sheet.dart';
import 'xp_overlay.dart';

/// Mesh background + current tab + floating nav + quick-add + XP toasts.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = shell.currentIndex;
    final navBottom = 10 + MediaQuery.paddingOf(context).bottom;
    final showFab = index <= 1; // Home and Plan
    final d = Motion.of(context, Motion.card);
    final pending = ref.watch(assistantProvider.select((s) => s.pending.length));
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final live = ref.watch(authProvider.select((a) => a.live));

    return Scaffold(
      backgroundColor: LifeColors.bg,
      resizeToAvoidBottomInset: index == 4, // chat input follows the keyboard
      body: Stack(
        children: [
          Positioned.fill(child: AmbientBackground(mode: AmbientMode.values[index])),
          Positioned.fill(
            child: live
                // Pull down on any tab to sync with the server.
                ? RefreshIndicator(
                    color: LifeColors.lilac,
                    backgroundColor: LifeColors.surfaceHigh,
                    edgeOffset: MediaQuery.paddingOf(context).top,
                    onRefresh: () async {
                      await ref.read(syncEngineProvider).syncNow();
                      await ref.read(assistantProvider.notifier).load();
                    },
                    child: shell,
                  )
                : shell,
          ),
          Positioned(
            right: Space.screen,
            bottom: navBottom + Sizes.navHeight + Space.md,
            child: IgnorePointer(
              ignoring: !showFab,
              child: AnimatedScale(
                scale: showFab ? 1 : 0.6,
                duration: d,
                curve: Motion.emphasized,
                child: AnimatedOpacity(opacity: showFab ? 1 : 0, duration: d, child: const QuickAddFab()),
              ),
            ),
          ),
          if (!keyboardOpen)
            Positioned(
              left: Space.lg,
              right: Space.lg,
              bottom: navBottom,
              child: GlassBottomNav(
                index: index,
                onChanged: (i) => shell.goBranch(i, initialLocation: i == index),
                items: [
                  const GlassNavItem(icon: LucideIcons.house, label: 'Home'),
                  const GlassNavItem(icon: LucideIcons.listTodo, label: 'Plan'),
                  const GlassNavItem(icon: LucideIcons.sprout, label: 'Growth'),
                  const GlassNavItem(icon: LucideIcons.notebookPen, label: 'Journal'),
                  GlassNavItem(icon: LucideIcons.sparkles, label: 'Assistant', badge: pending > 0),
                ],
              ),
            ),
          const Positioned.fill(child: XpOverlay()),
        ],
      ),
    );
  }
}

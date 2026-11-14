import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../feedback/feedback.dart';
import '../glass/glass_card.dart';

/// Standard tab page: transparent (shows the mesh background), an editorial
/// serif title, content slivers, and padding that clears the floating nav.
class TabScaffold extends StatelessWidget {
  const TabScaffold({
    super.key,
    this.title,
    this.subtitle,
    this.header,
    this.actions = const [],
    required this.slivers,
  });

  final String? title;
  final String? subtitle;

  /// Replaces the default title header when provided.
  final Widget? header;
  final List<Widget> actions;
  final List<Widget> slivers;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      slivers: [
        SliverSafeArea(
          bottom: false,
          sliver: SliverPadding(
            padding: const EdgeInsets.fromLTRB(Space.screen, Space.lg, Space.screen, Space.xxl),
            sliver: SliverToBoxAdapter(
              child: header ??
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (subtitle != null) Text(subtitle!, style: LifeText.eyebrow),
                            Text(title ?? '', style: LifeText.display),
                          ],
                        ),
                      ),
                      ...actions,
                    ],
                  ),
            ),
          ),
        ),
        ...slivers,
        // Clears the floating tab bar, the + button above it, and the system nav bar.
        SliverToBoxAdapter(child: SizedBox(height: Space.navClearance + MediaQuery.paddingOf(context).bottom)),
      ],
    );
  }
}

/// Padded box sliver helper.
class SliverSection extends StatelessWidget {
  const SliverSection({super.key, required this.child, this.bottom = Space.section});

  final Widget child;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(Space.screen, 0, Space.screen, bottom),
      sliver: SliverToBoxAdapter(child: child),
    );
  }
}

/// Placeholder content for tabs that are built in later steps.
class ComingSoonCard extends StatelessWidget {
  const ComingSoonCard({super.key, required this.title, required this.message, this.icon});

  final String title;
  final String message;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: icon == null
          ? EmptyState(title: title, message: message)
          : EmptyState(title: title, message: message, icon: icon!),
    );
  }
}

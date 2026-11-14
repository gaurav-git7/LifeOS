import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/routing/routes.dart';
import '../../core/widgets/widgets.dart';
import '../../data/stores.dart';

/// Three-slide intro on first launch. See docs/UI_UX.md §9.0.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pages = PageController();
  int _page = 0;

  static const _modes = [AmbientMode.home, AmbientMode.assistant, AmbientMode.growth];

  void _finish(String route) {
    ref.read(authProvider.notifier).completeOnboarding();
    context.go(route);
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slides = [
      (
        const ActivityRings(
          size: 190,
          stroke: 18,
          rings: [RingData(0.8, LifeColors.iris), RingData(0.6, LifeColors.coral), RingData(0.7, LifeColors.mint)],
        ),
        'Your personal',
        'operating system.',
        'Tasks, habits, learning, projects and your journal — in one calm place that shows how your days add up.',
      ),
      (
        const _ProposalMock(),
        'An assistant that',
        'suggests. You decide.',
        'LifeOS plans and reviews with you. Nothing changes until you tap Accept — and your journal stays private unless you choose otherwise.',
      ),
      (
        const AiMark(size: 170),
        'Grow a little',
        'every day.',
        'Roadmaps, focus sessions and quiet progress — levels and streaks that reward doing, not scrolling.',
      ),
    ];

    return Scaffold(
      backgroundColor: LifeColors.bg,
      body: Stack(
        children: [
          Positioned.fill(child: AmbientBackground(mode: _modes[_page])),
          SafeArea(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.all(Space.md),
                    child: GradientButton(label: 'Skip', variant: ButtonVariant.ghost, compact: true, onPressed: () => _finish(Routes.login)),
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _pages,
                    itemCount: slides.length,
                    onPageChanged: (i) => setState(() => _page = i),
                    itemBuilder: (context, i) {
                      final s = slides[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Space.xxl),
                        child: Column(
                          children: [
                            // The illustration shrinks on short screens instead of overflowing.
                            Expanded(
                              child: Center(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: SizedBox(height: 230, child: Center(child: s.$1)),
                                ),
                              ),
                            ),
                            Text(s.$2, textAlign: TextAlign.center, style: LifeText.display),
                            Text(s.$3, textAlign: TextAlign.center, style: LifeText.displayItalic.copyWith(color: LifeColors.text2)),
                            const SizedBox(height: Space.lg),
                            Text(s.$4, textAlign: TextAlign.center, style: LifeText.body.copyWith(color: LifeColors.text2)),
                            const SizedBox(height: Space.xxl),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < slides.length; i++)
                      AnimatedContainer(
                        duration: Motion.of(context, Motion.card),
                        width: i == _page ? 22 : 7,
                        height: 7,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: i == _page ? Colors.white : LifeColors.text3,
                          borderRadius: Radii.rPill,
                        ),
                      ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.all(Space.screen),
                  child: GradientButton(
                    label: _page == slides.length - 1 ? 'Get started' : 'Continue',
                    expand: true,
                    onPressed: () => _page == slides.length - 1
                        ? _finish(Routes.register)
                        : _pages.nextPage(duration: Motion.page, curve: Motion.emphasized),
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

class _ProposalMock extends StatelessWidget {
  const _ProposalMock();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 300,
      child: GlassCard(
        ai: true,
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const IconChip(icon: LucideIcons.calendarDays, color: LifeColors.iris, size: 30),
                const SizedBox(width: Space.md),
                Expanded(child: Text('Block 9:00–10:30 tomorrow for DSA', style: LifeText.bodyStrong)),
              ],
            ),
            const SizedBox(height: Space.sm),
            Text('Why: your best focus is in the morning.', style: LifeText.caption),
            const SizedBox(height: Space.md),
            const Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                GradientButton(label: 'Reject', compact: true, variant: ButtonVariant.ghost),
                SizedBox(width: Space.sm),
                IgnorePointer(child: GradientButton(label: 'Accept', compact: true, onPressed: _noop)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

void _noop() {}

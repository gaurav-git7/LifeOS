import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/routing/routes.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/models.dart';
import '../../../data/stores.dart';
import 'chat_view.dart';
import 'reviews_view.dart';
import 'suggestions_view.dart';

/// AI companion: chat, reviews, suggestions. See docs/UI_UX.md §9.5.
class AssistantScreen extends ConsumerWidget {
  const AssistantScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(assistantTabProvider);
    final s = ref.watch(assistantProvider);
    final busy = s.thinking || s.messages.any((m) => m.streaming);
    final pending = s.pending.length;
    final chatStarted = s.messages.any((m) => m.role == ChatRole.user);
    final compactHeader = tab != 0 || chatStarted;

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.screen, Space.md, Space.screen, Space.lg),
            child: Column(
              children: [
                Row(
                  children: [
                    const SizedBox(width: Sizes.touch),
                    const Spacer(),
                    AnimatedSize(
                      duration: Motion.size(context, Motion.card),
                      curve: Motion.inOut,
                      child: AiMark(
                        size: compactHeader ? 52 : 104,
                        state: busy ? AiState.thinking : AiState.idle,
                      ),
                    ),
                    const Spacer(),
                    IconGlassButton(
                      icon: LucideIcons.brain,
                      semanticLabel: 'What the assistant remembers',
                      onPressed: () => context.push(Routes.memories),
                    ),
                  ],
                ),
                AnimatedSize(
                  duration: Motion.size(context, Motion.card),
                  curve: Motion.inOut,
                  child: compactHeader
                      ? const SizedBox(width: double.infinity, height: Space.md)
                      : Padding(
                          padding: const EdgeInsets.only(top: Space.md, bottom: Space.xl),
                          child: Column(
                            children: [
                              Text('What should we', style: LifeText.titleSerif, textAlign: TextAlign.center),
                              Text(
                                'work on today?',
                                style: LifeText.titleSerifItalic.copyWith(color: LifeColors.text2),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                ),
                SegmentedGlass(
                  segments: const ['Chat', 'Reviews', 'Suggestions'],
                  index: tab,
                  badges: {2: pending},
                  onChanged: (i) => ref.read(assistantTabProvider.notifier).set(i),
                ),
              ],
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: Motion.of(context, Motion.card),
              transitionBuilder: (c, a) => FadeTransition(opacity: a, child: c),
              child: switch (tab) {
                0 => const ChatView(key: ValueKey('chat')),
                1 => const ReviewsView(key: ValueKey('reviews')),
                _ => const SuggestionsView(key: ValueKey('suggestions')),
              },
            ),
          ),
        ],
      ),
    );
  }
}

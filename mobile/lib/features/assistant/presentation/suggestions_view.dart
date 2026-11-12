import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/widgets/widgets.dart';
import '../../../data/models.dart';
import '../../../data/stores.dart';
import 'approval_cards.dart';

/// Every pending proposal, grouped; recent decisions below. UI_UX.md §9.5.
class SuggestionsView extends ConsumerWidget {
  const SuggestionsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(assistantProvider);
    final pending = s.pending;
    final decided = s.proposals.where((p) => p.status != ProposalStatus.pending).toList().reversed.take(8).toList();
    final navSpace = Sizes.navHeight + 30 + MediaQuery.paddingOf(context).bottom;

    return ListView(
      padding: EdgeInsets.fromLTRB(Space.screen, 0, Space.screen, navSpace),
      children: [
        if (pending.isEmpty)
          const GlassCard(
            child: EmptyState(
              icon: LucideIcons.inbox,
              title: 'You’re all caught up',
              message: 'Suggestions from chat and reviews appear here. Nothing changes until you accept.',
            ),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.only(bottom: Space.md),
            child: Row(
              children: [
                const Icon(LucideIcons.shieldCheck, size: 15, color: LifeColors.mint),
                const SizedBox(width: Space.sm),
                Expanded(child: Text('Nothing changes until you accept.', style: LifeText.caption)),
              ],
            ),
          ),
          ProposalsBlock(ids: [for (final p in pending) p.id]),
        ],
        if (decided.isNotEmpty) ...[
          const SizedBox(height: Space.section),
          const SectionHeader(title: 'Recent decisions'),
          for (final p in decided) Padding(padding: const EdgeInsets.only(bottom: 6), child: DecidedPill(proposal: p)),
        ],
      ],
    );
  }
}

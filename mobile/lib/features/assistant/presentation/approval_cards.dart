import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/widgets/widgets.dart';
import '../../../data/models.dart';
import '../../../data/stores.dart';

String originLabel(String origin) => switch (origin) {
      'daily_review' => 'From daily review',
      'weekly_review' => 'From weekly review',
      'quick_capture' => 'From quick capture',
      _ => 'From chat',
    };

IconData actionIcon(String type) => switch (type) {
      'create_task' => LucideIcons.squareCheck,
      'reschedule_task' => LucideIcons.calendarClock,
      'schedule_block' => LucideIcons.calendarDays,
      'create_learning_path' => LucideIcons.map,
      'create_habit' => LucideIcons.flame,
      _ => LucideIcons.sparkles,
    };

/// Single AI proposal: what changes, why, and Reject / Modify / Accept.
/// Nothing changes until Accept. See docs/UI_UX.md §9.5.
class ApprovalCard extends ConsumerStatefulWidget {
  const ApprovalCard({super.key, required this.proposalId});

  final String proposalId;

  @override
  ConsumerState<ApprovalCard> createState() => _ApprovalCardState();
}

class _ApprovalCardState extends ConsumerState<ApprovalCard> {
  bool _editing = false;
  bool _showChanges = false;
  late final _title = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = ref.watch(assistantProvider.select((s) => s.proposal(widget.proposalId)));
    if (p == null) return const SizedBox.shrink();
    final d = Motion.size(context, Motion.card);
    final notifier = ref.read(assistantProvider.notifier);

    return AnimatedSize(
      duration: d,
      curve: Motion.inOut,
      child: p.status != ProposalStatus.pending
          ? DecidedPill(proposal: p)
          : GlassCard(
              ai: true,
              padding: const EdgeInsets.all(Space.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      IconChip(icon: actionIcon(p.actionType), color: LifeColors.iris, size: 32),
                      const SizedBox(width: Space.md),
                      Expanded(child: Text(p.summary, style: LifeText.bodyStrong)),
                    ],
                  ),
                  const SizedBox(height: Space.sm),
                  Text('Why: ${p.reason}', style: LifeText.caption),
                  if (p.changes.isNotEmpty) ...[
                    const SizedBox(height: Space.md),
                    if (p.changes.length > 3 && !_showChanges)
                      GestureDetector(
                        onTap: () => setState(() => _showChanges = true),
                        child: Text('Show ${p.changes.length} details', style: LifeText.label.copyWith(color: LifeColors.lilac)),
                      )
                    else
                      ...[for (final c in p.changes) _ChangeRow(change: c)],
                  ],
                  if (_editing) ...[
                    const SizedBox(height: Space.md),
                    TextField(
                      controller: _title,
                      autofocus: true,
                      style: LifeText.body,
                      decoration: const InputDecoration(hintText: 'Title'),
                    ),
                  ],
                  const SizedBox(height: Space.md),
                  Text(originLabel(p.origin), style: LifeText.mono.copyWith(fontSize: 11)),
                  const SizedBox(height: Space.sm),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: Space.sm,
                    runSpacing: Space.sm,
                    children: [
                      if (!_editing) ...[
                        GradientButton(
                          label: 'Reject',
                          compact: true,
                          variant: ButtonVariant.ghost,
                          onPressed: () => notifier.reject(p.id),
                        ),
                        if (p.payload['title'] != null)
                          GradientButton(
                            label: 'Modify',
                            compact: true,
                            variant: ButtonVariant.glass,
                            onPressed: () => setState(() {
                              _editing = true;
                              _title.text = p.payload['title']! as String;
                            }),
                          ),
                        GradientButton(
                          label: 'Accept',
                          compact: true,
                          onPressed: () {
                            HapticFeedback.mediumImpact();
                            notifier.approve(p.id);
                          },
                        ),
                      ] else ...[
                        GradientButton(
                          label: 'Cancel',
                          compact: true,
                          variant: ButtonVariant.ghost,
                          onPressed: () => setState(() => _editing = false),
                        ),
                        GradientButton(
                          label: 'Save',
                          compact: true,
                          onPressed: () {
                            if (_title.text.trim().isNotEmpty) notifier.editTitle(p.id, _title.text.trim());
                            setState(() => _editing = false);
                          },
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}

class _ChangeRow extends StatelessWidget {
  const _ChangeRow({required this.change});

  final ProposalChange change;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 72, child: Text(change.label, style: LifeText.caption)),
          if (change.before != null) ...[
            Text(
              change.before!,
              style: LifeText.label.copyWith(
                color: LifeColors.text3,
                decoration: TextDecoration.lineThrough,
                decorationColor: LifeColors.text3,
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Icon(LucideIcons.arrowRight, size: 13, color: LifeColors.text3),
            ),
          ],
          Expanded(child: Text(change.after, style: LifeText.label.copyWith(color: LifeColors.lilac))),
        ],
      ),
    );
  }
}

/// After a decision the card collapses into a small status pill.
class DecidedPill extends StatelessWidget {
  const DecidedPill({super.key, required this.proposal});

  final Proposal proposal;

  @override
  Widget build(BuildContext context) {
    final ok = proposal.status == ProposalStatus.executed;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: (ok ? LifeColors.mint : LifeColors.text3).withValues(alpha: 0.15),
          borderRadius: Radii.rPill,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(ok ? LucideIcons.check : LucideIcons.x, size: 14, color: ok ? LifeColors.mint : LifeColors.text3),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                '${ok ? 'Done' : 'Dismissed'} · ${proposal.summary}',
                style: LifeText.caption.copyWith(color: ok ? LifeColors.mint : LifeColors.text3),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Several related proposals approved together (all succeed or none).
class GroupApprovalCard extends ConsumerStatefulWidget {
  const GroupApprovalCard({super.key, required this.groupId});

  final String groupId;

  @override
  ConsumerState<GroupApprovalCard> createState() => _GroupApprovalCardState();
}

class _GroupApprovalCardState extends ConsumerState<GroupApprovalCard> {
  final _excluded = <String>{};

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(assistantProvider.select((s) => s.proposals.where((p) => p.groupId == widget.groupId).toList()));
    final pending = items.where((p) => p.status == ProposalStatus.pending).toList();
    final selected = pending.where((p) => !_excluded.contains(p.id)).length;
    final d = Motion.size(context, Motion.card);

    if (pending.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [for (final p in items) Padding(padding: const EdgeInsets.only(bottom: 6), child: DecidedPill(proposal: p))],
      );
    }

    return AnimatedSize(
      duration: d,
      child: GlassCard(
        ai: true,
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const AiMark(size: 24),
                const SizedBox(width: Space.sm),
                Expanded(child: Text('${pending.length} suggestions', style: LifeText.title)),
                Flexible(
                  child: Text(
                    originLabel(pending.first.origin),
                    style: LifeText.mono.copyWith(fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.sm),
            for (final p in pending)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: !_excluded.contains(p.id),
                    activeColor: Colors.white,
                    checkColor: LifeColors.onLight,
                    side: const BorderSide(color: LifeColors.text3, width: 1.4),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    onChanged: (v) => setState(() => v == true ? _excluded.remove(p.id) : _excluded.add(p.id)),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.summary, style: LifeText.bodyStrong),
                          const SizedBox(height: 2),
                          Text(p.reason, style: LifeText.caption),
                          for (final c in p.changes.where((c) => c.before != null)) _ChangeRow(change: c),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: Space.sm),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                GradientButton(
                  label: 'Reject all',
                  compact: true,
                  variant: ButtonVariant.ghost,
                  onPressed: () => ref.read(assistantProvider.notifier).approveGroup(widget.groupId, {for (final p in pending) p.id}),
                ),
                GradientButton(
                  label: selected == pending.length ? 'Accept all' : 'Accept $selected',
                  compact: true,
                  onPressed: selected == 0
                      ? null
                      : () {
                          HapticFeedback.mediumImpact();
                          ref.read(assistantProvider.notifier).approveGroup(widget.groupId, {..._excluded});
                        },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Renders a list of proposal ids as single cards or group cards.
class ProposalsBlock extends ConsumerWidget {
  const ProposalsBlock({super.key, required this.ids});

  final List<String> ids;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(assistantProvider);
    final seenGroups = <String>{};
    final children = <Widget>[];
    for (final id in ids) {
      final p = s.proposal(id);
      if (p == null) continue;
      if (p.groupId != null) {
        if (seenGroups.add(p.groupId!)) children.add(GroupApprovalCard(groupId: p.groupId!));
      } else {
        children.add(ApprovalCard(proposalId: id));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (final c in children) Padding(padding: const EdgeInsets.only(top: Space.sm), child: c)],
    );
  }
}

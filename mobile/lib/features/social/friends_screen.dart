import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/widgets/widgets.dart';
import '../../data/schedule.dart';
import '../../data/social/social_store.dart';
import '../../data/stores.dart';
import '../../shared/schedule_picker.dart';

/// Friends and groups. Friends only see habits you mark "Share with friends".
class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen> {
  late int _tab = widget.initialTab;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(socialProvider.notifier).load());
  }

  void _toast(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final live = ref.watch(authProvider.select((a) => a.live));
    final s = ref.watch(socialProvider);
    return Scaffold(
      backgroundColor: LifeColors.bg,
      body: Stack(
        children: [
          const Positioned.fill(child: AmbientBackground(mode: AmbientMode.growth)),
          SafeArea(
            child: RefreshIndicator(
              onRefresh: () => ref.read(socialProvider.notifier).load(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(Space.screen, Space.lg, Space.screen, 80),
                children: [
                  Row(children: [IconGlassButton(icon: Icons.arrow_back_rounded, semanticLabel: 'Back', onPressed: () => context.pop())]),
                  const SizedBox(height: Space.lg),
                  Text('Friends', style: LifeText.display),
                  Text('Only habits you share are visible', style: LifeText.caption),
                  const SizedBox(height: Space.xl),
                  if (!live)
                    const GlassCard(
                      child: EmptyState(
                        icon: LucideIcons.users,
                        title: 'Sign in to add friends',
                        message: 'Friends and groups need an account; sample data stays on this phone.',
                      ),
                    )
                  else ...[
                    SegmentedGlass(segments: const ['Friends', 'Groups'], index: _tab, onChanged: (i) => setState(() => _tab = i)),
                    const SizedBox(height: Space.lg),
                    if (s.error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Space.md),
                        child: Text(s.error!, style: LifeText.caption.copyWith(color: LifeColors.danger)),
                      ),
                    if (!s.loaded && s.error == null)
                      const Padding(padding: EdgeInsets.all(Space.xxl), child: Center(child: CircularProgressIndicator()))
                    else if (_tab == 0)
                      _FriendsTab(state: s, toast: _toast)
                    else
                      _GroupsTab(state: s, toast: _toast),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- friends

class _FriendsTab extends ConsumerWidget {
  const _FriendsTab({required this.state, required this.toast});

  final SocialState state;
  final void Function(String) toast;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final social = ref.read(socialProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CodeCard(
          label: 'Your friend code',
          code: state.friendCode ?? '…',
          shareText: 'Add me on LifeOS: my friend code is ${state.friendCode}',
          action: 'Add friend',
          onAction: () => _askCode(context, title: 'Add a friend', hint: 'Their friend code', submit: social.addFriend, toast: toast),
        ),
        if (state.incoming.isNotEmpty) ...[
          const SectionHeader(title: 'Requests'),
          for (final p in state.incoming)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: GlassCard(
                padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
                child: Row(
                  children: [
                    _Avatar(p),
                    const SizedBox(width: Space.md),
                    Expanded(child: Text('${p.name} wants to be friends', style: LifeText.body)),
                    IconGlassButton(icon: LucideIcons.x, size: 36, semanticLabel: 'Decline', onPressed: () => social.remove(p.id)),
                    const SizedBox(width: Space.xs),
                    IconGlassButton(icon: LucideIcons.check, size: 36, semanticLabel: 'Accept', onPressed: () => social.accept(p.id)),
                  ],
                ),
              ),
            ),
        ],
        if (state.outgoing.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: Space.sm),
            child: Text('Waiting for ${state.outgoing.map((p) => p.name).join(', ')} to accept', style: LifeText.caption),
          ),
        const SectionHeader(title: 'Today'),
        if (state.feed.isEmpty)
          const GlassCard(
            child: EmptyState(
              icon: LucideIcons.userPlus,
              title: 'No friends yet',
              message: 'Share your code. Then open a habit and turn on “Share with friends”.',
            ),
          ),
        for (final f in state.feed)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.cardGap),
            child: _FriendCard(feed: f, toast: toast),
          ),
      ],
    );
  }
}

class _FriendCard extends ConsumerWidget {
  const _FriendCard({required this.feed, required this.toast});

  final FriendFeed feed;
  final void Function(String) toast;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = feed.person;
    return GlassCard(
      onLongPress: () async {
        final ok = await showGlassConfirm(context, title: 'Remove ${p.name}?', message: 'You’ll stop seeing each other’s shared habits.', confirmLabel: 'Remove');
        if (ok) await ref.read(socialProvider.notifier).remove(p.id);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _Avatar(p),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name, style: LifeText.bodyStrong, overflow: TextOverflow.ellipsis),
                    Text('Level ${p.level} · ${p.rank}', style: LifeText.mono.copyWith(fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
          if (feed.habits.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Space.md),
              child: Text('Hasn’t shared any habits yet.', style: LifeText.caption),
            ),
          for (final h in feed.habits)
            Padding(
              padding: const EdgeInsets.only(top: Space.md),
              child: Row(
                children: [
                  Icon(h.doneToday ? LucideIcons.circleCheck : LucideIcons.circle, size: 18, color: h.doneToday ? LifeColors.mint : LifeColors.text3),
                  const SizedBox(width: Space.sm),
                  Expanded(child: Text(h.title, style: LifeText.body, overflow: TextOverflow.ellipsis)),
                  if (h.streak > 0) ...[
                    const Icon(LucideIcons.flame, size: 14, color: LifeColors.amber),
                    const SizedBox(width: 2),
                    Text('${h.streak}${h.unit == 'week' ? 'w' : 'd'}', style: LifeText.mono),
                    const SizedBox(width: Space.sm),
                  ],
                  _ReactButton(
                    onReact: (kind) async {
                      final err = await ref.read(socialProvider.notifier).react(p.id, kind, habitId: h.id);
                      toast(err ?? (kind == 'nudge' ? 'Nudged ${p.name}' : 'Sent to ${p.name}'));
                    },
                    canNudge: !h.doneToday,
                  ),
                ],
              ),
            ),
          if (feed.badges.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Space.md),
              child: Row(
                children: [
                  const Icon(LucideIcons.trophy, size: 14, color: LifeColors.amber),
                  const SizedBox(width: Space.xs),
                  Expanded(child: Text('Unlocked ${feed.badges.join(', ')}', style: LifeText.caption, overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 🔥 👏 💪 cheers, plus "nudge" when they haven't done it yet today.
class _ReactButton extends StatelessWidget {
  const _ReactButton({required this.onReact, required this.canNudge});

  final void Function(String kind) onReact;
  final bool canNudge;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
        tooltip: 'Cheer',
        color: LifeColors.surfaceHigh,
        icon: const Icon(LucideIcons.partyPopper, size: 18, color: LifeColors.lilac),
        onSelected: onReact,
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'fire', child: Text('🔥  Fire')),
          const PopupMenuItem(value: 'clap', child: Text('👏  Clap')),
          const PopupMenuItem(value: 'strong', child: Text('💪  Keep going')),
          if (canNudge) const PopupMenuItem(value: 'nudge', child: Text('👋  Nudge')),
        ],
      );
}

// ---------------------------------------------------------------- groups

class _GroupsTab extends ConsumerWidget {
  const _GroupsTab({required this.state, required this.toast});

  final SocialState state;
  final void Function(String) toast;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final social = ref.read(socialProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: GradientButton(
                label: 'New group',
                icon: LucideIcons.plus,
                expand: true,
                onPressed: () => _askCode(context, title: 'New group', hint: 'Name, e.g. DSA squad', submit: social.createGroup, toast: toast, upper: false),
              ),
            ),
            const SizedBox(width: Space.sm),
            Expanded(
              child: GradientButton(
                label: 'Join with code',
                variant: ButtonVariant.glass,
                expand: true,
                onPressed: () => _askCode(context, title: 'Join a group', hint: 'Group code', submit: social.joinGroup, toast: toast),
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.lg),
        if (state.groups.isEmpty)
          const GlassCard(
            child: EmptyState(
              icon: LucideIcons.usersRound,
              title: 'No groups yet',
              message: 'Make one, add a habit like “2 DSA problems a day”, and share the code.',
            ),
          ),
        for (final g in state.groups)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.cardGap),
            child: GroupCard(group: g, myId: state.myId, toast: toast),
          ),
      ],
    );
  }
}

class GroupCard extends ConsumerWidget {
  const GroupCard({super.key, required this.group, required this.myId, required this.toast, this.compact = false});

  final Group group;
  final String? myId;
  final void Function(String) toast;
  final bool compact; // inside the Habits tab: no admin actions

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final social = ref.read(socialProvider.notifier);
    final names = {for (final m in group.members) m.id: m};
    return GlassCard(
      tint: LifeColors.iris,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const IconChip(icon: LucideIcons.usersRound, color: LifeColors.iris, size: 36),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(group.name, style: LifeText.bodyStrong, overflow: TextOverflow.ellipsis),
                    Text('${group.members.length} member${group.members.length == 1 ? '' : 's'}', style: LifeText.caption),
                  ],
                ),
              ),
              if (!compact)
                PopupMenuButton<String>(
                  color: LifeColors.surfaceHigh,
                  icon: const Icon(LucideIcons.ellipsisVertical, size: 18, color: LifeColors.text2),
                  onSelected: (v) async {
                    if (v == 'share') {
                      await SharePlus.instance.share(ShareParams(text: 'Join my LifeOS group “${group.name}” with code ${group.inviteCode}'));
                    } else if (v == 'habit') {
                      if (context.mounted) await _addGroupHabit(context, ref, group.id, toast);
                    } else if (v == 'leave') {
                      final ok = await showGlassConfirm(context, title: 'Leave ${group.name}?', message: 'Your check-ins stay with the group.', confirmLabel: 'Leave');
                      if (ok) toast(await social.leaveGroup(group.id) ?? 'Left ${group.name}');
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'share', child: Text('Invite · code ${group.inviteCode}')),
                    const PopupMenuItem(value: 'habit', child: Text('Add a group habit')),
                    const PopupMenuItem(value: 'leave', child: Text('Leave group')),
                  ],
                ),
            ],
          ),
          if (group.habits.isEmpty && !compact)
            Padding(
              padding: const EdgeInsets.only(top: Space.md),
              child: GradientButton(
                label: 'Add a group habit',
                icon: LucideIcons.plus,
                variant: ButtonVariant.glass,
                compact: true,
                onPressed: () => _addGroupHabit(context, ref, group.id, toast),
              ),
            ),
          for (final h in group.habits)
            Padding(
              padding: const EdgeInsets.only(top: Space.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(h.title, style: LifeText.body, overflow: TextOverflow.ellipsis),
                            Text(
                              '${Schedule.fromRRule(h.rule, target: h.target).label} · '
                              '${h.streak > 0 ? '🔥 ${h.streak} together' : 'Start the streak'}',
                              style: LifeText.mono.copyWith(fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      if (myId != null)
                        Pressable(
                          semanticLabel: '${h.title} today',
                          onTap: () async {
                            HapticFeedback.lightImpact();
                            final err = await social.checkin(h.id, !h.doneToday.contains(myId));
                            if (err != null) toast(err);
                          },
                          child: AnimatedCheck(checked: h.doneToday.contains(myId), color: LifeColors.mint, size: 30),
                        ),
                    ],
                  ),
                  const SizedBox(height: Space.sm),
                  // Who's done today
                  Wrap(
                    spacing: Space.xs,
                    runSpacing: Space.xs,
                    children: [
                      for (final m in group.members)
                        Tooltip(
                          message: names[m.id]?.name ?? '',
                          child: Opacity(
                            opacity: h.doneToday.contains(m.id) ? 1 : 0.35,
                            child: _Avatar(m, size: 26, done: h.doneToday.contains(m.id)),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

Future<void> _addGroupHabit(BuildContext context, WidgetRef ref, String groupId, void Function(String) toast) {
  final title = TextEditingController();
  var schedule = Schedule.daily;
  return showGlassSheet<void>(
    context,
    title: 'Group habit',
    builder: (sheet) => StatefulBuilder(
      builder: (sheet, setSheet) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(controller: title, autofocus: true, decoration: const InputDecoration(hintText: 'e.g. Solve 2 DSA problems')),
          const SizedBox(height: Space.md),
          SchedulePicker(forHabit: true, value: schedule, onChanged: (s) => setSheet(() => schedule = s)),
          const SizedBox(height: Space.lg),
          GradientButton(
            label: 'Add for everyone',
            expand: true,
            onPressed: () async {
              if (title.text.trim().isEmpty) return;
              Navigator.of(sheet).pop();
              final err = await ref
                  .read(socialProvider.notifier)
                  .addGroupHabit(groupId, title.text.trim(), schedule.toRRule() ?? 'FREQ=DAILY', schedule.target);
              if (err != null) toast(err);
            },
          ),
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------- shared bits

class _Avatar extends StatelessWidget {
  const _Avatar(this.p, {this.size = 40, this.done = false});

  final Person p;
  final double size;
  final bool done;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(colors: [Color(0xFFFFB38A), LifeColors.rose]),
          border: done ? Border.all(color: LifeColors.mint, width: 2) : null,
        ),
        child: Text(p.initial, style: LifeText.label.copyWith(color: LifeColors.onLight, fontSize: size * 0.4)),
      );
}

class _CodeCard extends StatelessWidget {
  const _CodeCard({required this.label, required this.code, required this.shareText, required this.action, required this.onAction});

  final String label, code, shareText, action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(label, style: LifeText.eyebrow),
            const SizedBox(height: Space.xs),
            Row(
              children: [
                Expanded(child: SelectableText(code, style: LifeText.stat.copyWith(letterSpacing: 3))),
                IconGlassButton(
                  icon: LucideIcons.copy,
                  size: 38,
                  semanticLabel: 'Copy code',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
                  },
                ),
                const SizedBox(width: Space.xs),
                IconGlassButton(
                  icon: LucideIcons.share2,
                  size: 38,
                  semanticLabel: 'Share code',
                  onPressed: () => SharePlus.instance.share(ShareParams(text: shareText)),
                ),
              ],
            ),
            const SizedBox(height: Space.md),
            GradientButton(label: action, icon: LucideIcons.userPlus, variant: ButtonVariant.glass, expand: true, onPressed: onAction),
          ],
        ),
      );
}

Future<void> _askCode(
  BuildContext context, {
  required String title,
  required String hint,
  required Future<String?> Function(String) submit,
  required void Function(String) toast,
  bool upper = true,
}) {
  final c = TextEditingController();
  return showGlassSheet<void>(
    context,
    title: title,
    builder: (sheet) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: c,
          autofocus: true,
          textCapitalization: upper ? TextCapitalization.characters : TextCapitalization.sentences,
          decoration: InputDecoration(hintText: hint),
        ),
        const SizedBox(height: Space.lg),
        GradientButton(
          label: 'Continue',
          expand: true,
          onPressed: () async {
            if (c.text.trim().isEmpty) return;
            Navigator.of(sheet).pop();
            final err = await submit(c.text.trim());
            if (err != null) toast(err);
          },
        ),
      ],
    ),
  );
}

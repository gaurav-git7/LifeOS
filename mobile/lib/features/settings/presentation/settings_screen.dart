import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/routing/routes.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/stores.dart';
import '../../../data/reminders/reminder_service.dart';
import '../../../data/sync/sync_engine.dart';

/// Settings. See docs/UI_UX.md §9.6.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final prefs = ref.watch(prefsProvider);
    final motion = ref.watch(motionSettingsProvider);
    final level = ref.watch(progressionProvider).info;
    final set = ref.read(prefsProvider.notifier).update;

    return Scaffold(
      backgroundColor: LifeColors.bg,
      body: Stack(
        children: [
          const Positioned.fill(child: AmbientBackground(mode: AmbientMode.plan)),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(Space.screen, Space.lg, Space.screen, 60),
              children: [
                Row(children: [IconGlassButton(icon: Icons.arrow_back_rounded, semanticLabel: 'Back', onPressed: () => context.pop())]),
                const SizedBox(height: Space.lg),
                Text('Settings', style: LifeText.display),
                const SizedBox(height: Space.xl),

                // profile
                GlassCard(
                  onTap: () => _rename(context, ref, auth.name),
                  child: Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(colors: [Color(0xFFFFB38A), LifeColors.rose]),
                        ),
                        alignment: Alignment.center,
                        child: Text(auth.name.isEmpty ? '?' : auth.name[0].toUpperCase(),
                            style: LifeText.h2.copyWith(color: LifeColors.onLight)),
                      ),
                      const SizedBox(width: Space.lg),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(auth.name, style: LifeText.h2),
                            Text(auth.email, style: LifeText.caption),
                            const SizedBox(height: 2),
                            Text('Level ${level.level} · ${level.rank}', style: LifeText.mono.copyWith(color: LifeColors.lilac)),
                          ],
                        ),
                      ),
                      const Icon(LucideIcons.pencil, size: 16, color: LifeColors.text3),
                    ],
                  ),
                ),

                _Section('Reviews & notifications', [
                  _SwitchRow(
                    icon: LucideIcons.bell,
                    color: LifeColors.coral,
                    title: 'Notifications',
                    value: prefs.notifications,
                    onChanged: (v) {
                      set((p) => p.copyWith(notifications: v));
                      if (v) ref.read(reminderServiceProvider).requestPermission();
                    },
                  ),
                  if (prefs.notifications) const _ReminderRows(),
                  _SwitchRow(
                    icon: LucideIcons.sunset,
                    color: LifeColors.amber,
                    title: 'Daily review',
                    subtitle: 'Every evening',
                    value: prefs.dailyReview,
                    onChanged: (v) => set((p) => p.copyWith(dailyReview: v)),
                  ),
                  _NavRow(
                    icon: LucideIcons.clock,
                    color: LifeColors.sky,
                    title: 'Review time',
                    trailing: prefs.reviewTime.format(context),
                    onTap: () async {
                      final t = await showTimePicker(context: context, initialTime: prefs.reviewTime);
                      if (t != null) set((p) => p.copyWith(reviewTime: t));
                    },
                  ),
                  _SwitchRow(
                    icon: LucideIcons.calendarCheck,
                    color: LifeColors.mint,
                    title: 'Weekly review',
                    subtitle: 'Sunday evenings',
                    value: prefs.weeklyReview,
                    onChanged: (v) => set((p) => p.copyWith(weeklyReview: v)),
                  ),
                  _SwitchRow(
                    icon: LucideIcons.moon,
                    color: LifeColors.iris,
                    title: 'Quiet hours',
                    subtitle: '22:30 – 07:00 · task and habit times still ring',
                    value: prefs.quietHours,
                    onChanged: (v) => set((p) => p.copyWith(quietHours: v)),
                  ),
                ]),

                _Section('Goals', [
                  _NavRow(
                    icon: LucideIcons.timer,
                    color: LifeColors.mint,
                    title: 'Daily study goal',
                    trailing: formatMinutes(prefs.studyGoalMinutes.toDouble()),
                    onTap: () => showGlassSheet<void>(
                      context,
                      title: 'Daily study goal',
                      builder: (sheet) => Wrap(
                        spacing: Space.sm,
                        runSpacing: Space.sm,
                        children: [
                          for (final m in const [30, 45, 60, 90, 120, 180])
                            GlassChip(
                              data: FilterChipData(formatMinutes(m.toDouble())),
                              selected: prefs.studyGoalMinutes == m,
                              onTap: () {
                                set((p) => p.copyWith(studyGoalMinutes: m));
                                Navigator.of(sheet).pop();
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                ]),

                _Section('Assistant & privacy', [
                  _SwitchRow(
                    icon: LucideIcons.sparkles,
                    color: LifeColors.iris,
                    title: 'Assistant',
                    subtitle: 'Chat, reviews and suggestions',
                    value: prefs.aiEnabled,
                    onChanged: (v) => set((p) => p.copyWith(aiEnabled: v)),
                  ),
                  _NavRow(
                    icon: LucideIcons.brain,
                    color: LifeColors.lilac,
                    title: 'Memory',
                    trailing: prefs.aiMemory ? 'On' : 'Off',
                    onTap: () => context.push(Routes.memories),
                  ),
                  _SwitchRow(
                    icon: LucideIcons.smile,
                    color: LifeColors.rose,
                    title: 'Use mood in reviews',
                    subtitle: 'Sends mood scores to the AI',
                    value: prefs.moodAi,
                    onChanged: (v) => set((p) => p.copyWith(moodAi: v)),
                  ),
                  _SwitchRow(
                    icon: LucideIcons.notebookPen,
                    color: LifeColors.rose,
                    title: 'Let AI read journal',
                    subtitle: 'Only entries you unlock',
                    value: prefs.journalAi,
                    onChanged: (v) => set((p) => p.copyWith(journalAi: v)),
                  ),
                  _NavRow(
                    icon: LucideIcons.wallet,
                    color: LifeColors.amber,
                    title: 'Daily AI budget',
                    trailing: '\$${prefs.dailyBudget.toStringAsFixed(2)}',
                    onTap: () => _budget(context, ref, prefs.dailyBudget),
                  ),
                  const _InfoRow(text: 'Today: 3 AI calls · \$0.004 · well within budget'),
                ]),

                _Section('Appearance', [
                  _SwitchRow(
                    icon: LucideIcons.activity,
                    color: LifeColors.mint,
                    title: 'Reduce motion',
                    subtitle: 'Calmer transitions, no background animation',
                    value: motion.reduceMotion,
                    onChanged: ref.read(motionSettingsProvider.notifier).setReduceMotion,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: Space.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Background animation', style: LifeText.eyebrow),
                        const SizedBox(height: Space.sm),
                        SegmentedGlass(
                          segments: const ['Off', 'Low', 'Normal'],
                          index: motion.ambient.index,
                          onChanged: (i) => ref.read(motionSettingsProvider.notifier).setAmbient(AmbientIntensity.values[i]),
                        ),
                      ],
                    ),
                  ),
                ]),

                _Section('Security', [
                  _SwitchRow(
                    icon: LucideIcons.fingerprint,
                    color: LifeColors.sky,
                    title: 'App lock',
                    subtitle: 'Fingerprint when opening LifeOS',
                    value: prefs.appLock,
                    onChanged: (v) => set((p) => p.copyWith(appLock: v)),
                  ),
                  _SwitchRow(
                    icon: LucideIcons.lockKeyhole,
                    color: LifeColors.rose,
                    title: 'Lock journal',
                    value: prefs.journalLock,
                    onChanged: (v) => set((p) => p.copyWith(journalLock: v)),
                  ),
                  _NavRow(
                    icon: LucideIcons.keyRound,
                    color: LifeColors.text2,
                    title: 'Change password',
                    onTap: () => _toast(context, 'Available once the app is connected to your account.'),
                  ),
                  _NavRow(
                    icon: LucideIcons.monitorSmartphone,
                    color: LifeColors.text2,
                    title: 'Sign out of all devices',
                    onTap: () => _toast(context, 'Available once the app is connected to your account.'),
                  ),
                ]),

                _Section('Your data', [
                  if (auth.live) const _SyncRow(),
                  _NavRow(
                    icon: LucideIcons.download,
                    color: LifeColors.mint,
                    title: 'Export everything',
                    trailing: 'JSON',
                    onTap: () => _toast(context, 'Export starts once the app is connected to your account.'),
                  ),
                  _NavRow(
                    icon: LucideIcons.trash2,
                    color: LifeColors.danger,
                    title: 'Delete account',
                    danger: true,
                    onTap: () => _confirmDelete(context, ref),
                  ),
                ]),

                _Section('About', [
                  _InfoRow(text: 'LifeOS 0.1.0 · ${auth.live ? 'synced with your account' : 'sample data on this phone'}'),
                  if (kDebugMode)
                    _NavRow(
                      icon: LucideIcons.layoutGrid,
                      color: LifeColors.text2,
                      title: 'Component gallery',
                      onTap: () => context.push(Routes.gallery),
                    ),
                ]),

                const SizedBox(height: Space.section),
                GradientButton(
                  label: auth.live ? 'Sign out' : 'Leave sample mode',
                  icon: LucideIcons.logOut,
                  variant: ButtonVariant.glass,
                  expand: true,
                  onPressed: () => ref.read(authProvider.notifier).signOut(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _toast(BuildContext context, String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  void _rename(BuildContext context, WidgetRef ref, String current) {
    final c = TextEditingController(text: current);
    showGlassSheet<void>(
      context,
      title: 'Your name',
      builder: (sheet) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(controller: c, autofocus: true, textCapitalization: TextCapitalization.words),
          const SizedBox(height: Space.lg),
          GradientButton(
            label: 'Save',
            expand: true,
            onPressed: () {
              if (c.text.trim().isNotEmpty) ref.read(authProvider.notifier).rename(c.text.trim());
              Navigator.of(sheet).pop();
            },
          ),
        ],
      ),
    );
  }

  void _budget(BuildContext context, WidgetRef ref, double current) {
    showGlassSheet<void>(
      context,
      title: 'Daily AI budget',
      builder: (sheet) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('When today’s AI spend reaches this, the assistant pauses until tomorrow. Everything else keeps working.',
              style: LifeText.body.copyWith(color: LifeColors.text2)),
          const SizedBox(height: Space.lg),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              for (final v in [0.05, 0.10, 0.25, 0.50])
                GlassChip(
                  data: FilterChipData('\$${v.toStringAsFixed(2)}'),
                  selected: v == current,
                  onTap: () {
                    ref.read(prefsProvider.notifier).update((p) => p.copyWith(dailyBudget: v));
                    Navigator.of(sheet).pop();
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showGlassConfirm(
      context,
      title: 'Delete your account?',
      message: 'All tasks, goals, journal entries and AI memory are permanently deleted. This can’t be undone.',
      confirmLabel: 'Delete account',
      icon: LucideIcons.userX,
    );
    if (!ok) return;
    final err = await ref.read(authProvider.notifier).deleteAccount();
    if (err != null && context.mounted) _toast(context, err);
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.children);

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: Space.section),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(title: title),
          GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.xs),
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const Divider(height: 1, indent: 44),
                  children[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.sm),
        child: Row(
          children: [
            IconChip(icon: icon, color: color, size: 30),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: LifeText.bodyStrong),
                  if (subtitle != null) Text(subtitle!, style: LifeText.caption),
                ],
              ),
            ),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      );
}

class _NavRow extends StatelessWidget {
  const _NavRow({required this.icon, required this.color, required this.title, this.trailing, this.onTap, this.danger = false});

  final IconData icon;
  final Color color;
  final String title;
  final String? trailing;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        scale: 0.99,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.md),
          child: Row(
            children: [
              IconChip(icon: icon, color: color, size: 30),
              const SizedBox(width: Space.md),
              Expanded(child: Text(title, style: LifeText.bodyStrong.copyWith(color: danger ? LifeColors.danger : null))),
              if (trailing != null) Text(trailing!, style: LifeText.mono),
              const SizedBox(width: Space.xs),
              const Icon(LucideIcons.chevronRight, size: 16, color: LifeColors.text3),
            ],
          ),
        ),
      );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.md),
        child: Text(text, style: LifeText.caption),
      );
}

/// Sync state + "Sync now".
class _SyncRow extends ConsumerWidget {
  const _SyncRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(syncStatusProvider);
    final status = switch (s.phase) {
      SyncPhase.syncing => 'Syncing…',
      SyncPhase.offline => s.pending > 0 ? 'Offline · ${s.pending} waiting' : 'Offline',
      SyncPhase.error => s.message ?? 'Sync problem',
      SyncPhase.idle => s.pending > 0
          ? '${s.pending} waiting'
          : (s.lastSync == null ? 'Not synced yet' : 'Synced ${DateFormat('HH:mm').format(s.lastSync!)}'),
    };
    return _NavRow(
      icon: LucideIcons.refreshCw,
      color: s.phase == SyncPhase.error ? LifeColors.danger : LifeColors.sky,
      title: 'Sync now',
      trailing: status,
      onTap: () => ref.read(syncEngineProvider).syncNow(),
    );
  }
}

/// Permission state, exact timing and a test button for phone reminders.
class _ReminderRows extends ConsumerWidget {
  const _ReminderRows();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(reminderStatusProvider);
    final service = ref.read(reminderServiceProvider);
    return Column(
      children: [
        if (s.permitted == false)
          _NavRow(
            icon: LucideIcons.bellOff,
            color: LifeColors.danger,
            title: 'Notifications are blocked',
            trailing: 'Allow',
            onTap: () async {
              final ok = await service.requestPermission();
              if (!ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Turn them on in Android Settings → Apps → LifeOS → Notifications.'),
                ));
              }
            },
          ),
        _NavRow(
          icon: LucideIcons.alarmClock,
          color: LifeColors.amber,
          title: 'On-the-minute reminders',
          trailing: s.exact == true ? 'On' : 'Turn on',
          onTap: service.requestExact,
        ),
        _NavRow(
          icon: LucideIcons.bellRing,
          color: LifeColors.lilac,
          title: 'Send a test notification',
          trailing: s.scheduled > 0 ? '${s.scheduled} planned' : null,
          onTap: service.test,
        ),
      ],
    );
  }
}

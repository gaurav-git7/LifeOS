import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/widgets/widgets.dart';
import '../data/security/app_lock.dart';
import '../data/stores.dart';

/// Covers the whole app while it's locked.
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate> {
  bool _prompted = false;

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(prefsProvider.select((p) => p.appLock));
    final unlocked = ref.watch(lockProvider.select((l) => l.appUnlocked));
    final signedIn = ref.watch(authProvider.select((a) => a.signedIn));
    final locked = enabled && !unlocked && signedIn;
    if (locked && !_prompted) {
      _prompted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(lockProvider.notifier).unlockApp());
    }
    if (!locked) _prompted = false;
    return Stack(
      children: [
        widget.child,
        if (locked)
          Positioned.fill(
            child: _LockedView(
              title: 'LifeOS is locked',
              onUnlock: () => ref.read(lockProvider.notifier).unlockApp(),
            ),
          ),
      ],
    );
  }
}

/// Journal tab content while the journal lock is on.
class JournalLockedView extends ConsumerWidget {
  const JournalLockedView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      _LockedView(title: 'Your journal is locked', onUnlock: () => ref.read(lockProvider.notifier).unlockJournal(), transparent: true);
}

class _LockedView extends StatelessWidget {
  const _LockedView({required this.title, required this.onUnlock, this.transparent = false});

  final String title;
  final VoidCallback onUnlock;
  final bool transparent;

  @override
  Widget build(BuildContext context) {
    final content = Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.screen),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const IconChip(icon: LucideIcons.lockKeyhole, color: LifeColors.lilac, size: 64),
            const SizedBox(height: Space.lg),
            Text(title, textAlign: TextAlign.center, style: LifeText.titleSerif.copyWith(fontSize: 28)),
            const SizedBox(height: Space.sm),
            Text('Use your fingerprint, face or phone PIN.', textAlign: TextAlign.center, style: LifeText.body.copyWith(color: LifeColors.text2)),
            const SizedBox(height: Space.xl),
            GradientButton(label: 'Unlock', icon: LucideIcons.fingerprint, onPressed: onUnlock),
          ],
        ),
      ),
    );
    if (transparent) return content;
    return Material(
      color: LifeColors.bg,
      child: Stack(children: [const Positioned.fill(child: AmbientBackground(mode: AmbientMode.home)), content]),
    );
  }
}

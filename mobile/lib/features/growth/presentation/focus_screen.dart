import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/widgets/widgets.dart';
import '../../../data/focus/focus_controller.dart';
import '../../../data/stores.dart';
import '../../../data/system_channel.dart';

/// Full-screen focus timer. Keeps running when you leave the screen or the app
/// (countdown notification); finishing records a study session (+XP).
/// See docs/UI_UX.md §9.3 (Study).
class FocusScreen extends ConsumerStatefulWidget {
  const FocusScreen({super.key, this.topicId});

  final String? topicId;

  @override
  ConsumerState<FocusScreen> createState() => _FocusScreenState();
}

class _FocusScreenState extends ConsumerState<FocusScreen> {
  static const _presets = [25, 50, 90];
  Timer? _tick;
  int _burst = 0;
  bool _finishing = false;

  FocusController get _ctl => ref.read(focusProvider.notifier);

  @override
  void initState() {
    super.initState();
    final f = ref.read(focusProvider);
    if (!f.active) {
      // New session: preselect the topic (from a roadmap) or the first skill.
      final learning = ref.read(learningProvider);
      String? skillId, topicTitle;
      if (widget.topicId != null) {
        for (final p in learning.paths) {
          final t = p.topics.where((t) => t.id == widget.topicId).firstOrNull;
          if (t != null) {
            topicTitle = t.title;
            skillId = p.skillId;
          }
        }
      }
      skillId ??= f.skillId ?? learning.skills.firstOrNull?.id;
      WidgetsBinding.instance.addPostFrameCallback((_) => _ctl.setup(
            skillId: skillId,
            topicId: widget.topicId,
            label: topicTitle ?? learning.skill(skillId)?.name,
          ));
    }
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      final s = ref.read(focusProvider);
      if (s.running && s.elapsed >= s.total) _finish();
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _toggle() {
    HapticFeedback.lightImpact();
    ref.read(focusProvider).running ? _ctl.pause() : _ctl.start();
  }

  Future<void> _toggleDnd(bool on) async {
    if (on && !await SystemChannel.hasDndAccess()) {
      if (!mounted) return;
      final go = await showGlassConfirm(
        context,
        title: 'Allow Do Not Disturb?',
        message: 'Android asks you to allow LifeOS once. It turns DND on while you focus and off when the session ends.',
        confirmLabel: 'Open settings',
        destructive: false,
        icon: LucideIcons.bellOff,
      );
      if (go) await SystemChannel.openDndSettings();
      return;
    }
    _ctl.setDnd(on);
  }

  void _finish() {
    if (_finishing) return;
    _finishing = true;
    final result = _ctl.finish();
    _finishing = false;
    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sessions under a minute aren’t saved.')));
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() => _burst++);
    showGlassSheet<void>(
      context,
      builder: (sheet) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Session saved', style: LifeText.titleSerif),
          const SizedBox(height: Space.sm),
          Text('${result.minutes} minutes${result.topic != null ? ' on ${result.topic}' : ''} · +${result.xp} XP',
              style: LifeText.body.copyWith(color: LifeColors.text2)),
          const SizedBox(height: Space.xl),
          GradientButton(
            label: 'Done',
            expand: true,
            onPressed: () {
              Navigator.of(sheet).pop();
              context.pop();
            },
          ),
          const SizedBox(height: Space.sm),
          GradientButton(
            label: 'Another round',
            variant: ButtonVariant.glass,
            expand: true,
            onPressed: () => Navigator.of(sheet).pop(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final f = ref.watch(focusProvider);
    final skills = ref.watch(learningProvider.select((s) => s.skills));
    final elapsed = f.elapsed;
    final remaining = (f.total - elapsed).clamp(0, f.total);
    final mm = (remaining ~/ 60).toString().padLeft(2, '0');
    final ss = (remaining % 60).toString().padLeft(2, '0');
    final size = (MediaQuery.sizeOf(context).width * 0.72).clamp(220.0, 320.0);

    return Scaffold(
      backgroundColor: LifeColors.bg,
      body: Stack(
        children: [
          const Positioned.fill(child: AmbientBackground(mode: AmbientMode.growth)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(Space.screen),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconGlassButton(icon: LucideIcons.x, semanticLabel: 'Close', onPressed: () => context.pop()),
                      const Spacer(),
                      Text('Focus', style: LifeText.titleSerif.copyWith(fontSize: 24)),
                      const Spacer(),
                      IconGlassButton(
                        icon: f.dnd ? LucideIcons.bellOff : LucideIcons.bell,
                        semanticLabel: f.dnd ? 'Do Not Disturb on' : 'Do Not Disturb off',
                        onPressed: () => _toggleDnd(!f.dnd),
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.lg),
                  if (f.topicId != null || f.active)
                    Text(f.label ?? 'Focus session', style: LifeText.title, textAlign: TextAlign.center)
                  else
                    SizedBox(
                      height: 38,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (final s in skills)
                            Padding(
                              padding: const EdgeInsets.only(right: Space.sm),
                              child: GlassChip(
                                data: FilterChipData(s.name, icon: s.icon, accent: s.color),
                                selected: s.id == f.skillId,
                                onTap: () => _ctl.setup(skillId: s.id, label: s.name),
                              ),
                            ),
                        ],
                      ),
                    ),
                  if (f.dnd)
                    Padding(
                      padding: const EdgeInsets.only(top: Space.sm),
                      child: Text('Do Not Disturb while focusing', style: LifeText.caption),
                    ),
                  const Spacer(),
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      ActivityRings(
                        size: size,
                        stroke: 16,
                        rings: [RingData(elapsed / f.total, LifeColors.mint)],
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('$mm:$ss', style: LifeText.statHero.copyWith(fontSize: 60, height: 1)),
                            const SizedBox(height: Space.sm),
                            Text(f.running ? 'Stay with it' : (elapsed > 0 ? 'Paused' : '${f.minutes}-minute session'),
                                style: LifeText.caption),
                          ],
                        ),
                      ),
                      GlowBurst(trigger: _burst, size: size + 60, color: LifeColors.mint),
                    ],
                  ),
                  const Spacer(),
                  if (!f.active)
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: Space.sm,
                      runSpacing: Space.sm,
                      children: [
                        for (final p in _presets)
                          GlassChip(
                            data: FilterChipData('$p min'),
                            selected: f.minutes == p,
                            onTap: () => _ctl.setup(minutes: p),
                          ),
                      ],
                    ),
                  const SizedBox(height: Space.xl),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconGlassButton(icon: LucideIcons.rotateCcw, size: 52, semanticLabel: 'Reset', onPressed: elapsed > 0 ? _ctl.reset : null),
                      const SizedBox(width: Space.xl),
                      Pressable(
                        onTap: _toggle,
                        scale: 0.92,
                        semanticLabel: f.running ? 'Pause' : 'Start',
                        child: Container(
                          width: 78,
                          height: 78,
                          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: LifeShadows.float),
                          child: Icon(f.running ? LucideIcons.pause : LucideIcons.play, color: LifeColors.onLight, size: 30),
                        ),
                      ),
                      const SizedBox(width: Space.xl),
                      IconGlassButton(icon: LucideIcons.check, size: 52, semanticLabel: 'Finish', onPressed: elapsed > 0 ? _finish : null),
                    ],
                  ),
                  const SizedBox(height: Space.xxl),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

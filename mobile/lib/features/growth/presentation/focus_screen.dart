import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/widgets/widgets.dart';
import '../../../data/models.dart';
import '../../../data/stores.dart';

/// Full-screen focus timer. Finishing records a study session (+XP).
/// See docs/UI_UX.md §9.3 (Study).
class FocusScreen extends ConsumerStatefulWidget {
  const FocusScreen({super.key, this.topicId});

  final String? topicId;

  @override
  ConsumerState<FocusScreen> createState() => _FocusScreenState();
}

class _FocusScreenState extends ConsumerState<FocusScreen> {
  static const _presets = [25, 50, 90];
  int _minutes = 25;
  int _elapsed = 0; // seconds
  bool _running = false;
  Timer? _timer;
  String? _skillId;
  Topic? _topic;
  int _burst = 0;

  @override
  void initState() {
    super.initState();
    final learning = ref.read(learningProvider);
    if (widget.topicId != null) {
      for (final p in learning.paths) {
        final t = p.topics.where((t) => t.id == widget.topicId).firstOrNull;
        if (t != null) {
          _topic = t;
          _skillId = p.skillId;
        }
      }
    }
    _skillId ??= learning.skills.firstOrNull?.id;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  int get _total => _minutes * 60;

  void _toggle() {
    HapticFeedback.lightImpact();
    if (_running) {
      _timer?.cancel();
      setState(() => _running = false);
      return;
    }
    setState(() => _running = true);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _elapsed++);
      if (_elapsed >= _total) _finish();
    });
  }

  void _reset() {
    _timer?.cancel();
    setState(() {
      _elapsed = 0;
      _running = false;
    });
  }

  void _finish() {
    _timer?.cancel();
    final minutes = (_elapsed / 60).round();
    setState(() => _running = false);
    if (minutes < 1) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sessions under a minute aren’t saved.')));
      return;
    }
    final skill = ref.read(learningProvider).skill(_skillId);
    final xp = ref.read(learningProvider.notifier).addSession(StudySession(
          id: newId(),
          start: DateTime.now().subtract(Duration(seconds: _elapsed)),
          minutes: minutes,
          skillId: _skillId,
          topicId: _topic?.id,
          label: _topic?.title ?? '${skill?.name ?? 'Study'} focus',
        ));
    HapticFeedback.mediumImpact();
    setState(() => _burst++);
    showGlassSheet<void>(
      context,
      builder: (sheet) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Session saved', style: LifeText.titleSerif),
          const SizedBox(height: Space.sm),
          Text('$minutes minutes${_topic != null ? ' on ${_topic!.title}' : ''} · +$xp XP',
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
            onPressed: () {
              Navigator.of(sheet).pop();
              _reset();
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final skills = ref.watch(learningProvider.select((s) => s.skills));
    final remaining = (_total - _elapsed).clamp(0, _total);
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
                      const SizedBox(width: Sizes.touch),
                    ],
                  ),
                  const SizedBox(height: Space.lg),
                  if (_topic != null)
                    Text(_topic!.title, style: LifeText.title, textAlign: TextAlign.center)
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
                                selected: s.id == _skillId,
                                onTap: _running ? null : () => setState(() => _skillId = s.id),
                              ),
                            ),
                        ],
                      ),
                    ),
                  const Spacer(),
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      ActivityRings(
                        size: size,
                        stroke: 16,
                        rings: [RingData(_elapsed / _total, LifeColors.mint)],
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('$mm:$ss', style: LifeText.statHero.copyWith(fontSize: 60, height: 1)),
                            const SizedBox(height: Space.sm),
                            Text(_running ? 'Stay with it' : (_elapsed > 0 ? 'Paused' : '$_minutes-minute session'),
                                style: LifeText.caption),
                          ],
                        ),
                      ),
                      GlowBurst(trigger: _burst, size: size + 60, color: LifeColors.mint),
                    ],
                  ),
                  const Spacer(),
                  if (_elapsed == 0)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (final p in _presets)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: GlassChip(
                              data: FilterChipData('$p min'),
                              selected: _minutes == p,
                              onTap: () => setState(() => _minutes = p),
                            ),
                          ),
                      ],
                    ),
                  const SizedBox(height: Space.xl),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconGlassButton(icon: LucideIcons.rotateCcw, size: 52, semanticLabel: 'Reset', onPressed: _elapsed > 0 ? _reset : null),
                      const SizedBox(width: Space.xl),
                      Pressable(
                        onTap: _toggle,
                        scale: 0.92,
                        semanticLabel: _running ? 'Pause' : 'Start',
                        child: Container(
                          width: 78,
                          height: 78,
                          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: LifeShadows.float),
                          child: Icon(_running ? LucideIcons.pause : LucideIcons.play, color: LifeColors.onLight, size: 30),
                        ),
                      ),
                      const SizedBox(width: Space.xl),
                      IconGlassButton(icon: LucideIcons.check, size: 52, semanticLabel: 'Finish', onPressed: _elapsed > 0 ? _finish : null),
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

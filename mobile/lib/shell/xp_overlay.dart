import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/widgets/widgets.dart';
import '../data/stores.dart';

/// Floating "+20 XP" pill whenever XP is gained, and a short level-up moment.
/// See docs/UI_UX.md §7.2 and §10.2.
class XpOverlay extends ConsumerStatefulWidget {
  const XpOverlay({super.key});

  @override
  ConsumerState<XpOverlay> createState() => _XpOverlayState();
}

class _XpOverlayState extends ConsumerState<XpOverlay> {
  int? _gain;
  int _tick = 0;
  Timer? _hide;
  bool _levelUp = false;
  int _burst = 0;

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<Progression>(progressionProvider, (prev, next) {
      if (prev == null) return;
      if (next.gainTick != prev.gainTick && next.lastGain > 0) {
        setState(() {
          _gain = next.lastGain;
          _tick = next.gainTick;
        });
        _hide?.cancel();
        _hide = Timer(const Duration(milliseconds: 1400), () {
          if (mounted) setState(() => _gain = null);
        });
      }
      if (next.levelUps != prev.levelUps) {
        HapticFeedback.mediumImpact();
        setState(() {
          _levelUp = true;
          _burst++;
        });
      }
    });

    final level = ref.watch(progressionProvider).info;
    final d = Motion.of(context, Motion.card);

    return Stack(
      children: [
        // +XP pill
        Positioned(
          top: MediaQuery.paddingOf(context).top + 8,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Center(
              child: AnimatedSwitcher(
                duration: d,
                switchInCurve: Motion.emphasized,
                transitionBuilder: (child, a) => FadeTransition(
                  opacity: a,
                  child: SlideTransition(
                    position: Tween(begin: const Offset(0, -0.6), end: Offset.zero).animate(a),
                    child: child,
                  ),
                ),
                child: _gain == null
                    ? const SizedBox.shrink()
                    : Container(
                        key: ValueKey(_tick),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: Radii.rPill,
                          boxShadow: LifeShadows.float,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.bolt_rounded, size: 16, color: LifeColors.iris),
                            const SizedBox(width: 4),
                            Text('+$_gain XP', style: LifeText.label.copyWith(color: LifeColors.onLight, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
              ),
            ),
          ),
        ),
        // Level up
        if (_levelUp)
          Positioned.fill(
            child: GestureDetector(
              onTap: () => setState(() => _levelUp = false),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: Motion.of(context, const Duration(milliseconds: 600)),
                curve: Motion.emphasized,
                builder: (context, t, child) => Opacity(opacity: t, child: child),
                child: ColoredBox(
                  color: const Color(0xCC07070B),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            ActivityRings(
                              size: 160,
                              stroke: 14,
                              rings: const [RingData(1, LifeColors.iris), RingData(1, LifeColors.rose), RingData(1, LifeColors.amber)],
                              child: Text('${level.level}', style: LifeText.statHero),
                            ),
                            GlowBurst(trigger: _burst, size: 260),
                          ],
                        ),
                        const SizedBox(height: Space.xl),
                        Text('Level ${level.level}', style: LifeText.display),
                        Text(level.rank, style: LifeText.titleSerifItalic.copyWith(color: LifeColors.text2)),
                        const SizedBox(height: Space.lg),
                        Text('Tap to continue', style: LifeText.caption),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

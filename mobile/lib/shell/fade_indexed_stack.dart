import 'package:flutter/material.dart';

import '../core/motion/motion.dart';

/// Like IndexedStack, but cross-fades tabs with a slight vertical shift.
/// Inactive tabs keep their state, ignore touches, and have their
/// animations paused (TickerMode). See docs/UI_UX.md §7.3.
class FadeIndexedStack extends StatelessWidget {
  const FadeIndexedStack({super.key, required this.index, required this.children});

  final int index;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final d = Motion.of(context, Motion.nav);
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < children.length; i++)
          _Tab(active: i == index, duration: d, child: children[i]),
      ],
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.active, required this.duration, required this.child});

  final bool active;
  final Duration duration;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: active ? 1 : 0,
      duration: duration,
      curve: Motion.emphasized,
      child: AnimatedSlide(
        offset: active ? Offset.zero : const Offset(0, 0.012),
        duration: duration,
        curve: Motion.emphasized,
        child: IgnorePointer(
          ignoring: !active,
          child: ExcludeSemantics(
            excluding: !active,
            child: TickerMode(enabled: active, child: child),
          ),
        ),
      ),
    );
  }
}

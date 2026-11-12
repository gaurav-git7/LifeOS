import 'package:flutter/material.dart';

import 'motion.dart';

/// Fades a child in with a small upward rise, delayed by its [index].
/// Plays once, on first build. Max 6 steps of delay so long lists don't lag.
class StaggeredEntry extends StatefulWidget {
  const StaggeredEntry({
    super.key,
    required this.index,
    required this.child,
    this.rise = 16,
    this.baseDelay = Duration.zero,
  });

  final int index;
  final Widget child;
  final double rise;
  final Duration baseDelay;

  @override
  State<StaggeredEntry> createState() => _StaggeredEntryState();
}

class _StaggeredEntryState extends State<StaggeredEntry>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: Motion.card);
  late final Animation<double> _t =
      CurvedAnimation(parent: _c, curve: Motion.standard);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MotionScope.reducedOf(context)) {
      _c.value = 1;
      return;
    }
    final delay = widget.baseDelay + Motion.stagger * widget.index.clamp(0, 6);
    Future.delayed(delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: _t.value,
        child: Transform.translate(
          offset: Offset(0, (1 - _t.value) * widget.rise),
          child: child,
        ),
      ),
    );
  }
}

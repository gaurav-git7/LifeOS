import 'package:flutter/widgets.dart';

/// Swipe left/right to move between tabs.
///
/// Can be nested: a screen with sub-tabs (Plan, Growth, Assistant) handles the
/// swipe first; when it's already on its first/last sub-tab it returns false
/// and the swipe moves to the next main tab instead. Horizontal scrollers
/// inside (chip rows, the week strip) keep their own gestures.
class SwipeNav extends StatelessWidget {
  const SwipeNav({super.key, required this.onSwipe, required this.child});

  /// [direction] is +1 for "next" (swipe left) and -1 for "previous".
  /// Return true if handled.
  final bool Function(int direction) onSwipe;
  final Widget child;

  static const _minVelocity = 350.0;

  @override
  Widget build(BuildContext context) {
    final parent = context.findAncestorWidgetOfExactType<_SwipeScope>();
    bool handle(int direction) => onSwipe(direction) || (parent?.handle(direction) ?? false);
    return _SwipeScope(
      handle: handle,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v.abs() >= _minVelocity) handle(v < 0 ? 1 : -1);
        },
        child: child,
      ),
    );
  }
}

class _SwipeScope extends InheritedWidget {
  const _SwipeScope({required this.handle, required super.child});

  final bool Function(int direction) handle;

  @override
  bool updateShouldNotify(_SwipeScope oldWidget) => false;
}

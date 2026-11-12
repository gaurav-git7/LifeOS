import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'motion.dart';

/// Detail-page transition: fade + 24 px slide up. See docs/UI_UX.md §7.3.
CustomTransitionPage<void> lifePage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: Motion.page,
    reverseTransitionDuration: Motion.modalExit,
    transitionsBuilder: (context, animation, secondary, child) {
      if (MotionScope.reducedOf(context)) {
        return FadeTransition(opacity: animation, child: child);
      }
      final curved = CurvedAnimation(
        parent: animation,
        curve: Motion.emphasized,
        reverseCurve: Motion.exit,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.03), end: Offset.zero)
              .animate(curved),
          child: child,
        ),
      );
    },
  );
}

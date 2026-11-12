import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../motion/motion.dart';
import '../../theme/app_theme.dart';

/// Shows a liquid-glass bottom sheet with a drag handle.
Future<T?> showGlassSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  String? title,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x8C000000),
    elevation: 0,
    sheetAnimationStyle: AnimationStyle(
      duration: Motion.modal,
      reverseDuration: Motion.modalExit,
      curve: Motion.emphasized,
    ),
    builder: (context) => GlassSheet(title: title, child: builder(context)),
  );
}

class GlassSheet extends StatelessWidget {
  const GlassSheet({super.key, required this.child, this.title});

  final Widget child;
  final String? title;

  @override
  Widget build(BuildContext context) {
    const r = BorderRadius.vertical(top: Radius.circular(Radii.xl));
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ClipRRect(
        borderRadius: r,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              borderRadius: r,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xB31C1C26), Color(0xD910101A)],
              ),
              border: Border(top: BorderSide(color: Color(0x40FFFFFF))),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Space.screen, Space.md, Space.screen, Space.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 5,
                        decoration: const BoxDecoration(color: Color(0x4DFFFFFF), borderRadius: Radii.rPill),
                      ),
                    ),
                    const SizedBox(height: Space.lg),
                    if (title != null) ...[
                      Text(title!, style: LifeText.h2),
                      const SizedBox(height: Space.lg),
                    ],
                    child,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

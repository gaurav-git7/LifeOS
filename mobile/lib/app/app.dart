import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/motion/motion.dart';
import '../core/routing/router.dart';
import '../core/theme/app_theme.dart';

class LifeOSApp extends ConsumerWidget {
  const LifeOSApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final motion = ref.watch(motionSettingsProvider);

    return MaterialApp.router(
      title: 'LifeOS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      routerConfig: router,
      builder: (context, child) => MotionScope(
        reduced: motion.reduceMotion || MediaQuery.disableAnimationsOf(context),
        ambient: motion.ambient,
        // Lets every glass surface share one backdrop blur pass, so real
        // glass can be used on many cards without hurting performance.
        child: BackdropGroup(child: child!),
      ),
    );
  }
}

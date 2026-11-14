import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/motion/motion.dart';
import '../core/routing/router.dart';
import '../core/theme/app_theme.dart';
import '../data/stores.dart';
import '../data/sync/sync_engine.dart';

class LifeOSApp extends ConsumerStatefulWidget {
  const LifeOSApp({super.key});

  @override
  ConsumerState<LifeOSApp> createState() => _LifeOSAppState();
}

class _LifeOSAppState extends ConsumerState<LifeOSApp> with WidgetsBindingObserver {
  DateTime _lastSync = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back to the app: pick up changes made elsewhere (e.g. approved from a review).
    if (state != AppLifecycleState.resumed || !ref.read(authProvider).live) return;
    if (DateTime.now().difference(_lastSync) < const Duration(seconds: 30)) return;
    _lastSync = DateTime.now();
    ref.read(syncEngineProvider).syncNow();
    ref.read(assistantProvider.notifier).load();
  }

  @override
  Widget build(BuildContext context) {
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

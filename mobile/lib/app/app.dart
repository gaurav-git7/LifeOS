import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/motion/motion.dart';
import '../core/routing/router.dart';
import '../core/theme/app_theme.dart';
import '../data/stores.dart';
import '../data/focus/focus_controller.dart';
import '../data/push/push_service.dart';
import '../data/reminders/reminder_service.dart';
import '../data/security/app_lock.dart';
import '../shared/lock_views.dart';
import '../data/telemetry/crash_reporter.dart';
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
    ref.read(crashReporterProvider).install();
    // Phone reminders (no-op in tests). Ask for notification permission when someone signs in.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final reminders = ref.read(reminderServiceProvider);
      await reminders.start();
      await ref.read(pushServiceProvider).start(); // server push; after reminders (shares channels)
      if (ref.read(authProvider).signedIn) await reminders.requestPermission();
    });
    ref.listenManual(authProvider.select((a) => a.signedIn), (was, now) {
      if (now && was == false) ref.read(reminderServiceProvider).requestPermission();
      // Restores a running focus timer; one that ended while closed is saved now.
      if (now) ref.read(focusProvider);
    }, fireImmediately: true);
    ref.listenManual(authProvider.select((a) => a.live && a.signedIn), (was, now) {
      if (!now) return;
      ref.read(pushServiceProvider).registerIfSignedIn();
      ref.read(crashReporterProvider).flush();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) ref.read(lockProvider.notifier).onBackground();
    if (state == AppLifecycleState.resumed) ref.read(lockProvider.notifier).onResume();
    // A new day may have started: re-plan reminders (cheap, local).
    if (state == AppLifecycleState.resumed) {
      ref.read(reminderServiceProvider).applyPendingActions(); // Done/Tomorrow pressed while closed
      ref.read(reminderServiceProvider).schedule();
    }
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
        child: BackdropGroup(child: AppLockGate(child: child!)),
      ),
    );
  }
}

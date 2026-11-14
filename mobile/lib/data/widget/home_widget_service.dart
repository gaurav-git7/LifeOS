// Android home-screen "Today" widget. The app draws the card (rings, percent,
// top tasks) as an image whenever the day's data changes; the native widget
// (TodayWidgetProvider.kt) shows that image. Taps open the app or quick add.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:home_widget/home_widget.dart';

import '../../core/routing/router.dart';
import '../../core/routing/routes.dart';
import '../../core/theme/colors.dart';
import '../../core/widgets/glass/glass_sheet.dart';
import '../../shell/quick_add_sheet.dart';
import '../reminders/reminder_service.dart';
import '../stores.dart';

class HomeWidgetService {
  HomeWidgetService(this.ref);

  final Ref ref;
  Timer? _debounce;
  bool _started = false;
  final List<ProviderSubscription<Object?>> _subs = [];
  StreamSubscription<Uri?>? _clicks;

  static const _provider = 'com.lifeos.lifeos.TodayWidgetProvider';

  Future<void> start() async {
    if (!ReminderService.supported || _started) return;
    _started = true;
    void watch<T>(ProviderListenable<T> p) => _subs.add(ref.listen<T>(p, (_, _) => refresh()));
    watch(tasksProvider);
    watch(habitsProvider);
    watch(learningProvider.select((l) => l.sessions.length));
    watch(prefsProvider.select((p) => p.studyGoalMinutes));
    watch(authProvider.select((a) => a.signedIn));
    try {
      _handle(await HomeWidget.initiallyLaunchedFromHomeWidget());
      _clicks = HomeWidget.widgetClicked.listen(_handle);
    } catch (_) {}
    refresh();
  }

  void dispose() {
    _debounce?.cancel();
    _clicks?.cancel();
    for (final s in _subs) {
      s.close();
    }
  }

  void _handle(Uri? uri) {
    if (uri == null) return;
    Future<void>.delayed(const Duration(milliseconds: 500), () {
      ref.read(routerProvider).go(Routes.home);
      if (uri.host == 'quickadd') {
        final ctx = rootNavigatorKey.currentContext;
        if (ctx != null && ctx.mounted) showGlassSheet<void>(ctx, builder: (_) => const QuickAddSheet());
      }
    });
  }

  /// Redraw soon (changes come in bursts, e.g. after a sync).
  void refresh() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () => unawaited(_render()));
  }

  Future<void> _render() async {
    try {
      final auth = ref.read(authProvider);
      final now = DateTime.now();
      final tasks = ref.read(tasksProvider);
      final today = tasks.where((t) => t.isDueOn(now)).toList();
      final habits = ref.read(habitsProvider).where((h) => h.isDueOn(now) || h.doneOn(now)).toList();
      final study = ref.read(learningProvider).minutesOn(now);
      final goal = ref.read(prefsProvider).studyGoalMinutes;
      final open = tasks.where((t) => !t.done && (t.isDueOn(now) || t.isOverdue(now))).toList()
        ..sort((a, b) => b.priority.index.compareTo(a.priority.index));
      final data = TodayCardData(
        signedIn: auth.signedIn,
        tasks: (today.where((t) => t.done).length, today.length),
        habits: (habits.where((h) => h.doneOn(now)).length, habits.length),
        studyMinutes: study,
        studyGoal: goal,
        top: [for (final t in open.take(3)) t.title],
      );
      final path = await HomeWidget.renderFlutterWidget(
        TodayCard(data: data),
        key: 'today_image',
        logicalSize: const Size(340, 160),
      );
      await HomeWidget.saveWidgetData<String>('today_image', path);
      await HomeWidget.updateWidget(qualifiedAndroidName: _provider);
    } catch (e) {
      debugPrint('Home widget update failed: $e');
    }
  }
}

final homeWidgetProvider = Provider<HomeWidgetService>((ref) {
  final s = HomeWidgetService(ref);
  ref.onDispose(s.dispose);
  return s;
});

class TodayCardData {
  const TodayCardData({
    required this.signedIn,
    required this.tasks,
    required this.habits,
    required this.studyMinutes,
    required this.studyGoal,
    required this.top,
  });
  final bool signedIn;
  final (int, int) tasks;
  final (int, int) habits;
  final int studyMinutes;
  final int studyGoal;
  final List<String> top;

  double get taskRatio => tasks.$2 == 0 ? 0 : tasks.$1 / tasks.$2;
  double get habitRatio => habits.$2 == 0 ? 0 : habits.$1 / habits.$2;
  double get studyRatio => (studyMinutes / studyGoal).clamp(0, 1).toDouble();
  double get overall {
    final parts = [if (tasks.$2 > 0) taskRatio, if (habits.$2 > 0) habitRatio, studyRatio];
    return parts.fold(0.0, (a, b) => a + b) / parts.length;
  }
}

/// The picture shown on the home screen. Plain widgets only (no blur or
/// animation): it's rendered once, off screen.
class TodayCard extends StatelessWidget {
  const TodayCard({super.key, required this.data});

  final TodayCardData data;

  @override
  Widget build(BuildContext context) {
    const white = Color(0xFFF5F5FA);
    const dim = Color(0x99F5F5FA);
    if (!data.signedIn) {
      return const Center(child: Text('Sign in to LifeOS', style: TextStyle(color: dim, fontSize: 15)));
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          SizedBox(
            width: 116,
            height: 116,
            child: CustomPaint(
              painter: _RingsPainter([
                (data.taskRatio, LifeColors.tasks),
                (data.habitRatio, LifeColors.habits),
                (data.studyRatio, LifeColors.learning),
              ]),
              child: Center(
                child: Text(
                  '${(data.overall * 100).round()}%',
                  style: const TextStyle(color: white, fontSize: 20, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('TODAY', style: TextStyle(color: dim, fontSize: 11, letterSpacing: 1.4, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(
                  'Tasks ${data.tasks.$1}/${data.tasks.$2} · Habits ${data.habits.$1}/${data.habits.$2}',
                  style: const TextStyle(color: white, fontSize: 13, fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                if (data.top.isEmpty)
                  const Text('All clear 🎉', style: TextStyle(color: dim, fontSize: 13))
                else
                  for (final t in data.top)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3, right: 44),
                      child: Text('○  $t', style: const TextStyle(color: white, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RingsPainter extends CustomPainter {
  _RingsPainter(this.rings);

  final List<(double, Color)> rings;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 10.0, gap = 3.0;
    final c = size.center(Offset.zero);
    var r = size.shortestSide / 2 - stroke / 2;
    for (final (v, color) in rings) {
      final rect = Rect.fromCircle(center: c, radius: r);
      final track = Paint()
        ..color = color.withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke;
      canvas.drawCircle(c, r, track);
      if (v > 0) {
        final arc = Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round;
        canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * v.clamp(0.0, 1.0), false, arc);
      }
      r -= stroke + gap;
    }
  }

  @override
  bool shouldRepaint(_RingsPainter old) => true;
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/routing/routes.dart';
import '../../../core/widgets/layout/tab_scaffold.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/stores.dart';
import 'calendar_view.dart';
import 'goals_view.dart';
import 'habits_view.dart';
import 'tasks_view.dart';

/// Productivity hub. See docs/UI_UX.md §9.2.
class PlanScreen extends ConsumerStatefulWidget {
  const PlanScreen({super.key});

  @override
  ConsumerState<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends ConsumerState<PlanScreen> {
  int _segment = 0;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final tasks = ref.watch(tasksProvider);
    final todayOpen = tasks.where((t) => !t.done && t.isDueOn(now)).length;
    final overdue = tasks.where((t) => t.isOverdue(now)).length;
    final pending = ref.watch(assistantProvider.select((s) => s.pending.length));

    final body = switch (_segment) {
      0 => const TasksView(),
      1 => const GoalsView(),
      2 => const HabitsView(),
      _ => const CalendarView(),
    };

    return SwipeNav(
      onSwipe: (dir) {
        final next = _segment + dir;
        if (next < 0 || next > 3) return false;
        setState(() => _segment = next);
        return true;
      },
      child: TabScaffold(
        title: 'Plan',
        subtitle: '$todayOpen open today${overdue > 0 ? ' · $overdue overdue' : ''}',
        slivers: [
          SliverSection(
            bottom: Space.lg,
            child: SegmentedGlass(
              segments: const ['Tasks', 'Goals', 'Habits', 'Calendar'],
              index: _segment,
              onChanged: (i) => setState(() => _segment = i),
            ),
          ),
          if (pending > 0)
            SliverSection(
              bottom: Space.lg,
              child: GlassCard(
                ai: true,
                padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
                onTap: () {
                  ref.read(assistantTabProvider.notifier).set(2);
                  context.go(Routes.assistant);
                },
                child: Row(
                  children: [
                    const AiMark(size: 24),
                    const SizedBox(width: Space.md),
                    Expanded(child: Text('$pending suggestions from your assistant', style: LifeText.bodyStrong)),
                    const Icon(LucideIcons.chevronRight, size: 18, color: LifeColors.text2),
                  ],
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: AnimatedSwitcher(
              duration: Motion.of(context, Motion.card),
              switchInCurve: Motion.emphasized,
              transitionBuilder: (child, a) => FadeTransition(opacity: a, child: child),
              child: KeyedSubtree(key: ValueKey(_segment), child: body),
            ),
          ),
        ],
      ),
    );
  }
}

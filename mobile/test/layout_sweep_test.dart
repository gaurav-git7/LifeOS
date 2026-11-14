// Opens every screen, sub-tab and sheet at small phone widths. Any
// "RenderFlex overflowed" error fails the test, so layout bugs are caught
// before they reach the phone.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lifeos/app/app.dart';
import 'package:lifeos/core/motion/motion.dart';
import 'package:lifeos/core/routing/router.dart';
import 'package:lifeos/core/routing/routes.dart';
import 'package:lifeos/core/widgets/widgets.dart' show FilterChipRow;
import 'package:lifeos/data/stores.dart';

import 'helpers/fake_api.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  // (physical width, height, devicePixelRatio) → logical 360 dp and 392 dp (Galaxy S23 FE)
  const sizes = {'360dp': (1080.0, 2340.0, 3.0), '392dp (S23 FE)': (1080.0, 2340.0, 2.75)};

  for (final entry in sizes.entries) {
    testWidgets('no overflow anywhere at ${entry.key}', (tester) async {
      final (w, h, dpr) = entry.value;
      tester.view.physicalSize = Size(w, h);
      tester.view.devicePixelRatio = dpr;
      addTearDown(tester.view.reset);

      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(motionSettingsProvider.notifier).setReduceMotion(true);
      c.read(authProvider.notifier).debugSignIn();
      await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const LifeOSApp()));

      Future<void> settle([int frames = 6]) async {
        for (var i = 0; i < frames; i++) {
          await tester.pump(const Duration(milliseconds: 150));
        }
      }

      // The vertical scroll view the user can currently touch (inactive tabs ignore pointers).
      Finder activeScroll() => find
          .byWidgetPredicate((w) => w is Scrollable && axisDirectionToAxis(w.axisDirection) == Axis.vertical)
          .hitTestable()
          .last;

      Future<void> toTop() async {
        await tester.drag(activeScroll(), const Offset(0, 4000));
        await settle(3);
      }

      Future<void> scrollToAndTap(String text) async {
        final target = find.text(text);
        if (!tester.any(target.hitTestable()) && tester.any(target)) {
          // Already built but off-screen (e.g. a chip in a horizontal row): scroll every ancestor list to it.
          await tester.ensureVisible(target.first);
          await settle(2);
        }
        if (!tester.any(target.hitTestable())) {
          final scrollables = find
              .byWidgetPredicate((w) => w is Scrollable && axisDirectionToAxis(w.axisDirection) == Axis.vertical)
              .hitTestable();
          expect(scrollables, findsWidgets, reason: '"$text" is not visible and there is nothing to scroll');
          await toTop();
          if (!tester.any(target.hitTestable())) {
            await tester.scrollUntilVisible(target, 250, scrollable: activeScroll(), maxScrolls: 60);
            await settle(2);
          }
        }
        expect(target.hitTestable(), findsWidgets, reason: 'expected to find "$text" on screen');
        await tester.tap(target.hitTestable().first);
        await settle();
      }

      /// Taps a chip in the visible horizontal chip row (all chips are built; scroll it into view).
      Future<void> chip(String text) async {
        if (!tester.any(find.byType(FilterChipRow).hitTestable())) {
          await toTop();
          await settle(4);
        }
        final row = find.byType(FilterChipRow).hitTestable().first;
        // skipOffstage: false — chips scrolled out of the row's viewport still exist.
        final target = find.descendant(of: row, matching: find.text(text, skipOffstage: false), skipOffstage: false);
        if (!tester.any(target)) {
          final texts = find
              .descendant(of: row, matching: find.byType(Text, skipOffstage: false), skipOffstage: false)
              .evaluate()
              .map((e) => (e.widget as Text).data)
              .toList();
          fail('chip "$text" not found; visible chip row has $texts');
        }
        await tester.ensureVisible(target.first);
        await settle(2);
        await tester.tap(target.first, warnIfMissed: false);
        await settle();
      }

      Future<void> tapText(String text) async {
        try {
          await scrollToAndTap(text);
        } catch (e) {
          fail('Could not reach "$text": $e');
        }
      }

      Future<void> closeSheet() async {
        await tester.tapAt(const Offset(10, 40)); // tap the barrier above the sheet
        await settle();
      }

      Future<void> tab(String label) async {
        await tester.tap(find.byKey(ValueKey('nav-$label')));
        await settle();
      }

      final router = c.read(routerProvider);
      Future<void> go(String path) async {
        router.push(path);
        await settle();
      }

      Future<void> back() async {
        router.pop();
        await settle();
      }

      await settle();

      // ---- Home + sheets
      await tester.tap(find.bySemanticsLabel('Notifications'));
      await settle();
      await closeSheet();
      await tester.tap(find.bySemanticsLabel('Quick add'));
      await settle();
      await closeSheet();
      await scrollToAndTap('Solve 3 sliding-window problems'); // task editor
      await closeSheet();

      // ---- Plan
      await tab('Plan');
      for (final f in ['Upcoming', 'Overdue', 'Done', 'Today']) {
        await chip(f);
      }
      await tapText('Goals');
      await scrollToAndTap('Docker & Kubernetes fundamentals'); // goal detail
      await closeSheet();
      await scrollToAndTap('New goal');
      await closeSheet();
      await tapText('Habits');
      await scrollToAndTap('Gym'); // habit detail
      await closeSheet();
      await tapText('Calendar');
      await scrollToAndTap('+ Add');
      await tapText('Block time');
      await closeSheet();

      // ---- Growth
      await tab('Growth');
      for (final t in ['Skills', 'Roadmaps', 'Study', 'Projects', 'Overview']) {
        await chip(t);
      }
      await chip('Skills');
      await scrollToAndTap('Track a skill');
      await closeSheet();
      await toTop();
      await chip('Roadmaps');
      await scrollToAndTap('New roadmap');
      await closeSheet();
      await toTop();
      await chip('Projects');
      await scrollToAndTap('New project');
      await closeSheet();
      await scrollToAndTap('LifeOS'); // project detail
      await closeSheet();

      // ---- Journal
      await tab('Journal');
      await scrollToAndTap('Good');

      // ---- Assistant
      await tab('Assistant');
      await tapText('Reviews');
      await chip('This week');
      await tapText('Suggestions');
      await tapText('Chat');

      // ---- Pushed screens
      await go(Routes.focus);
      await back();
      await go(Routes.achievements);
      await back();
      await go(Routes.roadmap('p1'));
      await back();
      await go(Routes.journalNew(prompt: 'What went well today?'));
      await back();
      await go(Routes.journalInsights);
      await back();
      await go(Routes.memories);
      await back();
      await go(Routes.settings);
      await back();

      // ---- Signed-out screens
      c.read(authProvider.notifier).signOut();
      await settle();
      await go(Routes.register);
      await go(Routes.forgot);

    });
  }

  // A new live account has no data: every screen must still lay out (empty states).
  testWidgets('no overflow with an empty live account at 360dp', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final c = fakeLiveContainer(FakeApi());
    addTearDown(c.dispose);
    c.read(motionSettingsProvider.notifier).setReduceMotion(true);
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const LifeOSApp()));
    Future<void> settle([int frames = 6]) async {
      for (var i = 0; i < frames; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }
    }

    await settle();
    await tester.runAsync(() => c.read(authProvider.notifier).register('New', 'new@example.com', 'correct-horse-battery'));
    await settle(10);
    expect(c.read(authProvider).live, isTrue);
    expect(c.read(tasksProvider), isEmpty);

    Future<void> chip(String label) async {
      final row = find.byType(FilterChipRow).hitTestable().first;
      final f = find.descendant(of: row, matching: find.text(label, skipOffstage: false), skipOffstage: false);
      await tester.ensureVisible(f.first);
      await tester.tap(f.first, warnIfMissed: false);
      await settle(3);
    }

    final router = c.read(routerProvider);
    await tester.tap(find.bySemanticsLabel('Notifications'));
    await settle();
    expect(find.text('All caught up'), findsOneWidget);
    await tester.tapAt(const Offset(10, 40));
    await settle();

    for (final t in ['Plan', 'Growth', 'Journal', 'Assistant']) {
      await tester.tap(find.byKey(ValueKey('nav-$t')));
      await settle();
      if (t == 'Plan') {
        for (final s in ['Goals', 'Habits', 'Calendar']) {
          await tester.tap(find.text(s).hitTestable().first);
          await settle();
        }
      }
      if (t == 'Growth') {
        for (final s in ['Skills', 'Roadmaps', 'Study', 'Projects', 'Overview']) {
          await chip(s);
        }
      }
      if (t == 'Assistant') {
        await tester.tap(find.text('Reviews').hitTestable().first);
        await settle();
        await chip('This week');
        expect(find.text('Generate my weekly review'), findsOneWidget);
        await tester.tap(find.text('Suggestions').hitTestable().first);
        await settle();
      }
    }
    for (final r in [Routes.focus, Routes.achievements, Routes.journalInsights, Routes.memories, Routes.settings]) {
      router.push(r);
      await settle();
      router.pop();
      await settle();
    }
  });
}

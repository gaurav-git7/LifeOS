import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lifeos/app/app.dart';
import 'package:lifeos/core/motion/motion.dart';
import 'package:lifeos/core/routing/router.dart';
import 'package:lifeos/core/routing/routes.dart';
import 'package:lifeos/data/stores.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fake_api.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<ProviderContainer> pumpApp(WidgetTester tester, {bool signedIn = true, FakeApi? api}) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});

    final container = api != null ? fakeLiveContainer(api) : ProviderContainer();
    addTearDown(container.dispose);
    // Reduced motion so ambient animations don't keep the test pumping forever.
    container.read(motionSettingsProvider.notifier).setReduceMotion(true);
    if (signedIn) container.read(authProvider.notifier).debugSignIn();

    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const LifeOSApp()));
    // Session restore → redirect → page transition.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    return container;
  }

  /// Several frames: navigation is async, then the page transition runs.
  Future<void> settle(WidgetTester tester, [int frames = 6]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  Future<void> tapTab(WidgetTester tester, String label) async {
    await tester.tap(find.byKey(ValueKey('nav-$label')));
    await settle(tester);
  }

  testWidgets('signed out → onboarding → register → home', (tester) async {
    final api = FakeApi();
    final c = await pumpApp(tester, signedIn: false, api: api);
    expect(find.text('operating system.'), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await settle(tester);
    expect(find.text('Welcome back'), findsOneWidget);

    await tester.tap(find.text('Create an account'));
    await settle(tester);
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Gaurav');
    await tester.enterText(fields.at(1), 'me@example.com');
    await tester.enterText(fields.at(2), 'correct-horse-battery');
    await tester.tap(find.text('Create account'));
    await settle(tester, 12);
    expect(find.text('Priorities', skipOffstage: false), findsOneWidget);
    // Live mode: starts empty (no sample data) and talks to the server.
    expect(c.read(authProvider).live, isTrue);
    expect(c.read(tasksProvider), isEmpty);
    expect(api.calls, containsAll(['POST /auth/register', 'GET /sync/pull']));
  });

  testWidgets('sample data mode from the sign-in screen', (tester) async {
    final c = await pumpApp(tester, signedIn: false, api: FakeApi());
    await tester.tap(find.text('Skip'));
    await settle(tester);
    await tester.tap(find.text('Explore with sample data'));
    await settle(tester, 10);
    expect(find.text('Priorities', skipOffstage: false), findsOneWidget);
    expect(c.read(authProvider).live, isFalse);
    expect(c.read(tasksProvider), isNotEmpty);
  });

  testWidgets('every tab renders', (tester) async {
    await pumpApp(tester);
    expect(find.text('Priorities', skipOffstage: false), findsOneWidget);
    await tapTab(tester, 'Plan');
    expect(find.text('Upcoming'), findsOneWidget);
    await tapTab(tester, 'Growth');
    expect(find.text('Skill profile'), findsOneWidget);
    await tapTab(tester, 'Journal');
    expect(find.text('How are you today?'), findsOneWidget);
    await tapTab(tester, 'Assistant');
    expect(find.text('work on today?'), findsOneWidget);
  });

  testWidgets('assistant chat streams a reply with proposals', (tester) async {
    final c = await pumpApp(tester);
    await tapTab(tester, 'Assistant');
    await tester.tap(find.text('Plan tomorrow'));
    await tester.pump(const Duration(seconds: 1)); // thinking
    await tester.pump(const Duration(seconds: 3)); // streaming
    await tester.pump(const Duration(milliseconds: 500));
    expect(c.read(assistantProvider).messages.last.streaming, isFalse);
    expect(find.text('Accept all'), findsWidgets);
  });

  testWidgets('quick add creates a task', (tester) async {
    final c = await pumpApp(tester);
    await tester.tap(find.bySemanticsLabel('Quick add'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.enterText(find.byType(TextField).first, 'study graphs tomorrow 7pm');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Study graphs'), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect(c.read(tasksProvider).any((t) => t.title == 'Study graphs' && t.hasTime), isTrue);
  });

  testWidgets('swipe moves through sub-tabs, then to the next tab', (tester) async {
    final c = await pumpApp(tester);
    Future<void> swipeLeft() async {
      await tester.flingFrom(const Offset(320, 420), const Offset(-250, 0), 1500);
      await settle(tester);
    }

    expect(find.text('Priorities', skipOffstage: false), findsOneWidget);
    await swipeLeft(); // Home → Plan
    expect(c.read(routerProvider).state.matchedLocation, Routes.plan);
    for (var i = 0; i < 3; i++) {
      await swipeLeft(); // Tasks → Goals → Habits → Calendar
    }
    expect(find.text('+ Add'), findsOneWidget); // calendar day header
    await swipeLeft(); // Calendar is the last sub-tab → Growth
    expect(c.read(routerProvider).state.matchedLocation, Routes.growth);
  });

  testWidgets('sign out returns to login', (tester) async {
    final c = await pumpApp(tester);
    c.read(authProvider.notifier).signOut();
    await settle(tester);
    expect(find.text('Welcome back'), findsOneWidget);
  });
}

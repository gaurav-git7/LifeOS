import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lifeos/app/app.dart';
import 'package:lifeos/core/motion/motion.dart';
import 'package:lifeos/data/stores.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<ProviderContainer> pumpApp(WidgetTester tester, {bool signedIn = true}) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    // Reduced motion so ambient animations don't keep the test pumping forever.
    container.read(motionSettingsProvider.notifier).setReduceMotion(true);
    if (signedIn) container.read(authProvider.notifier).debugSignIn();

    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const LifeOSApp()));
    await tester.pump(const Duration(seconds: 1));
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
    await pumpApp(tester, signedIn: false);
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
    expect(find.text('Priorities'), findsOneWidget);
  });

  testWidgets('every tab renders', (tester) async {
    await pumpApp(tester);
    expect(find.text('Priorities'), findsOneWidget);
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

  testWidgets('sign out returns to login', (tester) async {
    final c = await pumpApp(tester);
    c.read(authProvider.notifier).signOut();
    await settle(tester);
    expect(find.text('Welcome back'), findsOneWidget);
  });
}

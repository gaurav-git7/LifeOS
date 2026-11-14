import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/stores.dart';
import '../../dev/gallery_screen.dart';
import '../../features/assistant/presentation/assistant_screen.dart';
import '../../features/assistant/presentation/memories_screen.dart';
import '../../features/auth/presentation/auth_screens.dart';
import '../../features/growth/presentation/achievements_screen.dart';
import '../../features/growth/presentation/focus_screen.dart';
import '../../features/growth/presentation/growth_screen.dart';
import '../../features/growth/presentation/roadmap_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/journal/presentation/journal_editor_screen.dart';
import '../../features/journal/presentation/journal_insights_screen.dart';
import '../../features/journal/presentation/journal_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/plan/presentation/plan_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/social/friends_screen.dart';
import '../../shell/app_shell.dart';
import '../../shell/fade_indexed_stack.dart';
import '../motion/transitions.dart';
import 'routes.dart';

final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// For showing sheets from outside the widget tree (e.g. a home-screen widget tap).
GlobalKey<NavigatorState> get rootNavigatorKey => _rootKey;

StatefulShellBranch _tab(String path, Widget screen) => StatefulShellBranch(
      routes: [
        GoRoute(
          path: path,
          pageBuilder: (context, state) => NoTransitionPage(key: state.pageKey, child: screen),
        ),
      ],
    );

GoRoute _page(String path, Widget Function(GoRouterState s) build) => GoRoute(
      path: path,
      parentNavigatorKey: _rootKey,
      pageBuilder: (context, state) => lifePage(state, build(state)),
    );

final routerProvider = Provider<GoRouter>((ref) {
  // Re-run redirects whenever sign-in state changes.
  final auth = ValueNotifier<AuthState>(ref.read(authProvider));
  ref.listen<AuthState>(authProvider, (_, next) => auth.value = next);
  ref.onDispose(auth.dispose);

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: Routes.home,
    refreshListenable: auth,
    redirect: (context, state) {
      final a = auth.value;
      final loc = state.matchedLocation;
      final public = Routes.isPublic(loc);
      if (a.status == AuthStatus.unknown) return loc == Routes.splash ? null : Routes.splash;
      if (!a.signedIn) {
        if (public && loc != Routes.splash) return null;
        return a.onboarded ? Routes.login : Routes.onboarding;
      }
      if (public) return Routes.home;
      return null;
    },
    routes: [
      _page(Routes.splash, (_) => const SplashScreen()),
      _page(Routes.onboarding, (_) => const OnboardingScreen()),
      _page(Routes.login, (_) => const LoginScreen()),
      _page(Routes.register, (_) => const RegisterScreen()),
      _page(Routes.forgot, (_) => const ForgotPasswordScreen()),
      StatefulShellRoute(
        builder: (context, state, shell) => AppShell(shell: shell),
        navigatorContainerBuilder: (context, shell, children) =>
            FadeIndexedStack(index: shell.currentIndex, children: children),
        branches: [
          _tab(Routes.home, const HomeScreen()),
          _tab(Routes.plan, const PlanScreen()),
          _tab(Routes.growth, const GrowthScreen()),
          _tab(Routes.journal, const JournalScreen()),
          _tab(Routes.assistant, const AssistantScreen()),
        ],
      ),
      _page(Routes.focus, (s) => FocusScreen(topicId: s.uri.queryParameters['topic'])),
      _page(Routes.achievements, (_) => const AchievementsScreen()),
      _page('/roadmap/:id', (s) => RoadmapScreen(pathId: s.pathParameters['id']!)),
      _page(Routes.journalInsights, (_) => const JournalInsightsScreen()),
      _page('/entry/new', (s) => JournalEditorScreen(
            prompt: s.uri.queryParameters['prompt'],
            day: DateTime.tryParse(s.uri.queryParameters['day'] ?? ''),
          )),
      _page('/entry/:id', (s) => JournalEditorScreen(entryId: s.pathParameters['id'])),
      _page(Routes.memories, (_) => const MemoriesScreen()),
      _page(Routes.friends, (s) => FriendsScreen(initialTab: s.uri.queryParameters['tab'] == 'groups' ? 1 : 0)),
      _page(Routes.settings, (_) => const SettingsScreen()),
      _page(Routes.gallery, (_) => const GalleryScreen()),
    ],
  );
});

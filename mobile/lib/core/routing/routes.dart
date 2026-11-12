/// Route paths. See docs/UI_UX.md §8.1.
abstract final class Routes {
  // auth
  static const onboarding = '/onboarding';
  static const login = '/auth/login';
  static const register = '/auth/register';
  static const forgot = '/auth/forgot';

  // tabs
  static const home = '/home';
  static const plan = '/plan';
  static const growth = '/growth';
  static const journal = '/journal';
  static const assistant = '/assistant';

  // details
  static const focus = '/focus';
  static String focusFor(String topicId) => '/focus?topic=$topicId';
  static const achievements = '/achievements';
  static String roadmap(String id) => '/roadmap/$id';
  static const journalInsights = '/journal-insights';
  static String journalEntry(String id) => '/entry/$id';
  static String journalNew({String? prompt, DateTime? day}) => Uri(
        path: '/entry/new',
        queryParameters: {
          'prompt': ?prompt,
          if (day != null) 'day': day.toIso8601String().substring(0, 10),
        },
      ).toString();
  static const memories = '/memories';
  static const settings = '/settings';
  static const gallery = '/dev/gallery';

  /// Tab order in the bottom navigation.
  static const tabs = [home, plan, growth, journal, assistant];

  static bool isPublic(String location) => location.startsWith('/auth') || location == onboarding;
}

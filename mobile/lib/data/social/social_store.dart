// Friends, reactions and group habits. Server-only (needs an account): these
// are other people's data, so nothing here is cached offline.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../api/api_client.dart';
import '../stores.dart';

class Person {
  const Person({required this.id, required this.name, required this.level, required this.rank});
  final String id;
  final String name;
  final int level;
  final String rank;

  String get initial => name.isEmpty ? '?' : name[0].toUpperCase();

  static Person fromJson(Map<String, dynamic> j) => Person(
        id: j['id'] as String,
        name: j['name'] as String,
        level: j['level'] as int? ?? 1,
        rank: j['rank'] as String? ?? '',
      );
}

class SharedHabit {
  const SharedHabit({required this.id, required this.title, required this.streak, required this.unit, required this.doneToday});
  final String id;
  final String title;
  final int streak;
  final String unit; // day | week
  final bool doneToday;
}

class FriendFeed {
  const FriendFeed({required this.person, required this.habits, required this.badges});
  final Person person;
  final List<SharedHabit> habits;
  final List<String> badges; // achievements in the last 7 days
}

class GroupHabitView {
  const GroupHabitView({
    required this.id,
    required this.title,
    required this.rule,
    required this.target,
    required this.dueToday,
    required this.doneToday,
    required this.weekDone,
    required this.streak,
  });
  final String id;
  final String title;
  final String rule;
  final int target;
  final bool dueToday;
  final Set<String> doneToday; // member ids
  final Map<String, int> weekDone; // member id → done this week
  final int streak;
}

class LeaderRow {
  const LeaderRow({required this.userId, required this.week, required this.allTime, required this.streak});
  final String userId;
  final int week;
  final int allTime;
  final int streak;
}

class Group {
  const Group({
    required this.id,
    required this.name,
    required this.inviteCode,
    required this.isOwner,
    required this.members,
    required this.habits,
    this.leaderboard = const [],
    this.lastWeekWinner,
  });
  final String id;
  final String name;
  final String inviteCode;
  final bool isOwner;
  final List<Person> members;
  final List<GroupHabitView> habits;
  final List<LeaderRow> leaderboard; // sorted by this week, then streak
  final String? lastWeekWinner;

  static Group fromJson(Map<String, dynamic> j) => Group(
        id: j['id'] as String,
        name: j['name'] as String,
        inviteCode: j['invite_code'] as String,
        isOwner: j['is_owner'] == true,
        members: [for (final m in j['members'] as List) Person.fromJson(Map<String, dynamic>.from(m as Map))],
        habits: [
          for (final h in (j['habits'] as List).cast<Map>())
            GroupHabitView(
              id: h['id'] as String,
              title: h['title'] as String,
              rule: h['recurrence_rule'] as String? ?? 'FREQ=DAILY',
              target: h['target_per_period'] as int? ?? 1,
              dueToday: h['due_today'] != false,
              doneToday: {for (final u in (h['done_today'] as List)) u as String},
              weekDone: {for (final e in (h['week_done'] as Map).entries) e.key as String: e.value as int},
              streak: h['group_streak'] as int? ?? 0,
            ),
        ],
        leaderboard: [
          for (final r in ((j['leaderboard'] as List?) ?? const []).cast<Map>())
            LeaderRow(
              userId: r['user_id'] as String,
              week: r['week'] as int? ?? 0,
              allTime: r['all_time'] as int? ?? 0,
              streak: r['streak'] as int? ?? 0,
            ),
        ],
        lastWeekWinner: j['last_week_winner'] as String?,
      );
}

class SocialState {
  const SocialState({
    this.loaded = false,
    this.friendCode,
    this.myId,
    this.feed = const [],
    this.incoming = const [],
    this.outgoing = const [],
    this.groups = const [],
    this.error,
  });
  final bool loaded;
  final String? friendCode;
  final String? myId;
  final List<FriendFeed> feed;
  final List<Person> incoming;
  final List<Person> outgoing;
  final List<Group> groups;
  final String? error;

  SocialState copyWith({List<Group>? groups, String? error}) => SocialState(
        loaded: loaded,
        friendCode: friendCode,
        myId: myId,
        feed: feed,
        incoming: incoming,
        outgoing: outgoing,
        groups: groups ?? this.groups,
        error: error,
      );
}

class SocialNotifier extends Notifier<SocialState> {
  @override
  SocialState build() => const SocialState();

  ApiClient get _api => ref.read(apiClientProvider);
  bool get _live => ref.read(authProvider).live;

  Future<void> load() async {
    if (!_live) return;
    try {
      final results = await Future.wait([
        _api.get<Map<String, dynamic>>('/social/me'),
        _api.get<Map<String, dynamic>>('/social/friends'),
        _api.get<List<dynamic>>('/social/feed'),
        _api.get<List<dynamic>>('/social/groups'),
        _api.get<Map<String, dynamic>>('/users/me'),
      ]);
      if (!ref.mounted) return;
      final me = results[0] as Map<String, dynamic>;
      final friends = results[1] as Map<String, dynamic>;
      List<Person> people(String k) => [for (final p in friends[k] as List) Person.fromJson(Map<String, dynamic>.from(p as Map))];
      state = SocialState(
        loaded: true,
        friendCode: me['friend_code'] as String?,
        myId: (results[4] as Map<String, dynamic>)['id'] as String?,
        incoming: people('incoming'),
        outgoing: people('outgoing'),
        feed: [
          for (final f in (results[2] as List).cast<Map>())
            FriendFeed(
              person: Person.fromJson(Map<String, dynamic>.from(f)),
              habits: [
                for (final h in (f['habits'] as List).cast<Map>())
                  SharedHabit(
                    id: h['id'] as String,
                    title: h['title'] as String,
                    streak: h['streak'] as int? ?? 0,
                    unit: h['streak_unit'] as String? ?? 'day',
                    doneToday: h['done_today'] == true,
                  ),
              ],
              badges: [for (final b in (f['badges'] as List).cast<Map>()) b['title'] as String],
            ),
        ],
        groups: [for (final g in (results[3] as List)) Group.fromJson(Map<String, dynamic>.from(g as Map))],
      );
    } on ApiException catch (e) {
      if (ref.mounted) state = state.copyWith(error: e.isNetwork ? 'You’re offline.' : e.message);
    }
  }

  /// Runs a call, then reloads. Returns an error message or null.
  Future<String?> _do(Future<dynamic> Function() call) async {
    try {
      await call();
      await load();
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }

  Future<String?> addFriend(String code) => _do(() => _api.post<dynamic>('/social/friends', data: {'code': code.trim().toUpperCase()}));
  Future<String?> accept(String id) => _do(() => _api.post<dynamic>('/social/friends/$id/accept'));
  Future<String?> remove(String id) => _do(() => _api.delete('/social/friends/$id'));

  Future<String?> react(String toUserId, String kind, {String? habitId, String? groupHabitId}) async {
    try {
      await _api.post<dynamic>('/social/react', data: {
        'to_user_id': toUserId,
        'kind': kind,
        'habit_id': ?habitId,
        'group_habit_id': ?groupHabitId,
      });
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }

  Future<String?> createGroup(String name) => _do(() => _api.post<dynamic>('/social/groups', data: {'name': name}));
  Future<String?> joinGroup(String code) =>
      _do(() => _api.post<dynamic>('/social/groups/join', data: {'code': code.trim().toUpperCase()}));
  Future<String?> leaveGroup(String id) => _do(() => _api.post<dynamic>('/social/groups/$id/leave'));
  Future<String?> addGroupHabit(String groupId, String title, String rule, int target) => _do(() =>
      _api.post<dynamic>('/social/groups/$groupId/habits', data: {'title': title, 'recurrence_rule': rule, 'target_per_period': target}));
  Future<String?> removeGroupHabit(String groupId, String habitId) =>
      _do(() => _api.delete('/social/groups/$groupId/habits/$habitId'));

  /// Tick a group habit for today (optimistic).
  Future<String?> checkin(String habitId, bool done) async {
    final me = state.myId;
    if (me != null) {
      state = state.copyWith(groups: [
        for (final g in state.groups)
          Group(
            id: g.id,
            name: g.name,
            inviteCode: g.inviteCode,
            isOwner: g.isOwner,
            members: g.members,
            leaderboard: g.leaderboard,
            lastWeekWinner: g.lastWeekWinner,
            habits: [
              for (final h in g.habits)
                h.id == habitId
                    ? GroupHabitView(
                        id: h.id,
                        title: h.title,
                        rule: h.rule,
                        target: h.target,
                        dueToday: h.dueToday,
                        doneToday: done ? {...h.doneToday, me} : ({...h.doneToday}..remove(me)),
                        weekDone: h.weekDone,
                        streak: h.streak,
                      )
                    : h,
            ],
          ),
      ]);
    }
    final day = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return _do(() => _api.put<dynamic>('/social/group-habits/$habitId/checkins/$day', data: {'done': done}));
  }
}

final socialProvider = NotifierProvider<SocialNotifier, SocialState>(SocialNotifier.new);

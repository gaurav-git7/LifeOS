// Fingerprint / face / PIN lock using the phone's own screen lock (local_auth).
// - App lock: asked when the app opens and after 1 minute in the background.
// - Journal lock: asked once when opening the Journal; the journal is also
//   hidden from "recent apps" and screenshots while it's on screen.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../stores.dart';

class LockState {
  const LockState({this.appUnlocked = false, this.journalUnlocked = false});
  final bool appUnlocked;
  final bool journalUnlocked;
}

class LockController extends Notifier<LockState> {
  final _auth = LocalAuthentication();
  DateTime? _backgroundedAt;
  bool _asking = false;

  static const relockAfter = Duration(minutes: 1);

  @override
  LockState build() => const LockState();

  bool get appLocked => ref.read(prefsProvider).appLock && !state.appUnlocked;

  Future<bool> isSupported() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// Shows the system fingerprint / PIN prompt. Returns true if it passed.
  Future<bool> authenticate(String reason) async {
    if (_asking) return false;
    _asking = true;
    try {
      return await _auth.authenticate(localizedReason: reason, persistAcrossBackgrounding: true);
    } catch (_) {
      return false;
    } finally {
      _asking = false;
    }
  }

  Future<bool> unlockApp() async {
    final ok = await authenticate('Unlock LifeOS');
    if (ok) state = LockState(appUnlocked: true, journalUnlocked: state.journalUnlocked);
    return ok;
  }

  Future<bool> unlockJournal() async {
    final ok = await authenticate('Unlock your journal');
    if (ok) state = LockState(appUnlocked: state.appUnlocked, journalUnlocked: true);
    return ok;
  }

  void onBackground() {
    if (!_asking) _backgroundedAt = DateTime.now();
  }

  /// Back from the background: lock again if it's been a while.
  void onResume() {
    final since = _backgroundedAt;
    _backgroundedAt = null;
    if (since == null || DateTime.now().difference(since) < relockAfter) return;
    state = const LockState(); // both locks apply again
  }
}

final lockProvider = NotifierProvider<LockController, LockState>(LockController.new);

// Small native helpers (android/.../MainActivity.kt). All calls are safe to
// make in tests or on unsupported platforms: they just do nothing.

import 'package:flutter/services.dart';

abstract final class SystemChannel {
  static const _c = MethodChannel('lifeos/system');

  static Future<T?> _call<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _c.invokeMethod<T>(method, args);
    } catch (_) {
      return null;
    }
  }

  static Future<bool> hasDndAccess() async => await _call<bool>('hasDndAccess') ?? false;
  static Future<void> openDndSettings() => _call<void>('openDndSettings');

  /// Returns false when access hasn't been granted.
  static Future<bool> setDnd(bool on, {DateTime? until}) async =>
      await _call<bool>('setDnd', {'on': on, 'untilMillis': until?.millisecondsSinceEpoch}) ?? false;

  /// Hides the app in "recent apps" and blocks screenshots while on.
  static Future<void> setSecure(bool on) => _call<void>('setSecure', {'on': on});
}

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AmbientIntensity { off, low, normal }

@immutable
class MotionSettings {
  const MotionSettings({
    this.reduceMotion = false,
    this.ambient = AmbientIntensity.normal,
  });

  final bool reduceMotion;
  final AmbientIntensity ambient;

  MotionSettings copyWith({bool? reduceMotion, AmbientIntensity? ambient}) =>
      MotionSettings(
        reduceMotion: reduceMotion ?? this.reduceMotion,
        ambient: ambient ?? this.ambient,
      );
}

/// In-app motion settings (Settings → Appearance).
class MotionSettingsNotifier extends Notifier<MotionSettings> {
  @override
  MotionSettings build() => const MotionSettings();

  void setReduceMotion(bool value) => state = state.copyWith(reduceMotion: value);
  void setAmbient(AmbientIntensity value) => state = state.copyWith(ambient: value);
}

final motionSettingsProvider =
    NotifierProvider<MotionSettingsNotifier, MotionSettings>(MotionSettingsNotifier.new);

/// Makes the effective motion preference (system "remove animations" OR the
/// in-app toggle) available to every widget without needing a WidgetRef.
class MotionScope extends InheritedWidget {
  const MotionScope({
    super.key,
    required this.reduced,
    required this.ambient,
    required super.child,
  });

  final bool reduced;
  final AmbientIntensity ambient;

  static MotionScope? _of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MotionScope>();

  static bool reducedOf(BuildContext context) =>
      _of(context)?.reduced ?? MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  static AmbientIntensity ambientOf(BuildContext context) {
    final scope = _of(context);
    if (scope == null) return AmbientIntensity.normal;
    return scope.reduced ? AmbientIntensity.off : scope.ambient;
  }

  @override
  bool updateShouldNotify(MotionScope oldWidget) =>
      reduced != oldWidget.reduced || ambient != oldWidget.ambient;
}

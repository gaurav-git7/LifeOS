import 'package:package_info_plus/package_info_plus.dart';

/// "0.1.0+3" once loaded (sent with crash reports, feedback and device registration).
String appVersion = 'dev';

/// "0.1.0" without the build number.
String get appVersionName => appVersion.split('+').first;

Future<void> loadAppInfo() async {
  try {
    final p = await PackageInfo.fromPlatform();
    appVersion = '${p.version}+${p.buildNumber}';
  } catch (_) {
    // tests / unsupported platform
  }
}

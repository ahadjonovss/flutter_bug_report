import 'dart:io' show Platform;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

/// What can be known about the phone without asking a plugin for it.
///
/// Deliberately the *non-identifying* half: the platform, its version, the
/// locale, the screen, and which build this is. No device id, no advertising
/// id, no serial — those need a plugin, and a package that reached for one
/// would be deciding on your behalf what is safe to send.
///
/// Whatever else you want in the report — the app version, a device model, an
/// installation id — you pass through `metadata`, having decided it yourself.
abstract final class DeviceFacts {
  /// Reads what it can. Never throws: this runs while a report is being filed,
  /// and a report that fails because it could not name the screen size is
  /// worse than one with a field missing.
  static Map<String, String> collect() {
    final facts = <String, String>{};

    try {
      facts['platform'] = defaultTargetPlatform.name;
      facts['build_mode'] = kReleaseMode
          ? 'release'
          : kProfileMode
              ? 'profile'
              : 'debug';

      if (!kIsWeb) {
        facts['os_version'] = Platform.operatingSystemVersion;
        facts['locale'] = Platform.localeName;
        facts['dart_version'] = Platform.version.split(' ').first;
      }

      final view = ui.PlatformDispatcher.instance.implicitView;
      if (view != null) {
        final size = view.physicalSize / view.devicePixelRatio;
        facts['screen'] = '${size.width.round()}×${size.height.round()}';
        facts['pixel_ratio'] = view.devicePixelRatio.toStringAsFixed(1);
      }

      facts['text_scale'] = ui.PlatformDispatcher.instance
          .textScaleFactor
          .toStringAsFixed(2);
    } on Object {
      // Whatever was gathered before it went wrong is still worth sending.
    }

    return facts;
  }
}

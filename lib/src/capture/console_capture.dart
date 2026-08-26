import 'dart:async';

import 'package:flutter/foundation.dart';

/// Puts what the app already prints into the log, without the app changing a
/// line.
///
/// The value of this is what it catches that nobody would have logged on
/// purpose: a plugin's warning, a framework deprecation, the `print` somebody
/// left in a repository three years ago. Those are the lines that explain a
/// report, and none of them would be there if capture meant calling a logger.
///
/// The original [debugPrint] is kept and still called, so the console reads
/// exactly as it did before.
abstract final class ConsoleCapture {
  static DebugPrintCallback? _original;

  static bool get isActive => _original != null;

  /// Redirects [debugPrint] through [onLine]. Idempotent: calling it twice does
  /// not chain two wrappers, which would double every line.
  static void start(void Function(String line) onLine) {
    if (_original != null) return;

    final original = _original = debugPrint;

    debugPrint = (String? message, {int? wrapWidth}) {
      original(message, wrapWidth: wrapWidth);
      if (message != null && message.isNotEmpty) onLine(message);
    };
  }

  /// Restores the console to how it was found. Called by `BugReport.dispose`,
  /// and worth calling in a test that installed it.
  static void stop() {
    final original = _original;
    if (original == null) return;

    debugPrint = original;
    _original = null;
  }

  /// Runs [body] in a zone where bare `print` is captured too.
  ///
  /// Separate from [start] because it cannot be switched on in place: `print`
  /// is resolved through the ambient zone, so catching it means running the app
  /// inside one. Wrap `runApp` to use it.
  static R runCaptured<R>(R Function() body, void Function(String line) onLine) {
    return runZoned<R>(
      body,
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) {
          parent.print(zone, line);
          if (line.isNotEmpty) onLine(line);
        },
      ),
    );
  }
}

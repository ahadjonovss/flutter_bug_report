import 'dart:ui';

import 'package:flutter/foundation.dart';

/// Puts what the framework catches into the log.
///
/// Two handlers, because Flutter reports through two: [FlutterError.onError] is
/// everything raised inside the framework — a failed build, an overflow, a
/// bad assertion — and [PlatformDispatcher.onError] is what escapes an
/// asynchronous callback and would otherwise reach nothing at all.
///
/// Both keep whatever was installed before and call it: this is not a crash
/// handler and must not displace one. An app running Sentry or Crashlytics
/// keeps reporting to them exactly as it did.
abstract final class ErrorCapture {
  static FlutterExceptionHandler? _previousFlutterError;
  static ErrorCallback? _previousPlatformError;
  static bool _isActive = false;

  static bool get isActive => _isActive;

  static void start(
    void Function(Object error, StackTrace? stackTrace, String? context) onError,
  ) {
    if (_isActive) return;
    _isActive = true;

    final previousFlutterError = _previousFlutterError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      onError(
        details.exception,
        details.stack,
        // What the framework was doing — "building HomePage", "during layout".
        // The sentence that turns a stack trace into something placeable.
        details.context?.toDescription() ?? details.library,
      );
      previousFlutterError?.call(details);
    };

    final previousPlatformError = _previousPlatformError =
        PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      onError(error, stack, 'uncaught asynchronous error');

      // Whatever was there decides whether this counts as handled. False by
      // default, which is the framework's own answer and lets the error keep
      // going to the zone above.
      return previousPlatformError?.call(error, stack) ?? false;
    };
  }

  static void stop() {
    if (!_isActive) return;

    FlutterError.onError = _previousFlutterError;
    PlatformDispatcher.instance.onError = _previousPlatformError;
    _previousFlutterError = null;
    _previousPlatformError = null;
    _isActive = false;
  }
}

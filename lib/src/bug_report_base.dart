import 'dart:async';

import 'package:flutter_bug_report/src/bundle/bundle.dart';
import 'package:flutter_bug_report/src/bundle/bundle_builder.dart';
import 'package:flutter_bug_report/src/bundle/bundle_format.dart';
import 'package:flutter_bug_report/src/capture/console_capture.dart';
import 'package:flutter_bug_report/src/capture/error_capture.dart';
import 'package:flutter_bug_report/src/model/log_entry.dart';
import 'package:flutter_bug_report/src/model/log_level.dart';
import 'package:flutter_bug_report/src/redaction/redactor.dart';
import 'package:flutter_bug_report/src/store/log_store.dart';

/// Collects what the app logs, and builds the file a bug report attaches.
///
/// Two halves, and deliberately nothing between them: entries go in through
/// [info] and the capture hooks, and come out as a [Bundle] through [build].
/// Where that bundle then goes — Sentry, Crashlytics, Jira, a Telegram bot,
/// your own upload endpoint — is the app's business and not this package's.
/// There is no client here, no DSN, and no service to sign up for.
///
/// ```dart
/// await BugReport.init();
///
/// BugReport.info('opened the payment screen');
///
/// // …later, when someone reports something
/// final bundle = await BugReport.build(
///   description: 'Payment screen froze after I pressed pay',
///   metadata: {'app_version': '1.0.17+2185', 'platform': 'android'},
/// );
/// await myBackend.upload(bundle.bytes, bundle.fileName, bundle.mimeType);
/// ```
///
/// Static throughout, and not an object anybody holds. There is one log per
/// app, the same way there is one console: an instance to pass around would be
/// a parameter on every constructor between `main` and the line worth
/// recording, and the first thing anyone would do is make it a global anyway.
abstract final class BugReport {
  static _Runtime? _runtime;

  /// The runtime, made on demand.
  ///
  /// Logging before [init] collects rather than throws or silently drops: the
  /// lines that explain a startup bug are written before anything has had a
  /// chance to be configured, and losing them to call ordering would defeat
  /// the point. [init] then carries them into whatever store it was given.
  static _Runtime get _active => _runtime ??= _Runtime(
    store: MemoryLogStore(),
    redactors: Redactor.defaults,
    minimumLevel: LogLevel.debug,
    builder: const BundleBuilder(),
    isImplicit: true,
  );

  /// Whether [init] has run. Collection works either way.
  static bool get isInitialised => _runtime?.isImplicit == false;

  /// Prepares collection. Call it in `main`, before `runApp`, so the log covers
  /// startup — which is where the errors nobody can reproduce tend to live.
  ///
  /// [store] decides whether the log survives the process; [MemoryLogStore] is
  /// the default and keeps nothing on the device.
  ///
  /// [redactors] default to [Redactor.defaults] — bearer tokens, JWTs, card
  /// numbers and the usual credential field names. Pass `const []` to turn
  /// redaction off, knowingly.
  ///
  /// [captureConsole] routes `debugPrint` through the log, which picks up
  /// everything the app and its plugins already print. [captureErrors] adds
  /// what the framework catches. Neither displaces what was installed before
  /// them: the console still prints, and an existing crash reporter still
  /// reports.
  static Future<void> init({
    LogStore? store,
    List<Redactor>? redactors,
    LogLevel minimumLevel = LogLevel.debug,
    bool captureConsole = true,
    bool captureErrors = true,
    BundleBuilder builder = const BundleBuilder(),
  }) async {
    // Whatever was logged on the way here, before anyone could configure
    // anything. Read before the old runtime is torn down.
    final previous = _runtime;
    final carried = previous == null || !previous.isImplicit
        ? const <LogEntry>[]
        : await previous.entries();

    await previous?.close();

    final resolved = store ?? MemoryLogStore();
    await resolved.open();

    final runtime = _runtime = _Runtime(
      store: resolved,
      redactors: redactors ?? Redactor.defaults,
      minimumLevel: minimumLevel,
      builder: builder,
      isImplicit: false,
    );

    // Already redacted — they went through the fallback runtime on the way in.
    for (final entry in carried) {
      runtime.add(entry);
    }

    if (captureConsole) {
      ConsoleCapture.start((line) => log(LogLevel.debug, line));
    }

    if (captureErrors) {
      ErrorCapture.start((error, stackTrace, context) {
        BugReport.error(
          context ?? 'unhandled error',
          error: error,
          stackTrace: stackTrace,
        );
      });
    }
  }

  /// Records one entry.
  ///
  /// Returns immediately: the entry is redacted and queued, and the store's
  /// write happens after the caller has moved on. Nothing here throws — a
  /// logger that can fail is a logger that turns a bug into two.
  static void log(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? extra,
  }) => _active.log(
    level,
    message,
    error: error,
    stackTrace: stackTrace,
    extra: extra,
  );

  static void debug(String message, {Map<String, Object?>? extra}) =>
      log(LogLevel.debug, message, extra: extra);

  static void info(String message, {Map<String, Object?>? extra}) =>
      log(LogLevel.info, message, extra: extra);

  static void warning(String message, {Map<String, Object?>? extra}) =>
      log(LogLevel.warning, message, extra: extra);

  static void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? extra,
  }) => log(
    LogLevel.error,
    message,
    error: error,
    stackTrace: stackTrace,
    extra: extra,
  );

  /// Builds the attachment.
  ///
  /// [description] is what the person said went wrong, in their words — the one
  /// thing no amount of logging produces on its own.
  ///
  /// [metadata] is whatever identifies the build and the phone: version,
  /// platform, OS, model, a device id. Deliberately a plain map rather than a
  /// device-info dependency, so this package does not decide what counts as
  /// identifying — the app does, and it already knows.
  ///
  /// [limit] and [maxBytes] bound it twice over. An attachment nobody can open
  /// is no better than none.
  static Future<Bundle> build({
    String? description,
    Map<String, String> metadata = const {},
    BundleFormat format = BundleFormat.zip,
    int? limit,
    int maxBytes = BundleBuilder.defaultMaxBytes,
    int stackFrames = BundleBuilder.defaultStackFrames,
  }) => _active.build(
    description: description,
    metadata: metadata,
    format: format,
    limit: limit,
    maxBytes: maxBytes,
    stackFrames: stackFrames,
  );

  /// The entries as they are held, redaction already applied. For an app that
  /// wants to show its own log screen rather than attach a file.
  static Future<List<LogEntry>> entries({int? limit}) =>
      _active.entries(limit: limit);

  /// Waits for every queued write to land. [build] and [entries] call it, so
  /// this is only needed when reaching for a store directly.
  static Future<void> flush() => _active.flush();

  /// Drops everything collected so far. Worth calling on sign-out if the log
  /// could name the person who just left.
  static Future<void> clear() => _active.clear();

  /// Uninstalls the capture hooks and closes the store. The console and the
  /// error handlers are left exactly as they were found.
  static Future<void> dispose() async {
    ConsoleCapture.stop();
    ErrorCapture.stop();

    await _runtime?.close();
    _runtime = null;
  }
}

/// The state behind the static API: one store, one set of rules, one queue.
///
/// Separate from [BugReport] so that state has a place to live and a lifetime
/// that can be replaced wholesale by `init` — rather than a dozen static fields
/// that have to be reset one at a time and can disagree with each other in
/// between.
class _Runtime {
  _Runtime({
    required this.store,
    required this.redactors,
    required this.minimumLevel,
    required this.builder,
    required this.isImplicit,
  });

  final LogStore store;
  final List<Redactor> redactors;
  final LogLevel minimumLevel;
  final BundleBuilder builder;

  /// Whether this was made on demand by a log call rather than by `init`.
  /// What `init` carries forward, and what `isInitialised` reports on.
  final bool isImplicit;

  /// Writes are serialised through this rather than awaited by the caller: a
  /// log call must never be something the UI waits on, and a store that writes
  /// to disk must not interleave two entries into one row.
  Future<void> _pending = Future.value();

  void log(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? extra,
  }) {
    if (level.index < minimumLevel.index) return;

    add(
      _clean(
        LogEntry(
          level: level,
          message: message,
          error: error?.toString(),
          stackTrace: stackTrace?.toString(),
          extra: extra,
        ),
      ),
    );
  }

  /// Queues an entry that has already been through redaction.
  void add(LogEntry entry) {
    _pending = _pending.then((_) => store.write(entry)).catchError((_) {});
  }

  Future<Bundle> build({
    String? description,
    Map<String, String> metadata = const {},
    BundleFormat format = BundleFormat.zip,
    int? limit,
    int maxBytes = BundleBuilder.defaultMaxBytes,
    int stackFrames = BundleBuilder.defaultStackFrames,
  }) async {
    // Anything logged up to this call belongs in the bundle — including the
    // line the report itself was logged from.
    final entries = await this.entries(limit: limit);

    return builder.build(
      entries: entries,
      format: format,
      description: description,
      metadata: metadata,
      maxBytes: maxBytes,
      stackFrames: stackFrames,
    );
  }

  Future<List<LogEntry>> entries({int? limit}) async {
    await flush();

    return store.read(limit: limit);
  }

  Future<void> flush() => _pending;

  Future<void> clear() async {
    await flush();
    await store.clear();
  }

  Future<void> close() async {
    await flush();
    await store.close();
  }

  /// Redaction happens here, once, on the way in — never on the way out. A
  /// secret that was never written down cannot leak from a store somebody later
  /// dumps by hand.
  LogEntry _clean(LogEntry entry) {
    if (redactors.isEmpty) return entry;

    final extra = entry.extra;

    return entry.copyWith(
      message: redact(entry.message, redactors),
      error: entry.error == null ? null : redact(entry.error, redactors),
      // The frames name types and files, not values, and a redactor let loose
      // on them turns a card-shaped memory address into stars for no gain.
      stackTrace: entry.stackTrace,
      extra: extra == null
          ? null
          : {
              for (final field in extra.entries)
                field.key: field.value is String
                    ? redact(field.value! as String, redactors)
                    : field.value,
            },
    );
  }
}

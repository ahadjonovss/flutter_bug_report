import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_bug_report/src/model/log_entry.dart';
import 'package:flutter_bug_report/src/store/log_store.dart';
import 'package:path_provider/path_provider.dart';

/// A log that survives the crash it is describing.
///
/// [MemoryLogStore] loses everything the process loses — including, at the
/// worst moment, the lines that explain why the process died. This one writes
/// them down, so the next launch can still file the report.
///
/// **Opt in knowingly.** A file on disk is a file that outlives the session,
/// and a phone that is shared, repaired or sold carries it along. That is why
/// this is not the default and never will be. Before switching it on, decide
/// three things:
///
/// * that your redactors cover what your app actually logs — redaction runs on
///   the way in, so whatever reaches this file is what stays there;
/// * that [retention] is as short as you can stand;
/// * that you call `BugReport.clear()` on sign-out, if the log could name the
///   person who just left.
///
/// ```dart
/// await BugReport.init(store: FileLogStore(retention: Duration(days: 3)));
/// ```
///
/// Writes are buffered and flushed on a timer, so logging stays a cheap call
/// and the disk is touched in batches rather than per line.
class FileLogStore implements LogStore {
  FileLogStore({
    this.maxEntries = 5000,
    this.retention = const Duration(days: 7),
    this.flushInterval = const Duration(seconds: 2),
    this.directory,
    this.fileName = 'bug_report_log.jsonl',
  }) : assert(maxEntries > 0, 'a store that keeps nothing bundles nothing');

  /// How many lines to keep. Past this the oldest go.
  final int maxEntries;

  /// How long a line is allowed to sit on the device.
  ///
  /// Anything older is dropped when the store opens. Shorter is safer: the log
  /// is only useful for a bug somebody is still chasing.
  final Duration retention;

  final Duration flushInterval;

  /// Where the file lives. Defaults to the app's support directory, which is
  /// not user-visible and is not backed up to iCloud or Google Drive — a log
  /// syncing to somebody's cloud is not a thing you want to explain.
  final Directory? directory;

  final String fileName;

  File? _file;
  Timer? _timer;
  final List<LogEntry> _buffer = [];
  bool _isFlushing = false;

  @override
  Future<void> open() async {
    final dir = directory ?? await getApplicationSupportDirectory();
    final file = _file = File('${dir.path}${Platform.pathSeparator}$fileName');

    await file.parent.create(recursive: true);
    if (!file.existsSync()) await file.create();

    await _prune();
    _timer = Timer.periodic(flushInterval, (_) => unawaited(_flush()));
  }

  @override
  Future<void> write(LogEntry entry) async {
    _buffer.add(entry);
    // A burst should not sit in memory waiting for the timer.
    if (_buffer.length >= 50) await _flush();
  }

  @override
  Future<List<LogEntry>> read({int? limit}) async {
    await _flush();

    final file = _file;
    if (file == null || !file.existsSync()) return const [];

    final lines = await file.readAsLines();
    final kept = limit == null || limit >= lines.length
        ? lines
        : lines.sublist(lines.length - limit);

    final entries = <LogEntry>[];
    for (final line in kept) {
      if (line.trim().isEmpty) continue;
      final entry = _decode(line);
      if (entry != null) entries.add(entry);
    }

    return entries;
  }

  @override
  Future<void> clear() async {
    _buffer.clear();
    final file = _file;
    if (file != null && file.existsSync()) await file.writeAsString('');
  }

  @override
  Future<void> close() async {
    _timer?.cancel();
    _timer = null;
    await _flush();
  }

  /// Appends the buffer in one write, so a hundred log calls cost one syscall.
  Future<void> _flush() async {
    if (_isFlushing || _buffer.isEmpty) return;

    final file = _file;
    if (file == null) return;

    _isFlushing = true;
    try {
      final pending = List<LogEntry>.of(_buffer);
      _buffer.clear();

      final text = pending.map((e) => jsonEncode(e.toMap())).join('\n');
      await file.writeAsString('$text\n', mode: FileMode.append, flush: true);

      await _prune();
    } on Object {
      // A log that throws while being written turns one bug into two.
    } finally {
      _isFlushing = false;
    }
  }

  /// Drops what is too old and what is over the count, in one rewrite.
  Future<void> _prune() async {
    final file = _file;
    if (file == null || !file.existsSync()) return;

    final lines = await file.readAsLines();
    final cutoff = DateTime.now().toUtc().subtract(retention);

    var kept = [
      for (final line in lines)
        if (line.trim().isNotEmpty && _isRecent(line, cutoff)) line,
    ];

    if (kept.length > maxEntries) {
      kept = kept.sublist(kept.length - maxEntries);
    }

    if (kept.length != lines.length) {
      await file.writeAsString(kept.isEmpty ? '' : '${kept.join('\n')}\n');
    }
  }

  bool _isRecent(String line, DateTime cutoff) {
    try {
      final at = DateTime.tryParse(
        (jsonDecode(line) as Map<String, Object?>)['time'] as String? ?? '',
      );

      return at == null || at.isAfter(cutoff);
    } on Object {
      // Unreadable lines are dropped rather than kept forever.
      return false;
    }
  }

  LogEntry? _decode(String line) {
    try {
      return LogEntry.fromMap(jsonDecode(line) as Map<String, Object?>);
    } on Object {
      return null;
    }
  }
}

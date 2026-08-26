import 'package:flutter_bug_report/src/model/log_entry.dart';

/// Where entries live between being written and being bundled.
///
/// Behind an interface because the right answer differs per app and neither
/// choice is safe as a default for the other. Memory keeps nothing on the
/// device — no file to grow unattended, nothing left behind on a phone that is
/// shared or sold — and loses everything the process loses. A store backed by
/// a database survives a crash and a restart, which is exactly what you want
/// when the bug you are chasing is the crash itself.
///
/// Asynchronous throughout, including where the in-memory implementation has
/// nothing to wait for: a store that writes to disk must fit here later without
/// every caller changing shape.
abstract interface class LogStore {
  /// Prepares the store. Called once by `BugReport.init`.
  Future<void> open();

  /// Takes one entry. Must not throw: it is called from `debugPrint`, from
  /// error handlers, and from paths that are already going wrong.
  Future<void> write(LogEntry entry);

  /// The tail, oldest first — the order a person reads a log in.
  ///
  /// [limit] counts from the newest end: the last hundred lines, not the first.
  Future<List<LogEntry>> read({int? limit});

  /// Drops everything. What a "clear logs" button calls, and what a sign-out
  /// should call if the logs could name the person who just left.
  Future<void> clear();

  Future<void> close();
}

/// Holds the tail of the log in memory and nothing anywhere else.
///
/// A ring: past [maxEntries] the oldest line goes to make room, so a long
/// session costs the same as a short one and no cleanup is ever due.
class MemoryLogStore implements LogStore {
  MemoryLogStore({this.maxEntries = 2000})
    : assert(maxEntries > 0, 'a store that keeps nothing bundles nothing');

  /// How many lines are worth carrying.
  ///
  /// The default is sized for a bug report rather than for an audit: a couple
  /// of thousand lines is several minutes of a busy app, which is the window a
  /// person can actually describe.
  final int maxEntries;

  final List<LogEntry> _entries = [];

  @override
  Future<void> open() async {}

  @override
  Future<void> write(LogEntry entry) async {
    _entries.add(entry);
    if (_entries.length > maxEntries) {
      _entries.removeRange(0, _entries.length - maxEntries);
    }
  }

  @override
  Future<List<LogEntry>> read({int? limit}) async {
    if (limit == null || limit >= _entries.length) {
      return List.unmodifiable(_entries);
    }

    return List.unmodifiable(_entries.sublist(_entries.length - limit));
  }

  @override
  Future<void> clear() async => _entries.clear();

  @override
  Future<void> close() async => _entries.clear();
}

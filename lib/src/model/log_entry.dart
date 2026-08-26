import 'package:flutter_bug_report/src/model/log_level.dart';

/// One line, with whatever it carries.
///
/// Immutable and free of Flutter: the same entry is written by a collector,
/// held by a store, rewritten by a redactor and read by a formatter, and none
/// of those should be able to change it under the others.
class LogEntry {
  LogEntry({
    required this.level,
    required this.message,
    DateTime? time,
    this.error,
    this.stackTrace,
    this.extra,
  }) : time = time ?? DateTime.now();

  /// Rebuilt from a stored row. [time] arrives as an ISO-8601 string because
  /// that is what survives both JSON and a SQL column unambiguously.
  factory LogEntry.fromMap(Map<String, Object?> map) => LogEntry(
    level: LogLevel.values.firstWhere(
      (level) => level.name == map['level'],
      orElse: () => LogLevel.info,
    ),
    message: map['message'] as String? ?? '',
    time: DateTime.tryParse(map['time'] as String? ?? ''),
    error: map['error'] as String?,
    stackTrace: map['stack_trace'] as String?,
    extra: (map['extra'] as Map?)?.cast<String, Object?>(),
  );

  final LogLevel level;

  final String message;

  final DateTime time;

  /// What was thrown, already turned into text.
  ///
  /// Text rather than the object: an entry outlives the frame it was made in,
  /// and holding the exception would hold everything it closes over with it —
  /// a response body, a widget, a whole cubit.
  final String? error;

  final String? stackTrace;

  /// Structured detail the message itself should not have to spell out — a
  /// status code, a route, a duration. Searchable in a json bundle; folded into
  /// the line in a txt one.
  final Map<String, Object?>? extra;

  LogEntry copyWith({
    String? message,
    String? error,
    String? stackTrace,
    Map<String, Object?>? extra,
  }) => LogEntry(
    level: level,
    message: message ?? this.message,
    time: time,
    error: error ?? this.error,
    stackTrace: stackTrace ?? this.stackTrace,
    extra: extra ?? this.extra,
  );

  Map<String, Object?> toMap() => {
    'time': time.toUtc().toIso8601String(),
    'level': level.name,
    'message': message,
    if (error != null) 'error': error,
    if (stackTrace != null) 'stack_trace': stackTrace,
    if (extra != null && extra!.isNotEmpty) 'extra': extra,
  };
}

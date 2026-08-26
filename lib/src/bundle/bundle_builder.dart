import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_bug_report/src/bundle/bundle.dart';
import 'package:flutter_bug_report/src/bundle/bundle_format.dart';
import 'package:flutter_bug_report/src/model/log_entry.dart';

/// Turns entries and a description into the thing that gets attached.
///
/// Kept apart from the store and the collectors, and free of Flutter, so what a
/// bundle looks like can be tested against a list of entries and nothing else.
class BundleBuilder {
  const BundleBuilder();

  /// How much of a stack trace is worth carrying per entry.
  ///
  /// The top of it says where the error came from; the rest is framework frames
  /// that read the same in every report and would crowd out the lines around
  /// them, which is what the reader actually came for.
  static const int defaultStackFrames = 12;

  /// The ceiling a bundle is built to, before compression.
  ///
  /// An attachment nobody can open is no better than none: mail gateways and
  /// issue trackers reject on the uncompressed size often enough that bounding
  /// it here is the only place it can be relied on.
  static const int defaultMaxBytes = 256 * 1024;

  Bundle build({
    required List<LogEntry> entries,
    required BundleFormat format,
    String? description,
    Map<String, String> metadata = const {},
    int maxBytes = defaultMaxBytes,
    int stackFrames = defaultStackFrames,
    DateTime? generatedAt,
  }) {
    final stamp = generatedAt ?? DateTime.now();

    // Trimmed from the front: a limit reached means the beginning of the
    // session goes, not the end. Whatever the person is reporting happened just
    // before they wrote it down.
    final kept = _fit(
      entries: entries,
      format: format,
      maxBytes: maxBytes,
      stackFrames: stackFrames,
    );
    final truncated = kept.length < entries.length;

    final report = <String, Object?>{
      'generated_at': stamp.toUtc().toIso8601String(),
      if (description != null && description.isNotEmpty)
        'description': description,
      'entry_count': kept.length,
      'truncated': truncated,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };

    final name = _fileName(stamp, format);
    final bytes = switch (format) {
      BundleFormat.text => _utf8(_asText(report, kept, stackFrames)),
      BundleFormat.json => _utf8(_asJson(report, kept)),
      BundleFormat.zip => _asZip(
        report: report,
        entries: kept,
        stackFrames: stackFrames,
      ),
    };

    return Bundle(
      bytes: bytes,
      fileName: name,
      format: format,
      entryCount: kept.length,
      truncated: truncated,
    );
  }

  /// The longest tail of [entries] that renders within [maxBytes].
  ///
  /// Measured by rendering rather than estimated: an entry carrying a stack
  /// trace is an order of magnitude larger than one that does not, and a guess
  /// that averages the two is wrong in both directions. Halving rather than
  /// stepping, so a very long history costs a handful of renders and not one
  /// per entry.
  List<LogEntry> _fit({
    required List<LogEntry> entries,
    required BundleFormat format,
    required int maxBytes,
    required int stackFrames,
  }) {
    if (entries.isEmpty) return entries;

    var count = entries.length;
    while (count > 1) {
      final tail = entries.sublist(entries.length - count);
      final rendered = format == BundleFormat.json
          ? _asJson(const {}, tail)
          : _asText(const {}, tail, stackFrames);

      if (utf8.encode(rendered).length <= maxBytes) return tail;
      count ~/= 2;
    }

    return entries.sublist(entries.length - 1);
  }

  String _asText(
    Map<String, Object?> report,
    List<LogEntry> entries,
    int stackFrames,
  ) {
    final buffer = StringBuffer();

    if (report.isNotEmpty) {
      buffer.writeln('=== flutter_bug_report ===');
      for (final field in report.entries) {
        final value = field.value;
        if (value is Map<String, String>) {
          buffer.writeln('${field.key}:');
          for (final item in value.entries) {
            buffer.writeln('  ${item.key}: ${item.value}');
          }
        } else {
          buffer.writeln('${field.key}: $value');
        }
      }
      buffer.writeln('=' * 18);
      buffer.writeln();
    }

    for (final entry in entries) {
      buffer.writeln(_line(entry, stackFrames));
    }

    return buffer.toString();
  }

  /// One entry, with the level in a fixed column so the whole log reads down.
  String _line(LogEntry entry, int stackFrames) {
    final buffer = StringBuffer()
      ..write(entry.time.toUtc().toIso8601String())
      ..write(' ')
      ..write(entry.level.label)
      ..write(' ')
      ..write(entry.message);

    final extra = entry.extra;
    if (extra != null && extra.isNotEmpty) {
      buffer.write('\n  ${jsonEncode(extra)}');
    }

    final error = entry.error;
    if (error != null) buffer.write('\n  $error');

    final stackTrace = entry.stackTrace;
    if (stackTrace != null && stackTrace.isNotEmpty) {
      final frames = stackTrace
          .split('\n')
          .where((frame) => frame.trim().isNotEmpty)
          .take(stackFrames);
      buffer.write('\n  ${frames.join('\n  ')}');
    }

    return buffer.toString();
  }

  String _asJson(Map<String, Object?> report, List<LogEntry> entries) =>
      const JsonEncoder.withIndent('  ').convert({
        if (report.isNotEmpty) 'report': report,
        'entries': [for (final entry in entries) entry.toMap()],
      });

  /// Both renderings, side by side: one to read and one to query.
  Uint8List _asZip({
    required Map<String, Object?> report,
    required List<LogEntry> entries,
    required int stackFrames,
  }) {
    final logs = _utf8(_asText(const {}, entries, stackFrames));
    final meta = _utf8(_asJson(report, entries));

    final archive = Archive()
      ..addFile(ArchiveFile('logs.txt', logs.length, logs))
      ..addFile(ArchiveFile('report.json', meta.length, meta));

    final encoded = ZipEncoder().encode(archive);

    return Uint8List.fromList(encoded);
  }

  Uint8List _utf8(String value) => Uint8List.fromList(utf8.encode(value));

  /// `log-bundle-20260826-141233.zip` — sortable, and unambiguous in a
  /// directory that already holds yesterday's.
  String _fileName(DateTime stamp, BundleFormat format) {
    final utc = stamp.toUtc();
    String two(int value) => value.toString().padLeft(2, '0');

    final date = '${utc.year}${two(utc.month)}${two(utc.day)}';
    final time = '${two(utc.hour)}${two(utc.minute)}${two(utc.second)}';

    return 'log-bundle-$date-$time.${format.extension}';
  }
}

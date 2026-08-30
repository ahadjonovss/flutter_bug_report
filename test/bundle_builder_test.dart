import 'dart:typed_data';

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bug_report/flutter_bug_report.dart';

List<LogEntry> _entries(int count, {String prefix = 'line'}) => [
  for (var i = 0; i < count; i++)
    LogEntry(
      level: LogLevel.info,
      message: '$prefix $i',
      time: DateTime.utc(2026, 8, 26, 12, 0, i),
    ),
];

String _text(Bundle bundle) => utf8.decode(bundle.bytes);

void main() {
  const builder = BundleBuilder();
  final stamp = DateTime.utc(2026, 8, 26, 14, 12, 33);

  group('text', () {
    test('carries the header, the description and the lines', () {
      final bundle = builder.build(
        entries: _entries(3),
        format: BundleFormat.text,
        description: 'Payment screen froze',
        metadata: const {'app_version': '1.0.17+2185'},
        generatedAt: stamp,
      );

      final text = _text(bundle);

      expect(text, contains('Payment screen froze'));
      expect(text, contains('app_version: 1.0.17+2185'));
      expect(text, contains('line 0'));
      expect(text, contains('line 2'));
      expect(bundle.entryCount, 3);
      expect(bundle.truncated, isFalse);
    });

    test('an error and its frames are folded under the line', () {
      final bundle = builder.build(
        entries: [
          LogEntry(
            level: LogLevel.error,
            message: 'load failed',
            error: 'StateError: boom',
            stackTrace: List.generate(30, (i) => '#$i frame').join('\n'),
          ),
        ],
        format: BundleFormat.text,
        stackFrames: 4,
      );

      final text = _text(bundle);

      expect(text, contains('ERROR'));
      expect(text, contains('StateError: boom'));
      expect(text, contains('#3 frame'));
      // Past the cap the frames stop: the rest reads the same in every report.
      expect(text, isNot(contains('#4 frame')));
    });
  });

  group('json', () {
    test('is an object of report and entries', () {
      final bundle = builder.build(
        entries: _entries(2),
        format: BundleFormat.json,
        description: 'nothing loads',
        generatedAt: stamp,
      );

      final decoded = jsonDecode(_text(bundle)) as Map<String, dynamic>;
      final report = decoded['report']! as Map<String, dynamic>;

      expect(report['description'], 'nothing loads');
      expect(report['entry_count'], 2);
      expect(report['generated_at'], '2026-08-26T14:12:33.000Z');
      expect((decoded['entries']! as List).length, 2);
    });
  });

  group('zip', () {
    test('holds one file to read and one to query', () {
      final bundle = builder.build(
        entries: _entries(5),
        format: BundleFormat.zip,
        description: 'frozen',
        generatedAt: stamp,
      );

      final archive = ZipDecoder().decodeBytes(bundle.bytes);

      expect(archive.files.map((f) => f.name), containsAll(<String>[
        'logs.txt',
        'report.json',
      ]));

      final logs = utf8.decode(
        archive.files.firstWhere((f) => f.name == 'logs.txt').content as List<int>,
      );
      expect(logs, contains('line 4'));
    });

    test('compresses: a repetitive log is smaller zipped than plain', () {
      final entries = _entries(400, prefix: 'the same thing over and over');

      final plain = builder.build(
        entries: entries,
        format: BundleFormat.text,
      );
      final zipped = builder.build(entries: entries, format: BundleFormat.zip);

      expect(zipped.sizeInBytes, lessThan(plain.sizeInBytes));
    });
  });

  group('bounds', () {
    test('a log over the byte ceiling is cut from the front and says so', () {
      final bundle = builder.build(
        entries: _entries(2000),
        format: BundleFormat.text,
        maxBytes: 2048,
      );

      expect(bundle.truncated, isTrue);
      expect(bundle.entryCount, lessThan(2000));
      expect(bundle.sizeInBytes, lessThanOrEqualTo(2048 + 512));

      // The end of the session survives — that is where the report is.
      expect(_text(bundle), contains('line 1999'));
      expect(_text(bundle), isNot(contains('line 0 ')));
    });

    test('one enormous entry still produces a bundle', () {
      final bundle = builder.build(
        entries: [
          LogEntry(level: LogLevel.info, message: 'x' * 10000),
        ],
        format: BundleFormat.text,
        maxBytes: 100,
      );

      expect(bundle.entryCount, 1);
      expect(bundle.bytes, isNotEmpty);
    });

    test('an empty log is a bundle, not a crash', () {
      final bundle = builder.build(
        entries: const [],
        format: BundleFormat.json,
        description: 'nothing happened',
      );

      expect(bundle.entryCount, 0);
      expect(bundle.truncated, isFalse);
      expect(jsonDecode(_text(bundle)), isA<Map<String, dynamic>>());
    });
  });

  group('a screenshot', () {
    test('is named in a zip, which is the only place it can be', () {
      final bundle = builder.build(
        entries: _entries(1),
        format: BundleFormat.zip,
        generatedAt: stamp,
        screenshot: Uint8List.fromList([1, 2, 3]),
      );

      final report = jsonDecode(
        utf8.decode(
          ZipDecoder()
              .decodeBytes(bundle.bytes)
              .files
              .firstWhere((file) => file.name == 'report.json')
              .content as List<int>,
        ),
      ) as Map<String, dynamic>;

      expect(report['report']['screenshot'], 'screenshot.png');
    });

    /// A single document has nowhere to put a PNG, so a report that names one
    /// sends its reader looking for a file that was never there. Wrong through
    /// 0.3.0, which is why a viewer still has to survive the claim.
    test('is not named in text or json, where it cannot be', () {
      for (final format in [BundleFormat.text, BundleFormat.json]) {
        final bundle = builder.build(
          entries: _entries(1),
          format: format,
          generatedAt: stamp,
          screenshot: Uint8List.fromList([1, 2, 3]),
        );

        expect(
          _text(bundle),
          isNot(contains('screenshot')),
          reason: '${format.name} claimed an attachment it cannot carry',
        );
      }
    });
  });

  group('a header value spanning lines', () {
    /// The sheet takes four lines, so this is reachable by anyone who presses
    /// Enter. Unwrapped, it turns one field into several to anything reading
    /// the header back.
    test('is wrapped, so it stays one field', () {
      final bundle = builder.build(
        entries: _entries(1),
        format: BundleFormat.text,
        description: 'I pressed refresh\nand then pay',
        generatedAt: stamp,
      );

      expect(
        _text(bundle),
        contains('description: I pressed refresh\n  and then pay\n'),
      );
    });
  });

  group('file name', () {
    test('is sortable and carries the format', () {
      final bundle = builder.build(
        entries: _entries(1),
        format: BundleFormat.zip,
        generatedAt: stamp,
      );

      expect(bundle.fileName, 'log-bundle-20260826-141233.zip');
      expect(bundle.mimeType, 'application/zip');
    });
  });
}

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_bug_report/flutter_bug_report.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

/// Golden bundles, written by the real builder.
///
/// They are here for the log viewer, which parses this format from another
/// repository and in another language. A parser written against a *description*
/// of a format drifts from it the first time the format changes and nobody
/// remembers to say so; a parser tested against the builder's own output
/// cannot.
///
/// **To regenerate after a deliberate format change:** delete `test/fixtures/`
/// and run the suite. A missing file is written rather than failed, so the
/// diff of the regenerated files is the change, reviewable line by line.
void main() {
  final dir = Directory('test/fixtures');

  /// A 1×1 PNG. Small on purpose — it is here to prove a zip carries the file
  /// and names it, not to be looked at.
  final screenshot = Uint8List.fromList(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
      '+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
    ),
  );

  setUpAll(() {
    if (!dir.existsSync()) dir.createSync(recursive: true);
  });

  for (final fixture in fixtures) {
    for (final format in fixture.formats) {
      test('${fixture.name}.${format.extension}', () {
        final built = const BundleBuilder().build(
          entries: fixture.entries,
          format: format,
          description: fixture.description,
          metadata: fixture.metadata,
          maxBytes: fixture.maxBytes,
          generatedAt: fixedStamp,
          screenshot: fixture.withScreenshot ? screenshot : null,
        );

        final file = File('${dir.path}/${fixture.name}.${format.extension}');
        if (!file.existsSync()) {
          file.writeAsBytesSync(built.bytes);
          printOnFailure('wrote ${file.path}');

          return;
        }

        final golden = file.readAsBytesSync();

        // A zip is compared by what is in it, not by its bytes: an archive
        // records a modification time, so two runs of the same input do not
        // produce the same file and never can.
        if (format == BundleFormat.zip) {
          expect(
            _unzip(built.bytes),
            _unzip(golden),
            reason: 'zip contents drifted — see the doc comment to regenerate',
          );

          return;
        }

        expect(
          utf8.decode(built.bytes),
          utf8.decode(golden),
          reason: '${fixture.name}.${format.extension} drifted — '
              'see the doc comment to regenerate',
        );
      });
    }
  }

  test('the fixture index names every case', () {
    final buffer = StringBuffer()
      ..writeln('# Golden bundles')
      ..writeln()
      ..writeln('Written by `flutter_bug_report`\'s own builder, from')
      ..writeln('`test/fixtures.dart`. The log viewer parses these; do not')
      ..writeln('edit them by hand.')
      ..writeln()
      ..writeln('Regenerate by deleting this directory and running')
      ..writeln('`flutter test`.')
      ..writeln();

    for (final fixture in fixtures) {
      final names =
          fixture.formats.map((f) => '`${fixture.name}.${f.extension}`');
      buffer
        ..writeln('### ${names.join(', ')}')
        ..writeln()
        ..writeln(fixture.why)
        ..writeln();
    }

    File('${dir.path}/README.md').writeAsStringSync(buffer.toString());
  });
}

/// Every file in an archive, as name → contents, so two zips can be compared
/// on what they carry.
Map<String, String> _unzip(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);

  return {
    for (final file in archive.files)
      file.name: file.name.endsWith('.png')
          // A PNG has no text form worth diffing; that it is there and the
          // right size is the whole assertion.
          ? 'binary:${file.size}'
          : utf8.decode(file.content as List<int>),
  };
}

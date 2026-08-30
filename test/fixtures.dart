/// The bundles under `test/fixtures/`, and what each one is for.
///
/// Shared by the generator that writes them and the test that checks they have
/// not drifted, so the two cannot disagree about what a case is.
///
/// They exist for a second reader as much as for this repository: the log
/// viewer parses these files, and a parser written against a description of a
/// format rather than against its output is a parser that is wrong somewhere
/// nobody has looked yet.
library;

import 'package:flutter_bug_report/src/bundle/bundle_format.dart';
import 'package:flutter_bug_report/src/model/log_entry.dart';
import 'package:flutter_bug_report/src/model/log_level.dart';

/// Fixed, so a regenerated fixture differs only where the builder changed.
final DateTime fixedStamp = DateTime.utc(2026, 8, 26, 7, 19, 11, 214, 967);

LogEntry _entry(
  int msOffset,
  LogLevel level,
  String message, {
  String? error,
  String? stackTrace,
  Map<String, Object?>? extra,
}) => LogEntry(
  level: level,
  message: message,
  error: error,
  stackTrace: stackTrace,
  extra: extra,
  time: fixedStamp.add(Duration(milliseconds: msOffset)),
);

class Fixture {
  const Fixture({
    required this.name,
    required this.why,
    required this.entries,
    required this.formats,
    this.description,
    this.metadata = const {},
    this.maxBytes = 256 * 1024,
    this.withScreenshot = false,
  });

  /// File stem. The extension comes from the format.
  final String name;

  /// What a parser is supposed to learn from this one.
  final String why;

  final List<LogEntry> entries;
  final List<BundleFormat> formats;
  final String? description;
  final Map<String, String> metadata;
  final int maxBytes;
  final bool withScreenshot;
}

const _ordinaryMetadata = {
  'app_version': '1.0.17+2185',
  'platform': 'android',
  'os_version': 'Android 14',
};

/// A Flutter error banner, arriving through `debugPrint` as one string.
///
/// The reason an entry boundary cannot be "a line that is not indented": this
/// message is several lines and none of them are.
const _banner = '''
══╡ EXCEPTION CAUGHT BY WIDGETS LIBRARY ╞═══════════════════════
The following assertion was thrown building ClientsPage:
A RenderFlex overflowed by 42 pixels on the bottom.''';

final List<Fixture> fixtures = [
  Fixture(
    name: 'ordinary',
    why: 'The shape everything else is a deviation from.',
    description: 'The client list was empty after I pressed refresh',
    metadata: _ordinaryMetadata,
    formats: BundleFormat.values,
    entries: [
      _entry(0, LogLevel.info, 'signed in'),
      _entry(
        8,
        LogLevel.info,
        'GET /clients',
        extra: const {
          'status': 500,
          'authorization': 'Bearer «redacted»',
          'ms': 1840,
        },
      ),
      _entry(9, LogLevel.warning, 'retrying in 2s'),
      _entry(10, LogLevel.info, 'paid with card ************4242'),
      _entry(
        11,
        LogLevel.error,
        'could not load clients',
        error: 'Bad state: clients came back null',
        stackTrace: '#0      ClientsCubit.load '
            '(package:app/clients_cubit.dart:41:7)\n'
            '#1      _rootRunUnary (dart:async/zone.dart:1407:13)\n'
            '<asynchronous suspension>',
      ),
    ],
  ),
  Fixture(
    name: 'multiline_message',
    why: 'A message spanning lines, written unindented. Entry boundaries have '
        'to be anchored on the timestamp and the padded level, never on '
        'indentation.',
    description: 'it crashed on the clients screen',
    metadata: _ordinaryMetadata,
    formats: BundleFormat.values,
    entries: [
      _entry(0, LogLevel.info, 'opened the clients screen'),
      _entry(4, LogLevel.debug, _banner),
      _entry(9, LogLevel.error, 'could not load clients'),
    ],
  ),
  Fixture(
    name: 'multiline_description',
    why: 'The sheet takes four lines, so a description can carry line breaks. '
        'In text they are wrapped two-space indented, like the metadata block.',
    description: 'I pressed refresh\n'
        'and then pay\n'
        'and the list was still empty',
    metadata: _ordinaryMetadata,
    formats: BundleFormat.values,
    entries: [_entry(0, LogLevel.info, 'opened the payment screen')],
  ),
  Fixture(
    name: 'no_metadata',
    why: 'Every optional field absent at once: no description, no metadata, no '
        'error, no stack, no extra. Nothing may be assumed present.',
    formats: BundleFormat.values,
    entries: [
      _entry(0, LogLevel.info, 'signed in'),
      _entry(3, LogLevel.debug, 'cache warm'),
    ],
  ),
  Fixture(
    name: 'truncated',
    why: 'truncated: true, and entry_count below what went in. The beginning '
        'of the session is what was cut — the end is intact.',
    description: 'it has been slow all morning',
    metadata: _ordinaryMetadata,
    maxBytes: 400,
    formats: BundleFormat.values,
    entries: [
      for (var i = 0; i < 40; i++)
        _entry(i, LogLevel.info, 'line $i of a session that ran long'),
    ],
  ),
  Fixture(
    name: 'screenshot',
    why: 'A screenshot was attached. The zip carries screenshot.png and its '
        'report names it; the text and json forms name nothing, because '
        'nothing can be in them. Bundles from 0.3.0 and earlier claim it in '
        'all three — a viewer still has to handle the claim without the file.',
    description: 'the button is off the screen',
    metadata: _ordinaryMetadata,
    withScreenshot: true,
    formats: BundleFormat.values,
    entries: [_entry(0, LogLevel.warning, 'layout overflowed')],
  ),
  Fixture(
    name: 'timeline',
    why: 'A session with a real shape: a quiet stretch, a gap where nothing '
        'was logged, then everything going wrong at once. Every other fixture '
        'is stamped to the same instant so a regenerated file differs only '
        'where the builder changed — which makes them useless for anything '
        'that draws time. This one is for that.',
    description: 'it froze for a while and then died',
    metadata: _ordinaryMetadata,
    formats: BundleFormat.values,
    entries: [
      for (var i = 0; i < 6; i++)
        _entry(i * 900, LogLevel.info, 'polling for updates ($i)'),
      // Nothing for half a minute. The gap is the point.
      _entry(36000, LogLevel.info, 'user tapped pay'),
      _entry(36200, LogLevel.warning, 'no response in 200ms'),
      for (var i = 0; i < 5; i++)
        _entry(
          36400 + i * 40,
          LogLevel.error,
          'payment call failed, attempt ${i + 1}',
          error: 'TimeoutException after 0:00:30.000000',
        ),
      _entry(37000, LogLevel.error, 'giving up'),
    ],
  ),
  Fixture(
    name: 'empty',
    why: 'A report filed before anything was logged. Still a bundle.',
    description: 'nothing happens when I tap it',
    metadata: _ordinaryMetadata,
    formats: BundleFormat.values,
    entries: const [],
  ),
];

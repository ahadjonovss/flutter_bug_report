import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bug_report/flutter_bug_report.dart';

void main() {
  tearDown(() async {
    await BugReport.dispose();
  });

  group('init', () {
    test('logging before init is collected, not lost', () async {
      BugReport.info('something happened before anyone configured anything');

      expect(BugReport.isInitialised, isFalse);
      expect(
        (await BugReport.entries()).single.message,
        contains('before anyone configured anything'),
      );
    });

    test('init carries forward what was logged before it', () async {
      BugReport.info('during startup');

      await BugReport.init(captureConsole: false, captureErrors: false);
      BugReport.info('after init');

      expect(BugReport.isInitialised, isTrue);
      expect((await BugReport.entries()).map((e) => e.message), [
        'during startup',
        'after init',
      ]);
    });

    test('init twice does not carry the first session into the second',
        () async {
      await BugReport.init(captureConsole: false, captureErrors: false);
      BugReport.info('first session');

      await BugReport.init(captureConsole: false, captureErrors: false);

      expect(await BugReport.entries(), isEmpty);
    });

    test('init twice leaves one console wrapper, not two', () async {
      final printed = <String>[];
      final original = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) printed.add(message);
      };

      await BugReport.init(captureErrors: false);
      await BugReport.init(captureErrors: false);

      debugPrint('once');

      final entries = await BugReport.entries();
      await BugReport.dispose();
      debugPrint = original;

      expect(entries.where((e) => e.message == 'once'), hasLength(1));
      expect(printed.where((line) => line == 'once'), hasLength(1));
    });

    test('dispose puts the console back as it was found', () async {
      final original = debugPrint;

      await BugReport.init(captureErrors: false);
      expect(debugPrint, isNot(same(original)));

      await BugReport.dispose();

      expect(debugPrint, same(original));
      expect(BugReport.isInitialised, isFalse);
    });
  });

  group('collecting', () {
    test('a bundle holds what was logged, in order', () async {
      await BugReport.init(captureConsole: false, captureErrors: false);

      BugReport.info('opened the payment screen');
      BugReport.warning('retrying');
      BugReport.error('pay failed', error: StateError('boom'));

      final bundle = await BugReport.build(
        description: 'It froze when I pressed pay',
        metadata: const {'platform': 'android'},
        format: BundleFormat.text,
      );

      final text = utf8.decode(bundle.bytes);

      expect(bundle.entryCount, 3);
      expect(text, contains('It froze when I pressed pay'));
      expect(text, contains('platform: android'));
      expect(
        text.indexOf('opened the payment screen'),
        lessThan(text.indexOf('pay failed')),
      );
      expect(text, contains('Bad state: boom'));
    });

    test('a level below the minimum is not collected', () async {
      await BugReport.init(
        captureConsole: false,
        captureErrors: false,
        minimumLevel: LogLevel.warning,
      );

      BugReport.debug('noise');
      BugReport.info('more noise');
      BugReport.warning('kept');

      final entries = await BugReport.entries();

      expect(entries.map((e) => e.message), ['kept']);
    });

    test('debugPrint is captured and still reaches the console', () async {
      final printed = <String>[];
      final original = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) printed.add(message);
      };

      await BugReport.init(captureErrors: false);
      debugPrint('a plugin said something');

      final entries = await BugReport.entries();
      await BugReport.dispose();
      debugPrint = original;

      expect(entries.map((e) => e.message), contains('a plugin said something'));
      expect(printed, contains('a plugin said something'));
    });

    test('clear empties the log', () async {
      await BugReport.init(captureConsole: false, captureErrors: false);

      BugReport.info('something');
      await BugReport.clear();

      expect(await BugReport.entries(), isEmpty);
    });
  });

  group('redaction', () {
    test('a secret is gone from the bundle by default', () async {
      await BugReport.init(captureConsole: false, captureErrors: false);

      BugReport.info(
        'POST /auth {"phone":"998901234567","otp":"445566"}',
        extra: const {'authorization': 'Bearer s3cr3t-token', 'status': 200},
      );

      final text = utf8.decode(
        (await BugReport.build(format: BundleFormat.text)).bytes,
      );

      expect(text, isNot(contains('445566')));
      expect(text, isNot(contains('s3cr3t-token')));
      // What is left still reads: the route, the status, the phone.
      expect(text, contains('POST /auth'));
      expect(text, contains('200'));
    });

    test('it happens on the way in, so the store never holds the secret',
        () async {
      await BugReport.init(captureConsole: false, captureErrors: false);

      BugReport.info('token=s3cr3t');

      final entries = await BugReport.entries();

      expect(entries.single.message, isNot(contains('s3cr3t')));
    });

    test('passing no redactors turns it off, knowingly', () async {
      await BugReport.init(
        captureConsole: false,
        captureErrors: false,
        redactors: const [],
      );

      BugReport.info('token=s3cr3t');

      final entries = await BugReport.entries();

      expect(entries.single.message, contains('s3cr3t'));
    });
  });

  group('robustness', () {
    test('logging never throws, even when the store does', () async {
      await BugReport.init(
        store: _BrokenStore(),
        captureConsole: false,
        captureErrors: false,
      );

      expect(() => BugReport.info('into the void'), returnsNormally);
      await expectLater(BugReport.flush(), completes);
    });

    test('a bundle from an empty session is still a bundle', () async {
      await BugReport.init(captureConsole: false, captureErrors: false);

      final bundle = await BugReport.build(
        description: 'nothing to report',
      );

      expect(bundle.entryCount, 0);
      expect(bundle.bytes, isNotEmpty);
      expect(bundle.fileName, endsWith('.zip'));
    });
  });
}

/// A store that fails at everything, to prove a failing store cannot take the
/// app down with it.
class _BrokenStore implements LogStore {
  @override
  Future<void> open() async {}

  @override
  Future<void> write(LogEntry entry) async => throw StateError('disk is full');

  @override
  Future<List<LogEntry>> read({int? limit}) async => const [];

  @override
  Future<void> clear() async {}

  @override
  Future<void> close() async {}
}

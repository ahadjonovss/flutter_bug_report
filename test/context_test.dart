import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bug_report/flutter_bug_report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() async => BugReport.dispose());

  group('DeviceFacts', () {
    test('names the platform and the build, and no device id', () {
      final facts = DeviceFacts.collect();

      expect(facts['platform'], isNotEmpty);
      expect(facts['build_mode'], anyOf('debug', 'profile', 'release'));
      // The line this package will not cross without being asked.
      expect(facts.keys, isNot(contains('device_id')));
      expect(facts.keys, isNot(contains('advertising_id')));
    });
  });

  group('metadata', () {
    test('device facts ride along, and yours win over them', () async {
      await BugReport.init(captureConsole: false, captureErrors: false);
      BugReport.info('hello');

      final bundle = await BugReport.build(
        description: 'x',
        metadata: const {'platform': 'mine', 'app_version': '1.2.3'},
      );

      expect(bundle.metadata['app_version'], '1.2.3');
      expect(bundle.metadata['platform'], 'mine', reason: 'yours last');
      expect(bundle.metadata['build_mode'], isNotNull);
    });

    test('deviceFacts: false sends none of it', () async {
      await BugReport.init(
        captureConsole: false,
        captureErrors: false,
        deviceFacts: false,
      );
      BugReport.info('hello');

      final bundle = await BugReport.build(description: 'x');

      expect(bundle.metadata['build_mode'], isNull);
    });

    test('identify tags the bundle, and null untags it', () async {
      await BugReport.init(captureConsole: false, captureErrors: false);

      BugReport.identify('merchant-42');
      expect(
        (await BugReport.build(description: 'x')).metadata['user_id'],
        'merchant-42',
      );

      BugReport.identify(null);
      expect(
        (await BugReport.build(description: 'x')).metadata['user_id'],
        isNull,
      );
    });
  });

  group('screenshot', () {
    test('rides in the zip when given, and is absent when not', () async {
      await BugReport.init(captureConsole: false, captureErrors: false);
      BugReport.info('hello');

      final withShot = await BugReport.build(
        description: 'x',
        screenshot: Uint8List.fromList(const [137, 80, 78, 71, 1, 2, 3]),
      );
      final without = await BugReport.build(description: 'x');

      expect(_names(withShot), contains('screenshot.png'));
      expect(_names(without), isNot(contains('screenshot.png')));

      // And the report says it is there, so a reader knows to look.
      expect(_report(withShot)['screenshot'], 'screenshot.png');
      expect(_report(without).containsKey('screenshot'), isFalse);
    });
  });

  group('BugReportObserver', () {
    test('records the route names and not their arguments', () async {
      await BugReport.init(captureConsole: false, captureErrors: false);

      final observer = BugReportObserver();
      observer.didPush(
        _route('/clients', const {'client_id': 42, 'phone': '998901234567'}),
        _route('/home', null),
      );

      final logs = (await BugReport.entries()).map((e) => e.message).join('\n');

      expect(logs, contains('route: push /clients'));
      expect(logs, contains('← /home'));
      expect(logs, isNot(contains('998901234567')));
      expect(logs, isNot(contains('42')));
    });
  });
}

Route<dynamic> _route(String name, Object? arguments) => PageRouteBuilder<void>(
      settings: RouteSettings(name: name, arguments: arguments),
      pageBuilder: (_, __, ___) => const SizedBox.shrink(),
    );

Iterable<String> _names(Bundle bundle) =>
    ZipDecoder().decodeBytes(bundle.bytes).files.map((f) => f.name);

Map<String, Object?> _report(Bundle bundle) {
  final file = ZipDecoder()
      .decodeBytes(bundle.bytes)
      .files
      .firstWhere((f) => f.name == 'report.json');

  return (jsonDecode(utf8.decode(file.content as List<int>))
      as Map<String, Object?>)['report']! as Map<String, Object?>;
}

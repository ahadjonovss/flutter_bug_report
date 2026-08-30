import 'package:flutter/material.dart';
import 'package:flutter_bug_report/flutter_bug_report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() async => BugReport.dispose());

  Future<void> pumpSheet(
    WidgetTester tester, {
    required BugReportSender onSubmit,
    BugReportMetadata? metadata,
    BugReportStrings strings = const BugReportStrings(),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BugReportSheet(
            onSubmit: onSubmit,
            metadata: metadata,
            strings: strings,
            // No self-closing timer: a timer outliving the widget tree is an
            // error in a test, and closing is not what these assert on.
            closeDelay: null,
          ),
        ),
      ),
    );
  }

  /// The sheet builds a real zip, which takes a turn or two to finish.
  ///
  /// pumpAndSettle is no good here: it waits for animations to stop, and the
  /// spinner it would wait on never does. Plain pumps advance the work and
  /// leave when it is done.
  /// Taps send and waits for the whole chain — metadata, the zip, the send —
  /// to actually finish.
  ///
  /// Inside `runAsync`, because the chain is real asynchronous work and the
  /// fake clock a widget test runs on will not carry it. pumpAndSettle is no
  /// good either: it waits for animations to stop, and the spinner it would
  /// wait on never does.
  Future<void> tapSend(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.tap(find.byType(FilledButton));
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await tester.pump();
  }

  group('BugReportSheet', () {
    testWidgets('will not send a line too short to act on', (tester) async {
      var called = false;
      await pumpSheet(tester, onSubmit: (_, __) async {
        called = true;
        return true;
      });

      await tester.tap(find.byType(FilledButton));
      await tester.pump();

      expect(called, isFalse);
      expect(find.text(const BugReportStrings().tooShort), findsOneWidget);
    });

    testWidgets('sends what was typed, with the log attached', (tester) async {
      // Logged in the real zone, like the send below: a queue built on the
      // widget test's fake clock never drains inside runAsync, and mixing the
      // two is the one way to make this package look broken.
      await tester.runAsync(() async {
        BugReport.info('opened the payment screen');
        await BugReport.flush();
      });

      Bundle? filed;
      String? said;
      await pumpSheet(tester, onSubmit: (bundle, description) async {
        filed = bundle;
        said = description;
        return true;
      });

      await tester.enterText(find.byType(TextField), '  it froze on pay  ');
      await tapSend(tester);

      expect(said, 'it froze on pay', reason: 'trimmed');
      expect(filed, isNotNull);
      expect(filed!.mimeType, 'application/zip');
      expect(filed!.entryCount, greaterThan(0));
    });

    testWidgets('carries the metadata it was given', (tester) async {
      Bundle? filed;
      await pumpSheet(
        tester,
        metadata: () async => {'app_version': '1.2.3', 'platform': 'android'},
        onSubmit: (bundle, _) async {
          filed = bundle;
          return true;
        },
      );

      await tester.enterText(find.byType(TextField), 'the list was empty');
      await tapSend(tester);

      expect(filed!.metadata['app_version'], '1.2.3');
    });

    testWidgets('a send that fails says so and keeps what was written',
        (tester) async {
      await pumpSheet(tester, onSubmit: (_, __) async => false);

      await tester.enterText(find.byType(TextField), 'the list was empty');
      await tapSend(tester);

      expect(find.text(const BugReportStrings().failed), findsOneWidget);
      expect(find.text('the list was empty'), findsOneWidget);
    });

    testWidgets('a sender that throws does not take the sheet down',
        (tester) async {
      await pumpSheet(tester, onSubmit: (_, __) async => throw StateError('no'));

      await tester.enterText(find.byType(TextField), 'the list was empty');
      await tapSend(tester);

      expect(find.text(const BugReportStrings().failed), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    /// Opens the sheet the way an app does — through `show`, inside a modal
    /// route. The tests above pump it into a Scaffold body, which hands it a
    /// tight full-screen height and so cannot see how it lays itself out when
    /// the height is its own to choose.
    Future<void> openSheet(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => BugReportSheet.show(
                  context,
                  onSubmit: (_, __) async => true,
                  closeDelay: null,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('sits on the bottom edge, only as tall as its content',
        (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await openSheet(tester);

      final screen = tester.getSize(find.byType(MaterialApp));
      final sheet = tester.getRect(find.byType(BugReportSheet));

      // `isScrollControlled` offers the sheet the whole screen. Taking it
      // leaves a bottom sheet floating in the middle of one.
      expect(sheet.height, lessThan(screen.height * 0.75));
      expect(sheet.bottom, moreOrLessEquals(screen.height, epsilon: 1));
    });

    testWidgets('with the keyboard up it scrolls rather than overflows',
        (tester) async {
      // A short phone with the keyboard up has less room than the sheet wants.
      tester.view.physicalSize = const Size(400, 600);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 340);
      addTearDown(tester.view.reset);

      await openSheet(tester);

      expect(tester.takeException(), isNull);
      expect(find.text(const BugReportStrings().title), findsOneWidget);
    });

    testWidgets('speaks whatever words it is given', (tester) async {
      await pumpSheet(
        tester,
        onSubmit: (_, __) async => true,
        strings: const BugReportStrings(
          title: 'Muammo haqida xabar bering',
          send: 'Yuborish',
        ),
      );

      expect(find.text('Muammo haqida xabar bering'), findsOneWidget);
      expect(find.text('Yuborish'), findsOneWidget);
    });
  });

  group('BugReportWrapper', () {
    testWidgets('a long press opens the sheet', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: BugReportWrapper(
            onSubmit: (_, __) async => true,
            child: const Scaffold(body: Center(child: Text('app'))),
          ),
        ),
      );

      await tester.longPress(find.text('app'));
      await tester.pumpAndSettle();

      expect(find.text(const BugReportStrings().title), findsOneWidget);
    });

    testWidgets('disabled, it installs nothing at all', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: BugReportWrapper(
            enabled: false,
            onSubmit: (_, __) async => true,
            child: const Scaffold(body: Center(child: Text('app'))),
          ),
        ),
      );

      expect(find.byType(GestureDetector), findsNothing);

      await tester.longPress(find.text('app'));
      await tester.pumpAndSettle();

      expect(find.text(const BugReportStrings().title), findsNothing);
    });

    testWidgets('the none trigger leaves the gesture off', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: BugReportWrapper(
            trigger: BugReportTrigger.none,
            onSubmit: (_, __) async => true,
            child: const Scaffold(body: Center(child: Text('app'))),
          ),
        ),
      );

      await tester.longPress(find.text('app'));
      await tester.pumpAndSettle();

      expect(find.text(const BugReportStrings().title), findsNothing);
    });
  });
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bug_report/flutter_bug_report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() async => BugReport.dispose());

  Future<void> pumpSheet(WidgetTester tester, BugReportConfig config) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: BugReportSheet(config: config))),
    );
  }

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
      await pumpSheet(
        tester,
        BugReportConfig(onSubmit: (_, __) async {
          called = true;

          return true;
        }),
      );

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
      await pumpSheet(
        tester,
        BugReportConfig(onSubmit: (bundle, description) async {
          filed = bundle;
          said = description;

          return true;
        }),
      );

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
        BugReportConfig(
          metadata: () async => {'app_version': '1.2.3', 'platform': 'android'},
          onSubmit: (bundle, _) async {
            filed = bundle;

            return true;
          },
        ),
      );

      await tester.enterText(find.byType(TextField), 'the list was empty');
      await tapSend(tester);

      expect(filed!.metadata['app_version'], '1.2.3');
    });

    testWidgets('a send that fails says so and keeps what was written',
        (tester) async {
      await pumpSheet(tester, BugReportConfig(onSubmit: (_, __) async => false));

      await tester.enterText(find.byType(TextField), 'the list was empty');
      await tapSend(tester);

      expect(find.text(const BugReportStrings().failed), findsOneWidget);
      expect(find.text('the list was empty'), findsOneWidget);
    });

    testWidgets('a sender that throws does not take the sheet down',
        (tester) async {
      await pumpSheet(
        tester,
        BugReportConfig(onSubmit: (_, __) async => throw StateError('no')),
      );

      await tester.enterText(find.byType(TextField), 'the list was empty');
      await tapSend(tester);

      expect(find.text(const BugReportStrings().failed), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    /// The default `closeDelay` used to be a `Future.delayed` nothing could
    /// call off, so a test that sent successfully failed on a pending timer
    /// unless it pumped the delay away. This sends with the default and pumps
    /// nothing: the timer has to be gone on its own.
    testWidgets('a successful send leaves no timer behind', (tester) async {
      await pumpSheet(tester, BugReportConfig(onSubmit: (_, __) async => true));

      await tester.enterText(find.byType(TextField), 'the list was empty');
      await tapSend(tester);

      expect(find.text(const BugReportStrings().sent), findsWidgets);
    });

    testWidgets('while it is in flight it says so, not just a spinner',
        (tester) async {
      final held = Completer<bool>();
      await pumpSheet(
        tester,
        BugReportConfig(onSubmit: (_, __) => held.future),
      );

      await tester.enterText(find.byType(TextField), 'the list was empty');
      await tester.runAsync(() async {
        await tester.tap(find.byType(FilledButton));
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      await tester.pump();

      expect(find.text(const BugReportStrings().sending), findsOneWidget);

      held.complete(true);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    });

    testWidgets('cancel closes it, so a swipe is not the only way out',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => BugReportSheet.show(
                  context,
                  config: BugReportConfig(onSubmit: (_, __) async => true),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(BugReportSheet), findsOneWidget);

      await tester.tap(find.text(const BugReportStrings().cancel));
      await tester.pumpAndSettle();

      expect(find.byType(BugReportSheet), findsNothing);
    });

    testWidgets('showCancel false leaves it off', (tester) async {
      await pumpSheet(
        tester,
        BugReportConfig(
          showCancel: false,
          onSubmit: (_, __) async => true,
        ),
      );

      expect(find.text(const BugReportStrings().cancel), findsNothing);
    });

    testWidgets('draws the field and the button you give it', (tester) async {
      await pumpSheet(
        tester,
        BugReportConfig(
          onSubmit: (_, __) async => true,
          fieldBuilder: (context, controller, enabled) => TextField(
            controller: controller,
            enabled: enabled,
            key: const Key('our-field'),
          ),
          buttonBuilder: (context, onPressed, busy, label) => ElevatedButton(
            onPressed: onPressed,
            child: Text(label),
          ),
        ),
      );

      expect(find.byKey(const Key('our-field')), findsOneWidget);
      expect(find.byType(ElevatedButton), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing, reason: 'ours replaces it');
    });

    testWidgets('a custom button still files the report', (tester) async {
      var filed = false;
      await pumpSheet(
        tester,
        BugReportConfig(
          onSubmit: (_, __) async {
            filed = true;

            return true;
          },
          buttonBuilder: (context, onPressed, busy, label) => ElevatedButton(
            onPressed: onPressed,
            child: Text(label),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'the list was empty');
      await tester.runAsync(() async {
        await tester.tap(find.byType(ElevatedButton));
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      await tester.pump();

      expect(filed, isTrue);
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
                  config: BugReportConfig(onSubmit: (_, __) async => true),
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
        BugReportConfig(
          onSubmit: (_, __) async => true,
          strings: const BugReportStrings(
            title: 'Muammo haqida xabar bering',
            send: 'Yuborish',
          ),
        ),
      );

      expect(find.text('Muammo haqida xabar bering'), findsOneWidget);
      expect(find.text('Yuborish'), findsOneWidget);
    });
  });

  group('BugReportWrapper', () {
    Widget app({
      BugReportTrigger trigger = BugReportTrigger.longPress,
      bool enabled = true,
      BugReportTriggerCallback? onTrigger,
    }) => MaterialApp(
      home: BugReportWrapper(
        trigger: trigger,
        enabled: enabled,
        onTrigger: onTrigger,
        config: BugReportConfig(onSubmit: (_, __) async => true),
        child: const Scaffold(body: Center(child: Text('app'))),
      ),
    );

    testWidgets('a long press opens the sheet', (tester) async {
      await tester.pumpWidget(app());

      await tester.longPress(find.text('app'));
      await tester.pumpAndSettle();

      expect(find.text(const BugReportStrings().title), findsOneWidget);
    });

    testWidgets('disabled, it installs nothing at all', (tester) async {
      await tester.pumpWidget(app(enabled: false));

      expect(find.byType(GestureDetector), findsNothing);

      await tester.longPress(find.text('app'));
      await tester.pumpAndSettle();

      expect(find.text(const BugReportStrings().title), findsNothing);
    });

    testWidgets('the none trigger leaves the gesture off', (tester) async {
      await tester.pumpWidget(app(trigger: BugReportTrigger.none));

      await tester.longPress(find.text('app'));
      await tester.pumpAndSettle();

      expect(find.text(const BugReportStrings().title), findsNothing);
    });

    /// What an internal build wants: the same gesture reaches a menu, and the
    /// report is one of the things on it.
    testWidgets('onTrigger takes the gesture, and can still open the report',
        (tester) async {
      Future<void> Function()? offered;
      await tester.pumpWidget(
        app(onTrigger: (context, openReport) async => offered = openReport),
      );

      await tester.longPress(find.text('app'));
      await tester.pumpAndSettle();

      expect(find.byType(BugReportSheet), findsNothing, reason: 'intercepted');
      expect(offered, isNotNull);

      // Not awaited: `show` completes when the sheet *closes*, not when it
      // opens, so awaiting it here waits for a sheet nothing is going to shut.
      unawaited(offered!());
      await tester.pumpAndSettle();

      expect(find.byType(BugReportSheet), findsOneWidget);
    });
  });
}

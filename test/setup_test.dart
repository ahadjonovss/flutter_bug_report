import 'package:flutter/material.dart';
import 'package:flutter_bug_report/flutter_bug_report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() async => BugReport.dispose());

  /// Frames enough for a sheet to arrive, without pumpAndSettle — which waits
  /// for every animation to stop and so hangs on the sheet's own spinner.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('wrapper above MaterialApp, and nothing else at all',
      (tester) async {
    // Exactly what somebody writes after reading the first snippet: no
    // BugReport.init, no navigatorKey, no ensureInitialized.
    await tester.pumpWidget(
      BugReportWrapper(
        onSubmit: (bundle, description) async => true,
        child: const MaterialApp(home: Scaffold(body: Text('home'))),
      ),
    );
    await settle(tester);

    await tester.longPress(find.text('home'));
    await settle(tester);

    // The sheet lives under the app's own navigator, which the wrapper found
    // for itself — above MaterialApp its own context has no Material at all.
    expect(find.byType(BugReportSheet), findsOneWidget);
  });

  testWidgets('and inside MaterialApp.builder, where the context does work',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => BugReportWrapper(
          onSubmit: (bundle, description) async => true,
          child: child!,
        ),
        home: const Scaffold(body: Text('home')),
      ),
    );
    await settle(tester);

    await tester.longPress(find.text('home'));
    await settle(tester);

    expect(find.byType(BugReportSheet), findsOneWidget);
  });
}

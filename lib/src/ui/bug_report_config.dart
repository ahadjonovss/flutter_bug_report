import 'package:flutter/widgets.dart';
import 'package:flutter_bug_report/src/bundle/bundle.dart';
import 'package:flutter_bug_report/src/bundle/bundle_format.dart';
import 'package:flutter_bug_report/src/ui/bug_report_strings.dart';
import 'package:flutter_bug_report/src/ui/bug_report_theme.dart';

/// Files the report. Returns whether it got there.
///
/// The package builds the bundle and hands it over; where it goes is yours.
/// Return `false` and the sheet says so and keeps what the person wrote, so a
/// second attempt does not start from an empty field.
typedef BugReportSender = Future<bool> Function(
  Bundle bundle,
  String description,
);

/// Facts about the build and the phone, gathered when a report is filed.
///
/// A callback rather than a map so it is read at the moment of reporting, and
/// asynchronous because `package_info` and `device_info` both are. Whatever it
/// returns wins over the device facts collected automatically.
typedef BugReportMetadata = Future<Map<String, String>> Function();

/// Draws the description field.
///
/// Given the controller to bind and whether the field should still accept
/// typing. Return your own — an `AppTextField`, whatever your design system
/// calls it — and the sheet stops looking like a package bolted onto the app.
typedef BugReportFieldBuilder = Widget Function(
  BuildContext context,
  TextEditingController controller,
  bool enabled,
);

/// Draws the send button.
///
/// [onPressed] is null while the report is in flight or already filed, so a
/// button that respects it cannot file the same report twice. [busy] is true
/// only while it is in flight, for whatever you show instead of a label.
typedef BugReportButtonBuilder = Widget Function(
  BuildContext context,
  VoidCallback? onPressed,
  bool busy,
  String label,
);

/// Everything about a report: what it carries, what it says, how it looks.
///
/// One object rather than a parameter list, because there are two places that
/// open a sheet — [BugReportWrapper] and `BugReportSheet.show` — and a
/// parameter that exists on one and not the other is how an app ends up with
/// two differently-configured reports it believes are the same one.
///
/// ```dart
/// final reportConfig = BugReportConfig(
///   onSubmit: (bundle, description) => myBackend.upload(bundle),
///   metadata: () async => {'app_version': version},
/// );
///
/// BugReportWrapper(config: reportConfig, child: MaterialApp(...));
/// BugReportSheet.show(context, config: reportConfig);   // the same report
/// ```
@immutable
class BugReportConfig {
  const BugReportConfig({
    required this.onSubmit,
    this.metadata,
    this.strings = const BugReportStrings(),
    this.theme = const BugReportTheme(),
    this.minLength = 5,
    this.maxLength = 500,
    this.format = BundleFormat.zip,
    this.limit = 300,
    this.closeDelay = const Duration(milliseconds: 1200),
    this.showCancel = true,
    this.fieldBuilder,
    this.buttonBuilder,
  });

  /// The one thing you must write, and the point of the package: it builds the
  /// file and never decides where it goes.
  final BugReportSender onSubmit;

  final BugReportMetadata? metadata;
  final BugReportStrings strings;
  final BugReportTheme theme;

  /// The shortest description worth filing. Below this the report says nothing
  /// the log does not already, and the person is better off writing another
  /// line — which is what the sheet asks them to do.
  final int minLength;

  final int maxLength;

  /// What the attachment is. Zip by default: every tracker takes one, and it
  /// survives a size limit a plain log would not.
  final BundleFormat format;

  /// How many entries to carry.
  final int limit;

  /// How long the thanks stays up before the sheet closes itself.
  ///
  /// Null keeps it open, for a flow that closes it on its own terms. Under a
  /// widget test the sheet does not schedule this at all — see
  /// [BugReportSheet] — so a test never has to pump the delay away.
  final Duration? closeDelay;

  /// Whether the sheet offers a way out other than swiping it down.
  ///
  /// On by default. A modal whose only dismissal is a gesture is a modal some
  /// people are stuck in, and the person stuck in it is the one who already
  /// has a problem to report.
  final bool showCancel;

  /// Draw the field yourself. Null uses the built-in one.
  final BugReportFieldBuilder? fieldBuilder;

  /// Draw the send button yourself. Null uses the built-in one.
  final BugReportButtonBuilder? buttonBuilder;

  BugReportConfig copyWith({
    BugReportSender? onSubmit,
    BugReportMetadata? metadata,
    BugReportStrings? strings,
    BugReportTheme? theme,
    int? minLength,
    int? maxLength,
    BundleFormat? format,
    int? limit,
    Duration? closeDelay,
    bool? showCancel,
    BugReportFieldBuilder? fieldBuilder,
    BugReportButtonBuilder? buttonBuilder,
  }) => BugReportConfig(
    onSubmit: onSubmit ?? this.onSubmit,
    metadata: metadata ?? this.metadata,
    strings: strings ?? this.strings,
    theme: theme ?? this.theme,
    minLength: minLength ?? this.minLength,
    maxLength: maxLength ?? this.maxLength,
    format: format ?? this.format,
    limit: limit ?? this.limit,
    closeDelay: closeDelay ?? this.closeDelay,
    showCancel: showCancel ?? this.showCancel,
    fieldBuilder: fieldBuilder ?? this.fieldBuilder,
    buttonBuilder: buttonBuilder ?? this.buttonBuilder,
  );
}

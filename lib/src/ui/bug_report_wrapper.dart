import 'package:flutter/material.dart';
import 'package:flutter_bug_report/src/bundle/bundle_format.dart';
import 'package:flutter_bug_report/src/ui/bug_report_sheet.dart';
import 'package:flutter_bug_report/src/ui/bug_report_strings.dart';
import 'package:flutter_bug_report/src/ui/bug_report_theme.dart';
import 'package:flutter_bug_report/src/ui/screenshot.dart';

/// What opens the sheet.
enum BugReportTrigger {
  /// A long press anywhere in the app.
  ///
  /// No button, and no entry buried in a settings page: the moment worth
  /// reporting is whatever screen the person is looking at, and asking them to
  /// navigate away from it to say so loses both the impulse and the context.
  longPress,

  /// A double tap anywhere. Quicker than a long press, and easier to trigger
  /// by accident — worth it on an internal build, rarely on a public one.
  doubleTap,

  /// Nothing. Open the sheet yourself with [BugReportSheet.show] — from a menu
  /// item, a shake detector, a debug screen, wherever it belongs.
  none,
}

/// Wraps the app so a report is always one gesture away.
///
/// Put it above your navigator so the gesture covers every screen:
///
/// ```dart
/// BugReportWrapper(
///   onSubmit: (bundle, description) => myBackend.upload(bundle),
///   metadata: () async => {'app_version': version, 'platform': platform},
///   child: MaterialApp(...),
/// )
/// ```
///
/// Translucent, so nothing underneath stops working: a long press that a field
/// or a list row wants — text selection, for one — goes to that widget instead.
class BugReportWrapper extends StatefulWidget {
  const BugReportWrapper({
    required this.child,
    required this.onSubmit,
    this.metadata,
    this.trigger = BugReportTrigger.longPress,
    this.enabled = true,
    this.strings = const BugReportStrings(),
    this.theme = const BugReportTheme(),
    this.minLength = 5,
    this.maxLength = 500,
    this.format = BundleFormat.zip,
    this.limit = 300,
    this.closeDelay = const Duration(milliseconds: 1200),
    this.withScreenshot = false,
    this.screenshotPixelRatio = 1.5,
    this.navigatorKey,
    super.key,
  });

  final Widget child;
  final BugReportSender onSubmit;
  final BugReportMetadata? metadata;
  final BugReportTrigger trigger;

  /// Whether the gesture is installed at all.
  ///
  /// Pass a compile-time constant — `!kReleaseMode`, or your own flavor flag —
  /// and a build with it false drops the gesture entirely rather than carrying
  /// a sheet it will never open.
  final bool enabled;

  final BugReportStrings strings;
  final BugReportTheme theme;
  final int minLength;
  final int maxLength;
  final BundleFormat format;
  final int limit;

  /// How long the thanks stays up before the sheet closes itself.
  final Duration? closeDelay;

  /// Whether to offer a screenshot of the screen the report was filed from.
  ///
  /// Off by default, and that is the right default. A screenshot carries
  /// whatever the screen carried — a name, a number, a balance — and unlike a
  /// log it cannot be redacted, because nothing here can read it.
  ///
  /// Turned on, the sheet shows the person the picture before it goes and lets
  /// them drop it. Nobody should find out afterwards what they sent.
  final bool withScreenshot;

  /// Resolution of that screenshot. Low on purpose: a full-resolution capture
  /// is megabytes, and megabytes do not upload on one bar of signal.
  final double screenshotPixelRatio;

  /// The navigator the sheet opens on.
  ///
  /// Needed when this sits *above* `MaterialApp`, because then its own context
  /// has no navigator under it. Pass the same key you gave the app. Leave it
  /// null when the wrapper is inside the app instead.
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  State<BugReportWrapper> createState() => _BugReportWrapperState();
}

class _BugReportWrapperState extends State<BugReportWrapper> {
  /// True while the sheet is up. The gesture covers the whole app, the sheet
  /// included, so without this a second long press would put one report on
  /// top of another.
  bool _isOpen = false;


  /// Wraps the app when — and only when — a screenshot may be taken. A
  /// repaint boundary is not free, and an app that will never capture one
  /// should not pay for it.
  final GlobalKey _boundary = GlobalKey();

  /// A context that can actually open a modal sheet.
  ///
  /// The natural way to install this is above `MaterialApp` —
  /// `runApp(BugReportWrapper(child: MaterialApp(...)))` — and that puts our
  /// own context *outside* Material, where `showModalBottomSheet` throws for
  /// want of `MaterialLocalizations`. Rather than make everyone wire a
  /// `navigatorKey` for the common case, look down the tree for the navigator
  /// the app already has.
  ///
  /// Falls back to our own context, which is the right one when this is
  /// installed inside the app instead — as `MaterialApp(builder: ...)`.
  BuildContext _navigatorContext() {
    BuildContext? found;

    void search(Element element) {
      if (found != null) return;
      if (element.widget is Navigator) {
        found = element;

        return;
      }
      element.visitChildren(search);
    }

    if (mounted) context.visitChildElements(search);

    return found ?? context;
  }

  Future<void> _open() async {
    if (_isOpen) return;

    // Captured before the sheet is up, so the picture is of the screen they
    // are reporting rather than of the form they are reporting it on.
    final shot = widget.withScreenshot
        ? await Screenshot.capture(
            _boundary,
            pixelRatio: widget.screenshotPixelRatio,
          )
        : null;

    final context = widget.navigatorKey?.currentContext ?? _navigatorContext();
    if (!context.mounted) return;

    _isOpen = true;
    try {
      await BugReportSheet.show(
        context,
        onSubmit: widget.onSubmit,
        metadata: widget.metadata,
        strings: widget.strings,
        theme: widget.theme,
        minLength: widget.minLength,
        maxLength: widget.maxLength,
        format: widget.format,
        limit: widget.limit,
        closeDelay: widget.closeDelay,
        screenshot: shot,
      );
    } finally {
      _isOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    final child = widget.withScreenshot
        ? RepaintBoundary(key: _boundary, child: widget.child)
        : widget.child;

    if (widget.trigger == BugReportTrigger.none) return child;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPress:
          widget.trigger == BugReportTrigger.longPress ? _open : null,
      onDoubleTap:
          widget.trigger == BugReportTrigger.doubleTap ? _open : null,
      child: child,
    );
  }
}

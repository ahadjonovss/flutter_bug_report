import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bug_report/src/bundle/bundle.dart';
import 'package:flutter_bug_report/src/bundle/bundle_format.dart';
import 'package:flutter_bug_report/src/bug_report_base.dart';
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
/// asynchronous because `package_info` and `device_info` both are. Deliberately
/// yours to fill: this package does not read the device, so it never has to
/// decide on your behalf what counts as identifying.
typedef BugReportMetadata = Future<Map<String, String>> Function();

/// The sheet a person writes their complaint into.
///
/// Everything visible is overridable — [strings] for the words, [theme] for the
/// look — and both default to something usable, so the shortest version of this
/// is one line:
///
/// ```dart
/// BugReportSheet.show(context, onSubmit: myUpload);
/// ```
class BugReportSheet extends StatefulWidget {
  const BugReportSheet({
    required this.onSubmit,
    this.metadata,
    this.strings = const BugReportStrings(),
    this.theme = const BugReportTheme(),
    this.minLength = 5,
    this.maxLength = 500,
    this.format = BundleFormat.zip,
    this.limit = 300,
    this.closeDelay = const Duration(milliseconds: 1200),
    this.screenshot,
    super.key,
  });

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
  /// Null keeps it open, for a flow that wants to close it on its own terms —
  /// or for a test, where a pending timer outliving the widget is an error.
  final Duration? closeDelay;

  /// A picture of the screen the report was filed from, if one was taken.
  ///
  /// Shown to the person before it goes, with a control to drop it. A
  /// screenshot cannot be redacted — nothing here can read what is in it — so
  /// consent has to come from someone who can.
  final Uint8List? screenshot;

  /// Opens the sheet, and closes it once the report is filed.
  static Future<void> show(
    BuildContext context, {
    required BugReportSender onSubmit,
    BugReportMetadata? metadata,
    BugReportStrings strings = const BugReportStrings(),
    BugReportTheme theme = const BugReportTheme(),
    int minLength = 5,
    int maxLength = 500,
    BundleFormat format = BundleFormat.zip,
    int limit = 300,
    Duration? closeDelay = const Duration(milliseconds: 1200),
    Uint8List? screenshot,
  }) {
    final radius = theme.radius ?? 20;

    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        // Above the keyboard, which is up the whole time this sheet is.
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Material(
          color: theme.background ?? Theme.of(context).canvasColor,
          borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            top: false,
            child: BugReportSheet(
              onSubmit: onSubmit,
              metadata: metadata,
              strings: strings,
              theme: theme,
              minLength: minLength,
              maxLength: maxLength,
              format: format,
              limit: limit,
              closeDelay: closeDelay,
              screenshot: screenshot,
            ),
          ),
        ),
      ),
    );
  }

  @override
  State<BugReportSheet> createState() => _BugReportSheetState();
}

/// Where the report is between the person writing it and the app filing it.
enum _Stage { writing, sending, sent, failed }

class _BugReportSheetState extends State<BugReportSheet> {
  final TextEditingController _controller = TextEditingController();
  _Stage _stage = _Stage.writing;
  bool _tooShort = false;

  /// Attached unless they say otherwise — but they can see it first, and one
  /// tap takes it out.
  late bool _attachShot = widget.screenshot != null;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_stage == _Stage.sending) return;

    final text = _controller.text.trim();
    if (text.length < widget.minLength) {
      setState(() => _tooShort = true);
      return;
    }

    setState(() {
      _tooShort = false;
      _stage = _Stage.sending;
    });

    try {
      final metadata = await widget.metadata?.call() ?? const <String, String>{};
      final bundle = await BugReport.build(
        description: text,
        metadata: metadata,
        format: widget.format,
        limit: widget.limit,
        screenshot: _attachShot ? widget.screenshot : null,
      );

      final filed = await widget.onSubmit(bundle, text);
      if (!mounted) return;

      setState(() => _stage = filed ? _Stage.sent : _Stage.failed);

      final delay = widget.closeDelay;
      if (filed && delay != null) {
        // Long enough to read the thanks, short enough not to be in the way.
        await Future<void>.delayed(delay);
        if (mounted) Navigator.of(context).maybePop();
      }
    } on Object catch (error, stackTrace) {
      // Reporting a problem must not become one.
      BugReport.error(
        'bug report: could not be filed',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() => _stage = _Stage.failed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context);
    final accent = widget.theme.accent ?? palette.colorScheme.primary;
    final onAccent = widget.theme.onAccent ?? palette.colorScheme.onPrimary;
    final radius = widget.theme.radius ?? 20;
    final strings = widget.strings;

    // Centred horizontally, but only as tall as what is in it. A plain Center
    // takes every pixel it is offered, and `isScrollControlled` offers the
    // whole screen — which is how a bottom sheet ends up floating in the
    // middle of one. `heightFactor` is what keeps it at the bottom.
    return Align(
      alignment: Alignment.bottomCenter,
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: widget.theme.maxWidth ?? 520),
        // Scrolls only once it has to: a short phone with the keyboard up has
        // less room than this sheet needs, and an overflow there is a stripe
        // across the report someone is trying to file.
        child: SingleChildScrollView(
          padding: widget.theme.padding ?? const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _grabber(palette),
              const SizedBox(height: 18),
              Text(
                strings.title,
                style: widget.theme.titleStyle ??
                    palette.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                strings.message,
                style: widget.theme.messageStyle ??
                    palette.textTheme.bodyMedium?.copyWith(
                      color: palette.textTheme.bodySmall?.color,
                      height: 1.45,
                    ),
              ),
              const SizedBox(height: 20),
              _field(palette, accent, radius, strings),
              if (_tooShort) ...[
                const SizedBox(height: 8),
                Text(
                  strings.tooShort,
                  style: palette.textTheme.bodySmall
                      ?.copyWith(color: palette.colorScheme.error),
                ),
              ],
              if (widget.screenshot != null) ...[
                const SizedBox(height: 14),
                _shot(palette, radius, strings),
              ],
              const SizedBox(height: 18),
              _button(accent, onAccent, radius, strings),
              if (_stage == _Stage.sent || _stage == _Stage.failed) ...[
                const SizedBox(height: 12),
                _outcome(palette, strings),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _grabber(ThemeData palette) => Center(
    child: Container(
      width: 38,
      height: 4,
      decoration: BoxDecoration(
        color: palette.dividerColor,
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );

  Widget _field(
    ThemeData palette,
    Color accent,
    double radius,
    BugReportStrings strings,
  ) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(radius * 0.6),
      borderSide: BorderSide(color: palette.dividerColor),
    );

    return TextField(
      controller: _controller,
      enabled: _stage != _Stage.sending && _stage != _Stage.sent,
      autofocus: true,
      maxLines: 4,
      minLines: 3,
      maxLength: widget.maxLength,
      textCapitalization: TextCapitalization.sentences,
      onChanged: (_) {
        if (_tooShort) setState(() => _tooShort = false);
      },
      decoration: InputDecoration(
        labelText: strings.fieldLabel,
        hintText: strings.hint,
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: BorderSide(color: accent, width: 1.6),
        ),
      ),
    );
  }

  Widget _button(
    Color accent,
    Color onAccent,
    double radius,
    BugReportStrings strings,
  ) {
    final busy = _stage == _Stage.sending;

    return FilledButton(
      onPressed: busy || _stage == _Stage.sent ? null : _submit,
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: onAccent,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius * 0.6),
        ),
      ),
      child: busy
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                valueColor: AlwaysStoppedAnimation<Color>(onAccent),
              ),
            )
          : Text(_stage == _Stage.sent ? strings.sent : strings.send),
    );
  }

  /// The picture, and the switch that decides whether it goes.
  ///
  /// Shown rather than described: "a screenshot will be attached" is a sentence
  /// people agree to without picturing what is on their screen.
  Widget _shot(ThemeData palette, double radius, BugReportStrings strings) {
    final editable = _stage == _Stage.writing || _stage == _Stage.failed;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(radius * 0.35),
          child: Opacity(
            opacity: _attachShot ? 1 : 0.35,
            child: Image.memory(
              widget.screenshot!,
              width: 44,
              height: 78,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            strings.screenshotLabel,
            style: palette.textTheme.bodySmall,
          ),
        ),
        Switch(
          value: _attachShot,
          onChanged: editable
              ? (value) => setState(() => _attachShot = value)
              : null,
        ),
      ],
    );
  }

  Widget _outcome(ThemeData palette, BugReportStrings strings) {
    final sent = _stage == _Stage.sent;

    return Text(
      sent ? strings.sent : strings.failed,
      textAlign: TextAlign.center,
      style: palette.textTheme.bodySmall?.copyWith(
        color: sent ? palette.colorScheme.primary : palette.colorScheme.error,
      ),
    );
  }
}

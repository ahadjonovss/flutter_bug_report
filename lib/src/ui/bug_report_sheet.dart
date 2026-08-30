import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bug_report/src/bug_report_base.dart';
import 'package:flutter_bug_report/src/ui/bug_report_config.dart';
import 'package:flutter_bug_report/src/ui/bug_report_strings.dart';

/// The sheet a person writes their complaint into.
///
/// Everything visible is overridable — the words, the colours, and the field
/// and button themselves — through [BugReportConfig]. The shortest version is
/// one line:
///
/// ```dart
/// BugReportSheet.show(context, config: myReportConfig);
/// ```
class BugReportSheet extends StatefulWidget {
  const BugReportSheet({
    required this.config,
    this.screenshot,
    super.key,
  });

  final BugReportConfig config;

  /// A picture of the screen the report was filed from, if one was taken.
  ///
  /// Shown to the person before it goes, with a control to drop it. A
  /// screenshot cannot be redacted — nothing here can read what is in it — so
  /// consent has to come from someone who can.
  final Uint8List? screenshot;

  /// Opens the sheet, and closes it once the report is filed.
  ///
  /// The future completes when the sheet *closes* — filed, cancelled or swiped
  /// away — not when it opens. Await it to know the report is over with; do
  /// not await it expecting the sheet to be on screen.
  static Future<void> show(
    BuildContext context, {
    required BugReportConfig config,
    Uint8List? screenshot,
  }) {
    final radius = config.theme.radius ?? 20;

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
          color: config.theme.background ?? Theme.of(context).canvasColor,
          borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            top: false,
            child: BugReportSheet(config: config, screenshot: screenshot),
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

  /// The self-close, held so it can be called off.
  ///
  /// A `Future.delayed` cannot be cancelled, and one left running past the end
  /// of a widget test is a failure with nothing wrong behind it: the test has
  /// to pump the delay away purely to satisfy the timer. A [Timer] cancelled
  /// in [dispose] leaves nothing pending.
  Timer? _closer;

  /// Attached unless they say otherwise — but they can see it first, and one
  /// tap takes it out.
  late bool _attachShot = widget.screenshot != null;

  BugReportConfig get _config => widget.config;

  @override
  void dispose() {
    _closer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_stage == _Stage.sending) return;

    final text = _controller.text.trim();
    if (text.length < _config.minLength) {
      setState(() => _tooShort = true);
      return;
    }

    setState(() {
      _tooShort = false;
      _stage = _Stage.sending;
    });

    try {
      final metadata = await _config.metadata?.call() ?? const <String, String>{};
      final bundle = await BugReport.build(
        description: text,
        metadata: metadata,
        format: _config.format,
        limit: _config.limit,
        screenshot: _attachShot ? widget.screenshot : null,
      );

      final filed = await _config.onSubmit(bundle, text);
      if (!mounted) return;

      setState(() => _stage = filed ? _Stage.sent : _Stage.failed);

      final delay = _config.closeDelay;
      if (filed && delay != null) {
        // Long enough to read the thanks, short enough not to be in the way.
        _closer = Timer(delay, () {
          if (mounted) Navigator.of(context).maybePop();
        });
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
    final accent = _config.theme.accent ?? palette.colorScheme.primary;
    final onAccent = _config.theme.onAccent ?? palette.colorScheme.onPrimary;
    final radius = _config.theme.radius ?? 20;
    final strings = _config.strings;

    // Centred horizontally, but only as tall as what is in it. A plain Center
    // takes every pixel it is offered, and `isScrollControlled` offers the
    // whole screen — which is how a bottom sheet ends up floating in the
    // middle of one. `heightFactor` is what keeps it at the bottom.
    return Align(
      alignment: Alignment.bottomCenter,
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: _config.theme.maxWidth ?? 520),
        // Scrolls only once it has to: a short phone with the keyboard up has
        // less room than this sheet needs, and an overflow there is a stripe
        // across the report someone is trying to file.
        child: SingleChildScrollView(
          padding: _config.theme.padding ?? const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _grabber(palette),
              const SizedBox(height: 18),
              Text(
                strings.title,
                style: _config.theme.titleStyle ??
                    palette.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                strings.message,
                style: _config.theme.messageStyle ??
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
              if (_config.showCancel) ...[
                const SizedBox(height: 4),
                _cancel(palette, strings),
              ],
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
    final enabled = _stage != _Stage.sending && _stage != _Stage.sent;

    final custom = _config.fieldBuilder;
    if (custom != null) return custom(context, _controller, enabled);

    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(radius * 0.6),
      borderSide: BorderSide(color: palette.dividerColor),
    );

    return TextField(
      controller: _controller,
      enabled: enabled,
      autofocus: true,
      maxLines: 4,
      minLines: 3,
      maxLength: _config.maxLength,
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
    final onPressed = busy || _stage == _Stage.sent ? null : _submit;
    final label = switch (_stage) {
      _Stage.sending => strings.sending,
      _Stage.sent => strings.sent,
      _ => strings.send,
    };

    final custom = _config.buttonBuilder;
    if (custom != null) return custom(context, onPressed, busy, label);

    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: onAccent,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius * 0.6),
        ),
      ),
      // The spinner says something is happening; the word says what. A
      // progress indicator on its own is the same picture for a send, a
      // build and a hang.
      child: busy
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    valueColor: AlwaysStoppedAnimation<Color>(onAccent),
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
              ],
            )
          : Text(label),
    );
  }

  /// The way out that is not a swipe.
  ///
  /// Hidden once the report is filed, where the sheet closes itself and a
  /// second dismissal is a button that does nothing.
  Widget _cancel(ThemeData palette, BugReportStrings strings) => TextButton(
    onPressed: _stage == _Stage.sent
        ? null
        : () => Navigator.of(context).maybePop(),
    child: Text(
      strings.cancel,
      style: palette.textTheme.bodyMedium
          ?.copyWith(color: palette.textTheme.bodySmall?.color),
    ),
  );

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

/// Every word the sheet says, in one place.
///
/// A package that ships English into an app whose users do not read it is a
/// package that gets forked. Nothing here is baked in: pass your own, from
/// your own localisations, and the sheet speaks whatever the app speaks.
///
/// ```dart
/// BugReportStrings(
///   title: l10n.reportTitle,
///   send: l10n.send,
/// )
/// ```
class BugReportStrings {
  const BugReportStrings({
    this.title = 'Report a problem',
    this.message =
        'Tell us what went wrong. The app sends its recent log along with '
        'your message, so we can see what happened without asking you to '
        'repeat it.',
    this.fieldLabel = 'What happened',
    this.hint = 'The list was empty after I pressed refresh…',
    this.send = 'Send report',
    this.sending = 'Sending…',
    this.sent = 'Thanks — the report is with us.',
    this.failed = 'That did not go through. Try again?',
    this.tooShort = 'A line or two more, so we know what to look for.',
    this.cancel = 'Cancel',
    this.screenshotLabel = 'Attach a picture of this screen',
  });

  /// The heading.
  final String title;

  /// The sentence under it that explains what gets sent.
  ///
  /// Worth keeping something like the default: a person is more willing to
  /// send a log when they are told it is going, and less pleased to discover
  /// it afterwards.
  final String message;

  final String fieldLabel;

  /// Shown in the empty field. An example of a useful report does more than
  /// "Describe the issue" — it shows the level of detail you are asking for.
  final String hint;

  final String send;
  final String sending;
  final String sent;
  final String failed;

  /// Shown when the description is under the minimum length.
  final String tooShort;

  final String cancel;

  /// Next to the screenshot preview and its switch.
  final String screenshotLabel;

  BugReportStrings copyWith({
    String? title,
    String? message,
    String? fieldLabel,
    String? hint,
    String? send,
    String? sending,
    String? sent,
    String? failed,
    String? tooShort,
    String? cancel,
    String? screenshotLabel,
  }) => BugReportStrings(
    title: title ?? this.title,
    message: message ?? this.message,
    fieldLabel: fieldLabel ?? this.fieldLabel,
    hint: hint ?? this.hint,
    send: send ?? this.send,
    sending: sending ?? this.sending,
    sent: sent ?? this.sent,
    failed: failed ?? this.failed,
    tooShort: tooShort ?? this.tooShort,
    cancel: cancel ?? this.cancel,
    screenshotLabel: screenshotLabel ?? this.screenshotLabel,
  );
}

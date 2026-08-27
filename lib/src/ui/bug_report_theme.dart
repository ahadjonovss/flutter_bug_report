import 'package:flutter/material.dart';

/// How the sheet looks.
///
/// Every field is nullable and every null falls back to the app's own
/// [ThemeData]. Left alone, the sheet looks like the rest of the app rather
/// than like a package that was bolted onto it — which is the point. Set only
/// what you want to differ.
///
/// ```dart
/// const BugReportTheme(accent: Color(0xFF1B4FD8), radius: 20);
/// ```
@immutable
class BugReportTheme {
  const BugReportTheme({
    this.background,
    this.accent,
    this.onAccent,
    this.titleStyle,
    this.messageStyle,
    this.radius,
    this.padding,
    this.maxWidth,
  });

  /// The sheet's own surface. Defaults to the theme's dialog background.
  final Color? background;

  /// The send button, the focused field border, the progress indicator.
  /// Defaults to the theme's primary colour.
  final Color? accent;

  /// Text on the send button. Defaults to the theme's onPrimary.
  ///
  /// Separate from [accent] because white is legible on a deep accent and not
  /// on a pale one, and a package cannot guess which yours is.
  final Color? onAccent;

  final TextStyle? titleStyle;
  final TextStyle? messageStyle;

  /// Corner radius for the sheet and the controls inside it.
  final double? radius;

  final EdgeInsets? padding;

  /// Keeps the sheet readable on a tablet, where a full-width field turns into
  /// a line of text nobody can track across.
  final double? maxWidth;

  BugReportTheme copyWith({
    Color? background,
    Color? accent,
    Color? onAccent,
    TextStyle? titleStyle,
    TextStyle? messageStyle,
    double? radius,
    EdgeInsets? padding,
    double? maxWidth,
  }) => BugReportTheme(
    background: background ?? this.background,
    accent: accent ?? this.accent,
    onAccent: onAccent ?? this.onAccent,
    titleStyle: titleStyle ?? this.titleStyle,
    messageStyle: messageStyle ?? this.messageStyle,
    radius: radius ?? this.radius,
    padding: padding ?? this.padding,
    maxWidth: maxWidth ?? this.maxWidth,
  );
}

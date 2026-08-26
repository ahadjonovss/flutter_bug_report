/// How much a line matters, and what a filter keeps.
///
/// Ordered on purpose: [index] is the comparison, so `entry.level.index >=
/// LogLevel.warning.index` reads as "warning and worse" without a lookup table.
enum LogLevel {
  debug,
  info,
  warning,
  error;

  /// Fixed width, so every line in a bundle starts at the same column and the
  /// whole thing can be read down rather than across.
  String get label => name.toUpperCase().padRight(7);
}

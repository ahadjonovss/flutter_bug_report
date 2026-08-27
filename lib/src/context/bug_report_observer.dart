import 'package:flutter/widgets.dart';
import 'package:flutter_bug_report/src/bug_report_base.dart';

/// Writes the route the person took into the log.
///
/// The single most useful line in a bug report is usually not an error — it is
/// which screens they passed through to reach it. Add this to your router's
/// observers and the trail records itself:
///
/// ```dart
/// MaterialApp(navigatorObservers: [BugReportObserver()]);
/// // or: GoRouter(observers: [BugReportObserver()]);
/// ```
///
/// Only the route names, never their arguments — an argument is where the
/// client id and the phone number live, and this is one of the few places a
/// package can leak them without anybody noticing.
class BugReportObserver extends NavigatorObserver {
  BugReportObserver({this.category = 'route'});

  /// Prefixes each line, so the trail is greppable in a long log.
  final String category;

  void _note(String verb, Route<dynamic>? route, Route<dynamic>? previous) {
    final name = _nameOf(route);
    if (name == null) return;

    final from = _nameOf(previous);
    BugReport.debug(
      from == null ? '$category: $verb $name' : '$category: $verb $name ← $from',
    );
  }

  /// A route with no name has nothing worth recording — and a `toString()`
  /// would print the arguments this deliberately does not.
  String? _nameOf(Route<dynamic>? route) => route?.settings.name;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _note('push', route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _note('pop', route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _note('replace', newRoute, oldRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    _note('remove', route, previousRoute);
  }
}

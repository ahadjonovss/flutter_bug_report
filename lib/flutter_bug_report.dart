/// Bug reports with the log already attached.
///
/// The collector gathers what the app logs and prints, takes the secrets out,
/// and builds a bounded `txt`, `json` or `zip`. The UI — a modal sheet and a
/// wrapper that opens it — is optional, themeable and translatable, and you can
/// ignore it and build your own.
///
/// Everything beyond that is opt-in, and the ones that could carry somebody's
/// details are off until you say so: screenshots, a log that persists to disk,
/// and a route trail.
///
/// Where the file goes is always yours — Sentry, Crashlytics, Jira, Telegram,
/// your own endpoint. No client here, and no service to sign up for.
///
/// ```dart
/// await BugReport.init();
///
/// BugReportWrapper(
///   config: BugReportConfig(
///     onSubmit: (bundle, description) => myBackend.upload(bundle),
///   ),
///   child: MaterialApp(...),
/// );
/// ```
library;

export 'src/bug_report_base.dart' show BugReport;
export 'src/bundle/bundle.dart' show Bundle;
export 'src/bundle/bundle_builder.dart' show BundleBuilder;
export 'src/bundle/bundle_format.dart' show BundleFormat;
export 'src/capture/console_capture.dart' show ConsoleCapture;
export 'src/capture/error_capture.dart' show ErrorCapture;
export 'src/context/bug_report_observer.dart' show BugReportObserver;
export 'src/context/device_facts.dart' show DeviceFacts;
export 'src/model/log_entry.dart' show LogEntry;
export 'src/model/log_level.dart' show LogLevel;
export 'src/redaction/redactor.dart' show Redactor;
export 'src/store/file_log_store.dart' show FileLogStore;
export 'src/store/log_store.dart' show LogStore, MemoryLogStore;
export 'src/ui/bug_report_config.dart'
    show
        BugReportButtonBuilder,
        BugReportConfig,
        BugReportFieldBuilder,
        BugReportMetadata,
        BugReportSender;
export 'src/ui/bug_report_sheet.dart' show BugReportSheet;
export 'src/ui/bug_report_strings.dart' show BugReportStrings;
export 'src/ui/bug_report_theme.dart' show BugReportTheme;
export 'src/ui/bug_report_wrapper.dart'
    show BugReportTrigger, BugReportTriggerCallback, BugReportWrapper;
export 'src/ui/screenshot.dart' show Screenshot;

/// Collect app logs and build a ready-to-attach bug report bundle.
///
/// The payload a shake-to-report SDK sends, without the vendor: this package
/// gathers what the app logs and prints, takes the secrets out, and hands back
/// a bounded `txt`, `json` or `zip` file. Where that file goes — Sentry,
/// Crashlytics, Jira, Telegram, your own endpoint — is up to you.
library;

export 'src/bundle/bundle.dart' show Bundle;
export 'src/bundle/bundle_builder.dart' show BundleBuilder;
export 'src/bundle/bundle_format.dart' show BundleFormat;
export 'src/capture/console_capture.dart' show ConsoleCapture;
export 'src/capture/error_capture.dart' show ErrorCapture;
export 'src/bug_report_base.dart' show BugReport;
export 'src/model/log_entry.dart' show LogEntry;
export 'src/model/log_level.dart' show LogLevel;
export 'src/redaction/redactor.dart' show Redactor;
export 'src/store/log_store.dart' show LogStore, MemoryLogStore;

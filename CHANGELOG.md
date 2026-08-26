## 0.1.0

First release under this name. Previously published as `log_bundle`, which is
now discontinued in favour of this package — the rename is the only difference
between `log_bundle` 0.1.2 and this release.

- `BugReport` — a static API: `BugReport.info(...)`, `BugReport.error(...)`,
  `await BugReport.build(...)`. No instance to hold and nothing to inject.
- Logging before `init()` is collected rather than dropped, and `init()` carries
  those entries forward into the store it was given — so a startup bug is not
  lost to call ordering.
- Automatic capture of `debugPrint`, bare `print` (via
  `ConsoleCapture.runCaptured`), `FlutterError.onError` and
  `PlatformDispatcher.onError`. None of it displaces a handler already installed.
- `Redactor.defaults` — bearer tokens, JWTs, Luhn-checked card numbers, and the
  usual credential field names. Applied on the way in, so a store never holds a
  secret. `Redactor.pattern` and `Redactor.keys` for your own rules.
- `BundleFormat.text`, `.json` and `.zip`. Zip carries `logs.txt` and
  `report.json` side by side.
- Bounded by entry count and by byte size, measured by rendering rather than
  estimated, and cut from the front so the end of the session survives.
- `LogStore` with `MemoryLogStore` as the default: nothing written to the device.

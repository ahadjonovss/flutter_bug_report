## 0.2.0

A UI, and everything around the log that makes a report worth reading. All of it
optional; the ones that could carry somebody's details are off until you ask.

**Added — UI**
- `BugReportWrapper` — wrap the app, long-press (or double-tap, or nothing)
  opens the sheet. `enabled` is a plain bool, so a `const false` folds the whole
  thing out of a release build.
- `BugReportSheet` — a modal that writes, sends, and says whether it worked.
  Open it yourself from any trigger you like.
- `BugReportTheme` and `BugReportStrings` — every colour falls back to your
  `ThemeData` and every word is a parameter, so it does not read as a package
  bolted onto an app.

**Added — optional context**
- `BugReportObserver` — a `NavigatorObserver` that writes the route trail into
  the log. Names only, never arguments.
- Screenshots, off by default: `BugReportWrapper(withScreenshot: true)`. Taken
  before the sheet opens, shown to the person with a switch to drop it, and
  attached as `screenshot.png`. A screenshot cannot be redacted, which is why
  consent comes from someone who can read it.
- `FileLogStore` — a log that survives the crash it describes, with retention
  and a size cap. Not the default and never will be: a file on disk outlives
  the session.
- `BugReport.identify(id)` — an id and nothing else.
- Device facts from what Flutter already knows — platform, OS version, locale,
  screen, build mode. No device id. `init(deviceFacts: false)` to send none.
  Anything you pass in `metadata` wins over what was collected.

## 0.1.1

- `Bundle` now carries the `metadata` it was built with. Whatever files the
  bundle usually wants the same facts beside it — as tags on an event, as fields
  on a form — and reading them back out of a zip to do that would be absurd.

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

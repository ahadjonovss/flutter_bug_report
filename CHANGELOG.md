## 0.3.0

Written against a real integration report. Most of what follows is somebody
else's afternoon, handed back.

**Breaking — one config object instead of a parameter list**

`BugReportWrapper` and `BugReportSheet.show` each took the same eleven
parameters, kept in step by hand. They now take one `BugReportConfig`, and the
report opened from a settings row can no longer drift away from the one opened
by the gesture.

```dart
// before
BugReportWrapper(onSubmit: upload, strings: ..., theme: ..., child: app)

// after
final config = BugReportConfig(onSubmit: upload, strings: ..., theme: ...);
BugReportWrapper(config: config, child: app)
BugReportSheet.show(context, config: config);   // the same report
```

**Added**

- `onTrigger` on the wrapper. The gesture no longer has to mean "open the
  report": an internal build can put a debug menu in front of it and still be
  handed the report, screenshot and all, rather than rebuilding the path.
  `onTrigger: kReleaseMode ? null : (context, openReport) => ...`.
- `fieldBuilder` and `buttonBuilder`. The field and the send button were a
  `TextField` and a `FilledButton` and nothing could reach them, so a sheet in
  an app with its own design system read as a package bolted on. Draw both
  yourself and the collecting, redacting and bundling stay where they are.
- A **Cancel** button, on by default (`showCancel: false` to drop it). A modal
  whose only way out is a swipe is a modal some people are stuck in, and the
  person stuck in it already had a problem to report.

**Fixed**

- **The sheet opened as a full-screen panel with its content floating in the
  middle.** `isScrollControlled` offers a bottom sheet the whole screen, and the
  `Center` wrapping the content took all of it. It shrink-wraps its height now
  and stays on the bottom edge. It also scrolls once there is not room — a short
  phone with the keyboard up had less height than the sheet wanted.
- **A successful send no longer leaves a timer running.** The self-close was a
  `Future.delayed` nothing could call off, so every widget test that sent
  successfully failed on a pending timer unless it pumped the delay away. It is
  a `Timer` now, cancelled in `dispose`.
- `BugReportStrings.sending` and `.cancel` were never rendered anywhere —
  translated by people who then found nothing used them. Both are on screen
  now: the send button says what it is doing instead of showing a bare spinner,
  and Cancel is a real button.
- The README's Sentry recipe did not compile. It called `BugReport(text)`, and
  `BugReport` is an `abstract final class` — an accident that says something
  about the name, so the README now shows the `hide` for apps that have a
  `BugReport` of their own.
- The Privacy section still claimed the package does not read the device. It
  has since 0.2.0: device facts are collected by default, non-identifying by
  construction. Says so now.

**Documented**

- **How to feed it the logger you already have.** Most apps log through
  `talker`, `logger` or `package:logging` — which is where the HTTP calls are —
  and without a bridge the bundle arrives missing the most useful thing in it.
  `BugReport.log` was always the seam; there is now a recipe for it.
- The one ordering caveat that comes with such a bridge: a direct
  `BugReport.info(...)` followed by `build()` is ordered, because the entry is
  queued synchronously and `build` waits for the queue. An entry arriving
  through a *stream* is not.

## 0.2.2

- **The sheet opened as a full-screen panel with its content floating in the
  middle.** `isScrollControlled` offers a bottom sheet the whole screen, and the
  `Center` wrapping the content took all of it. It now shrink-wraps its height
  and stays on the bottom edge, where a bottom sheet belongs.
- The content scrolls once there is not room for it — a short phone with the
  keyboard up had less height than the sheet wanted, and an overflow stripe
  across the form is a poor place to report a bug from.
- Layout is now tested through `BugReportSheet.show`. The existing tests pumped
  the sheet into a `Scaffold` body, which hands it a tight full-screen height —
  so none of them could see how it lays itself out when the height is its own to
  choose, which is exactly the case that was broken.

## 0.2.1

Setup was not as easy as 0.2.0 claimed. Found by writing the naive setup out
and running it.

- **`BugReportWrapper` above `MaterialApp` threw.** The documented snippet —
  `runApp(BugReportWrapper(child: MaterialApp(...)))` — put the wrapper's own
  context outside Material, where opening a sheet fails for want of
  `MaterialLocalizations`. The fix in 0.2.0 was to pass a `navigatorKey`, which
  is exactly the wiring this package exists to avoid. The wrapper now finds the
  app's navigator itself, and works above `MaterialApp` or inside its `builder`.
- `BugReport.init()` is no longer needed for the wrapper to work. Collection
  starts on its own; `init` is for redactors, a persistent store, and capture of
  `debugPrint` and the framework's errors.
- The README's install section still described 0.1.x and never introduced the
  sheet or the wrapper at all. Rewritten around what the package now does.

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

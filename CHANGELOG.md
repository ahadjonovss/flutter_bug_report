## 0.5.0

HTTP capture. The request that failed is the thing a bug report is usually
missing, and the app already knew it.

**Added — `BugReport.httpClient()`**

An `HttpClient` that reports every exchange it carries: the method, the url,
the status, and how long it took.

```dart
// Dio
dio.httpClientAdapter = IOHttpClientAdapter(
  createHttpClient: BugReport.httpClient,
);

// package:http
final client = IOClient(BugReport.httpClient());
```

`HttpClient` is what Dio, `package:http`, Chopper and Retrofit are all built
on, so one wrapper reaches all of them and this package still depends on none
of them.

**Nothing global is replaced.** `HttpOverrides.global` is one slot per isolate
that `flutter_test` and other packages also want, and a package that takes it
answers the question for the whole process — including for a Dio instance that
cached its client before the answer changed. A client the app hands over has
none of that: install order stops mattering, an app can capture one client and
not another, and a test that installed its own overrides keeps them.

A request that never arrived is reported too — no host, no route, no
certificate accepted. There is no response to hang the line on, so it reads
`GET … failed in 30021ms` with no status, and in a report from a phone that
could not reach anything it is most of the file.

The level follows the outcome: `info` under 400, `warning` for 4xx, `error` for
5xx and for a failure. A 404 an app handles is not the same news as a 500.

Bodies are **off by default**, and switched on with `bodies: true`. They are the
most useful thing here and the most sensitive, and the rest of this package
already draws that line the same way — route *names* without their arguments, a
screenshot only when asked. Redaction covers the field names it was told about,
and a payload of names, addresses and balances is personal whether or not it
holds a token.

Switched on they are capped at 4 KB each way, and kept only when the content
type says text — `text/*`, json, xml, form encoding. An image, a protobuf, a
multipart upload or a body the app asked to decompress itself goes past
untouched. A body that ran past the cap ends in `…` rather than looking like
json that broke.

`HttpCapture.client` is the same thing without `BugReport`, for an app that
wants the exchanges somewhere else. `HttpExchange` is what it hands over.

**On the wrapper itself**

It carries the app's traffic, so it has to be a wrapper before it is a feature.
Every member of `HttpClient`, `HttpClientRequest` and `HttpClientResponse` is
delegated; a request body is copied as it is written rather than read back; a
response body is copied as the app reads it, through the one `listen` every
other stream method is built on. A callback that throws is swallowed, because a
line about a request must not be able to break the request.

The endings that are easy to miss are covered: a read that was cancelled
half-way — which is what a receive timeout looks like from here — a body handed
to `drain` or `pipe`, a socket taken over by a web socket upgrade, and a
listener whose handlers were replaced after the fact. Each of those reports
once, and the exchange is reported once however it ends.

The content type is read through something that cannot throw, because
`HttpHeaders.contentType` parses on every read and `text/plain; charset="unclosed`
is enough to make it fail. Nothing else in the app necessarily reads that
header, and capture asking for it is not a licence to break a request that
would otherwise have worked.

## 0.4.0

Redaction, written against a report from an app that read the rules before
turning body logging on — and found three of them it could not turn on with.
The redaction rules change behaviour, so the version does too.

**Breaking — a key matches a whole field name**

`Redactor.keys({'pin'})` matched `pin` as a substring of whatever name it
found it in, but only where the name *ended* with it. So it hid `has_pin`, a
boolean state flag, and did not hide `phone_number` — a real number, left in
the clear by a rule the caller had every reason to think covered it. Broad
enough to catch what it should not, narrow enough to miss what it should, and
nothing at the call site said which.

A key is a **whole field name** now, counting `-`, `_` and `.` as part of the
name, and a `*` asks for the rest of it explicitly:

```dart
Redactor.keys({'pin'});      // pin — not has_pin, not pin_hash
Redactor.keys({'*token'});   // access_token, x-firebase-token — not token_type
Redactor.keys({'phone*'});   // phone, phone_number
Redactor.keys({'*card*'});   // either end
```

The defaults carry the `*` where they always relied on it, so `*token`,
`*secret`, `*password` and `*api_key` still reach the names they reached
before. **Check your own `Redactor.keys` calls for a key you were relying on
to match inside a longer name** — that is the one thing this release can
silently take away. A field name you wrote for one shape of it and meant for
all of them wants the `*` now: `{'phone'}` → `{'phone*'}`.

An empty set now redacts nothing, rather than everything. A pattern built from
an empty alternation matched every field there is, which is the wrong direction
to fail in when the set arrived from configuration.

**Breaking — `code` is not a credential**

`code` was in the default key set, and it is the standard name for a
machine-readable error or status code: `"code":"limit_exceeded"`,
`"code":"otp_sent"`. That is frequently the one line in a bundle worth reading,
and every bundle had it destroyed. The verification codes it was there for
arrive under their own names, and those are listed instead: `otp_code`,
`sms_code`, `verification_code`, `confirmation_code`.

**Added — the defaults come apart**

`Redactor.defaults` was a list of four things, three of them private, so "the
defaults, minus one field name" meant `Redactor.defaults.take(3)` and a
hand-rolled key rule — positionally coupled to a private list, and silently
wrong the day a fourth pattern is added.

```dart
redactors: [
  ...Redactor.defaultPatterns,                              // Bearer, JWT, PAN
  Redactor.keys(Redactor.defaultKeys.difference({'pin'})),
],
```

`Redactor.defaults` is unchanged and still the answer for anyone not
subtracting anything.

**Fixed — a long id is no longer starred out by chance**

The card rule masked any 13–19 digit run that passed Luhn, and Luhn passes one
number in ten. A 14-digit product id was one unlucky checksum away from
arriving as `**********0674`, with nothing in the bundle to say why. It now
also asks for a length and prefix a scheme issues: fifteen digits wants Amex,
fourteen wants Diners, thirteen wants Visa.

Sixteen digits stays unconditional. Gating that on the international prefixes
would have quietly stopped redacting every domestic scheme — Uzcard `8600`,
Humo `9860`, Mir `2200` — and those are cards to the person whose card it is.

## 0.3.3

Documentation only.

- The viewer is named at the top of the README now, not four screens down. A
  bundle arriving in a ticket is somebody else's problem to read, and the
  person who needs the viewer is often not the person who added the package.
- `What you get` opens with the bundle as it actually reads — a screenshot of
  the viewer with the sample session in it, the gap and the burst visible —
  before the raw text of the same file.

## 0.3.2

Documentation only — no library change, nothing to migrate.

- **A viewer for the bundles.** A bundle in a ticket still had to be read by
  somebody, and that meant downloading a zip, unzipping it and scrolling
  `logs.txt` in an editor. [The viewer][viewer] takes all three formats and
  shows the shape of the session before a word of it is read: the quiet
  stretch, the gap where nothing was logged, the burst where it went wrong.

  It runs entirely in the page — no upload, no server, no request of any kind,
  because its own `Content-Security-Policy` forbids one. That is a property
  somebody can check rather than a promise they have to take, which is the only
  version of this claim worth making for a package whose whole argument is that
  your logs are nobody else's business. It is tested against this repository's
  own `test/fixtures/`, so the two cannot drift.

- A logo, shared by the package and the viewer. It is the density strip the
  viewer draws — quiet, a gap, then the burst. Not a metaphor for what the tool
  does; a picture of what it shows.

[viewer]: https://ahadjonovss.github.io/flutter_bug_report_viewer/

## 0.3.1

Two format defects, found by writing a parser against the output instead of
against the description of it.

- **A `.txt` or `.json` bundle claimed a screenshot it could not carry.** The
  `screenshot: screenshot.png` line went into the report for every format, but
  only a zip has anywhere to put the file — so a report built as json with a
  screenshot attached named an attachment that was never in it, and sent
  whoever read it looking for a file that does not exist. Named in a zip only
  now.
- **A description with a line break in it broke the text header.** The sheet
  takes four lines, so this is reachable by anyone who presses Enter, and the
  second line landed in the header looking like a field of its own.
  Continuation lines are wrapped two-space indented, like the metadata block —
  wrapped rather than escaped, because the header exists to be read and `\n`
  in the middle of somebody's sentence reads worse than the wrap.

**Added — golden bundles**

`test/fixtures/` now holds bundles written by the builder itself, one per case
worth getting wrong: a multi-line message (a Flutter error banner arrives
through `debugPrint` as one string, so an entry boundary cannot be "a line that
is not indented"), a multi-line description, every optional field absent at
once, `truncated: true`, a screenshot, and an empty session — in all three
formats.

They are here for a second reader: a log viewer parses this format from another
repository and another language, and a parser written against a description of
a format drifts from it the first time the format changes and nobody remembers
to say so. Deleting the directory and running the suite regenerates them, so
the diff of a format change is reviewable line by line. Not shipped to
consumers of the package.

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

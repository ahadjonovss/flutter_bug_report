<p align="center">
  <img src="https://raw.githubusercontent.com/ahadjonovss/flutter_bug_report/main/doc/logo.svg" width="72" alt="">
</p>

<h1 align="center">flutter_bug_report</h1>

<p align="center">
  <b>Bug reports with the log already attached.</b><br>
  The payload a shake-to-report SDK sends — without the vendor.
</p>

<p align="center">
  <a href="https://pub.dev/packages/flutter_bug_report"><img src="https://img.shields.io/pub/v/flutter_bug_report.svg?logo=dart&color=0175C2" alt="pub package"></a>
  <a href="https://pub.dev/packages/flutter_bug_report/score"><img src="https://img.shields.io/pub/points/flutter_bug_report?logo=dart&color=0175C2" alt="pub points"></a>
  <a href="https://pub.dev/packages/flutter_bug_report/score"><img src="https://img.shields.io/pub/likes/flutter_bug_report?logo=dart&color=0175C2" alt="likes"></a>
  <a href="https://github.com/ahadjonovss/flutter_bug_report/blob/main/LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="license"></a>
</p>

<p align="center">
  <b><a href="https://ahadjonovss.github.io/flutter_bug_report_viewer/">Open a bundle in the viewer&nbsp;&rarr;</a></b><br>
  <sub>Reads <code>.txt</code>, <code>.json</code> and <code>.zip</code> in the browser. No upload, no server, no signup.</sub>
</p>

---

Every bug report that arrives as *"it didn't work"* costs somebody an afternoon.
Attaching **Flutter crash logs** to a report by hand costs them the rest of it.
The fix isn't a better form — it's attaching the log, the build number and the
phone to whatever the person typed. Tools that do this exist, and they're SDKs
from companies that want your data on their servers.

`flutter_bug_report` is that attachment, and nothing else. It **collects**, and it
**hands you a file**. Where the file goes — Sentry, Crashlytics, Jira, Telegram,
your own endpoint — is your app's business. No client, no DSN, no signup.

```dart
await BugReport.init();

BugReport.info('opened the payment screen');

// …later, when someone reports something
final bundle = await BugReport.build(
  description: 'Payment screen froze after I pressed pay',
  metadata: {'app_version': '1.0.17+2185', 'platform': 'android'},
);

await myBackend.upload(bundle.bytes, bundle.fileName, bundle.mimeType);
```

No instance to hold, nothing to inject, no service locator. There's one log per
app, the same way there's one console.

> Already have a `BugReport` of your own — an exception class, most often? Import
> around it: `import 'package:flutter_bug_report/flutter_bug_report.dart' hide BugReport;`
> and reach this one through a prefixed import instead.

## What it looks like

<p align="center">
  <img src="https://raw.githubusercontent.com/ahadjonovss/flutter_bug_report/main/doc/demo.gif" width="300" alt="Reporting a problem: the description goes with the log already attached">
</p>

<p align="center">
  <i>A sheet, a sentence, and the log goes with it — from Alif Business, in production.</i>
</p>

## What you get

<p align="center">
  <a href="https://ahadjonovss.github.io/flutter_bug_report_viewer/"><img src="https://raw.githubusercontent.com/ahadjonovss/flutter_bug_report/main/doc/viewer.png" width="880" alt="The viewer: a strip across the top showing the shape of the session, the log below it, the report beside it"></a>
</p>

<p align="center">
  <i>The same bundle, <a href="https://ahadjonovss.github.io/flutter_bug_report_viewer/">opened in the viewer</a> — the quiet stretch, the
  31.5s gap where nothing was logged, then the burst. Nothing is uploaded to read it.</i>
</p>

And this is the file itself. Note what happened to the bearer token and the card
number on the way:

```text
=== flutter_bug_report ===
generated_at: 2026-08-26T07:19:11.214967Z
description: The client list was empty after I pressed refresh
entry_count: 5
truncated: false
metadata:
  app_version: 1.0.17+2185
  platform: android
  os_version: Android 14
  device_model: samsung SM-A546E
==================

2026-08-26T07:19:11.201742Z INFO    signed in
2026-08-26T07:19:11.209049Z INFO    GET /clients
  {"status":500,"authorization":"Bearer «redacted»","ms":1840}
2026-08-26T07:19:11.210375Z WARNING retrying in 2s
2026-08-26T07:19:11.210420Z INFO    paid with card ************4242
2026-08-26T07:19:11.211374Z ERROR   could not load clients
  Bad state: clients came back null
  #0      ClientsCubit.load (package:app/clients_cubit.dart:41:7)
  <asynchronous suspension>
```


## Everything else is optional

The collector and the sheet are the whole package. What follows is off until
you switch it on, and the ones that could carry somebody's details stay off
until you have thought about it.

### The route they took

The most useful line in a bug report is often not an error — it is which screens
they passed through to reach one.

```dart
MaterialApp(navigatorObservers: [BugReportObserver()]);
GoRouter(observers: [BugReportObserver()]);
```

```
route: push /clients ← /home
route: push /clients/details ← /clients
route: push /payment ← /clients/details
```

Route **names** only, never their arguments — an argument is where the client id
and the phone number live.

### The request that failed

The one thing a bug report is usually missing is the thing the app already knew:
which request failed, and what came back. Hand your networking layer a client
that writes it down.

```dart
// Dio
dio.httpClientAdapter = IOHttpClientAdapter(
  createHttpClient: () => BugReport.httpClient(),
);

// package:http
final client = IOClient(BugReport.httpClient());

// dart:io
final client = BugReport.httpClient();
```

```
INFO    GET  https://api.example.com/v1/clients 200 in 143ms
WARNING POST https://api.example.com/v1/auth/otp 422 in 318ms
ERROR   GET  https://api.example.com/v1/clients failed in 30021ms
  SocketException: Connection timed out
```

`HttpClient` is what Dio, `package:http`, Chopper and Retrofit are all built on,
so wrapping that one class reaches all of them without this package depending on
any of them.

**Nothing global is replaced.** `HttpOverrides.global` is a single slot that
`flutter_test` and other packages also want, and taking it would decide the
question for your whole process. A client you hand over decides nothing, and an
app can capture one client and not another.

| | |
| --- | --- |
| Logged | method, url, status, duration — including a request that never arrived, which is most of what an offline report is made of |
| Level | `info` under 400, `warning` for 4xx, `error` for 5xx and for a request that failed outright |
| Bodies | **off until you ask**, then capped at 4 KB each way and only when the content type says text — an image or an upload goes past untouched |
| Redaction | the same redaction as everything else, on the way in: a token in a response body is gone before it is stored |

```dart
// Dio, and the reason the wiring above is a closure and not `BugReport.httpClient`
// on its own: a torn-off method has nowhere to put these.
dio.httpClientAdapter = IOHttpClientAdapter(
  createHttpClient: () => BugReport.httpClient(
    bodies: true,                                    // the payload as well as the line
    ignore: (url) => url.host == 'logs.example.com', // don't report the reporter
  ),
);
```

```
WARNING POST https://api.example.com/v1/auth/otp 422 in 318ms
  {"request":"{\"phone\":\"998901234567\",\"otp\":«redacted»}","response":"{\"code\":\"otp_invalid\"}"}
```

Bodies are the most useful thing here and the most sensitive, which is why they
are the one part you have to ask for. Redaction covers the field names it was
told about — and a payload of names, addresses and balances is personal whether
or not it holds a token.

### A screenshot

```dart
BugReportWrapper(withScreenshot: true, ...)
```

Off by default, and that is the right default. A screenshot carries whatever the
screen carried, and unlike a log it **cannot be redacted** — nothing here can
read what is in it. Switched on, the sheet shows the person the picture before
it goes and one tap drops it. Nobody should find out afterwards what they sent.

It lands as `screenshot.png` inside the zip, captured before the sheet opens so
it shows the screen being reported rather than the form reporting it.

### A log that survives the crash

`MemoryLogStore` loses everything the process loses — including, at the worst
moment, the lines that explain why the process died.

```dart
await BugReport.init(store: FileLogStore(retention: Duration(days: 3)));
```

**Opt in knowingly.** A file on disk outlives the session, and a phone that is
shared, repaired or sold carries it along. Before switching it on: check your
redactors cover what your app logs, keep `retention` as short as you can stand,
and call `BugReport.clear()` on sign-out.

### Who it happened to

```dart
BugReport.identify(user.id);   // and identify(null) on sign-out
```

An id and nothing else. A name, a phone number and an email are yours to send or
not, through `metadata`.

### What the phone is

Folded in automatically, from what Flutter itself knows:

```
platform · os_version · locale · screen · pixel_ratio · text_scale · build_mode
```

Non-identifying by construction — nothing here reads a device id, and anything
more specific is yours to pass. `BugReport.init(deviceFacts: false)` sends none
of it. Whatever you pass in `metadata` wins over what was collected.

## Install

```yaml
dependencies:
  flutter_bug_report: ^0.5.0
```

### With the built-in sheet

```dart
final reportConfig = BugReportConfig(
  onSubmit: (bundle, description) => myBackend.upload(bundle),
);

runApp(
  BugReportWrapper(
    config: reportConfig,
    child: MaterialApp(...),
  ),
);
```

That is the whole setup. No `init`, no `navigatorKey`, no `async main`: the
wrapper starts collection itself and finds your app's navigator on its own, so
it works wrapped above `MaterialApp` or inside its `builder`.

A long press anywhere opens the sheet. `trigger: BugReportTrigger.doubleTap` or
`.none` if you would rather open it yourself, and `enabled: false` — a plain
bool, so a `const` folds the whole thing out of a release build.

`onSubmit` is the one thing you must write, and it is the point: the package
builds the file and never decides where it goes.

**Everything about a report lives in `BugReportConfig`** — what it sends, what
it says, how it looks — and both the wrapper and `BugReportSheet.show` take the
same object. Hold one and pass it to both, and the report opened from a settings
row cannot drift away from the one opened by the gesture.

```dart
BugReportSheet.show(context, config: reportConfig);   // the same report
```

### When the gesture should reach more than the report

An internal build usually wants the long press to open a menu, with the report
one item on it. `onTrigger` takes the gesture and is handed the report:

```dart
BugReportWrapper(
  config: reportConfig,
  onTrigger: kReleaseMode
      ? null                                  // straight to the report
      : (context, openReport) => showDebugMenu(context, onReport: openReport),
  child: MaterialApp(...),
)
```

The screenshot, if you asked for one, is captured before your menu opens — so it
is a picture of the screen being reported, not of the menu.

### Or without any UI

```dart
final bundle = await BugReport.build(
  description: whateverTheyTyped,
  metadata: {'app_version': '1.0.17+2185'},
);

await myBackend.upload(bundle.bytes, bundle.fileName, bundle.mimeType);
```

### When you want more than the default

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await BugReport.init(              // before runApp, so the log covers startup
    redactors: [...Redactor.defaults, Redactor.keys({'merchant_pin'})],
  );
  runApp(const MyApp());
}
```

`init` is where redactors, a persistent store, and capture of `debugPrint` and
the framework's own errors are switched on. The implicit setup leaves
`debugPrint` alone on purpose — swapping a global nobody asked for turns up as a
failing assertion in *your* widget tests.

Logging **before** `init()` collects rather than throws or silently drops, and
`init()` carries those entries forward: the lines that explain a startup bug are
written before anything has had a chance to be configured.

### Making it yours

```dart
BugReportConfig(
  onSubmit: myUpload,
  strings: BugReportStrings(title: l10n.reportTitle, send: l10n.send),
  theme: const BugReportTheme(accent: Color(0xFF1B4FD8), radius: 20),
)
```

Every word is a parameter and every colour falls back to your own `ThemeData`,
so the sheet reads as part of the app rather than as a package bolted onto it.

When a colour is not enough — you have a design system, and its button is not a
`FilledButton` — draw the two controls yourself and leave the collecting,
redacting and bundling where it is:

```dart
BugReportConfig(
  onSubmit: myUpload,
  fieldBuilder: (context, controller, enabled) =>
      AppTextField(controller: controller, enabled: enabled),
  buttonBuilder: (context, onPressed, busy, label) =>
      MainButton(onPressed: onPressed, loading: busy, title: label),
)
```

`onPressed` is null while the report is in flight or already filed, so a button
that respects it cannot file the same report twice.

And if you want none of the sheet, you already have the headless path — it is
the original API. `BugReport.build()` returns the bundle; the UI is yours:

```dart
final bundle = await BugReport.build(description: whateverTheyTyped);
```

## What it collects

| Source | How |
| --- | --- |
| Your own calls | `BugReport.debug/info/warning/error(...)` |
| `debugPrint` | automatic — including from plugins and packages you don't control |
| bare `print` | wrap `runApp` in `ConsoleCapture.runCaptured` |
| Flutter errors | `FlutterError.onError` and `PlatformDispatcher.onError` |
| HTTP | hand `BugReport.httpClient()` to Dio, `package:http` or `dart:io` |

Capture never displaces what was there before it. The console still prints, and
an existing crash reporter still reports — `flutter_bug_report` chains onto both.

## Redaction

A bundle leaves the device, so secrets come out **on the way in** — an entry is
rewritten as it's stored, never as it's read. A secret that was never written
down can't leak from a store somebody later dumps by hand.

`Redactor.defaults` covers what it's wrong to ship without:

| Rule | Catches |
| --- | --- |
| Auth schemes | `Authorization` headers, `Bearer`/`Basic` tokens — **including the token after the scheme**, not just the word |
| JWTs | `eyJ…` written out on its own |
| Card numbers | **Luhn-checked**, and against the lengths and prefixes the schemes issue, so a long id doesn't come out starred. Last four kept |
| Credential keys | `*password`, `otp`, `*token`, `*api_key`, `*secret`, `cvv`, `cookie`, and the rest — `Redactor.defaultKeys` is the whole list, readable and subtractable |

Add your own, or turn it off knowingly:

```dart
await BugReport.init(
  redactors: [
    ...Redactor.defaults,
    Redactor.pattern(RegExp(r'\+998\d{9}'), replacement: '«phone»'),
    Redactor.keys({'merchant_pin'}),
  ],
);
```

A key matches a **whole field name**, counting `-`, `_` and `.` as part of the
name. `{'pin'}` hides `pin` and leaves `has_pin` and `pin_hash` alone — a state
flag is not a secret, and a bug report that lost it is harder to read for
nothing. Ask for more with a `*` on the side that may carry anything else:

| Given | Hides | Leaves |
| --- | --- | --- |
| `{'pin'}` | `pin`, `PIN`, `"pin"` | `has_pin`, `pin_hash` |
| `{'*token'}` | `access_token`, `x-firebase-token` | `token_type` |
| `{'phone*'}` | `phone`, `phone_number` | `contact_phone` |
| `{'*card*'}` | `card`, `card_number`, `saved_cards` | |

What the defaults **don't** hide is a field named `code`. It's the standard name
for a machine-readable error or status code — `"code":"limit_exceeded"` — which
is often the one line in a bundle worth reading. The codes that are secrets are
named on their own: `otp_code`, `sms_code`, `verification_code`,
`confirmation_code`.

The defaults come apart, so "the defaults, minus one field name" doesn't mean
depending on the order of a list:

```dart
await BugReport.init(
  redactors: [
    ...Redactor.defaultPatterns,                                   // Bearer, JWT, PAN
    Redactor.keys(Redactor.defaultKeys.difference({'pin'})),
  ],
);
```

A pattern added to `defaultPatterns` later arrives through that spread on its
own. Nothing in a security path is counted or positioned by hand.

## Bounds

An attachment nobody can open is no better than none. A bundle is bounded twice
over — by entry count and by byte size — and cut **from the front**, because
whatever is being reported happened just before the person wrote it down.

```dart
final bundle = await BugReport.build(
  limit: 500,             // entries
  maxBytes: 256 * 1024,   // before compression
  format: BundleFormat.zip,
);

bundle.truncated;   // say so in the ticket: this is the end of a session
bundle.entryCount;
bundle.sizeInBytes;
```

Size is measured by rendering, not estimated: an entry carrying a stack trace is
an order of magnitude larger than one that doesn't, and an average is wrong in
both directions.

## Formats

| | Contents | For |
| --- | --- | --- |
| `BundleFormat.text` | header, then lines, oldest first | a human opening a ticket |
| `BundleFormat.json` | `report` + `entries` | anything that will index it |
| `BundleFormat.zip` | `logs.txt` **and** `report.json` | the default — every tracker takes it |

Take the bytes, or take a file:

```dart
bundle.bytes;              // Uint8List — for a multipart field or an attachment
bundle.fileName;           // log-bundle-20260826-141233.zip
bundle.mimeType;           // application/zip
await bundle.writeTo();    // File, in the temp directory by default
```

## Reading one

A bundle in a ticket still has to be read by somebody, and that should not mean
downloading a zip, unzipping it and scrolling `logs.txt` in a text editor.

**[Open a bundle in the viewer](https://ahadjonovss.github.io/flutter_bug_report_viewer/)**

Takes `.txt`, `.json` and `.zip`. Filter by level, search, jump between errors,
and see the metadata and the screenshot beside the log — with a strip across the
top that shows the shape of the session before you read a word of it: the quiet
stretch, the gap where nothing was logged, the burst where it went wrong.

It runs entirely in the page. No upload, no server, no request of any kind — the
page's own `Content-Security-Policy` forbids one, so it is a property you can
check rather than a promise you have to take. Save the page and it works with no
network at all.

[Source](https://github.com/ahadjonovss/flutter_bug_report_viewer), and the
golden bundles it is tested against are this repository's own
[`test/fixtures/`](test/fixtures).

## Storage

`MemoryLogStore` is the default. It keeps nothing on the device: no file to grow
unattended, nothing to clean up, and nothing left behind on a phone that's shared
or sold. It loses everything the process loses.

If you need the log to survive the crash you're chasing, implement `LogStore`
over sqflite, Hive or a file — five methods, all async by design so a disk-backed
store fits without callers changing shape.

```dart
await BugReport.init(store: MyDatabaseLogStore());
```

## Recipes

<details>
<summary><b>Shake to report</b></summary>
<br>

`flutter_bug_report` builds the payload; any gesture package can be the trigger.

```dart
ShakeDetector.autoStart(onPhoneShake: (_) async {
  final bundle = await BugReport.build(description: await askUser());
  await upload(bundle);
});
```
</details>

<details>
<summary><b>Attach to Sentry</b></summary>
<br>

```dart
final bundle = await BugReport.build(description: text);

await Sentry.captureMessage(
  text,
  withScope: (scope) {
    scope.addAttachment(
      SentryAttachment.fromUint8List(bundle.bytes, bundle.fileName),
    );
    bundle.metadata.forEach(scope.setTag);   // app_version, platform, the rest
  },
);
```

`bundle.metadata` is handed back to you rather than only written into the file,
so the facts that belong beside the attachment — as tags on an event, as fields
on a form — do not have to be read back out of a zip.
</details>

<details>
<summary><b>Send to a Telegram bot</b></summary>
<br>

```dart
final bundle = await BugReport.build(description: text);

await dio.post(
  'https://api.telegram.org/bot$token/sendDocument',
  data: FormData.fromMap({
    'chat_id': chatId,
    'caption': text,
    'document': MultipartFile.fromBytes(bundle.bytes, filename: bundle.fileName),
  }),
);
```
</details>

<details>
<summary><b>Feed it the logger you already have</b></summary>
<br>

Most apps do not log through this package — they log through `talker`, `logger`
or `package:logging`, and that is where the HTTP calls are. Without a bridge the
bundle arrives without the most useful thing in it.

`BugReport.log` is the seam. Map your levels onto `LogLevel` and forward:

```dart
// package:logging
Logger.root.onRecord.listen((r) => BugReport.log(
      switch (r.level.value) {
        >= 1000 => LogLevel.error,
        >= 900 => LogLevel.warning,
        >= 800 => LogLevel.info,
        _ => LogLevel.debug,
      },
      r.message,
      error: r.error,
      stackTrace: r.stackTrace,
    ));

// talker
talker.stream.listen((e) => BugReport.log(
      switch (e.logLevel) {
        LogLevel.error || LogLevel.critical => LogLevel.error,
        LogLevel.warning => LogLevel.warning,
        _ => LogLevel.info,
      },
      e.generateTextMessage(),
      error: e.error,
      stackTrace: e.stackTrace,
    ));
```

Redaction still runs on the way in, so a bridged logger cannot smuggle a token
past it.

**One caveat, and it is the only one.** A stream delivers asynchronously. Calling
`BugReport.info(...)` directly and then `BugReport.build()` is ordered — the
entry is queued synchronously and `build` waits for the queue. An entry arriving
*through a stream* is not: it lands whenever the stream gets around to it, which
may be after the bundle was built. If you file a report immediately after the
line you want in it, give the stream a turn first:

```dart
await Future<void>.delayed(Duration.zero);
final bundle = await BugReport.build(description: text);
```
</details>

<details>
<summary><b>Log Dio requests</b></summary>
<br>

Deliberately not a dependency — ten lines, and you decide what's worth recording.

```dart
class BugReportInterceptor extends Interceptor {
  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    BugReport.info(
      '${response.requestOptions.method} ${response.requestOptions.path}',
      extra: {'status': response.statusCode},
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    BugReport.error(
      '${err.requestOptions.method} ${err.requestOptions.path}',
      error: err,
      extra: {'status': err.response?.statusCode},
    );
    handler.next(err);
  }
}
```
</details>

<details>
<summary><b>Log bloc state changes</b></summary>
<br>

```dart
class BugReportObserver extends BlocObserver {
  @override
  void onChange(BlocBase bloc, Change change) {
    super.onChange(bloc, change);
    BugReport.debug(
      '${bloc.runtimeType}: ${change.currentState.runtimeType} '
      '-> ${change.nextState.runtimeType}',
    );
  }
}
```
</details>

<details>
<summary><b>Capture bare <code>print</code> too</b></summary>
<br>

`print` resolves through the ambient zone, so catching it means running the app
inside one:

```dart
void main() async {
  await BugReport.init();
  ConsoleCapture.runCaptured(
    () => runApp(const MyApp()),
    (line) => BugReport.debug(line),
  );
}
```
</details>

## Privacy

- Nothing is sent anywhere. The package opens no connection of its own — HTTP
  capture wraps a client your app already has and carries its traffic through
  unchanged.
- `MemoryLogStore` writes nothing to disk.
- Redaction runs before storage, not before export.
- HTTP is only captured through a client you hand over yourself, and the bodies
  are off inside that until you ask for them. Switched on they are capped, text
  only, and redacted like everything else.
- Device facts are collected by default and are non-identifying by construction —
  platform, OS version, locale, screen, build mode. No device id, no advertising
  id, nothing that names a person. `BugReport.init(deviceFacts: false)` sends
  none of it, and anything you pass in `metadata` wins over what was collected.
  Anything more specific than that is yours to add, never ours to guess.
- `BugReport.clear()` on sign-out, if the log could name the person who just left.
- The [viewer](https://ahadjonovss.github.io/flutter_bug_report_viewer/) sends
  nothing either. It parses the bundle in the browser and has no network code —
  the same shape as the package.

## License

MIT © [Samandar Ahadjonov](https://github.com/ahadjonovss)

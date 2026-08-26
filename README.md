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

## What it looks like

<p align="center">
  <img src="https://raw.githubusercontent.com/ahadjonovss/flutter_bug_report/main/doc/demo.gif" width="300" alt="Reporting a problem: the description goes with the log already attached">
</p>

<p align="center">
  <i>A sheet, a sentence, and the log goes with it — from Alif Business, in production.</i>
</p>

## What you get

And this is what arrives. Note what happened to the bearer token and the card
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

## Install

```yaml
dependencies:
  flutter_bug_report: ^0.1.0
```

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await BugReport.init();   // before runApp, so the log covers startup
  runApp(const MyApp());
}
```

Calling `BugReport.info(...)` **before** `init()` collects rather than throws or
silently drops — the lines that explain a startup bug are written before anything
has had a chance to be configured, and `init()` carries them forward into
whatever store you gave it.

## What it collects

| Source | How |
| --- | --- |
| Your own calls | `BugReport.debug/info/warning/error(...)` |
| `debugPrint` | automatic — including from plugins and packages you don't control |
| bare `print` | wrap `runApp` in `ConsoleCapture.runCaptured` |
| Flutter errors | `FlutterError.onError` and `PlatformDispatcher.onError` |

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
| Card numbers | **Luhn-checked**, so an order id doesn't come out starred. Last four kept |
| Credential keys | `password`, `otp`, `token`, `refresh_token`, `api_key`, `secret`, `cvv`, `cookie`, and the rest |

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

await Sentry.captureException(
  BugReport(text),
  withScope: (scope) => scope.addAttachment(
    SentryAttachment.fromUint8List(bundle.bytes, bundle.fileName),
  ),
);
```
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

- Nothing is sent anywhere. The package has no network code.
- `MemoryLogStore` writes nothing to disk.
- Redaction runs before storage, not before export.
- `metadata` is a plain map you fill in — `flutter_bug_report` doesn't read the device,
  so it can't decide on your behalf what counts as identifying.
- `BugReport.clear()` on sign-out, if the log could name the person who just left.

## License

MIT © [Samandar Ahadjonov](https://github.com/ahadjonovss)

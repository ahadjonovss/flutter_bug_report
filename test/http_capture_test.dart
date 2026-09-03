import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_bug_report/flutter_bug_report.dart';
import 'package:flutter_test/flutter_test.dart';

/// Against a real server on the loopback interface, because the point of this
/// wrapper is that it sits in the middle of a socket without changing what the
/// two ends see. A fake client would only prove the fake.
void main() {
  late HttpServer server;
  late Uri base;
  late List<HttpExchange> seen;

  /// What the server does with the next request. Replaced per test.
  late Future<void> Function(HttpRequest request) respond;

  Future<void> json(HttpRequest request) async {
    request.response.headers.contentType = ContentType.json;
    request.response.write('{"ok":true}');
    await request.response.close();
  }

  setUp(() async {
    seen = [];
    respond = json;

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.autoCompress = false;
    base = Uri.parse('http://${server.address.address}:${server.port}/clients');

    server.listen((request) => respond(request));
  });

  tearDown(() => server.close(force: true));

  HttpClient capturing({
    // On for most of these, because a body is the part with something to get
    // wrong. The default is the other way, and has its own test.
    bool bodies = true,
    int maxBodyBytes = HttpCapture.defaultMaxBodyBytes,
    bool Function(Uri url)? ignore,
  }) => HttpCapture.client(
    seen.add,
    inner: HttpClient(),
    bodies: bodies,
    maxBodyBytes: maxBodyBytes,
    ignore: ignore,
  );

  Future<String> read(HttpClientResponse response) =>
      response.transform(utf8.decoder).join();

  group('HttpCapture.client', () {
    test('reports a request the app never had to describe', () async {
      final response = await (await capturing().getUrl(base)).close();

      expect(await read(response), '{"ok":true}');

      final exchange = seen.single;
      expect(exchange.method, 'GET');
      expect(exchange.url, base);
      expect(exchange.statusCode, 200);
      expect(exchange.failed, isFalse);
      expect(exchange.error, isNull);
      expect(exchange.requestBody, isNull);
      expect(exchange.responseBody, '{"ok":true}');
    });

    test('keeps both bodies of a post', () async {
      respond = (request) async {
        request.response.statusCode = HttpStatus.unprocessableEntity;
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"code":"otp_invalid"}');
        await request.response.close();
      };

      final request = await capturing().postUrl(base);
      request.headers.contentType = ContentType.json;
      request.write('{"phone":"998901234567","otp":"445566"}');

      final response = await request.close();
      await read(response);

      expect(seen.single.requestBody, contains('998901234567'));
      expect(seen.single.responseBody, '{"code":"otp_invalid"}');
      expect(seen.single.statusCode, 422);
    });

    test('a body written as bytes or a stream is kept the same way', () async {
      const payload = '{"amount":5000}';

      final byBytes = await capturing().postUrl(base);
      byBytes.headers.contentType = ContentType.json;
      byBytes.add(utf8.encode(payload));
      await read(await byBytes.close());

      final client = capturing();
      final byStream = await client.postUrl(base);
      byStream.headers.contentType = ContentType.json;
      await byStream.addStream(Stream.value(utf8.encode(payload)));
      await read(await byStream.close());

      expect(seen.map((exchange) => exchange.requestBody), [payload, payload]);
    });

    test('a duration is measured, not guessed', () async {
      respond = (request) async {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        await json(request);
      };

      await read(await (await capturing().getUrl(base)).close());

      expect(seen.single.duration, greaterThanOrEqualTo(
        const Duration(milliseconds: 40),
      ));
    });

    test('keeps the line and no payload until it is asked', () async {
      // The default, spelled out: a body can be personal without holding
      // anything a redactor is looking for.
      final request = await HttpCapture.client(seen.add).postUrl(base);
      request.headers.contentType = ContentType.json;
      request.write('{"pin":"0000"}');

      final response = await request.close();

      // Still readable by the app, and still reported.
      expect(await read(response), '{"ok":true}');
      expect(seen.single.statusCode, 200);
      expect(seen.single.requestBody, isNull);
      expect(seen.single.responseBody, isNull);
    });

    test('a body longer than the cap is cut and says so', () async {
      respond = (request) async {
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"items":[${List.filled(200, 1).join(',')}]}');
        await request.response.close();
      };

      final response = await (await capturing(
        maxBodyBytes: 16,
      ).getUrl(base)).close();

      // The app is handed every byte regardless of what capture kept.
      expect((await read(response)).length, greaterThan(16));

      expect(seen.single.responseBody, '{"items":[1,1,1,…');
    });

    test('a body that is not text is left where it is', () async {
      respond = (request) async {
        request.response.headers.contentType = ContentType.binary;
        request.response.add(const [0, 1, 2, 250]);
        await request.response.close();
      };

      final request = await capturing().postUrl(base);
      request.headers.contentType = ContentType.binary;
      request.add(const [0, 1, 2, 250]);

      await (await request.close()).drain<void>();

      expect(seen.single.statusCode, 200);
      expect(seen.single.requestBody, isNull);
      expect(seen.single.responseBody, isNull);
    });

    test('a body the app asked to decode itself is not decoded here', () async {
      server.autoCompress = true;

      final client = capturing();
      client.autoUncompress = false;

      final response = await (await client.getUrl(base)).close();

      expect(
        response.compressionState,
        HttpClientResponseCompressionState.compressed,
      );
      // Still gzip, and still the app's to unpack.
      expect(
        utf8.decode(gzip.decode(await response.expand((bytes) => bytes).toList())),
        '{"ok":true}',
      );

      expect(seen.single.statusCode, 200);
      expect(seen.single.responseBody, isNull);
    });

    test('a request that never arrives is the report', () async {
      final client = capturing();
      await server.close(force: true);

      await expectLater(
        client.getUrl(base).then((request) => request.close()),
        throwsA(isA<SocketException>()),
      );

      final exchange = seen.single;
      expect(exchange.method, 'GET');
      expect(exchange.url, base);
      expect(exchange.statusCode, isNull);
      expect(exchange.failed, isTrue);
      expect(exchange.error, isA<SocketException>());
    });

    test('a read given up on halfway is still reported', () async {
      respond = (request) async {
        request.response.headers.contentType = ContentType.json;
        // Off, or the first chunk waits for a buffer that is never filled.
        request.response.bufferOutput = false;
        request.response.write('{"items":[1,');
        await request.response.flush();
        // Never closed: the app gives up before the server finishes.
      };

      final response = await (await capturing().getUrl(base)).close();

      // Takes one chunk and cancels, which is what a receive timeout does.
      expect(utf8.decode(await response.first), '{"items":[1,');

      expect(seen.single.statusCode, 200);
      expect(seen.single.responseBody, '{"items":[1,');
    });

    test('a body thrown away rather than read is still reported', () async {
      // `drain` and `pipe` both end in StreamSubscription.asFuture, which
      // replaces the handlers on the subscription underneath it. Read through
      // that future rather than through handlers it is about to overwrite.
      await (await (await capturing().getUrl(base)).close()).drain<void>();

      expect(seen.single.statusCode, 200);
      expect(seen.single.responseBody, '{"ok":true}');
    });

    test('a socket taken over is reported before it goes', () async {
      final response = await (await capturing().getUrl(base)).close();
      final socket = await response.detachSocket();

      expect(seen.single.statusCode, 200);

      socket.destroy();
    });

    test('ignore skips a url whole', () async {
      final response = await (await capturing(
        ignore: (url) => url.path == '/clients',
      ).getUrl(base)).close();

      expect(await read(response), '{"ok":true}');
      expect(seen, isEmpty);
    });

    test('a redirect is one exchange, under the url that was asked for',
        () async {
      final target = base.replace(path: '/clients/1');

      respond = (request) async {
        if (request.uri.path == '/clients') {
          await request.response.redirect(target);
          return;
        }
        await json(request);
      };

      final response = await (await capturing().getUrl(base)).close();
      await read(response);

      expect(seen.single.url, base);
      expect(seen.single.statusCode, 200);
    });

    test('reports once however the response is awaited', () async {
      final request = await capturing().getUrl(base);
      final closed = await request.close();

      expect(await request.done, same(closed));

      await read(closed);

      expect(seen, hasLength(1));
    });

    test('every setting the app makes reaches the client underneath', () async {
      final inner = HttpClient();
      final client = HttpCapture.client(seen.add, inner: inner)
        ..userAgent = 'alif/1.0'
        ..autoUncompress = false
        ..idleTimeout = const Duration(seconds: 3)
        ..maxConnectionsPerHost = 2
        ..connectionTimeout = const Duration(seconds: 5);

      expect(inner.userAgent, 'alif/1.0');
      expect(inner.autoUncompress, isFalse);
      expect(inner.idleTimeout, const Duration(seconds: 3));
      expect(inner.maxConnectionsPerHost, 2);
      expect(inner.connectionTimeout, const Duration(seconds: 5));

      expect(client.userAgent, 'alif/1.0');

      String? sent;
      respond = (request) async {
        sent = request.headers.value(HttpHeaders.userAgentHeader);
        await json(request);
      };

      await read(await (await client.getUrl(base)).close());

      expect(sent, 'alif/1.0');
    });

    test('a content type that does not parse costs the app nothing', () async {
      // `HttpHeaders.contentType` parses on every read and throws on a value
      // like this one. The app may never read that header; capture does, and a
      // header the app was happy to ignore must not fail its request.
      respond = (request) async {
        request.response.headers.set(
          HttpHeaders.contentTypeHeader,
          'text/plain; charset="unclosed',
        );
        request.response.add(utf8.encode('{"ok":true}'));
        await request.response.close();
      };

      // Added as bytes, because `write` reads the encoding off that same header
      // and throws on it with or without a wrapper in the way.
      final request = await capturing().postUrl(base);
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'text/plain; charset="unclosed',
      );
      request.add(utf8.encode('{"pin":"0000"}'));

      final response = await request.close();

      expect(await read(response), '{"ok":true}');

      // Still reported, minus the bodies it could not read a charset for.
      expect(seen.single.statusCode, 200);
      expect(seen.single.requestBody, isNull);
      expect(seen.single.responseBody, isNull);
    });

    test('a callback that throws does not break the request', () async {
      final client = HttpCapture.client((_) => throw StateError('logger'));

      final response = await (await client.getUrl(base)).close();

      expect(await read(response), '{"ok":true}');
    });
  });

  group('BugReport.httpClient', () {
    setUp(() => BugReport.init(captureConsole: false, captureErrors: false));

    tearDown(() => BugReport.dispose());

    Future<LogEntry> lastEntry() async => (await BugReport.entries()).last;

    test('a request becomes a line, and the secrets in it do not', () async {
      respond = (request) async {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          '{"access_token":"387606|t4sOm","has_pin":true}',
        );
        await request.response.close();
      };

      final request = await BugReport.httpClient(
        bodies: true,
      ).postUrl(base);
      request.headers.contentType = ContentType.json;
      request.write('{"phone":"998901234567","otp":"445566"}');
      await read(await request.close());

      final entry = await lastEntry();

      expect(entry.level, LogLevel.info);
      expect(entry.message, startsWith('POST $base 200 in '));
      expect(entry.message, endsWith('ms'));

      // Redaction is the same redaction as everywhere else: it runs on the way
      // in, so the token was never stored to begin with.
      expect(entry.extra?['request'], contains('998901234567'));
      expect(entry.extra?['request'], isNot(contains('445566')));
      expect(entry.extra?['response'], isNot(contains('387606')));
      expect(entry.extra?['response'], contains('"has_pin":true'));
    });

    test('the level says who has to look at it', () async {
      Future<LogLevel> levelOf(int status) async {
        respond = (request) async {
          request.response.statusCode = status;
          await request.response.close();
        };

        await (await BugReport.httpClient().getUrl(base)).close().then(
          (response) => response.drain<void>(),
        );

        return (await lastEntry()).level;
      }

      expect(await levelOf(200), LogLevel.info);
      expect(await levelOf(404), LogLevel.warning);
      expect(await levelOf(503), LogLevel.error);
    });

    test('goes where an adapter wants a plain factory', () {
      // What `IOHttpClientAdapter(createHttpClient: ...)` asks for, and the
      // reason every argument here is optional.
      final HttpClient Function() factory = BugReport.httpClient;

      factory().close();
    });

    test('a request that never arrives is an error with no status', () async {
      final client = BugReport.httpClient();
      await server.close(force: true);

      await expectLater(
        client.getUrl(base).then((request) => request.close()),
        throwsA(isA<SocketException>()),
      );

      final entry = await lastEntry();

      expect(entry.level, LogLevel.error);
      expect(entry.message, startsWith('GET $base failed in '));
      expect(entry.error, contains('SocketException'));
      expect(entry.extra, isNull);
    });
  });
}

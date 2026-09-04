import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_bug_report/flutter_bug_report.dart';
import 'package:flutter_test/flutter_test.dart';

/// With Dio actually in the loop, because that is what the wiring in the README
/// is for and every other test here drives `dart:io` by hand. Two apps wired
/// this up and got the lines without the payloads; a test that only speaks
/// `HttpClient` cannot tell you why.
void main() {
  late HttpServer server;
  late String base;
  late List<HttpExchange> seen;
  late Future<void> Function(HttpRequest request) respond;

  Future<void> json(HttpRequest request) async {
    request.response.headers.contentType = ContentType.json;
    request.response.write('{"ok":true,"id":7}');
    await request.response.close();
  }

  setUp(() async {
    seen = [];
    respond = json;

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://${server.address.address}:${server.port}';
    server.listen((request) => respond(request));
  });

  tearDown(() => server.close(force: true));

  Dio dioWith({bool bodies = true}) => Dio(BaseOptions(baseUrl: base))
    ..httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () => HttpCapture.client(seen.add, bodies: bodies),
    );

  test('a get through Dio arrives with its response body', () async {
    final response = await dioWith().get<Map<String, Object?>>('/profile');

    // Dio still got everything.
    expect(response.statusCode, 200);
    expect(response.data, {'ok': true, 'id': 7});

    final exchange = seen.single;
    expect(exchange.method, 'GET');
    expect(exchange.url.path, '/profile');
    expect(exchange.statusCode, 200);
    expect(exchange.responseBody, '{"ok":true,"id":7}');
  });

  test('a post through Dio arrives with both bodies', () async {
    respond = (request) async {
      request.response.statusCode = HttpStatus.unprocessableEntity;
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"code":"otp_invalid"}');
      await request.response.close();
    };

    await expectLater(
      dioWith().post<void>('/auth/verify-otp', data: {'otp': '445566'}),
      throwsA(isA<DioException>()),
    );

    expect(seen.single.statusCode, 422);
    expect(seen.single.requestBody, contains('445566'));
    expect(seen.single.responseBody, '{"code":"otp_invalid"}');
  });

  test('a gzipped response is still read', () async {
    // What a real gateway does, and the one thing the wrapper refuses to
    // decode itself. `autoUncompress` is on by default, so by the time the
    // body reaches here it is plain again.
    server.autoCompress = true;

    final response = await dioWith().get<Map<String, Object?>>('/profile');

    expect(response.data, {'ok': true, 'id': 7});
    expect(seen.single.responseBody, '{"ok":true,"id":7}');
  });

  test('a form post through Dio is kept too', () async {
    await dioWith().post<void>(
      '/auth/send-otp',
      data: {'phone': '998901234567'},
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );

    expect(seen.single.requestBody, contains('998901234567'));
  });

  test('a response Dio hands back as a stream is not held up', () async {
    final response = await dioWith().get<ResponseBody>(
      '/profile',
      options: Options(responseType: ResponseType.stream),
    );

    final body = await utf8.decodeStream(response.data!.stream);

    expect(body, '{"ok":true,"id":7}');
    expect(seen.single.responseBody, '{"ok":true,"id":7}');
  });

  test('bodies off is the line and nothing else', () async {
    await dioWith(bodies: false).get<Map<String, Object?>>('/profile');

    expect(seen.single.statusCode, 200);
    expect(seen.single.responseBody, isNull);
    expect(seen.single.requestBody, isNull);
  });

  test('a request Dio could not send is reported', () async {
    final dio = dioWith();
    await server.close(force: true);

    await expectLater(
      dio.get<void>('/profile'),
      throwsA(isA<DioException>()),
    );

    expect(seen.single.statusCode, isNull);
    expect(seen.single.failed, isTrue);
  });

  test('a receive timeout does not lose the exchange', () async {
    respond = (request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.bufferOutput = false;
      request.response.write('{"partial":');
      await request.response.flush();
      // Never closed: Dio gives up first.
    };

    final dio = dioWith()
      ..options.receiveTimeout = const Duration(milliseconds: 300);

    await expectLater(
      dio.get<void>('/clients'),
      throwsA(isA<DioException>()),
    );

    // Dio calls `abort()` on the request, so what is reported is whatever had
    // arrived — the status came back, the body did not finish.
    expect(seen, hasLength(1));
    expect(seen.single.statusCode, 200);
  });
}

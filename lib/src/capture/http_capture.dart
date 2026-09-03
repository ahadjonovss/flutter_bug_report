import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_bug_report/src/model/http_exchange.dart';

/// Puts the app's HTTP traffic into the log, without the app naming a client
/// library.
///
/// The request that failed is the thing a bug report is usually missing, and
/// the app already knows it: the method, the url, the status, how long it took
/// and — when it is text — what went either way. All of that is in
/// [HttpClient], which is what Dio, `package:http`, Chopper and Retrofit are
/// all built on. Wrapping that one class reaches every one of them without
/// this package depending on any of them.
///
/// Nothing global is touched. [HttpOverrides.global] is a single slot that
/// `flutter_test` and other packages also want, and taking it decides the
/// question for the whole process. A client the app hands to its own networking
/// layer decides nothing:
///
/// ```dart
/// // Dio
/// dio.httpClientAdapter = IOHttpClientAdapter(
///   createHttpClient: BugReport.httpClient,
/// );
///
/// // package:http
/// final client = IOClient(BugReport.httpClient());
/// ```
///
/// The line — method, url, status, duration — is always collected. Bodies are
/// opt-in, and when they are on they land in the log as text, so the redactors
/// apply to them the same way they apply to everything else: a bearer token in
/// a response is gone before it is stored.
abstract final class HttpCapture {
  /// How much of each body is kept, per direction, per exchange.
  ///
  /// Enough for the error object a server sends back, not enough for a page of
  /// search results.
  static const int defaultMaxBodyBytes = 4096;

  /// An [HttpClient] that reports every exchange it carries to [onExchange].
  ///
  /// [inner] is the client the work actually goes through, and defaults to a
  /// fresh [HttpClient] — which itself still consults [HttpOverrides], so a
  /// test that installed one keeps it.
  ///
  /// [bodies] reads the request and response payloads as well as the line.
  /// **Off by default, and that is the right default**: a body is the most
  /// useful thing here and the most sensitive, and redaction only knows the
  /// field names it was told about. A payload that is personal by nature —
  /// names, addresses, balances — is personal whether or not it holds a token.
  ///
  /// Switched on, only bodies whose content type says text are kept — `text/*`,
  /// json, xml, form encoding — capped at [maxBodyBytes] each way. An image, a
  /// protobuf or an upload with no declared type goes past untouched.
  ///
  /// [ignore] skips an exchange entirely, by url. Worth pointing at your own
  /// log-upload endpoint, which is otherwise a request that reports itself.
  static HttpClient client(
    void Function(HttpExchange exchange) onExchange, {
    HttpClient? inner,
    bool bodies = false,
    int maxBodyBytes = defaultMaxBodyBytes,
    bool Function(Uri url)? ignore,
  }) => _CapturingClient(
    inner ?? HttpClient(),
    _Options(
      onExchange: onExchange,
      bodies: bodies,
      maxBodyBytes: maxBodyBytes,
      ignore: ignore,
    ),
  );
}

/// What [HttpCapture.client] was asked for, carried down to every wrapper.
class _Options {
  const _Options({
    required this.onExchange,
    required this.bodies,
    required this.maxBodyBytes,
    required this.ignore,
  });

  final void Function(HttpExchange exchange) onExchange;
  final bool bodies;
  final int maxBodyBytes;
  final bool Function(Uri url)? ignore;

  bool ignores(Uri url) => ignore?.call(url) ?? false;

  /// Reports one exchange, and gives up on the report rather than on the
  /// request it was describing.
  ///
  /// Both halves run inside the app's own traffic, often from a stream
  /// handler, and both can fail: building the exchange reads the request and
  /// the response back, and delivering it runs the app's own callback. Neither
  /// is worth breaking a request that was working — a feature that exists to
  /// describe a bug has no business being one.
  ///
  /// [exchange] is built here rather than passed in so that it is inside this.
  void report(HttpExchange Function() exchange) {
    try {
      onExchange(exchange());
    } catch (_) {}
  }
}

/// Delegates every member, and wraps the requests on the way out.
class _CapturingClient implements HttpClient {
  _CapturingClient(this._inner, this._options);

  final HttpClient _inner;
  final _Options _options;

  /// [method] and [url] are taken as arguments rather than read back from the
  /// request, because a request that was never opened cannot be asked.
  Future<HttpClientRequest> _watch(
    String method,
    Uri url,
    Future<HttpClientRequest> pending,
  ) async {
    if (_options.ignores(url)) return pending;

    // Started before the await: opening a connection is part of how long the
    // request took, and on a bad network it is most of it.
    final stopwatch = Stopwatch()..start();

    try {
      return _CapturingRequest(await pending, _options, stopwatch);
    } catch (error) {
      // No host, no route, no certificate — the connection was never made.
      // Nothing else in the exchange will happen, and a report of an app that
      // could not reach anything is mostly made of these.
      _options.report(
        () => HttpExchange(
          method: method.toUpperCase(),
          url: url,
          duration: stopwatch.elapsed,
          error: error,
        ),
      );
      rethrow;
    }
  }

  /// The url [HttpClient.open] would have built from the same three arguments.
  static Uri _url(String host, int port, String path) {
    final query = path.indexOf('?');

    return query == -1
        ? Uri(scheme: 'http', host: host, port: port, path: path)
        : Uri(
            scheme: 'http',
            host: host,
            port: port,
            path: path.substring(0, query),
            query: path.substring(query + 1),
          );
  }

  @override
  Future<HttpClientRequest> open(
    String method,
    String host,
    int port,
    String path,
  ) => _watch(
    method,
    _url(host, port, path),
    _inner.open(method, host, port, path),
  );

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) =>
      _watch(method, url, _inner.openUrl(method, url));

  @override
  Future<HttpClientRequest> get(String host, int port, String path) => _watch(
    'get',
    _url(host, port, path),
    _inner.get(host, port, path),
  );

  @override
  Future<HttpClientRequest> getUrl(Uri url) =>
      _watch('get', url, _inner.getUrl(url));

  @override
  Future<HttpClientRequest> post(String host, int port, String path) => _watch(
    'post',
    _url(host, port, path),
    _inner.post(host, port, path),
  );

  @override
  Future<HttpClientRequest> postUrl(Uri url) =>
      _watch('post', url, _inner.postUrl(url));

  @override
  Future<HttpClientRequest> put(String host, int port, String path) => _watch(
    'put',
    _url(host, port, path),
    _inner.put(host, port, path),
  );

  @override
  Future<HttpClientRequest> putUrl(Uri url) =>
      _watch('put', url, _inner.putUrl(url));

  @override
  Future<HttpClientRequest> patch(String host, int port, String path) => _watch(
    'patch',
    _url(host, port, path),
    _inner.patch(host, port, path),
  );

  @override
  Future<HttpClientRequest> patchUrl(Uri url) =>
      _watch('patch', url, _inner.patchUrl(url));

  @override
  Future<HttpClientRequest> delete(String host, int port, String path) =>
      _watch(
        'delete',
        _url(host, port, path),
        _inner.delete(host, port, path),
      );

  @override
  Future<HttpClientRequest> deleteUrl(Uri url) =>
      _watch('delete', url, _inner.deleteUrl(url));

  @override
  Future<HttpClientRequest> head(String host, int port, String path) => _watch(
    'head',
    _url(host, port, path),
    _inner.head(host, port, path),
  );

  @override
  Future<HttpClientRequest> headUrl(Uri url) =>
      _watch('head', url, _inner.headUrl(url));

  @override
  Duration get idleTimeout => _inner.idleTimeout;

  @override
  set idleTimeout(Duration value) => _inner.idleTimeout = value;

  @override
  Duration? get connectionTimeout => _inner.connectionTimeout;

  @override
  set connectionTimeout(Duration? value) => _inner.connectionTimeout = value;

  @override
  int? get maxConnectionsPerHost => _inner.maxConnectionsPerHost;

  @override
  set maxConnectionsPerHost(int? value) =>
      _inner.maxConnectionsPerHost = value;

  @override
  bool get autoUncompress => _inner.autoUncompress;

  @override
  set autoUncompress(bool value) => _inner.autoUncompress = value;

  @override
  String? get userAgent => _inner.userAgent;

  @override
  set userAgent(String? value) => _inner.userAgent = value;

  @override
  set authenticate(
    Future<bool> Function(Uri url, String scheme, String? realm)? f,
  ) => _inner.authenticate = f;

  @override
  set authenticateProxy(
    Future<bool> Function(String host, int port, String scheme, String? realm)?
    f,
  ) => _inner.authenticateProxy = f;

  @override
  set badCertificateCallback(
    bool Function(X509Certificate cert, String host, int port)? callback,
  ) => _inner.badCertificateCallback = callback;

  @override
  set connectionFactory(
    Future<ConnectionTask<Socket>> Function(
      Uri url,
      String? proxyHost,
      int? proxyPort,
    )?
    f,
  ) => _inner.connectionFactory = f;

  @override
  set findProxy(String Function(Uri url)? f) => _inner.findProxy = f;

  @override
  set keyLog(Function(String line)? callback) => _inner.keyLog = callback;

  @override
  void addCredentials(
    Uri url,
    String realm,
    HttpClientCredentials credentials,
  ) => _inner.addCredentials(url, realm, credentials);

  @override
  void addProxyCredentials(
    String host,
    int port,
    String realm,
    HttpClientCredentials credentials,
  ) => _inner.addProxyCredentials(host, port, realm, credentials);

  @override
  void close({bool force = false}) => _inner.close(force: force);
}

/// Delegates every member, copies the body as it is written, and reports the
/// exchange once — whichever way it ends.
class _CapturingRequest implements HttpClientRequest {
  _CapturingRequest(this._inner, _Options options, this._stopwatch)
    : _options = options,
      _body = _Body(options.maxBodyBytes);

  final HttpClientRequest _inner;
  final _Options _options;
  final Stopwatch _stopwatch;
  final _Body _body;

  bool _reported = false;
  bool? _keepsBody;

  /// The response wrapper, made once: [close] and [done] both hand back the
  /// same response, and a second wrapper would be a second listener on a
  /// stream that only allows one.
  HttpClientResponse? _observed;

  /// Whether what is being written is worth keeping. Decided on the first
  /// write, by which time the content type has been set.
  bool get _keeps {
    if (!_options.bodies) return false;
    return _keepsBody ??= _isText(_inner.headers);
  }

  void _write(String text) {
    if (_keeps) _body.add(_encodingOf(_inner).encode(text));
  }

  /// Reports the exchange. Idempotent: the first ending wins, so a body that
  /// errors after its status arrived does not report twice.
  ///
  /// The bodies arrive as buffers rather than as text, because decoding one
  /// means reading the headers back — and that belongs inside the guard.
  void _report({
    HttpClientResponse? response,
    _Body? responseBody,
    Object? error,
  }) {
    if (_reported) return;
    _reported = true;
    _stopwatch.stop();

    _options.report(
      () => HttpExchange(
        method: _inner.method,
        url: _inner.uri,
        duration: _stopwatch.elapsed,
        statusCode: response?.statusCode,
        requestBody: _body.text(_encodingOf(_inner)),
        responseBody: response == null
            ? null
            : responseBody?.text(_charset(response.headers)),
        error: error,
      ),
    );
  }

  HttpClientResponse _observe(HttpClientResponse response) =>
      _observed ??= _wrap(response);

  HttpClientResponse _wrap(HttpClientResponse response) {
    if (_options.bodies && _isReadable(response)) {
      return _CapturingResponse(response, this, _options.maxBodyBytes);
    }

    // Nothing of this one will be read, so there is nothing left to wait for.
    _report(response: response);
    return response;
  }

  /// Whether the body can be copied without changing what the app receives.
  ///
  /// A 101 has handed the socket to something else — a web socket, most
  /// likely. A compressed body is bytes the app asked to decode itself. Both
  /// are read straight through.
  static bool _isReadable(HttpClientResponse response) =>
      response.statusCode != HttpStatus.switchingProtocols &&
      response.compressionState !=
          HttpClientResponseCompressionState.compressed &&
      _isText(response.headers);

  @override
  Future<HttpClientResponse> close() async {
    try {
      return _observe(await _inner.close());
    } catch (error) {
      _report(error: error);
      rethrow;
    }
  }

  @override
  Future<HttpClientResponse> get done => _inner.done.then(
    _observe,
    onError: (Object error, StackTrace stackTrace) {
      _report(error: error);
      Error.throwWithStackTrace(error, stackTrace);
    },
  );

  @override
  void add(List<int> data) {
    if (_keeps) _body.add(data);
    _inner.add(data);
  }

  @override
  Future<void> addStream(Stream<List<int>> stream) {
    if (!_keeps) return _inner.addStream(stream);

    // Mapped rather than listened to twice: a request body is usually a single
    // subscription stream, and reading it here would leave nothing to send.
    return _inner.addStream(
      stream.map((chunk) {
        _body.add(chunk);
        return chunk;
      }),
    );
  }

  @override
  void write(Object? object) {
    _write('$object');
    _inner.write(object);
  }

  @override
  void writeAll(Iterable<dynamic> objects, [String separator = '']) {
    _write(objects.join(separator));
    _inner.writeAll(objects, separator);
  }

  @override
  void writeln([Object? object = '']) {
    _write('$object\n');
    _inner.writeln(object);
  }

  @override
  void writeCharCode(int charCode) {
    _write(String.fromCharCode(charCode));
    _inner.writeCharCode(charCode);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _inner.addError(error, stackTrace);

  @override
  Future<void> flush() => _inner.flush();

  @override
  void abort([Object? exception, StackTrace? stackTrace]) =>
      _inner.abort(exception, stackTrace);

  @override
  Encoding get encoding => _inner.encoding;

  @override
  set encoding(Encoding value) => _inner.encoding = value;

  @override
  bool get persistentConnection => _inner.persistentConnection;

  @override
  set persistentConnection(bool value) => _inner.persistentConnection = value;

  @override
  bool get followRedirects => _inner.followRedirects;

  @override
  set followRedirects(bool value) => _inner.followRedirects = value;

  @override
  int get maxRedirects => _inner.maxRedirects;

  @override
  set maxRedirects(int value) => _inner.maxRedirects = value;

  @override
  int get contentLength => _inner.contentLength;

  @override
  set contentLength(int value) => _inner.contentLength = value;

  @override
  bool get bufferOutput => _inner.bufferOutput;

  @override
  set bufferOutput(bool value) => _inner.bufferOutput = value;

  @override
  String get method => _inner.method;

  @override
  Uri get uri => _inner.uri;

  @override
  HttpHeaders get headers => _inner.headers;

  @override
  List<Cookie> get cookies => _inner.cookies;

  @override
  HttpConnectionInfo? get connectionInfo => _inner.connectionInfo;
}

/// The response, copied as the app reads it.
///
/// Extends [Stream] rather than delegating its forty-odd members: every one of
/// them is written in terms of [listen], so overriding that one covers
/// `transform`, `toList`, `pipe` and the rest at once.
class _CapturingResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _CapturingResponse(this._inner, this._request, int maxBodyBytes)
    : _body = _Body(maxBodyBytes);

  final HttpClientResponse _inner;
  final _CapturingRequest _request;
  final _Body _body;

  bool _finished = false;

  void _finish([Object? error]) {
    if (_finished) return;
    _finished = true;

    _request._report(response: _inner, responseBody: _body, error: error);
  }

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _CapturingSubscription(
      _inner.listen(
        (chunk) {
          _body.add(chunk);
          onData?.call(chunk);
        },
        onError: (Object error, StackTrace stackTrace) {
          _finish(error);
          _forwardError(onError, error, stackTrace);
        },
        onDone: () {
          _finish();
          onDone?.call();
        },
        cancelOnError: cancelOnError,
      ),
      _body,
      _finish,
    );
  }

  @override
  Future<Socket> detachSocket() {
    // Whatever reads the socket from here is not this stream, so this is the
    // last chance to say what the exchange was.
    _finish();
    return _inner.detachSocket();
  }

  @override
  Future<HttpClientResponse> redirect([
    String? method,
    Uri? url,
    bool? followLoops,
  ]) {
    // The body of this hop is abandoned by definition. The hop that follows is
    // a fresh request through the same client, and reports itself.
    _finish();
    return _inner.redirect(method, url, followLoops);
  }

  @override
  int get statusCode => _inner.statusCode;

  @override
  String get reasonPhrase => _inner.reasonPhrase;

  @override
  int get contentLength => _inner.contentLength;

  @override
  HttpClientResponseCompressionState get compressionState =>
      _inner.compressionState;

  @override
  bool get persistentConnection => _inner.persistentConnection;

  @override
  bool get isRedirect => _inner.isRedirect;

  @override
  List<RedirectInfo> get redirects => _inner.redirects;

  @override
  HttpHeaders get headers => _inner.headers;

  @override
  List<Cookie> get cookies => _inner.cookies;

  @override
  X509Certificate? get certificate => _inner.certificate;

  @override
  HttpConnectionInfo? get connectionInfo => _inner.connectionInfo;
}

/// Keeps the copying in place when the handlers are replaced after the fact,
/// and reports the exchange if the read is cancelled instead of finished —
/// which is what a receive timeout looks like from here.
class _CapturingSubscription implements StreamSubscription<List<int>> {
  _CapturingSubscription(this._inner, this._body, this._finish);

  final StreamSubscription<List<int>> _inner;
  final _Body _body;
  final void Function([Object? error]) _finish;

  @override
  Future<void> cancel() {
    _finish();
    return _inner.cancel();
  }

  @override
  void onData(void Function(List<int> data)? handleData) {
    _inner.onData((chunk) {
      _body.add(chunk);
      handleData?.call(chunk);
    });
  }

  @override
  void onDone(void Function()? handleDone) {
    _inner.onDone(() {
      _finish();
      handleDone?.call();
    });
  }

  @override
  void onError(Function? handleError) {
    _inner.onError((Object error, StackTrace stackTrace) {
      _finish(error);
      _forwardError(handleError, error, stackTrace);
    });
  }

  /// [StreamSubscription.asFuture] overwrites the done and error handlers on
  /// the subscription underneath, so the ones installed by [listen] are gone
  /// from here. What it leaves behind is this future, so the end is read from
  /// that instead. `drain` and `pipe` both come through here.
  @override
  Future<E> asFuture<E>([E? futureValue]) => _inner.asFuture(futureValue).then(
    (E value) {
      _finish();
      return value;
    },
    onError: (Object error, StackTrace stackTrace) {
      _finish(error);
      Error.throwWithStackTrace(error, stackTrace);
    },
  );

  @override
  bool get isPaused => _inner.isPaused;

  @override
  void pause([Future<void>? resumeSignal]) => _inner.pause(resumeSignal);

  @override
  void resume() => _inner.resume();
}

/// Hands an error to a listener's handler the way [Stream.listen] would.
///
/// The handler is either unary or binary, and a missing one means the error
/// belongs to the zone — same as it would have without any of this in the way.
void _forwardError(Function? handler, Object error, StackTrace stackTrace) {
  if (handler == null) {
    Zone.current.handleUncaughtError(error, stackTrace);
  } else if (handler is void Function(Object, StackTrace)) {
    handler(error, stackTrace);
  } else if (handler is void Function(Object)) {
    handler(error);
  }
}

/// A bounded copy of a body.
class _Body {
  _Body(this._limit);

  final int _limit;
  final BytesBuilder _bytes = BytesBuilder();

  bool _truncated = false;

  void add(List<int> chunk) {
    if (chunk.isEmpty) return;

    final room = _limit - _bytes.length;
    if (room <= 0) {
      _truncated = true;
      return;
    }

    if (chunk.length <= room) {
      _bytes.add(chunk);
      return;
    }

    _bytes.add(chunk.sublist(0, room));
    _truncated = true;
  }

  /// The body as text, or null if there was none. A cut is marked, so that a
  /// json object with no closing brace reads as short rather than as broken.
  String? text(Encoding encoding) {
    if (_bytes.isEmpty) return null;

    final bytes = _bytes.toBytes();

    String decoded;
    try {
      decoded = encoding.decode(bytes);
    } on FormatException {
      // The cap fell inside a character, most likely.
      decoded = const Utf8Decoder(allowMalformed: true).convert(bytes);
    }

    return _truncated ? '$decoded…' : decoded;
  }
}

/// Whether a body under these headers is text somebody could read in a report.
///
/// An allow list rather than a deny list: an unknown type is far more likely
/// to be a photo or a protobuf than something worth putting in a log, and a
/// missing type says nothing at all.
bool _isText(HttpHeaders headers) {
  final type = _contentType(headers);
  if (type == null) return false;

  return switch (type.primaryType) {
    'text' => true,
    'application' => const {
      'json',
      'xml',
      'javascript',
      'x-www-form-urlencoded',
      'graphql',
    }.contains(type.subType) || type.subType.endsWith('+json'),
    _ => false,
  };
}

/// The encoding a body says it is in, or utf-8, which it nearly always is.
Encoding _charset(HttpHeaders headers) {
  final name = _contentType(headers)?.charset;
  if (name == null) return utf8;

  return Encoding.getByName(name) ?? utf8;
}

/// The encoding a request writes in, or utf-8 if asking cost an exception.
///
/// [HttpClientRequest.encoding] reads the charset off the content type, so it
/// throws on the same headers [_contentType] does.
Encoding _encodingOf(HttpClientRequest request) {
  try {
    return request.encoding;
  } on Exception {
    return utf8;
  }
}

/// The parsed content type, or null if it does not parse.
///
/// [HttpHeaders.contentType] parses on every read and throws on a header it
/// cannot make sense of — `text/plain; charset="unclosed` is enough. A server
/// that sends one of those, or an app that sets one, is not a reason for a
/// request to fail that would otherwise have worked: nothing else in the app
/// necessarily reads this header, and capture asking for it is not a licence
/// to break the traffic it is watching.
ContentType? _contentType(HttpHeaders headers) {
  try {
    return headers.contentType;
  } on Exception {
    return null;
  }
}

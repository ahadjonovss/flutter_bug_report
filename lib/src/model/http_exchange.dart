/// One request and whatever came back, as much of it as capture kept.
///
/// Handed to the callback given to `HttpCapture.client`, once per exchange,
/// after the response body has been read to its end — which is the first
/// moment the duration means anything.
class HttpExchange {
  const HttpExchange({
    required this.method,
    required this.url,
    required this.duration,
    this.statusCode,
    this.requestBody,
    this.responseBody,
    this.error,
  });

  /// The verb, upper case whatever case it was asked for: `GET`, `POST`.
  final String method;

  final Uri url;

  /// From the moment the request was opened to the end of the response body.
  ///
  /// Not the server's time: a slow phone on a slow network spends most of this
  /// somewhere between the two, which is exactly what a report needs to show.
  final Duration duration;

  /// The status, or null when nothing came back at all — a refused connection,
  /// a timeout, a certificate the client would not accept.
  final int? statusCode;

  /// What the app sent, if it was text and capture was asked for bodies.
  /// A trailing `…` means it was longer than the cap.
  final String? requestBody;

  /// What came back, under the same conditions as [requestBody].
  final String? responseBody;

  /// Why there is no [statusCode], or why the body stopped early.
  final Object? error;

  /// Whether the exchange ended without a response.
  bool get failed => statusCode == null;
}

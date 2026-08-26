/// Takes a secret out of a line before anything else sees it.
///
/// The point of the whole package is that a bundle leaves the device, so this
/// is the last gate before it does. Redaction runs once, on the way in: an
/// entry is rewritten as it is stored, never when it is read. A secret that was
/// never written down cannot leak out of a store someone later dumps by hand,
/// and a bundle built twice cannot be redacted twice differently.
abstract interface class Redactor {
  /// Returns [input] with whatever it recognises replaced. Called with a
  /// message, an error, a stack trace and every value in `extra`, separately.
  String apply(String input);

  /// A rule of your own: everything [pattern] matches becomes [replacement].
  factory Redactor.pattern(RegExp pattern, {String replacement}) =
      _PatternRedactor;

  /// Hides the value of any of [keys] wherever it appears as a JSON field, a
  /// query parameter, a header or a `key=value` pair.
  ///
  /// Keys rather than value shapes, because a token has no shape worth matching
  /// — it is whatever the server decided — but it always arrives under a name.
  factory Redactor.keys(Set<String> keys, {String replacement}) = _KeyRedactor;

  /// What every app should have on and few remember: the `Authorization`
  /// header, bearer tokens, and the field names a credential travels under.
  ///
  /// Not a complete list of secrets — nothing is. It is the list that is wrong
  /// to ship without.
  static List<Redactor> get defaults => [
    // Before the key rule, not after it: that rule rewrites the line, and a
    // token it half-consumes is a token these can no longer recognise.
    _bearer,
    _jwt,
    _pan,
    Redactor.keys(const {
      'authorization',
      'password',
      'passwd',
      'pin',
      'otp',
      'code',
      'token',
      'access_token',
      'refresh_token',
      'id_token',
      'api_key',
      'apikey',
      'secret',
      'client_secret',
      'session',
      'cookie',
      'set-cookie',
      'card_number',
      'pan',
      'cvv',
      'cvc',
    }),
  ];

  /// `Bearer eyJ…` wherever it is written out rather than sent as a header.
  static final Redactor _bearer = Redactor.pattern(
    RegExp(r'\bBearer\s+[A-Za-z0-9\-._~+/]+=*', caseSensitive: false),
    replacement: 'Bearer $_mask',
  );

  /// A JWT on its own, which is what a log line usually holds once the header
  /// has been stripped off it.
  static final Redactor _jwt = Redactor.pattern(
    RegExp(r'\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]*'),
  );

  /// A card number, spaced or run together, keeping the last four — the digits
  /// a person is asked to confirm and the only ones worth reading in a report.
  ///
  /// Checked against Luhn rather than length alone, so an order id and a
  /// timestamp do not come out starred.
  static final Redactor _pan = _PanRedactor();

  static const String _mask = '«redacted»';
}

/// Runs every rule over every field of an entry.
///
/// Order is the order they were given: a specific rule can hide a value before
/// a broader one turns it into something the broader rule no longer matches.
String redact(String? input, List<Redactor> redactors) {
  if (input == null || input.isEmpty || redactors.isEmpty) return input ?? '';

  var result = input;
  for (final redactor in redactors) {
    result = redactor.apply(result);
  }

  return result;
}

class _PatternRedactor implements Redactor {
  const _PatternRedactor(this._pattern, {String replacement = Redactor._mask})
    : _replacement = replacement;

  final RegExp _pattern;
  final String _replacement;

  @override
  String apply(String input) => input.replaceAll(_pattern, _replacement);
}

/// Finds a named field and replaces what follows it, in whichever of the four
/// shapes a log line writes it: `"key": "value"`, `key=value`, `key: value`,
/// `key value`.
///
/// The value is taken up to the first delimiter that ends it, so a redacted
/// field leaves the rest of the line — the closing brace, the next parameter —
/// intact and still readable as JSON.
class _KeyRedactor implements Redactor {
  _KeyRedactor(Set<String> keys, {String replacement = Redactor._mask})
    : _replacement = replacement,
      _pattern = RegExp(
        '($_quote?(?:${_alternation(keys)})$_quote?$_separator)$_value',
        caseSensitive: false,
      );

  /// The key may be written quoted, as in JSON, or bare, as in a query string
  /// or a header dump.
  static const String _quote = '["\']';

  /// What stands between a key and its value in each of those shapes.
  static const String _separator = r'\s*[:=]\s*';

  /// The value, in the order the alternatives must be tried:
  ///
  /// 1. quoted, and taken whole — the unambiguous case;
  /// 2. an auth scheme and the token after it, because `Bearer abc` is one
  ///    value with a space inside it and stopping at that space would leave the
  ///    token itself in the clear;
  /// 3. bare, and taken to the first delimiter that ends it — so what is left
  ///    of the line, the closing brace or the next parameter, stays readable.
  static const String _value =
      r'(?:"[^"]*"'
      r"|'[^']*'"
      r'|(?:Bearer|Basic|Token|JWT|Digest)\s+[^,;&}\]\s]+'
      r'|[^,;&}\]\s]+)';

  static String _alternation(Set<String> keys) =>
      keys.map(RegExp.escape).join('|');

  final RegExp _pattern;
  final String _replacement;

  @override
  String apply(String input) => input.replaceAllMapped(
    _pattern,
    (match) => '${match.group(1)}$_replacement',
  );
}

/// A card number, verified before it is hidden.
class _PanRedactor implements Redactor {
  _PanRedactor();

  static final RegExp _candidate = RegExp(r'\b(?:\d[ -]?){12,18}\d\b');

  @override
  String apply(String input) => input.replaceAllMapped(_candidate, (match) {
    final text = match.group(0)!;
    final digits = text.replaceAll(RegExp(r'[^0-9]'), '');

    if (digits.length < 13 || digits.length > 19) return text;
    if (!_passesLuhn(digits)) return text;

    return '${'*' * (digits.length - 4)}${digits.substring(digits.length - 4)}';
  });

  /// The checksum every card number carries. Cheap, and it is the difference
  /// between hiding a card and starring out an invoice number.
  static bool _passesLuhn(String digits) {
    var sum = 0;
    var double = false;

    for (var i = digits.length - 1; i >= 0; i--) {
      var digit = digits.codeUnitAt(i) - 0x30;
      if (double) {
        digit *= 2;
        if (digit > 9) digit -= 9;
      }
      sum += digit;
      double = !double;
    }

    return sum % 10 == 0;
  }
}

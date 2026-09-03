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
  ///
  /// A key matches a **whole field name**, counting `-`, `_` and `.` as part of
  /// the name: `{'pin'}` hides `pin`, `PIN` and `"pin"`, and leaves `has_pin`
  /// and `pin_hash` alone. Ask for more with a `*` on the side that may carry
  /// anything else — `{'*token'}` for `access_token` and `x-firebase-token`,
  /// `{'phone*'}` for `phone_number`, `{'*card*'}` for either end. The rule a
  /// caller gets is the rule they can read at the call site.
  factory Redactor.keys(Set<String> keys, {String replacement}) = _KeyRedactor;

  /// What every app should have on and few remember: the `Authorization`
  /// header, bearer tokens, and the field names a credential travels under.
  ///
  /// Not a complete list of secrets — nothing is. It is the list that is wrong
  /// to ship without.
  ///
  /// [defaultPatterns] and [defaultKeys] are the two halves of it, so a caller
  /// who needs the defaults minus one field name can say so without depending
  /// on the order of this list:
  ///
  /// ```dart
  /// redactors: [
  ///   ...Redactor.defaultPatterns,
  ///   Redactor.keys(Redactor.defaultKeys.difference(const {'pin'})),
  /// ],
  /// ```
  static List<Redactor> get defaults => [
    // Before the key rule, not after it: that rule rewrites the line, and a
    // token it half-consumes is a token these can no longer recognise.
    ...defaultPatterns,
    Redactor.keys(defaultKeys),
  ];

  /// The value shapes [defaults] recognises wherever they are written: `Bearer
  /// …`, a JWT on its own, a card number.
  static List<Redactor> get defaultPatterns => [_bearer, _jwt, _pan];

  /// The field names [defaults] hides the value of.
  ///
  /// Nothing here is a name an API uses for anything but a credential. A
  /// machine-readable error code arrives as `code`, which is a field a bug
  /// report is often written about, so the codes that are secrets are named
  /// one by one instead.
  static Set<String> get defaultKeys => const {
    'authorization',
    // Anything either side of `password`: `new_password`, `old_password`,
    // `password_confirmation`.
    '*password',
    'password*',
    'passwd',
    'pin',
    'otp',
    'otp_code',
    'sms_code',
    'verification_code',
    'confirmation_code',
    // `access_token`, `refresh_token`, `id_token`, `x-firebase-token`, and the
    // next one somebody invents. Not `token_type`, which says `Bearer`.
    '*token',
    '*api_key',
    '*api-key',
    '*apikey',
    '*secret',
    '*session',
    'session_id',
    'cookie',
    'set-cookie',
    'card_number',
    'pan',
    'cvv',
    'cvc',
  };

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
  /// Checked against Luhn, and against the lengths and prefixes the schemes
  /// actually issue, so an order id and a timestamp do not come out starred.
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
      // An empty set asks for nothing, and a pattern built from an empty
      // alternation matches every field there is.
      _pattern = keys.isEmpty
          ? null
          : RegExp(
              '($_quote?$_start(?:${_alternation(keys)})$_quote?$_separator)'
              '$_value',
              caseSensitive: false,
            );

  /// The key may be written quoted, as in JSON, or bare, as in a query string
  /// or a header dump.
  static const String _quote = '["\']';

  /// What a field name is made of. A name is matched whole, so `pin` is not
  /// found inside `has_pin`, and the caller who wants it there asks for
  /// `*pin` and can see that they asked.
  static const String _keyCharacter = r'[-\w.]';

  /// Where a field name is allowed to begin: anywhere the character before it
  /// is not part of a name of its own.
  static const String _start = '(?<!$_keyCharacter)';

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

  static String _alternation(Set<String> keys) => keys.map(_key).join('|');

  /// One key, whole, with a `*` on either side standing for the rest of a
  /// field name — none of it, or as much as there is.
  static String _key(String key) {
    var name = key;
    final open = name.startsWith('*');
    if (open) name = name.substring(1);
    final close = name.endsWith('*');
    if (close) name = name.substring(0, name.length - 1);

    final before = open ? '$_keyCharacter*' : '';
    final after = close ? '$_keyCharacter*' : '';

    return '$before${RegExp.escape(name)}$after';
  }

  final RegExp? _pattern;
  final String _replacement;

  @override
  String apply(String input) {
    final pattern = _pattern;
    if (pattern == null) return input;

    return input.replaceAllMapped(
      pattern,
      (match) => '${match.group(1)}$_replacement',
    );
  }
}

/// A card number, verified before it is hidden.
class _PanRedactor implements Redactor {
  _PanRedactor();

  static final RegExp _candidate = RegExp(r'\b(?:\d[ -]?){12,18}\d\b');

  @override
  String apply(String input) => input.replaceAllMapped(_candidate, (match) {
    final text = match.group(0)!;
    final digits = text.replaceAll(RegExp(r'[^0-9]'), '');

    if (!_hasCardLength(digits)) return text;
    if (!_passesLuhn(digits)) return text;

    return '${'*' * (digits.length - 4)}${digits.substring(digits.length - 4)}';
  });

  /// A card number is also a length its scheme issues, and that is the half of
  /// the test Luhn cannot do: Luhn alone lets through one in ten of every long
  /// number an app logs, and a product id starred out for no stated reason is
  /// a corrupted report nobody can explain.
  ///
  /// Sixteen digits stays unconditional. Gating it on the international IINs
  /// would quietly stop redacting every domestic scheme — Uzcard `8600`, Humo
  /// `9860`, Mir `2200` — which are cards to the person whose card it is. The
  /// other lengths are rarer for a card and commoner for an id, so those ask
  /// for a prefix as well.
  static bool _hasCardLength(String digits) => switch (digits.length) {
    16 => true,
    // Amex.
    15 => digits.startsWith('34') || digits.startsWith('37'),
    // Diners Club, the one scheme that issues fourteen.
    14 => _startsWithAny(digits, const ['30', '36', '38', '39']),
    // Visa, from before it was sixteen.
    13 => digits.startsWith('4'),
    // Visa, UnionPay and Discover, extended.
    17 || 18 || 19 => _startsWithAny(digits, const ['4', '6', '8']),
    _ => false,
  };

  static bool _startsWithAny(String digits, List<String> prefixes) =>
      prefixes.any(digits.startsWith);

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

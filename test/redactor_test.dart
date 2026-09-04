import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bug_report/flutter_bug_report.dart';
import 'package:flutter_bug_report/src/redaction/redactor.dart' show redact;

void main() {
  final defaults = Redactor.defaults;

  String clean(String input) => redact(input, defaults);

  group('Redactor.defaults', () {
    test('an authorization header keeps its name and loses its value', () {
      final result = clean('headers: {authorization: Bearer abc.def.ghi}');

      expect(result, contains('authorization'));
      expect(result, isNot(contains('abc.def.ghi')));
    });

    test('a JWT written on its own goes too', () {
      const token =
          'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dBjftJeZ4CVP';

      expect(clean('token refreshed: $token'), isNot(contains(token)));
    });

    test('a credential field is hidden and the json around it survives', () {
      final result = clean('{"phone":"998901234567","otp":"445566"}');

      expect(result, isNot(contains('445566')));
      // The rest of the object is still there to read.
      expect(result, contains('"phone"'));
      expect(result, contains('998901234567'));
      expect(result, endsWith('}'));
    });

    test('a query parameter is hidden without eating the next one', () {
      final result = clean('GET /auth?access_token=s3cr3t&lang=uz');

      expect(result, isNot(contains('s3cr3t')));
      expect(result, contains('lang=uz'));
    });


    test('a card number is masked but an order id is not', () {
      expect(clean('card 4242424242424242'), contains('************4242'));

      // Sixteen digits that fail Luhn: an order id, a timestamp, an account
      // number. Starring these out would make the log unreadable for nothing.
      expect(clean('order 1234567812345678'), contains('1234567812345678'));
    });

    test('an error code survives, and a code that is a secret does not', () {
      const line =
          '{"message":"OTP code sent","code":"otp_sent",'
          '"data":{"is_resend":false}}';

      // The single most useful field in a bug report about a failed request.
      expect(clean(line), line);
      expect(clean('{"code":"products_cart_incorrect"}'), contains('products'));

      expect(clean('{"otp_code":"3465"}'), isNot(contains('3465')));
      expect(clean('{"verification_code":"3465"}'), isNot(contains('3465')));
      expect(clean('{"sms_code":"3465"}'), isNot(contains('3465')));
    });

    test('a state flag named after a secret is not a secret', () {
      final result = clean(
        '{"access_token":"387606|t4sOm","refresh_token":"9931|zzz",'
        '"has_pin":true,"token_type":"Bearer"}',
      );

      expect(result, isNot(contains('387606')));
      expect(result, isNot(contains('9931')));
      expect(result, contains('"has_pin":true'));
    });

    test('a token under a vendor name still goes', () {
      final result = clean('{"x-firebase-token":"cJ8ZzQ:APA91bF","ok":true}');

      expect(result, isNot(contains('APA91bF')));
      expect(result, contains('"ok":true'));
    });

    test('a hyphenated header name is a name, not a pattern', () {
      expect(clean('set-cookie: session=a9f; Path=/'), isNot(contains('a9f')));
      expect(clean('x-api-key: k-123'), isNot(contains('k-123')));
    });

    test('a password under any name goes', () {
      for (final key in const [
        'password',
        'new_password',
        'old_password',
        'password_confirmation',
      ]) {
        expect(clean('{"$key":"hunter2"}'), isNot(contains('hunter2')));
      }
    });

    test('a long numeric id is left alone whatever its checksum', () {
      // Fourteen digits is a length no card scheme issues under a Visa
      // prefix, so this holds however the next id comes out of Luhn.
      expect(clean('variant_id: 46924319850674'), contains('46924319850674'));
      expect(clean('variant_id: 46924319850673'), contains('46924319850673'));
    });

    test('a line with no secret in it comes back unchanged', () {
      const line = 'GET /clients 200 in 143ms';

      expect(clean(line), line);
    });
  });

  group('Redactor.pattern', () {
    test('replaces what it matches', () {
      final redactor = Redactor.pattern(
        RegExp(r'\+998\d{9}'),
        replacement: '«phone»',
      );

      expect(
        redactor.apply('called +998901234567'),
        'called «phone»',
      );
    });
  });

  group('Redactor.keys', () {
    test('is case-insensitive and takes quoted values whole', () {
      final redactor = Redactor.keys(const {'pin'});

      expect(redactor.apply('"PIN": "0000"'), isNot(contains('0000')));
    });

    test('leaves a key it was not given', () {
      final redactor = Redactor.keys(const {'pin'});

      expect(redactor.apply('{"amount": 5000}'), contains('5000'));
    });

    test('matches a whole field name and nothing it is part of', () {
      final redactor = Redactor.keys(const {'pin'});

      expect(redactor.apply('{"has_pin":true}'), contains('true'));
      expect(redactor.apply('{"pin_hash":"a9f"}'), contains('a9f'));
      // A dotted path is a name like any other: `*pin` reaches into it, `pin`
      // does not, and both of those are readable from the call site.
      expect(redactor.apply('{"user.pin":"0000"}'), contains('0000'));
      expect(
        Redactor.keys(const {'*pin'}).apply('{"user.pin":"0000"}'),
        isNot(contains('0000')),
      );
    });

    test('a trailing * takes the rest of the name', () {
      final redactor = Redactor.keys(const {'phone*'});
      final result = redactor.apply(
        '{"user_id":8786,"phone_number":"923001234567"}',
      );

      expect(result, isNot(contains('923001234567')));
      expect(result, contains('8786'));
    });

    test('a leading * takes whatever the name is prefixed with', () {
      final redactor = Redactor.keys(const {'*phone'});

      expect(
        redactor.apply('{"contact_phone":"923001234567"}'),
        isNot(contains('923001234567')),
      );
      // None of it is as much as any of it.
      expect(redactor.apply('{"phone":"92300"}'), isNot(contains('92300')));
    });

    test('an empty set redacts nothing at all', () {
      const line = '{"amount":5000,"status":"ok"}';

      expect(Redactor.keys(const {}).apply(line), line);
    });

    test('the words of a key match however the api joined them', () {
      // A field name is one naming convention away from the one the rule was
      // written against, and that is the miss nobody notices.
      final redactor = Redactor.keys(const {'phone_number'});

      for (final spelling in [
        '{"phone_number":"923001234567"}',
        '{"phoneNumber":"923001234567"}',
        '{"phone-number":"923001234567"}',
        '{"phonenumber":"923001234567"}',
        '{"PhoneNumber":"923001234567"}',
      ]) {
        expect(
          redactor.apply(spelling),
          isNot(contains('923001234567')),
          reason: spelling,
        );
      }
    });

    test('a name is still whole, however its words are joined', () {
      final redactor = Redactor.keys(const {'phone_number'});

      // The words are optional-separator, not optional-anything: a longer
      // name that merely starts the same way is a different field.
      expect(
        redactor.apply('{"phone_numbers":[1,2]}'),
        '{"phone_numbers":[1,2]}',
      );
      expect(
        redactor.apply('{"old_phone_number":"92300"}'),
        '{"old_phone_number":"92300"}',
      );
    });
  });

  group('Redactor.defaults, the names it is easy to write around', () {
    // Each of these arrived from a real payload that walked past the rule
    // meant to cover it.
    test('a pin under any of the names one is asked for twice', () {
      for (final field in [
        'pin',
        'new_pin',
        'newPin',
        'old_pin',
        'current_pin',
        'confirm_pin',
        'repeat_pin',
        'pin_code',
        'pinCode',
        'pin_confirmation',
      ]) {
        expect(clean('{"$field":"1111"}'), isNot(contains('1111')),
            reason: field);
      }
    });

    test('but not the flags and counters a pin bug is read from', () {
      for (final line in [
        '{"has_pin":true}',
        '{"hasPin":true}',
        '{"is_pin_set":false}',
        '{"pin_attempts":2}',
      ]) {
        expect(clean(line), line);
      }
    });

    test('a camelCase spelling of a key that was written with words', () {
      for (final field in ['otpCode', 'cardNumber', 'apiKey', 'setCookie']) {
        expect(clean('{"$field":"secretvalue"}'), isNot(contains('secretvalue')),
            reason: field);
      }
    });

    test('a cvv with a 2 after it', () {
      expect(clean('{"cvv2":"123"}'), isNot(contains('123')));
      expect(clean('{"cvc2":"123"}'), isNot(contains('123')));
    });

    test('and still nothing that merely starts like one of them', () {
      for (final line in [
        '{"pan_india":true}',
        '{"panel_id":7}',
        '{"token_type":"Bearer"}',
        '{"otp_retry_after":30}',
      ]) {
        expect(clean(line), line);
      }
    });
  });

  group('Redactor.defaults, in pieces', () {
    test('the key set can be subtracted from', () {
      final mine = [
        ...Redactor.defaultPatterns,
        Redactor.keys(Redactor.defaultKeys.difference(const {'pin'})),
      ];

      expect(redact('{"pin":"1111"}', mine), contains('1111'));
      expect(redact('{"otp":"1111"}', mine), isNot(contains('1111')));

      // The value rules come along without being named or counted, which is
      // the point: a fourth one added here cannot go missing there.
      expect(
        redact('card 4242424242424242', mine),
        contains('************4242'),
      );
      expect(redact('auth: Bearer abc.def', mine), isNot(contains('abc.def')));
    });
  });
}

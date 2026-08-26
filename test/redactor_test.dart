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
  });
}

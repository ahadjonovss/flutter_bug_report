import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bug_report/flutter_bug_report.dart';

LogEntry _entry(String message) =>
    LogEntry(level: LogLevel.info, message: message);

void main() {
  group('MemoryLogStore', () {
    test('reads back what it was given, oldest first', () async {
      final store = MemoryLogStore();
      await store.open();

      for (final message in ['one', 'two', 'three']) {
        await store.write(_entry(message));
      }

      final entries = await store.read();

      expect(entries.map((e) => e.message), ['one', 'two', 'three']);
    });

    test('past its size the oldest line goes, not the newest', () async {
      final store = MemoryLogStore(maxEntries: 3);
      await store.open();

      for (var i = 1; i <= 5; i++) {
        await store.write(_entry('$i'));
      }

      final entries = await store.read();

      expect(entries.map((e) => e.message), ['3', '4', '5']);
    });

    test('a limit counts from the newest end', () async {
      final store = MemoryLogStore();
      await store.open();

      for (var i = 1; i <= 5; i++) {
        await store.write(_entry('$i'));
      }

      expect((await store.read(limit: 2)).map((e) => e.message), ['4', '5']);
    });

    test('a limit larger than the log is not an error', () async {
      final store = MemoryLogStore();
      await store.open();
      await store.write(_entry('only'));

      expect((await store.read(limit: 100)).length, 1);
    });

    test('clear empties it', () async {
      final store = MemoryLogStore();
      await store.open();
      await store.write(_entry('gone'));
      await store.clear();

      expect(await store.read(), isEmpty);
    });
  });
}

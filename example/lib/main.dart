import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bug_report/flutter_bug_report.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Before runApp, so the log covers startup — which is where the errors nobody
  // can reproduce tend to live.
  await BugReport.init();

  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'flutter_bug_report',
    theme: ThemeData(colorSchemeSeed: Colors.indigo),
    home: const ReportPage(),
  );
}

class ReportPage extends StatefulWidget {
  const ReportPage({super.key});

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  final _description = TextEditingController(
    text: 'The list was empty after I pressed refresh',
  );

  String? _preview;
  Bundle? _bundle;

  /// Stands in for a session: a few ordinary lines, a print nobody logged on
  /// purpose, a secret that should not survive, and something that throws.
  void _makeSomeNoise() {
    BugReport.info('opened the clients screen');
    BugReport.info(
      'GET /clients',
      extra: const {'status': 500, 'authorization': 'Bearer s3cr3t-token'},
    );
    BugReport.warning('retrying in 2s');

    debugPrint('a plugin printed this, and nobody asked it to');

    try {
      throw StateError('the list came back null');
    } on Object catch (error, stackTrace) {
      BugReport.error(
        'could not load clients',
        error: error,
        stackTrace: stackTrace,
      );
    }

    setState(() => _preview = null);
  }

  Future<void> _build() async {
    final bundle = await BugReport.build(
      description: _description.text,
      metadata: const {
        'app_version': '1.0.0+1',
        'platform': 'android',
        'device_model': 'Pixel 7',
      },
      // Text here only so the example can show it on screen. Ship zip.
      format: BundleFormat.text,
    );

    setState(() {
      _bundle = bundle;
      _preview = utf8.decode(bundle.bytes);
    });
  }

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bundle = _bundle;

    return Scaffold(
      appBar: AppBar(title: const Text('flutter_bug_report')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _description,
              decoration: const InputDecoration(
                labelText: 'What went wrong',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _makeSomeNoise,
                    child: const Text('Make some noise'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _build,
                    child: const Text('Build bundle'),
                  ),
                ),
              ],
            ),
            if (bundle != null) ...[
              const SizedBox(height: 12),
              Text(
                '${bundle.fileName} · ${bundle.sizeInBytes} bytes · '
                '${bundle.entryCount} entries'
                '${bundle.truncated ? ' · truncated' : ''}',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    _preview ?? 'Make some noise, then build the bundle.\n\n'
                        'Note what the bearer token looks like by the time it '
                        'reaches the file.',
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

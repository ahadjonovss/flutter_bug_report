import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_bug_report/src/bundle/bundle_format.dart';
import 'package:path_provider/path_provider.dart';

/// A finished bundle: bytes, and enough about them to hand over.
///
/// Bytes rather than a file, because most of what these are given to wants
/// bytes — an attachment, a multipart field, a `Uint8List` on a platform
/// channel — and writing to disk first only to read it back is a copy nobody
/// asked for. [writeTo] is there for the callers that genuinely need a path.
class Bundle {
  const Bundle({
    required this.bytes,
    required this.fileName,
    required this.format,
    required this.entryCount,
    required this.truncated,
    this.metadata = const {},
  });

  final Uint8List bytes;

  /// Timestamped, so two reports from the same phone do not overwrite each
  /// other in whatever directory they end up sharing.
  final String fileName;

  final BundleFormat format;

  String get mimeType => format.mimeType;

  int get sizeInBytes => bytes.length;

  /// How many entries made it in — which is not how many were logged, if the
  /// bundle hit a limit.
  final int entryCount;

  /// What was passed as `metadata` when this was built.
  ///
  /// Handed back rather than only written into the file, because whatever
  /// files the bundle usually wants the same facts beside it — as tags on an
  /// event, as fields on a form — and reading them back out of a zip to do
  /// that would be absurd.
  final Map<String, String> metadata;

  /// Whether a limit cut the log short. Worth saying out loud in the ticket:
  /// the reader is looking at the end of a session, not the whole of it.
  final bool truncated;

  /// Writes the bundle and returns the file.
  ///
  /// Defaults to the temporary directory: a bundle is made to be handed
  /// somewhere and has no business surviving in application storage, where it
  /// would sit unattended holding whatever the log held.
  Future<File> writeTo([Directory? directory]) async {
    final target = directory ?? await getTemporaryDirectory();
    final file = File('${target.path}${Platform.pathSeparator}$fileName');

    await file.parent.create(recursive: true);

    return file.writeAsBytes(bytes, flush: true);
  }
}

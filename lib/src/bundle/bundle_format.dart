/// What comes out the other end.
enum BundleFormat {
  /// One plain-text document: the header, then the lines, oldest first. What a
  /// person opens in a ticket and reads without tooling.
  text('txt', 'text/plain'),

  /// The same thing as an object — `report` and `entries` — for anything that
  /// is going to index it rather than read it.
  json('json', 'application/json'),

  /// Both of the above in an archive: `logs.txt` to read and `report.json` to
  /// query. The format every ticket system accepts without asking questions,
  /// and the one that survives a size limit a plain log would not.
  zip('zip', 'application/zip');

  const BundleFormat(this.extension, this.mimeType);

  final String extension;

  /// What to tell whatever it is being handed to. A bundle uploaded with the
  /// wrong type is a bundle nobody can open in the browser.
  final String mimeType;
}

# Golden bundles

Written by `flutter_bug_report`'s own builder, from
`test/fixtures.dart`. The log viewer parses these; do not
edit them by hand.

Regenerate by deleting this directory and running
`flutter test`.

### `ordinary.txt`, `ordinary.json`, `ordinary.zip`

The shape everything else is a deviation from.

### `multiline_message.txt`, `multiline_message.json`, `multiline_message.zip`

A message spanning lines, written unindented. Entry boundaries have to be anchored on the timestamp and the padded level, never on indentation.

### `multiline_description.txt`, `multiline_description.json`, `multiline_description.zip`

The sheet takes four lines, so a description can carry line breaks. In text they are wrapped two-space indented, like the metadata block.

### `no_metadata.txt`, `no_metadata.json`, `no_metadata.zip`

Every optional field absent at once: no description, no metadata, no error, no stack, no extra. Nothing may be assumed present.

### `truncated.txt`, `truncated.json`, `truncated.zip`

truncated: true, and entry_count below what went in. The beginning of the session is what was cut — the end is intact.

### `screenshot.txt`, `screenshot.json`, `screenshot.zip`

A screenshot was attached. The zip carries screenshot.png and its report names it; the text and json forms name nothing, because nothing can be in them. Bundles from 0.3.0 and earlier claim it in all three — a viewer still has to handle the claim without the file.

### `timeline.txt`, `timeline.json`, `timeline.zip`

A session with a real shape: a quiet stretch, a gap where nothing was logged, then everything going wrong at once. Every other fixture is stamped to the same instant so a regenerated file differs only where the builder changed — which makes them useless for anything that draws time. This one is for that.

### `empty.txt`, `empty.json`, `empty.zip`

A report filed before anything was logged. Still a bundle.


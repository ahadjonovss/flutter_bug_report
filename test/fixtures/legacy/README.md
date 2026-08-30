# Bundles from before 0.3.1

Written by the builder at tag `v0.3.0`, not by a hand-made approximation of it.
A test written against a description of an old format encodes what somebody
remembered about it; these are what it actually produced.

They matter because **0.1.0 through 0.3.0 are published and cannot be
unpublished.** Bundles in this shape will keep arriving in tickets for as long
as anybody runs a build that was compiled against them, so a reader of this
format has to handle them permanently — not until some migration finishes.

Regenerating them, if the need ever arises:

```
git worktree add --detach /tmp/fbr-030 v0.3.0
cp test/fixtures.dart test/fixtures_test.dart /tmp/fbr-030/test/
cd /tmp/fbr-030 && flutter pub get && flutter test test/fixtures_test.dart
```

Only these three files differ from what 0.3.1 produces. Everything else in
`test/fixtures/` is byte-identical across the two versions, which is the
evidence that 0.3.1 changed what it said it changed and nothing else.

### `multiline_description.txt`

The description's second and third lines sit unindented in the header, where
each reads as a field of its own. 0.3.1 wraps them two-space indented.

### `screenshot.txt`, `screenshot.json`

Both name `screenshot.png` in the report. Neither contains it, and neither
could: only a zip has anywhere to put a file. A reader that trusts the claim
goes looking for something that was never there.

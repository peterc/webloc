These fixtures deliberately come from sources other than the current writer.

`binary-*.webloc` were generated using Python 3's `plistlib.dumps` with
`fmt=plistlib.FMT_BINARY, sort_keys=False`. They cover inline string lengths,
additional metadata, UTF-16 strings, two-byte object references, a URL containing
`<plist`, and invalid root/URL types.

`binary-root-last.webloc` is a copy of the Python-generated short-URL fixture
with its object references renumbered so the root is last in the offset table.
Its contents were verified with both Python's `plistlib` and Apple's `plutil`.

`legacy-*.webloc` were generated with the unmodified writer from commit
`c7d2c00`. Each URL is `https://example.com/` followed by enough `a` characters to
reach the length in the filename. They preserve the old writer's insufficient
offset width, off-by-one table position, and (at 65,535 characters) wrapped table
position. Keep these files unchanged so compatibility is tested against actual
historical output.

The original `../oldstyle.webloc` and `../pliststyle.webloc` remain unchanged.

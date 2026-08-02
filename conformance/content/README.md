# Content-library conformance fixture

`library.json` is the shared, engine-neutral **content library** — a portable pack
of authored content (items / characters / towns / quests / narratives) that a
creator authors once and imports into any engine. It is the source artifact the
content-portability track proves round-trips into every engine's native entities
(the author-once / use-anywhere proof).

**This file is NOT a mirror.** Unlike the rest of `conformance/` (see
[`../VENDORED.md`](../VENDORED.md)), it has no counterpart in
`packages/core/conformance` and never had one — the claim that it did stood here
until tasklist 100's US-3 re-vendor checked. Core's shared content-library golden
is [`../content-library/`](../content-library) (`minimal.json`,
`riverside-starter.json`), which is mirrored byte-for-byte and carries a
different, current shape: a `manifest` block with
`contractVersion: "insimul-content-library-v1"` instead of the top-level
`schemaVersion` used here, and `quests` between `items` and `characters`. The two
are **not interchangeable**, and reconciling this importer onto the shared golden
belongs to the content-portability track, not to the runtime-core adoption.

`library.json` is declared `local` in `../VENDORED.json`, so the drift guard
leaves it alone rather than reporting it as a stale mirror. It is consumed here
by the Godot content importer
(`addons/insimul/runtime/content_library.gd`) and its parity gates
(`addons/insimul/tests/content_import_test.gd`), and by the same-shaped importers in
the Unity / Unreal legs, so no engine can silently diverge on the contract.

## Shape

A content library is a single JSON object:

- **`schemaVersion`** (int) — the library-format version. The importer gates on it
  (`InsimulContentLibrary.check_schema_version`); a version outside the supported
  range is rejected before any entity is materialized.
- **`id`**, **`name`** (string) — library identity.
- **`items`**, **`characters`**, **`towns`**, **`quests`**, **`narratives`**
  (array) — the entity collections. Each array MUST be present (may be empty). Every
  entity is an object with a unique **`id`**; the remaining fields are the
  engine-neutral, opaque payload each engine reads off as needed.

A library missing a required key, carrying a non-array collection, holding an
entity without an `id`, or stamped with an unsupported `schemaVersion` is invalid
and rejected with a clear `last_error()` — never partially imported.

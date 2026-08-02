# Vendored conformance corpus

Byte-for-byte mirror of `@insimul/core`'s `packages/core/conformance/` — the
**source of truth** for cross-runtime parity. This repository is standalone by
design (it does not path-resolve into core), so it carries a copy; the copy is
guarded rather than trusted.

## Provenance and the drift guard

`VENDORED.json` records the source commit and a sha256 per mirrored file.

```sh
npm run check                                                          # includes --check (no core needed)
npm run vendor:conformance -- --check --core /path/to/packages/core    # the REAL diff
npm run vendor:conformance -- --core /path/to/packages/core            # re-vendor
```

`--check` alone proves the tree matches what `VENDORED.json` records and that no
undeclared file is hiding inside a mirrored directory. With `--core` it
additionally diffs byte-for-byte against the source tree — that is the check that
catches core moving, and it is the one that had never been run.

## Why the guard exists

At the start of tasklist 100 the mirror had silently rotted and **nothing was
checking**:

| | vendored (before) | core | after re-vendor |
|---|---|---|---|
| `prolog/` files | 7 | 10 | 10 |
| `prolog/` cases | 41 (54%) | 76 | **76** |
| `prolog/gameplay.json` | pre-KINP (`quest(q1, …)`) | KINP `id/3` terms | mirrored |
| `predicate-schema-hash.json` | absent | present | mirrored |
| `content-library/` | absent | 2 fixtures | mirrored |
| `README.md` | pre-tasklist-91 | current | mirrored |
| `saves/` `quests/` `radiant/` `ui/` | identical | — | identical |

The missing files were `identity.json`, `equivalence.json` and `worlds.json` —
the whole KINP identity / equivalence / world layer. The Godot marshalling gate
now runs **76 of 76**, and both it and the radiant gate assert a case-count
floor, so a corpus that shrinks again fails loudly instead of printing a smaller
green number.

## Local, not mirrored

`VENDORED.json`'s `local` list is the set of paths that are this repo's own and
mirror nothing in core. The guard fails on any file that is neither mirrored nor
declared local.

- `VENDORED.md`, `VENDORED.json` — this file and the manifest.
- `content/library.json`, `content/README.md` — a Godot-local importer fixture in
  a **superseded** shape (`schemaVersion` + flat sections). Core's shared
  content-library golden is `content-library/*.json`
  (`manifest.contractVersion: "insimul-content-library-v1"`), now mirrored beside
  it. The two are not interchangeable; see `content/README.md`.

## Honest orphan note

Not every mirrored file has a reader in this repo yet — `content-library/` and
`predicate-schema-hash.json` currently have none. They are mirrored for
completeness and provenance. A file with no reader is dead weight; a file that
has quietly diverged is worse, because it makes a green gate mean less than it
appears to.

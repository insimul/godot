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

## Tasklist 147 US-2 — the band-120 corpora, and a floor that a re-vendor cannot lower

The mirror is now **63 files**, up from 34, at core `76782e5`:

| | before | now |
|---|---|---|
| `prolog/` files | 10 | **21** (the eight `mechanic-*` packs, `scaffold`, `agent-ai`, `geo-map`) |
| `prolog/` cases | 76 | **255** |
| decision corpora | none | `combat/` `stealth/` `traversal/` `skills/` `items/` `routines/` — **212 cases / 18 areas** |
| executed as QUERIES | only with a Godot binary | **all 255**, on any box, `npm run test:corpus` |
| executed as DECISIONS | nothing | **all 212** |

Two guards were added with them:

- **`CASE_FLOORS`** in `tools/vendor-conformance.mjs` — 19 hand-written minimums,
  465 cases. `prologCases` alone could never catch a shrink, because it is
  written *from* the corpus on every re-vendor: an upstream corpus that lost half
  its cases re-vendors to a smaller number and the guard agrees with it. A floor
  is a number a human wrote down, and a re-vendor cannot lower it.
- **`NOT_MIRRORED`**, now six entries rather than one. Every core corpus this
  repo does *not* carry is listed with a reason, and every run PRINTS them with a
  count — an exclusion nobody sees is how a corpus stops being checked. The
  reasons are in `RUNTIME_CORE_ADOPTION.md` §12.2; the shape of them is that a
  DECISION corpus needs the module's layer to be adopted, while a Prolog corpus
  does not (which is why `prolog/agent-ai.json` is mirrored and `ai/` is not).

## Tasklist 147 US-3 — the activation table, and a floor a case count cannot hold

The mirror is now **64 files**. `modules/genre-activation.json` — core's genre
bundle to active-module-set table, emitted from `INSIMUL_MODULES` — left
`NOT_MIRRORED` in the **same commit** that added the thing which runs it
(`gdextension/test/run_activation_tests.sh`, via the `modules.table` and
`modules.activate` rows). That is the rule this repo now works by, and its old
NOT_MIRRORED entry said so in as many words.

It needed a new kind of guard. `CASE_FLOORS` reads `cases.length`, and this file
has no `cases`: it is one object keyed by genre. So `tools/vendor-conformance.mjs`
grew **`TABLE_FLOORS`** — 8 genre bundles, 24 module activations — because the
failure worth catching here is a bundle that quietly stopped selecting a module,
and that is invisible to a file count and to a hash the re-vendor rewrites.

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

Not every mirrored file has a reader in this repo — `content-library/`,
`predicate-schema-hash.json` and **`ui/` (8 files)** have none on the host tier.
They are mirrored for completeness and provenance. A file with no reader is dead
weight; a file that has quietly diverged is worse, because it makes a green gate
mean less than it appears to.

Since US-2 that is no longer a note anyone has to remember. Every directory under
`conformance/` is now accounted for in `check-mechanics.mjs` by either
`DECISION_DIRS` (something runs it here) or `CORPUS_RUN_ELSEWHERE` (a named gate,
or an explicit `null` meaning *nothing here runs it*). A directory in neither
list fails the gate — so the next corpus cannot be vendored into silence, and the
three above are orphans **on the record** rather than by omission.

# Changelog — Insimul Godot Plugin

All notable changes to the Godot plugin are documented here. This package is
independently versioned; its version is the `godot` entry in the repo-root
`VERSIONS.json` (the single source of truth, enforced by
`npm run engines:manifests`) and must match both `addons/insimul/plugin.cfg` and
the top-level `asset-lib.json` metadata.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **`@insimul/core` adoption, first slice — radiant quest generation.**
  `InsimulRadiantSource` (`addons/insimul/runtime/radiant_source.gd`) generates
  radiant quests by calling core's own deterministic, Prolog-driven generator
  instead of re-implementing it. Same seed + world + time ⇒ byte-identical
  quests on every engine, pinned by the shared corpus `conformance/radiant/*.json`
  (`npm run test:radiant`, 11 cases). Set `source = SOURCE_NONE` for
  pre-adoption behaviour.
- **`libinsimulcore` (`gdextension/corebridge/`)** — the C ABI all four runtimes
  will bind (`insimulcore.h`: opaque handle, JSON in, JSON out), with core's
  TypeScript running behind it in an embedded QuickJS and its Prolog seam wired
  to the natively linked libinsimul rather than a wasm copy. `InsimulCore`
  exposes it to GDScript. See `gdextension/corebridge/README.md` and
  `RUNTIME_CORE_ADOPTION.md` §4.
- `npm run test:radiant` (the adoption gate) and `npm run vendor:core` (re-vendor
  the core bundle); `npm run check` now also guards the vendored bundle against
  drift.
- **`npm run test:quest-parity`** — the two-implementation diff. Runs
  `conformance/quests/{hydration,radiant}-cases.json` through both this repo's
  hand-ported C++ quest core and `@insimul/core`, and classifies every case
  **AGREE / FIX / SHAPE / REGRESSION** against the committed corpus. Result:
  **7 AGREE, 0 regressions** — the hand-port and core agree byte-for-byte on
  every shared vector. `--source cpp` runs the hand-port alone (no libinsimul).
  See `RUNTIME_CORE_ADOPTION.md` §10.3.
- **`npm run vendor:conformance`** — re-vendor and drift-guard the shared
  conformance corpus, mirroring `vendor:core`'s two modes. `npm run check` now
  runs `--check`; pass `--core <packages/core>` for a byte-for-byte diff against
  the source tree.
- `run_radiant_tests.sh --source none` now **classifies** the pre-adoption leg
  (4 AGREE, 7 GAIN, 0 REGRESSION) and fails if that leg ever produces a quest of
  its own, or if the GAIN count reaches zero.
- `asset-lib.json` — Godot Asset Library submission metadata, version-locked to
  `plugin.cfg` and `VERSIONS.json` by `npm run engines:manifests`.
- Asset Library release dry-run (`scripts/release/build-assetlib-zip.mjs`): stages
  `addons/insimul/**` (no `templates/` tree) and builds + validates a
  `dist/insimul-godot-<version>.zip`.

### Fixed
- **`InsimulProlog.consult()`, `assert_fact()`, `retract_fact()` and `restore()`
  returned the inverse of what happened.** The vendored libinsimul header was a
  hand-written contract copy predating the library, and it documented "1 on
  success" where libinsimul returns **0**. Found by the first code to actually
  link the library; the header is now a verbatim copy of the shipping one.
- `run_save_tests.sh`, `run_quest_tests.sh` and `run_bootstrap_tests.sh` resolve
  the vendored conformance corpus first, like `run_conformance.sh` already did.
  They hardcoded a monorepo sibling path and so failed in a standalone checkout —
  58, 33 and 42 checks now run green instead of reporting 20, 6 and 21 path
  failures.
- **The vendored conformance corpus had silently rotted to 54% of the source and
  nothing was checking.** `conformance/prolog/` carried **41 of core's 76 cases**
  — the whole KINP `identity` / `equivalence` / `worlds` pack was missing and
  `gameplay.json` was a pre-KINP snapshot — while `VENDORED.md` described the
  directory as a mirror. Re-vendored to byte-identity (34 files,
  `packages/core` @ `443cce78`), so `npm run test:conformance` now runs
  **76 cases / 97 solutions** instead of 41. `predicate-schema-hash.json` and
  `content-library/` are mirrored too.
- `conformance/content/library.json` no longer claims to mirror a core file that
  does not exist; it is declared local, and core's actual content-library golden
  (`conformance/content-library/`) now sits beside it. The two shapes are not
  interchangeable — see `conformance/content/README.md`.
- **Two gates that could not fail.** `run_conformance.sh` returned success on an
  empty corpus directory; it now asserts a file and case floor. The quest-parity
  classifier asserts all five of its verdicts are reachable before it reports
  agreement.

## [1.0.0]

### Added
- Initial addon (`addons/insimul/`): `InsimulClient` autoload, `InsimulNPC`,
  streaming text/audio, lip sync, microphone capture, and world-export loading.

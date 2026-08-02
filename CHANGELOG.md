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

## [1.0.0]

### Added
- Initial addon (`addons/insimul/`): `InsimulClient` autoload, `InsimulNPC`,
  streaming text/audio, lip sync, microphone capture, and world-export loading.

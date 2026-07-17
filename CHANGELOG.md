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
- `asset-lib.json` — Godot Asset Library submission metadata, version-locked to
  `plugin.cfg` and `VERSIONS.json` by `npm run engines:manifests`.
- Asset Library release dry-run (`scripts/release/build-assetlib-zip.mjs`): stages
  `addons/insimul/**` (no `templates/` tree) and builds + validates a
  `dist/insimul-godot-<version>.zip`.

## [1.0.0]

### Added
- Initial addon (`addons/insimul/`): `InsimulClient` autoload, `InsimulNPC`,
  streaming text/audio, lip sync, microphone capture, and world-export loading.

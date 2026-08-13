# `insimul-talos-bridge` — Godot

The third artifact of [`TALOS_INSIMUL_BRIDGE.md`](https://github.com/) §7.5: the
Talos bridge for an Insimul game **depends on both projects and is depended on by
neither**. Not an adapter inside the Insimul plugin, not a profile inside the
Talos plugin — a separate addon, installed only when a game is being played
tested.

```
addons/insimul/          the game's runtime SDK          — ships in the game
addons/talos/            Talos's Bridge                  — QA only, dormant unless armed
addons/insimul_talos/    THIS                            — QA only, inert without either
```

Three artifacts is one more than anybody wants. It is the honest number: any
smaller count requires one project to take a dependency on the other's internals,
which is the thing the design forbids and which Unity's and Unreal's module
systems independently refuse. Godot's does not refuse it — its game-side contract
is duck-typed — which is exactly why the discipline has to be deliberate here.

## Install

1. Install the Insimul plugin (`addons/insimul/`) and build its GDExtension. This
   addon's decision half is the `InsimulTalosBridge` class that extension
   registers; without it the adapter reports a broken install rather than a
   working one.
2. Install Talos's addon (`addons/talos/`) and enable it.
3. Enable **Insimul Talos Bridge** in *Project Settings → Plugins*. It registers
   the `InsimulTalos` autoload.
4. **Merge [`talos.game.yaml`](talos.game.yaml) into the game's own manifest.**
   This is the step that matters and the one an installer gets wrong: the Bridge
   finds the adapter through manifest-declared GROUPS, so an adapter whose groups
   are not named is invisible, and `save_checkpoint` refuses with
   `no_checkpoint_hooks` — correctly, and after the run has started.
5. Hand the adapter a world once one is loaded:

   ```gdscript
   InsimulTalos.attach_world(prolog_kb, world_id, seed, active_modules)
   InsimulTalos.declare_state("quest.open", "quest_status(Q, active)")
   ```

**Exclude this addon and `addons/talos/` from release export presets.** Both are
QA-only. Talos's autoload is dormant without its launch switch and this one is
inert without Talos, but the posture should be explicit rather than inherited.

## What it maps

| TBP | Insimul | Where |
| --- | --- | --- |
| `query_state` | a Prolog query over the live KB, canonically sorted before the digest cap | `watch: insimul/state/*` → `_get()` |
| `set_progress_var` | an assert — refused when it would land on a world template | `watch: insimul/progress/*` → `_set()` |
| `save_checkpoint` | `insimul_kb_snapshot`, stamped with the four version axes | `talos_save()` |
| `restore_checkpoint` | `insimul_kb_restore`, refused when the stamp does not match the published matrix | `talos_load()` |
| `teleport` | generated places with entity ids stable across regenerations from one seed | `talos_announce_markers()` |
| `set_seed` | the world seed | `talos_set_seed()` |
| `declare_context` | the host game-state **phase** — never Insimul's `@world` | `talos_context_changed` |
| `mark_event` | KB deltas | `talos_event` |

Every other TBP verb is refused with a why-not token rather than a generic
failure: `insimul_verb_host_owned` for the ones a knowledge base has no reading
for (frames, pixels, clocks, input paths) and `insimul_verb_unmapped` for the ones
within Insimul's reach that this artifact does not map yet. The whole table is
[`bridge-contract.json`](bridge-contract.json), which is data because both readers
— the decision core and this document's gate — must quote one list.

`inject_input` is deliberately in the first group. Injecting at Insimul's action
layer would bypass the engine's input pipeline entirely, which is the one thing
`inject_input` exists to test; it would report `action_fired: true` while proving
nothing about `reached_tree`. Refusing is the honest answer.

## The one rule

**The adapter never reads the knowledge base while it is being constructed.**

Autoload order in Godot is registration order, and registration order is whichever
addon a developer enabled first. A `_ready`-time KB read therefore works on one
machine and not the next — and it fails *silently*, because an early read returns
an empty KB rather than an error, and a Conductor reads "no facts" as a fact.

The fix is structural rather than sequential: this node has no KB until a running
game hands it one through `attach_world()`, so there is no ordering to get wrong.
Until then `talos_ready_state()` answers false and every state answer is the
retryable `insimul_kb_uninitialized` refusal.

## Versions

The bridge refuses at the handshake rather than at first use. A refusal at
`hello` is something a Conductor can plan around; a refusal at the first
`restore_checkpoint` is a wasted run. The decision is the workspace's published
six-rung contract, and it is read from
[`supported-versions.json`](supported-versions.json) — mirrored from the
workspace matrix by `tools/vendor-supported-versions.mjs`, never compiled in,
because the answer is meant to be knowable before a run and a build that likes
itself is not evidence.

Against the matrix as published today, **this bridge refuses on Godot** with
`insimul_engine_version_declared`: `compatibility_minimum = "4.2"` is a floor
rather than a support claim, no GDExtension has been built for any minor, and
Talos's green claim is at 4.6. That refusal is the current honest state, it is a
checked-in case, and it will start failing the day a cell is genuinely earned —
which is the signal to re-publish, not a nuisance.

`capabilities.insimul` — the block all of this rides on — **does not validate
against tbp/1.x today**: `hello_response.schema.json` declares `capabilities` with
`additionalProperties: false` and rejects unknown keys by design. That is a
counterparty ask, not something this side can work around, so the payload is
assembled, published on the `insimul.capabilities` watch key, and travels the
moment an additive Talos minor registers the namespaced block.

## Gates

```sh
npm run check              # includes the artifact's structural gate + 7 negative controls
npm run test:talos-bridge  # the decision half, against the reference's own 21 cases
```

`gdextension/test/run_talos_bridge_tests.sh` replays every case
`scripts/engine-versions/check-hello.mjs` publishes — the reference implementation
of the same contract — and demands the same verdict and the same token, plus the
two controls that prove the decision is read from the matrix rather than baked
into the build. It needs no libinsimul and no Godot binary, so it always runs.

## Files

| | |
| --- | --- |
| `insimul_talos_plugin.gd` | the `EditorPlugin` that registers the autoload |
| `insimul_talos_adapter.gd` | the node: six groups, four methods, three signals, no Talos symbol |
| `bridge-contract.json` | the declared surface — groups, all 25 verbs, the verb-stage tokens |
| `supported-versions.json` | the mirrored version matrix (generated; do not hand-edit) |
| `talos.game.yaml` | the manifest fragment a game merges |
| `gdextension/src/talos_bridge.*` | the decision half, host-tested under a plain compiler |

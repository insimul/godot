# Quest / radiant conformance corpus (US-XC3)

Language-neutral, data-only golden cases for the cross-engine quest gate. Every
runtime (TS authority, Unreal `FInsimulQuestSystem`, and the future `libinsimul`
C harness) reproduces the committed `expected` values byte-for-byte.

## Files

- **`hydration-cases.json`** — quest hydration goldens.
  `cases[].input` is the quest seed (`content`: Prolog source, optional runtime
  `status`); `cases[].expected` is the present-only projection of
  `hydrateQuestFromProlog(input)` (see
  `packages/core/scripts/quest-golden-manifest.ts` → `projectHydratedQuest`).
  Fields are **omitted when absent** (never `null`) so the canonical bytes match
  on every runtime; the always-null back-fill fields (`questChainId`,
  `parentQuestId`) are intentionally excluded from the projection.

- **`radiant-cases.json`** — radiant-tick goldens.
  Given `quests` (`id` + `tags` + `status`), `maxOffering`, and `ticks`, the
  deterministic `radiantTick` offers up to `maxOffering` still-available radiant
  quests (tag `radiant`, status `available`, ascending id order, never
  re-offered) per tick, asserting `quest_offered(questId, tick)` facts.
  `cases[].expected` is the emitted fact list, compared as an **order-independent
  multiset**.

## Regenerating

The `expected` values are emitted from the TS semantics authority, not authored
by hand:

```sh
cd packages/core && npm run quest-goldens   # vite-node scripts/emit-quest-goldens.ts
```

Commit the regenerated JSON. Two guards keep the corpus honest:

- **TS drift guard** — `src/conformance/__tests__/quest-goldens-crosscheck.test.ts`
  (runs in `npm test`) recomputes `expected` from `hydrateQuestFromProlog` /
  `radiantTick` and fails if the committed JSON differs.
- **C++ host harness** — `packages/unreal/tools/verify-unreal/test_quest_system.cpp`
  independently reproduces `expected` from the portable port. A pass proves the
  Unreal runtime agrees with TS on hydrated fields and radiant facts.

Both read these same JSON files, so a semantics change surfaces in both gates.

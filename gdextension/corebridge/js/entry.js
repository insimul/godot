// entry.js — the bundle entry point: the ONLY place that says which of
// `@insimul/core`'s functions this adapter exposes across the C ABI.
//
// Adding a method here is what "adopting more of core" means for this plugin.
// The method table is deliberately explicit: `insimul_core_call()` cannot reach
// arbitrary core internals, so the adopted surface is reviewable in one screen.
//
// Contract with the C host (../src/insimulcore.c):
//   `globalThis.__insimul_core_dispatch(method, argsJson) -> Promise<any>`
// The host JSON.stringifies whatever the promise fulfils with, and turns a
// rejection into `insimul_core_last_error()`.

// FIRST, and it has to be: core's `identity/kinp.ts` constructs a `TextEncoder`
// at module scope, and esbuild emits modules in import order. See the file.
import './host-text-codec.js';

import { generateRadiantQuests } from '@insimul/core/radiant/radiant-engine';
import { BASE_RADIANT_TEMPLATES, BASE_RADIANT_TEMPLATE_IDS } from '@insimul/core/radiant/base-templates';
// The quest-golden manifest is core's declared authority for the SHAPE the
// quest corpus is compared in (`conformance/quests/*.json` is emitted from it),
// and `radiantTick` is defined there rather than in src/ precisely so the TS
// reference and every port assert against one definition. Importing it is what
// lets US-3 compare core against this repo's hand-ported quest_system.cpp
// without either side reimplementing the other. NOT an adopted runtime surface:
// these two methods exist for the parity gate (RUNTIME_CORE_ADOPTION.md §10).
import {
	computeHydrationExpected,
	radiantTick,
} from '@insimul/core-scripts/quest-golden-manifest';

// ── The band-120 mechanic modules (tasklist 147, US-1) ──────────────────────
//
// Seven decision layers, imported exactly as `radiant.generate` is. Adopting a
// module is THIS LINE plus a row below plus a host implementation in the engine
// — never a port (UNIFICATION_ROADMAP decision 1). The `git grep` that proves it
// is the absence of a second damage formula, suspicion curve or traversal cost
// anywhere in `gdextension/` and `addons/`.
import { CombatResolver } from '@insimul/core/game-engine/logic/CombatResolver';
import { StaminaPool } from '@insimul/core/game-engine/logic/StaminaPool';
import { DetectionTracker } from '@insimul/core/game-engine/logic/DetectionTracker';
import { TraversalPlanner } from '@insimul/core/game-engine/logic/TraversalPlanner';
import { SkillProgression } from '@insimul/core/game-engine/logic/SkillProgression';
import { EquipmentManager } from '@insimul/core/game-engine/logic/EquipmentManager';
import { RoutineDirector } from '@insimul/core/game-engine/logic/RoutineDirector';
import { CombatActionTable } from '@insimul/core/combat/action-table';
// ── Genre bundle → active module set (tasklist 147, US-3) ───────────────────
//
// The activation table is DATA (`docs/module-contract.md` §7): a genre selects
// modules, a module names its pack and its host interfaces, and a plugin that
// reads that resolves what to activate without a list of mechanics in its own
// source. These three rows are the whole of it — `modules.activate` for one
// world, `modules.table` for the committed table, `prolog.packs` for the pack
// TEXT that the active set names but does not carry.
import {
	activeModulesForWorld,
	moduleActivationTable,
	resolveActiveModules,
} from '@insimul/core/modules/module-activation';
import {
	PREDICATE_PACK_AREAS,
	PREDICATE_PACKS,
} from '@insimul/core/prolog/predicate-packs';
// The Prolog seam, resolved by the bundler to js/host-prolog-engine.js — the
// same native Trealla the rest of this plugin links.
import { createPrologEngine } from '@insimul/core/prolog/prolog-engine';
import {
	adapterFor,
	beginCall,
	closeSession,
	combatStatSinkShim,
	created,
	combatSystemShim,
	endCall,
	HOST_INTERFACES,
	newSession,
	openSessions,
	session,
	sessionEngine,
	skillModifierSinkShim,
	survivalShim,
} from './host-mechanics.js';
// The conformance runners (tasklist 147, US-2). Adapter-owned, and deliberately
// a separate module: they are the only code here whose caller is a gate rather
// than a game, and keeping them out of the mechanic rows keeps the shipped
// surface readable.
import { CORPUS_AREAS, CORPUS_AREAS_BY_MODULE, runCorpusCase } from './host-corpus.js';

/**
 * Which module owns which rows, which host interfaces it executes through, and
 * which decision layer answers. Data, not prose, because
 * `tools/verify-mechanics/check-mechanics.mjs` diffs it against core's own
 * `INSIMUL_MODULES` manifest — a module whose parts move in core fails the gate
 * here rather than rotting quietly.
 */
const MECHANIC_MODULES = {
	combat: {
		layers: ['CombatResolver'],
		hostInterfaces: ['ICombatSystem', 'ITrajectoryProbe'],
		rows: ['combat.create', 'combat.attack', 'combat.defend', 'combat.endDefense', 'combat.state'],
	},
	stamina: {
		layers: ['StaminaPool'],
		hostInterfaces: ['ISurvivalSystem'],
		rows: ['stamina.create', 'stamina.spend', 'stamina.rest', 'stamina.state'],
	},
	perception: {
		layers: ['DetectionTracker'],
		hostInterfaces: ['IPerceptionProbe'],
		rows: ['perception.create', 'perception.observe', 'perception.state'],
	},
	traversal: {
		layers: ['TraversalPlanner'],
		hostInterfaces: ['ITraversalProbe', 'ILocomotionHost'],
		rows: ['traversal.create', 'traversal.traverse', 'traversal.affordances', 'traversal.state'],
	},
	skill: {
		layers: ['SkillProgression'],
		hostInterfaces: ['ISkillModifierSink'],
		rows: ['skill.create', 'skill.award', 'skill.unlock', 'skill.state'],
	},
	equipment: {
		layers: ['EquipmentManager'],
		hostInterfaces: ['ICombatStatSink'],
		rows: ['equipment.create', 'equipment.equip', 'equipment.unequip', 'equipment.state'],
	},
	routine: {
		layers: ['RoutineDirector'],
		hostInterfaces: ['ILocomotionHost'],
		rows: ['routine.create', 'routine.tick', 'routine.state'],
	},
};

/** The shared meter, when a combat or traversal session names one. */
function staminaOf(args) {
	return args.stamina === undefined || args.stamina === null
		? undefined
		: session({ session: args.stamina }, 'stamina').layer;
}

/** One resolved genre, with the pack list and interfaces lifted to the top. */
function activated(source, set) {
	return {
		source,
		active: set,
		predicatePacks: [...set.predicatePacks],
		hostInterfaces: [...set.hostInterfaces],
		reason: set.known ? '' : `core has no genre bundle "${set.genre}" — shared vocabulary only`,
	};
}

/** No genre was declared: every pack, and nothing activated. See the row. */
function undeclared(reason) {
	return {
		source: 'undeclared',
		active: null,
		predicatePacks: [...PREDICATE_PACK_AREAS],
		hostInterfaces: [],
		reason,
	};
}

/** The adopted surface. One entry per method name callable from the host. */
const METHODS = {
	/**
	 * `radiant.generate` — the first adopted slice (RUNTIME_CORE_ADOPTION.md §5).
	 * args: `{ kb: string | string[], options: { seed, now, maxQuests? } }`
	 * result: `{ quests: GeneratedRadiantQuest[] }`
	 */
	'radiant.generate': (args) => generateRadiantQuests(args.kb, args.options),

	/**
	 * `radiant.baseTemplates` — core's shipped template pack, so a game does not
	 * have to vendor a copy of it to generate anything.
	 */
	'radiant.baseTemplates': () => ({
		templates: BASE_RADIANT_TEMPLATES,
		templateIds: BASE_RADIANT_TEMPLATE_IDS,
	}),

	/**
	 * `quest.hydrate` — core's `hydrateQuestFromProlog`, projected exactly as
	 * `conformance/quests/hydration-cases.json` records it.
	 * args: `{ content: string, status?: string }`
	 * result: `{ quest: <projection> }`
	 *
	 * COMPARISON SURFACE, not an adopted one: `gdextension/src/quest_system.cpp`
	 * is the hand-port that ships, and US-3 diffs the two over the same vectors
	 * to decide whether the port can eventually retire. See §10.
	 */
	'quest.hydrate': (args) => ({
		quest: computeHydrationExpected({
			content: args.content,
			...(args.status ? { status: args.status } : {}),
		}),
	}),

	/**
	 * `quest.radiantTick` — core's deterministic radiant distributor.
	 * args: `{ quests: [{id, tags, status}], maxOffering: number, ticks: number }`
	 * result: `{ facts: [{predicate, args}] }` (an order-independent multiset)
	 */
	'quest.radiantTick': (args) => ({
		facts: radiantTick({
			quests: args.quests || [],
			maxOffering: args.maxOffering,
			ticks: args.ticks,
		}),
	}),

	// ── combat ────────────────────────────────────────────────────────────────
	//
	// `CombatResolver` decides everything: legality through `can_attack/2`, the
	// damage pipeline, the health and death transitions, the fact delta. What
	// crosses this row is a request in (with the host's line-of-fire reading, if
	// it took one) and orders out (`ICombatSystem.applyDamage`, with the number
	// core computed). A host that answered `clear: true` to every shot still
	// cannot change one number of the outcome.

	/**
	 * args: `{ kb?, seed, tuning?, actions?: CombatAction[], combatants?: [],
	 *          stamina?: <stamina session> }`
	 * result: `{ session, orders }` — registration is already an order
	 * (`ICombatSystem.registerEntity`), so the host drains it like any other.
	 */
	'combat.create': async (args) => {
		const engine = await sessionEngine(args, createPrologEngine);
		const s = beginCall(newSession('combat', engine), args);
		const layer = new CombatResolver({
			engine,
			seed: args.seed ?? 0,
			...(args.tuning ? { tuning: args.tuning } : {}),
			...(args.actions ? { actions: new CombatActionTable(args.actions) } : {}),
			stamina: staminaOf(args),
			combat: combatSystemShim(s),
			host: adapterFor(s),
		});
		return created(s, layer, async () => {
			for (const combatant of args.combatants ?? []) layer.register(combatant);
			if (engine && args.actions) await layer.publishActionTable();
		});
	},

	'combat.attack': async (args) => {
		const s = beginCall(session(args, 'combat'), args);
		return endCall(
			s,
			await s.layer.attack({
				attackerId: args.attackerId,
				targetId: args.targetId,
				action: args.action,
				...(args.separation === undefined ? {} : { separation: args.separation }),
				tick: args.tick ?? 0,
			}),
		);
	},

	'combat.defend': async (args) => {
		const s = beginCall(session(args, 'combat'), args);
		return endCall(
			s,
			await s.layer.defend({
				actorId: args.actorId,
				action: args.action,
				tick: args.tick ?? 0,
				...(args.legality ? { legality: args.legality } : {}),
			}),
		);
	},

	/**
	 * The host owns the clock, so the host is what closes an evasion window —
	 * core hands the authored duration over and never counts it down.
	 */
	'combat.endDefense': async (args) => {
		const s = beginCall(session(args, 'combat'), args);
		return endCall(s, await s.layer.endDefense(args.actorId));
	},

	'combat.state': (args) => {
		const s = session(args, 'combat');
		return { state: s.layer.serialize(), roster: s.layer.roster() };
	},

	// ── stamina ───────────────────────────────────────────────────────────────

	'stamina.create': async (args) => {
		const engine = await sessionEngine(args, createPrologEngine);
		const s = beginCall(newSession('stamina', engine), args);
		const layer = new StaminaPool({
			engine,
			...(args.tuning ? { tuning: args.tuning } : {}),
			...(args.costs ? { costs: args.costs } : {}),
			// `ISurvivalSystem` takes no actor argument — it is the host's own meter
			// for the entity the host owns — so core forwards only this actor's
			// spends. Absent means none reach the host, which core documents.
			...(args.survivalActorId ? { survivalActorId: args.survivalActorId } : {}),
			...(args.state ? { state: args.state } : {}),
			survival: survivalShim(s),
		});
		return created(s, layer, async () => {
			for (const actor of args.actors ?? []) layer.register(actor);
			if (engine && args.publishTuning) await layer.publishTuning();
		});
	},

	'stamina.spend': async (args) => {
		const s = beginCall(session(args, 'stamina'), args);
		return endCall(
			s,
			await s.layer.spend(args.actorId, {
				action: args.action,
				...(args.cost === undefined ? {} : { cost: args.cost }),
			}),
		);
	},

	'stamina.rest': async (args) => {
		const s = beginCall(session(args, 'stamina'), args);
		return endCall(
			s,
			await s.layer.rest(args.actorId, {
				ticks: args.ticks ?? 1,
				...(args.inCombat === undefined ? {} : { inCombat: args.inCombat }),
				...(args.encumbered === undefined ? {} : { encumbered: args.encumbered }),
			}),
		);
	},

	'stamina.state': (args) => {
		const s = session(args, 'stamina');
		return { state: s.layer.serialize(), roster: s.layer.roster() };
	},

	// ── perception ────────────────────────────────────────────────────────────
	//
	// The one module whose inbound half core already supports directly:
	// `DetectionTracker.observe({readings})` takes the host's measurements, which
	// is how the corpus and a headless world drive it. `IPerceptionProbe` is the
	// same data one pair at a time, and the shim serves any pair the host left
	// out. Nothing about what a reading is WORTH crosses either way.

	'perception.create': async (args) => {
		const engine = await sessionEngine(args, createPrologEngine);
		const s = beginCall(newSession('perception', engine), args);
		const layer = new DetectionTracker({
			engine,
			seed: args.seed ?? 0,
			// A CURIE, and required: belief is stamped at a world derived from it,
			// so core cannot invent one. The host passes the playthrough it is in.
			playthrough: args.playthrough,
			...(args.namespace ? { namespace: args.namespace } : {}),
			...(args.tuning ? { tuning: args.tuning } : {}),
			...(args.actions ? { actions: args.actions } : {}),
			host: adapterFor(s),
		});
		return created(s, layer, async () => {
			for (const observer of args.observers ?? []) layer.registerObserver(observer);
			for (const target of args.targets ?? []) layer.registerTarget(target);
			if (engine && args.actions) await layer.publishActions();
		});
	},

	'perception.observe': async (args) => {
		const s = beginCall(session(args, 'perception'), args);
		return endCall(
			s,
			await s.layer.observe({
				tick: args.tick ?? 0,
				...(args.readings ? { readings: args.readings } : {}),
			}),
		);
	},

	'perception.state': (args) => {
		const s = session(args, 'perception');
		return { state: s.layer.serialize() };
	},

	// ── traversal ─────────────────────────────────────────────────────────────
	//
	// Two interfaces running opposite ways, which is the shape combat has:
	// `ITraversalProbe` is ASKED whether the actor could get across from where
	// they are standing (the host measured it before the call), `ILocomotionHost`
	// is TOLD to carry out a movement core has afforded, permitted and charged
	// for. The path, the speed and the animation are on the host's side of this
	// row and nothing about them appears in it.

	'traversal.create': async (args) => {
		const engine = await sessionEngine(args, createPrologEngine);
		const s = beginCall(newSession('traversal', engine), args);
		const layer = new TraversalPlanner({
			engine,
			...(args.links ? { links: args.links } : {}),
			...(args.tuning ? { tuning: args.tuning } : {}),
			stamina: staminaOf(args),
			host: adapterFor(s),
			...(args.state ? { state: args.state } : {}),
		});
		return created(s, layer, async () => {
			for (const actor of args.actors ?? []) await layer.register(actor);
			if (engine && args.links) await layer.publishGraph();
		});
	},

	'traversal.traverse': async (args) => {
		const s = beginCall(session(args, 'traversal'), args);
		return endCall(
			s,
			await s.layer.traverse(args.actorId, args.to, args.intent ?? undefined),
		);
	},

	'traversal.affordances': async (args) => {
		const s = beginCall(session(args, 'traversal'), args);
		return endCall(s, { affordances: await s.layer.affordances(args.actorId) });
	},

	'traversal.state': (args) => {
		const s = session(args, 'traversal');
		return { state: s.layer.serialize() };
	},

	// ── skill ─────────────────────────────────────────────────────────────────
	//
	// Drawing a tree is NOT an interface — it is the value `buildSkillView`
	// returns — so the only thing that leaves through a host hook here is a
	// `modifies(Param, Amount)` effect whose parameter names a quantity only the
	// engine holds. Absolute totals, once per change to an actor's taken nodes.

	'skill.create': async (args) => {
		const engine = await sessionEngine(args, createPrologEngine);
		const s = beginCall(newSession('skill', engine), args);
		const layer = new SkillProgression({
			engine,
			...(args.skills ? { skills: args.skills } : {}),
			...(args.trees ? { trees: args.trees } : {}),
			...(args.tuning ? { tuning: args.tuning } : {}),
			...(args.state ? { state: args.state } : {}),
			skillModifiers: skillModifierSinkShim(s),
		});
		return created(s, layer, async () => {
			if (engine && (args.skills || args.trees)) await layer.publishWorld();
			for (const actor of args.actors ?? []) await layer.register(actor);
		});
	},

	'skill.award': async (args) => {
		const s = beginCall(session(args, 'skill'), args);
		return endCall(s, await s.layer.award(args.actorId, args.skill, args.amount ?? 0));
	},

	'skill.unlock': async (args) => {
		const s = beginCall(session(args, 'skill'), args);
		return endCall(s, await s.layer.unlock(args.actorId, args.node));
	},

	'skill.state': (args) => {
		const s = session(args, 'skill');
		return { state: s.layer.serialize() };
	},

	// ── equipment ─────────────────────────────────────────────────────────────
	//
	// The only interface that runs both ways, and therefore the cheapest place to
	// see the inversion whole: `getBaseStats` is a reading the host gathered
	// before the call, `applyStats` is an order it drains after.

	'equipment.create': (args) => {
		// No KB: `EquipmentManager` reads no rules and writes no facts. It is the
		// one adopted layer that needs no engine, which is why this row is `async`
		// in neither direction.
		const s = beginCall(newSession('equipment', undefined), args);
		const layer = new EquipmentManager({
			...(args.entityId ? { entityId: args.entityId } : {}),
			...(args.state ? { state: args.state } : {}),
			combatStats: combatStatSinkShim(s),
		});
		return created(s, layer);
	},

	'equipment.equip': (args) => {
		const s = beginCall(session(args, 'equipment'), args);
		return endCall(s, s.layer.equip(args.item));
	},

	'equipment.unequip': (args) => {
		const s = beginCall(session(args, 'equipment'), args);
		return endCall(s, s.layer.unequip(args.slot));
	},

	'equipment.state': (args) => {
		const s = session(args, 'equipment');
		return { state: s.layer.getState(), bonuses: s.layer.getBonuses() };
	},

	// ── routine ───────────────────────────────────────────────────────────────
	//
	// `RoutineDirector` writes one `agent_goal/3` and stops; walking to the forge
	// because your day says so leaves through `ILocomotionHost` like any other
	// movement, which is why this module names no interface of its own.

	'routine.create': async (args) => {
		const engine = await sessionEngine(args, createPrologEngine);
		const s = beginCall(newSession('routine', engine), args);
		const layer = new RoutineDirector({
			engine,
			...(args.routines ? { routines: args.routines } : {}),
			...(args.tuning ? { tuning: args.tuning } : {}),
		});
		return created(s, layer, async () => {
			if (engine && args.routines) await layer.publishRoutines();
			for (const assignment of args.assign ?? []) {
				await layer.assign(assignment.agent, assignment.routine ?? null);
			}
		}).then((result) => ({ ...result, issues: layer.issues() }));
	},

	'routine.tick': async (args) => {
		const s = beginCall(session(args, 'routine'), args);
		return endCall(
			s,
			await s.layer.tick(args.clock ?? { day: 1, hour: 0 }, args.agents ?? []),
		);
	},

	'routine.state': (args) => {
		const s = session(args, 'routine');
		return { state: s.layer.serialize(), roster: s.layer.roster() };
	},

	// ── sessions ──────────────────────────────────────────────────────────────

	/**
	 * `mechanic.dispose` — release a session and the KB it owns.
	 *
	 * ONE row rather than the seven `<module>.dispose` rows Unity's proposal
	 * sketched (its §12.3), because a handle already names its module: the
	 * session table is what makes `combat.dispose` and `skill.dispose` the same
	 * function with a redundant argument. The deviation is deliberate and
	 * recorded in RUNTIME_CORE_ADOPTION.md §12.
	 */
	'mechanic.dispose': (args) => ({ disposed: closeSession(args.session) }),

	/** Every open session — a leak in a game shows up here as growth. */
	'mechanic.sessions': () => ({ sessions: openSessions() }),

	/**
	 * `mechanic.modules` — which modules this build can reach, by name, with the
	 * rows and host interfaces each one uses. Asking the BINARY is the only
	 * honest way to know what it can do; a version stamp is not (Unity §12.6
	 * item 2). The gate diffs this against core's own module manifest.
	 */
	'mechanic.modules': () => ({
		modules: MECHANIC_MODULES,
		hostInterfaces: HOST_INTERFACES,
	}),

	// ── module activation (tasklist 147, US-3) ────────────────────────────────
	//
	// A genre bundle names its modules; a module names its pack, its decision
	// layers and its host interfaces. All of it is DATA in core
	// (`src/modules/module-activation.ts`), which is what lets this plugin
	// activate what a world selected WITHOUT a list of mechanics in its own
	// source: adding a module to a bundle in core changes the answer these rows
	// give, and no GDScript changes. `addons/insimul/runtime/mechanics/
	// insimul_module_activation.gd` is the reader.

	/**
	 * `modules.activate` — what this world activates.
	 *
	 * args: `{ ir }` a World IR (the genre rides in `meta.genreConfig.id`, which
	 *       is all a plugin has to carry across the ABI), or `{ genre }` for a
	 *       host that already knows the id, or NEITHER.
	 *
	 * The three answers are core's three and they are kept apart, because
	 * conflating any two of them is a bug with a different consequence each
	 * (`GamePrologEngineConfig.genre`, and `resolveActiveModules`'s header):
	 *
	 *   known genre    -> exactly what the bundle selects.
	 *   unknown genre  -> `known: false`, no modules, the always-active packs.
	 *                     A genre core has never heard of must NOT silently
	 *                     inherit every mechanic in the build.
	 *   nothing said   -> every pack in the build. Right for a tool, an editor
	 *                     session or a test; a warning in a game, which is why
	 *                     `source` is reported rather than inferred.
	 *
	 * result: `{ source, active, predicatePacks, hostInterfaces, reason }`.
	 * `active` is core's `ActiveModuleSet` VERBATIM — the same object the
	 * committed `conformance/modules/genre-activation.json` holds, so the gate
	 * can deep-compare the two — and is `null` when no genre was declared.
	 * `predicatePacks` and `hostInterfaces` are lifted to the top level so a
	 * caller reads the same two fields whichever answer it got.
	 */
	'modules.activate': (args) => {
		if (args.ir !== undefined && args.ir !== null) {
			const id = args.ir?.meta?.genreConfig?.id;
			// A World IR with no genreConfig is NOT an unknown genre: nothing was
			// declared. Core's `activeModulesForWorld` would raise on the missing
			// field rather than resolve, so the adapter answers here — see
			// RUNTIME_CORE_ADOPTION.md §13.2, which is where it is written up.
			if (typeof id !== 'string') {
				return undeclared('the World IR carries no meta.genreConfig.id');
			}
			return activated('worldIr', activeModulesForWorld(args.ir));
		}
		if (typeof args.genre === 'string') return activated('genre', resolveActiveModules(args.genre));
		return undeclared('no genre and no World IR was passed');
	},

	/**
	 * `modules.table` — the WHOLE activation table, byte-for-byte the contents of
	 * core's `conformance/modules/genre-activation.json`.
	 *
	 * Emitted by core's own `moduleActivationTable()`, which is the function
	 * `scripts/emit-module-activation.ts` writes that file with. So the corpus
	 * this repo vendors and the answer this build gives have ONE definition
	 * between them, and `run_activation_tests.sh` compares them.
	 */
	'modules.table': () => moduleActivationTable(),

	/**
	 * `prolog.packs` — the rule-pack TEXT for a set of areas, in consult order.
	 *
	 * The activation table says WHICH packs a world consults and no row returned
	 * their source, so a native adapter had the list and nowhere to get the text
	 * (Unity hit this and vendored the eleven packs as game data; this bundle
	 * already carries them, so a row is enough). RUNTIME_CORE_ADOPTION.md §13.1.
	 *
	 * `order` is `PREDICATE_PACK_AREAS` and the returned packs are in it, which
	 * is a HARD constraint rather than tidiness: the routine and map packs add
	 * clauses for predicates the substrate pack declares `:- dynamic`, and a
	 * `:- dynamic` arriving after a clause is a permission_error on a strict ISO
	 * engine — which is the engine this plugin links.
	 *
	 * args: `{ areas?: string[] }`; absent means every pack in the build.
	 * result: `{ packs: [{ area, prolog, runtimePredicates }], order, unknown }`.
	 */
	'prolog.packs': (args) => {
		const wanted = Array.isArray(args.areas) ? new Set(args.areas.map(String)) : null;
		return {
			packs: PREDICATE_PACKS.filter((pack) => wanted === null || wanted.has(pack.area)).map(
				(pack) => ({
					area: pack.area,
					prolog: pack.prolog,
					runtimePredicates: [...pack.runtimePredicates],
				}),
			),
			order: [...PREDICATE_PACK_AREAS],
			unknown: wanted === null ? [] : [...wanted].filter((a) => !PREDICATE_PACK_AREAS.includes(a)),
		};
	},

	// ── conformance (tasklist 147, US-2) ──────────────────────────────────────
	//
	// A vendored corpus nothing runs is a checked-in file. These three rows are
	// what run it — in THIS engine, through the same bundle a game loads, on the
	// same native Trealla the mechanic sessions use.

	/**
	 * `prolog.run` — consult a corpus case's KB and run its query.
	 *
	 * The protocol is core's own `prolog-corpus.test.ts` verbatim: join the `kb`
	 * lines with newlines, consult, query with core's 1000-solution default, and
	 * hand back the binding sets. A fresh engine per case and an unconditional
	 * `destroy()`, for the same reason core's runner gives — one live KB per case
	 * exhausts the table partway through a 255-case corpus.
	 *
	 * A consult or query FAILURE is returned, not thrown: the harness needs to
	 * tell "this engine disagreed" from "this engine could not run it", and the
	 * one documented amendment (`assert-retract.json::asserta-prepends`) is
	 * applied only on the second kind. Throwing would collapse the two.
	 */
	'prolog.run': async (args) => {
		const program = Array.isArray(args.kb) ? args.kb.join('\n') : String(args.kb ?? '');
		const engine = await createPrologEngine();
		try {
			const consulted = await engine.consult(program);
			if (!consulted.success) {
				return { ok: false, stage: 'consult', error: consulted.error ?? 'consult failed', solutions: [] };
			}
			const result = await engine.query(String(args.query ?? ''), args.maxResults ?? 1000);
			if (!result.success) {
				return { ok: false, stage: 'query', error: result.error ?? 'query failed', solutions: [] };
			}
			return { ok: true, solutions: result.bindings };
		} finally {
			engine.destroy();
		}
	},

	/**
	 * `conformance.run` — run one DECISION-corpus case and return the whole
	 * `expected` shape, so the harness compares rather than interprets.
	 */
	'conformance.run': async (args) => ({
		result: await runCorpusCase(String(args.area ?? ''), args.case ?? {}),
	}),

	/**
	 * `conformance.areas` — which decision corpora this build can execute, and
	 * which module owns each. Asking the binary, again: a corpus vendored into
	 * `conformance/` with no runner behind it is exactly the failure this whole
	 * story exists to close, and it is only visible by comparing these two lists.
	 */
	'conformance.areas': () => ({
		areas: Object.keys(CORPUS_AREAS).sort(),
		byModule: CORPUS_AREAS_BY_MODULE,
	}),

	/** `core.methods` — introspection; lets a gate assert the adopted surface. */
	'core.methods': () => ({ methods: Object.keys(METHODS).sort() }),
};

globalThis.__insimul_core_dispatch = function (method, argsJson) {
	const fn = METHODS[method];
	if (!fn) {
		return Promise.reject(new Error(`insimulcore: unknown method "${method}"`));
	}
	// `Promise.resolve().then(...)` so a synchronous throw inside `fn` becomes a
	// rejection the host reports through last_error(), never a C-level exception.
	return Promise.resolve().then(() => fn(argsJson ? JSON.parse(argsJson) : {}));
};

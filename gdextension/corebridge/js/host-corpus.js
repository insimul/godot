// host-corpus.js — the ADAPTER's runners for core's DECISION corpora
// (tasklist 147, US-2).
//
// WHY THIS FILE EXISTS. `conformance/` is vendored from core, and a vendored
// corpus that nothing executes is a checked-in file — this repository has
// shipped exactly that failure before (tasklist 100 found the Prolog corpus at
// 41 of core's 76 cases, drifted, with a gate that could not fail). US-1 landed
// seven decision layers behind bridge rows and proved they are REACHABLE;
// what proves they are RIGHT is running core's own golden vectors through them
// in this engine and comparing to the pinned output.
//
// Two corpora shapes, two runners, and they answer different questions:
//
//   - `conformance/prolog/mechanic-*.json` pins the VOCABULARY — what
//     `can_attack/2` answers for a given world. That runs through `prolog.run`
//     in entry.js, on the native Trealla, and needs nothing from this file.
//   - `conformance/{combat,stealth,traversal,skills,items,routines}/` pins the
//     DECISION — the damage number, the suspicion rung, the route, the price.
//     No rule computes those, so no Prolog corpus can pin them. They run
//     through this file.
//
// ── WHAT THIS FILE IS ALLOWED TO CONTAIN ────────────────────────────────────
//
// Nothing that decides anything. Every function below is a MIRROR of the
// corresponding helper in core's own corpus runner
// (`packages/core/src/conformance/__tests__/<area>-corpus.test.ts`), which is
// test-harness composition — "call these core functions in this order and put
// their answers in a record with these keys" — and never a rule, a formula or a
// tie-break. Those all stay in the imported core functions, which is what keeps
// UNIFICATION_ROADMAP decision 1 intact: the corpus is executed by BINDING
// core, not by a second implementation that happens to agree with it.
//
// The one place that rule is visibly strained is `wornFrom` below, which sorts
// a paper doll. It is copied verbatim from core's items runner and its ordering
// is the corpus's own subject, so a divergence in it FAILS the corpus rather
// than hiding inside it. It is flagged here so a reader does not have to notice.
//
// ── WHY THE CASE ARRIVES WHOLE ──────────────────────────────────────────────
//
// Every corpus case carries its entire input — both combatants, the whole
// tuning, the authored rows, the seed and the tick — precisely so that "a
// harness in any language reproduces it with no defaults table, no world file
// and no KB" (core's own words, in every one of those files' `description`).
// So the bridge row takes the case object verbatim and returns the whole
// `expected` shape; the C++ harness does not know what a combat action is, and
// must not have to.

import { CombatActionTable, combatActionFacts } from '@insimul/core/combat/action-table';
import {
	defenseFacts,
	resolutionFacts,
	threatAfterDamage,
} from '@insimul/core/combat/combat-facts';
import { resolveAttack, resolveDefense } from '@insimul/core/combat/resolution';

import { runDetection } from '@insimul/core/perception/detection';
import { detectionPassFacts } from '@insimul/core/perception/detection-facts';
import {
	StealthActionTable,
	stealthActEffects,
	stealthActFor,
	stealthActionFacts,
} from '@insimul/core/perception/stealth-actions';

import {
	bestAffordance,
	findRoute,
	resolveAffordances,
} from '@insimul/core/traversal/traversal';
import { traversalGraphFacts } from '@insimul/core/traversal/traversal-facts';
import { planFastTravel } from '@insimul/core/traversal/fast-travel';
import { discoveryDelta, fastTravelArrivalDelta } from '@insimul/core/traversal/fast-travel-facts';
import {
	applyVehicleVerb,
	isAnothersVehicle,
	resolveVehicleVerb,
	vehicleActions,
	vehicleSeats,
} from '@insimul/core/traversal/vehicles';
import {
	vehicleModeFact,
	vehicleStateDelta,
	vehicleStateFacts,
} from '@insimul/core/traversal/vehicle-facts';

import {
	maxLevelOf,
	nodeCost,
	nodeDepth,
	nodeRequirements,
	resolveAdvance,
	resolveUnlock,
	treesFundedBy,
	xpForLevel,
} from '@insimul/core/skills/skills';
import {
	modifierOf,
	permittedThings,
	skillModifiers,
	unlockedActions,
	withSkillModifiers,
} from '@insimul/core/skills/skill-effects';
import { buildSkillView } from '@insimul/core/skills/skill-view';

import {
	armorValue,
	carriedWeight,
	encumbered,
	findSlot,
	resolveEquip,
	sortStacks,
	unmetRequirements,
} from '@insimul/core/items/items';
import { equipmentModifierTotals } from '@insimul/core/items/item-effects';
import { placeFacts } from '@insimul/core/items/item-facts';
import { resolvePrice, resolveTransaction } from '@insimul/core/items/economy';
import {
	generateLoot,
	isContainerPlacement,
	itemPlacementsFromIR,
	lootTablesFromIR,
	placeOf,
	placementTuningFromIR,
} from '@insimul/core/items/placement';

import {
	activeBlock,
	dueBlocks,
	resolveRoutine,
	routineIssues,
	weekdayOf,
} from '@insimul/core/routines/routines';
import { adoptedGoalDelta, routineGraphFacts } from '@insimul/core/routines/routine-facts';
import {
	inPlace,
	movementIntent,
	shouldReplan,
	urgencyFor,
} from '@insimul/core/routines/movement';
import { animationIntentFor, isAnimationIntent } from '@insimul/core/routines/animation';
import { RoutineDirector } from '@insimul/core/game-engine/logic/RoutineDirector';
import {
	RecordingKb,
	RecordingPlans,
} from '@insimul/core/conformance/__tests__/headless-routine-host';

// ── combat ──────────────────────────────────────────────────────────────────

/** Mirrors `factsFor` in core's combat runner — `CombatResolver.applyResolution`. */
function combatFactsFor(c, resolved) {
	if (resolved.damage <= 0) return resolutionFacts(resolved);
	const threat = threatAfterDamage(resolved.damage, resolved.targetMaxHealth, c.threatBefore ?? 0);
	return resolutionFacts(resolved, { threat, priorThreat: c.threatBefore });
}

function runCombatResolution(c) {
	if (c.kind === 'defense') {
		const resolved = resolveDefense(c.input);
		return { resolution: resolved, facts: defenseFacts(resolved) };
	}
	const resolved = resolveAttack(c.input);
	const out = { resolution: resolved, facts: combatFactsFor(c, resolved) };
	// `threat` is pinned only where the case pins it; emitting it unconditionally
	// would fail every case that does not, and inventing it would be a decision.
	if (c.expected && c.expected.threat !== undefined) {
		out.threat = threatAfterDamage(resolved.damage, resolved.targetMaxHealth, c.threatBefore ?? 0);
	}
	return out;
}

function runCombatActionTable(c) {
	const table = new CombatActionTable();
	const loaded = table.loadFromIR(c.actions, c.combat);
	const rows = table.all();
	return {
		loaded,
		rows,
		facts: rows.flatMap((row) => combatActionFacts(row)),
		projectiles: table.projectileActions().map((row) => row.id),
		defensive: table.defensiveActions().map((row) => row.id),
	};
}

// ── perception / stealth ────────────────────────────────────────────────────

/** Core's runner pins the percept against ONE fixed act context; so does this. */
const ACT_CONTEXT = {
	event: 'evt:act:1',
	actor: { kind: 'ent', namespace: 'insimul:world:alderforest', localId: 'npc-thief' },
	object: { kind: 'ent', namespace: 'insimul:world:alderforest', localId: 'npc-guard' },
	coarseActor: { kind: 'ent', namespace: 'insimul:world:alderforest', localId: 'someone' },
};

function runStealthDetection(c) {
	const result = runDetection(c.input);
	return {
		updates: result.updates,
		memory: result.memory,
		facts: detectionPassFacts(result.updates),
		perceptions: result.perception.perceptions,
		beliefFacts: result.perception.beliefFacts,
		perceptFacts: result.perception.perceptFacts,
		perceivedFacts: result.perception.perceivedFacts,
	};
}

function runStealthActions(c) {
	const table = new StealthActionTable();
	const loaded = table.loadFromIR(c.actions, c.columns);
	const rows = table.all();
	return {
		loaded,
		rows,
		facts: rows.flatMap((row) => stealthActionFacts(row)),
		effects: rows.map((row) => ({ id: row.id, effects: stealthActEffects(row) })),
		percepts: rows.map((row) => ({ id: row.id, percept: stealthActFor(row, ACT_CONTEXT) ?? null })),
	};
}

// ── traversal ───────────────────────────────────────────────────────────────

function runTraversalAffordances(c) {
	const input = c.input;
	const resolved = resolveAffordances(input);
	return {
		affordances: resolved,
		best: c.best === null ? null : (bestAffordance(resolved, c.best) ?? null),
		route: c.route === null ? null : (findRoute({ ...input, ...c.route }) ?? null),
		graphFacts: traversalGraphFacts(input.links, input.tuning),
	};
}

function runTraversalFastTravel(c) {
	const input = c.input;
	const route = findRoute({
		actor: input.actor,
		from: input.from,
		to: input.to,
		links: input.links,
		modes: input.modes,
		blocked: input.blocked,
		tuning: input.graphTuning,
	});
	const plan =
		route === undefined
			? null
			: planFastTravel({
					seed: input.seed,
					actor: input.actor,
					from: input.from,
					to: input.to,
					journey: input.journey,
					route,
					tuning: input.tuning,
				});
	return {
		route: route ?? null,
		plan,
		arrival: plan === null ? null : fastTravelArrivalDelta(input.actor, input.from, input.to),
		discovery: plan === null ? null : discoveryDelta(input.to, false),
		discoveryWhenAlreadyKnown: plan === null ? null : discoveryDelta(input.to, true),
	};
}

function runTraversalVehicles(c) {
	const resolution = resolveVehicleVerb({
		vehicle: c.vehicle,
		state: c.state,
		actor: c.actor,
		at: c.at,
		verb: c.verb,
	});
	const next = applyVehicleVerb(c.state, c.actor, c.verb, resolution);
	return {
		resolution,
		next,
		actions: vehicleActions(c.vehicle),
		seats: vehicleSeats(c.vehicle),
		modeFact: vehicleModeFact(c.vehicle),
		stateFacts: vehicleStateFacts(c.state),
		delta: next === null ? { retract: [], assert: [] } : vehicleStateDelta(c.state, next),
		anothers: isAnothersVehicle(c.state, c.actor),
	};
}

// ── skills ──────────────────────────────────────────────────────────────────

function runSkillAdvance(c) {
	const input = c.input;
	const skill = input.skill ?? undefined;
	const max = maxLevelOf(skill, input.tuning);
	const curve = [];
	for (let level = 0; level <= max + 1; level += 1) curve.push(xpForLevel(skill, level, input.tuning));
	return { resolution: resolveAdvance({ ...input, skill }), curve, maxLevel: max };
}

function runSkillUnlock(c) {
	const input = c.input;
	const node = input.node ?? undefined;
	return {
		resolution: resolveUnlock({ ...input, node }),
		requirements: node ? [...nodeRequirements(node)] : [],
		cost: node ? nodeCost(node, input.tuning) : 0,
	};
}

function runSkillEffects(c) {
	const input = c.input;
	const modifiers = {};
	for (const [param, amount] of skillModifiers(input.effects)) modifiers[param] = amount;
	return {
		modifiers,
		unlocks: unlockedActions(input.effects),
		permits: permittedThings(input.effects),
		modified: withSkillModifiers(input.snapshot, input.effects),
		modifierOf: modifierOf(input.effects, input.parameter),
	};
}

function runSkillTrees(c) {
	const input = c.input;
	const depths = {};
	for (const tree of input.trees) for (const n of tree.nodes) depths[n.id] = nodeDepth(tree, n.id);
	return {
		view: buildSkillView(input),
		funded: treesFundedBy(input.trees, input.trees[0]?.skill ?? ''),
		depths,
	};
}

// ── items / equipment ───────────────────────────────────────────────────────

/**
 * The paper doll's row order. Copied verbatim from core's items runner (see the
 * file header: this is the one mirrored helper with real ordering in it, and
 * the ordering is what the corpus is pinning, so a divergence here fails a case
 * rather than hiding in one).
 */
function wornFrom(input) {
	const declared = [...input.slots]
		.sort((a, b) => a.order - b.order || a.id.localeCompare(b.id))
		.map((slot) => slot.id);
	const order = (slot) => {
		const index = declared.indexOf(slot);
		return index === -1 ? declared.length : index;
	};
	return input.stacks
		.filter((stack) => stack.place.kind === 'equipped' && stack.place.holder === input.actor)
		.slice()
		.sort(
			(a, b) =>
				order(a.place.slot ?? '') - order(b.place.slot ?? '') ||
				(a.place.slot ?? '').localeCompare(b.place.slot ?? '') ||
				a.item.localeCompare(b.item),
		)
		.map((stack) => stack.item);
}

function runItemsEquipping(c) {
	const input = c.input;
	const item = input.item ?? undefined;
	const definitions = new Map(input.catalogue.map((row) => [row.id, row]));
	const worn = wornFrom(input);
	const mine = input.stacks.filter(
		(stack) =>
			(stack.place.kind === 'inventory' || stack.place.kind === 'equipped') &&
			stack.place.holder === input.actor,
	);
	const weight = carriedWeight(mine, definitions);
	return {
		resolution: resolveEquip({
			actor: input.actor,
			item,
			itemId: input.itemId,
			slot: item?.equipSlot ? findSlot(input.slots, item.equipSlot) : undefined,
			occupied: input.occupied,
			held: input.held,
			equipped: input.equipped,
			levels: input.levels,
			tuning: input.tuning,
		}),
		unmet: item ? unmetRequirements(item, input.levels) : [],
		facts: sortStacks(input.stacks).flatMap((stack) =>
			placeFacts(stack.place, stack.item, stack.quantity),
		),
		worn,
		weight,
		encumbered: encumbered(weight, input.tuning.carryCapacity),
		armor: armorValue(worn, definitions),
		modifiers: equipmentModifierTotals(
			worn.map((id) => definitions.get(id)).filter((row) => !!row),
		),
	};
}

function runItemsPricing(c) {
	const input = c.input;
	return {
		price: resolvePrice({
			actor: input.actor,
			item: input.item ?? undefined,
			itemId: input.itemId,
			direction: input.direction,
			quantity: input.quantity,
			market: input.market ?? undefined,
			tuning: input.tuning,
		}),
	};
}

function runItemsTransactions(c) {
	const input = c.input;
	return {
		resolution: resolveTransaction({
			actor: input.actor,
			item: input.item ?? undefined,
			itemId: input.itemId,
			direction: input.direction,
			quantity: input.quantity,
			market: input.market ?? undefined,
			vendorId: input.vendorId,
			supply: input.supply,
			actorGold: input.actorGold,
			vendorGold: input.vendorGold,
			tuning: input.tuning,
		}),
	};
}

function runItemsPlacement(c) {
	const input = c.input;
	const tuning = placementTuningFromIR(input.ir);
	const placements = itemPlacementsFromIR(input.ir);
	const tables = lootTablesFromIR(input.lootTables);
	const places = {};
	const loot = {};
	for (const row of placements) {
		places[row.id] = placeOf(row);
		if (!isContainerPlacement(row)) continue;
		const named = row.declares?.lootTable;
		loot[row.id] = generateLoot({
			seed: input.seed,
			container: row.id,
			cycle: input.cycle,
			table: named ? tables.get(named) : undefined,
			catalogue: input.catalogue,
			draws: row.declares?.draws,
			tuning,
		});
	}
	return {
		tuning,
		placements,
		places,
		containers: placements.filter(isContainerPlacement).map((row) => row.id),
		loot,
	};
}

// ── routines ────────────────────────────────────────────────────────────────

function runRoutineGoals(c) {
	const { tuning, clock, agent } = c.input;
	const authored = c.input.routines.routines?.find((r) => r.id === c.input.routine);
	if (authored === undefined) throw new Error(`${c.name} names a routine it did not author`);
	const routine = resolveRoutine(authored, tuning);
	const active = activeBlock(routine, clock, tuning);
	return {
		resolved: routine,
		weekday: weekdayOf(clock, tuning),
		due: dueBlocks(routine, clock, tuning).map((block) => block.id),
		active: active?.id ?? null,
		goal: active?.goal ?? null,
		priority: active?.priority ?? null,
		destination: active?.place ?? null,
		graphFacts: routineGraphFacts([routine], tuning),
		issues: routineIssues([routine], tuning),
		delta: adoptedGoalDelta(
			agent,
			null,
			active === null ? null : { goal: active.goal, priority: active.priority },
		),
	};
}

/**
 * The one corpus that is a SCRIPT rather than a call: a director is assigned,
 * ticked, preempted and resumed, and what is pinned is the whole run. It uses
 * core's own `RecordingKb`/`RecordingPlans` headless host — imported, not
 * reimplemented, which is the whole point.
 */
async function runRoutineInterruption(c) {
	const input = c.input;
	const kb = new RecordingKb();
	const plans = new RecordingPlans();
	const director = new RoutineDirector({ routines: input.routines, engine: kb.asEngine(), plans });

	const steps = [];
	for (const step of input.steps) {
		const mark = kb.mark();
		const before = plans.interrupts.length;
		let outcomes;
		switch (step.do) {
			case 'assign':
				await director.assign(step.agent, step.routine);
				break;
			case 'tick':
				outcomes = [...(await director.tick(step.clock, input.roster)).outcomes];
				break;
			case 'preempt':
				await director.preempt(step.agent, step.reason, step.block);
				break;
			case 'resume':
				await director.resume(step.agent);
				break;
			case 'forget':
				await director.forget(step.agent);
				break;
		}
		steps.push({
			...(outcomes === undefined ? {} : { outcomes }),
			delta: kb.since(mark),
			interrupts: plans.interrupts.slice(before),
		});
	}
	return { steps, facts: kb.facts(), state: director.serialize() };
}

function runRoutineIntents(c) {
	const input = c.input;
	const authored = new Map(
		Object.entries(input.authored).flatMap(([action, intent]) =>
			isAnimationIntent(intent) ? [[action, intent]] : [],
		),
	);
	const intent = movementIntent({
		actor: input.actor,
		from: input.from,
		destination: input.destination,
		priority: input.priority,
		stance: input.stance,
		suspended: input.suspended,
		tuning: input.tuning,
	});
	return {
		intent,
		inPlace: inPlace(intent),
		urgency: urgencyFor(input.priority, input.tuning),
		replan: shouldReplan(input.failures, input.tuning),
		animation: animationIntentFor(input.action, authored),
	};
}

/**
 * The runners, keyed by the corpus file's own `area` string. The C++ harness
 * reads `area` out of the vendored file and asks for it by name — so a corpus
 * this repo vendored but never taught to run reports UNRUNNABLE rather than
 * being skipped, and `conformance.areas` below is what makes that checkable
 * without executing anything.
 *
 * Every module in `tools/verify-mechanics/MODULE_HOSTS.json` whose decision
 * layer this repo adopted has its areas here; `check-mechanics.mjs` holds that
 * to account.
 */
export const CORPUS_AREAS = {
	'combat-resolution': runCombatResolution,
	'combat-action-table': runCombatActionTable,
	'stealth-detection': runStealthDetection,
	'stealth-actions': runStealthActions,
	'traversal-affordances': runTraversalAffordances,
	'traversal-fast-travel': runTraversalFastTravel,
	'traversal-vehicles': runTraversalVehicles,
	'skills-advancement': runSkillAdvance,
	'skills-unlocks': runSkillUnlock,
	'skills-effects': runSkillEffects,
	'skills-trees': runSkillTrees,
	'items-equipping': runItemsEquipping,
	'items-pricing': runItemsPricing,
	'items-transactions': runItemsTransactions,
	'items-placement': runItemsPlacement,
	'routine-goals': runRoutineGoals,
	'routine-intents': runRoutineIntents,
	'routine-interruption': runRoutineInterruption,
};

/** Which module owns which corpus areas — the map `check-mechanics.mjs` diffs. */
export const CORPUS_AREAS_BY_MODULE = {
	combat: ['combat-resolution', 'combat-action-table'],
	perception: ['stealth-detection', 'stealth-actions'],
	traversal: ['traversal-affordances', 'traversal-fast-travel', 'traversal-vehicles'],
	skill: ['skills-advancement', 'skills-unlocks', 'skills-effects', 'skills-trees'],
	equipment: ['items-equipping', 'items-pricing', 'items-transactions', 'items-placement'],
	routine: ['routine-goals', 'routine-intents', 'routine-interruption'],
	// `stamina` has no decision corpus of its own: StaminaPool's arithmetic is
	// pinned inside conformance/combat/resolution.json (every attack case
	// carries the meter and pins `attackerStaminaAfter`) and its vocabulary in
	// conformance/prolog/mechanic-stamina.json. Recorded as an empty list rather
	// than omitted, so "no corpus" is a statement and not an oversight.
	stamina: [],
};

/** Run one case of one area. Throws with the area name when there is no runner. */
export async function runCorpusCase(area, testCase) {
	const runner = CORPUS_AREAS[area];
	if (!runner) {
		throw new Error(
			`insimulcore: no conformance runner for area "${area}" — ` +
				'add one in gdextension/corebridge/js/host-corpus.js, or the vendored corpus ' +
				'is a checked-in file nothing executes.',
		);
	}
	return await runner(testCase);
}

// host-mechanics.js — the ADAPTER's side of the band-120 mechanic modules
// (tasklist 147, US-1). Everything here is glue; not one decision is made in
// this file.
//
// ── WHY THIS FILE EXISTS ────────────────────────────────────────────────────
//
// Core's mechanic modules name eight host interfaces (`module-contract.ts`), and
// every one of them is a CALLBACK: an object the host implements and core calls.
// In-process that is a function reference on `EngineHostAdapter`. Across
// `insimul_core_call(method, argsJson) -> json` there is nowhere for a function
// to live — the C ABI has no callback entry points, deliberately (they are what
// makes a binding leak an engine's threading model into core).
//
// Unity's probe (tasklist 145, its RUNTIME_CORE_ADOPTION.md §12.2) named the
// shape that resolves it, and could not build it because `native/corebridge` is
// not in a Unity worktree. It IS in this one. So this is that shape:
//
//     READINGS IN, ORDERS OUT.
//
//   * Everything core would ASK the host (`ITrajectoryProbe.query`,
//     `IPerceptionProbe.sense`, `ITraversalProbe.query`,
//     `ICombatStatSink.getBaseStats`) is gathered by the engine BEFORE the call
//     and travels in as an argument. The shim below serves core's question from
//     what arrived; nothing blocks and nothing calls back out.
//   * Everything core would TELL the host (`ICombatSystem.applyDamage`,
//     `ISurvivalSystem.consumeStamina`, `ILocomotionHost.travel`,
//     `ISkillModifierSink.applyModifiers`, `ICombatStatSink.applyStats`) is
//     RECORDED as an order and returned in the result, for the engine to drain
//     and carry out. `orders` is that queue.
//
// The one interface this cannot make synchronous is `ILocomotionHost.travel`,
// which returns an `ArrivalReport` core reads immediately. The host pre-declares
// what an arrival means for this call (`arrival` in the args); the order still
// goes out, so the body still moves. See `arrivalFor()` for the default and why
// it is `arrived: true` rather than `false`.
//
// ── WHAT IS NOT HERE ────────────────────────────────────────────────────────
//
// No damage number, no suspicion curve, no traversal cost, no XP table, no
// price. Every one of those is core's, reached through the imports in entry.js.
// If a formula ever appears in this file, the adoption has forked
// (`docs/module-contract.md` §3, UNIFICATION_ROADMAP decision 1).

/** Sessions by handle. A handle names its module, so dispose needs no module. */
const SESSIONS = new Map();
let nextHandle = 1;

/**
 * The eight interfaces, and which direction each runs. The gate
 * (`tools/verify-mechanics/check-mechanics.mjs`) reads this to check the bridge
 * against core's manifest, so it is data rather than prose.
 */
export const HOST_INTERFACES = Object.freeze({
	ICombatSystem: 'told',
	ICombatStatSink: 'both',
	ITrajectoryProbe: 'asked',
	IPerceptionProbe: 'asked',
	ITraversalProbe: 'asked',
	ILocomotionHost: 'told',
	ISkillModifierSink: 'told',
	ISurvivalSystem: 'told',
	IAgentActionHost: 'told',
});

/**
 * One live decision layer, plus the queue of orders it produced during the call
 * that is running right now.
 *
 * Sessions exist because a decision layer is STATEFUL and a bridge call is not —
 * Unity §12.2 finding 2. `CombatResolver` holds a roster, accumulated `threat/3`
 * and a `PrologEngine`; `radiant.generate`, the only surface adopted before
 * this, was a pure function of a KB string and so never had to answer "which
 * instance?". A handle is that answer.
 */
class MechanicSession {
	constructor(module, layer, engine) {
		this.module = module;
		this.layer = layer;
		this.engine = engine;
		/** Orders recorded during the CURRENT call. Drained into every result. */
		this.orders = [];
		/** Questions core asked the shims during the current call, in order. */
		this.asked = [];
		/** Readings the current call was given, by interface. */
		this.readings = {};
	}
}

/**
 * Open a session BEFORE its layer exists.
 *
 * The order matters and is not a style choice: the shims below close over the
 * session object, and the layer is constructed WITH those shims, so the session
 * has to come first. Every shim reaches `s.orders` at call time rather than
 * capturing the array, which is what lets {@link beginCall} start a fresh queue
 * for each call without leaving a shim writing into the previous one.
 */
export function newSession(module, engine) {
	return new MechanicSession(module, undefined, engine);
}

/** Attach the constructed layer and publish the handle the caller passes back. */
export function openSession(s, layer) {
	s.layer = layer;
	const handle = nextHandle++;
	s.handle = handle;
	SESSIONS.set(handle, s);
	return handle;
}

/**
 * Open a session, load the world into its layer, and hand back the result every
 * `<module>.create` row returns.
 *
 * The try/catch is the interesting part. Registration, `publishGraph()` and
 * `publishWorld()` all run AFTER the handle exists and all of them can throw —
 * a KB missing the pack a gate reads raises out of Prolog, which is core's
 * deliberate behaviour and not an error this layer should swallow. Without the
 * catch, a create that failed halfway would leave a session nobody holds a
 * handle to: a leak with no possible caller. Found by the gate
 * (`test_mechanic_bridge.cpp` asserts that no session outlives it) rather than
 * by reading, which is why the gate counts open sessions at the end.
 */
export async function created(s, layer, hydrate) {
	const handle = openSession(s, layer);
	try {
		if (hydrate) await hydrate();
	} catch (err) {
		closeSession(handle);
		throw err;
	}
	return { session: handle, orders: s.orders, asked: s.asked };
}

/**
 * Resolve a handle, or throw a NAMED error. A stale handle is a host bug and a
 * plausible empty result would hide it (the reasoning `host-prolog-engine.js`
 * applies to unimplemented members).
 */
export function session(args, module) {
	const handle = args && args.session;
	const found = SESSIONS.get(handle);
	if (!found) {
		throw new Error(`insimulcore: no such mechanic session ${JSON.stringify(handle)}`);
	}
	if (module && found.module !== module) {
		throw new Error(
			`insimulcore: session ${handle} is a ${found.module} session, not ${module}`,
		);
	}
	return found;
}

/** Close a session and release the KB it owns. Idempotent. */
export function closeSession(handle) {
	const found = SESSIONS.get(handle);
	if (!found) return false;
	// The decision layers document that the CALLER owns the engine and they never
	// destroy it. The session is that caller.
	if (found.engine) found.engine.destroy();
	SESSIONS.delete(handle);
	return true;
}

/** Every open session, for a gate or a leak hunt. */
export function openSessions() {
	return Array.from(SESSIONS.entries()).map(([handle, s]) => ({
		session: handle,
		module: s.module,
	}));
}

/**
 * Build a KB for a session and load the world into it, or answer `undefined`.
 *
 * `kb` absent means NO engine, which every module documents as a real mode: no
 * legality gate, no requirement can be met, no fact delta is written. It is what
 * a host with its own persistence runs in, and it is not an error.
 */
export async function sessionEngine(args, createPrologEngine) {
	const kb = args && args.kb;
	if (kb === undefined || kb === null || kb === false) return undefined;
	const engine = await createPrologEngine();
	const programs = Array.isArray(kb) ? kb : [kb];
	for (const program of programs) {
		if (!program) continue;
		const res = await engine.consult(String(program));
		if (!res.success) {
			engine.destroy();
			throw new Error(`insimulcore: session KB failed to consult: ${res.error}`);
		}
	}
	return engine;
}

// ── The shims ───────────────────────────────────────────────────────────────

/**
 * Start a call: forget the previous call's orders and take this call's readings.
 * Every row does this first, so a result's `orders` are that call's and no other.
 */
export function beginCall(s, args) {
	s.orders = [];
	s.asked = [];
	s.readings = args || {};
	return s;
}

/** Finish a call: the report core produced, plus what the host must now do. */
export function endCall(s, report) {
	return { report, orders: s.orders, asked: s.asked };
}

function order(s, host, call, payload) {
	s.orders.push({ host, call, ...payload });
}

function asked(s, host, call, payload) {
	s.asked.push({ host, call, ...payload });
}

/**
 * A reading the host supplied, keyed or flat.
 *
 * `probe: {passable: true}` answers every question of that kind in this call;
 * `probe: {"gap_west": {passable: false}}` answers per key. Both forms are
 * useful — a turn-based host has one answer, a scene has one per link — and
 * telling them apart is a shape test, never a guess about content.
 */
function reading(source, key) {
	if (!source || typeof source !== 'object') return undefined;
	if (key !== undefined && Object.prototype.hasOwnProperty.call(source, key)) {
		const keyed = source[key];
		return keyed && typeof keyed === 'object' ? keyed : undefined;
	}
	// A flat reading is one whose fields are scalars rather than objects.
	const values = Object.values(source);
	if (values.length > 0 && values.every((v) => v === null || typeof v !== 'object')) return source;
	return undefined;
}

/**
 * `ICombatSystem` — TOLD, never asked.
 *
 * Core calls exactly three members (`CombatResolver` lines 405/418/781, measured
 * rather than assumed): register, unregister and applyDamage. The other five on
 * the interface are the host's own surface and core never reaches them, so this
 * shim does not implement them — `gdextension`'s GDScript host does, because a
 * game calls them.
 */
export function combatSystemShim(s) {
	return {
		registerEntity: (entity) => order(s, 'ICombatSystem', 'registerEntity', { entity }),
		unregisterEntity: (entityId) => order(s, 'ICombatSystem', 'unregisterEntity', { entityId }),
		applyDamage: (targetId, damage) =>
			order(s, 'ICombatSystem', 'applyDamage', { entityId: targetId, damage }),
	};
}

/**
 * `ISurvivalSystem` — TOLD. Core calls two members (`StaminaPool` 348/386): the
 * spend it decided and the recovery it decided. The needs CLOCK stays the
 * host's entirely and never crosses this boundary in either direction.
 */
export function survivalShim(s) {
	return {
		consumeStamina: (amount) => {
			order(s, 'ISurvivalSystem', 'consumeStamina', { amount });
			// Core reads the boolean as "did the host's own meter cover it". The
			// host cannot answer mid-call, and core has ALREADY decided the spend
			// was affordable against its own meter — so answering `false` here
			// would be the shim overruling core, which is the one thing it must
			// never do.
			return true;
		},
		recoverStamina: (amount) => order(s, 'ISurvivalSystem', 'recoverStamina', { amount }),
	};
}

/**
 * `ICombatStatSink` — the only interface that runs BOTH ways, which is why
 * equipment is the cheapest place to prove a row end to end (Unity §12.6 item 4).
 * `getBaseStats` is a reading the host gathered; `applyStats` is an order.
 */
export function combatStatSinkShim(s) {
	return {
		getBaseStats: (entityId) => {
			asked(s, 'ICombatStatSink', 'getBaseStats', { entityId });
			const stats = reading(s.readings.baseStats, entityId);
			return stats ? { ...stats } : undefined;
		},
		applyStats: (entityId, stats) =>
			order(s, 'ICombatStatSink', 'applyStats', { entityId, stats }),
	};
}

/** `ISkillModifierSink` — TOLD absolute totals, never a delta. */
export function skillModifierSinkShim(s) {
	return {
		applyModifiers: (actorId, modifiers) =>
			order(s, 'ISkillModifierSink', 'applyModifiers', { actorId, modifiers }),
	};
}

/**
 * `ITrajectoryProbe` — ASKED. The host raycast before the call; the answer rides
 * in as `trajectory`. No reading means the documented fallback: a world with no
 * geometry resolves a ranged attack on reach and accuracy alone.
 */
export function trajectoryShim(s) {
	return {
		query: (query) => {
			asked(s, 'ITrajectoryProbe', 'query', { query });
			return reading(s.readings.trajectory, query.target) ?? { clear: true };
		},
	};
}

/**
 * `IPerceptionProbe` — ASKED, per (observer, target) pair.
 *
 * `DetectionTracker.observe({readings})` already takes host readings directly,
 * which is how the corpus drives it, so `perception.observe` passes them through
 * and this shim is only reached for a pair the host did NOT supply. `null` is
 * the documented "sensed nothing", not an error.
 */
export function perceptionShim(s) {
	return {
		sense: (query) => {
			asked(s, 'IPerceptionProbe', 'sense', { query });
			return reading(s.readings.perception, `${query.observer}>${query.target}`) ?? null;
		},
	};
}

/**
 * `ITraversalProbe` — ASKED, once per geometric link. A link with no reading is
 * passable, which is core's documented fallback and what a headless world wants.
 */
export function traversalProbeShim(s) {
	return {
		query: (query) => {
			asked(s, 'ITraversalProbe', 'query', { query });
			return reading(s.readings.probe, query.link) ?? { passable: true };
		},
	};
}

/**
 * `ILocomotionHost` — TOLD, and the one place the ABI's synchrony bites.
 *
 * Core reads the `ArrivalReport` immediately; a real walk takes seconds. Unity
 * §12.2 finding 3 answered it and this answers it the same way, for the same
 * reason: report what is knowable at the DECISION moment, dispatch the body
 * after. So the order always goes out, and the arrival is whatever the host
 * pre-declared for this call.
 *
 * The default is `arrived: true` — core's own no-host behaviour — and NOT
 * `false`, because a movement that will complete in two seconds reported as a
 * failure makes `LocomotionDirector` count a successful walk against the plan
 * and re-plan around a wall that is not there. A host that already knows the
 * body cannot get there (no path, no body, unknown destination) says so by
 * passing `arrival: {arrived: false, reason: ...}`, which it can, because it
 * gathered the traversal reading before the call.
 */
export function locomotionShim(s) {
	return {
		travel: (locomotionOrder) => {
			order(s, 'ILocomotionHost', 'travel', { order: locomotionOrder });
			return arrivalFor(s, locomotionOrder);
		},
	};
}

function arrivalFor(s, locomotionOrder) {
	const declared =
		reading(s.readings.arrival, locomotionOrder.actor) ?? reading(s.readings.arrival);
	if (!declared) return { arrived: true };
	return {
		arrived: declared.arrived !== false,
		...(declared.location ? { location: declared.location } : {}),
		...(declared.reason ? { reason: declared.reason } : {}),
	};
}

/**
 * `IAgentActionHost` — TOLD. The `agentAi` module's interface, adopted here for
 * completeness of the seam rather than by a row: `AgentPlanner` is not a
 * band-120 module and tasklist 147 does not adopt it, so nothing in `entry.js`
 * constructs one yet. The shim exists because the Godot host implements the
 * interface (`addons/insimul/runtime/mechanics/`) and a shim it can be tested
 * against costs four lines.
 */
export function agentActionShim(s) {
	return {
		perform: (actionOrder) => order(s, 'IAgentActionHost', 'perform', { order: actionOrder }),
	};
}

/**
 * The whole `EngineHostAdapter`, as core's modules take it — one object wired
 * into every layer rather than hooks picked out per module
 * (`docs/runtime-contract.md` §2).
 */
export function adapterFor(s) {
	return {
		trajectory: trajectoryShim(s),
		perception: perceptionShim(s),
		traversal: traversalProbeShim(s),
		locomotion: locomotionShim(s),
		skillModifiers: skillModifierSinkShim(s),
		combatStats: combatStatSinkShim(s),
		agentActions: agentActionShim(s),
	};
}

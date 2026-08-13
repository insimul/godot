// host-prolog-engine.js — the ADAPTER's implementation of core's `PrologEngine`
// seam, backed by the NATIVE Prolog engine this plugin already links.
//
// Why this file exists (US-2 of tasklist 100, RUNTIME_CORE_ADOPTION.md §5.4):
//
//   `@insimul/core`'s `createPrologEngine()` dynamic-imports `WasmPrologEngine`,
//   which instantiates libinsimul/Trealla compiled to **wasm32**. QuickJS has no
//   WebAssembly, so that path cannot run inside the bridge — and it should not:
//   this plugin already links the *same* Trealla, natively, through libinsimul's
//   C ABI (vendor/insimul/insimul.h). Wrapping a wasm build of an engine we hold
//   natively would be silly.
//
//   So the bundler (tools/vendor-core-bundle.mjs) resolves core's
//   `../prolog/prolog-engine` import to THIS module. Core's source is not
//   patched — the dependency stays one-way (adapter -> core); the adapter simply
//   supplies the seam's implementation, which is exactly what a seam is for.
//   The proposed contract amendment that would make this explicit rather than
//   resolver-driven is RUNTIME_CORE_ADOPTION.md §8.
//
// SEMANTICS: this file must agree with `packages/core/src/prolog/wasm-engine.ts`
// on everything radiant generation can observe — `collapseTerm`, the trailing-`.`
// trim, the 1000-result default, and "success with zero bindings is still
// success". Those are mirrored below with the source lines they mirror. The
// conformance corpus (conformance/radiant/*.json) is what proves the mirror.
//
// The six `__insimul_prolog_*` globals are installed by the C host
// (../src/insimulcore.c); they map 1:1 onto libinsimul's KB + query ABI.

/**
 * Collapse an ABI term to the scalar a `QueryBindings` slot holds.
 *
 * Mirrors `collapseTerm` in packages/core/src/prolog/wasm-engine.ts verbatim:
 *   - atom / integer / float / bool → itself;
 *   - list `[a,b]` → `"."` (`"[]"` for the empty list);
 *   - compound `f(a,b)` → `"f"` (the functor).
 * libinsimul's binding JSON uses the same term encoding the wasm ABI does
 * (vendor/insimul/insimul.h "Binding-set JSON format"), so one rule set serves
 * both.
 */
export function collapseTerm(term) {
	if (term === null || term === undefined) return null;
	if (typeof term === 'string' || typeof term === 'number' || typeof term === 'boolean') {
		return term;
	}
	if (Array.isArray(term)) return term.length === 0 ? '[]' : '.';
	if (typeof term === 'object' && typeof term.functor === 'string') return term.functor;
	return String(term);
}

/** The engine used when a caller does not choose one. Mirrors core's default. */
export const DEFAULT_PROLOG_ENGINE = 'wasm';

/**
 * `PrologEngine` over libinsimul's C ABI.
 *
 * Only the members the ADOPTED surface actually calls are implemented —
 * `consult`, `query`, `destroy` for the radiant slice (tasklist 100), and
 * `assertFact` / `retractFact` / `queryOnce` for the band-120 mechanic modules
 * (tasklist 147 US-1: those four are the only `PrologEngine` members
 * `CombatResolver`, `StaminaPool`, `DetectionTracker`, `TraversalPlanner`,
 * `SkillProgression` and `RoutineDirector` reach for, measured rather than
 * assumed). Everything else throws a NAMED error rather than returning a
 * plausible empty value — if a future slice reaches for `getStats()` we want a
 * loud failure at the call site, not silent wrong behaviour the corpus might
 * not cover.
 *
 * ── THE ONE DELIBERATE DIVERGENCE FROM `WasmPrologEngine` ──────────────────
 *
 * Core's wasm engine implements every mutation as **rebuild**: record the fact
 * in a `factStore`, throw the KB away, create a fresh one and re-consult the
 * whole accumulated program. Its own header says why, and it is not a
 * correctness reason — *"Trealla supports incremental assert/retract properly,
 * so this class does NOT have to rebuild the KB from stored state... It does
 * anyway, [so that] US-2's diff of the two engines sees only real
 * disagreements."*
 *
 * This engine is that same Trealla, linked natively, so it asserts and retracts
 * in place. That is a divergence in MECHANISM and, deliberately, not in
 * OBSERVABLE BEHAVIOUR — the bookkeeping below mirrors core's exactly, so the
 * two agree on every question a caller can ask:
 *
 *  - **De-duplication.** Core stores facts in a `Set` keyed by normalized text,
 *    so asserting the same fact twice leaves ONE clause and `findall/3` cannot
 *    double-count. A bare native assert would leave two. `_facts` below is that
 *    same `Set`, and a repeat assert never reaches the KB.
 *  - **Retracting something that was CONSULTED rather than asserted.** Core's
 *    rebuild removes the fact from `factStore` and then re-consults the original
 *    program — which still contains the clause, so it survives. A bare native
 *    retract would delete it. So a retract whose fact is not in `_facts` never
 *    reaches the KB either, and reports success exactly as core's does.
 *  - **Dynamic declarations.** Core's rebuild emits `:- dynamic(p/n).` ahead of
 *    the program for every predicate it has ever recorded a fact for. Trealla
 *    auto-creates a dynamic predicate on assert, so the directive is only needed
 *    where the consulted program already defined the predicate STATICALLY — it
 *    is issued once per signature, at first sight, for exactly that case.
 *
 * Why diverge at all, when a rebuild would have been fewer lines: a mechanic
 * module asserts on every attack, spend, observation and step, and a rebuild is
 * O(whole program) per fact — a combat tick would re-consult every rule pack the
 * world loaded. It also churns KB handles, which is the failure mode the
 * `keepalive` KB in ../src/insimulcore.c exists to work around. Executing the
 * mechanic corpora against this engine (tasklist 147 US-2) is what holds the
 * "no observable divergence" claim to account.
 */
class NativePrologEngine {
	constructor(id) {
		/** @type {'wasm'} Same Trealla the wasm engine wraps — natively linked. */
		this.kind = 'wasm';
		this._id = id;
		/**
		 * Facts asserted through this wrapper, keyed `name/arity` -> Set of
		 * normalized `fact.` text. Core's `factStore`, with core's normalization.
		 */
		this._facts = new Map();
		/** Signatures already declared dynamic — core's `dynamicPredicates`. */
		this._dynamic = new Set();
	}

	async consult(program) {
		const err = globalThis.__insimul_prolog_consult(this._id, program);
		return err === null ? { success: true } : { success: false, error: err };
	}

	/**
	 * @param {string} queryString goal text, with or without a trailing `.`
	 * @param {number} [maxResults] defaults to 1000, as `WasmPrologEngine.query` does
	 */
	async query(queryString, maxResults = 1000) {
		// wasm-engine.ts: `queryString.trim().replace(/\.\s*$/, '')`.
		const goal = String(queryString).trim().replace(/\.\s*$/, '');
		let raw;
		try {
			raw = globalThis.__insimul_prolog_query(this._id, goal, maxResults);
		} catch (err) {
			// A goal that will not even start (syntax/type error) — the wasm
			// engine reports the same shape.
			return { success: false, bindings: [], error: String(err && err.message ? err.message : err) };
		}
		const solutions = JSON.parse(raw);
		return {
			success: true,
			bindings: solutions.map((sol) => {
				const out = {};
				for (const key of Object.keys(sol)) out[key] = collapseTerm(sol[key]);
				return out;
			}),
		};
	}

	destroy() {
		if (this._id < 0) return;
		globalThis.__insimul_prolog_destroy(this._id);
		this._id = -1;
	}

	/**
	 * `name/arity` of a fact — core's `extractPredicateSignature`, with its one
	 * bug fixed and the fix confined to something unobservable.
	 *
	 * Core matches the argument list with `[^)]*`, which STOPS at the first inner
	 * `)`, so `threat(a, pos(1,2), 3)` buckets as `threat/2`. That is harmless
	 * there because the key is only a bucket, and every caller reaches a fact
	 * through the same wrong key. Here the key is also what `:- dynamic(...)`
	 * names, and a directive for a predicate that does not exist protects
	 * nothing — so the scan below counts top-level commas across the whole term.
	 * Bucketing stays internal (de-duplication is by full fact text WITHIN a
	 * bucket, so a differing key cannot change which facts are dropped), which is
	 * what keeps this a fix rather than a divergence.
	 */
	_signature(fact) {
		const match = fact.match(/^([a-z_]\w*)\s*\(([^)]*)/);
		if (!match) {
			const atom = fact.match(/^([a-z_]\w*)\s*\.?$/);
			return atom ? `${atom[1]}/0` : '';
		}
		// Arity is the number of TOP-LEVEL commas plus one; nested compounds and
		// lists do not raise it. Scan the whole tail rather than `match[2]`, whose
		// `[^)]*` stops at the first inner `)`.
		const args = fact.slice(match[1].length + fact.slice(match[1].length).indexOf('(') + 1);
		let depth = 0;
		let arity = 1;
		for (let i = 0; i < args.length; i++) {
			const ch = args[i];
			if (ch === '(' || ch === '[') depth++;
			else if (ch === ']') depth--;
			else if (ch === ')') {
				if (depth === 0) break;
				depth--;
			} else if (ch === ',' && depth === 0) arity++;
		}
		return `${match[1]}/${arity}`;
	}

	/** Issue `:- dynamic(sig).` once per signature — see the class header. */
	_ensureDynamic(signature) {
		if (!signature || this._dynamic.has(signature)) return;
		this._dynamic.add(signature);
		// A predicate the program never defined statically needs no directive and
		// a KB that rejects the directive is telling us the predicate is already
		// dynamic, so the return value is deliberately not consulted.
		globalThis.__insimul_prolog_consult(this._id, `:- dynamic(${signature}).`);
	}

	/**
	 * @param {string} fact term text, with or without a trailing `.`
	 * @returns {Promise<boolean>} core's contract: whether the KB is loadable
	 *   afterwards, NOT whether anything changed.
	 */
	async assertFact(fact) {
		const normalized = String(fact).trim().replace(/\.\s*$/, '');
		if (!normalized) return true;
		const signature = this._signature(normalized);
		let bucket = this._facts.get(signature);
		if (!bucket) this._facts.set(signature, (bucket = new Set()));
		// Already there: core's rebuild would emit the identical program, so the
		// KB must not gain a second clause. See the header's de-duplication note.
		if (bucket.has(`${normalized}.`)) return true;

		this._ensureDynamic(signature);
		const err = globalThis.__insimul_prolog_assert(this._id, normalized);
		if (err !== null) return false;
		bucket.add(`${normalized}.`);
		return true;
	}

	async assertFacts(facts) {
		let ok = true;
		for (const fact of facts) ok = (await this.assertFact(fact)) && ok;
		return ok;
	}

	async retractFact(fact) {
		const normalized = String(fact).trim().replace(/\.\s*$/, '');
		if (!normalized) return true;
		const bucket = this._facts.get(this._signature(normalized));
		// Not one of ours: core's rebuild re-consults the original program, which
		// still carries the clause, so nothing is removed there and nothing is
		// removed here. See the header's second note.
		if (!bucket || !bucket.has(`${normalized}.`)) return true;
		bucket.delete(`${normalized}.`);
		const res = globalThis.__insimul_prolog_retract(this._id, normalized);
		// `true` removed, `false` nothing matched (not an error), string = error.
		return typeof res !== 'string';
	}

	/** Mirrors `WasmPrologEngine.queryOnce`: one solution is enough. */
	async queryOnce(queryString) {
		const result = await this.query(queryString, 1);
		return result.success && result.bindings.length > 0;
	}

	/** Mirrors core's: the facts THIS wrapper asserted, in insertion order. */
	getFactsForPredicate(signature) {
		const bucket = this._facts.get(signature);
		return bucket ? Array.from(bucket) : [];
	}

	getAllFacts() {
		const all = [];
		for (const bucket of this._facts.values()) for (const fact of bucket) all.push(fact);
		return all;
	}

	// ── Not reached by the adopted surface. Fail loudly if a future one gets here.
	declareDynamic() { return unimplemented('declareDynamic'); }
	addRule() { return unimplemented('addRule'); }
	addRules() { return unimplemented('addRules'); }
	getAllRules() { return unimplemented('getAllRules'); }
	clear() { return unimplemented('clear'); }
	clearFacts() { return unimplemented('clearFacts'); }
	export() { return unimplemented('export'); }
	import() { return unimplemented('import'); }
	getStats() { return unimplemented('getStats'); }
}

function unimplemented(member) {
	throw new Error(
		`insimulcore: PrologEngine.${member}() is not implemented by the native bridge. ` +
			'The adopted slice does not use it — see gdextension/corebridge/js/host-prolog-engine.js.',
	);
}

/**
 * Build an engine. Async to match core's `createPrologEngine`, though the
 * native KB is created synchronously (there is no wasm module to instantiate).
 * The returned promise is already settled, which is what lets the C host drive
 * an async core call to completion by draining the job queue — see
 * `insimul_core_call`.
 */
export async function createPrologEngine(_options = {}) {
	const id = globalThis.__insimul_prolog_create();
	if (id < 0) throw new Error('insimulcore: could not create a Prolog KB');
	return new NativePrologEngine(id);
}

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

import { generateRadiantQuests } from '@insimul/core/radiant/radiant-engine';
import { BASE_RADIANT_TEMPLATES, BASE_RADIANT_TEMPLATE_IDS } from '@insimul/core/radiant/base-templates';

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

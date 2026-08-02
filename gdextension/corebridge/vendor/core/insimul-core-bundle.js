(() => {
  // gdextension/corebridge/js/host-prolog-engine.js
  function collapseTerm(term) {
    if (term === null || term === void 0) return null;
    if (typeof term === "string" || typeof term === "number" || typeof term === "boolean") {
      return term;
    }
    if (Array.isArray(term)) return term.length === 0 ? "[]" : ".";
    if (typeof term === "object" && typeof term.functor === "string") return term.functor;
    return String(term);
  }
  var NativePrologEngine = class {
    constructor(id) {
      this.kind = "wasm";
      this._id = id;
    }
    async consult(program) {
      const err = globalThis.__insimul_prolog_consult(this._id, program);
      return err === null ? { success: true } : { success: false, error: err };
    }
    /**
     * @param {string} queryString goal text, with or without a trailing `.`
     * @param {number} [maxResults] defaults to 1000, as `WasmPrologEngine.query` does
     */
    async query(queryString, maxResults = 1e3) {
      const goal = String(queryString).trim().replace(/\.\s*$/, "");
      let raw;
      try {
        raw = globalThis.__insimul_prolog_query(this._id, goal, maxResults);
      } catch (err) {
        return { success: false, bindings: [], error: String(err && err.message ? err.message : err) };
      }
      const solutions = JSON.parse(raw);
      return {
        success: true,
        bindings: solutions.map((sol) => {
          const out = {};
          for (const key of Object.keys(sol)) out[key] = collapseTerm(sol[key]);
          return out;
        })
      };
    }
    destroy() {
      if (this._id < 0) return;
      globalThis.__insimul_prolog_destroy(this._id);
      this._id = -1;
    }
    // ── Not reached by the adopted slice. Fail loudly if a future one gets here.
    declareDynamic() {
      return unimplemented("declareDynamic");
    }
    assertFact() {
      return unimplemented("assertFact");
    }
    assertFacts() {
      return unimplemented("assertFacts");
    }
    retractFact() {
      return unimplemented("retractFact");
    }
    addRule() {
      return unimplemented("addRule");
    }
    addRules() {
      return unimplemented("addRules");
    }
    queryOnce() {
      return unimplemented("queryOnce");
    }
    getFactsForPredicate() {
      return unimplemented("getFactsForPredicate");
    }
    getAllFacts() {
      return unimplemented("getAllFacts");
    }
    getAllRules() {
      return unimplemented("getAllRules");
    }
    clear() {
      return unimplemented("clear");
    }
    clearFacts() {
      return unimplemented("clearFacts");
    }
    export() {
      return unimplemented("export");
    }
    import() {
      return unimplemented("import");
    }
    getStats() {
      return unimplemented("getStats");
    }
  };
  function unimplemented(member) {
    throw new Error(
      `insimulcore: PrologEngine.${member}() is not implemented by the native bridge. The adopted slice does not use it \u2014 see gdextension/corebridge/js/host-prolog-engine.js.`
    );
  }
  async function createPrologEngine(_options = {}) {
    const id = globalThis.__insimul_prolog_create();
    if (id < 0) throw new Error("insimulcore: could not create a Prolog KB");
    return new NativePrologEngine(id);
  }

  // ../../../../Development/insimul/babylon/packages/core/src/prolog/prolog-fact-parser.ts
  function parsePrologFile(source) {
    const facts = [];
    const rules = [];
    const contentBlocks = [];
    const errors = [];
    const lines = source.split("\n");
    let i = 0;
    while (i < lines.length) {
      const line = lines[i].trim();
      if (!line || line.startsWith("%")) {
        i++;
        continue;
      }
      if (line.startsWith(":-")) {
        i++;
        continue;
      }
      let clause = line;
      let startLine = i + 1;
      while (!clauseEnds(clause) && i + 1 < lines.length) {
        i++;
        const nextLine = lines[i].trim();
        if (!nextLine || nextLine.startsWith("%")) continue;
        clause += "\n" + nextLine;
      }
      const ruleIdx = findRuleOperator(clause);
      if (ruleIdx >= 0) {
        const headText = clause.substring(0, ruleIdx).trim();
        const bodyText = clause.substring(ruleIdx + 2).trim().replace(/\.\s*$/, "");
        const head = parseTerm(headText);
        if (head && head.type === "fact") {
          rules.push({
            head: head.fact,
            body: bodyText,
            raw: clause,
            line: startLine
          });
        } else {
          errors.push({ line: startLine, message: "Failed to parse rule head", text: clause.substring(0, 80) });
        }
      } else {
        const factText = clause.replace(/\.\s*$/, "").trim();
        const result = parseTerm(factText);
        if (result && result.type === "fact") {
          result.fact.line = startLine;
          facts.push(result.fact);
        } else if (factText) {
          errors.push({ line: startLine, message: "Failed to parse fact", text: factText.substring(0, 80) });
        }
      }
      i++;
    }
    buildContentBlocks(facts, rules, contentBlocks, source, lines);
    return { facts, rules, contentBlocks, errors };
  }
  function parseTerm(text) {
    text = text.trim();
    if (!text) return null;
    const match = text.match(/^([a-z_][a-z0-9_]*)\s*\(([\s\S]*)\)$/);
    if (!match) {
      return null;
    }
    const predicate = match[1];
    const argsText = match[2];
    const args = parseArgList(argsText);
    return {
      type: "fact",
      fact: { predicate, arity: args.length, args, line: 0 }
    };
  }
  function parseArgList(text) {
    const args = [];
    let current = "";
    let depth = 0;
    let inSingleQuote = false;
    let i = 0;
    while (i < text.length) {
      const ch = text[i];
      if (inSingleQuote) {
        if (ch === "'" && i + 1 < text.length && text[i + 1] === "'") {
          current += "''";
          i += 2;
          continue;
        } else if (ch === "'") {
          inSingleQuote = false;
          current += ch;
          i++;
          continue;
        }
        current += ch;
        i++;
        continue;
      }
      if (ch === "'") {
        inSingleQuote = true;
        current += ch;
        i++;
        continue;
      }
      if (ch === "(" || ch === "[") {
        depth++;
        current += ch;
      } else if (ch === ")" || ch === "]") {
        depth--;
        current += ch;
      } else if (ch === "," && depth === 0) {
        args.push(parseArg(current.trim()));
        current = "";
        i++;
        continue;
      } else {
        current += ch;
      }
      i++;
    }
    if (current.trim()) {
      args.push(parseArg(current.trim()));
    }
    return args;
  }
  function parseArg(text) {
    text = text.trim();
    if (text.startsWith("'") && text.endsWith("'") && text.length >= 2) {
      const inner = text.slice(1, -1).replace(/''/g, "'");
      return { type: "string", value: inner };
    }
    if (/^-?[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?$/.test(text)) {
      return { type: "number", value: parseFloat(text) };
    }
    if (/^[A-Z_][A-Za-z0-9_]*$/.test(text)) {
      return { type: "variable", value: text };
    }
    if (text.startsWith("[") && text.endsWith("]")) {
      const inner = text.slice(1, -1).trim();
      if (!inner) return { type: "list", elements: [] };
      const elements = parseArgList(inner);
      return { type: "list", elements };
    }
    const compMatch = text.match(/^([a-z_][a-z0-9_]*)\s*\(([\s\S]*)\)$/);
    if (compMatch) {
      const functor = compMatch[1];
      const innerArgs = parseArgList(compMatch[2]);
      return { type: "compound", functor, args: innerArgs };
    }
    return { type: "atom", value: text };
  }
  function clauseEnds(clause) {
    let inQuote = false;
    for (let i = 0; i < clause.length; i++) {
      if (clause[i] === "'" && !inQuote) {
        inQuote = true;
      } else if (clause[i] === "'" && inQuote) {
        if (i + 1 < clause.length && clause[i + 1] === "'") {
          i++;
        } else {
          inQuote = false;
        }
      } else if (clause[i] === "." && !inQuote && (i + 1 >= clause.length || /\s/.test(clause[i + 1]))) {
        return true;
      }
    }
    return false;
  }
  function findRuleOperator(clause) {
    let inQuote = false;
    let depth = 0;
    for (let i = 0; i < clause.length - 1; i++) {
      if (clause[i] === "'" && !inQuote) {
        inQuote = true;
      } else if (clause[i] === "'" && inQuote) {
        if (i + 1 < clause.length && clause[i + 1] === "'") {
          i++;
        } else {
          inQuote = false;
        }
      } else if (!inQuote) {
        if (clause[i] === "(") depth++;
        else if (clause[i] === ")") depth--;
        else if (depth === 0 && clause[i] === ":" && clause[i + 1] === "-") {
          return i;
        }
      }
    }
    return -1;
  }
  function buildContentBlocks(facts, rules, blocks, _source, lines) {
    const groups = /* @__PURE__ */ new Map();
    for (const fact of facts) {
      const entityArg = fact.args[0];
      if (!entityArg) continue;
      const entityAtom = argToString(entityArg);
      if (!groups.has(entityAtom)) {
        groups.set(entityAtom, { predicate: fact.predicate, startLine: fact.line, endLine: fact.line });
      } else {
        const g = groups.get(entityAtom);
        g.endLine = Math.max(g.endLine, fact.line);
      }
    }
    for (const rule of rules) {
      const entityArg = rule.head.args[0];
      if (!entityArg) continue;
      const entityAtom = argToString(entityArg);
      if (!groups.has(entityAtom)) {
        groups.set(entityAtom, { predicate: rule.head.predicate, startLine: rule.line, endLine: rule.line });
      } else {
        const g = groups.get(entityAtom);
        g.endLine = Math.max(g.endLine, rule.line);
      }
    }
    Array.from(groups.entries()).forEach(([entityAtom, group]) => {
      const rawLines = [];
      for (let l = group.startLine - 1; l < group.endLine && l < lines.length; l++) {
        rawLines.push(lines[l]);
      }
      blocks.push({
        primaryPredicate: group.predicate,
        entityAtom,
        raw: rawLines.join("\n"),
        line: group.startLine
      });
    });
  }
  function argToString(arg) {
    switch (arg.type) {
      case "atom":
        return arg.value;
      case "string":
        return arg.value;
      case "number":
        return String(arg.value);
      case "variable":
        return arg.value;
      case "compound":
        return `${arg.functor}(${arg.args.map(argToString).join(", ")})`;
      case "list":
        return `[${arg.elements.map(argToString).join(", ")}]`;
    }
  }

  // ../../../../Development/insimul/babylon/packages/core/src/radiant/radiant-engine.ts
  async function generateRadiantQuests(kb, opts) {
    const program = Array.isArray(kb) ? kb.join("\n") : kb;
    const maxQuests = opts.maxQuests ?? Number.POSITIVE_INFINITY;
    const templates = parseTemplates(program);
    templates.sort((a, b) => a.id < b.id ? -1 : a.id > b.id ? 1 : 0);
    const engine = await createPrologEngine();
    try {
      const consulted = await engine.consult(program);
      if (!consulted.success) {
        throw new Error(`radiant: KB consult failed: ${consulted.error}`);
      }
      const quests = [];
      for (const tpl of templates) {
        if (quests.length >= maxQuests) break;
        let excluded = false;
        for (const goal of tpl.exclusions) {
          if (await succeeds(engine, goal)) {
            excluded = true;
            break;
          }
        }
        if (excluded) continue;
        const cooldownUntils = await solveAll(engine, `radiant_cooldown_until(${tpl.id}, T)`);
        const active = cooldownUntils.map((b) => Number(b["T"])).filter((t) => Number.isFinite(t));
        if (active.some((t) => t > opts.now)) continue;
        const candidates = await solveCandidates(engine, tpl);
        if (candidates.length === 0) continue;
        const rng = mulberry32(hashSeed(opts.seed) ^ hashSeed(tpl.id));
        const chosen = candidates[Math.floor(rng() * candidates.length)];
        quests.push(buildQuest(tpl, chosen, opts.now, active));
      }
      return { quests };
    } finally {
      engine.destroy?.();
    }
  }
  function parseTemplates(program) {
    const { facts } = parsePrologFile(program);
    const byId = /* @__PURE__ */ new Map();
    const ensure = (id) => {
      let t = byId.get(id);
      if (!t) {
        t = {
          id,
          meta: { category: "radiant", title: "", questType: "radiant", difficulty: 1 },
          preconditions: [],
          objectives: [],
          rewards: [],
          cooldownSeconds: 0,
          exclusions: []
        };
        byId.set(id, t);
      }
      return t;
    };
    for (const f of facts) {
      const id = firstAtom(f.args[0]);
      if (!id) continue;
      switch (`${f.predicate}/${f.arity}`) {
        case "radiant_template/2":
          ensure(id).meta = parseMeta(f.args[1]);
          break;
        case "radiant_precondition/3": {
          const slot = firstAtom(f.args[1]);
          if (slot) ensure(id).preconditions.push({ slot, goalText: goalText(f.args[2]) });
          break;
        }
        case "radiant_objective/2":
          ensure(id).objectives.push(f.args[1]);
          break;
        case "radiant_reward/3": {
          const kind = firstAtom(f.args[1]);
          if (kind) ensure(id).rewards.push({ kind, amount: f.args[2] });
          break;
        }
        case "radiant_cooldown/2":
          ensure(id).cooldownSeconds = argNum(f.args[1]) ?? 0;
          break;
        case "radiant_exclusion/2":
          ensure(id).exclusions.push(goalText(f.args[1]));
          break;
        default:
          break;
      }
    }
    return Array.from(byId.values()).filter((t) => t.meta.title !== "" || t.objectives.length > 0);
  }
  function parseMeta(arg) {
    const meta = { category: "radiant", title: "", questType: "radiant", difficulty: 1 };
    if (!arg || arg.type !== "list") return meta;
    for (const el of arg.elements) {
      if (el.type !== "compound" || el.args.length !== 1) continue;
      const v = el.args[0];
      switch (el.functor) {
        case "category":
          meta.category = argText(v);
          break;
        case "title":
          meta.title = argText(v);
          break;
        case "quest_type":
          meta.questType = argText(v);
          break;
        case "difficulty":
          meta.difficulty = argNum(v) ?? 1;
          break;
        default:
          break;
      }
    }
    return meta;
  }
  async function solveCandidates(engine, tpl) {
    if (tpl.preconditions.length === 0) return [];
    const goal = tpl.preconditions.map((p) => p.goalText).join(", ");
    const slotVars = tpl.preconditions.map((p) => ({ slot: p.slot, varName: slotVar(p.slot) }));
    const solutions = await solveAll(engine, goal);
    const seen = /* @__PURE__ */ new Set();
    const projected = [];
    for (const sol of solutions) {
      const row = {};
      let complete = true;
      for (const { slot, varName } of slotVars) {
        const raw = sol[varName];
        if (raw === void 0 || raw === null || typeof raw === "boolean") {
          complete = false;
          break;
        }
        row[slot] = raw;
      }
      if (!complete) continue;
      const key = canonKey(row, slotVars.map((s) => s.slot));
      if (seen.has(key)) continue;
      seen.add(key);
      projected.push(row);
    }
    const slots = slotVars.map((s) => s.slot);
    projected.sort((a, b) => canonKey(a, slots) < canonKey(b, slots) ? -1 : 1);
    return projected;
  }
  function canonKey(row, slots) {
    return JSON.stringify(slots.map((s) => [s, typeof row[s], row[s]]));
  }
  function buildQuest(tpl, bindings, now, staleCooldowns) {
    const questId = `radiant_${tpl.id}_${now}`;
    const bindMap = new Map(Object.entries(bindings));
    const lines = [];
    lines.push(
      `quest(${questId}, ${quoteProlog(fillTitle(tpl.meta.title, bindings))}, ${atom(tpl.meta.questType)}, ${tpl.meta.difficulty}, available).`
    );
    tpl.objectives.forEach((obj, i) => {
      lines.push(`quest_objective(${questId}, ${i}, ${argToProlog(substitute(obj, bindMap))}).`);
    });
    for (const reward of tpl.rewards) {
      const amount = evalAmount(reward.amount, tpl, bindMap);
      lines.push(`quest_reward(${questId}, ${atom(reward.kind)}, ${amount}).`);
    }
    const factsToAssert = [`radiant_generated(${questId}, ${tpl.id}, ${now}).`];
    const factsToRetract = [];
    if (tpl.cooldownSeconds > 0) {
      for (const t of staleCooldowns) {
        factsToRetract.push(`radiant_cooldown_until(${tpl.id}, ${t}).`);
      }
      factsToAssert.push(`radiant_cooldown_until(${tpl.id}, ${now + tpl.cooldownSeconds}).`);
    }
    return {
      questId,
      templateId: tpl.id,
      questContent: lines.join("\n"),
      factsToAssert,
      factsToRetract
    };
  }
  function fillTitle(title, bindings) {
    return title.replace(
      /\{(\w+)\}/g,
      (whole, slot) => slot in bindings ? String(bindings[slot]) : whole
    );
  }
  function evalAmount(arg, tpl, bindMap) {
    if (arg.type === "number") return Math.trunc(arg.value);
    if (arg.type === "compound" && arg.functor === "times" && arg.args.length === 2) {
      return Math.trunc(evalFactor(arg.args[0], tpl, bindMap) * evalFactor(arg.args[1], tpl, bindMap));
    }
    if (arg.type === "compound" && arg.functor === "per" && arg.args.length === 2) {
      const slot = argText(arg.args[0]);
      const unit = evalFactor(arg.args[1], tpl, bindMap);
      return Math.trunc(unit * countForSlot(slot, tpl));
    }
    return 0;
  }
  function evalFactor(arg, tpl, bindMap) {
    if (arg.type === "number") return arg.value;
    if (arg.type === "atom") {
      if (arg.value === "difficulty") return tpl.meta.difficulty;
      const n = Number(arg.value);
      return Number.isFinite(n) ? n : 0;
    }
    if (arg.type === "variable") {
      const v = bindMap.get(slotForVar(arg.value));
      const n = Number(v);
      return Number.isFinite(n) ? n : 0;
    }
    return 0;
  }
  function countForSlot(slot, tpl) {
    const v = slotVar(slot);
    for (const obj of tpl.objectives) {
      if (obj.type !== "compound") continue;
      const hasSlot = obj.args.some((a) => a.type === "variable" && a.value === v);
      if (!hasSlot) continue;
      const num = obj.args.find((a) => a.type === "number");
      if (num && num.type === "number") return num.value;
    }
    return 1;
  }
  function substitute(arg, bindMap) {
    switch (arg.type) {
      case "variable": {
        const slot = slotForVar(arg.value);
        const v = bindMap.get(slot);
        if (v === void 0) return arg;
        return typeof v === "number" ? { type: "number", value: v } : { type: "atom", value: v };
      }
      case "compound":
        return { type: "compound", functor: arg.functor, args: arg.args.map((a) => substitute(a, bindMap)) };
      case "list":
        return { type: "list", elements: arg.elements.map((a) => substitute(a, bindMap)) };
      default:
        return arg;
    }
  }
  function argToProlog(arg) {
    switch (arg.type) {
      case "number":
        return String(arg.value);
      case "atom":
      case "string":
        return atom(arg.value);
      case "variable":
        return arg.value;
      case "compound":
        return `${arg.functor}(${arg.args.map(argToProlog).join(", ")})`;
      case "list":
        return `[${arg.elements.map(argToProlog).join(", ")}]`;
    }
  }
  async function succeeds(engine, goal) {
    try {
      const r = await engine.query(goal, 1);
      return r.success && r.bindings.length > 0;
    } catch {
      return false;
    }
  }
  async function solveAll(engine, goal) {
    try {
      const r = await engine.query(goal);
      return r.success ? r.bindings : [];
    } catch {
      return [];
    }
  }
  function slotVar(slot) {
    return slot.charAt(0).toUpperCase() + slot.slice(1);
  }
  function slotForVar(varName) {
    return varName.charAt(0).toLowerCase() + varName.slice(1);
  }
  function firstAtom(arg) {
    if (!arg) return null;
    if (arg.type === "atom") return arg.value;
    if (arg.type === "string") return arg.value;
    return null;
  }
  function argText(arg) {
    if (!arg) return "";
    if (arg.type === "atom" || arg.type === "string") return arg.value;
    if (arg.type === "number") return String(arg.value);
    if (arg.type === "variable") return arg.value;
    return "";
  }
  function argNum(arg) {
    if (arg && arg.type === "number") return arg.value;
    return null;
  }
  function goalText(arg) {
    return argToGoalSource(arg);
  }
  function argToGoalSource(arg) {
    if (!arg) return "fail";
    switch (arg.type) {
      case "atom":
        return arg.value;
      case "string":
        return quoteProlog(arg.value);
      case "number":
        return String(arg.value);
      case "variable":
        return arg.value;
      case "compound":
        return `${arg.functor}(${arg.args.map(argToGoalSource).join(", ")})`;
      case "list":
        return `[${arg.elements.map(argToGoalSource).join(", ")}]`;
    }
  }
  var ATOM_RE = /^[a-z][a-zA-Z0-9_]*$/;
  function atom(s) {
    if (s === "") return quoteProlog("");
    return ATOM_RE.test(s) ? s : quoteProlog(s);
  }
  function quoteProlog(s) {
    return `'${s.replace(/\\/g, "\\\\").replace(/'/g, "\\'")}'`;
  }
  function hashSeed(seed) {
    if (typeof seed === "number") return seed >>> 0;
    let h = 2166136261 >>> 0;
    for (let i = 0; i < seed.length; i++) {
      h ^= seed.charCodeAt(i);
      h = Math.imul(h, 16777619);
    }
    return h >>> 0;
  }
  function mulberry32(seed) {
    let a = seed >>> 0;
    return function() {
      a = a + 1831565813 | 0;
      let t = Math.imul(a ^ a >>> 15, 1 | a);
      t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t;
      return ((t ^ t >>> 14) >>> 0) / 4294967296;
    };
  }

  // ../../../../Development/insimul/babylon/packages/core/src/radiant/base-templates.ts
  var BASE_RADIANT_TEMPLATES = `% Insimul base radiant template pack (US-RQ5)
%
% A starter pack of genre-neutral radiant (procedural) quest templates. It uses
% ONLY predicates guaranteed by predicate-schema.ts for any world, so it drops
% into any base world without authoring:
%
%   characters  \u2014 person/1, occupation/2
%   settlements \u2014 settlement/1, settlement_mayor/2
%   items       \u2014 item_category/2
%   businesses  \u2014 business_owner/2
%
% This pack proves the runtime path (plan docs/PLATFORM_SPLIT_AND_ENGINE_PLUGINS.md
% \xA73.3): once radiant generation is Prolog template DATA + the fixed slot-filling
% algorithm (packages/core/src/radiant/radiant-engine.ts), a closed platform
% generator may later EMIT richer, world-specific template packs in this same
% format and every native engine inherits them for free.
%
% Vocabulary reference + fully-worked examples: packages/core/docs/radiant-templates.md
%
% Runtime provenance/cooldown facts are declared dynamic so the pack consults
% into a fresh engine (via GamePrologEngine.initialize's radiantTemplates seam)
% even before any quest has been generated.
:- dynamic(radiant_generated/3).
:- dynamic(radiant_cooldown_until/2).

% \u2500\u2500 1. Fetch \u2014 gather herbs for a herbalist \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
radiant_template(rt_fetch, [category(fetch), title('Gather Herbs for {giver}'), quest_type(gathering), difficulty(1)]).
radiant_precondition(rt_fetch, giver, occupation(Giver, herbalist)).
radiant_precondition(rt_fetch, item, item_category(Item, herb)).
radiant_objective(rt_fetch, collect(Item, 5)).
radiant_objective(rt_fetch, deliver(Item, Giver)).
radiant_reward(rt_fetch, gold, times(15, difficulty)).
radiant_reward(rt_fetch, experience, 20).
radiant_cooldown(rt_fetch, 3600).
radiant_exclusion(rt_fetch, radiant_generated(_, rt_fetch, _)).

% \u2500\u2500 2. Delivery \u2014 carry a trade good between two different residents \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
% Multi-slot join: \`recipient\` is solved after \`giver\` and must be a different
% person (the parenthesised conjunction is a single Goal term).
radiant_template(rt_delivery, [category(delivery), title('Deliver goods to {recipient}'), quest_type(delivery), difficulty(2)]).
radiant_precondition(rt_delivery, giver, business_owner(_Business, Giver)).
radiant_precondition(rt_delivery, item, item_category(Item, trade_good)).
radiant_precondition(rt_delivery, recipient, (person(Recipient), Recipient \\= Giver)).
radiant_objective(rt_delivery, deliver(Item, Recipient)).
radiant_reward(rt_delivery, gold, times(25, difficulty)).
radiant_reward(rt_delivery, experience, 35).
radiant_cooldown(rt_delivery, 1800).
radiant_exclusion(rt_delivery, radiant_generated(_, rt_delivery, _)).

% \u2500\u2500 3. Bounty \u2014 hunt a wanted outlaw for a settlement \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
radiant_template(rt_bounty, [category(bounty), title('Bounty: {target}'), quest_type(combat), difficulty(3)]).
radiant_precondition(rt_bounty, poster, settlement_mayor(_Settlement, Poster)).
radiant_precondition(rt_bounty, target, occupation(Target, outlaw)).
radiant_objective(rt_bounty, defeat(Target, 1)).
radiant_reward(rt_bounty, gold, times(50, difficulty)).
radiant_reward(rt_bounty, reputation, times(5, difficulty)).
radiant_cooldown(rt_bounty, 7200).
radiant_exclusion(rt_bounty, radiant_generated(_, rt_bounty, _)).

% \u2500\u2500 4. Escort-lite \u2014 meet a traveller and see them to a settlement \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
% "Escort-lite": no live escort AI, just talk to the traveller then reach the
% destination \u2014 expressible with the guaranteed talk_to/visit_location goals.
radiant_template(rt_escort, [category(escort), title('See {traveller} to {destination}'), quest_type(escort), difficulty(2)]).
radiant_precondition(rt_escort, traveller, occupation(Traveller, traveller)).
radiant_precondition(rt_escort, destination, settlement(Destination)).
radiant_objective(rt_escort, talk_to(Traveller)).
radiant_objective(rt_escort, visit_location(Destination)).
radiant_reward(rt_escort, gold, times(30, difficulty)).
radiant_reward(rt_escort, experience, 30).
radiant_cooldown(rt_escort, 3600).
radiant_exclusion(rt_escort, radiant_generated(_, rt_escort, _)).

% \u2500\u2500 5. Gather \u2014 collect a stock of ore for a blacksmith \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
% \`per(item, N)\` scales the gold by the objective's collect count (10).
radiant_template(rt_gather, [category(gather), title('Supply {giver} with ore'), quest_type(gathering), difficulty(2)]).
radiant_precondition(rt_gather, giver, occupation(Giver, blacksmith)).
radiant_precondition(rt_gather, item, item_category(Item, ore)).
radiant_objective(rt_gather, collect(Item, 10)).
radiant_objective(rt_gather, deliver(Item, Giver)).
radiant_reward(rt_gather, gold, per(item, 4)).
radiant_reward(rt_gather, experience, 40).
radiant_cooldown(rt_gather, 5400).
radiant_exclusion(rt_gather, radiant_generated(_, rt_gather, _)).

% \u2500\u2500 6. Visit \u2014 scout a settlement \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
radiant_template(rt_visit, [category(visit), title('Scout {destination}'), quest_type(exploration), difficulty(1)]).
radiant_precondition(rt_visit, destination, settlement(Destination)).
radiant_objective(rt_visit, visit_location(Destination)).
radiant_reward(rt_visit, gold, times(10, difficulty)).
radiant_reward(rt_visit, experience, 15).
radiant_cooldown(rt_visit, 2400).
radiant_exclusion(rt_visit, radiant_generated(_, rt_visit, _)).
`;
  var BASE_RADIANT_TEMPLATE_IDS = [
    "rt_fetch",
    "rt_delivery",
    "rt_bounty",
    "rt_escort",
    "rt_gather",
    "rt_visit"
  ];

  // gdextension/corebridge/js/entry.js
  var METHODS = {
    /**
     * `radiant.generate` — the first adopted slice (RUNTIME_CORE_ADOPTION.md §5).
     * args: `{ kb: string | string[], options: { seed, now, maxQuests? } }`
     * result: `{ quests: GeneratedRadiantQuest[] }`
     */
    "radiant.generate": (args) => generateRadiantQuests(args.kb, args.options),
    /**
     * `radiant.baseTemplates` — core's shipped template pack, so a game does not
     * have to vendor a copy of it to generate anything.
     */
    "radiant.baseTemplates": () => ({
      templates: BASE_RADIANT_TEMPLATES,
      templateIds: BASE_RADIANT_TEMPLATE_IDS
    }),
    /** `core.methods` — introspection; lets a gate assert the adopted surface. */
    "core.methods": () => ({ methods: Object.keys(METHODS).sort() })
  };
  globalThis.__insimul_core_dispatch = function(method, argsJson) {
    const fn = METHODS[method];
    if (!fn) {
      return Promise.reject(new Error(`insimulcore: unknown method "${method}"`));
    }
    return Promise.resolve().then(() => fn(argsJson ? JSON.parse(argsJson) : {}));
  };
})();

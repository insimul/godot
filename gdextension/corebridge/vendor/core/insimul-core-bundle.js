(() => {
  var __defProp = Object.defineProperty;
  var __defNormalProp = (obj, key, value) => key in obj ? __defProp(obj, key, { enumerable: true, configurable: true, writable: true, value }) : obj[key] = value;
  var __publicField = (obj, key, value) => __defNormalProp(obj, typeof key !== "symbol" ? key + "" : key, value);

  // corebridge/js/host-text-codec.js
  var REPLACEMENT = 65533;
  var PolyfillTextEncoder = class {
    get encoding() {
      return "utf-8";
    }
    /** @param {string} input @returns {Uint8Array} */
    encode(input = "") {
      const str = String(input);
      const bytes = [];
      for (let i = 0; i < str.length; i++) {
        let code = str.charCodeAt(i);
        if (code >= 55296 && code <= 56319) {
          const next = i + 1 < str.length ? str.charCodeAt(i + 1) : 0;
          if (next >= 56320 && next <= 57343) {
            code = 65536 + (code - 55296 << 10) + (next - 56320);
            i++;
          } else {
            code = REPLACEMENT;
          }
        } else if (code >= 56320 && code <= 57343) {
          code = REPLACEMENT;
        }
        if (code < 128) {
          bytes.push(code);
        } else if (code < 2048) {
          bytes.push(192 | code >> 6, 128 | code & 63);
        } else if (code < 65536) {
          bytes.push(224 | code >> 12, 128 | code >> 6 & 63, 128 | code & 63);
        } else {
          bytes.push(
            240 | code >> 18,
            128 | code >> 12 & 63,
            128 | code >> 6 & 63,
            128 | code & 63
          );
        }
      }
      return new Uint8Array(bytes);
    }
  };
  var PolyfillTextDecoder = class {
    constructor(label = "utf-8") {
      const normalized = String(label).toLowerCase();
      if (normalized !== "utf-8" && normalized !== "utf8" && normalized !== "unicode-1-1-utf-8") {
        throw new RangeError(`insimulcore: TextDecoder supports utf-8 only, not "${label}"`);
      }
    }
    get encoding() {
      return "utf-8";
    }
    /** @param {Uint8Array | ArrayBuffer} input @returns {string} */
    decode(input) {
      if (input === void 0 || input === null) return "";
      const bytes = input instanceof Uint8Array ? input : new Uint8Array(input.buffer !== void 0 ? input.buffer : input);
      let out = "";
      for (let i = 0; i < bytes.length; ) {
        const byte = bytes[i];
        let code;
        let width;
        if (byte < 128) {
          code = byte;
          width = 1;
        } else if ((byte & 224) === 192) {
          code = byte & 31;
          width = 2;
        } else if ((byte & 240) === 224) {
          code = byte & 15;
          width = 3;
        } else if ((byte & 248) === 240) {
          code = byte & 7;
          width = 4;
        } else {
          out += String.fromCharCode(REPLACEMENT);
          i++;
          continue;
        }
        if (i + width > bytes.length) {
          out += String.fromCharCode(REPLACEMENT);
          break;
        }
        let malformed = false;
        for (let k = 1; k < width; k++) {
          const cont = bytes[i + k];
          if ((cont & 192) !== 128) {
            malformed = true;
            break;
          }
          code = code << 6 | cont & 63;
        }
        if (malformed || code > 1114111 || code >= 55296 && code <= 57343 || width === 2 && code < 128 || width === 3 && code < 2048 || width === 4 && code < 65536) {
          out += String.fromCharCode(REPLACEMENT);
          i++;
          continue;
        }
        if (code < 65536) {
          out += String.fromCharCode(code);
        } else {
          const astral = code - 65536;
          out += String.fromCharCode(55296 + (astral >> 10), 56320 + (astral & 1023));
        }
        i += width;
      }
      return out;
    }
  };
  if (typeof globalThis.TextEncoder === "undefined") globalThis.TextEncoder = PolyfillTextEncoder;
  if (typeof globalThis.TextDecoder === "undefined") globalThis.TextDecoder = PolyfillTextDecoder;

  // corebridge/js/host-prolog-engine.js
  function collapseTerm(term4) {
    if (term4 === null || term4 === void 0) return null;
    if (typeof term4 === "string" || typeof term4 === "number" || typeof term4 === "boolean") {
      return term4;
    }
    if (Array.isArray(term4)) return term4.length === 0 ? "[]" : ".";
    if (typeof term4 === "object" && typeof term4.functor === "string") return term4.functor;
    return String(term4);
  }
  var NativePrologEngine = class {
    constructor(id) {
      this.kind = "wasm";
      this._id = id;
      this._facts = /* @__PURE__ */ new Map();
      this._dynamic = /* @__PURE__ */ new Set();
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
        const atom3 = fact.match(/^([a-z_]\w*)\s*\.?$/);
        return atom3 ? `${atom3[1]}/0` : "";
      }
      const args = fact.slice(match[1].length + fact.slice(match[1].length).indexOf("(") + 1);
      let depth = 0;
      let arity = 1;
      for (let i = 0; i < args.length; i++) {
        const ch = args[i];
        if (ch === "(" || ch === "[") depth++;
        else if (ch === "]") depth--;
        else if (ch === ")") {
          if (depth === 0) break;
          depth--;
        } else if (ch === "," && depth === 0) arity++;
      }
      return `${match[1]}/${arity}`;
    }
    /** Issue `:- dynamic(sig).` once per signature — see the class header. */
    _ensureDynamic(signature) {
      if (!signature || this._dynamic.has(signature)) return;
      this._dynamic.add(signature);
      globalThis.__insimul_prolog_consult(this._id, `:- dynamic(${signature}).`);
    }
    /**
     * @param {string} fact term text, with or without a trailing `.`
     * @returns {Promise<boolean>} core's contract: whether the KB is loadable
     *   afterwards, NOT whether anything changed.
     */
    async assertFact(fact) {
      const normalized = String(fact).trim().replace(/\.\s*$/, "");
      if (!normalized) return true;
      const signature = this._signature(normalized);
      let bucket = this._facts.get(signature);
      if (!bucket) this._facts.set(signature, bucket = /* @__PURE__ */ new Set());
      if (bucket.has(`${normalized}.`)) return true;
      this._ensureDynamic(signature);
      const err = globalThis.__insimul_prolog_assert(this._id, normalized);
      if (err !== null) return false;
      bucket.add(`${normalized}.`);
      return true;
    }
    async assertFacts(facts) {
      let ok = true;
      for (const fact of facts) ok = await this.assertFact(fact) && ok;
      return ok;
    }
    async retractFact(fact) {
      const normalized = String(fact).trim().replace(/\.\s*$/, "");
      if (!normalized) return true;
      const bucket = this._facts.get(this._signature(normalized));
      if (!bucket || !bucket.has(`${normalized}.`)) return true;
      bucket.delete(`${normalized}.`);
      const res = globalThis.__insimul_prolog_retract(this._id, normalized);
      return typeof res !== "string";
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
    declareDynamic() {
      return unimplemented("declareDynamic");
    }
    addRule() {
      return unimplemented("addRule");
    }
    addRules() {
      return unimplemented("addRules");
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

  // @insimul/core/src/prolog/prolog-fact-parser.ts
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
  function parseTerm(text2) {
    text2 = text2.trim();
    if (!text2) return null;
    const match = text2.match(/^([a-z_][a-z0-9_]*)\s*\(([\s\S]*)\)$/);
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
  function parseArgList(text2) {
    const args = [];
    let current = "";
    let depth = 0;
    let inSingleQuote = false;
    let i = 0;
    while (i < text2.length) {
      const ch = text2[i];
      if (inSingleQuote) {
        if (ch === "'" && i + 1 < text2.length && text2[i + 1] === "'") {
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
  function parseArg(text2) {
    text2 = text2.trim();
    if (text2.startsWith("'") && text2.endsWith("'") && text2.length >= 2) {
      const inner = text2.slice(1, -1).replace(/''/g, "'");
      return { type: "string", value: inner };
    }
    if (/^-?[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?$/.test(text2)) {
      return { type: "number", value: parseFloat(text2) };
    }
    if (/^[A-Z_][A-Za-z0-9_]*$/.test(text2)) {
      return { type: "variable", value: text2 };
    }
    if (text2.startsWith("[") && text2.endsWith("]")) {
      const inner = text2.slice(1, -1).trim();
      if (!inner) return { type: "list", elements: [] };
      const elements = parseArgList(inner);
      return { type: "list", elements };
    }
    const compMatch = text2.match(/^([a-z_][a-z0-9_]*)\s*\(([\s\S]*)\)$/);
    if (compMatch) {
      const functor = compMatch[1];
      const innerArgs = parseArgList(compMatch[2]);
      return { type: "compound", functor, args: innerArgs };
    }
    return { type: "atom", value: text2 };
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

  // @insimul/core/src/radiant/radiant-engine.ts
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
      (whole2, slot) => slot in bindings ? String(bindings[slot]) : whole2
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
      const num2 = obj.args.find((a) => a.type === "number");
      if (num2 && num2.type === "number") return num2.value;
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

  // @insimul/core/src/radiant/base-templates.ts
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

  // @insimul/core/src/prolog/quest-hydrator.ts
  function hydrateQuestFromProlog(quest) {
    const content = quest?.content;
    if (!content || typeof content !== "string") return quest;
    const main = parseQuestFact(content);
    if (main) {
      quest.title = main.title;
      quest.questType = main.questType;
      quest.difficulty = main.difficulty;
      if (!quest.status) {
        quest.status = main.status;
      } else if (quest.status === "unavailable" && main.status === "available") {
        const prereqs2 = parsePrerequisites(content);
        const hasNoPrereqs = prereqs2.length === 0 || prereqs2.length === 1 && prereqs2[0] === "none";
        if (hasNoPrereqs) {
          quest.status = "available";
        }
      }
    }
    const objectives = parseObjectives(content);
    if (objectives.length > 0) {
      const targetLang = parseAtomFact(content, "quest_language");
      if (targetLang) {
        for (const obj of objectives) {
          if (obj.assessmentPhaseId && obj.description) {
            obj.description = enrichAssessmentDescription(obj.description, targetLang);
          }
        }
      }
      const existingObjs = Array.isArray(quest.objectives) ? quest.objectives : [];
      quest.objectives = objectives.map((obj) => {
        const existing = existingObjs.find((e) => e.id === obj.id);
        if (existing) {
          return {
            ...obj,
            completed: existing.completed ?? obj.completed,
            currentCount: existing.currentCount ?? obj.currentCount,
            current: existing.current ?? existing.currentCount ?? obj.currentCount
          };
        }
        return obj;
      });
    }
    quest.assignedTo = parseStringFact(content, "quest_assigned_to") ?? quest.assignedTo;
    quest.assignedBy = parseStringFact(content, "quest_assigned_by") ?? quest.assignedBy;
    quest.targetLanguage = parseAtomFact(content, "quest_language") ?? quest.targetLanguage;
    quest.questChainId = parseAtomFact(content, "quest_chain") ?? quest.questChainId ?? null;
    quest.parentQuestId = parseAtomFact(content, "quest_parent") ?? quest.parentQuestId ?? null;
    const chainOrder = parseNumberFact(content, "quest_chain_order");
    if (chainOrder !== null) quest.questChainOrder = chainOrder;
    const location = parseAtomOrStringFact(content, "quest_location");
    if (location && location !== "anywhere") {
      quest.locationName = quest.locationName || location;
    }
    const discoveryMethod = parseAtomFact(content, "quest_discovery");
    if (discoveryMethod) quest.discoveryMethod = discoveryMethod;
    const noticeText = parseStringFact(content, "quest_notice_text");
    if (noticeText) quest.noticeText = noticeText;
    const cefrLevel = parseAtomFact(content, "quest_cefr_level");
    if (cefrLevel) quest.cefrLevel = cefrLevel;
    const tags = parseAllAtomFacts(content, "quest_tag");
    if (tags.length > 0) quest.tags = tags;
    const rewards = parseRewards(content);
    if (rewards.experience) {
      quest.experienceReward = rewards.experience;
      delete rewards.experience;
    }
    if (Object.keys(rewards).length > 0) {
      quest.rewards = { ...quest.rewards, ...rewards };
    }
    const itemRewards = parseItemRewards(content);
    if (itemRewards.length > 0) quest.itemRewards = itemRewards;
    const skillRewards = parseSkillRewards(content);
    if (skillRewards.length > 0) quest.skillRewards = skillRewards;
    const unlocks = parseUnlocks(content);
    if (unlocks.length > 0) quest.unlocks = unlocks;
    const prereqs = parsePrerequisites(content);
    if (prereqs.length > 0 && !(prereqs.length === 1 && prereqs[0] === "none")) {
      quest.prerequisiteQuestIds = prereqs;
    }
    const activates = parseAllAtomFacts(content, "quest_activates");
    if (activates.length > 0) quest.activatesQuestIds = activates;
    const completionCriteria = parseCompletionCriteria(content);
    if (completionCriteria) quest.completionCriteria = completionCriteria;
    const failureConditions = parseFailureConditions(content);
    if (failureConditions) quest.failureConditions = failureConditions;
    return quest;
  }
  function parseQuestFact(content) {
    const m = content.match(/quest\(\s*\w+\s*,\s*'((?:[^'\\]|\\.)*)'\s*,\s*(\w+)\s*,\s*(\w+)\s*,\s*(\w+)\s*\)/);
    if (!m) return null;
    return { title: unescape(m[1]), questType: m[2], difficulty: m[3], status: m[4] };
  }
  function unescape(s) {
    return s.replace(/\\'/g, "'").replace(/\\\\/g, "\\");
  }
  function capitalize(s) {
    return s.charAt(0).toUpperCase() + s.slice(1);
  }
  function formatCountDescription(template, count) {
    const withCount = template.replace("{n}", String(count));
    if (count === 1) {
      return withCount.replace(/\(s\)/g, "").replace(/\(ies\)/g, "y");
    }
    return withCount.replace(/\(s\)/g, "s").replace(/\(ies\)/g, "ies");
  }
  function enrichAssessmentDescription(description, language) {
    const langCapitalized = capitalize(language);
    if (description.toLowerCase().includes(language.toLowerCase())) return description;
    const parenMatch = description.match(/^(.*?)(\s*\(.*\))$/);
    if (parenMatch) {
      return `${parenMatch[1]} in ${langCapitalized}${parenMatch[2]}`;
    }
    return `${description} in ${langCapitalized}`;
  }
  function buildExplicitDescription(phaseType, count, minWordCount) {
    if (phaseType.includes("initiate_conversation")) {
      return "Initiate a conversation with the marked NPC";
    }
    if (phaseType.includes("conversation")) {
      const turns = Math.max(count, 4);
      return `Complete the conversation exercise (at least ${turns} exchanges)`;
    }
    if (phaseType.includes("writing")) {
      const words = minWordCount || 20;
      return `Complete the writing exercise (at least ${words} words)`;
    }
    if (phaseType.includes("reading")) {
      return "Complete the reading comprehension exercise";
    }
    if (phaseType.includes("listening")) {
      return "Complete the listening comprehension exercise";
    }
    return capitalize(phaseType.replace(/_/g, " "));
  }
  function goalToDescription(functor, args) {
    const labels = {
      visit_location: "Visit",
      discover_location: "Discover",
      talk_to: "Talk to",
      collect: "Collect",
      defeat: "Defeat",
      deliver: "Deliver to",
      use_item: "Use",
      craft_item: "Craft",
      escort: "Escort",
      solve_puzzle: "Solve",
      gain_reputation: "Gain reputation with",
      reach_level: "Reach level",
      give_gift: "Give a gift to",
      equip_item: "Equip",
      drop_item: "Drop",
      accept_quest: "Accept quest",
      read_text: "Read",
      find_text: "Find texts",
      photograph: "Photograph"
    };
    const label = labels[functor] || capitalize(functor.replace(/_/g, " "));
    if (args.length === 0) return label;
    const mainArg = args[0] === "any" ? "" : ` ${args[0]}`;
    if (args.length > 1 && /^\d+$/.test(args[1])) {
      const count = parseInt(args[1]);
      if (count > 1) {
        if (functor === "collect") return `Collect ${count} ${args[0]}`;
        if (functor === "defeat") return `Defeat ${count} ${args[0]}`;
        if (functor === "craft_item") return `Craft ${count} ${args[0]}`;
        if (functor === "gain_reputation") return `Gain ${count} reputation with ${args[0]}`;
        if (functor === "photograph") return `Photograph ${count} ${args[0]}`;
        return `${label}${mainArg} (${count})`;
      }
    }
    return `${label}${mainArg}`.trim();
  }
  function unescapeObj(obj) {
    for (const key of Object.keys(obj)) {
      if (typeof obj[key] === "string") obj[key] = unescape(obj[key]);
    }
    return obj;
  }
  function parseObjectives(content) {
    const objectives = [];
    const pattern = /quest_objective\(\s*\w+\s*,\s*(\d+)\s*,\s*(.*)\)\s*\./g;
    let match;
    while ((match = pattern.exec(content)) !== null) {
      const index = parseInt(match[1]);
      const goalStr = match[2].trim();
      const parsed = parseObjectiveGoal(goalStr);
      if (parsed) {
        objectives.push({
          id: `obj_${index}`,
          ...unescapeObj(parsed),
          completed: false,
          currentCount: 0,
          current: 0
        });
      }
    }
    const descPattern = /% Objective (\d+):\s*(.*)/g;
    let descMatch;
    while ((descMatch = descPattern.exec(content)) !== null) {
      const idx = parseInt(descMatch[1]);
      const obj = objectives.find((o) => o.id === `obj_${idx}`);
      if (obj && !obj.description) {
        obj.description = descMatch[2].trim();
      }
    }
    const locPattern = /quest_objective_location\(\s*\w+\s*,\s*(\d+)\s*,\s*(.*)\)\s*\./g;
    let locMatch;
    while ((locMatch = locPattern.exec(content)) !== null) {
      const idx = parseInt(locMatch[1]);
      const locAtom = locMatch[2].trim().replace(/^'|'$/g, "");
      const obj = objectives.find((o) => o.id === `obj_${idx}`);
      if (obj) {
        obj.objectiveLocation = locAtom;
        const innerMatch = locAtom.match(/^(location|npc)\(\s*'((?:[^'\\]|\\.)*)'\s*\)$/);
        if (innerMatch) {
          const locType = innerMatch[1];
          const name = innerMatch[2].replace(/\\'/g, "'");
          if (locType === "location") {
            obj.locationName = name;
          } else if (locType === "npc") {
            if (!obj.npcName) obj.npcName = name;
            if (!obj.npcId) obj.npcId = name;
          }
        }
      }
    }
    const detailsPattern = /quest_objective_details\(\s*\w+\s*,\s*(\d+)\s*,\s*'((?:[^'\\]|\\.)*)'\s*\)\s*\./g;
    let detailsMatch;
    while ((detailsMatch = detailsPattern.exec(content)) !== null) {
      const idx = parseInt(detailsMatch[1]);
      const details = detailsMatch[2].replace(/\\'/g, "'").replace(/\\\\/g, "\\");
      const obj = objectives.find((o) => o.id === `obj_${idx}`);
      if (obj) {
        obj.details = details;
      }
    }
    return objectives;
  }
  function parseObjectiveGoal(goal) {
    const functorMatch = goal.match(/^(\w+)\(/);
    if (!functorMatch) {
      if (goal.trim() === "introduce_self") return { type: "introduce_self", description: "Introduce yourself", requiredCount: 1, required: 1 };
      if (goal.trim() === "complete_assessment") return { type: "complete_assessment", description: "Complete the assessment", requiredCount: 1, required: 1 };
      return null;
    }
    const functor = functorMatch[1];
    const argsStr = goal.slice(functor.length + 1, -1).trim();
    const args = [];
    let i = 0;
    while (i < argsStr.length) {
      if (argsStr[i] === " " || argsStr[i] === ",") {
        i++;
        continue;
      }
      if (argsStr[i] === "'") {
        let val = "";
        i++;
        while (i < argsStr.length) {
          if (argsStr[i] === "\\" && i + 1 < argsStr.length) {
            val += argsStr[i + 1];
            i += 2;
          } else if (argsStr[i] === "'") {
            i++;
            break;
          } else {
            val += argsStr[i];
            i++;
          }
        }
        args.push(val);
      } else if (argsStr[i] === "[") {
        const end = argsStr.indexOf("]", i);
        args.push(argsStr.slice(i, end + 1));
        i = end + 1;
      } else {
        let val = "";
        while (i < argsStr.length && argsStr[i] !== "," && argsStr[i] !== ")") {
          val += argsStr[i];
          i++;
        }
        args.push(val.trim());
      }
    }
    const twoArgGoals = {
      collect: "collect_item",
      defeat: "defeat_enemies",
      craft_item: "craft_item",
      gain_reputation: "gain_reputation",
      reach_level: "reach_level",
      photograph: "photograph_subject",
      physical_action: "physical_action",
      practice_grammar: "grammar_pattern"
    };
    if (twoArgGoals[functor] && args.length >= 2) {
      const target = args[0];
      const count = parseInt(args[1]) || 1;
      return { type: twoArgGoals[functor], description: goalToDescription(functor, args), target, requiredCount: count, required: count };
    }
    const singleArgGoals = {
      visit_location: "visit_location",
      discover_location: "discover_location",
      talk_to: "talk_to_npc",
      solve_puzzle: "solve_puzzle",
      use_item: "use_item",
      equip_item: "equip_item",
      drop_item: "drop_item",
      give_gift: "give_gift",
      read_text: "read_text",
      accept_quest: "accept_quest",
      escort: "escort_npc"
    };
    if (singleArgGoals[functor] && args.length >= 1) {
      const target = args[0];
      const count = args.length >= 2 ? parseInt(args[1]) || 1 : 1;
      let desc = goalToDescription(functor, args);
      if (functor === "talk_to" && count > 1) {
        desc = `Talk to ${target} (at least ${count} turns)`;
      }
      const result = { type: singleArgGoals[functor], description: desc, target, requiredCount: count, required: count };
      if (functor === "talk_to") result.npcId = target;
      return result;
    }
    if (functor === "deliver" && args.length >= 2) {
      return { type: "deliver_item", description: `Deliver ${args[0]} to ${args[1]}`, target: args[1], item: args[0], requiredCount: 1, required: 1 };
    }
    const countGoals = {
      conversation_turns: "Complete {n} conversation turn(s)",
      examine_object: "Examine {n} object(s)",
      read_sign: "Read {n} sign(s)",
      write_response: "Write {n} response(s)",
      listen_and_repeat: "Listen and repeat {n} phrase(s)",
      pronunciation_check: "Complete {n} pronunciation check(s)",
      identify_object: "Identify {n} object(s)",
      order_food: "Order {n} food item(s)",
      haggle_price: "Haggle {n} price(s)",
      buy_item: "Buy {n} item(s)",
      sell_item: "Sell {n} item(s)",
      ask_for_directions: "Ask for directions {n} time(s)",
      comprehension_quiz: "Answer {n} quiz question(s) correctly",
      translation_challenge: "Complete {n} translation(s) correctly",
      follow_directions: "Follow {n} direction(s)",
      listening_comprehension: "Answer {n} listening question(s) correctly",
      collect_vocabulary: "Collect {n} vocabulary word(s)",
      collect_clue: "Collect {n} clue(s)",
      vocabulary_activities: "Complete {n} vocabulary activit(ies)",
      conversation_activities: "Complete {n} conversation activit(ies)",
      grammar_activities: "Demonstrate {n} grammar pattern(s)",
      sustained_conversation: "Sustain a conversation for {n} turn(s)",
      master_words: "Master {n} vocabulary word(s)",
      learn_new_words: "Learn {n} new word(s)",
      find_vocabulary_items: "Find {n} vocabulary item(s)",
      find_text: "Find {n} text(s)",
      combat_action: "Perform {n} combat action(s)",
      observe_activity: "Observe {n} activit(ies)",
      build_friendship: "Build friendship (reach {n} strength)",
      learn_words_count: "Learn {n} vocabulary word(s)",
      survive: "Survive for {n} second(s)",
      visit_location: "Visit {n} location(s)"
    };
    if (countGoals[functor] && args.length >= 1 && /^\d+(\.\d+)?$/.test(args[0])) {
      const count = functor === "build_friendship" ? parseFloat(args[0]) : parseInt(args[0]);
      const result = { type: functor, description: formatCountDescription(countGoals[functor], count), requiredCount: count, required: count };
      if (functor === "observe_activity" && args.length >= 2) {
        result.observeDurationRequired = parseInt(args[1]) || 5;
      }
      if (functor === "build_friendship") {
        result.requiredStrength = count;
        result.requiredCount = 1;
        result.required = 1;
      }
      return result;
    }
    if (functor === "learn_words" && args.length === 1 && args[0].startsWith("[")) {
      const words = args[0].slice(1, -1).split(",").map((w) => w.trim().replace(/'/g, ""));
      return { type: "use_vocabulary", description: `Learn words: ${words.join(", ")}`, targetWords: words, requiredCount: words.length, required: words.length };
    }
    if (functor === "assessment_phase" && args.length >= 2) {
      const count = args.length >= 3 ? parseInt(args[2]) || 1 : 1;
      const minWordCount = args.length >= 4 ? parseInt(args[3]) || void 0 : void 0;
      const phaseType = args[0];
      const desc = buildExplicitDescription(phaseType, count, minWordCount);
      const result = {
        type: phaseType,
        description: desc,
        assessmentPhaseId: phaseType,
        completionTrigger: args[1],
        requiredCount: count,
        required: count
      };
      if (minWordCount) result.minWordCount = minWordCount;
      return result;
    }
    if (functor === "objective" && args.length >= 1) {
      let desc = args[0];
      const stripped = desc.replace(/[Oo]bjective\(\s*'?/g, "").replace(/'?\s*\)(?:\s*'\s*\))*\s*$/g, "").replace(/^'+|'+$/g, "").trim();
      const buriedTerm = stripped.match(/^(visit[\s_]location|discover[\s_]location|talk[\s_]to|collect|deliver|escort)\s*\(\s*'?/i);
      if (buriedTerm) {
        const funcName = buriedTerm[1].replace(/\s/g, "_").toLowerCase();
        const afterParen = stripped.slice(buriedTerm[0].length);
        const targetName = afterParen.replace(/[')\s]+$/g, "").trim();
        if (targetName) {
          return { type: funcName, description: goalToDescription(funcName, [targetName]), target: targetName, requiredCount: 1, required: 1 };
        }
      }
      return { type: "objective", description: capitalize(desc), requiredCount: 1, required: 1 };
    }
    return { type: functor || "custom", description: capitalize(goal.replace(/_/g, " ").replace(/'/g, "").replace(/\(.*\)/, "").trim()), requiredCount: 1, required: 1 };
  }
  function parseStringFact(content, predicate) {
    const m = content.match(new RegExp(`${predicate}\\(\\s*\\w+\\s*,\\s*'((?:[^'\\\\]|\\\\.)*)'\\s*\\)`));
    return m ? unescape(m[1]) : null;
  }
  function parseAtomFact(content, predicate) {
    const m = content.match(new RegExp(`${predicate}\\(\\s*\\w+\\s*,\\s*(\\w+)\\s*\\)`));
    return m ? m[1] : null;
  }
  function parseAtomOrStringFact(content, predicate) {
    return parseStringFact(content, predicate) ?? parseAtomFact(content, predicate);
  }
  function parseNumberFact(content, predicate) {
    const m = content.match(new RegExp(`${predicate}\\(\\s*\\w+\\s*,\\s*(\\d+(?:\\.\\d+)?)\\s*\\)`));
    return m ? parseFloat(m[1]) : null;
  }
  function parseAllAtomFacts(content, predicate) {
    const results = [];
    const pattern = new RegExp(`${predicate}\\(\\s*\\w+\\s*,\\s*(\\w+)\\s*\\)`, "g");
    let m;
    while ((m = pattern.exec(content)) !== null) {
      results.push(m[1]);
    }
    return results;
  }
  function parseRewards(content) {
    const rewards = {};
    const pattern = /quest_reward\(\s*\w+\s*,\s*(\w+)\s*,\s*(\d+(?:\.\d+)?)\s*\)/g;
    let m;
    while ((m = pattern.exec(content)) !== null) {
      rewards[m[1]] = parseFloat(m[2]);
    }
    return rewards;
  }
  function parseItemRewards(content) {
    const items = [];
    const pattern = /quest_item_reward\(\s*\w+\s*,\s*(?:'((?:[^'\\\\]|\\\\.)*)'|(\w+))\s*,\s*(\d+)\s*\)/g;
    let m;
    while ((m = pattern.exec(content)) !== null) {
      items.push({ itemName: m[1] || m[2], quantity: parseInt(m[3]) });
    }
    return items;
  }
  function parseSkillRewards(content) {
    const skills = [];
    const pattern = /quest_skill_reward\(\s*\w+\s*,\s*(?:'((?:[^'\\\\]|\\\\.)*)'|(\w+))\s*,\s*(\d+)\s*\)/g;
    let m;
    while ((m = pattern.exec(content)) !== null) {
      skills.push({ skillName: m[1] || m[2], level: parseInt(m[3]) });
    }
    return skills;
  }
  function parseUnlocks(content) {
    const unlocks = [];
    const pattern = /quest_unlock\(\s*\w+\s*,\s*(\w+)\s*,\s*(?:'((?:[^'\\\\]|\\\\.)*)'|(\w+))\s*\)/g;
    let m;
    while ((m = pattern.exec(content)) !== null) {
      unlocks.push({ type: m[1], name: m[2] || m[3] });
    }
    return unlocks;
  }
  function parsePrerequisites(content) {
    const prereqs = [];
    const pattern = /quest_prerequisite\(\s*\w+\s*,\s*(\w+)\s*\)/g;
    let m;
    while ((m = pattern.exec(content)) !== null) {
      if (m[1] !== "none") prereqs.push(m[1]);
    }
    return prereqs;
  }
  function parseCompletionCriteria(content) {
    const m = content.match(/quest_completion\(\s*\w+\s*,\s*(.*?)\)\s*\./);
    if (!m) return null;
    const goal = m[1].trim();
    if (goal === "all_objectives_complete") {
      return { type: "all_objectives", description: "Complete all objectives" };
    }
    const vocabMatch = goal.match(/^vocabulary_usage\(\s*\[(.*?)\]\s*,\s*(\d+)\s*\)$/);
    if (vocabMatch) {
      const words = vocabMatch[1].split(",").map((w) => w.trim().replace(/'/g, ""));
      return { type: "vocabulary_usage", requiredWords: words, requiredCount: parseInt(vocabMatch[2]) };
    }
    const vocabCountMatch = goal.match(/^vocabulary_count\(\s*(\d+)\s*\)$/);
    if (vocabCountMatch) {
      return { type: "vocabulary_usage", requiredCount: parseInt(vocabCountMatch[1]) };
    }
    const convMatch = goal.match(/^conversation_turns\(\s*(\d+)\s*\)$/);
    if (convMatch) {
      return { type: "conversation_turns", requiredTurns: parseInt(convMatch[1]) };
    }
    return { type: "all_objectives", description: "Complete all objectives" };
  }
  function parseFailureConditions(content) {
    const m = content.match(/quest_failure_condition\(\s*\w+\s*,\s*(.*?)\)\s*\./);
    if (!m) return null;
    const goal = m[1].trim();
    if (goal === "timeout") return { type: "timeout" };
    if (goal === "player_death") return { type: "player_death" };
    const repMatch = goal.match(/^reputation_below\(\s*(\d+)\s*\)$/);
    if (repMatch) return { type: "reputation_below", threshold: parseInt(repMatch[1]) };
    return { type: "custom", description: goal };
  }

  // @insimul/core/scripts/quest-golden-manifest.ts
  function projectHydratedQuest(q) {
    const out = {};
    const put = (k, v) => {
      if (v !== void 0 && v !== null) out[k] = v;
    };
    put("title", q.title);
    put("questType", q.questType);
    put("difficulty", q.difficulty);
    put("status", q.status);
    put("targetLanguage", q.targetLanguage);
    put("assignedTo", q.assignedTo);
    put("assignedBy", q.assignedBy);
    put("experienceReward", q.experienceReward);
    if (Array.isArray(q.tags) && q.tags.length > 0) out.tags = q.tags;
    if (Array.isArray(q.prerequisiteQuestIds) && q.prerequisiteQuestIds.length > 0) {
      out.prerequisiteQuestIds = q.prerequisiteQuestIds;
    }
    if (q.completionCriteria) out.completionCriteria = q.completionCriteria;
    if (Array.isArray(q.objectives) && q.objectives.length > 0) {
      out.objectives = q.objectives.map((o) => {
        const obj = {
          id: o.id,
          type: o.type,
          description: o.description,
          requiredCount: o.requiredCount
        };
        if (o.target !== void 0 && o.target !== null) obj.target = o.target;
        if (o.npcId !== void 0 && o.npcId !== null) obj.npcId = o.npcId;
        return obj;
      });
    }
    return out;
  }
  function computeHydrationExpected(input) {
    const seed = { content: input.content };
    if (input.status !== void 0) seed.status = input.status;
    return projectHydratedQuest(hydrateQuestFromProlog(seed));
  }
  function radiantTick(params) {
    const { quests, maxOffering, ticks } = params;
    const offered = /* @__PURE__ */ new Set();
    const facts = [];
    for (let t = 0; t < ticks; t++) {
      const candidates = quests.filter(
        (q) => Array.isArray(q.tags) && q.tags.includes("radiant") && q.status === "available" && !offered.has(q.id)
      ).map((q) => q.id).sort();
      for (const id of candidates.slice(0, Math.max(0, maxOffering))) {
        offered.add(id);
        facts.push({ predicate: "quest_offered", args: [id, t] });
      }
    }
    return facts;
  }

  // @insimul/core/src/prolog/prolog-fact-serializer.ts
  var ATOM_RE2 = /^[a-z][a-zA-Z0-9_]*$/;
  function quoteAtom(s) {
    return `'${s.replace(/\\/g, "\\\\").replace(/'/g, "\\'")}'`;
  }
  function serializeArg(arg) {
    if (typeof arg === "number") {
      return Number.isFinite(arg) ? String(arg) : quoteAtom(String(arg));
    }
    if (arg === "") return quoteAtom("");
    if (ATOM_RE2.test(arg)) return arg;
    return quoteAtom(arg);
  }
  function serializedFactToProlog(fact) {
    const args = fact.args.map(serializeArg).join(", ");
    return `${fact.predicate}(${args}).`;
  }

  // @insimul/core/src/ai/deterministic-stream.ts
  function hashSeedString(text2) {
    let h = 2166136261 >>> 0;
    for (let i = 0; i < text2.length; i++) {
      h ^= text2.charCodeAt(i);
      h = Math.imul(h, 16777619);
    }
    return h >>> 0;
  }
  function mulberry322(seed) {
    let a = seed >>> 0;
    return function next() {
      a = a + 1831565813 | 0;
      let t = Math.imul(a ^ a >>> 15, 1 | a);
      t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t;
      return ((t ^ t >>> 14) >>> 0) / 4294967296;
    };
  }
  function streamKey(parts) {
    return parts.map((part) => {
      const text2 = String(part);
      return `${text2.length}:${text2}`;
    }).join("");
  }
  function derivedStream(...parts) {
    return mulberry322(hashSeedString(streamKey(parts)));
  }
  function derivedValue(...parts) {
    return derivedStream(...parts)();
  }
  var DETERMINISTIC_DECIMALS = 4;
  function roundDeterministic(value, decimals = DETERMINISTIC_DECIMALS) {
    const scale = 10 ** decimals;
    return Math.round(value * scale) / scale;
  }
  function compareIds(a, b) {
    return a === b ? 0 : a < b ? -1 : 1;
  }
  function clamp01(value) {
    return value < 0 ? 0 : value > 1 ? 1 : value;
  }

  // @insimul/core/src/stamina/stamina.ts
  var STAMINA_THRESHOLD_NAMES = Object.freeze(["winded", "exhausted"]);
  var DEFAULT_STAMINA_TUNING = Object.freeze({
    maxStamina: 100,
    recoveryRate: 5,
    combatRecoveryRate: 0,
    encumberedRecoveryMultiplier: 0.5,
    windedPercent: 40,
    exhaustedPercent: 15
  });
  function staminaStateOf(current, max, tuning) {
    if (!(max > 0)) return "fresh";
    if (current * 100 <= max * tuning.exhaustedPercent) return "exhausted";
    if (current * 100 <= max * tuning.windedPercent) return "winded";
    return "fresh";
  }
  function canAffordStamina(current, cost) {
    return current >= cost;
  }
  function spendStamina(input) {
    const { current, max, tuning } = input;
    const cost = Math.max(0, Math.floor(input.cost));
    const stateBefore = staminaStateOf(current, max, tuning);
    if (!canAffordStamina(current, cost)) {
      return {
        affordable: false,
        cost,
        before: current,
        after: current,
        max,
        spent: 0,
        stateBefore,
        state: stateBefore,
        becameWinded: false,
        becameExhausted: false
      };
    }
    const after = Math.max(0, current - cost);
    const state = staminaStateOf(after, max, tuning);
    return {
      affordable: true,
      cost,
      before: current,
      after,
      max,
      spent: current - after,
      stateBefore,
      state,
      becameWinded: state === "winded" && stateBefore === "fresh",
      becameExhausted: state === "exhausted" && stateBefore !== "exhausted"
    };
  }
  function staminaRegenRate(input) {
    const base = Math.max(0, input.rate ?? input.tuning.recoveryRate);
    if (input.inCombat) return Math.max(0, input.tuning.combatRecoveryRate);
    if (input.encumbered) return Math.floor(base * input.tuning.encumberedRecoveryMultiplier);
    return base;
  }
  function regenerateStamina(input) {
    const rate = staminaRegenRate(input);
    const ticks = Math.max(0, input.ticks);
    const recovered = Math.max(0, Math.min(input.max - input.current, Math.floor(rate * ticks)));
    const after = input.current + recovered;
    return {
      before: input.current,
      after,
      max: input.max,
      rate,
      recovered,
      state: staminaStateOf(after, input.max, input.tuning)
    };
  }

  // @insimul/core/src/combat/resolution.ts
  var DEFAULT_COMBAT_TUNING = Object.freeze({
    baseDamage: 10,
    damageVariance: 0.2,
    criticalChance: 0.1,
    criticalMultiplier: 2,
    blockReduction: 0.5,
    dodgeChance: 0.05,
    resistMultiplier: 0.5,
    vulnerableMultiplier: 1.5,
    deathAtZero: true
  });
  function roll(input, phase) {
    return derivedValue(
      input.seed,
      input.tick,
      input.attacker.id,
      input.defender.id,
      input.action.id,
      phase
    );
  }
  function roundHalfUp(value) {
    return Math.floor(value + 0.5);
  }
  function has(list, value) {
    return value !== void 0 && list !== void 0 && list.includes(value);
  }
  function refusal(input, outcome, reason, spent = 0) {
    return {
      attackerId: input.attacker.id,
      targetId: input.defender.id,
      actionId: input.action.id,
      outcome,
      reason,
      isCritical: false,
      isBlocked: false,
      isResisted: false,
      isVulnerable: false,
      damage: 0,
      targetHealthBefore: input.defender.health,
      targetHealthAfter: input.defender.health,
      targetMaxHealth: input.defender.maxHealth,
      incapacitated: false,
      killed: false,
      statusesApplied: [],
      staminaCost: staminaCostOf(input),
      staminaSpent: spent,
      attackerStaminaAfter: staminaAfter(input, spent)
    };
  }
  function staminaCostOf(input) {
    return Math.max(0, Math.floor(input.action.staminaCost ?? 0));
  }
  function staminaAfter(input, spent) {
    const stamina = input.attacker.stamina;
    return stamina === void 0 ? void 0 : Math.max(0, stamina.current - spent);
  }
  function resolveAttack(input) {
    const { attacker, defender, action, tuning } = input;
    if (input.legality && !input.legality.permitted) {
      return refusal(input, "refused", input.legality.reason ?? "not_permitted");
    }
    if (!attacker.alive) return refusal(input, "refused", "attacker_dead");
    if (attacker.incapacitated) return refusal(input, "refused", "attacker_incapacitated");
    if (!defender.alive) return refusal(input, "refused", "target_dead");
    if (defender.incapacitated) return refusal(input, "refused", "target_incapacitated");
    const staminaCost = staminaCostOf(input);
    if (staminaCost > 0 && attacker.stamina !== void 0 && !canAffordStamina(attacker.stamina.current, staminaCost)) {
      return refusal(input, "exhausted", "insufficient_stamina");
    }
    const range = action.range ?? attacker.weapon?.range;
    if (range !== void 0 && input.separation > range) {
      return refusal(input, "out_of_reach", "beyond_reach");
    }
    if (action.delivery === "projectile" && input.lineOfFire && !input.lineOfFire.clear) {
      return refusal(input, "missed", "line_blocked", staminaCost);
    }
    const accuracy = action.accuracy ?? 1;
    if (accuracy < 1 && roll(input, "accuracy") >= accuracy) {
      return refusal(input, "missed", "missed", staminaCost);
    }
    const dodgeChance = tuning.dodgeChance + (defender.dodgeBonus ?? 0);
    if (dodgeChance > 0 && roll(input, "dodge") < dodgeChance) {
      return refusal(input, "dodged", "dodged", staminaCost);
    }
    const damageType = action.damageType ?? attacker.weapon?.damageType;
    const isResisted = has(defender.resists, damageType);
    const isVulnerable = has(defender.vulnerableTo, damageType);
    const base = action.damage ?? attacker.weapon?.damage ?? tuning.baseDamage;
    const swing = tuning.damageVariance * (2 * roll(input, "variance") - 1);
    const varied = roundDeterministic(base * (1 + swing));
    const isCritical = tuning.criticalChance > 0 && roll(input, "critical") < tuning.criticalChance;
    const critical = roundDeterministic(isCritical ? varied * tuning.criticalMultiplier : varied);
    let typed = critical;
    if (isResisted) typed *= tuning.resistMultiplier;
    if (isVulnerable) typed *= tuning.vulnerableMultiplier;
    typed = roundDeterministic(typed);
    const isBlocked = defender.blocking === true && tuning.blockReduction > 0;
    const blocked = roundDeterministic(isBlocked ? typed * (1 - tuning.blockReduction) : typed);
    const mitigated = roundDeterministic(blocked - (defender.armor ?? 0));
    const damage = Math.max(0, roundHalfUp(mitigated));
    const before = defender.health;
    const after = Math.max(0, before - damage);
    const wentDown = after === 0 && before > 0;
    const lethal = action.lethal ?? true;
    const killed = wentDown && lethal && tuning.deathAtZero;
    return {
      attackerId: attacker.id,
      targetId: defender.id,
      actionId: action.id,
      outcome: "hit",
      damageType,
      isCritical,
      isBlocked,
      isResisted,
      isVulnerable,
      breakdown: { base, varied, critical, typed, blocked, mitigated },
      damage,
      targetHealthBefore: before,
      targetHealthAfter: after,
      targetMaxHealth: defender.maxHealth,
      incapacitated: wentDown,
      killed,
      statusesApplied: damage > 0 ? action.appliesStatus ?? [] : [],
      staminaCost,
      staminaSpent: staminaCost,
      attackerStaminaAfter: staminaAfter(input, staminaCost)
    };
  }
  var DEFAULT_DEFENSE_STATUS = "evading";
  function resolveDefense(input) {
    const { actor, action } = input;
    const profile = action.defense;
    const staminaCost = Math.max(0, Math.floor(action.staminaCost ?? 0));
    const refused = (outcome, reason) => ({
      actorId: actor.id,
      actionId: action.id,
      outcome,
      reason,
      status: profile?.status ?? DEFAULT_DEFENSE_STATUS,
      magnitude: 0,
      evasionBonus: 0,
      window: 0,
      recovery: profile?.recovery,
      staminaCost,
      staminaSpent: 0,
      actorStaminaAfter: actor.stamina?.current
    });
    if (input.legality && !input.legality.permitted) {
      return refused("refused", input.legality.reason ?? "not_permitted");
    }
    if (!profile) return refused("refused", "not_a_defense");
    if (!actor.alive) return refused("refused", "actor_dead");
    if (actor.incapacitated) return refused("refused", "actor_incapacitated");
    if (staminaCost > 0 && actor.stamina !== void 0 && !canAffordStamina(actor.stamina.current, staminaCost)) {
      return refused("exhausted", "insufficient_stamina");
    }
    const evasionBonus = Math.max(0, profile.evasionBonus);
    return {
      actorId: actor.id,
      actionId: action.id,
      outcome: "evading",
      status: profile.status ?? DEFAULT_DEFENSE_STATUS,
      // `has_status/3`'s Magnitude is integral, so the bonus is carried as
      // percentage points. Half-up, like every other rounding here.
      magnitude: roundHalfUp(evasionBonus * 100),
      evasionBonus,
      window: profile.window,
      recovery: profile.recovery,
      staminaCost,
      staminaSpent: staminaCost,
      actorStaminaAfter: actor.stamina === void 0 ? void 0 : Math.max(0, actor.stamina.current - staminaCost)
    };
  }

  // @insimul/core/src/combat/combat-facts.ts
  var COMBAT_RESOLUTION_PREDICATES = Object.freeze([
    "health/3",
    "alive/1",
    "incapacitated/1",
    "in_combat/1",
    "combat_target/2",
    "has_status/3",
    "threat/3"
  ]);
  function threatAfterDamage(damage, maxHealth, prior = 0) {
    if (damage <= 0 || maxHealth <= 0) return clampThreat(prior);
    return clampThreat(prior + Math.floor(100 * damage / maxHealth));
  }
  function clampThreat(level) {
    if (!Number.isFinite(level) || level < 0) return 0;
    return level > 100 ? 100 : Math.floor(level);
  }
  function attackWasMade(resolution) {
    return resolution.outcome !== "refused" && resolution.outcome !== "exhausted";
  }
  function resolutionFacts(resolution, options = {}) {
    const delta = { retract: [], assert: [] };
    if (!attackWasMade(resolution)) return delta;
    const { attackerId, targetId } = resolution;
    if (options.enterCombat !== false) {
      delta.assert.push({ predicate: "in_combat", args: [attackerId] });
      delta.assert.push({ predicate: "in_combat", args: [targetId] });
      delta.assert.push({ predicate: "combat_target", args: [attackerId, targetId] });
    }
    if (resolution.damage > 0) {
      delta.retract.push({
        predicate: "health",
        args: [targetId, resolution.targetHealthBefore, resolution.targetMaxHealth]
      });
      delta.assert.push({
        predicate: "health",
        args: [targetId, resolution.targetHealthAfter, resolution.targetMaxHealth]
      });
    }
    for (const applied of resolution.statusesApplied) {
      delta.assert.push({
        predicate: "has_status",
        args: [targetId, applied.status, applied.magnitude]
      });
    }
    if (options.threat !== void 0) {
      if (options.priorThreat !== void 0) {
        delta.retract.push({ predicate: "threat", args: [targetId, attackerId, clampThreat(options.priorThreat)] });
      }
      delta.assert.push({ predicate: "threat", args: [targetId, attackerId, clampThreat(options.threat)] });
    }
    if (resolution.incapacitated || resolution.killed) {
      delta.assert.push({ predicate: "incapacitated", args: [targetId] });
      delta.retract.push({ predicate: "in_combat", args: [targetId] });
      delta.retract.push({ predicate: "combat_target", args: [attackerId, targetId] });
      delta.assert = delta.assert.filter(
        (fact) => !(fact.predicate === "in_combat" && fact.args[0] === targetId)
      );
      delta.assert = delta.assert.filter(
        (fact) => !(fact.predicate === "combat_target" && fact.args[1] === targetId)
      );
    }
    if (resolution.killed) {
      delta.retract.push({ predicate: "alive", args: [targetId] });
    }
    return delta;
  }
  function defenseFacts(resolution) {
    const delta = { retract: [], assert: [] };
    if (resolution.outcome !== "evading") return delta;
    delta.assert.push({
      predicate: "has_status",
      args: [resolution.actorId, resolution.status, resolution.magnitude]
    });
    return delta;
  }
  function defenseEndFacts(actorId, status, magnitude) {
    return {
      retract: [{ predicate: "has_status", args: [actorId, status, magnitude] }],
      assert: []
    };
  }

  // @insimul/core/src/combat/action-table.ts
  var COMBAT_ACTION_CATEGORY = "combat";
  function combatActionFrom(row, columns) {
    const id = columns?.id ?? row?.id;
    if (!id) throw new Error("combatActionFrom: an action row must have an id");
    const range = firstNumber(columns?.range, positive(row?.range));
    const staminaCost = firstNumber(columns?.staminaCost, positive(row?.energyCost));
    const action = { id };
    if (columns?.damage !== void 0) action.damage = columns.damage;
    if (columns?.damageType !== void 0) action.damageType = columns.damageType;
    if (range !== void 0) action.range = range;
    if (columns?.accuracy !== void 0) action.accuracy = columns.accuracy;
    if (columns?.delivery !== void 0) action.delivery = columns.delivery;
    if (staminaCost !== void 0) action.staminaCost = staminaCost;
    if (columns?.lethal !== void 0) action.lethal = columns.lethal;
    if (columns?.appliesStatus !== void 0) {
      action.appliesStatus = columns.appliesStatus.map(
        (applied) => ({ ...applied })
      );
    }
    if (columns?.defense !== void 0) action.defense = { ...columns.defense };
    return action;
  }
  var CombatActionTable = class {
    constructor(actions = []) {
      __publicField(this, "rows", /* @__PURE__ */ new Map());
      for (const action of actions) this.define(action);
    }
    /**
     * Add or replace one row. Returns the row as stored, so a caller that built one
     * from authored data can assert on what the table actually holds.
     */
    define(action) {
      const stored = { ...action };
      this.rows.set(stored.id, stored);
      return stored;
    }
    /** Add or replace one row from authored columns plus, optionally, its shared row. */
    defineAuthored(columns, row) {
      return this.define(combatActionFrom(row, columns));
    }
    get(actionId) {
      const row = this.rows.get(actionId);
      return row === void 0 ? void 0 : { ...row };
    }
    has(actionId) {
      return this.rows.has(actionId);
    }
    /** Every action id, in the order the rows were defined. */
    ids() {
      return [...this.rows.keys()];
    }
    /** Every row, in the order they were defined. */
    all() {
      return [...this.rows.values()].map((row) => ({ ...row }));
    }
    get size() {
      return this.rows.size;
    }
    /**
     * Load a world's rows: every action the creator gave combat columns to, plus
     * every action block row already in the `combat` category.
     *
     * The second half is what stops a world that authored no `CombatIR.actions` from
     * having an empty table — an action the creator filed under `combat` with a
     * range and an energy cost is a melee attack, and that is a complete row.
     * Returns how many rows were loaded.
     */
    loadFromIR(actions = [], combat) {
      const columnsById = /* @__PURE__ */ new Map();
      for (const columns of combat?.actions ?? []) columnsById.set(columns.id, columns);
      let loaded = 0;
      const rowsById = /* @__PURE__ */ new Map();
      for (const row of actions) {
        rowsById.set(row.id, row);
        if (!columnsById.has(row.id) && !isCombatRow(row)) continue;
        this.define(combatActionFrom(row, columnsById.get(row.id)));
        loaded += 1;
      }
      for (const [id, columns] of columnsById) {
        if (rowsById.has(id)) continue;
        this.define(combatActionFrom(void 0, columns));
        loaded += 1;
      }
      return loaded;
    }
    /** Every row that crosses the space to reach its target — the ranged ones. */
    projectileActions() {
      return this.all().filter((row) => row.delivery === "projectile");
    }
    /** Every row that grants its own actor evasion — the dodges. */
    defensiveActions() {
      return this.all().filter((row) => row.defense !== void 0);
    }
  };
  function isCombatRow(row) {
    return row.category === COMBAT_ACTION_CATEGORY || row.actionType === COMBAT_ACTION_CATEGORY;
  }
  function combatActionFacts(action) {
    if (action.range === void 0 || !Number.isFinite(action.range)) return [];
    return [{ predicate: "action_range", args: [action.id, action.range] }];
  }
  function positive(value) {
    return typeof value === "number" && Number.isFinite(value) && value > 0 ? value : void 0;
  }
  function firstNumber(...values) {
    for (const value of values) {
      if (typeof value === "number" && Number.isFinite(value)) return value;
    }
    return void 0;
  }

  // @insimul/core/src/game-engine/logic/CombatResolver.ts
  var CombatResolver = class {
    constructor(config) {
      __publicField(this, "engine");
      __publicField(this, "seed");
      __publicField(this, "tuning");
      __publicField(this, "combat");
      __publicField(this, "stamina");
      __publicField(this, "trajectory");
      __publicField(this, "eventBus");
      __publicField(this, "combatants", /* @__PURE__ */ new Map());
      __publicField(this, "defenses", /* @__PURE__ */ new Map());
      /** The world's authored action table. Empty until a world loads one. */
      __publicField(this, "actions");
      this.engine = config.engine;
      this.seed = config.seed;
      this.tuning = config.tuning ?? { ...DEFAULT_COMBAT_TUNING };
      this.combat = config.combat;
      this.stamina = config.stamina;
      this.actions = config.actions ?? new CombatActionTable();
      this.trajectory = config.trajectory ?? config.host?.trajectory;
      this.eventBus = config.eventBus;
      if (config.state) this.restore(config.state);
    }
    setEventBus(bus) {
      this.eventBus = bus;
    }
    /** Whether a host wired {@link ICombatSystem}. False means decisions are tracked only. */
    hasCombatSystem() {
      return this.combat !== void 0;
    }
    /**
     * Whether a host wired {@link ITrajectoryProbe}. False means nothing obstructs a
     * shot — the documented fallback, and the mode a turn-based or headless world
     * runs in.
     */
    hasTrajectoryProbe() {
      return this.trajectory !== void 0;
    }
    /** The world's authored numbers, as this instance read them. */
    getTuning() {
      return { ...this.tuning };
    }
    // ── Roster ─────────────────────────────────────────────────────────────
    /** Add or replace a combatant. Also registers it with the host's system, if any. */
    register(entity) {
      const state = {
        id: entity.id,
        kind: entity.kind ?? "entity",
        health: entity.health,
        maxHealth: entity.maxHealth,
        alive: entity.alive ?? true,
        incapacitated: entity.incapacitated ?? false,
        statuses: [],
        threat: {},
        weapon: entity.weapon,
        armor: entity.armor,
        resists: entity.resists,
        vulnerableTo: entity.vulnerableTo,
        dodgeBonus: entity.dodgeBonus,
        blocking: entity.blocking
      };
      this.combatants.set(entity.id, state);
      this.combat?.registerEntity({
        id: state.id,
        name: state.id,
        health: state.health,
        maxHealth: state.maxHealth,
        damage: state.weapon?.damage
      });
      return state;
    }
    unregister(entityId) {
      this.combatants.delete(entityId);
      this.defenses.delete(entityId);
      this.combat?.unregisterEntity(entityId);
    }
    get(entityId) {
      return this.combatants.get(entityId);
    }
    /** Every combatant, in registration order. */
    roster() {
      return [...this.combatants.values()];
    }
    /**
     * Update the stat half of a registration — what is worn, what is held, what is
     * being guarded against. Called when equipment changes, never on a tick.
     */
    setProfile(entityId, patch) {
      const state = this.combatants.get(entityId);
      if (!state) return;
      Object.assign(state, patch);
    }
    /** What this entity currently fears the other one at, 0–100. */
    threatOf(entityId, towardId) {
      return this.combatants.get(entityId)?.threat[towardId] ?? 0;
    }
    // ── The decision ───────────────────────────────────────────────────────
    /**
     * Resolve one attack, apply what follows, and report it.
     *
     * Order: ask the rules layer, resolve purely, then apply. Nothing is written
     * before the resolution exists, so a refused or missed attack cannot leave a
     * half-applied state behind.
     */
    async attack(request) {
      const attacker = this.combatants.get(request.attackerId);
      const defender = this.combatants.get(request.targetId);
      if (!attacker || !defender) {
        throw new Error(
          `CombatResolver.attack: ${!attacker ? request.attackerId : request.targetId} is not a registered combatant`
        );
      }
      const action = this.actionFor(request.action);
      const legality = await this.askLegality(attacker.id, defender.id);
      const lineOfFire = legality?.permitted === false ? void 0 : await this.askLineOfFire(attacker.id, defender.id, action);
      const resolution = resolveAttack({
        attacker: snapshot(attacker, this.stamina),
        defender: snapshot(defender, this.stamina, this.defenses.get(defender.id)),
        action,
        tuning: this.tuning,
        separation: request.separation ?? lineOfFire?.separation ?? 0,
        seed: this.seed,
        tick: request.tick,
        legality,
        lineOfFire
      });
      const stamina = await this.paySwing(attacker.id, resolution);
      const facts = this.applyResolution(attacker, defender, resolution);
      const applied = await this.writeFacts(facts, resolution, request.tick);
      this.announce(resolution, defender);
      return { resolution, facts, applied, stamina, lineOfFire };
    }
    /**
     * Resolve a request's action into the row that will be used.
     *
     * An id is looked up in the authored table; a row is taken as given. Either way
     * the action's price comes from the shared meter's cost table when the row
     * carries none — `action/4`'s `EnergyCost`, the same column a climb is priced
     * in, which is what keeps a dodge and a sprint on one resource (US-2).
     *
     * An id with no row is an error, not a silent free action: a game asking for
     * `crossbow_shot` in a world that never authored one has a content bug, and
     * resolving it as an unarmed swing would hide it.
     */
    actionFor(action) {
      const row = typeof action === "string" ? this.actions.get(action) : { ...action };
      if (!row) {
        throw new Error(
          `CombatResolver: "${action}" is not a row of the world's combat action table (have: ${this.actions.ids().join(", ") || "none"})`
        );
      }
      return { ...row, staminaCost: row.staminaCost ?? this.stamina?.costOf(row.id) };
    }
    /**
     * Ask the host whether the shot's line is clear.
     *
     * Asked only for a `projectile` row, only when a probe is wired, and only once —
     * this is a decision-path query, not a frame-path one. A probe that throws is
     * treated as no answer: the host's geometry failing must not stop the rules
     * layer from resolving a fight, and `ITrajectoryProbe` documents that a thrown
     * error reads as `clear`.
     */
    async askLineOfFire(attackerId, targetId, action) {
      if (!this.trajectory || action.delivery !== "projectile") return void 0;
      try {
        return await this.trajectory.query({
          attacker: attackerId,
          target: targetId,
          action: action.id,
          range: action.range
        });
      } catch {
        return void 0;
      }
    }
    // ── Defensive actions ──────────────────────────────────────────────────
    /**
     * Perform a defensive action — a dodge, a roll, a parry.
     *
     * The same table, the same meter and the same gates as a swing (US-3): what
     * makes this one defensive is that its authored row carries a `defense` profile.
     * Core decides whether the window opens and how wide it is; the HOST times it
     * and calls {@link CombatResolver.endDefense} when it closes, which is the whole
     * of "timing is data the host enforces, not core polling".
     */
    async defend(request) {
      const actor = this.combatants.get(request.actorId);
      if (!actor) {
        throw new Error(`CombatResolver.defend: ${request.actorId} is not a registered combatant`);
      }
      const action = this.actionFor(request.action);
      const resolution = resolveDefense({
        actor: snapshot(actor, this.stamina),
        action,
        legality: request.legality
      });
      const stamina = this.stamina && resolution.staminaSpent > 0 ? await this.stamina.spend(actor.id, {
        action: resolution.actionId,
        cost: resolution.staminaSpent
      }) : void 0;
      if (resolution.outcome !== "evading") {
        return { resolution, facts: { retract: [], assert: [] }, applied: false, stamina };
      }
      const previous = this.defenses.get(actor.id);
      const defense = {
        actorId: actor.id,
        actionId: resolution.actionId,
        status: resolution.status,
        magnitude: resolution.magnitude,
        evasionBonus: resolution.evasionBonus,
        window: resolution.window,
        openedAt: request.tick
      };
      this.defenses.set(actor.id, defense);
      const facts = defenseFacts(resolution);
      if (previous) {
        facts.retract.push(...defenseEndFacts(actor.id, previous.status, previous.magnitude).retract);
      }
      const applied = await this.writeDelta(facts);
      this.eventBus?.emit({
        type: "combat_action",
        actionType: resolution.actionId,
        targetId: actor.id
      });
      return { resolution, facts, applied, stamina, defense };
    }
    /** The evasion window this actor has open, if any. */
    activeDefense(actorId) {
      const defense = this.defenses.get(actorId);
      return defense === void 0 ? void 0 : { ...defense };
    }
    /**
     * The host says the window elapsed. Core takes the status back off.
     *
     * This is the only place a dodge ends, and it is deliberately not a tick: core
     * holds no clock, and a window measured in frames is the host's to count
     * (`docs/module-contract.md` §3). Calling it for an actor with no open window is
     * a no-op, so a host that fires the callback twice does no damage.
     */
    async endDefense(actorId) {
      const defense = this.defenses.get(actorId);
      if (!defense) return { facts: { retract: [], assert: [] }, applied: false };
      this.defenses.delete(actorId);
      const facts = defenseEndFacts(actorId, defense.status, defense.magnitude);
      const applied = await this.writeDelta(facts);
      return { facts, applied };
    }
    /**
     * Publish the action table's reach into the KB as `action_range/2`.
     *
     * Authored data, asserted at load the way `StaminaPool.publishTuning` asserts
     * `stamina_threshold/2` — so a `can_perform/3` prerequisite about range reads
     * the same number the resolution does, without combat inventing a predicate of
     * its own. Returns how many facts were written.
     */
    async publishActionTable(engine = this.engine) {
      if (!engine) return 0;
      let written = 0;
      for (const action of this.actions.all()) {
        for (const fact of combatActionFacts(action)) {
          await engine.assertFact(term(fact));
          written += 1;
        }
      }
      return written;
    }
    /**
     * Pay for a swing that happened, out of the shared meter.
     *
     * The resolution already decided how much (`staminaSpent`, which is zero for
     * anything that was not a swing); this only tells the pool to move it, so the
     * arithmetic stays in the pure function four engines reproduce and the memory
     * stays in the one module that owns it.
     */
    async paySwing(attackerId, resolution) {
      if (!this.stamina || resolution.staminaSpent <= 0) return void 0;
      return this.stamina.spend(attackerId, {
        action: resolution.actionId,
        cost: resolution.staminaSpent
      });
    }
    /**
     * `can_attack/2`, asked of the KB.
     *
     * With no engine wired the attack is not gated — the same "tracked, not
     * enforced" degradation `EquipmentManager` documents for a missing stat sink.
     * A KB that is wired but carries no combat facts answers `false` rather than
     * raising, which is what the pack's `:- dynamic` declarations are for.
     */
    async askLegality(attackerId, targetId) {
      if (!this.engine) return void 0;
      const goal = `can_attack(${atom2(attackerId)}, ${atom2(targetId)})`;
      const permitted = await this.engine.queryOnce(goal);
      return permitted ? { permitted: true } : { permitted: false, reason: "not_permitted" };
    }
    /** Move this module's own state to match the resolution, and build the fact delta. */
    applyResolution(attacker, defender, resolution) {
      if (!attackWasMade(resolution)) return { retract: [], assert: [] };
      const priorThreat = defender.threat[attacker.id];
      const threat = threatAfterDamage(resolution.damage, defender.maxHealth, priorThreat ?? 0);
      defender.health = resolution.targetHealthAfter;
      if (resolution.incapacitated) defender.incapacitated = true;
      if (resolution.killed) defender.alive = false;
      if (resolution.damage > 0) defender.threat[attacker.id] = threat;
      for (const applied of resolution.statusesApplied) {
        const existing = defender.statuses.findIndex((s) => s.status === applied.status);
        if (existing >= 0) defender.statuses[existing] = { ...applied };
        else defender.statuses.push({ ...applied });
      }
      return resolutionFacts(resolution, {
        threat: resolution.damage > 0 ? threat : void 0,
        priorThreat: resolution.damage > 0 ? priorThreat : void 0
      });
    }
    /**
     * Write the delta into the KB, plus the lifecycle facts a death owes the rest
     * of the simulation.
     *
     * `deceased/3` and `cause_of_death/2` are `prolog/npc-reasoning.ts`'s existing
     * vocabulary, not combat's: asserting them is what makes `is_grieving/1`,
     * `has_living_children/1`, `event_candidate(funeral, …)` and `inherits_from/3`
     * true of someone killed in a fight, without this module naming genealogy,
     * inheritance or reputation at all.
     *
     * They are also what makes a death SURVIVE a reload. `alive/1` is an authored
     * character fact — it is not in `buildKnownPredicateSignatures()`, so it never
     * enters a save, and a world that consulted it as content cannot have it
     * retracted at all. Every other predicate written here (`health/3`,
     * `incapacitated/1`, `in_combat/1`, `combat_target/2`, `has_status/3`,
     * `threat/3`, `deceased/3`, `cause_of_death/2`) validates as a runtime fact, so
     * the retraction is best-effort and `deceased/3` is the load-bearing one.
     */
    async writeFacts(delta, resolution, tick) {
      if (!this.engine) return false;
      if (delta.retract.length === 0 && delta.assert.length === 0) return false;
      const asserts = [...delta.assert];
      if (resolution.killed) {
        asserts.push({ predicate: "deceased", args: [resolution.targetId, tick, "combat"] });
        asserts.push({ predicate: "cause_of_death", args: [resolution.targetId, "combat"] });
      }
      return this.writeDelta({ retract: delta.retract, assert: asserts });
    }
    /**
     * Write one delta into the KB, retracting first.
     *
     * Retracting a fact the KB never carried is a no-op rather than a failure: a
     * host with its own persistence, a restored save and a dodge that opened before
     * the engine was wired all produce one, and none of them is an error.
     */
    async writeDelta(delta) {
      if (!this.engine) return false;
      if (delta.retract.length === 0 && delta.assert.length === 0) return false;
      for (const fact of delta.retract) {
        try {
          await this.engine.retractFact(term(fact));
        } catch {
        }
      }
      for (const fact of delta.assert) {
        await this.engine.assertFact(term(fact));
      }
      return true;
    }
    /** Hand the decision to the host and the bus. Everything here is after the fact. */
    announce(resolution, defender) {
      if (!attackWasMade(resolution)) return;
      this.eventBus?.emit({
        type: "combat_action",
        actionType: resolution.actionId,
        targetId: resolution.targetId
      });
      if (resolution.damage > 0) this.combat?.applyDamage(resolution.targetId, resolution.damage);
      if (resolution.killed) {
        this.combat?.unregisterEntity(resolution.targetId);
        this.eventBus?.emit({
          type: "enemy_defeated",
          entityId: resolution.targetId,
          enemyType: defender.kind
        });
        this.eventBus?.emit({
          type: "create_truth",
          characterId: resolution.targetId,
          title: "Killed in combat",
          content: `${resolution.targetId} was killed by ${resolution.attackerId}.`,
          entryType: "event",
          category: "death"
        });
      }
    }
    // ── Save/restore ───────────────────────────────────────────────────────
    serialize() {
      return {
        combatants: this.roster().map((state) => ({
          ...state,
          statuses: state.statuses.map((s) => ({ ...s })),
          threat: { ...state.threat }
        })),
        // The open windows, but never the TABLE that authored them: rows are world
        // content, and a save carrying a copy would freeze a creator's balance pass
        // at the moment the player first pressed New Game.
        defenses: [...this.defenses.values()].map((defense) => ({ ...defense }))
      };
    }
    /**
     * Restore a saved fight. Silent — no events, because loading a save is not a
     * fight happening, and a quest listener counting kills must not fire on load.
     */
    restore(state) {
      this.combatants = /* @__PURE__ */ new Map();
      for (const entry of state.combatants ?? []) {
        this.combatants.set(entry.id, {
          ...entry,
          statuses: (entry.statuses ?? []).map((s) => ({ ...s })),
          threat: { ...entry.threat ?? {} }
        });
      }
      this.defenses = /* @__PURE__ */ new Map();
      for (const defense of state.defenses ?? []) {
        this.defenses.set(defense.actorId, { ...defense });
      }
    }
  };
  function snapshot(state, stamina, defense) {
    const meter = stamina?.get(state.id);
    return {
      id: state.id,
      health: state.health,
      maxHealth: state.maxHealth,
      alive: state.alive,
      incapacitated: state.incapacitated,
      weapon: state.weapon,
      armor: state.armor,
      resists: state.resists,
      vulnerableTo: state.vulnerableTo,
      statuses: state.statuses.map((s) => s.status),
      // An open evasion window is a dodge bonus and nothing more exotic: an evaded
      // shot comes out `dodged` through the ordinary gate, so the pure resolution
      // needs no notion of "defending" at all (US-3).
      dodgeBonus: (state.dodgeBonus ?? 0) + (defense?.evasionBonus ?? 0),
      blocking: state.blocking,
      stamina: meter ? { current: meter.current, max: meter.max } : void 0
    };
  }
  function term(fact) {
    return serializedFactToProlog(fact).replace(/\.$/, "");
  }
  function atom2(id) {
    return serializeArg(id);
  }

  // @insimul/core/src/stamina/stamina-facts.ts
  var STAMINA_RESOLUTION_PREDICATES = Object.freeze(["energy/3"]);
  var STAMINA_AUTHORED_PREDICATES = Object.freeze([
    "stamina_threshold/2",
    "stamina_regen_base/2",
    "action/4"
  ]);
  function energyFacts(actorId, before, after, max) {
    if (before === after) return { retract: [], assert: [] };
    return {
      retract: [{ predicate: "energy", args: [actorId, before, max] }],
      assert: [{ predicate: "energy", args: [actorId, after, max] }]
    };
  }
  function spendFacts(actorId, spend) {
    if (!spend.affordable) return { retract: [], assert: [] };
    return energyFacts(actorId, spend.before, spend.after, spend.max);
  }
  function regenFacts(actorId, regen) {
    return energyFacts(actorId, regen.before, regen.after, regen.max);
  }
  function staminaTuningFacts(tuning) {
    const percent = {
      winded: tuning.windedPercent,
      exhausted: tuning.exhaustedPercent
    };
    return STAMINA_THRESHOLD_NAMES.map((name) => ({
      predicate: "stamina_threshold",
      args: [name, percent[name]]
    }));
  }
  function staminaRegenBaseFact(actorId, rate) {
    return { predicate: "stamina_regen_base", args: [actorId, rate] };
  }

  // @insimul/core/src/game-engine/logic/StaminaPool.ts
  var StaminaPool = class {
    constructor(config = {}) {
      __publicField(this, "engine");
      __publicField(this, "tuning");
      __publicField(this, "survival");
      __publicField(this, "survivalActorId");
      __publicField(this, "costs", /* @__PURE__ */ new Map());
      __publicField(this, "actors", /* @__PURE__ */ new Map());
      this.engine = config.engine;
      this.tuning = config.tuning ?? { ...DEFAULT_STAMINA_TUNING };
      this.survival = config.survival;
      this.survivalActorId = config.survivalActorId;
      for (const [action, cost] of Object.entries(config.costs ?? {})) this.setCost(action, cost);
      if (config.state) this.restore(config.state);
    }
    /** The world's authored numbers, as this instance read them. */
    getTuning() {
      return { ...this.tuning };
    }
    // ── The authored cost table ────────────────────────────────────────────
    /** Price one action. Authored data, set at load rather than during play. */
    setCost(actionId, cost) {
      this.costs.set(actionId, Math.max(0, Math.floor(cost)));
    }
    /**
     * What this action costs. An action the world never priced costs nothing —
     * silently free rather than an error, because a world that authored no costs at
     * all is a world with no stamina economy, not a broken one.
     */
    costOf(actionId) {
      return this.costs.get(actionId) ?? 0;
    }
    /**
     * Load the cost table from the IR's action block — `ActionIR.energyCost`, the
     * authoring surface behind `action/4`'s fourth argument.
     */
    loadCosts(actions) {
      for (const action of actions) {
        if (typeof action.energyCost === "number" && Number.isFinite(action.energyCost)) {
          this.setCost(action.id, action.energyCost);
        }
      }
    }
    /**
     * Load the cost table from a KB that already consulted the world's action
     * table. `action/4` IS the cost table (`docs/mechanic-predicates.md` §12 cut
     * `stamina_cost/2` precisely so there would be only one), so this reads it
     * rather than a stamina-specific predicate.
     */
    async loadCostsFromKb(engine) {
      const result = await engine.query("action(Id, _, _, Cost)", MAX_ACTION_SOLUTIONS);
      if (!result.success) return 0;
      let loaded = 0;
      for (const binding of result.bindings) {
        const id = typeof binding["Id"] === "string" ? binding["Id"] : null;
        const cost = typeof binding["Cost"] === "number" ? binding["Cost"] : Number(binding["Cost"]);
        if (id === null || !Number.isFinite(cost)) continue;
        if (cost > (this.costs.get(id) ?? -Infinity)) this.setCost(id, cost);
        loaded += 1;
      }
      return loaded;
    }
    /**
     * Publish the world's authored thresholds into the KB as `stamina_threshold/2`,
     * so `winded/1` and `exhausted/1` answer with the same percentages
     * {@link staminaStateOf} uses.
     *
     * Called when a world is loaded, not when one is saved: these are authored
     * facts, they are not in the save-restore validator's known set, and a
     * playthrough that reloads gets them from the world again.
     */
    async publishTuning(engine = this.engine) {
      if (!engine) return false;
      const facts = [...staminaTuningFacts(this.tuning)];
      for (const actor of this.actors.values()) {
        if (actor.regenBase !== void 0) facts.push(staminaRegenBaseFact(actor.id, actor.regenBase));
      }
      for (const fact of facts) await engine.assertFact(term2(fact));
      return true;
    }
    // ── The roster ─────────────────────────────────────────────────────────
    /** Add or replace an actor's meter. */
    register(entry) {
      const max = entry.max ?? this.tuning.maxStamina;
      const state = {
        id: entry.id,
        max,
        current: Math.max(0, Math.min(max, entry.current ?? max)),
        regenBase: entry.regenBase
      };
      this.actors.set(entry.id, state);
      return state;
    }
    unregister(actorId) {
      this.actors.delete(actorId);
    }
    get(actorId) {
      return this.actors.get(actorId);
    }
    /** Every actor with a meter, in registration order. */
    roster() {
      return [...this.actors.values()];
    }
    /** Which band this actor is in — `fresh`, `winded` or `exhausted`. */
    stateOf(actorId) {
      const actor = this.actors.get(actorId);
      if (!actor) return "fresh";
      return staminaStateOf(actor.current, actor.max, this.tuning);
    }
    /**
     * Whether this actor could pay for this action right now — `can_afford_stamina/2`
     * without a round trip. An unregistered actor can afford anything: a world that
     * never gave them a meter does not have one to check.
     */
    canAfford(actorId, action, cost) {
      const actor = this.actors.get(actorId);
      if (!actor) return true;
      return canAffordStamina(actor.current, cost ?? this.costOf(action));
    }
    // ── The decision ───────────────────────────────────────────────────────
    /**
     * Spend an action's cost out of this actor's meter.
     *
     * An unaffordable spend moves nothing and writes nothing: `affordable: false`
     * is the caller's cue to refuse the action, exactly as a `refused` attack is
     * `CombatResolver`'s. An unregistered actor is not an error either — the spend
     * reports as affordable and free, so a world can price actions for the actors
     * it gave meters to without every other caller having to check first.
     */
    async spend(actorId, request) {
      const cost = request.cost ?? this.costOf(request.action);
      const actor = this.actors.get(actorId);
      if (!actor) {
        return {
          actorId,
          action: request.action,
          spend: unmeteredSpend(cost),
          facts: { retract: [], assert: [] },
          applied: false
        };
      }
      const spend = spendStamina({
        current: actor.current,
        max: actor.max,
        cost,
        tuning: this.tuning
      });
      if (spend.affordable) actor.current = spend.after;
      const facts = spendFacts(actorId, spend);
      const applied = await this.writeFacts(facts);
      if (spend.spent > 0 && actorId === this.survivalActorId) {
        this.survival?.consumeStamina(spend.spent);
      }
      return { actorId, action: request.action, spend, facts, applied };
    }
    /**
     * Grant rest. The host owns the clock and says how many ticks passed; core
     * decides only the modifier (`docs/mechanic-predicates.md` §9), which is what
     * keeps this off a per-frame path across the ABI.
     */
    async rest(actorId, request) {
      const actor = this.actors.get(actorId);
      if (!actor) {
        const empty = {
          before: 0,
          after: 0,
          max: 0,
          rate: 0,
          recovered: 0,
          state: "fresh"
        };
        return { actorId, regen: empty, facts: { retract: [], assert: [] }, applied: false };
      }
      const regen = regenerateStamina({
        current: actor.current,
        max: actor.max,
        ticks: request.ticks,
        tuning: this.tuning,
        rate: actor.regenBase,
        inCombat: request.inCombat,
        encumbered: request.encumbered
      });
      actor.current = regen.after;
      const facts = regenFacts(actorId, regen);
      const applied = await this.writeFacts(facts);
      if (regen.recovered > 0 && actorId === this.survivalActorId) {
        this.survival?.recoverStamina(regen.recovered);
      }
      return { actorId, regen, facts, applied };
    }
    /**
     * Write a delta into the KB. Retract first — `energy/3` is replaced, never
     * accumulated — and a retraction of a fact the KB never carried is a no-op
     * rather than a failure, the same way `CombatResolver` treats `health/3`.
     */
    async writeFacts(delta) {
      if (!this.engine) return false;
      if (delta.retract.length === 0 && delta.assert.length === 0) return false;
      for (const fact of delta.retract) {
        try {
          await this.engine.retractFact(term2(fact));
        } catch {
        }
      }
      for (const fact of delta.assert) {
        await this.engine.assertFact(term2(fact));
      }
      return true;
    }
    // ── Save/restore ───────────────────────────────────────────────────────
    /**
     * The per-playthrough state, as a save carries it: how much each actor has
     * left. No thresholds, no rates and no costs — those are the world template's,
     * and a save that carried a copy would freeze a creator's balance pass at the
     * moment the player first pressed New Game.
     */
    serialize() {
      return { actors: this.roster().map((actor) => ({ ...actor })) };
    }
    /** Restore a saved pool. Silent: loading a save is not an actor getting tired. */
    restore(state) {
      this.actors = /* @__PURE__ */ new Map();
      for (const entry of state.actors ?? []) {
        this.actors.set(entry.id, { ...entry });
      }
    }
  };
  var MAX_ACTION_SOLUTIONS = 1e3;
  function unmeteredSpend(cost) {
    return {
      affordable: true,
      cost,
      before: 0,
      after: 0,
      max: 0,
      spent: 0,
      stateBefore: "fresh",
      state: "fresh",
      becameWinded: false,
      becameExhausted: false
    };
  }
  function term2(fact) {
    return serializedFactToProlog(fact).replace(/\.$/, "");
  }

  // @insimul/core/src/identity/kinp.ts
  var KINP_KINDS = ["ent", "claim", "asset", "world", "agent", "src"];
  var INSIMUL_NAMESPACE = "insimul";
  var LOCAL_ID_PASSTHROUGH = /[a-z0-9._-]/;
  var LOCAL_ID_HEAD = /[a-z0-9]/;
  var LOCAL_ID_GUARD = "x-";
  var utf8Encoder = new TextEncoder();
  var utf8Decoder = new TextDecoder();
  function percentEncodeChar(ch) {
    let out = "";
    for (const byte of utf8Encoder.encode(ch)) {
      out += `%${byte.toString(16).toUpperCase().padStart(2, "0")}`;
    }
    return out;
  }
  function encodeLocalIdBody(raw) {
    let out = "";
    for (const ch of raw) {
      out += LOCAL_ID_PASSTHROUGH.test(ch) ? ch : percentEncodeChar(ch);
    }
    return out;
  }
  function sanitizeLocalId(raw) {
    if (!raw) throw new Error("sanitizeLocalId: empty id");
    const body = encodeLocalIdBody(raw);
    if (LOCAL_ID_HEAD.test(body[0]) && !body.startsWith(LOCAL_ID_GUARD)) return body;
    const [first, ...rest] = Array.from(raw);
    return LOCAL_ID_GUARD + percentEncodeChar(first) + encodeLocalIdBody(rest.join(""));
  }
  function formatCurie(id) {
    return `${id.namespace}:${id.kind}:${id.localId}`;
  }
  function parseCurie(curie) {
    const parts = curie.split(":");
    if (parts.length < 3) throw new Error(`parseCurie: not a CURIE: "${curie}"`);
    const localId = parts[parts.length - 1];
    const kind = parts[parts.length - 2];
    const namespace = parts.slice(0, -2).join(":");
    if (!KINP_KINDS.includes(kind)) throw new Error(`parseCurie: unknown kind "${kind}" in "${curie}"`);
    if (!namespace) throw new Error(`parseCurie: empty namespace in "${curie}"`);
    if (!localId) throw new Error(`parseCurie: empty local id in "${curie}"`);
    return { kind, namespace, localId };
  }
  function prologAtom(value) {
    if (/^[a-z][a-zA-Z0-9_]*$/.test(value)) return value;
    return `'${value.replace(/\\/g, "\\\\").replace(/'/g, "\\'")}'`;
  }
  function formatIdTerm(id) {
    return `id(${id.kind}, ${prologAtom(id.namespace)}, ${prologAtom(id.localId)})`;
  }
  function provisionalEntityId(localId, ns = INSIMUL_NAMESPACE) {
    return { kind: "ent", namespace: `${ns}:local`, localId: sanitizeLocalId(localId) };
  }

  // @insimul/core/src/identity/worlds.ts
  var PLAYTHROUGH_SEPARATOR = "#save-";
  var ENCODED_SEPARATOR = sanitizeLocalId(`a${PLAYTHROUGH_SEPARATOR}b`).slice(1, -1);
  function worldFacts(decl) {
    const world = formatIdTerm(decl.world);
    const facts = [`world_declared(${world}).`];
    if (decl.role) facts.push(`world_role(${world}, ${decl.role}).`);
    if (decl.parent) facts.push(`world_parent(${world}, ${formatIdTerm(decl.parent)}).`);
    if (decl.inheritsIdentity) facts.push(`world_inherits_identity(${world}).`);
    return facts;
  }
  var WORLD_CONTEXT_FUNCTOR = "@world";
  function worldContextTerm(world) {
    return `${prologAtom(WORLD_CONTEXT_FUNCTOR)}(${formatIdTerm(world)})`;
  }

  // @insimul/core/src/game-engine/host-contracts.ts
  var MOVEMENT_URGENCIES = Object.freeze([
    "idle",
    "ordinary",
    "hurried",
    "urgent"
  ]);
  var MOVEMENT_STANCES = Object.freeze(["standing", "crouching", "prone"]);
  var ANIMATION_INTENTS = Object.freeze([
    "idle",
    "walk",
    "run",
    "crouch",
    "swim",
    "climb",
    "jump",
    "ride",
    "carry",
    "sit",
    "sleep",
    "eat",
    "work",
    "handle",
    "read",
    "talk",
    "listen",
    "wave",
    "gesture",
    "strike",
    "guard",
    "cast",
    "stagger",
    "collapse"
  ]);
  var DEFAULT_ANIMATION_INTENT = "idle";
  var INFERENCE_REQUEST_KINDS = Object.freeze(["proposal", "utterance"]);
  var MODEL_RESIDENCIES = Object.freeze(["resident", "on-demand", "absent"]);
  var INFERENCE_STATUSES = Object.freeze([
    "pending",
    "ready",
    "failed",
    "unknown"
  ]);
  var NULL_HOST_ADAPTER = Object.freeze({});

  // @insimul/core/src/game-engine/action-matrix.ts
  var ACTION_MATRIX = [
    // ═══════════════════════════════════════════════════════════════════════════
    // MOVEMENT
    // ═══════════════════════════════════════════════════════════════════════════
    // ─── Parent: move ──────────────────────────────────────────────────────
    {
      actionId: "move",
      animation: "walk",
      displayName: "Move",
      category: "movement",
      parentAction: null,
      interactionMode: "automatic",
      eventTypes: [],
      objectiveTypes: [],
      status: "implemented",
      requiresTarget: true,
      targetType: "location"
    },
    {
      actionId: "walk",
      animation: "walk",
      displayName: "Walk",
      category: "movement",
      parentAction: "move",
      interactionMode: "animation",
      eventTypes: [],
      objectiveTypes: [],
      status: "animation-only",
      requiresTarget: true,
      targetType: "location"
    },
    {
      actionId: "jog",
      animation: "run",
      displayName: "Jog",
      category: "movement",
      parentAction: "move",
      interactionMode: "animation",
      eventTypes: [],
      objectiveTypes: [],
      status: "animation-only",
      requiresTarget: true,
      targetType: "location"
    },
    {
      actionId: "sprint",
      animation: "run",
      displayName: "Sprint",
      category: "movement",
      parentAction: "move",
      interactionMode: "animation",
      eventTypes: [],
      objectiveTypes: [],
      status: "animation-only",
      requiresTarget: true,
      targetType: "location"
    },
    {
      actionId: "swim",
      animation: "swim",
      displayName: "Swim",
      category: "movement",
      parentAction: "move",
      interactionMode: "animation",
      eventTypes: [],
      objectiveTypes: [],
      status: "animation-only",
      requiresTarget: true,
      targetType: "location"
    },
    {
      actionId: "swim_idle",
      animation: "swim",
      displayName: "Tread Water",
      category: "movement",
      parentAction: "move",
      interactionMode: "animation",
      eventTypes: [],
      objectiveTypes: [],
      status: "animation-only",
      requiresTarget: false
    },
    {
      actionId: "walk_carry",
      animation: "carry",
      displayName: "Walk While Carrying",
      category: "movement",
      parentAction: "move",
      interactionMode: "animation",
      eventTypes: [],
      objectiveTypes: [],
      status: "animation-only",
      requiresTarget: true,
      targetType: "location"
    },
    {
      actionId: "walk_formal",
      animation: "walk",
      displayName: "Walk Formally",
      category: "movement",
      parentAction: "move",
      interactionMode: "animation",
      eventTypes: [],
      objectiveTypes: [],
      status: "animation-only",
      requiresTarget: true,
      targetType: "location"
    },
    {
      actionId: "drive",
      animation: "ride",
      displayName: "Drive",
      category: "movement",
      parentAction: "move",
      interactionMode: "animation",
      eventTypes: [],
      objectiveTypes: [],
      status: "animation-only",
      requiresTarget: true,
      targetType: "location"
    },
    {
      actionId: "crouch_walk",
      animation: "crouch",
      displayName: "Crouch Walk",
      category: "movement",
      parentAction: "move",
      interactionMode: "animation",
      eventTypes: [],
      objectiveTypes: [],
      status: "animation-only",
      requiresTarget: true,
      targetType: "location"
    },
    {
      actionId: "crouch_idle",
      animation: "crouch",
      displayName: "Crouch",
      category: "movement",
      parentAction: "move",
      interactionMode: "animation",
      eventTypes: [],
      objectiveTypes: [],
      status: "animation-only",
      requiresTarget: false
    },
    // ─── Parent: jump ──────────────────────────────────────────────────────
    {
      actionId: "jump",
      animation: "jump",
      displayName: "Jump",
      category: "movement",
      parentAction: null,
      interactionMode: "automatic",
      eventTypes: [],
      objectiveTypes: [],
      status: "implemented",
      requiresTarget: false
    },
    {
      actionId: "ninja_jump",
      animation: "jump",
      displayName: "Ninja Jump",
      category: "movement",
      parentAction: "jump",
      interactionMode: "animation",
      eventTypes: [],
      objectiveTypes: [],
      status: "animation-only",
      requiresTarget: false
    },
    {
      actionId: "roll",
      animation: "jump",
      displayName: "Roll",
      category: "movement",
      parentAction: "jump",
      interactionMode: "animation",
      eventTypes: [],
      objectiveTypes: [],
      status: "animation-only",
      requiresTarget: false
    },
    {
      actionId: "slide",
      animation: "jump",
      displayName: "Slide",
      category: "movement",
      parentAction: "jump",
      interactionMode: "animation",
      eventTypes: [],
      objectiveTypes: [],
      status: "animation-only",
      requiresTarget: false
    },
    {
      actionId: "climb",
      animation: "climb",
      displayName: "Climb",
      category: "movement",
      parentAction: "jump",
      interactionMode: "animation",
      eventTypes: [],
      objectiveTypes: [],
      status: "animation-only",
      requiresTarget: true,
      targetType: "object"
    },
    // ═══════════════════════════════════════════════════════════════════════════
    // COMBAT
    // ═══════════════════════════════════════════════════════════════════════════
    // ─── Parent: attack_enemy ──────────────────────────────────────────────
    {
      actionId: "attack_enemy",
      animation: "strike",
      displayName: "Attack Enemy",
      category: "combat",
      parentAction: null,
      interactionMode: "physical",
      eventTypes: ["combat_action", "enemy_defeated"],
      objectiveTypes: ["defeat_enemies"],
      status: "implemented",
      requiresTarget: true,
      targetType: "npc"
    },
    {
      actionId: "sword_attack",
      animation: "strike",
      displayName: "Sword Attack",
      category: "combat",
      parentAction: "attack_enemy",
      interactionMode: "animation",
      eventTypes: ["combat_action"],
      objectiveTypes: [],
      status: "animation-only",
      requiresTarget: true,
      targetType: "npc"
    },
    {
      actionId: "sword_combo",
      animation: "strike",
      displayName: "Sword Combo",
      category: "combat",
      parentAction: "attack_enemy",
      interactionMode: "animation",
      eventTypes: ["combat_action"],
      objectiveTypes: [],
      status: "animation-only",
      requiresTarget: true,
      targetType: "npc"
    },
    {
      actionId: "sword_dash",
      animation: "strike",
      displayName: "Sword Dash",
      category: "combat",
      parentAction: "attack_enemy",
      interactionMode: "animation",
      eventTypes: ["combat_action"],
      objectiveTypes: [],
      status: "animation-only",
      requiresTarget: true,
      targetType: "npc"
    },
    {
      actionId: "sword_idle",
      animation: "guard",
      displayName: "Sword Ready",
      category: "combat",
      parentAction: "attack_enemy",
      interactionMode: "animation",
      eventTypes: [],
      objectiveTypes: [],
      status: "animation-only",
      requiresTarget: false
    },
    {
      actionId: "punch",
      animation: "strike",
      displayName: "Punch",
      category: "combat",
      parentAction: "attack_enemy",
      interactionMode: "animation",
      eventTypes: ["combat_action"],
      objectiveTypes: [],
      status: "animation-only",
      requiresTarget: true,
      targetType: "npc"
    },
    {
      actionId: "punch_heavy",
      animation: "strike",
      displayName: "Heavy Punch",
      category: "combat",
      parentAction: "attack_enemy",
      interactionMode: "animation",
      eventTypes: ["combat_action"],
      objectiveTypes: [],
      status: "animation-only",
      requiresTarget: true,
      targetType: "npc"
    },
    {
      actionId: "melee_hook",
      animation: "strike",
      displayName: "Hook Punch",
      category: "combat",
      parentAction: "attack_enemy",
      interactionMode: "animation",
      eventTypes: ["combat_action"],
      objectiveTypes: [],
      status: "animation-only",
      requiresTarget: true,
      targetType: "npc"
    },
    {
      actionId: "shield_bash",
      animation: "strike",
      displayName: "Shield Bash",
      category: "combat",
      parentAction: "attack_enemy",
      interactionMode: "animation",
      eventTypes: ["combat_action"],
      objectiveTypes: [],
      status: "animation-only",
      requiresTarget: true,
      targetType: "npc"
    },
    {
      actionId: "shield_dash",
      animation: "strike",
      displayName: "Shield Dash",
      category: "combat",
      parentAction: "attack_enemy",
      interactionMode: "animation",
      eventTypes: ["combat_action"],
      objectiveTypes: [],
      status: "animation-only",
      requiresTarget: true,
      targetType: "npc"
    },
    {
      actionId: "pistol_shoot",
      animation: "strike",
      displayName: "Shoot Pistol",
      category: "combat",
      parentAction: "attack_enemy",
      interactionMode: "animation",
      eventTypes: ["combat_action"],
      objectiveTypes: [],
      status: "animation-only",
      requiresTarget: true,
      targetType: "npc"
    },
    {
      actionId: "pistol_aim",
      animation: "guard",
      displayName: "Aim Pistol",
      category: "combat",
      parentAction: "attack_enemy",
      interactionMode: "animation",
      eventTypes: [],
      objectiveTypes: [],
      status: "animation-only",
      requiresTarget: true,
      targetType: "npc"
    },
    {
      actionId: "pistol_reload",
      animation: "handle",
      displayName: "Reload Pistol",
      category: "combat",
      parentAction: "attack_enemy",
      interactionMode: "animation",
      eventTypes: [],
      objectiveTypes: [],
      status: "animation-only",
      requiresTarget: false
    },
    {
      actionId: "throw_projectile",
      animation: "strike",
      displayName: "Throw Projectile",
      category: "combat",
      parentAction: "attack_enemy",
      interactionMode: "animation",
      eventTypes: ["combat_action"],
      objectiveTypes: [],
      status: "animation-only",
      requiresTarget: true,
      targetType: "npc"
    },
    {
      actionId: "zombie_attack",
      animation: "strike",
      displayName: "Zombie Attack",
      category: "combat",
      parentAction: "attack_enemy",
      interactionMode: "animation",
      eventTypes: ["combat_action"],
      objectiveTypes: [],
      status: "animation-only",
      requiresTarget: true,
      targetType: "npc"
    },
    // ─── Parent: defend ────────────────────────────────────────────────────
    {
      actionId: "defend",
      animation: "guard",
      displayName: "Defend",
      category: "combat",
      parentAction: null,
      interactionMode: "physical",
      eventTypes: ["combat_action"],
      objectiveTypes: [],
      status: "implemented",
      requiresTarget: false
    },
    {
      actionId: "shield_block",
      animation: "guard",
      displayName: "Shield Block",
      category: "combat",
      parentAction: "defend",
      interactionMode: "animation",
      eventTypes: ["combat_action"],
      objectiveTypes: [],
      status: "animation-only",
      requiresTarget: false
    },
    {
      actionId: "sword_block",
      animation: "guard",
      displayName: "Sword Block",
      category: "combat",
      parentAction: "defend",
      interactionMode: "animation",
      eventTypes: ["combat_action"],
      objectiveTypes: [],
      status: "animation-only",
      requiresTarget: false
    },
    // ─── Parent: cast_spell ────────────────────────────────────────────────
    {
      actionId: "cast_spell",
      animation: "cast",
      displayName: "Cast Spell",
      category: "combat",
      parentAction: null,
      interactionMode: "physical",
      eventTypes: ["combat_action"],
      objectiveTypes: [],
      status: "implemented",
      requiresTarget: true,
      targetType: "npc"
    },
    {
      actionId: "spell_channel",
      animation: "cast",
      displayName: "Channel Spell",
      category: "combat",
      parentAction: "cast_spell",
      interactionMode: "animation",
      eventTypes: ["combat_action"],
      objectiveTypes: [],
      status: "animation-only",
      requiresTarget: false
    },
    // ─── Parent: react ─────────────────────────────────────────────────────
    {
      actionId: "react",
      animation: "stagger",
      displayName: "React",
      category: "combat",
      parentAction: null,
      interactionMode: "animation",
      eventTypes: [],
      objectiveTypes: [],
      status: "animation-only",
      requiresTarget: false
    },
    {
      actionId: "die",
      animation: "collapse",
      displayName: "Die",
      category: "combat",
      parentAction: "react",
      interactionMode: "animation",
      eventTypes: [],
      objectiveTypes: [],
      status: "animation-only",
      requiresTarget: false
    },
    {
      actionId: "hit_head",
      animation: "stagger",
      displayName: "Hit Head",
      category: "combat",
      parentAction: "react",
      interactionMode: "animation",
      eventTypes: [],
      objectiveTypes: [],
      status: "animation-only",
      requiresTarget: false
    },
    {
      actionId: "hit_reaction",
      animation: "stagger",
      displayName: "Hit Reaction",
      category: "combat",
      parentAction: "react",
      interactionMode: "animation",
      eventTypes: [],
      objectiveTypes: [],
      status: "animation-only",
      requiresTarget: false
    },
    {
      actionId: "knockback",
      animation: "stagger",
      displayName: "Knockback",
      category: "combat",
      parentAction: "react",
      interactionMode: "animation",
      eventTypes: [],
      objectiveTypes: [],
      status: "animation-only",
      requiresTarget: false
    },
    // ─── Creature actions (zombie_idle, zombie_walk share parents above) ──
    {
      actionId: "zombie_idle",
      animation: "idle",
      displayName: "Zombie Idle",
      category: "combat",
      parentAction: "idle",
      interactionMode: "animation",
      eventTypes: [],
      objectiveTypes: [],
      status: "animation-only",
      requiresTarget: false
    },
    {
      actionId: "zombie_walk",
      animation: "walk",
      displayName: "Zombie Walk",
      category: "combat",
      parentAction: "move",
      interactionMode: "animation",
      eventTypes: [],
      objectiveTypes: [],
      status: "animation-only",
      requiresTarget: true,
      targetType: "location"
    },
    // ═══════════════════════════════════════════════════════════════════════════
    // SOCIAL
    // ═══════════════════════════════════════════════════════════════════════════
    // ─── Parent: talk_to_npc ───────────────────────────────────────────────
    {
      actionId: "talk_to_npc",
      animation: "talk",
      displayName: "Talk to NPC",
      category: "social",
      parentAction: null,
      interactionMode: "conversational",
      eventTypes: ["npc_talked"],
      objectiveTypes: ["talk_to_npc", "complete_conversation", "conversation_initiation"],
      status: "implemented",
      requiresTarget: true,
      targetType: "npc"
    },
    {
      actionId: "talk",
      animation: "talk",
      displayName: "Talk",
      category: "social",
      parentAction: "talk_to_npc",
      interactionMode: "animation",
      eventTypes: ["npc_talked"],
      objectiveTypes: [],
      status: "animation-only",
      requiresTarget: true,
      targetType: "npc"
    },
    {
      actionId: "sit_talk",
      animation: "sit",
      displayName: "Sit and Talk",
      category: "social",
      parentAction: "talk_to_npc",
      interactionMode: "animation",
      eventTypes: ["npc_talked"],
      objectiveTypes: [],
      status: "animation-only",
      requiresTarget: true,
      targetType: "npc"
    },
    {
      actionId: "phone_call",
      animation: "talk",
      displayName: "Phone Call",
      category: "social",
      parentAction: "talk_to_npc",
      interactionMode: "animation",
      eventTypes: ["conversational_action"],
      objectiveTypes: [],
      status: "animation-only",
      requiresTarget: true,
      targetType: "npc"
    },
    {
      actionId: "greet",
      animation: "wave",
      displayName: "Greet",
      category: "social",
      parentAction: "talk_to_npc",
      interactionMode: "conversational",
      eventTypes: ["npc_greeting", "conversational_action"],
      objectiveTypes: [],
      status: "partial",
      priority: "medium",
      requiresTarget: true,
      targetType: "npc"
    },
    {
      actionId: "compliment_npc",
      animation: "talk",
      displayName: "Compliment",
      category: "social",
      parentAction: "talk_to_npc",
      interactionMode: "conversational",
      eventTypes: ["conversational_action", "npc_relationship_changed"],
      objectiveTypes: ["build_friendship", "gain_reputation"],
      status: "partial",
      priority: "medium",
      requiresTarget: true,
      targetType: "npc"
    },
    {
      actionId: "insult_npc",
      animation: "talk",
      displayName: "Insult",
      category: "social",
      parentAction: "talk_to_npc",
      interactionMode: "conversational",
      eventTypes: ["conversational_action", "npc_relationship_changed"],
      objectiveTypes: [],
      status: "partial",
      priority: "low",
      requiresTarget: true,
      targetType: "npc"
    },
    {
      actionId: "threaten",
      animation: "talk",
      displayName: "Threaten",
      category: "social",
      parentAction: "talk_to_npc",
      interactionMode: "conversational",
      eventTypes: ["conversational_action", "npc_relationship_changed"],
      objectiveTypes: [],
      status: "partial",
      priority: "low",
      requiresTarget: true,
      targetType: "npc"
    },
    {
      actionId: "flirt",
      animation: "talk",
      displayName: "Flirt",
      category: "social",
      parentAction: "talk_to_npc",
      interactionMode: "conversational",
      eventTypes: ["conversational_action", "romance_action"],
      objectiveTypes: [],
      status: "partial",
      priority: "low",
      requiresTarget: true,
      targetType: "npc"
    },
    {
      actionId: "persuade",
      animation: "talk",
      displayName: "Persuade",
      category: "social",
      parentAction: "talk_to_npc",
      interactionMode: "conversational",
      eventTypes: ["conversational_action"],
      objectiveTypes: [],
      status: "partial",
      priority: "medium",
      requiresTarget: true,
      targetType: "npc"
    },
    {
      actionId: "bribe",
      animation: "talk",
      displayName: "Bribe",
      category: "social",
      parentAction: "talk_to_npc",
      interactionMode: "conversational",
      eventTypes: ["conversational_action"],
      objectiveTypes: [],
      status: "partial",
      priority: "low",
      requiresTarget: true,
      targetType: "npc"
    },
    {
      actionId: "gossip",
      animation: "talk",
      displayName: "Gossip",
      category: "social",
      parentAction: "talk_to_npc",
      interactionMode: "conversational",
      eventTypes: ["conversational_action"],
      objectiveTypes: [],
      status: "partial",
      priority: "low",
      requiresTarget: true,
      targetType: "npc"
    },
    {
      actionId: "confess",
      animation: "talk",
      displayName: "Confess",
      category: "social",
      parentAction: "talk_to_npc",
      interactionMode: "conversational",
      eventTypes: ["conversational_action"],
      objectiveTypes: [],
      status: "partial",
      priority: "low",
      requiresTarget: true,
      targetType: "npc"
    },
    {
      actionId: "apologize",
      animation: "talk",
      displayName: "Apologize",
      category: "social",
      parentAction: "talk_to_npc",
      interactionMode: "conversational",
      eventTypes: ["conversational_action", "npc_relationship_changed"],
      objectiveTypes: [],
      status: "partial",
      priority: "low",
      requiresTarget: true,
      targetType: "npc"
    },
    {
      actionId: "comfort",
      animation: "talk",
      displayName: "Comfort",
      category: "social",
      parentAction: "talk_to_npc",
      interactionMode: "conversational",
      eventTypes: ["conversational_action", "npc_relationship_changed"],
      objectiveTypes: ["build_friendship"],
      status: "partial",
      priority: "low",
      requiresTarget: true,
      targetType: "npc"
    },
    {
      actionId: "argue",
      animation: "talk",
      displayName: "Argue",
      category: "social",
      parentAction: "talk_to_npc",
      interactionMode: "conversational",
      eventTypes: ["conversational_action", "npc_relationship_changed"],
      objectiveTypes: [],
      status: "partial",
      priority: "low",
      requiresTarget: true,
      targetType: "npc"
    },
    {
      actionId: "joke",
      animation: "talk",
      displayName: "Tell Joke",
      category: "social",
      parentAction: "talk_to_npc",
      interactionMode: "conversational",
      eventTypes: ["conversational_action"],
      objectiveTypes: [],
      status: "partial",
      priority: "low",
      requiresTarget: true,
      targetType: "npc"
    },
    {
      actionId: "share_story",
      animation: "talk",
      displayName: "Share Story",
      category: "social",
      parentAction: "talk_to_npc",
      interactionMode: "conversational",
      eventTypes: ["conversational_action"],
      objectiveTypes: [],
      status: "partial",
      priority: "low",
      requiresTarget: true,
      targetType: "npc"
    },
    {
      actionId: "ask_about",
      animation: "talk",
      displayName: "Ask About",
      category: "social",
      parentAction: "talk_to_npc",
      interactionMode: "conversational",
      eventTypes: ["conversational_action"],
      objectiveTypes: [],
      status: "partial",
      priority: "medium",
      requiresTarget: true,
      targetType: "npc"
    },
    // ─── Parent: express ───────────────────────────────────────────────────
    {
      actionId: "express",
      animation: "talk",
      displayName: "Express",
      category: "social",
      parentAction: null,
      interactionMode: "automatic",
      eventTypes: [],
      objectiveTypes: [],
      status: "implemented",
      requiresTarget: false
    },
    {
      actionId: "call_out",
      animation: "talk",
      displayName: "Call Out",
      category: "social",
      parentAction: "express",
      interactionMode: "animation",
      eventTypes: [],
      objectiveTypes: [],
      status: "animation-only",
      requiresTarget: false
    },
    {
      actionId: "dance",
      animation: "gesture",
      displayName: "Dance",
      category: "social",
      parentAction: "express",
      interactionMode: "animation",
      eventTypes: [],
      objectiveTypes: [],
      status: "animation-only",
      requiresTarget: false
    },
    {
      actionId: "fold_arms",
      animation: "gesture",
      displayName: "Fold Arms",
      category: "social",
      parentAction: "express",
      interactionMode: "animation",
      eventTypes: [],
      objectiveTypes: [],
      status: "animation-only",
      requiresTarget: false
    },
    {
      actionId: "nod_yes",
      animation: "gesture",
      displayName: "Nod Yes",
      category: "social",
      parentAction: "express",
      interactionMode: "animation",
      eventTypes: [],
      objectiveTypes: [],
      status: "animation-only",
      requiresTarget: false
    },
    {
      actionId: "shake_head_no",
      animation: "gesture",
      displayName: "Shake Head No",
      category: "social",
      parentAction: "express",
      interactionMode: "animation",
      eventTypes: [],
      objectiveTypes: [],
      status: "animation-only",
      requiresTarget: false
    },
    // ─── Parent: idle ──────────────────────────────────────────────────────
    {
      actionId: "idle",
      animation: "idle",
      displayName: "Idle",
      category: "social",
      parentAction: null,
      interactionMode: "animation",
      eventTypes: [],
      objectiveTypes: [],
      status: "animation-only",
      requiresTarget: false
    },
    {
      actionId: "sit_down",
      animation: "sit",
      displayName: "Sit Down",
      category: "social",
      parentAction: "idle",
      interactionMode: "animation",
      eventTypes: ["furniture_sat"],
      objectiveTypes: [],
      status: "animation-only",
      requiresTarget: false
    },
    {
      actionId: "sit_idle",
      animation: "sit",
      displayName: "Sit Idle",
      category: "social",
      parentAction: "idle",
      interactionMode: "animation",
      eventTypes: [],
      objectiveTypes: [],
      status: "animation-only",
      requiresTarget: false
    },
    {
      actionId: "stand_up",
      animation: "idle",
      displayName: "Stand Up",
      category: "social",
      parentAction: "idle",
      interactionMode: "animation",
      eventTypes: ["furniture_stood"],
      objectiveTypes: [],
      status: "animation-only",
      requiresTarget: false
    },
    {
      actionId: "get_up",
      animation: "idle",
      displayName: "Get Up",
      category: "social",
      parentAction: "idle",
      interactionMode: "animation",
      eventTypes: [],
      objectiveTypes: [],
      status: "animation-only",
      requiresTarget: false
    },
    {
      actionId: "lean_railing",
      animation: "sit",
      displayName: "Lean on Railing",
      category: "social",
      parentAction: "idle",
      interactionMode: "animation",
      eventTypes: [],
      objectiveTypes: [],
      status: "animation-only",
      requiresTarget: false
    },
    // ─── Social standalone ─────────────────────────────────────────────────
    {
      actionId: "give_gift",
      animation: "handle",
      displayName: "Give Gift",
      category: "social",
      parentAction: null,
      interactionMode: "physical",
      eventTypes: ["gift_given"],
      objectiveTypes: ["give_gift", "deliver_item"],
      status: "implemented",
      requiresTarget: true,
      targetType: "npc"
    },
    {
      actionId: "pray",
      animation: "gesture",
      displayName: "Pray",
      category: "social",
      parentAction: null,
      interactionMode: "physical",
      eventTypes: ["physical_action_completed"],
      objectiveTypes: ["physical_action"],
      status: "implemented",
      requiresTarget: false
    },
    {
      actionId: "escort_npc",
      animation: "walk",
      displayName: "Escort NPC",
      category: "social",
      parentAction: null,
      interactionMode: "automatic",
      eventTypes: ["escort_started", "escort_completed"],
      objectiveTypes: ["escort_npc"],
      status: "implemented",
      requiresTarget: true,
      targetType: "npc"
    },
    {
      actionId: "request_quest",
      animation: "talk",
      displayName: "Request Quest",
      category: "social",
      parentAction: null,
      interactionMode: "conversational",
      eventTypes: ["quest_accepted"],
      objectiveTypes: [],
      status: "implemented",
      requiresTarget: true,
      targetType: "npc"
    },
    {
      actionId: "steal",
      animation: "handle",
      displayName: "Steal",
      category: "social",
      parentAction: null,
      interactionMode: "physical",
      eventTypes: ["item_collected"],
      objectiveTypes: ["collect_item"],
      status: "partial",
      priority: "low",
      requiresTarget: true,
      targetType: "npc"
    },
    {
      actionId: "eavesdrop",
      animation: "listen",
      displayName: "Eavesdrop",
      category: "social",
      parentAction: null,
      interactionMode: "observational",
      eventTypes: ["conversation_overheard", "vocabulary_overheard"],
      objectiveTypes: ["observe_activity"],
      status: "implemented",
      requiresTarget: true,
      targetType: "npc"
    },
    // ═══════════════════════════════════════════════════════════════════════════
    // COMMERCE
    // ═══════════════════════════════════════════════════════════════════════════
    {
      actionId: "trade",
      animation: "handle",
      displayName: "Trade",
      category: "commerce",
      parentAction: null,
      interactionMode: "physical",
      eventTypes: ["item_purchased"],
      objectiveTypes: [],
      status: "implemented",
      requiresTarget: true,
      targetType: "npc"
    },
    {
      actionId: "buy_item",
      animation: "handle",
      displayName: "Buy Item",
      category: "commerce",
      parentAction: "trade",
      interactionMode: "physical",
      eventTypes: ["item_purchased"],
      objectiveTypes: ["collect_item"],
      status: "implemented",
      requiresTarget: true,
      targetType: "npc"
    },
    {
      actionId: "sell_item",
      animation: "handle",
      displayName: "Sell Item",
      category: "commerce",
      parentAction: "trade",
      interactionMode: "physical",
      eventTypes: ["item_purchased"],
      objectiveTypes: [],
      status: "implemented",
      requiresTarget: true,
      targetType: "npc"
    },
    // ═══════════════════════════════════════════════════════════════════════════
    // RESOURCE
    // ═══════════════════════════════════════════════════════════════════════════
    // ─── Parent: gather ────────────────────────────────────────────────────
    {
      actionId: "gather",
      animation: "work",
      displayName: "Gather",
      category: "resource",
      parentAction: null,
      interactionMode: "physical",
      eventTypes: ["physical_action_completed"],
      objectiveTypes: ["physical_action"],
      status: "implemented",
      requiresTarget: true,
      targetType: "object"
    },
    {
      actionId: "chop_tree",
      animation: "work",
      displayName: "Chop Tree",
      category: "resource",
      parentAction: "gather",
      interactionMode: "physical",
      eventTypes: ["physical_action_completed"],
      objectiveTypes: ["physical_action"],
      status: "implemented",
      requiresTarget: true,
      targetType: "object"
    },
    {
      actionId: "mine_rock",
      animation: "work",
      displayName: "Mine Rock",
      category: "resource",
      parentAction: "gather",
      interactionMode: "physical",
      eventTypes: ["physical_action_completed"],
      objectiveTypes: ["physical_action"],
      status: "implemented",
      requiresTarget: true,
      targetType: "object"
    },
    {
      actionId: "fish",
      animation: "work",
      displayName: "Fish",
      category: "resource",
      parentAction: "gather",
      interactionMode: "physical",
      eventTypes: ["physical_action_completed"],
      objectiveTypes: ["physical_action"],
      status: "implemented",
      requiresTarget: false
    },
    {
      actionId: "gather_herb",
      animation: "work",
      displayName: "Gather Herb",
      category: "resource",
      parentAction: "gather",
      interactionMode: "physical",
      eventTypes: ["physical_action_completed"],
      objectiveTypes: ["physical_action", "collect_item"],
      status: "implemented",
      requiresTarget: false
    },
    // ─── Parent: farm ──────────────────────────────────────────────────────
    {
      actionId: "farm",
      animation: "work",
      displayName: "Farm",
      category: "resource",
      parentAction: null,
      interactionMode: "physical",
      eventTypes: ["physical_action_completed"],
      objectiveTypes: ["physical_action"],
      status: "implemented",
      requiresTarget: true,
      targetType: "object"
    },
    {
      actionId: "farm_plant",
      animation: "work",
      displayName: "Plant Crops",
      category: "resource",
      parentAction: "farm",
      interactionMode: "physical",
      eventTypes: ["physical_action_completed"],
      objectiveTypes: ["physical_action"],
      status: "implemented",
      priority: "high",
      requiresTarget: true,
      targetType: "object"
    },
    {
      actionId: "farm_water",
      animation: "work",
      displayName: "Water Crops",
      category: "resource",
      parentAction: "farm",
      interactionMode: "physical",
      eventTypes: ["physical_action_completed"],
      objectiveTypes: ["physical_action"],
      status: "implemented",
      priority: "high",
      requiresTarget: true,
      targetType: "object"
    },
    {
      actionId: "farm_harvest",
      animation: "work",
      displayName: "Harvest Crops",
      category: "resource",
      parentAction: "farm",
      interactionMode: "physical",
      eventTypes: ["physical_action_completed", "item_collected"],
      objectiveTypes: ["physical_action", "collect_item"],
      status: "implemented",
      priority: "high",
      requiresTarget: true,
      targetType: "object"
    },
    // ─── Parent: craft_item ────────────────────────────────────────────────
    {
      actionId: "craft_item",
      animation: "work",
      displayName: "Craft Item",
      category: "resource",
      parentAction: null,
      interactionMode: "physical",
      eventTypes: ["item_crafted"],
      objectiveTypes: ["craft_item"],
      status: "partial",
      priority: "high",
      requiresTarget: false
    },
    {
      actionId: "cook",
      animation: "work",
      displayName: "Cook",
      category: "resource",
      parentAction: "craft_item",
      interactionMode: "physical",
      eventTypes: ["physical_action_completed", "item_crafted"],
      objectiveTypes: ["craft_item", "physical_action"],
      status: "implemented",
      requiresTarget: false
    },
    {
      actionId: "fix_repair",
      animation: "work",
      displayName: "Repair",
      category: "resource",
      parentAction: "craft_item",
      interactionMode: "physical",
      eventTypes: ["physical_action_completed"],
      objectiveTypes: ["physical_action"],
      status: "animation-only",
      requiresTarget: true,
      targetType: "object"
    },
    // ─── Parent: work ──────────────────────────────────────────────────────
    {
      actionId: "work",
      animation: "work",
      displayName: "Work",
      category: "resource",
      parentAction: null,
      interactionMode: "automatic",
      eventTypes: ["furniture_worked"],
      objectiveTypes: [],
      status: "implemented",
      requiresTarget: true,
      targetType: "building"
    },
    {
      actionId: "paint",
      animation: "work",
      displayName: "Paint",
      category: "resource",
      parentAction: "work",
      interactionMode: "physical",
      eventTypes: ["physical_action_completed"],
      objectiveTypes: ["physical_action"],
      status: "implemented",
      requiresTarget: false
    },
    {
      actionId: "sweep",
      animation: "work",
      displayName: "Sweep",
      category: "resource",
      parentAction: "work",
      interactionMode: "physical",
      eventTypes: ["physical_action_completed"],
      objectiveTypes: ["physical_action"],
      status: "implemented",
      requiresTarget: false
    },
    {
      actionId: "push_object",
      animation: "carry",
      displayName: "Push Object",
      category: "resource",
      parentAction: "work",
      interactionMode: "animation",
      eventTypes: ["physical_action_completed"],
      objectiveTypes: [],
      status: "animation-only",
      requiresTarget: true,
      targetType: "object"
    },
    // ═══════════════════════════════════════════════════════════════════════════
    // ITEMS
    // ═══════════════════════════════════════════════════════════════════════════
    {
      actionId: "use_item",
      animation: "handle",
      displayName: "Use Item",
      category: "items",
      parentAction: null,
      interactionMode: "inventory",
      eventTypes: ["item_used"],
      objectiveTypes: [],
      status: "implemented",
      requiresTarget: true,
      targetType: "item"
    },
    {
      actionId: "consume",
      animation: "eat",
      displayName: "Consume",
      category: "items",
      parentAction: "use_item",
      interactionMode: "inventory",
      eventTypes: ["item_used"],
      objectiveTypes: ["collect_item"],
      status: "implemented",
      requiresTarget: true,
      targetType: "item"
    },
    {
      actionId: "equip_item",
      animation: "handle",
      displayName: "Equip Item",
      category: "items",
      parentAction: "use_item",
      interactionMode: "inventory",
      eventTypes: ["item_equipped"],
      objectiveTypes: [],
      status: "implemented",
      requiresTarget: true,
      targetType: "item"
    },
    {
      actionId: "hold_lantern",
      animation: "carry",
      displayName: "Hold Lantern",
      category: "items",
      parentAction: "use_item",
      interactionMode: "animation",
      eventTypes: ["item_used"],
      objectiveTypes: [],
      status: "animation-only",
      requiresTarget: true,
      targetType: "item"
    },
    {
      actionId: "hold_torch",
      animation: "carry",
      displayName: "Hold Torch",
      category: "items",
      parentAction: "use_item",
      interactionMode: "animation",
      eventTypes: ["item_used"],
      objectiveTypes: [],
      status: "animation-only",
      requiresTarget: true,
      targetType: "item"
    },
    {
      actionId: "drop_item",
      animation: "handle",
      displayName: "Drop Item",
      category: "items",
      parentAction: null,
      interactionMode: "inventory",
      eventTypes: ["item_dropped"],
      objectiveTypes: [],
      status: "implemented",
      requiresTarget: true,
      targetType: "item"
    },
    {
      actionId: "collect_item",
      animation: "handle",
      displayName: "Collect Item",
      category: "items",
      parentAction: null,
      interactionMode: "physical",
      eventTypes: ["item_collected"],
      objectiveTypes: ["collect_item", "collect_text"],
      status: "implemented",
      requiresTarget: true,
      targetType: "item"
    },
    {
      actionId: "pick_up",
      animation: "handle",
      displayName: "Pick Up",
      category: "items",
      parentAction: "collect_item",
      interactionMode: "animation",
      eventTypes: ["item_collected"],
      objectiveTypes: [],
      status: "animation-only",
      requiresTarget: true,
      targetType: "item"
    },
    // ═══════════════════════════════════════════════════════════════════════════
    // EXPLORATION
    // ═══════════════════════════════════════════════════════════════════════════
    {
      actionId: "travel_to_location",
      animation: "walk",
      displayName: "Travel to Location",
      category: "exploration",
      parentAction: null,
      interactionMode: "automatic",
      eventTypes: ["location_visited", "location_discovered"],
      objectiveTypes: ["visit_location", "discover_location"],
      status: "implemented",
      requiresTarget: true,
      targetType: "location"
    },
    {
      actionId: "enter_building",
      animation: "walk",
      displayName: "Enter Building",
      category: "exploration",
      parentAction: null,
      interactionMode: "physical",
      eventTypes: ["location_visited"],
      objectiveTypes: ["visit_location"],
      status: "implemented",
      requiresTarget: true,
      targetType: "building"
    },
    {
      actionId: "open_container",
      animation: "handle",
      displayName: "Open Container",
      category: "exploration",
      parentAction: null,
      interactionMode: "physical",
      eventTypes: ["container_opened"],
      objectiveTypes: [],
      status: "implemented",
      requiresTarget: true,
      targetType: "container"
    },
    {
      actionId: "investigate",
      animation: "handle",
      displayName: "Investigate",
      category: "exploration",
      parentAction: null,
      interactionMode: "physical",
      eventTypes: ["investigation_completed", "clue_discovered"],
      objectiveTypes: [],
      status: "implemented",
      requiresTarget: true,
      targetType: "object"
    },
    {
      actionId: "observe_activity",
      animation: "listen",
      displayName: "Observe Activity",
      category: "exploration",
      parentAction: null,
      interactionMode: "observational",
      eventTypes: ["activity_observed"],
      objectiveTypes: ["observe_activity"],
      status: "partial",
      priority: "medium",
      requiresTarget: true,
      targetType: "npc"
    },
    {
      actionId: "take_photo",
      animation: "handle",
      displayName: "Take Photo",
      category: "exploration",
      parentAction: null,
      interactionMode: "physical",
      eventTypes: ["photo_taken"],
      objectiveTypes: ["photograph_subject", "photograph_activity"],
      status: "implemented",
      requiresTarget: true,
      targetType: "object"
    },
    {
      actionId: "mount_vehicle",
      animation: "ride",
      displayName: "Mount Vehicle",
      category: "exploration",
      parentAction: null,
      interactionMode: "physical",
      eventTypes: ["vehicle_mounted"],
      objectiveTypes: [],
      status: "implemented",
      requiresTarget: true,
      targetType: "object"
    },
    {
      actionId: "solve_puzzle",
      animation: "handle",
      displayName: "Solve Puzzle",
      category: "exploration",
      parentAction: null,
      interactionMode: "physical",
      eventTypes: ["puzzle_solved"],
      objectiveTypes: [],
      status: "implemented",
      requiresTarget: false
    },
    {
      actionId: "interact",
      animation: "handle",
      displayName: "Interact",
      category: "exploration",
      parentAction: null,
      interactionMode: "physical",
      eventTypes: [],
      objectiveTypes: [],
      status: "implemented",
      requiresTarget: true,
      targetType: "object"
    },
    // ═══════════════════════════════════════════════════════════════════════════
    // LANGUAGE
    // ═══════════════════════════════════════════════════════════════════════════
    {
      actionId: "read_sign",
      animation: "read",
      displayName: "Read Sign",
      category: "language",
      parentAction: null,
      interactionMode: "physical",
      eventTypes: ["sign_read"],
      objectiveTypes: ["read_sign"],
      status: "implemented",
      requiresTarget: true,
      targetType: "object"
    },
    {
      actionId: "examine_object",
      animation: "read",
      displayName: "Examine Object",
      category: "language",
      parentAction: null,
      interactionMode: "physical",
      eventTypes: ["object_examined"],
      objectiveTypes: ["examine_object", "collect_vocabulary"],
      status: "implemented",
      requiresTarget: true,
      targetType: "object"
    },
    {
      actionId: "point_and_name",
      animation: "gesture",
      displayName: "Point and Name",
      category: "language",
      parentAction: null,
      interactionMode: "physical",
      eventTypes: ["object_named"],
      objectiveTypes: ["point_and_name", "identify_object"],
      status: "implemented",
      requiresTarget: true,
      targetType: "object"
    },
    {
      actionId: "ask_for_directions",
      animation: "talk",
      displayName: "Ask for Directions",
      category: "language",
      parentAction: null,
      interactionMode: "conversational",
      eventTypes: ["conversational_action"],
      objectiveTypes: ["ask_for_directions", "navigate_language", "follow_directions"],
      status: "implemented",
      requiresTarget: true,
      targetType: "npc"
    },
    {
      actionId: "introduce_self",
      animation: "wave",
      displayName: "Introduce Yourself",
      category: "language",
      parentAction: null,
      interactionMode: "conversational",
      eventTypes: ["conversational_action"],
      objectiveTypes: ["introduce_self"],
      status: "implemented",
      requiresTarget: true,
      targetType: "npc"
    },
    {
      actionId: "order_food",
      animation: "talk",
      displayName: "Order Food",
      category: "language",
      parentAction: null,
      interactionMode: "conversational",
      eventTypes: ["conversational_action", "food_ordered"],
      objectiveTypes: ["order_food"],
      status: "implemented",
      requiresTarget: true,
      targetType: "npc"
    },
    {
      actionId: "haggle_price",
      animation: "talk",
      displayName: "Haggle Price",
      category: "language",
      parentAction: null,
      interactionMode: "conversational",
      eventTypes: ["conversational_action", "price_haggled"],
      objectiveTypes: ["haggle_price"],
      status: "implemented",
      requiresTarget: true,
      targetType: "npc"
    },
    {
      actionId: "describe_scene",
      animation: "talk",
      displayName: "Describe Scene",
      category: "language",
      parentAction: null,
      interactionMode: "conversational",
      eventTypes: ["conversational_action"],
      objectiveTypes: ["describe_scene"],
      status: "implemented",
      requiresTarget: true,
      targetType: "npc"
    },
    {
      actionId: "listen_and_repeat",
      animation: "talk",
      displayName: "Listen and Repeat",
      category: "language",
      parentAction: null,
      interactionMode: "conversational",
      eventTypes: ["utterance_evaluated"],
      objectiveTypes: ["listen_and_repeat", "pronunciation_check"],
      status: "partial",
      priority: "medium",
      requiresTarget: true,
      targetType: "npc"
    },
    {
      actionId: "write_response",
      animation: "read",
      displayName: "Write Response",
      category: "language",
      parentAction: null,
      interactionMode: "conversational",
      eventTypes: ["writing_submitted"],
      objectiveTypes: ["write_response", "translation_challenge"],
      status: "implemented",
      requiresTarget: false
    },
    {
      actionId: "answer_question",
      animation: "talk",
      displayName: "Answer Question",
      category: "language",
      parentAction: null,
      interactionMode: "conversational",
      eventTypes: ["conversational_action", "questions_answered"],
      objectiveTypes: ["comprehension_quiz", "listening_comprehension"],
      status: "implemented",
      requiresTarget: false
    },
    {
      actionId: "teach_vocabulary",
      animation: "talk",
      displayName: "Teach Vocabulary",
      category: "language",
      parentAction: null,
      interactionMode: "conversational",
      eventTypes: ["conversational_action", "vocabulary_used"],
      objectiveTypes: ["teach_vocabulary", "teach_phrase"],
      status: "partial",
      priority: "medium",
      requiresTarget: true,
      targetType: "npc"
    },
    {
      actionId: "learn_word",
      animation: "listen",
      displayName: "Learn Word",
      category: "language",
      parentAction: null,
      interactionMode: "automatic",
      eventTypes: ["vocabulary_used"],
      objectiveTypes: ["collect_vocabulary"],
      status: "implemented",
      requiresTarget: false
    },
    {
      actionId: "read_book",
      animation: "read",
      displayName: "Read Book",
      category: "language",
      parentAction: null,
      interactionMode: "physical",
      eventTypes: ["reading_completed", "text_collected"],
      objectiveTypes: ["read_text", "find_text"],
      status: "implemented",
      requiresTarget: true,
      targetType: "item"
    },
    // ═══════════════════════════════════════════════════════════════════════════
    // SURVIVAL
    // ═══════════════════════════════════════════════════════════════════════════
    {
      actionId: "rest",
      animation: "sit",
      displayName: "Rest",
      category: "survival",
      parentAction: null,
      interactionMode: "automatic",
      eventTypes: ["furniture_sat"],
      objectiveTypes: [],
      status: "implemented",
      requiresTarget: false
    },
    {
      actionId: "sleep",
      animation: "sleep",
      displayName: "Sleep",
      category: "survival",
      parentAction: "rest",
      interactionMode: "automatic",
      eventTypes: ["furniture_slept"],
      objectiveTypes: [],
      status: "implemented",
      requiresTarget: false
    },
    {
      actionId: "sit",
      animation: "sit",
      displayName: "Sit",
      category: "survival",
      parentAction: "rest",
      interactionMode: "automatic",
      eventTypes: ["furniture_sat"],
      objectiveTypes: [],
      status: "implemented",
      requiresTarget: false
    }
  ];
  var actionIndex = /* @__PURE__ */ new Map();
  for (const entry of ACTION_MATRIX) {
    actionIndex.set(entry.actionId, entry);
  }
  var eventToActionsIndex = /* @__PURE__ */ new Map();
  for (const entry of ACTION_MATRIX) {
    for (const eventType of entry.eventTypes) {
      const list = eventToActionsIndex.get(eventType) || [];
      list.push(entry);
      eventToActionsIndex.set(eventType, list);
    }
  }
  var objectiveToActionsIndex = /* @__PURE__ */ new Map();
  for (const entry of ACTION_MATRIX) {
    for (const objType of entry.objectiveTypes) {
      const list = objectiveToActionsIndex.get(objType) || [];
      list.push(entry);
      objectiveToActionsIndex.set(objType, list);
    }
  }
  var childrenIndex = /* @__PURE__ */ new Map();
  for (const entry of ACTION_MATRIX) {
    if (entry.parentAction) {
      const list = childrenIndex.get(entry.parentAction) || [];
      list.push(entry);
      childrenIndex.set(entry.parentAction, list);
    }
  }
  function getActionAnimation(actionId) {
    return actionIndex.get(actionId)?.animation;
  }

  // @insimul/core/src/ai/action-selection.ts
  var NO_TARGET = "none";
  function agentRefKey(agent) {
    return typeof agent === "string" ? agent : formatCurie(agent);
  }
  var DEFAULT_UTILITY_WEIGHTS = Object.freeze({
    appeal: 1,
    targetAppeal: 0.3,
    cost: 0.1,
    bias: 0.5,
    jitter: 0.05,
    costScale: 100,
    windedCost: 2,
    exhaustedCost: 5
  });

  // @insimul/core/src/ai/rule-enforcement.ts
  var UNCLASSIFIED_NORM = "unclassified";
  function actFacts(acts) {
    return acts.map(
      (act) => `act(${prologAtom(act.event)}, ${prologAtom(agentRefKey(act.actor))}, ${prologAtom(act.action)}, ${prologAtom(act.target ?? NO_TARGET)}).`
    ).sort(compareIds);
  }
  var MAX_ENFORCEMENT_SOLUTIONS = 256;
  async function checkAction(engine, input) {
    const agent = agentRefKey(input.agent);
    const target = input.target ?? NO_TARGET;
    const breached = await breachedNorms(
      engine,
      `forbidden_by(${prologAtom(agent)}, ${prologAtom(input.action)}, ${prologAtom(target)}, Rule)`
    );
    return { agent, action: input.action, target, permitted: breached.length === 0, breached };
  }
  async function enforceActs(engine, input) {
    const world = worldContextTerm(input.playthrough);
    const violations = [];
    const consequenceFacts = [];
    for (const event of input.events) {
      const eventAtom = prologAtom(event);
      for (const breach of await breachesOf(engine, eventAtom)) {
        const ruleAtom = prologAtom(breach.rule);
        const actorAtom = prologAtom(breach.actor);
        const witnesses = await witnessesOf(engine, eventAtom, ruleAtom);
        const truths = await truthsOf(engine, eventAtom, ruleAtom, breach.actor);
        const reputation = await reputationOf(engine, eventAtom, ruleAtom);
        violations.push({
          event,
          rule: breach.rule,
          kind: await normKind(engine, ruleAtom),
          actor: breach.actor,
          action: breach.action,
          target: breach.target,
          witnesses,
          truths,
          reputation
        });
        for (const witness of witnesses) {
          consequenceFacts.push(
            `violation_record(${eventAtom}, ${ruleAtom}, ${actorAtom}, ${prologAtom(witness)}).`
          );
        }
        for (const truth of truths) {
          consequenceFacts.push(
            `claim(${prologAtom(truth.subject)}, ${prologAtom(truth.predicate)}, ${prologAtom(truth.object)}, ${world}).`
          );
        }
        for (const effect of reputation) {
          consequenceFacts.push(
            `reputation_change(${actorAtom}, ${prologAtom(effect.faction)}, ${effect.delta}).`
          );
        }
      }
    }
    violations.sort((a, b) => compareIds(a.event, b.event) || compareIds(a.rule, b.rule));
    consequenceFacts.sort(compareIds);
    return { tick: input.tick, violations, consequenceFacts };
  }
  async function solve(engine, goal) {
    const result = await engine.query(goal, MAX_ENFORCEMENT_SOLUTIONS);
    if (!result.success) {
      throw new Error(`rule enforcement: "${goal}" raised: ${result.error ?? "unknown error"}`);
    }
    return result.bindings;
  }
  async function breachesOf(engine, eventAtom) {
    const byKey = /* @__PURE__ */ new Map();
    for (const binding of await solve(
      engine,
      `violation_of(${eventAtom}, Rule, Actor, Act, T)`
    )) {
      const rule = text(binding["Rule"]);
      const actor = text(binding["Actor"]);
      const action = text(binding["Act"]);
      const target = text(binding["T"]);
      if (rule === null || actor === null || action === null || target === null) continue;
      byKey.set(streamKey([rule, actor, action, target]), { rule, actor, action, target });
    }
    return Array.from(byKey.values()).sort(
      (a, b) => compareIds(a.rule, b.rule) || compareIds(a.actor, b.actor)
    );
  }
  async function breachedNorms(engine, goal) {
    const rules = /* @__PURE__ */ new Set();
    for (const binding of await solve(engine, goal)) {
      const rule = text(binding["Rule"]);
      if (rule !== null) rules.add(rule);
    }
    const norms = [];
    for (const rule of Array.from(rules).sort(compareIds)) {
      norms.push({ rule, kind: await normKind(engine, prologAtom(rule)) });
    }
    return norms;
  }
  async function normKind(engine, ruleAtom) {
    let smallest = null;
    for (const binding of await solve(engine, `norm_kind(${ruleAtom}, K)`)) {
      const kind = text(binding["K"]);
      if (kind === null) continue;
      if (smallest === null || compareIds(kind, smallest) < 0) smallest = kind;
    }
    return smallest ?? UNCLASSIFIED_NORM;
  }
  async function witnessesOf(engine, eventAtom, ruleAtom) {
    const witnesses = /* @__PURE__ */ new Set();
    for (const binding of await solve(
      engine,
      `witnessed_violation(${eventAtom}, ${ruleAtom}, W)`
    )) {
      const witness = text(binding["W"]);
      if (witness !== null) witnesses.add(witness);
    }
    return Array.from(witnesses).sort(compareIds);
  }
  async function truthsOf(engine, eventAtom, ruleAtom, actor) {
    const byKey = /* @__PURE__ */ new Map();
    for (const binding of await solve(
      engine,
      `enforced_truth(${eventAtom}, ${ruleAtom}, _, P, O)`
    )) {
      const predicate = text(binding["P"]);
      const object = text(binding["O"]);
      if (predicate === null || object === null) continue;
      byKey.set(streamKey([predicate, object]), { subject: actor, predicate, object });
    }
    return Array.from(byKey.values()).sort(
      (a, b) => compareIds(a.predicate, b.predicate) || compareIds(a.object, b.object)
    );
  }
  async function reputationOf(engine, eventAtom, ruleAtom) {
    const rows = /* @__PURE__ */ new Map();
    for (const binding of await solve(
      engine,
      `enforced_reputation(${eventAtom}, ${ruleAtom}, _, F, D)`
    )) {
      const faction = text(binding["F"]);
      const delta = num(binding["D"]);
      if (faction === null || delta === null) continue;
      rows.set(streamKey([faction, String(delta)]), { faction, delta });
    }
    const byFaction = /* @__PURE__ */ new Map();
    for (const row of rows.values()) {
      byFaction.set(row.faction, (byFaction.get(row.faction) ?? 0) + row.delta);
    }
    return Array.from(byFaction.entries()).map(([faction, delta]) => ({ faction, delta })).sort((a, b) => compareIds(a.faction, b.faction));
  }
  function text(value) {
    if (typeof value === "string") return value;
    if (typeof value === "number") return String(value);
    return null;
  }
  function num(value) {
    if (typeof value === "number") return Number.isFinite(value) ? value : null;
    if (typeof value === "string") {
      const parsed = Number(value);
      return Number.isFinite(parsed) ? parsed : null;
    }
    return null;
  }

  // @insimul/core/src/identity/equivalence.ts
  function claimFact(subject, predicate, object, world) {
    return claimTermFact(subject, predicate, formatIdTerm(object), world);
  }
  function claimTermFact(subject, predicate, objectTerm, world) {
    return `claim(${formatIdTerm(subject)}, ${prologAtom(predicate)}, ${objectTerm}, ${worldContextTerm(world)}).`;
  }

  // @insimul/core/src/ai/belief-worlds.ts
  var BELIEF_LOCAL_ID_PREFIX = "belief-";
  function beliefWorldId(playthrough, agent) {
    if (playthrough.kind !== "world") {
      throw new Error(`beliefWorldId: not a world: "${formatCurie(playthrough)}"`);
    }
    return {
      kind: "world",
      namespace: formatCurie(playthrough),
      localId: BELIEF_LOCAL_ID_PREFIX + sanitizeLocalId(formatCurie(agent))
    };
  }
  function beliefWorldDeclaration(playthrough, agent) {
    return {
      world: beliefWorldId(playthrough, agent),
      parent: null,
      role: "belief",
      inheritsIdentity: false
    };
  }
  function beliefWorldFacts(playthrough, agent) {
    const declaration = beliefWorldDeclaration(playthrough, agent);
    return [
      ...worldFacts(declaration),
      `agent_belief_world(${formatIdTerm(agent)}, ${formatIdTerm(declaration.world)}).`
    ];
  }

  // @insimul/core/src/ai/perception.ts
  var DEFAULT_PERCEPTION_THRESHOLDS = Object.freeze({
    clear: 0.6,
    partial: 0.25,
    jitter: 0.1
  });
  function perceive(input) {
    const thresholds = { ...DEFAULT_PERCEPTION_THRESHOLDS, ...input.thresholds };
    const agentsByCurie = /* @__PURE__ */ new Map();
    for (const agent of input.agents) agentsByCurie.set(formatCurie(agent.agent), agent);
    const perceptsById = /* @__PURE__ */ new Map();
    for (const percept of input.percepts) perceptsById.set(percept.id, percept);
    const pairs = /* @__PURE__ */ new Map();
    for (const exposure of input.exposures) {
      const agentCurie = formatCurie(exposure.agent);
      if (!agentsByCurie.has(agentCurie) || !perceptsById.has(exposure.percept)) continue;
      const key = streamKey([agentCurie, exposure.percept]);
      const clarity = clamp01(exposure.clarity);
      const prev = pairs.get(key);
      if (prev === void 0 || clarity > prev.clarity) {
        pairs.set(key, { agentCurie, perceptId: exposure.percept, clarity });
      }
    }
    const perceptions = [];
    for (const { agentCurie, perceptId, clarity } of pairs.values()) {
      const agent = agentsByCurie.get(agentCurie);
      const percept = perceptsById.get(perceptId);
      const acuity = acuityFor(agent, percept.channel);
      if (acuity === null) continue;
      const base = clarity * clamp01(acuity) * clamp01(percept.strength / 100);
      const noise = thresholds.jitter === 0 ? 0 : (derivedValue(input.seed, input.tick, agentCurie, perceptId) * 2 - 1) * thresholds.jitter;
      const confidence = roundDeterministic(clamp01(base + noise));
      const fidelity = fidelityOf(confidence, thresholds);
      if (fidelity === null) continue;
      const learned = learnedTriple(percept, fidelity);
      perceptions.push({
        agent: agentCurie,
        percept: perceptId,
        channel: percept.channel,
        fidelity,
        confidence,
        belief: {
          subject: formatCurie(learned.subject),
          predicate: percept.predicate,
          object: formatCurie(learned.object)
        }
      });
    }
    perceptions.sort(
      (a, b) => compareIds(a.agent, b.agent) || compareIds(a.percept, b.percept)
    );
    return {
      perceptions,
      beliefWorldFacts: beliefWorldFactsFor(input.playthrough, perceptions, agentsByCurie),
      beliefFacts: beliefFactsFor(input.playthrough, perceptions, agentsByCurie, perceptsById),
      perceptFacts: perceptFactsFor(perceptions, perceptsById),
      perceivedFacts: perceptions.map(
        (p) => `perceived(${formatIdTerm(agentsByCurie.get(p.agent).agent)}, ${prologAtom(p.percept)}, ${p.channel}, ${p.fidelity}).`
      )
    };
  }
  function acuityFor(agent, channel) {
    let best = null;
    for (const sense of agent.senses) {
      if (sense.channel !== channel) continue;
      if (best === null || sense.acuity > best) best = sense.acuity;
    }
    return best;
  }
  function fidelityOf(score, thresholds) {
    if (score >= thresholds.clear) return "clear";
    if (score >= thresholds.partial) return "partial";
    return null;
  }
  function learnedTriple(percept, fidelity) {
    if (fidelity === "clear") return { subject: percept.subject, object: percept.object };
    return {
      subject: percept.coarseSubject ?? percept.subject,
      object: percept.coarseObject ?? percept.object
    };
  }
  function beliefWorldFactsFor(playthrough, perceptions, agentsByCurie) {
    const seen = /* @__PURE__ */ new Set();
    const facts = [];
    for (const perception of perceptions) {
      if (seen.has(perception.agent)) continue;
      seen.add(perception.agent);
      facts.push(...beliefWorldFacts(playthrough, agentsByCurie.get(perception.agent).agent));
    }
    return facts;
  }
  function beliefFactsFor(playthrough, perceptions, agentsByCurie, perceptsById) {
    return perceptions.map((perception) => {
      const percept = perceptsById.get(perception.percept);
      const learned = learnedTriple(percept, perception.fidelity);
      const agent = agentsByCurie.get(perception.agent).agent;
      return claimFact(
        learned.subject,
        percept.predicate,
        learned.object,
        beliefWorldId(playthrough, agent)
      );
    });
  }
  function perceptFactsFor(perceptions, perceptsById) {
    const perceived = new Set(perceptions.map((p) => p.percept));
    const ids = [...perceptsById.keys()].filter((id) => perceived.has(id) || perceptsById.get(id).actor !== void 0).sort(compareIds);
    const facts = [];
    for (const id of ids) {
      const percept = perceptsById.get(id);
      const atom3 = prologAtom(id);
      if (perceived.has(id)) {
        facts.push(
          `percept(${atom3}, ${formatIdTerm(percept.subject)}, ${prologAtom(percept.predicate)}, ${formatIdTerm(percept.object)}).`
        );
      }
      facts.push(`percept_channel(${atom3}, ${percept.channel}).`);
      if (percept.actor) facts.push(`percept_actor(${atom3}, ${formatIdTerm(percept.actor)}).`);
    }
    return facts;
  }

  // @insimul/core/src/perception/detection.ts
  var DETECTION_STATES = ["unaware", "suspicious", "searching", "alerted"];
  var DETECTION_THRESHOLD_NAMES = ["suspicious", "searching", "alerted"];
  function detectionRank(state) {
    return DETECTION_STATES.indexOf(state);
  }
  var DEFAULT_DETECTION_TUNING = Object.freeze({
    thresholds: Object.freeze({ suspicious: 25, searching: 50, alerted: 80 }),
    gain: 12,
    decay: 6,
    hysteresis: 10,
    senseWeights: Object.freeze({ sight: 1, hearing: 0.6, smell: 0.3, touch: 1 }),
    lightFloor: 10,
    lightReference: 60,
    coverWeight: 0.75,
    concealmentMultiplier: 0.35,
    stanceVisibility: Object.freeze({ standing: 1, crouching: 0.7, prone: 0.45 }),
    stanceNoise: Object.freeze({ standing: 1, crouching: 0.5, prone: 0.25 }),
    distractionWeight: 0.75,
    fidelity: DEFAULT_PERCEPTION_THRESHOLDS
  });
  function detectionStateFor(awareness, thresholds) {
    if (awareness >= thresholds.alerted) return "alerted";
    if (awareness >= thresholds.searching) return "searching";
    if (awareness >= thresholds.suspicious) return "suspicious";
    return "unaware";
  }
  function detectionThresholdOf(state, thresholds) {
    return state === "unaware" ? 0 : thresholds[state];
  }
  function nextDetectionState(previous, awareness, tuning) {
    const raw = detectionStateFor(awareness, tuning.thresholds);
    if (detectionRank(raw) >= detectionRank(previous)) return raw;
    const held = detectionThresholdOf(previous, tuning.thresholds) - tuning.hysteresis;
    return awareness >= held ? previous : raw;
  }
  function runDetection(input) {
    const tuning = input.tuning ?? DEFAULT_DETECTION_TUNING;
    const targetsByCurie = /* @__PURE__ */ new Map();
    for (const target of input.targets) targetsByCurie.set(formatCurie(target.id), target);
    const observersByCurie = /* @__PURE__ */ new Map();
    for (const observer of input.observers) observersByCurie.set(formatCurie(observer.agent), observer);
    const percepts = input.targets.map((target) => sightingPercept(target, tuning));
    const sounds = input.targets.map((target) => soundPercept(target, tuning));
    const acts = (input.acts ?? []).filter((act) => targetsByCurie.has(formatCurie(act.actor)));
    const actPercepts = acts.map((act) => actPercept(act));
    const exposures = [];
    for (const reading2 of input.readings) {
      const observerCurie = formatCurie(reading2.observer);
      const targetCurie = formatCurie(reading2.target);
      if (!observersByCurie.has(observerCurie) || !targetsByCurie.has(targetCurie)) continue;
      const target = targetsByCurie.get(targetCurie);
      exposures.push({
        agent: reading2.observer,
        percept: sightingPerceptId(targetCurie),
        clarity: sightClarity(reading2, target, tuning)
      });
      exposures.push({
        agent: reading2.observer,
        percept: soundPerceptId(targetCurie),
        clarity: clamp01(reading2.audibility ?? 1)
      });
      for (const act of acts) {
        if (formatCurie(act.actor) !== targetCurie) continue;
        exposures.push({
          agent: reading2.observer,
          percept: act.event,
          clarity: actClarity(act, reading2, target, tuning)
        });
      }
    }
    const perception = perceive({
      seed: input.seed,
      tick: input.tick,
      playthrough: input.playthrough,
      agents: input.observers.map(toPerceivingAgent),
      percepts: [...percepts, ...sounds, ...actPercepts],
      exposures,
      thresholds: tuning.fidelity
    });
    const pairs = /* @__PURE__ */ new Map();
    const pairKey2 = (observer, target) => streamKey([observer, target]);
    for (const memory of input.memory ?? []) {
      pairs.set(pairKey2(memory.observer, memory.target), {
        observer: memory.observer,
        target: memory.target,
        prior: { ...memory },
        perceptions: []
      });
    }
    const actIds = new Set(acts.map((act) => act.event));
    for (const perceived of perception.perceptions) {
      if (actIds.has(perceived.percept)) continue;
      const targetCurie = targetOfPerceptId(perceived.percept);
      if (targetCurie === null || !targetsByCurie.has(targetCurie)) continue;
      const key = pairKey2(perceived.agent, targetCurie);
      const work = pairs.get(key);
      if (work) work.perceptions.push(perceived);
      else {
        pairs.set(key, {
          observer: perceived.agent,
          target: targetCurie,
          prior: void 0,
          perceptions: [perceived]
        });
      }
    }
    const decided = [];
    for (const work of pairs.values()) {
      const update = resolvePair(work, observersByCurie.get(work.observer), input.tick, tuning);
      decided.push({
        update,
        memory: {
          observer: update.observer,
          target: update.target,
          awareness: update.awareness,
          state: update.state,
          believedLocation: update.believedLocation,
          believedAt: update.believedAt,
          lastPerceivedTick: update.beliefRefreshed ? input.tick : work.prior?.lastPerceivedTick
        }
      });
    }
    decided.sort(
      (a, b) => compareIds(a.update.observer, b.update.observer) || compareIds(a.update.target, b.update.target)
    );
    return {
      updates: decided.map((d) => d.update),
      memory: decided.map((d) => d.memory),
      perception
    };
  }
  function resolvePair(work, observer, tick, tuning) {
    const before = work.prior?.awareness ?? 0;
    const stateBefore = work.prior?.state ?? "unaware";
    const perceptions = [...work.perceptions].sort((a, b) => compareIds(a.percept, b.percept));
    let raw = 0;
    let confidence = 0;
    const channels = [];
    for (const perception of perceptions) {
      const weight = tuning.senseWeights[perception.channel] ?? 0;
      raw += perception.confidence * weight;
      if (perception.confidence > confidence) confidence = perception.confidence;
      if (!channels.includes(perception.channel)) channels.push(perception.channel);
    }
    channels.sort(compareIds);
    const attention = 1 - clamp01((observer?.distraction ?? 0) / 100) * clamp01(tuning.distractionWeight);
    const delta = perceptions.length === 0 ? -Math.round(tuning.decay) : Math.round(raw * tuning.gain * attention);
    const awareness = clampAwareness(before + delta);
    const state = nextDetectionState(stateBefore, awareness, tuning);
    const best = strongestPerception(perceptions);
    const believedLocation = best ? best.belief.object : work.prior?.believedLocation;
    const believedAt = best ? tick : work.prior?.believedAt;
    return {
      observer: work.observer,
      target: work.target,
      awarenessBefore: before,
      awareness,
      stateBefore,
      state,
      changed: state !== stateBefore,
      channels,
      confidence: roundDeterministic(confidence),
      believedLocation,
      believedAt,
      beliefRefreshed: best !== void 0
    };
  }
  function strongestPerception(perceptions) {
    let best;
    for (const perception of perceptions) {
      if (best === void 0 || perception.confidence > best.confidence || perception.confidence === best.confidence && compareIds(perception.percept, best.percept) < 0) {
        best = perception;
      }
    }
    return best;
  }
  function clampAwareness(level) {
    if (!Number.isFinite(level) || level < 0) return 0;
    return level > 100 ? 100 : Math.round(level);
  }
  function sightingPerceptId(targetCurie) {
    return `sighting:${targetCurie}`;
  }
  function soundPerceptId(targetCurie) {
    return `sound:${targetCurie}`;
  }
  function targetOfPerceptId(perceptId) {
    if (perceptId.startsWith("sighting:")) return perceptId.slice("sighting:".length);
    if (perceptId.startsWith("sound:")) return perceptId.slice("sound:".length);
    return null;
  }
  function sightingPercept(target, tuning) {
    const curie = formatCurie(target.id);
    const stance = target.stance ?? "standing";
    const strength = 100 * lightFactor(target.light, tuning) * clamp01(tuning.stanceVisibility[stance] ?? 1);
    return {
      id: sightingPerceptId(curie),
      subject: target.id,
      predicate: "at_location",
      object: target.location,
      channel: "sight",
      strength,
      coarseObject: target.coarseLocation
    };
  }
  function soundPercept(target, tuning) {
    const curie = formatCurie(target.id);
    const stance = target.stance ?? "standing";
    const strength = clampLevel(target.noise ?? 0) * clamp01(tuning.stanceNoise[stance] ?? 1);
    return {
      id: soundPerceptId(curie),
      subject: target.id,
      predicate: "at_location",
      object: target.location,
      channel: "hearing",
      strength,
      coarseObject: target.coarseLocation
    };
  }
  function actPercept(act) {
    return {
      id: act.event,
      subject: act.actor,
      predicate: act.action,
      object: act.object,
      channel: act.channel,
      strength: clampLevel(act.strength),
      actor: act.actor,
      coarseSubject: act.coarseActor,
      coarseObject: act.coarseObject
    };
  }
  function actClarity(act, reading2, target, tuning) {
    if (act.channel === "hearing") return clamp01(reading2.audibility ?? 1);
    if (act.channel === "sight") return sightClarity(reading2, target, tuning);
    return clamp01(reading2.visibility);
  }
  function sightClarity(reading2, target, tuning) {
    const cover = 1 - clamp01(reading2.cover ?? 0) * clamp01(tuning.coverWeight);
    const concealment = target.concealed ? clamp01(tuning.concealmentMultiplier) : 1;
    return clamp01(clamp01(reading2.visibility) * cover * concealment);
  }
  function lightFactor(light, tuning) {
    if (light === void 0) return 1;
    const span = tuning.lightReference - tuning.lightFloor;
    if (span <= 0) return clampLevel(light) > tuning.lightFloor ? 1 : 0;
    return clamp01((clampLevel(light) - tuning.lightFloor) / span);
  }
  function clampLevel(level) {
    if (!Number.isFinite(level) || level < 0) return 0;
    return level > 100 ? 100 : level;
  }
  function toPerceivingAgent(observer) {
    return { agent: observer.agent, senses: observer.senses };
  }
  function detectionEntityId(id, namespace) {
    if (id.split(":").length >= 3) {
      try {
        return parseCurie(id);
      } catch {
      }
    }
    return provisionalEntityId(sanitizeLocalId(id), namespace);
  }

  // @insimul/core/src/perception/detection-facts.ts
  var DETECTION_RESOLUTION_PREDICATES = Object.freeze([
    "awareness/3",
    "detection_state/3"
  ]);
  var DETECTION_AUTHORED_PREDICATES = Object.freeze([
    "detection_threshold/2"
  ]);
  function awarenessFact(observer, target, level) {
    return `awareness(${formatIdTerm(observer)}, ${formatIdTerm(target)}, ${Math.round(level)}).`;
  }
  function detectionStateFact(observer, target, state) {
    return `detection_state(${formatIdTerm(observer)}, ${formatIdTerm(target)}, ${state}).`;
  }
  function detectionFacts(update) {
    const delta = { retract: [], assert: [] };
    const observer = parseCurie(update.observer);
    const target = parseCurie(update.target);
    if (update.awareness !== update.awarenessBefore) {
      if (update.awarenessBefore !== 0) {
        delta.retract.push(awarenessFact(observer, target, update.awarenessBefore));
      }
      if (update.awareness !== 0) delta.assert.push(awarenessFact(observer, target, update.awareness));
    }
    if (update.changed) {
      if (update.stateBefore !== "unaware") {
        delta.retract.push(detectionStateFact(observer, target, update.stateBefore));
      }
      if (update.state !== "unaware") {
        delta.assert.push(detectionStateFact(observer, target, update.state));
      }
    }
    return delta;
  }
  function detectionPassFacts(updates) {
    const delta = { retract: [], assert: [] };
    for (const update of updates) {
      const one = detectionFacts(update);
      delta.retract.push(...one.retract);
      delta.assert.push(...one.assert);
    }
    return delta;
  }
  function detectionThresholdFacts(tuning) {
    return DETECTION_THRESHOLD_NAMES.map(
      (name) => `detection_threshold(${name}, ${Math.round(tuning.thresholds[name])}).`
    );
  }

  // @insimul/core/src/save-extensions.ts
  var extensionRegistry = {
    introShown: {
      owner: "intro-system",
      describe: "Whether the player has seen the opening intro cinematic for this save.",
      defaultValue: false
    },
    evaluations: {
      owner: "assessment-framework",
      describe: "Per-playthrough research evaluation responses (US-018). Replaces the legacy assessments collection.",
      defaultValue: []
    },
    sessions: {
      owner: "session-tracker",
      describe: "Array of SessionEntry records \u2014 one per play session for this save. Appended on createPlayerSession, finalized on endPlayerSession.",
      defaultValue: []
    },
    gamification: {
      owner: "language-gamification",
      describe: "GamificationState: XP/level, achievements unlocked, daily challenge, streaks, and lifetime counters (quests, NPCs talked, articles read, etc.). Written by LanguageGamificationTracker. Some saves still carry this at currentState.gamification (legacy position) \u2014 endpoints read both.",
      defaultValue: null
    },
    playthroughTelemetry: {
      owner: "telemetry",
      describe: "Rolling-window buffer of per-playthrough telemetry events (US-019). Capped at PLAYTHROUGH_TELEMETRY_MAX_EVENTS; oldest events drop on overflow.",
      defaultValue: []
    },
    droppedFacts: {
      owner: "prolog-migration",
      describe: "Prolog facts dropped during save migration because their predicate signature no longer matches the current schema. Each entry: {predicate, reason}.",
      defaultValue: []
    },
    skillTree: {
      owner: "skill-system",
      describe: "Skill-tree progression: unlocked node IDs and unspent skill points. Shape: {unlockedNodes: string[], availablePoints: number}. Registered preemptively; no production writer yet.",
      defaultValue: null
    },
    aiBlackboards: {
      owner: "ai-substrate",
      describe: "Per-agent working state for the game-AI substrate (US-1, 113-game-ai-substrate), keyed by the agent's CURIE. Shape: {[agentCurie]: {agent, updatedTick, slots}} with scalar slot values. Written by src/ai/blackboard.ts. Per-playthrough by definition: a world template must never carry it \u2014 findBlackboardLeaks() is the guard.",
      defaultValue: {}
    },
    detectionStates: {
      owner: "perception",
      describe: "Graded detection state per (observer, target) pair for the stealth module (US-2, 121-stealth-and-perception). Shape: {pairs: [{observer, target, awareness, state, believedLocation?, believedAt?, lastPerceivedTick?}]} \u2014 written by DetectionTracker.serialize() and read back through its constructor. Per-playthrough by definition: how convinced a guard has become and where they BELIEVE you are belong to one playthrough, while the thresholds, rates and stance weights that decide them are authored (WorldIR.perception) and must never ride here \u2014 findDetectionTuningLeaks() is the guard.",
      defaultValue: { pairs: [] }
    },
    achievements: {
      owner: "gamification",
      describe: "Per-playthrough achievement-earned records. Shape: {earned: Array<{id, earnedAt}>}. Registered for fixtures that persist achievement state outside the gamification bag; the canonical achievement list lives in `gamification.achievements`.",
      defaultValue: null
    }
  };
  function isRegisteredExtension(key) {
    return Object.prototype.hasOwnProperty.call(extensionRegistry, key);
  }
  function isDevWarningEnabled() {
    const env = typeof process !== "undefined" && process?.env ? process.env.NODE_ENV : void 0;
    if (env === "production") return false;
    return true;
  }
  function writeExtension(extensions, key, value) {
    if (!isRegisteredExtension(key) && isDevWarningEnabled()) {
      try {
        console.warn(
          `[save-extensions] writing unregistered extension "${key}". Register it in shared/save-extensions.ts::extensionRegistry before writing.`
        );
      } catch {
      }
    }
    extensions[key] = value;
  }

  // @insimul/core/src/perception/detection-save.ts
  var DETECTION_EXTENSION_KEY = "detectionStates";
  var DETECTION_AUTHORED_FIELDS = Object.freeze([
    "thresholds",
    "gain",
    "decay",
    "hysteresis",
    "senseWeights",
    "lightFloor",
    "lightReference",
    "coverWeight",
    "concealmentMultiplier",
    "stanceVisibility",
    "stanceNoise",
    "distractionWeight",
    "fidelity"
  ]);
  function readDetectionState(extensions) {
    const raw = extensions?.[DETECTION_EXTENSION_KEY];
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) return { pairs: [] };
    const pairs = raw.pairs;
    if (!Array.isArray(pairs)) return { pairs: [] };
    return { pairs: pairs.filter(isPairState).map((pair) => ({ ...pair })) };
  }
  function writeDetectionState(extensions, state) {
    const stored = {
      pairs: (state.pairs ?? []).filter(isPairState).map((pair) => ({ ...pair }))
    };
    writeExtension(extensions, DETECTION_EXTENSION_KEY, stored);
    return stored;
  }
  function isPairState(value) {
    if (!value || typeof value !== "object" || Array.isArray(value)) return false;
    const pair = value;
    return typeof pair.observer === "string" && typeof pair.target === "string" && typeof pair.awareness === "number" && typeof pair.state === "string";
  }

  // @insimul/core/src/perception/stealth-actions.ts
  var STEALTH_ACTION_CATEGORY = "stealth";
  var DEFAULT_STEALTH_ACTIONS = Object.freeze([
    Object.freeze({
      id: "hide",
      name: "Hide",
      energyCost: 5,
      conceals: true,
      stance: "crouching",
      noise: 0,
      // Breaking contact does not erase what a guard already believes; it costs
      // them the thread. The ladder's own decay does the rest.
      awarenessDelta: -10,
      presence: { channel: "sight", strength: 20 }
    }),
    Object.freeze({
      id: "sneak",
      name: "Sneak",
      energyCost: 10,
      stance: "crouching",
      noise: 10,
      presence: { channel: "sight", strength: 30 }
    }),
    Object.freeze({
      id: "distract",
      name: "Distract",
      requiresTarget: true,
      targetType: "person",
      energyCost: 10,
      distraction: 60,
      noise: 70,
      presence: { channel: "hearing", strength: 70 }
    }),
    Object.freeze({
      id: "take_down",
      name: "Take down",
      requiresTarget: true,
      targetType: "person",
      energyCost: 30,
      incapacitates: true,
      noise: 40,
      presence: { channel: "sight", strength: 80 }
    })
  ]);
  function stealthActionFrom(row, columns) {
    const id = columns?.id ?? row?.id;
    if (!id) throw new Error("stealthActionFrom: an action row must have an id");
    const action = { id };
    const name = columns?.name ?? row?.name;
    if (name) action.name = name;
    const requiresTarget = columns?.requiresTarget ?? row?.requiresTarget;
    if (requiresTarget !== void 0 && requiresTarget !== null) {
      action.requiresTarget = requiresTarget;
    }
    const targetType = columns?.targetType ?? row?.targetType;
    if (targetType) action.targetType = targetType;
    const energyCost = firstNumber2(columns?.energyCost, positive2(row?.energyCost));
    if (energyCost !== void 0) action.energyCost = energyCost;
    if (columns?.presence !== void 0) action.presence = { ...columns.presence };
    if (columns?.noise !== void 0) action.noise = columns.noise;
    if (columns?.stance !== void 0) action.stance = columns.stance;
    if (columns?.conceals !== void 0) action.conceals = columns.conceals;
    if (columns?.awarenessDelta !== void 0) action.awarenessDelta = columns.awarenessDelta;
    if (columns?.distraction !== void 0) action.distraction = columns.distraction;
    if (columns?.incapacitates !== void 0) action.incapacitates = columns.incapacitates;
    return action;
  }
  var StealthActionTable = class {
    constructor(actions = []) {
      __publicField(this, "rows", /* @__PURE__ */ new Map());
      for (const action of actions) this.define(action);
    }
    /** Add or replace one row. Returns it as stored. */
    define(action) {
      const stored = { ...action };
      this.rows.set(stored.id, stored);
      return stored;
    }
    /** Add or replace one row from authored columns plus, optionally, its shared row. */
    defineAuthored(columns, row) {
      return this.define(stealthActionFrom(row, columns));
    }
    get(actionId) {
      const row = this.rows.get(actionId);
      return row === void 0 ? void 0 : { ...row };
    }
    has(actionId) {
      return this.rows.has(actionId);
    }
    /** Every action id, in the order the rows were defined. */
    ids() {
      return [...this.rows.keys()];
    }
    /** Every row, in the order they were defined. */
    all() {
      return [...this.rows.values()].map((row) => ({ ...row }));
    }
    get size() {
      return this.rows.size;
    }
    /**
     * Load a world's rows: every action the creator gave stealth columns to, plus
     * every action-block row already in the `stealth` category.
     *
     * Returns how many rows were loaded. A world that authored neither gets none —
     * {@link DEFAULT_STEALTH_ACTIONS} is the caller's fallback to reach for, and it
     * is deliberately not applied here, because a world that deleted `take_down`
     * must not have it handed back.
     */
    loadFromIR(actions = [], columnRows = []) {
      const columnsById = /* @__PURE__ */ new Map();
      for (const columns of columnRows) columnsById.set(columns.id, columns);
      let loaded = 0;
      const rowsById = /* @__PURE__ */ new Map();
      for (const row of actions) {
        rowsById.set(row.id, row);
        if (!columnsById.has(row.id) && !isStealthRow(row)) continue;
        this.define(stealthActionFrom(row, columnsById.get(row.id)));
        loaded += 1;
      }
      for (const [id, columns] of columnsById) {
        if (rowsById.has(id)) continue;
        this.define(stealthActionFrom(void 0, columns));
        loaded += 1;
      }
      return loaded;
    }
  };
  function stealthActEffects(action) {
    const actor = {};
    if (action.noise !== void 0) actor.noise = clampLevel2(action.noise);
    if (action.stance !== void 0) actor.stance = action.stance;
    if (action.conceals !== void 0) actor.concealed = action.conceals;
    const effects = {
      actor,
      awarenessDelta: action.awarenessDelta ?? 0,
      incapacitates: action.incapacitates === true
    };
    if (action.distraction !== void 0) effects.distraction = clampLevel2(action.distraction);
    return effects;
  }
  function stealthActFor(action, context) {
    if (!action.presence) return void 0;
    return {
      event: context.event,
      actor: context.actor,
      action: action.id,
      object: context.object,
      channel: action.presence.channel,
      strength: clampLevel2(action.presence.strength),
      coarseActor: context.coarseActor,
      coarseObject: context.coarseObject
    };
  }
  function stealthActionFacts(action) {
    const facts = [
      {
        predicate: "action",
        args: [action.id, action.name ?? action.id, STEALTH_ACTION_CATEGORY, action.energyCost ?? 0]
      },
      { predicate: "action_category", args: [action.id, STEALTH_ACTION_CATEGORY] }
    ];
    if (action.requiresTarget) facts.push({ predicate: "action_requires_target", args: [action.id] });
    if (action.targetType) {
      facts.push({ predicate: "action_target_type", args: [action.id, action.targetType] });
    }
    return facts;
  }
  function isStealthRow(row) {
    return row.category === STEALTH_ACTION_CATEGORY || row.actionType === STEALTH_ACTION_CATEGORY;
  }
  function positive2(value) {
    return typeof value === "number" && Number.isFinite(value) && value > 0 ? value : void 0;
  }
  function firstNumber2(...values) {
    for (const value of values) {
      if (typeof value === "number" && Number.isFinite(value)) return value;
    }
    return void 0;
  }
  function clampLevel2(level) {
    if (!Number.isFinite(level) || level < 0) return 0;
    return level > 100 ? 100 : level;
  }

  // @insimul/core/src/game-engine/logic/DetectionTracker.ts
  var DetectionTracker = class {
    constructor(config) {
      __publicField(this, "engine");
      __publicField(this, "seed");
      __publicField(this, "tuning");
      __publicField(this, "playthrough");
      __publicField(this, "namespace");
      __publicField(this, "probe");
      __publicField(this, "eventBus");
      __publicField(this, "observers", /* @__PURE__ */ new Map());
      __publicField(this, "targets", /* @__PURE__ */ new Map());
      /** Keyed by the pair's logical identity — see `pairKey` at the foot of this file. */
      __publicField(this, "memory", /* @__PURE__ */ new Map());
      /** CURIE → the id the host registered, so a report speaks the host's language. */
      __publicField(this, "hostIds", /* @__PURE__ */ new Map());
      /** The last tick {@link DetectionTracker.observe} ran, which is what makes a belief stale. */
      __publicField(this, "lastTick");
      /** The world's stealth rows. Authored data — never written to by gameplay. */
      __publicField(this, "actions");
      /**
       * Acts submitted since the last tick, waiting to be published into the pass.
       *
       * Queued rather than published on the spot because an act is perceived by the
       * tick it happened in: publishing one immediately would mean a perception pass
       * per act, and an observer's exposure would depend on the order the caller
       * submitted things in.
       */
      __publicField(this, "pendingActs", []);
      this.engine = config.engine;
      this.seed = config.seed;
      this.tuning = config.tuning ?? { ...DEFAULT_DETECTION_TUNING };
      this.actions = new StealthActionTable(config.actions ?? DEFAULT_STEALTH_ACTIONS);
      this.playthrough = config.playthrough;
      this.namespace = config.namespace;
      this.probe = config.probe ?? config.host?.perception;
      this.eventBus = config.eventBus;
      if (config.state) this.restore(config.state);
    }
    setEventBus(bus) {
      this.eventBus = bus;
    }
    /** Whether a host wired {@link IPerceptionProbe}. False means the caller supplies readings. */
    hasPerceptionProbe() {
      return this.probe !== void 0;
    }
    /** The world's authored numbers, as this instance read them. */
    getTuning() {
      return { ...this.tuning };
    }
    // ── Roster ─────────────────────────────────────────────────────────────
    /** Add or replace an observer. */
    registerObserver(observer) {
      this.observers.set(observer.id, { ...observer, senses: [...observer.senses] });
      this.hostIds.set(formatCurie(this.kinpOf(observer.id, observer.kinp)), observer.id);
    }
    /** Add or replace a target. */
    registerTarget(target) {
      this.targets.set(target.id, { ...target });
      this.hostIds.set(formatCurie(this.kinpOf(target.id, target.kinp)), target.id);
    }
    /**
     * Update what the host knows about a target between ticks — where they are,
     * how loud they are, whether they are crouched or concealed.
     *
     * Called when the world changes, not on a frame: a host that has a new position
     * every frame reports the LOCATION it resolves to, and only when it changes.
     */
    setTargetState(id, patch) {
      const target = this.targets.get(id);
      if (!target) return;
      Object.assign(target, patch);
    }
    /** How distracted an observer is right now, 0–100. */
    setDistraction(id, distraction) {
      const observer = this.observers.get(id);
      if (!observer) return;
      observer.distraction = distraction;
    }
    unregisterObserver(id) {
      this.observers.delete(id);
      this.forgetPairs((memory) => this.hostIdOf(memory.observer) === id);
    }
    unregisterTarget(id) {
      this.targets.delete(id);
      this.forgetPairs((memory) => this.hostIdOf(memory.target) === id);
    }
    // ── The decision ───────────────────────────────────────────────────────
    /**
     * Run one detection tick and apply what follows.
     *
     * Order: gather the host's readings, decide purely, then write. Nothing is
     * written before the whole pass exists, so a partial tick cannot leave half a
     * ladder behind.
     */
    async observe(request) {
      const readings = request.readings ?? await this.askProbe(request.tick);
      const sensed = readings.flatMap((reading2) => this.toSensorReading(reading2));
      this.lastTick = request.tick;
      const pending = this.pendingActs;
      this.pendingActs = [];
      const result = runDetection({
        seed: this.seed,
        tick: request.tick,
        playthrough: this.playthrough,
        observers: [...this.observers.values()].map((o) => this.toObserver(o)),
        targets: [...this.targets.values()].map((t) => this.toTarget(t)),
        readings: sensed,
        acts: pending.map((entry) => entry.act),
        memory: [...this.memory.values()],
        tuning: this.tuning
      });
      this.memory = /* @__PURE__ */ new Map();
      for (const memory of result.memory) this.memory.set(pairKey(memory.observer, memory.target), memory);
      const facts = detectionPassFacts(result.updates);
      facts.assert.push(
        ...result.perception.beliefWorldFacts,
        ...result.perception.perceptFacts,
        ...result.perception.beliefFacts,
        ...result.perception.perceivedFacts
      );
      for (const entry of pending) facts.assert.push(entry.fact);
      const applied = await this.writeDelta(facts);
      const enforcement = await this.enforce(request.tick, pending.map((entry) => entry.act.event));
      const transitions = result.updates.filter((update) => update.changed);
      this.announce(transitions);
      return {
        updates: result.updates,
        transitions,
        facts,
        applied,
        perception: result.perception,
        acts: pending.map((entry) => entry.act),
        enforcement
      };
    }
    /**
     * Judge this tick's acts, and make the consequences real.
     *
     * Strictly after the write: `violation/5` reads `act/4` and `witness/2` reads
     * the pass's own `perceived/4` and `percept_actor/2`, so enforcement can only
     * answer once both are in the KB. What comes back is asserted rather than
     * returned to the caller to assert, because this module has already committed
     * the tick — and a `reputation_change/3` the caller forgot to apply would be a
     * crime that was witnessed and cost nothing.
     */
    async enforce(tick, events) {
      if (!this.engine || events.length === 0) return null;
      const result = await enforceActs(this.engine, {
        tick,
        events,
        playthrough: this.playthrough
      });
      for (const fact of result.consequenceFacts) {
        await this.engine.assertFact(stripPeriod(fact));
      }
      return result;
    }
    // ── Stealth acts ───────────────────────────────────────────────────────
    /**
     * The world's stealth rows, as this instance read them.
     */
    getActions() {
      return this.actions.all();
    }
    /**
     * May this actor take this action against this target?
     *
     * `ai/rule-enforcement.ts`'s `checkAction`, forwarded with the actor spelled the
     * way this module spells them. There is deliberately no stealth-private gate:
     * hiding in a temple is refused by whatever `forbids/4` refuses it with, which
     * is the same clause that refuses a theft. With no KB wired every action is
     * permitted — core does not invent a prohibition it cannot read.
     */
    async checkStealthAction(actorId, action, targetId) {
      const agent = this.curieOf(actorId);
      const target = targetId === void 0 ? NO_TARGET : this.curieOf(targetId);
      if (!this.engine) {
        return { agent, action, target, permitted: true, breached: [] };
      }
      return checkAction(this.engine, { agent, action, target });
    }
    /**
     * Perform one stealth act.
     *
     * Three things happen, in this order and for these reasons:
     *
     *  1. **The gate.** {@link checkStealthAction}, unless the caller opted out —
     *     see {@link StealthActRequest.gated}.
     *  2. **The row's effects.** What the actor now sounds like, what stance they
     *     are in, whether they are concealed, what it cost every watcher in
     *     awareness, what it did to the observer it was aimed at. All of it is said
     *     in facts that already existed.
     *  3. **The queue.** The act joins the next {@link DetectionTracker.observe},
     *     where it is published as a percept in the SAME pass everything else is
     *     perceived in — and, once that pass has written, judged.
     *
     * An act nobody could sense is still an act: it goes into the KB as `act/4`,
     * it is still a violation if a norm forbade it, and it produces no consequence
     * at all. That is the mechanic, not a degradation.
     */
    async act(request) {
      const check = await this.checkStealthAction(request.actor, request.action, request.target);
      const row = this.actions.get(request.action);
      if (!check.permitted && request.gated !== false) {
        return {
          event: request.event,
          actor: check.agent,
          action: request.action,
          target: check.target,
          check,
          performed: false
        };
      }
      const effects = row ? stealthActEffects(row) : void 0;
      if (effects) this.applyEffects(request, effects);
      const actor = this.kinpOf(
        request.actor,
        this.targets.get(request.actor)?.kinp ?? this.observers.get(request.actor)?.kinp
      );
      this.hostIds.set(formatCurie(actor), request.actor);
      const presence = request.presence ?? row?.presence ?? { channel: "sight", strength: 0 };
      const act = stealthActFor(
        { id: request.action, presence },
        {
          event: request.event,
          actor,
          object: this.objectOf(request),
          coarseActor: request.coarseActor === void 0 ? void 0 : this.kinpOf(request.coarseActor),
          coarseObject: this.coarseObjectOf(request)
        }
      );
      this.pendingActs.push({
        act,
        fact: actFacts([
          {
            event: request.event,
            actor: check.agent,
            action: request.action,
            target: check.target === NO_TARGET ? void 0 : check.target
          }
        ])[0]
      });
      return {
        event: request.event,
        actor: check.agent,
        action: request.action,
        target: check.target,
        check,
        performed: true,
        effects
      };
    }
    /**
     * Publish the world's stealth rows into the shared action block.
     *
     * `action/4`, `action_category/2`, `action_requires_target/1` and
     * `action_target_type/2` — four facts, not one of them stealth's own, which is
     * what makes a sneak enumerate as a candidate and a take-down refusable by an
     * ordinary norm. Authored data, asserted at load beside `publishTuning`.
     * Returns how many facts were written.
     */
    async publishActions(engine = this.engine) {
      if (!engine) return 0;
      let written = 0;
      for (const action of this.actions.all()) {
        for (const fact of stealthActionFacts(action)) {
          await engine.assertFact(term3(fact));
          written += 1;
        }
      }
      return written;
    }
    /** What the row changed. Everything here is said in a fact that already existed. */
    applyEffects(request, effects) {
      if (Object.keys(effects.actor).length > 0) {
        this.setTargetState(request.actor, effects.actor);
      }
      if (effects.awarenessDelta !== 0) {
        this.adjustAwareness(request.actor, effects.awarenessDelta);
      }
      if (request.target !== void 0 && effects.distraction !== void 0) {
        const observer = this.observers.get(request.target);
        if (observer) {
          this.setDistraction(request.target, (observer.distraction ?? 0) + effects.distraction);
        }
      }
      if (request.target !== void 0 && effects.incapacitates) {
        this.unregisterObserver(request.target);
      }
    }
    /**
     * Move every observer's awareness of one actor.
     *
     * The rung is left where it is: a hide does not un-alert a guard mid-tick, it
     * moves the level, and the next pass reads it through the same hysteresis
     * everything else goes through.
     */
    adjustAwareness(actorId, delta) {
      const actorCurie = formatCurie(
        this.kinpOf(actorId, this.targets.get(actorId)?.kinp ?? this.observers.get(actorId)?.kinp)
      );
      for (const memory of this.memory.values()) {
        if (memory.target !== actorCurie) continue;
        const level = memory.awareness + delta;
        memory.awareness = level < 0 ? 0 : level > 100 ? 100 : Math.round(level);
      }
    }
    /** The percept's object: what the act was aimed at, or where the actor is. */
    objectOf(request) {
      if (request.target !== void 0) return this.kinpOf(request.target, this.targets.get(request.target)?.kinp ?? this.observers.get(request.target)?.kinp);
      const location = this.targets.get(request.actor)?.location;
      return this.kinpOf(location ?? request.actor);
    }
    /** The coarse object a PARTIAL perception learns — only ever a coarser PLACE. */
    coarseObjectOf(request) {
      if (request.target !== void 0) return void 0;
      const coarse = this.targets.get(request.actor)?.coarseLocation;
      return coarse === void 0 ? void 0 : this.kinpOf(coarse);
    }
    /**
     * A host id as the atom the rules layer spells it with.
     *
     * A registered entity is its CURIE — the spelling `act/4`, a witness list and
     * the blackboard all share. Anything else passes through verbatim, because a
     * target that is not an entity (`ledger`, `door_03`) is already an atom of the
     * world's own content and minting a KINP id for it would name something that
     * does not exist.
     */
    curieOf(id) {
      const registration = this.observers.get(id) ?? this.targets.get(id);
      if (!registration) return id;
      return formatCurie(this.kinpOf(id, registration.kinp));
    }
    /**
     * Ask the host what every observer's senses can reach of every target.
     *
     * One query per pair per DETECTION tick, on the decision path. A probe that
     * throws or answers `null` for a pair is saying "sensed nothing", which is
     * different from "sensed badly" and is the same rule `ai/perception.ts` applies
     * to a missing exposure.
     */
    async askProbe(tick) {
      if (!this.probe) return [];
      const readings = [];
      for (const observer of this.observers.values()) {
        for (const target of this.targets.values()) {
          if (observer.id === target.id) continue;
          let reading2 = null;
          try {
            reading2 = await this.probe.sense({ observer: observer.id, target: target.id, tick }) ?? null;
          } catch {
            reading2 = null;
          }
          if (reading2) readings.push({ ...reading2, observer: observer.id, target: target.id });
        }
      }
      return readings;
    }
    // ── What is known ──────────────────────────────────────────────────────
    /** The rung this observer is on for this target. `unaware` for a pair with no history. */
    stateOf(observerId, targetId) {
      return this.pair(observerId, targetId)?.state ?? "unaware";
    }
    /** How convinced this observer is, 0–100. */
    awarenessOf(observerId, targetId) {
      return this.pair(observerId, targetId)?.awareness ?? 0;
    }
    /**
     * Where this observer BELIEVES the target is, in the host's own ids — not
     * where the target is.
     *
     * `undefined` means they have never perceived them. A value means they
     * perceived them at `believedAt` and have believed it ever since, however long
     * ago that was and however wrong it has become — and `stale` says which of the
     * two it is: `false` only when the belief was refreshed on the most recent
     * tick this tracker ran.
     */
    beliefOf(observerId, targetId) {
      const memory = this.pair(observerId, targetId);
      if (!memory?.believedLocation) return void 0;
      return {
        location: this.hostIdOf(memory.believedLocation),
        tick: memory.believedAt,
        stale: memory.believedAt === void 0 || memory.believedAt !== this.lastTick
      };
    }
    /** Every observer that has noticed this target at all, in canonical order. */
    observersAwareOf(targetId) {
      const found = [];
      for (const memory of this.memory.values()) {
        if (this.hostIdOf(memory.target) !== targetId || memory.state === "unaware") continue;
        found.push(this.hostIdOf(memory.observer));
      }
      return found.sort();
    }
    /** Every pair this tracker remembers, in canonical order. */
    pairs() {
      return this.serialize().pairs;
    }
    pair(observerId, targetId) {
      const observer = this.observers.get(observerId);
      const target = this.targets.get(targetId);
      return this.memory.get(
        pairKey(
          formatCurie(this.kinpOf(observerId, observer?.kinp)),
          formatCurie(this.kinpOf(targetId, target?.kinp))
        )
      );
    }
    // ── The KB ─────────────────────────────────────────────────────────────
    /**
     * Publish the world's authored bands into the KB as `detection_threshold/2`.
     *
     * Authored data, asserted at load the way `StaminaPool.publishTuning` asserts
     * `stamina_threshold/2` — so a rule that asks whether a guard is past the
     * `searching` band reads the same number core decided with. Returns how many
     * facts were written.
     */
    async publishTuning(engine = this.engine) {
      if (!engine) return 0;
      let written = 0;
      for (const fact of detectionThresholdFacts(this.tuning)) {
        await engine.assertFact(stripPeriod(fact));
        written += 1;
      }
      return written;
    }
    /**
     * Write one delta into the KB, retracting first.
     *
     * Retracting a fact the KB never carried is a no-op rather than a failure: a
     * host with its own persistence, a restored save and a pair whose first tick
     * ran before the engine was wired all produce one, and none of them is an
     * error.
     */
    async writeDelta(delta) {
      if (!this.engine) return false;
      if (delta.retract.length === 0 && delta.assert.length === 0) return false;
      for (const fact of delta.retract) {
        try {
          await this.engine.retractFact(stripPeriod(fact));
        } catch {
        }
      }
      for (const fact of delta.assert) {
        await this.engine.assertFact(stripPeriod(fact));
      }
      return true;
    }
    /** Hand the transitions to the bus. Everything here is after the fact. */
    announce(transitions) {
      for (const update of transitions) {
        this.eventBus?.emit({
          type: "detection_changed",
          observerId: this.hostIdOf(update.observer),
          targetId: this.hostIdOf(update.target),
          state: update.state,
          previousState: update.stateBefore,
          awareness: update.awareness
        });
      }
    }
    // ── Save/restore ───────────────────────────────────────────────────────
    serialize() {
      const pairs = [...this.memory.values()].map((memory) => ({
        observer: this.hostIdOf(memory.observer),
        target: this.hostIdOf(memory.target),
        awareness: memory.awareness,
        state: memory.state,
        believedLocation: memory.believedLocation === void 0 ? void 0 : this.hostIdOf(memory.believedLocation),
        believedAt: memory.believedAt,
        lastPerceivedTick: memory.lastPerceivedTick
      }));
      pairs.sort((a, b) => a.observer < b.observer ? -1 : a.observer > b.observer ? 1 : a.target < b.target ? -1 : a.target > b.target ? 1 : 0);
      return { pairs };
    }
    /**
     * Write this playthrough's state into a save's extensions bag — US-2.
     *
     * `currentState.extensions.detectionStates`, the registered key and the only
     * home the state has (`perception/detection-save.ts`). Goes through
     * `writeDetectionState`, which drops anything that is not a pair, so authored
     * tuning cannot ride into a save even if a caller handed some in.
     */
    saveTo(extensions) {
      return writeDetectionState(extensions, this.serialize());
    }
    /**
     * Restore from a save's extensions bag. Silent, exactly as
     * {@link DetectionTracker.restore} is, and tolerant of a bag written before the
     * key existed.
     */
    loadFrom(extensions) {
      this.restore(readDetectionState(extensions));
    }
    /**
     * Restore a saved playthrough. Silent — no events, because loading a save is
     * not a guard noticing you, and a quest listener counting alarms must not fire
     * on load.
     */
    restore(state) {
      this.memory = /* @__PURE__ */ new Map();
      for (const pair of state.pairs ?? []) {
        const observer = formatCurie(this.kinpOf(pair.observer, this.observers.get(pair.observer)?.kinp));
        const target = formatCurie(this.kinpOf(pair.target, this.targets.get(pair.target)?.kinp));
        this.hostIds.set(observer, pair.observer);
        this.hostIds.set(target, pair.target);
        let believedLocation;
        if (pair.believedLocation !== void 0) {
          believedLocation = formatCurie(this.kinpOf(pair.believedLocation));
          this.hostIds.set(believedLocation, pair.believedLocation);
        }
        this.memory.set(pairKey(observer, target), {
          observer,
          target,
          awareness: pair.awareness,
          state: pair.state,
          believedLocation,
          believedAt: pair.believedAt,
          lastPerceivedTick: pair.lastPerceivedTick
        });
      }
    }
    // ── Identity ───────────────────────────────────────────────────────────
    /**
     * The KINP id behind a host id.
     *
     * A host that already names its entities with CURIEs gets its own identity
     * back; anything else is minted provisionally in the configured namespace. The
     * bridge exists because belief is stamped at a KINP belief world and the
     * mechanic vocabulary is spoken in `id/3` terms, while a host is entitled to
     * keep calling its guard `guard_02`.
     */
    kinpOf(id, explicit) {
      return explicit ?? detectionEntityId(id, this.namespace);
    }
    /** The host id behind a CURIE, falling back to the CURIE for an id never registered. */
    hostIdOf(curie) {
      return this.hostIds.get(curie) ?? curie;
    }
    toObserver(registration) {
      return {
        agent: this.kinpOf(registration.id, registration.kinp),
        senses: registration.senses,
        distraction: registration.distraction
      };
    }
    toTarget(registration) {
      const location = this.kinpOf(registration.location);
      this.hostIds.set(formatCurie(location), registration.location);
      const coarse = registration.coarseLocation === void 0 ? void 0 : this.kinpOf(registration.coarseLocation);
      if (coarse && registration.coarseLocation) {
        this.hostIds.set(formatCurie(coarse), registration.coarseLocation);
      }
      return {
        id: this.kinpOf(registration.id, registration.kinp),
        location,
        coarseLocation: coarse,
        light: registration.light,
        stance: registration.stance,
        noise: registration.noise,
        concealed: registration.concealed
      };
    }
    /**
     * One host reading as the pure pass takes it.
     *
     * A reading naming an id that is not registered is DROPPED rather than
     * guessed at: a host may hold an id for a tick after the entity left, and
     * inventing a KINP identity for it would put a ghost in the KB.
     */
    toSensorReading(reading2) {
      const observer = this.observers.get(reading2.observer);
      const target = this.targets.get(reading2.target);
      if (!observer || !target) return [];
      if (reading2.light !== void 0) target.light = reading2.light;
      if (reading2.stance !== void 0) target.stance = reading2.stance;
      if (reading2.noise !== void 0) target.noise = reading2.noise;
      return [
        {
          observer: this.kinpOf(observer.id, observer.kinp),
          target: this.kinpOf(target.id, target.kinp),
          visibility: reading2.visibility,
          cover: reading2.cover,
          audibility: reading2.audibility
        }
      ];
    }
    forgetPairs(matches) {
      for (const [key, memory] of [...this.memory.entries()]) {
        if (matches(memory)) this.memory.delete(key);
      }
    }
  };
  function pairKey(observerCurie, targetCurie) {
    return `${observerCurie.length}:${observerCurie}${targetCurie.length}:${targetCurie}`;
  }
  function stripPeriod(clause) {
    return clause.replace(/\.$/, "");
  }
  function term3(fact) {
    return stripPeriod(serializedFactToProlog(fact));
  }

  // @insimul/core/src/traversal/traversal.ts
  var TRAVERSAL_MODES = Object.freeze([
    "walk",
    "climb",
    "swim",
    "jump",
    "ride",
    "boat"
  ]);
  function traversalLinkId(link) {
    return link.id ?? `${link.from}>${link.to}:${link.mode}`;
  }
  function edgeRequirements(links, from, to) {
    const goals = /* @__PURE__ */ new Set();
    for (const link of links) {
      if (link.from !== from || link.to !== to) continue;
      for (const goal of link.requires ?? []) goals.add(goal);
    }
    return [...goals].sort(compareIds);
  }
  var DEFAULT_TRAVERSAL_TUNING = Object.freeze({
    defaultCost: 5,
    modeCost: Object.freeze({ walk: 1, climb: 3, swim: 2.5, jump: 2, ride: 0.2, boat: 0.2 }),
    modeAction: Object.freeze({
      walk: "walk",
      climb: "climb",
      swim: "swim",
      jump: "jump",
      ride: "ride",
      boat: "row"
    }),
    defaultAction: "traverse"
  });
  function traversalCost(link, tuning) {
    const base = link.cost ?? tuning.defaultCost;
    const multiplier = tuning.modeCost[link.mode] ?? 1;
    const cost = Math.floor(base * multiplier);
    return Number.isFinite(cost) && cost > 0 ? cost : 0;
  }
  function traversalAction(link, tuning) {
    return link.action ?? tuning.modeAction[link.mode] ?? tuning.defaultAction;
  }
  var TRAVERSAL_REFUSALS = Object.freeze([
    /** No authored link goes that way at all. Not a refusal so much as an absence. */
    "unreachable",
    /** `traversal_blocked(From, To)` — the landslide closed the pass. */
    "blocked",
    /** `movement_mode(Actor, Mode)` does not hold — you cannot swim. */
    "mode",
    /** The host's geometry said no: the gap is too wide from here, the door is barred. */
    "impassable",
    /** `can_afford_stamina/2` — nothing left in the meter. */
    "stamina",
    /** A `traversal_requires/3` goal the rules layer did not satisfy. */
    "requires",
    /** `permissible/3` refused it — a norm, a law, a locked region, 123's skill gates. */
    "forbidden"
  ]);
  function resolveAffordances(input) {
    const tuning = input.tuning ?? DEFAULT_TRAVERSAL_TUNING;
    const modes = new Set(input.modes);
    const blocked = new Set((input.blocked ?? []).map((edge) => edgeKey(edge.from, edge.to)));
    const affordances = input.links.filter((link) => link.from === input.from).map((link) => {
      const id = traversalLinkId(link);
      const cost = traversalCost(link, tuning);
      const requires = edgeRequirements(input.links, link.from, link.to);
      const refusal2 = refuse(link, id, cost, { modes, blocked, input });
      return {
        id,
        from: link.from,
        to: link.to,
        mode: link.mode,
        action: traversalAction(link, tuning),
        cost,
        available: refusal2 === void 0,
        refusal: refusal2,
        requires,
        conditional: requires.length > 0
      };
    });
    affordances.sort(
      (a, b) => compareIds(a.to, b.to) || compareIds(a.mode, b.mode) || compareIds(a.id, b.id)
    );
    return affordances;
  }
  function refuse(link, id, cost, ctx) {
    if (ctx.blocked.has(edgeKey(link.from, link.to))) return "blocked";
    if (!ctx.modes.has(link.mode)) return "mode";
    if (link.geometric && ctx.input.geometry?.[id] === false) return "impassable";
    const stamina = ctx.input.stamina;
    if (stamina !== void 0 && stamina.current < cost) return "stamina";
    return void 0;
  }
  function bestAffordance(affordances, to) {
    let best;
    for (const affordance of affordances) {
      if (affordance.to !== to || !affordance.available) continue;
      if (best === void 0 || affordance.cost < best.cost) best = affordance;
    }
    return best;
  }
  var DEFAULT_MAX_ROUTE_STEPS = 32;
  function findRoute(input) {
    const maxSteps = input.maxSteps ?? DEFAULT_MAX_ROUTE_STEPS;
    if (input.to === input.from) {
      return { from: input.from, to: input.to, steps: [], cost: 0, conditional: false };
    }
    const settled = /* @__PURE__ */ new Set();
    let frontier = [
      { at: input.from, steps: [], cost: 0 }
    ];
    while (frontier.length > 0) {
      frontier.sort(
        (a, b) => a.cost - b.cost || a.steps.length - b.steps.length || compareIds(a.at, b.at) || compareIds(lastStepId(a.steps), lastStepId(b.steps))
      );
      const here = frontier.shift();
      if (here.at === input.to) {
        return {
          from: input.from,
          to: input.to,
          steps: here.steps,
          cost: here.cost,
          conditional: here.steps.some((step) => step.requires.length > 0)
        };
      }
      if (settled.has(here.at) || here.steps.length >= maxSteps) continue;
      settled.add(here.at);
      const next = resolveAffordances({ ...input, from: here.at });
      frontier = frontier.concat(
        next.filter((affordance) => affordance.available && !settled.has(affordance.to)).map((affordance) => ({
          at: affordance.to,
          cost: here.cost + affordance.cost,
          steps: [
            ...here.steps,
            {
              id: affordance.id,
              from: affordance.from,
              to: affordance.to,
              mode: affordance.mode,
              cost: affordance.cost,
              requires: affordance.requires
            }
          ]
        }))
      );
    }
    return void 0;
  }
  function lastStepId(steps) {
    return steps.length === 0 ? "" : steps[steps.length - 1].id;
  }
  function edgeKey(from, to) {
    return `${from.length}:${from}${to.length}:${to}`;
  }

  // @insimul/core/src/traversal/traversal-facts.ts
  function emptyTraversalDelta() {
    return { retract: [], assert: [] };
  }
  var TRAVERSAL_RESOLUTION_PREDICATES = Object.freeze([
    "movement_mode/2",
    "traversal_blocked/2",
    "at_location/2"
  ]);
  var TRAVERSAL_AUTHORED_PREDICATES = Object.freeze([
    "traversal_link/3",
    "traversal_cost/3",
    "traversal_requires/3"
  ]);
  function traversalLinkFact(link) {
    return `traversal_link(${prologAtom(link.from)}, ${prologAtom(link.to)}, ${prologAtom(link.mode)}).`;
  }
  function traversalGraphFacts(links, tuning) {
    const facts = links.map((link) => traversalLinkFact(link));
    const cheapest = /* @__PURE__ */ new Map();
    const goals = /* @__PURE__ */ new Map();
    for (const link of links) {
      const key = `${link.from.length}:${link.from}${link.to.length}:${link.to}`;
      const cost = traversalCost(link, tuning);
      const seen = cheapest.get(key);
      if (seen === void 0 || cost < seen.cost) {
        cheapest.set(key, { from: link.from, to: link.to, cost });
      }
      if ((link.requires ?? []).length === 0) continue;
      const edge = goals.get(key) ?? { from: link.from, to: link.to, goals: [] };
      for (const goal of link.requires ?? []) if (!edge.goals.includes(goal)) edge.goals.push(goal);
      goals.set(key, edge);
    }
    for (const edge of cheapest.values()) {
      facts.push(`traversal_cost(${prologAtom(edge.from)}, ${prologAtom(edge.to)}, ${edge.cost}).`);
    }
    for (const edge of goals.values()) {
      for (const goal of edge.goals) {
        facts.push(`traversal_requires(${prologAtom(edge.from)}, ${prologAtom(edge.to)}, ${goal}).`);
      }
    }
    return facts;
  }
  function movementModeFact(actor, mode) {
    return `movement_mode(${prologAtom(actor)}, ${prologAtom(mode)}).`;
  }
  function traversalBlockedFact(from, to) {
    return `traversal_blocked(${prologAtom(from)}, ${prologAtom(to)}).`;
  }
  function atLocationFact(actor, location) {
    return `at_location(${prologAtom(actor)}, ${prologAtom(location)}).`;
  }
  function movementModeDelta(actor, before, after) {
    const had = new Set(before);
    const has2 = new Set(after);
    return {
      retract: before.filter((mode) => !has2.has(mode)).map((mode) => movementModeFact(actor, mode)),
      assert: after.filter((mode) => !had.has(mode)).map((mode) => movementModeFact(actor, mode))
    };
  }
  function arrivalDelta(actor, before, after) {
    if (before === after) return emptyTraversalDelta();
    return {
      retract: before === void 0 ? [] : [atLocationFact(actor, before)],
      assert: [atLocationFact(actor, after)]
    };
  }
  function mergeTraversalDeltas(...deltas) {
    const merged = emptyTraversalDelta();
    for (const delta of deltas) {
      merged.retract.push(...delta.retract);
      merged.assert.push(...delta.assert);
    }
    return merged;
  }

  // @insimul/core/src/game-engine/logic/TraversalPlanner.ts
  var TraversalPlanner = class {
    constructor(config = {}) {
      __publicField(this, "engine");
      __publicField(this, "tuning");
      __publicField(this, "stamina");
      __publicField(this, "probe");
      __publicField(this, "locomotion");
      __publicField(this, "vehicles");
      __publicField(this, "eventBus");
      /** The world's authored graph. Authored data — never written to by gameplay. */
      __publicField(this, "links", []);
      __publicField(this, "actors", /* @__PURE__ */ new Map());
      /** `traversal_blocked/2`, keyed by the directed edge. */
      __publicField(this, "blocked", /* @__PURE__ */ new Map());
      this.engine = config.engine;
      this.tuning = config.tuning ?? { ...DEFAULT_TRAVERSAL_TUNING };
      this.stamina = config.stamina;
      this.probe = config.probe ?? config.host?.traversal;
      this.locomotion = config.locomotion ?? config.host?.locomotion;
      this.vehicles = config.vehicles;
      this.eventBus = config.eventBus;
      if (config.links) this.loadLinks(config.links);
      if (config.state) this.restore(config.state);
    }
    setEventBus(bus) {
      this.eventBus = bus;
    }
    /** Wire the vehicle module in after construction — see {@link DrivenVehicleSource}. */
    setVehicleSource(vehicles) {
      this.vehicles = vehicles;
    }
    /** Whether a host wired {@link ITraversalProbe}. False means geometric links are passable. */
    hasTraversalProbe() {
      return this.probe !== void 0;
    }
    /** Whether a host wired {@link ILocomotionHost}. False means every order arrives. */
    hasLocomotionHost() {
      return this.locomotion !== void 0;
    }
    /** The world's authored numbers, as this instance read them. */
    getTuning() {
      return { ...this.tuning };
    }
    // ── The graph ──────────────────────────────────────────────────────────
    /** Replace the authored graph. Ids are settled here so nothing downstream re-derives them. */
    loadLinks(links) {
      this.links = links.map((link) => ({ ...link, id: traversalLinkId(link) }));
    }
    /** The authored graph, as this instance read it. */
    getLinks() {
      return this.links.map((link) => ({ ...link }));
    }
    /**
     * Publish the world's authored graph into the KB as `traversal_link/3`,
     * `traversal_cost/3` and `traversal_requires/3`.
     *
     * Authored data, asserted at load the way `StaminaPool.publishTuning` asserts
     * `stamina_threshold/2` — so a rule that asks `can_traverse/3` walks the same
     * graph core resolves over. Returns how many facts were written.
     */
    async publishGraph(engine = this.engine) {
      if (!engine) return 0;
      let written = 0;
      for (const fact of traversalGraphFacts(this.links, this.tuning)) {
        await engine.assertFact(stripPeriod2(fact));
        written += 1;
      }
      return written;
    }
    // ── Roster ─────────────────────────────────────────────────────────────
    /**
     * Add or replace an actor, and write their `movement_mode/2` facts.
     *
     * `location` is where they are. It is a location ATOM: a host that has a
     * transform resolves it to the place that transform is in and hands over the
     * name, which is the entire contract between this module and locomotion.
     */
    async register(registration) {
      const before = this.actors.get(registration.id);
      const modes = [...registration.modes ?? ["walk"]];
      this.actors.set(registration.id, {
        id: registration.id,
        location: registration.location,
        modes
      });
      const delta = mergeTraversalDeltas(
        movementModeDelta(registration.id, before?.modes ?? [], modes),
        arrivalDelta(registration.id, before?.location, registration.location)
      );
      await this.writeDelta(delta);
      return delta;
    }
    /** Forget an actor. Their facts are retracted; the graph is untouched. */
    async unregister(actorId) {
      const actor = this.actors.get(actorId);
      if (!actor) return emptyTraversalDelta();
      this.actors.delete(actorId);
      const delta = movementModeDelta(actorId, actor.modes, []);
      delta.retract.push(atLocationFact(actorId, actor.location));
      await this.writeDelta(delta);
      return delta;
    }
    /** Where this actor is, or `undefined` for one that was never registered. */
    locationOf(actorId) {
      return this.actors.get(actorId)?.location;
    }
    /** Every mode this actor is currently using. */
    modesOf(actorId) {
      return [...this.actors.get(actorId)?.modes ?? []];
    }
    /**
     * Replace what modes an actor is using — they mounted, they got into the water,
     * they put the boat back.
     *
     * Replaced rather than added to, because `movement_mode/2` says what an actor is
     * DOING and a character who is both walking and swimming is two facts that
     * cannot both be true.
     */
    async setModes(actorId, modes) {
      const actor = this.actors.get(actorId);
      if (!actor) return emptyTraversalDelta();
      const delta = movementModeDelta(actorId, actor.modes, modes);
      actor.modes = [...modes];
      await this.writeDelta(delta);
      return delta;
    }
    /**
     * Record that an actor is somewhere — the ONE thing a host tells core about
     * where anybody is.
     *
     * Called when it becomes true, not on a frame. A host running a path follower at
     * 60fps calls this once, on arrival, and a host that teleports a character for a
     * cutscene calls it once too; core cannot tell the two apart and must not be
     * able to.
     */
    async arrive(actorId, location) {
      const actor = this.actors.get(actorId);
      if (!actor) return emptyTraversalDelta();
      const delta = arrivalDelta(actorId, actor.location, location);
      actor.location = location;
      await this.writeDelta(delta);
      return delta;
    }
    // ── Closures ───────────────────────────────────────────────────────────
    /**
     * Close a link — "the landslide closed the pass", as `traversal_blocked/2`.
     *
     * DIRECTED, exactly as the link is: closing `pass → valley` leaves
     * `valley → pass` open, and a world that means both closes both.
     */
    async block(from, to) {
      const key = edgeKey(from, to);
      if (this.blocked.has(key)) return emptyTraversalDelta();
      this.blocked.set(key, { from, to });
      const delta = { retract: [], assert: [traversalBlockedFact(from, to)] };
      await this.writeDelta(delta);
      return delta;
    }
    /** Reopen a link. Reopening one that was never closed writes nothing. */
    async unblock(from, to) {
      const key = edgeKey(from, to);
      if (!this.blocked.has(key)) return emptyTraversalDelta();
      this.blocked.delete(key);
      const delta = { retract: [traversalBlockedFact(from, to)], assert: [] };
      await this.writeDelta(delta);
      return delta;
    }
    /** Whether this directed edge is closed. */
    isBlocked(from, to) {
      return this.blocked.has(edgeKey(from, to));
    }
    // ── The decision ───────────────────────────────────────────────────────
    /**
     * Every way out of where this actor is, and whether each is open to them.
     *
     * The host is asked about the links a world marked `geometric` and about nothing
     * else, once per call, on the decision path. Refused ways are kept rather than
     * filtered: a UI wants to grey out the ford and say why.
     *
     * The two rules-layer gates are NOT applied here — an affordance's
     * `conditional` flag says a requirement is outstanding, and `permissible/3` is
     * asked when a movement is actually attempted. Asking the KB once per link per
     * call would be a round trip per candidate on a path an interface polls.
     */
    async affordances(actorId) {
      const actor = this.actors.get(actorId);
      if (!actor) return [];
      return resolveAffordances({
        actor: actorId,
        from: actor.location,
        links: this.links,
        modes: actor.modes,
        blocked: [...this.blocked.values()],
        geometry: await this.askProbe(actor),
        stamina: this.meterOf(actorId),
        tuning: this.tuning
      });
    }
    /**
     * `reachable/3`: the cheapest route from where this actor is to `to`, over links
     * they can currently use, or `undefined`.
     *
     * Pure and synchronous — it walks the authored graph and consults neither the
     * host nor the KB, so a caller can plan over it freely. Whether each leg is
     * permitted is settled leg by leg, as each is taken.
     */
    route(actorId, to) {
      const actor = this.actors.get(actorId);
      if (!actor) return void 0;
      return findRoute({
        actor: actorId,
        from: actor.location,
        to,
        links: this.links,
        modes: actor.modes,
        blocked: [...this.blocked.values()],
        tuning: this.tuning
      });
    }
    /**
     * Decide whether this actor may move to an ADJACENT location, without moving
     * them or spending anything.
     *
     * Every gate, in {@link TRAVERSAL_REFUSALS} order: what core knows first, then
     * the requirement, then permissibility. This is what an NPC's utility layer asks
     * before it commits and what a UI asks before it offers.
     */
    async canTraverse(actorId, to) {
      const actor = this.actors.get(actorId);
      if (!actor) {
        return { actor: actorId, from: "", to, permitted: false, refusal: "unreachable", cost: 0, unmet: [] };
      }
      const affordances = await this.affordances(actorId);
      const chosen = bestAffordance(affordances, to);
      if (!chosen) {
        const nearest = affordances.filter((a) => a.to === to).sort((a, b) => refusalRank(b.refusal) - refusalRank(a.refusal) || a.cost - b.cost)[0];
        return {
          actor: actorId,
          from: actor.location,
          to,
          permitted: false,
          refusal: nearest?.refusal ?? "unreachable",
          affordance: nearest,
          cost: nearest?.cost ?? 0,
          unmet: []
        };
      }
      const base = {
        actor: actorId,
        from: actor.location,
        to,
        affordance: chosen,
        cost: chosen.cost
      };
      const unmet = await this.unmetRequirements(actorId, chosen);
      if (unmet.length > 0) {
        return { ...base, permitted: false, refusal: "requires", unmet };
      }
      const check = await this.checkPermission(actorId, chosen);
      if (!check.permitted) {
        return { ...base, permitted: false, refusal: "forbidden", check, unmet };
      }
      return { ...base, permitted: true, check, unmet };
    }
    /**
     * Move this actor to an ADJACENT location, if every gate allows it.
     *
     * The order is the whole of the module's discipline, and each step is where it
     * is for a reason:
     *
     *  1. **Decide** ({@link canTraverse}). Nothing has happened yet.
     *  2. **Charge** the shared meter, with the link's authored cost. A spend that
     *     cannot be afforded moves nothing and refuses the movement.
     *  3. **Order** the host to carry it out ({@link ILocomotionHost}). Core has
     *     already committed; this is not a request for permission.
     *  4. **Record** where the actor ended up, from the atom the host reported.
     *
     * A host that reports `arrived: false` leaves the actor where they were (or
     * wherever it says they ended up) and **the spend stands**: the climb was
     * attempted and the effort was expended, which is the answer a simulation gives
     * and a teleport does not.
     *
     * `intent` is US-2 of `125-npc-routines-and-locomotion` — how pressing the
     * movement is and how the body is carried. It is forwarded onto the order and
     * read by nothing here; see {@link TraversalIntent}.
     */
    async traverse(actorId, to, intent) {
      const decision = await this.canTraverse(actorId, to);
      const location = this.actors.get(actorId)?.location ?? decision.from;
      if (!decision.permitted || !decision.affordance) {
        return { ...decision, performed: false, location, facts: emptyTraversalDelta(), applied: false };
      }
      const affordance = decision.affordance;
      const spend = await this.stamina?.spend(actorId, {
        action: affordance.action,
        cost: affordance.cost
      });
      if (spend && !spend.spend.affordable) {
        return {
          ...decision,
          permitted: false,
          refusal: "stamina",
          performed: false,
          spend,
          location,
          facts: emptyTraversalDelta(),
          applied: false
        };
      }
      const arrival = await this.orderLocomotion(actorId, affordance, intent);
      const landed = arrival.arrived ? to : arrival.location ?? location;
      const facts = arrivalDelta(actorId, location, landed);
      const actor = this.actors.get(actorId);
      if (actor) actor.location = landed;
      const applied = await this.writeDelta(facts);
      this.eventBus?.emit({
        type: "traversal_completed",
        actorId,
        from: decision.from,
        to,
        mode: affordance.mode,
        cost: affordance.cost,
        arrived: arrival.arrived,
        location: landed
      });
      return { ...decision, performed: true, spend, arrival, location: landed, facts, applied };
    }
    // ── The gates ──────────────────────────────────────────────────────────
    /**
     * The authored goals this link asks of this actor that the KB did not satisfy.
     *
     * Evaluated by the PACK's own `traversal_goal_met/2`, not by a second
     * implementation here: the pack rebuilds the goal with the actor bound (`=..`),
     * and reproducing that rebuild in TypeScript is how `has_item(Actor, rope, 1)`
     * ends up satisfied by anyone at all holding a rope
     * (`prolog/mechanics/traversal-predicates.ts`'s correction to §7).
     *
     * With no KB wired every goal is unmet — see the module header for why this gate
     * fails closed and permissibility fails open.
     */
    async unmetRequirements(actorId, affordance) {
      if (affordance.requires.length === 0) return [];
      if (!this.engine) return [...affordance.requires];
      const unmet = [];
      for (const goal of affordance.requires) {
        let met = false;
        try {
          met = await this.engine.queryOnce(`traversal_goal_met(${prologAtom(actorId)}, ${goal})`);
        } catch {
          met = false;
        }
        if (!met) unmet.push(goal);
      }
      return unmet;
    }
    /**
     * `permissible/3`'s own input, forwarded with the movement spelled as the action
     * it is.
     *
     * There is deliberately no traversal-private gate: climbing the temple wall is
     * refused by whatever `forbids/4` refuses it with, which is the same clause that
     * refuses a theft — and it is what lets 123's skill gates and a world's laws
     * refuse a movement without traversal knowing they exist. With no KB wired every
     * movement is permitted; core does not invent a prohibition it cannot read.
     */
    async checkPermission(actorId, affordance) {
      const target = affordance.to || NO_TARGET;
      if (!this.engine) {
        return { agent: actorId, action: affordance.action, target, permitted: true, breached: [] };
      }
      return checkAction(this.engine, { agent: actorId, action: affordance.action, target });
    }
    /**
     * Ask the host about every geometric link out of where this actor is.
     *
     * One query per geometric link per call, on the decision path. A probe that
     * throws is read as "passable" — a host's geometry failing must not strand a
     * character, which is the same direction `ITrajectoryProbe` degrades in.
     */
    async askProbe(actor) {
      const geometry = {};
      if (!this.probe) return geometry;
      for (const link of this.links) {
        if (!link.geometric || link.from !== actor.location) continue;
        const id = traversalLinkId(link);
        let reading2 = null;
        try {
          reading2 = await this.probe.query({
            actor: actor.id,
            from: link.from,
            to: link.to,
            mode: link.mode,
            link: id
          });
        } catch {
          reading2 = null;
        }
        geometry[id] = reading2 === null ? true : reading2.passable;
      }
      return geometry;
    }
    /**
     * Hand one order to the host, or take the documented fallback.
     *
     * With no locomotion host wired every order arrives: the world state moves and
     * nothing is animated, which is exactly what a headless simulation wants. A host
     * that throws is read the same way — core has already spent the meter and
     * committed the decision, and leaving the actor in limbo because an animation
     * driver raised is the worse failure.
     */
    async orderLocomotion(actorId, affordance, intent) {
      if (!this.locomotion) return { arrived: true };
      try {
        const vehicle = this.vehicles?.drivenBy(actorId);
        return await this.locomotion.travel({
          actor: actorId,
          from: affordance.from,
          to: affordance.to,
          mode: affordance.mode,
          link: affordance.id,
          cost: affordance.cost,
          action: affordance.action,
          // Every order carries a complete intent, so a host never has to guess at
          // half of one — and four engines never guess differently.
          urgency: intent?.urgency ?? "ordinary",
          stance: intent?.stance ?? "standing",
          ...vehicle === void 0 ? {} : { vehicle }
        });
      } catch {
        return { arrived: true };
      }
    }
    /** This actor's meter, for the pure resolver. `undefined` for an actor with none. */
    meterOf(actorId) {
      const actor = this.stamina?.get(actorId);
      return actor === void 0 ? void 0 : { current: actor.current, max: actor.max };
    }
    // ── The KB ─────────────────────────────────────────────────────────────
    /**
     * Write one delta into the KB, retracting first.
     *
     * Retracting a fact the KB never carried is a no-op rather than a failure: a
     * host with its own persistence, a restored save and an actor registered before
     * the engine was wired all produce one, and none of them is an error.
     */
    async writeDelta(delta) {
      if (!this.engine) return false;
      if (delta.retract.length === 0 && delta.assert.length === 0) return false;
      for (const fact of delta.retract) {
        try {
          await this.engine.retractFact(stripPeriod2(fact));
        } catch {
        }
      }
      for (const fact of delta.assert) {
        await this.engine.assertFact(stripPeriod2(fact));
      }
      return true;
    }
    /**
     * Publish every registered actor's `movement_mode/2` and `at_location/2`.
     *
     * For a caller that wired the KB after the roster — a save restore, a host that
     * builds its world before its engine. Returns how many facts were written.
     */
    async publishActors(engine = this.engine) {
      if (!engine) return 0;
      let written = 0;
      for (const actor of this.roster()) {
        const delta = mergeTraversalDeltas(
          movementModeDelta(actor.id, [], actor.modes),
          arrivalDelta(actor.id, void 0, actor.location)
        );
        for (const fact of delta.assert) {
          await engine.assertFact(stripPeriod2(fact));
          written += 1;
        }
      }
      return written;
    }
    // ── Save/restore ───────────────────────────────────────────────────────
    /** Every actor this planner knows, in canonical order. */
    roster() {
      return [...this.actors.values()].map((actor) => ({ ...actor, modes: [...actor.modes] })).sort((a, b) => a.id < b.id ? -1 : a.id > b.id ? 1 : 0);
    }
    /**
     * The per-playthrough state, and only that: where everyone is, what they are
     * doing, and which links this playthrough closed. The graph, the costs and the
     * requirements are authored and are NOT here — a tuning number inside a save
     * file is world-template data leaking into a playthrough
     * (`docs/mechanic-predicates.md` §3).
     */
    serialize() {
      return {
        actors: this.roster(),
        blocked: [...this.blocked.values()].sort(
          (a, b) => a.from < b.from ? -1 : a.from > b.from ? 1 : a.to < b.to ? -1 : a.to > b.to ? 1 : 0
        )
      };
    }
    /**
     * Restore a saved playthrough. Silent — no events, because loading a save is not
     * somebody walking somewhere, and no KB writes, because restoring a save is what
     * `publishActors` is for once the engine exists.
     */
    restore(state) {
      this.actors = /* @__PURE__ */ new Map();
      for (const actor of state.actors ?? []) {
        this.actors.set(actor.id, {
          id: actor.id,
          location: actor.location,
          modes: [...actor.modes ?? ["walk"]]
        });
      }
      this.blocked = /* @__PURE__ */ new Map();
      for (const edge of state.blocked ?? []) {
        this.blocked.set(edgeKey(edge.from, edge.to), { from: edge.from, to: edge.to });
      }
    }
  };
  function stripPeriod2(clause) {
    return clause.replace(/\.$/, "");
  }
  function refusalRank(refusal2) {
    return refusal2 === void 0 ? TRAVERSAL_REFUSALS.length : TRAVERSAL_REFUSALS.indexOf(refusal2);
  }

  // @insimul/core/src/skills/skills.ts
  var SKILL_EFFECT_KINDS = Object.freeze(["unlocks", "modifies", "permits"]);
  var DEFAULT_SKILL_TUNING = Object.freeze({
    pointsPerLevel: 1,
    defaultNodeCost: 1,
    defaultMaxLevel: 10,
    // Index = level. 0 and 1 are unused: nobody buys level 0, and a learned skill
    // starts at 1.
    levelXp: Object.freeze([0, 0, 100, 250, 450, 700, 1e3, 1350, 1750, 2200, 2700]),
    advanceAction: "train_skill",
    unlockAction: "unlock_skill_node"
  });
  function nodeCost(node, tuning) {
    const cost = Math.floor(node.cost ?? tuning.defaultNodeCost);
    return Number.isFinite(cost) && cost > 0 ? cost : 0;
  }
  function nodeRequirements(node) {
    const goals = /* @__PURE__ */ new Set();
    for (const parent of node.parents) goals.add(`skill_unlocked(Actor, ${parent})`);
    for (const goal of node.requires) goals.add(goal);
    return [...goals].sort(compareIds);
  }
  function xpForLevel(skill, level, tuning) {
    const curve = skill?.levelXp && skill.levelXp.length > 0 ? skill.levelXp : tuning.levelXp;
    if (curve.length === 0 || level <= 0) return 0;
    const price = level < curve.length ? curve[level] : curve[curve.length - 1];
    const rounded = Math.floor(price);
    return Number.isFinite(rounded) && rounded > 0 ? rounded : 0;
  }
  function maxLevelOf(skill, tuning) {
    return skill?.maxLevel ?? tuning.defaultMaxLevel;
  }
  var SKILL_ADVANCE_REFUSALS = Object.freeze([
    /** The world declares no such skill. Not a refusal so much as an absence. */
    "unknown",
    /** A `skill_requires/3` prerequisite skill is missing or too low. */
    "prerequisite",
    /** `skill_capped/2` — already at the world's cap. */
    "capped",
    /** Not enough banked `skill_xp/3` for the next level. */
    "xp",
    /** `permissible/3` refused it — a norm, a law, a guild that will not teach you. */
    "forbidden"
  ]);
  function resolveAdvance(input) {
    const tuning = input.tuning ?? DEFAULT_SKILL_TUNING;
    const skill = input.skill;
    const id = skill?.id ?? input.skillId ?? "";
    const next = input.level + 1;
    const price = xpForLevel(skill, next, tuning);
    const base = {
      actor: input.actor,
      skill: id,
      level: input.level,
      next,
      price,
      banked: input.banked,
      action: tuning.advanceAction
    };
    if (!skill) return { ...base, next: input.level, price: 0, available: false, refusal: "unknown" };
    const unmet = skill.requires.some((prereq) => (input.levels[prereq.skill] ?? 0) < prereq.level);
    if (unmet) return { ...base, available: false, refusal: "prerequisite" };
    if (input.level >= maxLevelOf(skill, tuning)) {
      return { ...base, next: input.level, available: false, refusal: "capped" };
    }
    if (input.banked < price) return { ...base, available: false, refusal: "xp" };
    return { ...base, available: true };
  }
  var SKILL_UNLOCK_REFUSALS = Object.freeze([
    /** No tree declares such a node. */
    "unknown",
    /** `skill_unlocked/2` already holds — a node is taken once. */
    "owned",
    /** `skill_points/3` — nothing left in the tree's pool. */
    "points",
    /** A `skill_node_requires/2` goal the rules layer did not satisfy. */
    "requires",
    /** `permissible/3` refused it — a norm, a law, a guild's own rules. */
    "forbidden"
  ]);
  function resolveUnlock(input) {
    const tuning = input.tuning ?? DEFAULT_SKILL_TUNING;
    const node = input.node;
    const base = {
      actor: input.actor,
      node: node?.id ?? input.nodeId ?? "",
      tree: node?.tree ?? "",
      points: input.points,
      action: tuning.unlockAction
    };
    if (!node) {
      return { ...base, cost: 0, available: false, refusal: "unknown", requires: [], conditional: false };
    }
    const cost = nodeCost(node, tuning);
    const requires = nodeRequirements(node);
    const resolution = { ...base, cost, requires, conditional: requires.length > 0 };
    if (input.unlocked) return { ...resolution, available: false, refusal: "owned" };
    if (input.points < cost) return { ...resolution, available: false, refusal: "points" };
    return { ...resolution, available: true };
  }
  function treesFundedBy(trees, skill) {
    return trees.filter((tree) => tree.skill === skill).map((tree) => tree.id).sort(compareIds);
  }
  function findNode(trees, nodeId) {
    for (const tree of trees) {
      for (const node of tree.nodes) if (node.id === nodeId) return { ...node, tree: tree.id };
    }
    return void 0;
  }
  function nodeDepth(tree, nodeId, seen = []) {
    if (seen.includes(nodeId)) return 0;
    const node = tree.nodes.find((candidate) => candidate.id === nodeId);
    if (!node || node.parents.length === 0) return 0;
    let deepest = 0;
    for (const parent of node.parents) {
      deepest = Math.max(deepest, 1 + nodeDepth(tree, parent, [...seen, nodeId]));
    }
    return deepest;
  }

  // @insimul/core/src/skills/skill-effects.ts
  var SKILL_EFFECT_UNLOCKS = "unlocks";
  var SKILL_EFFECT_MODIFIES = "modifies";
  var SKILL_EFFECT_PERMITS = "permits";
  function effectsOfKind(effects, kind) {
    return effects.filter((effect) => effect.kind === kind);
  }
  function atomArguments(effects, kind) {
    const atoms = /* @__PURE__ */ new Set();
    for (const effect of effectsOfKind(effects, kind)) {
      const first = effect.args[0];
      if (first !== void 0) atoms.add(String(first));
    }
    return [...atoms].sort(compareIds);
  }
  function unlockedActions(effects) {
    return atomArguments(effects, SKILL_EFFECT_UNLOCKS);
  }
  function permittedThings(effects) {
    return atomArguments(effects, SKILL_EFFECT_PERMITS);
  }
  function skillModifiers(effects) {
    const totals = /* @__PURE__ */ new Map();
    for (const effect of effectsOfKind(effects, SKILL_EFFECT_MODIFIES)) {
      const [param, amount] = effect.args;
      if (param === void 0) continue;
      if (typeof amount !== "number" || !Number.isFinite(amount)) continue;
      const key = String(param);
      totals.set(key, (totals.get(key) ?? 0) + amount);
    }
    return new Map([...totals].sort(([a], [b]) => compareIds(a, b)));
  }
  function modifierOf(effects, param) {
    return skillModifiers(effects).get(param) ?? 0;
  }
  function parameterField(param) {
    return param.replace(/_([a-z0-9])/g, (_, c) => c.toUpperCase());
  }
  function withSkillModifiers(snapshot2, effects) {
    const modifiers = skillModifiers(effects);
    if (modifiers.size === 0) return { ...snapshot2 };
    const out = { ...snapshot2 };
    for (const [param, amount] of modifiers) {
      const field = param in out ? param : parameterField(param);
      const current = out[field];
      if (typeof current !== "number") continue;
      out[field] = current + amount;
    }
    return out;
  }

  // @insimul/core/src/skills/skill-view.ts
  function buildSkillView(input) {
    const tuning = input.tuning ?? DEFAULT_SKILL_TUNING;
    const definitions = new Map((input.skills ?? []).map((skill) => [skill.id, skill]));
    const actor = input.actor;
    const unlocked = new Set(actor.unlocked ?? []);
    const forbidden = new Set(actor.forbidden ?? []);
    return input.trees.map((tree) => {
      const definition = definitions.get(tree.skill);
      const level = actor.levels?.[tree.skill] ?? 0;
      const maxLevel = maxLevelOf(definition, tuning);
      const capped = level >= maxLevel;
      const banked = actor.xp?.[tree.skill] ?? 0;
      const nextLevel = capped ? level : level + 1;
      const nextLevelPrice = capped ? 0 : xpForLevel(definition, nextLevel, tuning);
      const points = actor.points?.[tree.id] ?? 0;
      const nodes = tree.nodes.map(
        (node) => nodeView({ ...node, tree: tree.id }, { tree, tuning, points, unlocked, forbidden, actor })
      );
      return {
        id: tree.id,
        skill: tree.skill,
        label: tree.name ?? tree.id,
        level,
        maxLevel,
        capped,
        banked,
        nextLevel,
        nextLevelPrice,
        affordable: !capped && banked >= nextLevelPrice,
        points,
        spent: nodes.filter((node) => node.taken).reduce((sum, node) => sum + node.cost, 0),
        nodes,
        rows: rowsOf(nodes),
        edges: edgesOf(nodes),
        taken: nodes.filter((node) => node.taken).length,
        total: nodes.length
      };
    });
  }
  function nodeView(node, context) {
    const resolution = resolveUnlock({
      actor: context.actor.id,
      node,
      points: context.points,
      unlocked: context.unlocked.has(node.id),
      tuning: context.tuning
    });
    const unmet = [...context.actor.unmet?.[node.id] ?? []];
    const modifiers = [...skillModifiers(node.effects)].map(([param, amount]) => ({ param, amount }));
    const view = {
      id: node.id,
      tree: node.tree,
      label: node.name ?? node.id,
      depth: nodeDepth(context.tree, node.id),
      cost: resolution.cost,
      parents: [...node.parents],
      requires: nodeRequirements(node),
      unmet,
      taken: context.unlocked.has(node.id),
      available: resolution.available,
      conditional: resolution.conditional,
      effects: node.effects.map((effect) => ({ ...effect, args: [...effect.args] })),
      unlocks: unlockedActions(node.effects),
      permits: permittedThings(node.effects),
      modifies: modifiers
    };
    if (node.description !== void 0) view.description = node.description;
    if (resolution.refusal !== void 0) view.refusal = resolution.refusal;
    if (view.available && unmet.length > 0) {
      return { ...view, available: false, refusal: "requires" };
    }
    if (view.available && context.forbidden.has(node.id)) {
      return { ...view, available: false, refusal: "forbidden" };
    }
    return view;
  }
  function rowsOf(nodes) {
    const byDepth = /* @__PURE__ */ new Map();
    for (const node of nodes) {
      byDepth.set(node.depth, [...byDepth.get(node.depth) ?? [], node.id]);
    }
    return [...byDepth.keys()].sort((a, b) => a - b).map((depth) => [...byDepth.get(depth)].sort(compareIds));
  }
  function edgesOf(nodes) {
    return nodes.flatMap((node) => node.parents.map((parent) => ({ from: parent, to: node.id }))).sort((a, b) => compareIds(a.from, b.from) || compareIds(a.to, b.to));
  }
  function skillModifierTotals(effects) {
    const out = {};
    for (const [param, amount] of skillModifiers(effects)) out[param] = amount;
    return out;
  }

  // @insimul/core/src/skills/skill-facts.ts
  function emptySkillDelta() {
    return { retract: [], assert: [] };
  }
  function mergeSkillDeltas(...deltas) {
    const merged = emptySkillDelta();
    for (const delta of deltas) {
      merged.retract.push(...delta.retract);
      merged.assert.push(...delta.assert);
    }
    return merged;
  }
  var SKILL_RESOLUTION_PREDICATES = Object.freeze([
    "skill_xp/3",
    "skill_points/3",
    "skill_unlocked/2",
    "has_skill/3"
  ]);
  var SKILL_AUTHORED_PREDICATES = Object.freeze([
    "skill_defined/2",
    "skill_max_level/2",
    "skill_requires/3",
    "skill_level_xp/3",
    "skill_tree/2",
    "skill_node/2",
    "skill_node_cost/2",
    "skill_node_requires/2",
    "skill_node_effect/2"
  ]);
  function skillDefinitionFacts(skills, tuning) {
    const facts = [];
    for (const skill of skills) {
      const id = prologAtom(skill.id);
      facts.push(`skill_defined(${id}, ${prologAtom(skill.category)}).`);
      facts.push(`skill_max_level(${id}, ${skill.maxLevel}).`);
      for (const prereq of skill.requires) {
        facts.push(`skill_requires(${id}, ${prologAtom(prereq.skill)}, ${prereq.level}).`);
      }
      for (let level = 2; level <= skill.maxLevel; level += 1) {
        facts.push(`skill_level_xp(${id}, ${level}, ${xpForLevel(skill, level, tuning)}).`);
      }
    }
    return facts;
  }
  function skillTreeFacts(trees, tuning) {
    const facts = [];
    for (const tree of trees) {
      facts.push(`skill_tree(${prologAtom(tree.id)}, ${prologAtom(tree.skill)}).`);
      for (const node of tree.nodes) {
        const id = prologAtom(node.id);
        facts.push(`skill_node(${id}, ${prologAtom(tree.id)}).`);
        facts.push(`skill_node_cost(${id}, ${nodeCost(node, tuning)}).`);
        for (const goal of nodeRequirements(node)) {
          facts.push(`skill_node_requires(${id}, ${goal}).`);
        }
        for (const effect of node.effects) {
          facts.push(`skill_node_effect(${id}, ${effectTerm(effect)}).`);
        }
      }
    }
    return facts;
  }
  function effectTerm(effect) {
    if (effect.args.length === 0) return prologAtom(effect.kind);
    const args = effect.args.map(
      (arg) => typeof arg === "number" ? String(arg) : prologAtom(arg)
    );
    return `${prologAtom(effect.kind)}(${args.join(", ")})`;
  }
  function skillXpFact(actor, skill, xp) {
    return `skill_xp(${prologAtom(actor)}, ${prologAtom(skill)}, ${xp}).`;
  }
  function hasSkillFact(actor, skill, level) {
    return `has_skill(${prologAtom(actor)}, ${prologAtom(skill)}, ${level}).`;
  }
  function skillPointsFact(actor, tree, points) {
    return `skill_points(${prologAtom(actor)}, ${prologAtom(tree)}, ${points}).`;
  }
  function skillUnlockedFact(actor, node) {
    return `skill_unlocked(${prologAtom(actor)}, ${prologAtom(node)}).`;
  }
  function balanceDelta(fact, before, after) {
    if (before === after) return emptySkillDelta();
    return {
      retract: before === void 0 ? [] : [fact(before)],
      assert: [fact(after)]
    };
  }
  function skillXpDelta(actor, skill, before, after) {
    return balanceDelta((value) => skillXpFact(actor, skill, value), before, after);
  }
  function skillLevelDelta(actor, skill, before, after) {
    return balanceDelta(
      (value) => hasSkillFact(actor, skill, value),
      before === 0 ? void 0 : before,
      after
    );
  }
  function skillPointsDelta(actor, tree, before, after) {
    return balanceDelta((value) => skillPointsFact(actor, tree, value), before, after);
  }
  function skillUnlockDelta(actor, node) {
    return { retract: [], assert: [skillUnlockedFact(actor, node)] };
  }

  // @insimul/core/src/game-engine/logic/SkillProgression.ts
  var SkillProgression = class {
    constructor(config = {}) {
      __publicField(this, "engine");
      __publicField(this, "tuning");
      __publicField(this, "eventBus");
      /** Resolved once at construction, so it cannot be swapped out mid-session. */
      __publicField(this, "modifierSink");
      /** The world's authored content. Never written to by gameplay. */
      __publicField(this, "skills", /* @__PURE__ */ new Map());
      __publicField(this, "trees", []);
      __publicField(this, "actors", /* @__PURE__ */ new Map());
      this.engine = config.engine;
      this.tuning = config.tuning ?? { ...DEFAULT_SKILL_TUNING };
      this.eventBus = config.eventBus;
      this.modifierSink = config.skillModifiers ?? config.host?.skillModifiers;
      if (config.skills) this.loadSkills(config.skills);
      if (config.trees) this.loadTrees(config.trees);
      if (config.state) this.restore(config.state);
    }
    setEventBus(bus) {
      this.eventBus = bus;
    }
    /** The world's authored numbers, as this instance read them. */
    getTuning() {
      return { ...this.tuning };
    }
    // ── The authored world ─────────────────────────────────────────────────
    /** Replace the authored skills. */
    loadSkills(skills) {
      this.skills = new Map(skills.map((skill) => [skill.id, skill]));
    }
    /** Replace the authored trees. Node ids are settled against their tree here. */
    loadTrees(trees) {
      this.trees = trees.map((tree) => ({
        ...tree,
        nodes: tree.nodes.map((node) => ({ ...node, tree: tree.id }))
      }));
    }
    /** The authored skills, as this instance read them. */
    getSkills() {
      return [...this.skills.values()].map((skill) => ({ ...skill }));
    }
    /** The authored trees, as this instance read them. */
    getTrees() {
      return this.trees.map((tree) => ({ ...tree, nodes: tree.nodes.map((node) => ({ ...node })) }));
    }
    /**
     * Publish the world's authored skills and trees into the KB.
     *
     * Authored data, asserted at load the way `TraversalPlanner.publishGraph`
     * asserts the link graph — so a rule that asks `can_unlock/2` walks the same
     * tree core resolves over, and an authored quest objective can name a node
     * without a second export of it. Returns how many facts were written.
     */
    async publishWorld(engine = this.engine) {
      if (!engine) return 0;
      let written = 0;
      for (const fact of [
        ...skillDefinitionFacts([...this.skills.values()], this.tuning),
        ...skillTreeFacts(this.trees, this.tuning)
      ]) {
        await engine.assertFact(stripPeriod3(fact));
        written += 1;
      }
      return written;
    }
    // ── Roster ─────────────────────────────────────────────────────────────
    /** Add or replace an actor, and write their facts. */
    async register(registration) {
      const before = this.actors.get(registration.id);
      const after = {
        id: registration.id,
        levels: { ...registration.levels ?? {} },
        xp: { ...registration.xp ?? {} },
        points: { ...registration.points ?? {} },
        unlocked: [...registration.unlocked ?? []]
      };
      this.actors.set(registration.id, after);
      const deltas = [];
      for (const skill of union(before?.levels, after.levels)) {
        deltas.push(
          skillLevelDelta(after.id, skill, before?.levels[skill], after.levels[skill] ?? 0)
        );
      }
      for (const skill of union(before?.xp, after.xp)) {
        deltas.push(skillXpDelta(after.id, skill, before?.xp[skill], after.xp[skill] ?? 0));
      }
      for (const tree of union(before?.points, after.points)) {
        deltas.push(skillPointsDelta(after.id, tree, before?.points[tree], after.points[tree] ?? 0));
      }
      for (const node of after.unlocked) {
        if (!before?.unlocked.includes(node)) deltas.push(skillUnlockDelta(after.id, node));
      }
      const delta = mergeSkillDeltas(...deltas);
      await this.writeDelta(delta);
      this.publishModifiers(after.id);
      return delta;
    }
    /**
     * Forget an actor. Their facts are retracted; the authored world is untouched.
     *
     * Retract-only: an actor who left the world has no facts, not facts reading
     * zero — a `has_skill(gone, smithing, 0)` left behind is a character the rules
     * layer still thinks is present and merely unskilled.
     */
    async unregister(actorId) {
      const actor = this.actors.get(actorId);
      if (!actor) return emptySkillDelta();
      this.actors.delete(actorId);
      const delta = { retract: [], assert: [] };
      for (const [skill, level] of Object.entries(actor.levels)) {
        delta.retract.push(hasSkillFact(actorId, skill, level));
      }
      for (const [skill, xp] of Object.entries(actor.xp)) {
        delta.retract.push(skillXpFact(actorId, skill, xp));
      }
      for (const [tree, points] of Object.entries(actor.points)) {
        delta.retract.push(skillPointsFact(actorId, tree, points));
      }
      for (const node of actor.unlocked) delta.retract.push(skillUnlockedFact(actorId, node));
      await this.writeDelta(delta);
      if (this.modifierSink) {
        try {
          this.modifierSink.applyModifiers(actorId, {});
        } catch {
        }
      }
      return delta;
    }
    /** This actor's level in a skill. `0` for one they have not learned. */
    levelOf(actorId, skill) {
      return this.actors.get(actorId)?.levels[skill] ?? 0;
    }
    /** This actor's banked, unspent XP in a skill. */
    xpOf(actorId, skill) {
      return this.actors.get(actorId)?.xp[skill] ?? 0;
    }
    /** What this actor has left to spend in a tree. */
    pointsOf(actorId, tree) {
      return this.actors.get(actorId)?.points[tree] ?? 0;
    }
    /** Every node this actor has taken, in canonical order. */
    unlockedNodes(actorId) {
      return [...this.actors.get(actorId)?.unlocked ?? []].sort(compareIds);
    }
    /** Whether `skill_unlocked(Actor, Node)` holds. */
    hasUnlocked(actorId, node) {
      return this.actors.get(actorId)?.unlocked.includes(node) ?? false;
    }
    /**
     * What this actor's taken nodes DO — `skill_effect/2` in TypeScript.
     *
     * The read every other module makes (US-2), and the reason none of them needs
     * to know what a tree is: an effect is an authored term, and a module that
     * cares about `modifies(reach, 2)` asks for effects rather than for nodes.
     * Canonically ordered by node, so two engines applying them apply them in one
     * order.
     */
    effectsOf(actorId) {
      const effects = [];
      for (const node of this.unlockedNodes(actorId)) {
        const authored = findNode(this.trees, node);
        if (authored) effects.push(...authored.effects.map((effect) => ({ ...effect })));
      }
      return effects;
    }
    /**
     * Every numeric parameter this actor's taken nodes modify, summed (US-2).
     *
     * The convenience form of `skillModifiers(effectsOf(actor))`, for a caller that
     * is about to build a resolution input — `withSkillModifiers` is what applies
     * it. Reported rather than applied: this module does not know which module a
     * parameter belongs to, and the one that does is the one already holding the
     * snapshot.
     */
    modifiersOf(actorId) {
      return skillModifiers(this.effectsOf(actorId));
    }
    // ── The host ───────────────────────────────────────────────────────────
    /** Whether an engine supplied a modifier sink. `false` in a headless world. */
    hasModifierSink() {
      return this.modifierSink !== void 0;
    }
    /**
     * Hand an actor's whole current modifier set to the host (US-3).
     *
     * The module's only outbound call, and the only one it will ever have: an
     * effect whose parameter names a field of a snapshot core resolves from is
     * applied by the module that owns the snapshot (`withSkillModifiers`, US-2),
     * and an effect whose parameter names a quantity the ENGINE holds — how fast a
     * body moves, how far it reaches — can only be applied there.
     *
     * **Absolute, never a delta.** The whole set is sent every time, so re-applying
     * it is a no-op and a save load, a re-registration or a replayed unlock cannot
     * leave the host drifting from core. A host that throws is ignored: an engine
     * failing to move a speed number may not stop a node from being taken.
     *
     * With no actor named, every registered actor is published — what a caller
     * that has just restored a save wants, and the counterpart of
     * {@link publishActors}. Returns how many actors were published.
     */
    publishModifiers(actorId) {
      const sink = this.modifierSink;
      if (!sink) return 0;
      const actors = actorId === void 0 ? this.roster().map((a) => a.id) : [actorId];
      let published = 0;
      for (const id of actors) {
        if (actorId !== void 0 && !this.actors.has(id)) continue;
        try {
          sink.applyModifiers(id, skillModifierTotals(this.effectsOf(id)));
        } catch {
        }
        published += 1;
      }
      return published;
    }
    /**
     * The tree a host draws, for one actor — every authored tree, every node's
     * state, the rows and the edges (US-3).
     *
     * A VALUE rather than a hook, which is the whole of `docs/skill-progression.md`
     * §5: a panel is layout, layout differs legitimately between four engines, and
     * what may not differ is which nodes are open, what they cost and why the rest
     * are not. `buildSkillView` is the pure half; this is the half that asks the KB
     * the two questions a pure function may not — which authored goals are unmet,
     * and which nodes `permissible/3` refuses.
     *
     * One round trip per node, on the decision path: a player opening a screen,
     * never a frame. A caller with no KB can call `buildSkillView` directly and
     * gets a view whose gated nodes read `conditional` instead.
     */
    async viewOf(actorId) {
      const actor = this.actors.get(actorId);
      const unmet = {};
      const forbidden = [];
      for (const tree of this.trees) {
        for (const node of tree.nodes) {
          const goals = await this.unmetRequirements(actorId, nodeRequirements(node));
          if (goals.length > 0) unmet[node.id] = goals;
          const check = await this.checkPermission(actorId, this.tuning.unlockAction, node.id);
          if (!check.permitted) forbidden.push(node.id);
        }
      }
      const view = {
        id: actorId,
        levels: actor?.levels ?? {},
        xp: actor?.xp ?? {},
        points: actor?.points ?? {},
        unlocked: this.unlockedNodes(actorId),
        unmet,
        forbidden
      };
      return buildSkillView({ trees: this.trees, skills: this.getSkills(), tuning: this.tuning, actor: view });
    }
    // ── XP ─────────────────────────────────────────────────────────────────
    /**
     * Bank XP against a skill — what practising, questing or being taught pays.
     *
     * How MUCH an action is worth is not decided here and gets no predicate: it is
     * a property of the action the world authored, handed in by whoever raised the
     * event. A negative award is read as zero rather than as a punishment; a world
     * that wants to take skill away authors that, and silently draining a bank is
     * the bug that would hide.
     */
    async award(actorId, skill, amount) {
      const actor = this.actors.get(actorId);
      const awarded = Number.isFinite(amount) && amount > 0 ? Math.floor(amount) : 0;
      if (!actor || awarded === 0) {
        return {
          actor: actorId,
          skill,
          awarded: 0,
          banked: this.xpOf(actorId, skill),
          advanceable: (await this.canAdvance(actorId, skill)).available,
          facts: emptySkillDelta(),
          applied: false
        };
      }
      const before = actor.xp[skill];
      const banked = (before ?? 0) + awarded;
      actor.xp[skill] = banked;
      const facts = skillXpDelta(actorId, skill, before, banked);
      const applied = await this.writeDelta(facts);
      return {
        actor: actorId,
        skill,
        awarded,
        banked,
        advanceable: (await this.canAdvance(actorId, skill)).available,
        facts,
        applied
      };
    }
    /**
     * Whether this actor may take the next level of a skill, without taking it.
     *
     * Every gate in {@link SKILL_ADVANCE_REFUSALS} order: what core knows first —
     * the skill exists, its `skill_requires/3` prerequisites are met, it is not
     * capped, the bank affords it — then permissibility. Advancing from 0 to 1 is
     * LEARNING, which is why `can_learn_skill/2` and `can_advance/2` are one
     * operation here rather than two entry points a caller has to choose between.
     */
    async canAdvance(actorId, skill) {
      const actor = this.actors.get(actorId);
      const resolution = resolveAdvance({
        actor: actorId,
        skill: this.skills.get(skill),
        skillId: skill,
        level: actor?.levels[skill] ?? 0,
        banked: actor?.xp[skill] ?? 0,
        levels: actor?.levels ?? {},
        tuning: this.tuning
      });
      if (!resolution.available) return { ...resolution, permitted: false };
      const check = await this.checkPermission(actorId, this.tuning.advanceAction, skill);
      if (!check.permitted) {
        return { ...resolution, available: false, refusal: "forbidden", check, permitted: false };
      }
      return { ...resolution, check, permitted: true };
    }
    /**
     * Take the next level of a skill, if every gate allows it.
     *
     * The order is the module's discipline, and each step is where it is for a
     * reason:
     *
     *  1. **Decide** ({@link canAdvance}). Nothing has happened yet.
     *  2. **Spend** the banked XP. The bank is a currency, not a running total —
     *     `docs/skill-progression.md` §3.
     *  3. **Raise** `has_skill/3`, which is the fact the rest of the world already
     *     reads.
     *  4. **Grant** points to every tree the skill funds, so there is something to
     *     spend them on.
     */
    async advance(actorId, skill) {
      const decision = await this.canAdvance(actorId, skill);
      const actor = this.actors.get(actorId);
      const level = actor?.levels[skill] ?? 0;
      if (!decision.permitted || !actor) {
        return {
          ...decision,
          performed: false,
          level,
          spent: 0,
          granted: [],
          facts: emptySkillDelta(),
          applied: false
        };
      }
      const banked = actor.xp[skill] ?? 0;
      const remaining = banked - decision.price;
      const raised = level + 1;
      actor.xp[skill] = remaining;
      actor.levels[skill] = raised;
      const granted = [];
      const pointDeltas = [];
      for (const treeId of treesFundedBy(this.trees, skill)) {
        const before = actor.points[treeId];
        const after = (before ?? 0) + this.tuning.pointsPerLevel;
        actor.points[treeId] = after;
        granted.push({ treeId, points: this.tuning.pointsPerLevel });
        pointDeltas.push(skillPointsDelta(actorId, treeId, before, after));
      }
      const facts = mergeSkillDeltas(
        skillXpDelta(actorId, skill, banked, remaining),
        skillLevelDelta(actorId, skill, level, raised),
        ...pointDeltas
      );
      const applied = await this.writeDelta(facts);
      this.eventBus?.emit({
        type: "skill_advanced",
        actorId,
        skillId: skill,
        level: raised,
        spent: decision.price,
        granted
      });
      return {
        ...decision,
        performed: true,
        level: raised,
        spent: decision.price,
        granted,
        facts,
        applied
      };
    }
    /** What the next level of this skill would cost, or `0` past the cap. */
    priceOfNextLevel(actorId, skill) {
      const definition = this.skills.get(skill);
      const level = this.levelOf(actorId, skill);
      if (level >= maxLevelOf(definition, this.tuning)) return 0;
      return xpForLevel(definition, level + 1, this.tuning);
    }
    // ── Nodes ──────────────────────────────────────────────────────────────
    /**
     * Whether this actor may take a node, without taking it.
     *
     * Every gate in {@link SKILL_UNLOCK_REFUSALS} order: the node exists, it is not
     * already taken, the pool affords it, its authored goals hold, and nothing
     * forbids it. The two rules-layer rungs come last because they cost a round
     * trip and because a node nobody can pay for is refused for a reason nobody
     * needs the KB to explain.
     */
    async canUnlock(actorId, nodeId) {
      const node = findNode(this.trees, nodeId);
      const resolution = resolveUnlock({
        actor: actorId,
        node,
        nodeId,
        points: node ? this.pointsOf(actorId, node.tree) : 0,
        unlocked: this.hasUnlocked(actorId, nodeId),
        tuning: this.tuning
      });
      if (!resolution.available) return { ...resolution, unmet: [], permitted: false };
      const unmet = await this.unmetRequirements(actorId, resolution.requires);
      if (unmet.length > 0) {
        return { ...resolution, available: false, refusal: "requires", unmet, permitted: false };
      }
      const check = await this.checkPermission(actorId, resolution.action, nodeId);
      if (!check.permitted) {
        return {
          ...resolution,
          available: false,
          refusal: "forbidden",
          unmet,
          check,
          permitted: false
        };
      }
      return { ...resolution, unmet, check, permitted: true };
    }
    /**
     * Take a node, if every gate allows it.
     *
     * Spend, then record. What the node DOES is not applied here and never will be:
     * an effect is an authored term the KB carries, and the module it affects reads
     * it (US-2). A `SkillProgression` that reached into `CombatResolver` would be
     * the fork this whole design exists to avoid.
     */
    async unlock(actorId, nodeId) {
      const decision = await this.canUnlock(actorId, nodeId);
      const actor = this.actors.get(actorId);
      const node = findNode(this.trees, nodeId);
      const effects = node?.effects ?? [];
      if (!decision.permitted || !actor || !node) {
        return {
          ...decision,
          performed: false,
          remaining: decision.points,
          effects,
          facts: emptySkillDelta(),
          applied: false
        };
      }
      const before = actor.points[node.tree];
      const remaining = (before ?? 0) - decision.cost;
      actor.points[node.tree] = remaining;
      actor.unlocked.push(nodeId);
      const facts = mergeSkillDeltas(
        skillPointsDelta(actorId, node.tree, before, remaining),
        skillUnlockDelta(actorId, nodeId)
      );
      const applied = await this.writeDelta(facts);
      this.publishModifiers(actorId);
      this.eventBus?.emit({
        type: "skill_node_unlocked",
        actorId,
        nodeId,
        treeId: node.tree,
        cost: decision.cost,
        effects: effects.map((effect) => effectTerm(effect))
      });
      return { ...decision, performed: true, remaining, effects, facts, applied };
    }
    // ── The gates ──────────────────────────────────────────────────────────
    /**
     * The authored goals a node asks that the KB did not satisfy.
     *
     * Evaluated by the PACK's own `skill_goal_met/2`, not by a second
     * implementation here: the pack rebuilds the goal with the actor bound (`=..`),
     * and reproducing that rebuild in TypeScript is how one guild member's
     * reputation ends up unlocking the whole roster's node — the correction
     * `traversal_goal_met/2` already carries.
     *
     * With no KB wired every goal is unmet — see the module header for why this
     * gate fails closed and permissibility fails open.
     */
    async unmetRequirements(actorId, requires) {
      if (requires.length === 0) return [];
      if (!this.engine) return [...requires];
      const unmet = [];
      for (const goal of requires) {
        let met = false;
        try {
          met = await this.engine.queryOnce(`skill_goal_met(${prologAtom(actorId)}, ${goal})`);
        } catch {
          met = false;
        }
        if (!met) unmet.push(goal);
      }
      return unmet;
    }
    /**
     * `permissible/3`'s own input, forwarded with the attempt spelled as the action
     * it is.
     *
     * There is deliberately no progression-private gate: a guild that will not
     * teach an outsider, a law against training in a besieged city and a norm
     * against taking the assassin's node are all refused by whatever `forbids/4`
     * refuses them with, which is the same clause that refuses a theft. With no KB
     * wired every advancement is permitted; core does not invent a prohibition it
     * cannot read.
     */
    async checkPermission(actorId, action, target) {
      const subject = target || NO_TARGET;
      if (!this.engine) {
        return { agent: actorId, action, target: subject, permitted: true, breached: [] };
      }
      return checkAction(this.engine, { agent: actorId, action, target: subject });
    }
    // ── The KB ─────────────────────────────────────────────────────────────
    /**
     * Write one delta into the KB, retracting first.
     *
     * Retracting a fact the KB never carried is a no-op rather than a failure: a
     * host with its own persistence, a restored save and an actor registered before
     * the engine was wired all produce one, and none of them is an error.
     */
    async writeDelta(delta) {
      if (!this.engine) return false;
      if (delta.retract.length === 0 && delta.assert.length === 0) return false;
      for (const fact of delta.retract) {
        try {
          await this.engine.retractFact(stripPeriod3(fact));
        } catch {
        }
      }
      for (const fact of delta.assert) {
        await this.engine.assertFact(stripPeriod3(fact));
      }
      return true;
    }
    /**
     * Publish every registered actor's levels, banks, pools and taken nodes.
     *
     * For a caller that wired the KB after the roster — a save restore, a host that
     * builds its world before its engine. Returns how many facts were written.
     */
    async publishActors(engine = this.engine) {
      if (!engine) return 0;
      let written = 0;
      for (const actor of this.roster()) {
        const delta = mergeSkillDeltas(
          ...Object.entries(actor.levels).map(
            ([skill, level]) => skillLevelDelta(actor.id, skill, void 0, level)
          ),
          ...Object.entries(actor.xp).map(([skill, xp]) => skillXpDelta(actor.id, skill, void 0, xp)),
          ...Object.entries(actor.points).map(
            ([tree, points]) => skillPointsDelta(actor.id, tree, void 0, points)
          ),
          ...actor.unlocked.map((node) => skillUnlockDelta(actor.id, node))
        );
        for (const fact of delta.assert) {
          await engine.assertFact(stripPeriod3(fact));
          written += 1;
        }
      }
      return written;
    }
    // ── Save/restore ───────────────────────────────────────────────────────
    /** Every actor this module knows, in canonical order. */
    roster() {
      return [...this.actors.values()].map((actor) => ({
        id: actor.id,
        levels: sortedRecord(actor.levels),
        xp: sortedRecord(actor.xp),
        points: sortedRecord(actor.points),
        unlocked: [...actor.unlocked].sort(compareIds)
      })).sort((a, b) => compareIds(a.id, b.id));
    }
    /**
     * The per-playthrough state, and only that: what each actor has learned,
     * banked, been granted and taken. The skills, the trees, the curve, the costs
     * and the effects are authored and are NOT here — a tuning number inside a save
     * file is world-template data leaking into a playthrough
     * (`docs/mechanic-predicates.md` §3).
     */
    serialize() {
      return { actors: this.roster() };
    }
    /**
     * Restore a saved playthrough. Silent — no events, because loading a save is
     * not somebody levelling up, no KB writes, because restoring a save is what
     * `publishActors` is for once the engine exists, and no host call, because
     * {@link publishModifiers} is its counterpart on the other seam. A caller that
     * restores into a live world calls both; one that restores into a world it is
     * still building calls neither yet.
     */
    restore(state) {
      this.actors = /* @__PURE__ */ new Map();
      for (const actor of state.actors ?? []) {
        this.actors.set(actor.id, {
          id: actor.id,
          levels: { ...actor.levels ?? {} },
          xp: { ...actor.xp ?? {} },
          points: { ...actor.points ?? {} },
          unlocked: [...actor.unlocked ?? []]
        });
      }
    }
  };
  function stripPeriod3(clause) {
    return clause.replace(/\.$/, "");
  }
  function union(before, after) {
    return [.../* @__PURE__ */ new Set([...Object.keys(before ?? {}), ...Object.keys(after)])].sort(compareIds);
  }
  function sortedRecord(record) {
    const out = {};
    for (const key of Object.keys(record).sort(compareIds)) out[key] = record[key];
    return out;
  }

  // @insimul/core/src/game-engine/logic/EquipmentManager.ts
  var EQUIPMENT_SLOTS = ["weapon", "armor", "accessory"];
  var STAT_ALIASES = {
    attack: "attackPower",
    attackPower: "attackPower",
    damage: "attackPower",
    defense: "defense",
    defence: "defense",
    armor: "defense",
    dodge: "dodgeChance",
    dodgeChance: "dodgeChance",
    evasion: "dodgeChance"
  };
  var ZERO_BONUSES = { attackPower: 0, defense: 0, dodgeChance: 0 };
  var EquipmentManager = class {
    constructor(config = {}) {
      __publicField(this, "combatStats");
      __publicField(this, "eventBus");
      __publicField(this, "entityId");
      __publicField(this, "equipped", {});
      /** Read once per entity — see the file header on why this is not re-read. */
      __publicField(this, "baseStats");
      __publicField(this, "baseStatsRead", false);
      this.combatStats = config.combatStats ?? config.host?.combatStats;
      this.eventBus = config.eventBus;
      this.entityId = config.entityId ?? "player";
      if (config.state) this.setState(config.state);
    }
    setEventBus(bus) {
      this.eventBus = bus;
    }
    /** Whether a host supplied {@link ICombatStatSink}. False means stats are tracked only. */
    hasStatSink() {
      return this.combatStats !== void 0;
    }
    /** Point the manager at a different entity and re-apply the current loadout. */
    setEntityId(entityId) {
      if (entityId === this.entityId) return;
      this.entityId = entityId;
      this.baseStats = void 0;
      this.baseStatsRead = false;
      this.applyStats();
    }
    getEntityId() {
      return this.entityId;
    }
    // ── Equipping ──────────────────────────────────────────────────────────
    /**
     * Equip an item, replacing whatever occupied its slot.
     *
     * An item with no `equipSlot` is rejected (`'no_slot'`) rather than guessed
     * at: which slot a sword belongs in is authored data, not an inference core
     * should be making.
     */
    equip(item) {
      const slot = item.equipSlot;
      if (!slot) return { equipped: false, reason: "no_slot" };
      const current = this.equipped[slot];
      if (current?.itemId === item.id) return { equipped: false, reason: "already_equipped" };
      if (current) this.releaseSlot(slot, current);
      this.equipped[slot] = {
        itemId: item.id,
        itemName: item.name,
        slot,
        effects: item.effects ? { ...item.effects } : void 0
      };
      this.eventBus?.emit({ type: "item_equipped", itemId: item.id, itemName: item.name, slot });
      this.applyStats();
      return { equipped: true, replaced: current };
    }
    /** Empty a slot. Returns what came off, or `null` if it was already empty. */
    unequip(slot) {
      const current = this.equipped[slot];
      if (!current) return null;
      this.releaseSlot(slot, current);
      this.applyStats();
      return current;
    }
    /** Empty whichever slot holds `itemId`. */
    unequipItem(itemId) {
      const slot = EQUIPMENT_SLOTS.find((s) => this.equipped[s]?.itemId === itemId);
      return slot ? this.unequip(slot) : null;
    }
    /** Empty every slot, emitting one `item_unequipped` per item. */
    unequipAll() {
      const removed = [];
      for (const slot of EQUIPMENT_SLOTS) {
        const current = this.equipped[slot];
        if (!current) continue;
        this.releaseSlot(slot, current);
        removed.push(current);
      }
      if (removed.length > 0) this.applyStats();
      return removed;
    }
    /** Clears the slot and announces it. Stat application is the caller's, so a
     *  multi-slot change writes stats once rather than once per slot. */
    releaseSlot(slot, item) {
      delete this.equipped[slot];
      this.eventBus?.emit({
        type: "item_unequipped",
        itemId: item.itemId,
        itemName: item.itemName,
        slot
      });
    }
    // ── Queries ────────────────────────────────────────────────────────────
    getEquipped(slot) {
      return this.equipped[slot];
    }
    getAllEquipped() {
      return EQUIPMENT_SLOTS.map((s) => this.equipped[s]).filter(
        (e) => e !== void 0
      );
    }
    isEquipped(itemId) {
      return this.getAllEquipped().some((e) => e.itemId === itemId);
    }
    isSlotFilled(slot) {
      return this.equipped[slot] !== void 0;
    }
    /** The summed bonus of everything worn, before base stats. */
    getBonuses() {
      const total = { ...ZERO_BONUSES };
      for (const item of this.getAllEquipped()) {
        for (const [key, value] of Object.entries(item.effects ?? {})) {
          const stat = STAT_ALIASES[key];
          if (stat && Number.isFinite(value)) total[stat] += value;
        }
      }
      return total;
    }
    /**
     * Base stats plus {@link getBonuses}, or `undefined` when no host supplied
     * base stats to add them to (no sink, or an entity not in combat).
     */
    getEffectiveStats() {
      const base = this.readBaseStats();
      if (!base) return void 0;
      const bonuses = this.getBonuses();
      return {
        attackPower: base.attackPower + bonuses.attackPower,
        defense: base.defense + bonuses.defense,
        dodgeChance: base.dodgeChance + bonuses.dodgeChance
      };
    }
    /**
     * Re-read base stats from the host and re-apply. Call this when the entity's
     * unequipped stats changed for a reason equipment did not cause.
     */
    refreshBaseStats() {
      this.baseStats = void 0;
      this.baseStatsRead = false;
      this.applyStats();
    }
    readBaseStats() {
      if (!this.baseStatsRead) {
        this.baseStats = this.combatStats?.getBaseStats(this.entityId);
        this.baseStatsRead = true;
      }
      return this.baseStats;
    }
    /** Write recomputed totals back. A no-op without a sink or base stats. */
    applyStats() {
      if (!this.combatStats) return;
      const effective = this.getEffectiveStats();
      if (!effective) return;
      this.combatStats.applyStats(this.entityId, effective);
    }
    // ── Save/restore ───────────────────────────────────────────────────────
    getState() {
      const state = {};
      for (const item of this.getAllEquipped()) {
        state[item.slot] = { ...item, effects: item.effects ? { ...item.effects } : void 0 };
      }
      return state;
    }
    /**
     * Restore a saved loadout. Silent — no `item_equipped` events, because
     * loading a save is not the player equipping anything, and quest listeners
     * that count equips must not fire on load.
     */
    setState(state) {
      this.equipped = {};
      for (const slot of EQUIPMENT_SLOTS) {
        const item = state[slot];
        if (!item) continue;
        this.equipped[slot] = { ...item, slot, effects: item.effects ? { ...item.effects } : void 0 };
      }
      this.applyStats();
    }
  };

  // @insimul/core/src/routines/routine-facts.ts
  function emptyRoutineDelta() {
    return { retract: [], assert: [] };
  }
  var ROUTINE_RESOLUTION_PREDICATES = Object.freeze([
    "follows_routine/2",
    "routine_suspended/2",
    "agent_goal/3"
  ]);
  var ROUTINE_AUTHORED_FACT_PREDICATES = Object.freeze([
    "routine/2",
    "routine_block/2",
    "routine_block_window/3",
    "routine_block_day/2",
    "routine_block_goal/2",
    "routine_block_place/2",
    "routine_block_priority/2",
    "routine_week_length/1"
  ]);
  function routineGraphFacts(routines, tuning) {
    const facts = [`routine_week_length(${Math.max(1, Math.trunc(tuning.weekLength))}).`];
    for (const routine of routines) {
      facts.push(`routine(${prologAtom(routine.id)}, ${prologAtom(routine.name)}).`);
      for (const block of routine.blocks) {
        const id = prologAtom(block.id);
        facts.push(`routine_block(${prologAtom(routine.id)}, ${id}).`);
        facts.push(`routine_block_window(${id}, ${block.startHour}, ${block.endHour}).`);
        facts.push(`routine_block_goal(${id}, ${prologAtom(block.goal)}).`);
        facts.push(`routine_block_priority(${id}, ${block.priority}).`);
        if (block.place !== void 0) {
          facts.push(`routine_block_place(${id}, ${prologAtom(block.place)}).`);
        }
        for (const day of block.days) facts.push(`routine_block_day(${id}, ${day}).`);
      }
    }
    return facts;
  }
  function followsRoutineFact(agent, routine) {
    return `follows_routine(${prologAtom(agent)}, ${prologAtom(routine)}).`;
  }
  function routineSuspendedFact(agent, reason) {
    return `routine_suspended(${prologAtom(agent)}, ${prologAtom(reason)}).`;
  }
  function agentGoalFact(agent, goal, priority) {
    return `agent_goal(${prologAtom(agent)}, ${prologAtom(goal)}, ${Math.trunc(priority)}).`;
  }
  function adoptedGoalDelta(agent, before, after) {
    if (before?.goal === after?.goal && before?.priority === after?.priority) {
      return emptyRoutineDelta();
    }
    return {
      retract: before === null ? [] : [agentGoalFact(agent, before.goal, before.priority)],
      assert: after === null ? [] : [agentGoalFact(agent, after.goal, after.priority)]
    };
  }
  function suspensionDelta(agent, before, after) {
    if (before === after) return emptyRoutineDelta();
    return {
      retract: before === null ? [] : [routineSuspendedFact(agent, before)],
      assert: after === null ? [] : [routineSuspendedFact(agent, after)]
    };
  }
  function assignmentDelta(agent, before, after) {
    if (before === after) return emptyRoutineDelta();
    return {
      retract: before === null ? [] : [followsRoutineFact(agent, before)],
      assert: after === null ? [] : [followsRoutineFact(agent, after)]
    };
  }
  function mergeRoutineDeltas(...deltas) {
    const merged = emptyRoutineDelta();
    for (const delta of deltas) {
      merged.retract.push(...delta.retract);
      merged.assert.push(...delta.assert);
    }
    return merged;
  }

  // @insimul/core/src/routines/routines.ts
  var DEFAULT_ROUTINE_TUNING = Object.freeze({
    defaultPriority: 50,
    weekLength: 7
  });
  function routineTuningFromIR(ir) {
    return {
      defaultPriority: intOr(ir?.defaultPriority, DEFAULT_ROUTINE_TUNING.defaultPriority),
      weekLength: Math.max(1, intOr(ir?.weekLength, DEFAULT_ROUTINE_TUNING.weekLength))
    };
  }
  function routinesFromIR(ir, tuning) {
    const resolved = tuning ?? routineTuningFromIR(ir);
    const routines = [];
    for (const authored of ir?.routines ?? []) {
      if (!authored?.id) continue;
      routines.push(resolveRoutine(authored, resolved));
    }
    return routines;
  }
  function resolveRoutine(authored, tuning) {
    const blocks = [];
    for (const block of authored.blocks ?? []) {
      if (!block?.id || !block.goal) continue;
      blocks.push(resolveBlock(block, tuning));
    }
    return { id: authored.id, name: authored.name ?? authored.id, blocks };
  }
  function resolveBlock(block, tuning) {
    const days = Array.from(
      new Set((block.days ?? []).map((day) => Math.trunc(day)).filter((day) => day >= 0))
    ).sort((a, b) => a - b);
    return {
      id: block.id,
      goal: block.goal,
      startHour: wholeHour(block.startHour, 0),
      endHour: wholeHour(block.endHour, 24),
      days,
      ...block.place ? { place: block.place } : {},
      priority: intOr(block.priority, tuning.defaultPriority)
    };
  }
  function weekdayOf(clock, tuning) {
    const length = Math.max(1, Math.trunc(tuning.weekLength));
    return (Math.trunc(clock.day) % length + length) % length;
  }
  function hourInWindow(hour, startHour, endHour) {
    const h = Math.trunc(hour);
    if (startHour < endHour) return h >= startHour && h < endHour;
    return h >= startHour || h < endHour;
  }
  function blockOpen(block, clock, tuning) {
    if (!hourInWindow(clock.hour, block.startHour, block.endHour)) return false;
    if (block.days.length === 0) return true;
    return block.days.includes(weekdayOf(clock, tuning));
  }
  function dueBlocks(routine, clock, tuning) {
    return routine.blocks.filter((block) => blockOpen(block, clock, tuning)).sort((a, b) => a.priority !== b.priority ? b.priority - a.priority : compareIds(a.id, b.id));
  }
  function activeBlock(routine, clock, tuning) {
    return dueBlocks(routine, clock, tuning)[0] ?? null;
  }
  function routineIssues(routines, tuning = DEFAULT_ROUTINE_TUNING) {
    const issues = [];
    const placeOfGoal = /* @__PURE__ */ new Map();
    for (const routine of routines) {
      for (const block of routine.blocks) {
        const where = `${routine.id}.${block.id}`;
        if (!block.goal) issues.push(`${where}: block names no goal`);
        if (block.startHour < 0 || block.startHour > 23) {
          issues.push(`${where}: startHour ${block.startHour} is not an hour of the day (0-23)`);
        }
        if (block.endHour < 0 || block.endHour > 24) {
          issues.push(`${where}: endHour ${block.endHour} is not an hour of the day (0-24)`);
        }
        for (const day of block.days) {
          if (day >= tuning.weekLength) {
            issues.push(
              `${where}: day ${day} is outside a ${tuning.weekLength}-day week, so the block never runs`
            );
          }
        }
        if (block.place === void 0) continue;
        const seen = placeOfGoal.get(block.goal);
        if (seen === void 0) {
          placeOfGoal.set(block.goal, { place: block.place, block: where });
        } else if (seen.place !== block.place) {
          const [first, second] = [{ block: where, place: block.place }, seen].sort(
            (a, b) => compareIds(a.block, b.block)
          );
          issues.push(
            `${first.block}: goal "${block.goal}" is pursued at "${first.place}" here and at "${second.place}" in ${second.block}. A block's place is a requirement of its GOAL, so one goal in two places can never be satisfied \u2014 author two goals.`
          );
        }
      }
    }
    return issues.sort(compareIds);
  }
  var SCHEDULE_ACTIVITY_GOALS = Object.freeze([
    "sleep",
    "work",
    "eat",
    "socialize",
    "shop",
    "wander",
    "idle_at_home",
    "visit_friend"
  ]);
  function intOr(value, fallback) {
    return typeof value === "number" && Number.isFinite(value) ? Math.trunc(value) : fallback;
  }
  function wholeHour(value, fallback) {
    if (typeof value !== "number" || !Number.isFinite(value)) return fallback;
    return Math.trunc(value);
  }

  // @insimul/core/src/game-engine/logic/RoutineDirector.ts
  var RoutineDirector = class {
    constructor(config = {}) {
      __publicField(this, "engine");
      __publicField(this, "eventBus");
      __publicField(this, "plans");
      __publicField(this, "tuning");
      __publicField(this, "routines", /* @__PURE__ */ new Map());
      __publicField(this, "agents", /* @__PURE__ */ new Map());
      this.engine = config.engine;
      this.eventBus = config.eventBus;
      this.plans = config.plans;
      const authored = config.routines;
      if (Array.isArray(authored)) {
        this.tuning = { ...DEFAULT_ROUTINE_TUNING, ...config.tuning };
        for (const routine of authored) this.routines.set(routine.id, routine);
      } else {
        const ir = authored ?? null;
        this.tuning = { ...routineTuningFromIR(ir), ...config.tuning };
        for (const routine of routinesFromIR(ir, this.tuning)) this.routines.set(routine.id, routine);
      }
    }
    // ── The authored world ────────────────────────────────────────────────────
    /** The routine with this id, or `undefined`. Read-only. */
    routine(id) {
      return this.routines.get(id);
    }
    /** Everything wrong with the routines this world authored. Empty = sound. */
    issues() {
      return routineIssues(
        [...this.routines.values()].sort((a, b) => compareIds(a.id, b.id)),
        this.tuning
      );
    }
    /**
     * Publish the authored routines into the KB.
     *
     * For load time, and for a caller that wired the KB after the world — exactly
     * what `TraversalPlanner.publishGraph` is for. Returns how many facts were
     * written.
     */
    async publishRoutines(engine = this.engine) {
      if (!engine) return 0;
      const ordered = [...this.routines.values()].sort((a, b) => compareIds(a.id, b.id));
      const facts = routineGraphFacts(ordered, this.tuning);
      for (const fact of facts) await engine.assertFact(stripPeriod4(fact));
      return facts.length;
    }
    // ── The roster ────────────────────────────────────────────────────────────
    /**
     * Give an NPC a routine, or take one away with `null`.
     *
     * Adopting the routine's goal is the next {@link RoutineDirector.tick}'s job and
     * not this one's: what an NPC wants depends on the clock, and a method that
     * took a routine would have to take a time too.
     */
    async assign(agent, routine) {
      const key = agentRefKey(agent);
      const state = this.stateOf(key);
      if (state.routine === routine) return;
      const delta = mergeRoutineDeltas(
        assignmentDelta(key, state.routine, routine),
        // An NPC that gave up its routine gives up the goal that routine adopted.
        // A goal somebody else gave it is untouched.
        routine === null ? adoptedGoalDelta(key, state.adopted, null) : emptyRoutineDelta()
      );
      state.routine = routine;
      if (routine === null) state.adopted = null;
      await this.writeDelta(delta);
    }
    /** The routine this NPC keeps, or `null`. */
    routineOf(agent) {
      return this.agents.get(agentRefKey(agent))?.routine ?? null;
    }
    /** Forget an NPC entirely: it died, it despawned, it left the simulation. */
    async forget(agent) {
      const key = agentRefKey(agent);
      const state = this.agents.get(key);
      if (state === void 0) return;
      this.agents.delete(key);
      await this.writeDelta(
        mergeRoutineDeltas(
          assignmentDelta(key, state.routine, null),
          adoptedGoalDelta(key, state.adopted, null),
          suspensionDelta(key, state.suspension?.reason ?? null, null)
        )
      );
    }
    // ── The tick ──────────────────────────────────────────────────────────────
    /**
     * Advance every NPC's routine to this clock.
     *
     * Per NPC: resolve the block its routine has open now, work out the goal that
     * implies, and write the difference. Nothing else. The roster is iterated in
     * whatever order the caller passed and the RESULT does not depend on it — no
     * NPC's state is read by another's pass, and outcomes come back sorted.
     */
    async tick(clock, agents) {
      const outcomes = [];
      let changed = 0;
      for (const agent of agents) {
        const outcome = await this.tickAgent(clock, agentRefKey(agent));
        if (outcome.changed) changed += 1;
        outcomes.push(outcome);
      }
      outcomes.sort((a, b) => compareIds(a.agent, b.agent));
      return { clock, outcomes, changed };
    }
    async tickAgent(clock, agent) {
      const state = this.stateOf(agent);
      const routine = state.routine === null ? void 0 : this.routines.get(state.routine);
      const block = routine === void 0 ? null : activeBlock(routine, clock, this.tuning);
      const wanted = state.suspension !== null || block === null ? null : goalOf(block);
      const before = state.adopted;
      const delta = adoptedGoalDelta(agent, before, wanted);
      const moved = delta.assert.length > 0 || delta.retract.length > 0;
      const resumed = moved && wanted !== null && state.resuming === true;
      state.adopted = wanted;
      if (wanted !== null) delete state.resuming;
      await this.writeDelta(delta);
      if (moved) {
        this.eventBus?.emit({
          type: "routine_changed",
          actorId: agent,
          routineId: state.routine,
          blockId: block?.id ?? null,
          goal: wanted?.goal ?? null,
          priority: wanted?.priority ?? null,
          destination: block?.place ?? null,
          previousGoal: before?.goal ?? null,
          suspended: state.suspension !== null,
          resumed
        });
      }
      return {
        agent,
        routine: state.routine,
        block: block?.id ?? null,
        goal: wanted?.goal ?? null,
        priority: wanted?.priority ?? null,
        destination: block?.place ?? null,
        changed: moved,
        suspended: state.suspension !== null,
        resumed
      };
    }
    // ── Interruption ──────────────────────────────────────────────────────────
    /**
     * Preempt an NPC's routine — a threat, a conversation, an arrest.
     *
     * The reason is the CALLER's atom and core reads it as a label, never as a
     * decision: what displaced the routine is whatever goal the caller's own system
     * gave the NPC, and this module's job is only to get out of its way. Preempting
     * an already-preempted routine keeps the first reason, because what interrupted
     * it first is the true answer to "what is it doing instead".
     */
    async preempt(agent, reason, block) {
      const key = agentRefKey(agent);
      const state = this.stateOf(key);
      if (state.suspension !== null) return;
      state.suspension = {
        reason,
        block: block ?? null,
        goal: state.adopted?.goal ?? null
      };
      const delta = mergeRoutineDeltas(
        suspensionDelta(key, null, reason),
        adoptedGoalDelta(key, state.adopted, null)
      );
      state.adopted = null;
      await this.writeDelta(delta);
      this.plans?.interrupt(key, "external");
    }
    /**
     * Release a preemption. The NEXT tick adopts whichever block is due THEN —
     * which is what stops a smith resuming the forge at midnight.
     */
    async resume(agent) {
      const key = agentRefKey(agent);
      const state = this.agents.get(key);
      if (!state || state.suspension === null) return;
      const reason = state.suspension.reason;
      state.suspension = null;
      state.resuming = true;
      await this.writeDelta(suspensionDelta(key, reason, null));
    }
    /** What preempted this NPC's routine, or `null`. A debug overlay's view. */
    suspensionOf(agent) {
      const suspension = this.agents.get(agentRefKey(agent))?.suspension ?? null;
      return suspension === null ? null : { ...suspension };
    }
    /** The goal this NPC's routine has adopted, or `null`. */
    adoptedGoal(agent) {
      const adopted = this.agents.get(agentRefKey(agent))?.adopted ?? null;
      return adopted === null ? null : { ...adopted };
    }
    /**
     * Where this NPC's routine wants it to be at that clock, or `null`.
     *
     * A location atom, never a coordinate — `routine_destination/2` in the pack says
     * the same thing to a rule. Turning the gap between here and there into movement
     * is US-2's, and there is nothing on this class that could do it.
     */
    destinationOf(agent, clock) {
      const state = this.agents.get(agentRefKey(agent));
      const routine = state?.routine === null || state === void 0 ? void 0 : this.routines.get(state.routine);
      if (routine === void 0) return null;
      return activeBlock(routine, clock, this.tuning)?.place ?? null;
    }
    // ── The KB ────────────────────────────────────────────────────────────────
    /**
     * Write one delta into the KB, retracting first.
     *
     * Retracting a fact the KB never carried is a no-op rather than a failure: a
     * host with its own persistence, a restored save and an NPC assigned before the
     * engine was wired all produce one, and none of them is an error.
     */
    async writeDelta(delta) {
      if (!this.engine) return false;
      if (delta.retract.length === 0 && delta.assert.length === 0) return false;
      for (const fact of delta.retract) {
        try {
          await this.engine.retractFact(stripPeriod4(fact));
        } catch {
        }
      }
      for (const fact of delta.assert) {
        await this.engine.assertFact(stripPeriod4(fact));
      }
      return true;
    }
    /**
     * Publish every NPC's runtime facts, for a caller that wired the KB after the
     * roster — a save restore, a host that builds its world before its engine.
     */
    async publishAgents(engine = this.engine) {
      if (!engine) return 0;
      let written = 0;
      for (const state of this.roster()) {
        const facts = [];
        if (state.routine !== null) facts.push(followsRoutineFact(state.agent, state.routine));
        if (state.suspension !== null) {
          facts.push(routineSuspendedFact(state.agent, state.suspension.reason));
        }
        for (const fact of facts) {
          await engine.assertFact(stripPeriod4(fact));
          written += 1;
        }
      }
      return written;
    }
    // ── Save/restore ──────────────────────────────────────────────────────────
    /** Every NPC this director knows, in canonical order. */
    roster() {
      return [...this.agents.values()].map((state) => ({ ...state })).sort((a, b) => compareIds(a.agent, b.agent));
    }
    /**
     * The per-playthrough state, and only that: who follows what, what each has
     * adopted, and what preempted them. The routines, their windows and their
     * priorities are authored and are NOT here — a tuning number inside a save file
     * is world-template data leaking into a playthrough
     * (`docs/mechanic-predicates.md` §3).
     */
    serialize() {
      return { agents: this.roster() };
    }
    /**
     * Restore a saved playthrough. Silent — no events and no KB writes, because
     * loading a save is not an NPC changing its mind, and re-publishing is what
     * {@link publishAgents} is for once the engine exists.
     */
    restore(state) {
      this.agents = /* @__PURE__ */ new Map();
      for (const agent of state?.agents ?? []) {
        if (!agent?.agent) continue;
        this.agents.set(agent.agent, {
          agent: agent.agent,
          routine: agent.routine ?? null,
          adopted: agent.adopted ? { ...agent.adopted } : null,
          suspension: agent.suspension ? { ...agent.suspension } : null,
          ...agent.resuming ? { resuming: true } : {}
        });
      }
    }
    stateOf(agent) {
      let state = this.agents.get(agent);
      if (state === void 0) {
        state = { agent, routine: null, adopted: null, suspension: null };
        this.agents.set(agent, state);
      }
      return state;
    }
  };
  function goalOf(block) {
    return { goal: block.goal, priority: block.priority };
  }
  function stripPeriod4(clause) {
    return clause.replace(/\.$/, "");
  }

  // corebridge/js/host-mechanics.js
  var SESSIONS = /* @__PURE__ */ new Map();
  var nextHandle = 1;
  var HOST_INTERFACES = Object.freeze({
    ICombatSystem: "told",
    ICombatStatSink: "both",
    ITrajectoryProbe: "asked",
    IPerceptionProbe: "asked",
    ITraversalProbe: "asked",
    ILocomotionHost: "told",
    ISkillModifierSink: "told",
    ISurvivalSystem: "told",
    IAgentActionHost: "told"
  });
  var MechanicSession = class {
    constructor(module, layer, engine) {
      this.module = module;
      this.layer = layer;
      this.engine = engine;
      this.orders = [];
      this.asked = [];
      this.readings = {};
    }
  };
  function newSession(module, engine) {
    return new MechanicSession(module, void 0, engine);
  }
  function openSession(s, layer) {
    s.layer = layer;
    const handle = nextHandle++;
    s.handle = handle;
    SESSIONS.set(handle, s);
    return handle;
  }
  async function created(s, layer, hydrate) {
    const handle = openSession(s, layer);
    try {
      if (hydrate) await hydrate();
    } catch (err) {
      closeSession(handle);
      throw err;
    }
    return { session: handle, orders: s.orders, asked: s.asked };
  }
  function session(args, module) {
    const handle = args && args.session;
    const found = SESSIONS.get(handle);
    if (!found) {
      throw new Error(`insimulcore: no such mechanic session ${JSON.stringify(handle)}`);
    }
    if (module && found.module !== module) {
      throw new Error(
        `insimulcore: session ${handle} is a ${found.module} session, not ${module}`
      );
    }
    return found;
  }
  function closeSession(handle) {
    const found = SESSIONS.get(handle);
    if (!found) return false;
    if (found.engine) found.engine.destroy();
    SESSIONS.delete(handle);
    return true;
  }
  function openSessions() {
    return Array.from(SESSIONS.entries()).map(([handle, s]) => ({
      session: handle,
      module: s.module
    }));
  }
  async function sessionEngine(args, createPrologEngine2) {
    const kb = args && args.kb;
    if (kb === void 0 || kb === null || kb === false) return void 0;
    const engine = await createPrologEngine2();
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
  function beginCall(s, args) {
    s.orders = [];
    s.asked = [];
    s.readings = args || {};
    return s;
  }
  function endCall(s, report) {
    return { report, orders: s.orders, asked: s.asked };
  }
  function order(s, host, call, payload) {
    s.orders.push({ host, call, ...payload });
  }
  function asked(s, host, call, payload) {
    s.asked.push({ host, call, ...payload });
  }
  function reading(source, key) {
    if (!source || typeof source !== "object") return void 0;
    if (key !== void 0 && Object.prototype.hasOwnProperty.call(source, key)) {
      const keyed = source[key];
      return keyed && typeof keyed === "object" ? keyed : void 0;
    }
    const values = Object.values(source);
    if (values.length > 0 && values.every((v) => v === null || typeof v !== "object")) return source;
    return void 0;
  }
  function combatSystemShim(s) {
    return {
      registerEntity: (entity) => order(s, "ICombatSystem", "registerEntity", { entity }),
      unregisterEntity: (entityId) => order(s, "ICombatSystem", "unregisterEntity", { entityId }),
      applyDamage: (targetId, damage) => order(s, "ICombatSystem", "applyDamage", { entityId: targetId, damage })
    };
  }
  function survivalShim(s) {
    return {
      consumeStamina: (amount) => {
        order(s, "ISurvivalSystem", "consumeStamina", { amount });
        return true;
      },
      recoverStamina: (amount) => order(s, "ISurvivalSystem", "recoverStamina", { amount })
    };
  }
  function combatStatSinkShim(s) {
    return {
      getBaseStats: (entityId) => {
        asked(s, "ICombatStatSink", "getBaseStats", { entityId });
        const stats = reading(s.readings.baseStats, entityId);
        return stats ? { ...stats } : void 0;
      },
      applyStats: (entityId, stats) => order(s, "ICombatStatSink", "applyStats", { entityId, stats })
    };
  }
  function skillModifierSinkShim(s) {
    return {
      applyModifiers: (actorId, modifiers) => order(s, "ISkillModifierSink", "applyModifiers", { actorId, modifiers })
    };
  }
  function trajectoryShim(s) {
    return {
      query: (query) => {
        asked(s, "ITrajectoryProbe", "query", { query });
        return reading(s.readings.trajectory, query.target) ?? { clear: true };
      }
    };
  }
  function perceptionShim(s) {
    return {
      sense: (query) => {
        asked(s, "IPerceptionProbe", "sense", { query });
        return reading(s.readings.perception, `${query.observer}>${query.target}`) ?? null;
      }
    };
  }
  function traversalProbeShim(s) {
    return {
      query: (query) => {
        asked(s, "ITraversalProbe", "query", { query });
        return reading(s.readings.probe, query.link) ?? { passable: true };
      }
    };
  }
  function locomotionShim(s) {
    return {
      travel: (locomotionOrder) => {
        order(s, "ILocomotionHost", "travel", { order: locomotionOrder });
        return arrivalFor(s, locomotionOrder);
      }
    };
  }
  function arrivalFor(s, locomotionOrder) {
    const declared = reading(s.readings.arrival, locomotionOrder.actor) ?? reading(s.readings.arrival);
    if (!declared) return { arrived: true };
    return {
      arrived: declared.arrived !== false,
      ...declared.location ? { location: declared.location } : {},
      ...declared.reason ? { reason: declared.reason } : {}
    };
  }
  function agentActionShim(s) {
    return {
      perform: (actionOrder) => order(s, "IAgentActionHost", "perform", { order: actionOrder })
    };
  }
  function adapterFor(s) {
    return {
      trajectory: trajectoryShim(s),
      perception: perceptionShim(s),
      traversal: traversalProbeShim(s),
      locomotion: locomotionShim(s),
      skillModifiers: skillModifierSinkShim(s),
      combatStats: combatStatSinkShim(s),
      agentActions: agentActionShim(s)
    };
  }

  // @insimul/core/src/traversal/fast-travel.ts
  var DEFAULT_FAST_TRAVEL_TUNING = Object.freeze({
    hoursPerCost: 1,
    minimumHours: 1,
    maxHours: 72,
    stepHours: 6,
    maxSteps: 12,
    action: "fast_travel",
    mode: "fast_travel"
  });
  function whole(value, fallback) {
    const n = Math.floor(Number.isFinite(value) ? value : fallback);
    return n > 0 ? n : 0;
  }
  function fastTravelCeiling(tuning) {
    const byHours = whole(tuning.maxHours, DEFAULT_FAST_TRAVEL_TUNING.maxHours);
    const bySteps = whole(tuning.stepHours, DEFAULT_FAST_TRAVEL_TUNING.stepHours) * whole(tuning.maxSteps, DEFAULT_FAST_TRAVEL_TUNING.maxSteps);
    return Math.min(byHours, bySteps);
  }
  function fastTravelHours(routeCost, tuning) {
    const ceiling = fastTravelCeiling(tuning);
    const minimum = Math.min(whole(tuning.minimumHours, DEFAULT_FAST_TRAVEL_TUNING.minimumHours), ceiling);
    const cost = Number.isFinite(routeCost) && routeCost > 0 ? routeCost : 0;
    const rate = Number.isFinite(tuning.hoursPerCost) ? tuning.hoursPerCost : 1;
    const raw = Math.floor(cost * rate);
    return Math.min(Math.max(raw, minimum), ceiling);
  }
  function fastTravelDraw(identity, index) {
    return roundDeterministic(
      derivedValue(identity.seed, identity.actor, identity.from, identity.to, identity.journey, index)
    );
  }
  function fastTravelSteps(hours, tuning, identity) {
    const chunk = whole(tuning.stepHours, DEFAULT_FAST_TRAVEL_TUNING.stepHours) || 1;
    const limit = whole(tuning.maxSteps, DEFAULT_FAST_TRAVEL_TUNING.maxSteps);
    const steps = [];
    let elapsed = 0;
    while (elapsed < hours && steps.length < limit) {
      const span = Math.min(chunk, hours - elapsed);
      elapsed += span;
      steps.push({
        index: steps.length,
        hours: span,
        elapsed,
        draw: fastTravelDraw(identity, steps.length)
      });
    }
    return steps;
  }
  var FAST_TRAVEL_REFUSALS = Object.freeze([
    /** The traveller is already there. Not a refusal so much as a no-op. */
    "same_place",
    /**
     * No route the actor can currently use gets there. This is `reachable/3`, so a
     * landslide, a mode they do not have and a link that was never authored all land
     * here — you cannot fast travel past something you could not have walked past.
     */
    "unreachable",
    /** `location_discovered/1` — you have not found the place yet. */
    "undiscovered",
    /** A `traversal_requires/3` goal on some leg of the route the rules layer did not satisfy. */
    "requires",
    /** `permissible/3` refused it — a law, a closed border, 123's skill gates. */
    "forbidden"
  ]);
  function planFastTravel(input) {
    const tuning = input.tuning ?? DEFAULT_FAST_TRAVEL_TUNING;
    const ceiling = fastTravelCeiling(tuning);
    const hours = fastTravelHours(input.route.cost, tuning);
    const uncapped = Math.floor(
      Math.max(input.route.cost, 0) * (Number.isFinite(tuning.hoursPerCost) ? tuning.hoursPerCost : 1)
    );
    const requires = [];
    for (const step of input.route.steps) {
      for (const goal of step.requires) if (!requires.includes(goal)) requires.push(goal);
    }
    return {
      actor: input.actor,
      from: input.from,
      to: input.to,
      journey: input.journey,
      route: input.route,
      cost: input.route.cost,
      hours,
      ceiling,
      capped: uncapped > ceiling,
      steps: fastTravelSteps(hours, tuning, input),
      requires
    };
  }

  // @insimul/core/src/traversal/fast-travel-facts.ts
  var FAST_TRAVEL_RESOLUTION_PREDICATES = Object.freeze([
    "location_discovered/1",
    "at_location/2"
  ]);
  function locationDiscoveredFact(location) {
    return `location_discovered(${prologAtom(location)}).`;
  }
  function discoveryDelta(location, known) {
    return known ? { retract: [], assert: [] } : { retract: [], assert: [locationDiscoveredFact(location)] };
  }
  function fastTravelArrivalDelta(actor, from, to) {
    return arrivalDelta(actor, from, to);
  }

  // @insimul/core/src/traversal/vehicles.ts
  var DEFAULT_VEHICLE_ACTIONS = Object.freeze({
    board: "board",
    drive: "drive",
    disembark: "disembark"
  });
  var DEFAULT_VEHICLE_SEATS = 1;
  function vehicleActions(vehicle) {
    return { ...DEFAULT_VEHICLE_ACTIONS, ...vehicle.actions ?? {} };
  }
  function vehicleSeats(vehicle) {
    const seats = Math.floor(vehicle.seats ?? DEFAULT_VEHICLE_SEATS);
    return Number.isFinite(seats) && seats > 0 ? seats : DEFAULT_VEHICLE_SEATS;
  }
  var VEHICLE_VERBS = Object.freeze(["board", "drive", "disembark"]);
  var VEHICLE_REFUSALS = Object.freeze([
    /** No such vehicle. Not a refusal so much as an absence. */
    "unknown",
    /** The actor and the vehicle are not in the same place. */
    "elsewhere",
    /** Every seat is taken. */
    "full",
    /** The actor is not aboard, and the verb needs them to be. */
    "not_aboard",
    /** Somebody else has the reins. */
    "occupied",
    /** Already true — boarding what you are already in, driving what you already drive. */
    "redundant",
    /** `permissible/3` refused it: a law, a norm, an owner who is not you. */
    "forbidden"
  ]);
  function resolveVehicleVerb(input) {
    const { vehicle, state, actor, verb } = input;
    const action = vehicleActions(vehicle)[verb];
    const aboard = state.occupants.includes(actor);
    const refusal2 = refuseVerb(input, aboard);
    return {
      vehicle: vehicle.id,
      actor,
      verb,
      action,
      available: refusal2 === void 0,
      refusal: refusal2,
      grants: verb === "drive" ? vehicle.mode : void 0
    };
  }
  function refuseVerb(input, aboard) {
    const { vehicle, state, actor, at, verb } = input;
    if (verb === "board") {
      if (aboard) return "redundant";
      if (state.location !== at) return "elsewhere";
      if (state.occupants.length >= vehicleSeats(vehicle)) return "full";
      return void 0;
    }
    if (verb === "drive") {
      if (!aboard) return "not_aboard";
      if (state.driver === actor) return "redundant";
      if (state.driver !== void 0) return "occupied";
      return void 0;
    }
    return aboard ? void 0 : "not_aboard";
  }
  function applyVehicleVerb(state, actor, verb, resolution) {
    if (!resolution.available) return null;
    const occupants = new Set(state.occupants);
    let driver = state.driver;
    if (verb === "board") occupants.add(actor);
    if (verb === "drive") driver = actor;
    if (verb === "disembark") {
      occupants.delete(actor);
      if (driver === actor) driver = void 0;
    }
    return {
      ...state,
      occupants: [...occupants].sort(compareIds),
      driver
    };
  }
  function isAnothersVehicle(state, actor) {
    return state.owner !== void 0 && state.owner !== actor;
  }

  // @insimul/core/src/traversal/vehicle-facts.ts
  var VEHICLE_RESOLUTION_PREDICATES = Object.freeze([
    "vehicle_owner/2",
    "vehicle_occupant/2",
    "vehicle_driver/2",
    "at_location/2"
  ]);
  var VEHICLE_AUTHORED_PREDICATES = Object.freeze(["vehicle_mode/2"]);
  function vehicleModeFact(vehicle) {
    return `vehicle_mode(${prologAtom(vehicle.id)}, ${prologAtom(vehicle.mode)}).`;
  }
  function vehicleOwnerFact(vehicleId, owner) {
    return `vehicle_owner(${prologAtom(vehicleId)}, ${prologAtom(owner)}).`;
  }
  function vehicleOccupantFact(vehicleId, actor) {
    return `vehicle_occupant(${prologAtom(vehicleId)}, ${prologAtom(actor)}).`;
  }
  function vehicleDriverFact(vehicleId, actor) {
    return `vehicle_driver(${prologAtom(vehicleId)}, ${prologAtom(actor)}).`;
  }
  function vehicleStateFacts(state) {
    const facts = [atLocationFact(state.id, state.location)];
    if (state.owner !== void 0) facts.push(vehicleOwnerFact(state.id, state.owner));
    for (const occupant of state.occupants) facts.push(vehicleOccupantFact(state.id, occupant));
    if (state.driver !== void 0) facts.push(vehicleDriverFact(state.id, state.driver));
    return facts;
  }
  function vehicleStateDelta(before, after) {
    const delta = emptyTraversalDelta();
    const had = new Set(before?.occupants ?? []);
    const has2 = new Set(after.occupants);
    if (before?.location !== after.location) {
      if (before !== void 0) delta.retract.push(atLocationFact(after.id, before.location));
      delta.assert.push(atLocationFact(after.id, after.location));
    }
    if (before?.owner !== after.owner) {
      if (before?.owner !== void 0) delta.retract.push(vehicleOwnerFact(after.id, before.owner));
      if (after.owner !== void 0) delta.assert.push(vehicleOwnerFact(after.id, after.owner));
    }
    for (const gone of before?.occupants ?? []) {
      if (!has2.has(gone)) delta.retract.push(vehicleOccupantFact(after.id, gone));
    }
    for (const joined of after.occupants) {
      if (!had.has(joined)) delta.assert.push(vehicleOccupantFact(after.id, joined));
    }
    if (before?.driver !== after.driver) {
      if (before?.driver !== void 0) delta.retract.push(vehicleDriverFact(after.id, before.driver));
      if (after.driver !== void 0) delta.assert.push(vehicleDriverFact(after.id, after.driver));
    }
    return delta;
  }

  // @insimul/core/src/items/items.ts
  var DEFAULT_ITEM_TUNING = Object.freeze({
    defaultSlotCapacity: 1,
    carryCapacity: 100,
    equipAction: "equip",
    unequipAction: "unequip",
    moveAction: "move_item"
  });
  function findSlot(slots, slotId) {
    return slots.find((slot) => slot.id === slotId);
  }
  var ITEM_PLACE_KINDS = Object.freeze([
    /** `has_item(Actor, ItemId, Qty)` — carried. */
    "inventory",
    /** `container_contains(ContainerId, ItemId, Qty)` — in a chest, a crate, a shelf. */
    "container",
    /** `has_equipped(Actor, Slot, ItemId)` — worn or wielded. */
    "equipped",
    /** `item_at(ItemId, LocationId, Qty)` — lying in the world, owned by nobody. */
    "world"
  ]);
  function placeKey(place) {
    return place.kind === "equipped" ? `equipped:${place.holder}:${place.slot ?? ""}` : `${place.kind}:${place.holder}`;
  }
  function sortStacks(stacks) {
    return [...stacks].sort(
      (a, b) => compareIds(placeKey(a.place), placeKey(b.place)) || compareIds(a.item, b.item)
    );
  }
  function carriedWeight(stacks, definitions) {
    let total = 0;
    for (const stack of stacks) {
      const unit = definitions.get(stack.item)?.weight ?? 0;
      total += unit * stack.quantity;
    }
    return total;
  }
  function encumbered(weight, capacity) {
    return weight > capacity;
  }
  function armorValue(worn, definitions) {
    let total = 0;
    for (const item of worn) total += definitions.get(item)?.armor ?? 0;
    return total;
  }
  var EQUIP_REFUSALS = Object.freeze([
    /** The catalogue declares no such item. Not a refusal so much as an absence. */
    "unknown",
    /** `has_item/3` does not hold — you cannot put on what you are not carrying. */
    "not_held",
    /** The item authored no `equip_slot/2`. It is not equipment. */
    "no_slot",
    /** It names a slot the world does not declare — authored content that is wrong. */
    "unknown_slot",
    /** `has_equipped/3` already holds for this item. */
    "already_equipped",
    /** `slot_free/2` fails — "two rings, not five". */
    "slot_full",
    /** An `item_requires/3` skill is missing or too low. */
    "requires",
    /** `permissible/3` refused it — a norm, a law, a cursed blade. */
    "forbidden"
  ]);
  function resolveEquip(input) {
    const tuning = input.tuning ?? DEFAULT_ITEM_TUNING;
    const item = input.item;
    const base = {
      actor: input.actor,
      item: item?.id ?? input.itemId ?? "",
      slot: item?.equipSlot ?? "",
      occupied: input.occupied,
      capacity: input.slot?.capacity ?? 0,
      unmet: [],
      action: tuning.equipAction
    };
    if (!item) return { ...base, available: false, refusal: "unknown" };
    if (!input.held && !input.equipped) return { ...base, available: false, refusal: "not_held" };
    if (!item.equipSlot) return { ...base, available: false, refusal: "no_slot" };
    if (!input.slot) return { ...base, available: false, refusal: "unknown_slot" };
    if (input.equipped) return { ...base, available: false, refusal: "already_equipped" };
    if (input.occupied >= input.slot.capacity) {
      return { ...base, available: false, refusal: "slot_full" };
    }
    const unmet = unmetRequirements(item, input.levels);
    if (unmet.length > 0) return { ...base, available: false, refusal: "requires", unmet };
    return { ...base, available: true };
  }
  function unmetRequirements(item, levels) {
    return item.requires.filter((requirement) => (levels[requirement.skill] ?? 0) < requirement.level).sort((a, b) => compareIds(a.skill, b.skill));
  }
  var MOVE_REFUSALS = Object.freeze([
    /** The catalogue declares no such item. */
    "unknown",
    /** A quantity of zero or less, or a fractional one. */
    "quantity",
    /** The source and the destination are the same place. */
    "same_place",
    /**
     * Either end is a slot. Equipping and unequipping are actions of their own,
     * gated on their own atoms, so a generic move will not do either silently —
     * a silent unequip is how an item ends up somewhere no rule agreed to.
     */
    "equipped",
    /** Fewer than that many are there — `has_item/3` or `container_contains/3` disagrees. */
    "absent",
    /** `container_locked/1` on either end. */
    "locked",
    /** The destination has no room for it. */
    "full",
    /** `permissible/3` refused it — this is where a theft is refused. */
    "forbidden"
  ]);
  function drawItems(input) {
    const size = Math.floor(input.size);
    if (!Number.isFinite(size) || size <= 0) return [];
    const depth = Math.max(1, Math.floor(input.depth));
    const cycle = Math.floor(input.cycle ?? 0);
    return input.candidates.map((item) => ({
      item: item.id,
      // Weighted by `lootWeight`, so an authored rarity means the same thing on
      // a shelf as it does in a chest. A `lootWeight` of 0 can still be drawn —
      // a shop is not a loot table — but sorts last.
      score: derivedStream(input.seed, input.subject, cycle, item.id)() * drawWeightOf(item)
    })).sort((a, b) => b.score - a.score || compareIds(a.item, b.item)).slice(0, size).map((entry) => ({
      item: entry.item,
      quantity: 1 + Math.floor(derivedStream(input.seed, input.subject, cycle, entry.item, "qty")() * depth)
    })).sort((a, b) => compareIds(a.item, b.item));
  }
  function drawWeightOf(item) {
    const weight = item.lootWeight;
    return Number.isFinite(weight) && weight > 0 ? weight : 1;
  }

  // @insimul/core/src/items/item-effects.ts
  function equipmentModifiers(items) {
    const totals = /* @__PURE__ */ new Map();
    for (const item of items) {
      for (const [param, amount] of Object.entries(item.effects)) {
        if (typeof amount !== "number" || !Number.isFinite(amount)) continue;
        totals.set(param, (totals.get(param) ?? 0) + amount);
      }
    }
    return new Map([...totals].sort(([a], [b]) => compareIds(a, b)));
  }
  function equipmentModifierTotals(items) {
    return Object.fromEntries(equipmentModifiers(items));
  }

  // @insimul/core/src/items/item-facts.ts
  var ITEM_RESOLUTION_PREDICATES = Object.freeze([
    "has_item/3",
    "container_contains/3",
    "has_equipped/3",
    "item_at/3",
    "carry_capacity/2",
    "item_condition/2"
  ]);
  var ITEM_AUTHORED_PREDICATES = Object.freeze([
    "item/1",
    "item_name/2",
    "item_type/2",
    "item_weight/2",
    "item_value/2",
    "item_sell_value/2",
    "item_tradeable/1",
    "item_stackable/1",
    "item_max_stack/2",
    "item_tag/2",
    "item_armor/2",
    "equip_slot/2",
    "equip_slot_capacity/2",
    "item_requires/3"
  ]);
  function hasItemFact(actor, item, quantity) {
    return `has_item(${prologAtom(actor)}, ${prologAtom(item)}, ${quantity}).`;
  }
  function containerContainsFact(container, item, quantity) {
    return `container_contains(${prologAtom(container)}, ${prologAtom(item)}, ${quantity}).`;
  }
  function hasEquippedFact(actor, slot, item) {
    return `has_equipped(${prologAtom(actor)}, ${prologAtom(slot)}, ${prologAtom(item)}).`;
  }
  function itemAtFact(item, location, quantity) {
    return `item_at(${prologAtom(item)}, ${prologAtom(location)}, ${quantity}).`;
  }
  function placeFacts(place, item, quantity) {
    switch (place.kind) {
      case "inventory":
        return [hasItemFact(place.holder, item, quantity)];
      case "container":
        return [containerContainsFact(place.holder, item, quantity)];
      case "equipped":
        return [
          hasEquippedFact(place.holder, place.slot ?? "", item),
          hasItemFact(place.holder, item, quantity)
        ];
      case "world":
        return [itemAtFact(item, place.holder, quantity)];
    }
  }

  // @insimul/core/src/items/economy.ts
  var DEFAULT_ECONOMY_TUNING = Object.freeze({
    markupPercent: 0,
    sellMarginPercent: 100,
    scarcityPercent: 0,
    stockNormal: 0,
    standingPercent: 0,
    standingScale: 100,
    proprietorPercent: 0,
    minimumPrice: 0,
    buyAction: "buy_item",
    sellAction: "sell_item",
    stockSize: 0,
    stockDepth: 1
  });
  var PRICE_FACTORS = Object.freeze([
    /** `vendor_markup/2` — the business's margin. Absent for a sale, which pays a margin instead. */
    "markup",
    /** How far below `item_stock_normal/2` the shelf has fallen. */
    "scarcity",
    /** `reputation/3` with the vendor's faction, scaled by `standingScale`. */
    "standing",
    /** `business_owner/2` names this actor — they are buying from their own shop. */
    "proprietor"
  ]);
  function resolvePrice(input) {
    const tuning = input.tuning ?? DEFAULT_ECONOMY_TUNING;
    const item = input.item;
    const quantity = Math.max(0, Math.floor(input.quantity ?? 1));
    const buying = input.direction === "buy";
    const market = input.market;
    const base = item ? buying ? item.value : sellBase(item, tuning) : 0;
    const adjustments = [];
    if (item && market) {
      if (buying && market.vendor.markupPercent !== 0) {
        adjustments.push(
          adjustment("markup", market.vendor.markupPercent, base, market.vendor.business)
        );
      }
      const scarcity = scarcityPercent(market, tuning);
      if (scarcity !== 0) adjustments.push(adjustment("scarcity", scarcity, base, market.vendor.id));
      if (market.standing !== void 0 && tuning.standingPercent !== 0) {
        const share = clampUnit(market.standing / tuning.standingScale);
        const percent = round(tuning.standingPercent * share) * (buying ? -1 : 1);
        if (percent !== 0) adjustments.push(adjustment("standing", percent, base, market.faction));
      }
      if (market.owner !== void 0 && market.owner === input.actor && tuning.proprietorPercent !== 0) {
        const percent = tuning.proprietorPercent * (buying ? -1 : 1);
        adjustments.push(adjustment("proprietor", percent, base, market.owner));
      }
    }
    const raw = base + adjustments.reduce((sum, term4) => sum + term4.amount, 0);
    const unit = Math.max(tuning.minimumPrice, raw);
    return {
      item: item?.id ?? input.itemId ?? "",
      direction: input.direction,
      base,
      adjustments,
      unit,
      quantity,
      total: unit * quantity,
      fallback: market === void 0
    };
  }
  function sellBase(item, tuning) {
    return round(item.sellValue * tuning.sellMarginPercent / 100);
  }
  function scarcityPercent(market, tuning) {
    if (tuning.scarcityPercent === 0) return 0;
    const normal = market.stockNormal ?? tuning.stockNormal;
    if (!Number.isFinite(normal) || normal <= 0) return 0;
    const stock = Math.max(0, market.stock ?? 0);
    if (stock >= normal) return 0;
    return round(tuning.scarcityPercent * (normal - stock) / normal);
  }
  function adjustment(factor, percent, base, subject) {
    return { factor, percent, amount: round(base * percent / 100), subject };
  }
  function round(value) {
    return value < 0 ? -Math.round(-value) : Math.round(value);
  }
  function clampUnit(value) {
    if (!Number.isFinite(value)) return 0;
    return value < 0 ? 0 : value > 1 ? 1 : value;
  }
  var TRANSACTION_REFUSALS = Object.freeze([
    /** The catalogue declares no such item. */
    "unknown",
    /** A quantity of zero or less, or a fractional one. */
    "quantity",
    /** `item_tradeable/1` does not hold — a quest letter is not merchandise. */
    "not_tradeable",
    /** Fewer on the shelf (a purchase) or in the pack (a sale) than were asked for. */
    "out_of_stock",
    /** `gold/2` says the buyer cannot cover it. */
    "cannot_afford",
    /** The vendor's till cannot cover what they offered — a sale, refused. */
    "till_empty",
    /** `permissible/3` refused it. A theft is what happens next anyway. */
    "forbidden"
  ]);
  function resolveTransaction(input) {
    const tuning = input.tuning ?? DEFAULT_ECONOMY_TUNING;
    const item = input.item;
    const buying = input.direction === "buy";
    const price = resolvePrice({
      actor: input.actor,
      item,
      itemId: input.itemId,
      direction: input.direction,
      quantity: input.quantity,
      market: input.market,
      tuning
    });
    const base = {
      actor: input.actor,
      vendor: input.market?.vendor.id ?? input.vendorId ?? "",
      item: item?.id ?? input.itemId ?? "",
      direction: input.direction,
      quantity: input.quantity,
      price,
      action: buying ? tuning.buyAction : tuning.sellAction
    };
    if (!item) return { ...base, available: false, refusal: "unknown" };
    if (!Number.isInteger(input.quantity) || input.quantity <= 0) {
      return { ...base, available: false, refusal: "quantity" };
    }
    if (!item.tradeable) return { ...base, available: false, refusal: "not_tradeable" };
    if (input.supply < input.quantity) {
      return { ...base, available: false, refusal: "out_of_stock" };
    }
    if (buying && input.actorGold !== void 0 && input.actorGold < price.total) {
      return { ...base, available: false, refusal: "cannot_afford" };
    }
    if (!buying && input.vendorGold !== void 0 && input.vendorGold < price.total) {
      return { ...base, available: false, refusal: "till_empty" };
    }
    return { ...base, available: true };
  }

  // @insimul/core/src/items/placement.ts
  var DEFAULT_PLACEMENT_TUNING = Object.freeze({
    lootDraws: 3,
    lootDepth: 2
  });
  function placementTuningFromIR(ir) {
    const d = DEFAULT_PLACEMENT_TUNING;
    if (!ir) return { ...d };
    const num2 = (value, fallback) => typeof value === "number" && Number.isFinite(value) && value > 0 ? Math.floor(value) : fallback;
    return {
      lootDraws: num2(ir.lootDraws, d.lootDraws),
      lootDepth: num2(ir.lootDepth, d.lootDepth)
    };
  }
  function itemPlacementsFromIR(ir) {
    return (ir?.placements ?? []).filter((row) => typeof row?.id === "string" && row.id !== "").map((row) => placementFromIR(row)).sort((a, b) => compareIds(a.id, b.id));
  }
  function placementFromIR(row) {
    const quantity = Math.floor(row.quantity ?? 1);
    const placement = {
      id: row.id,
      item: row.item ?? "",
      quantity: Number.isFinite(quantity) && quantity > 0 ? quantity : 1,
      location: row.locationId ?? "",
      container: row.containerId,
      declares: row.container ? containerFromIR(row.container) : void 0,
      rotation: typeof row.rotation === "number" && Number.isFinite(row.rotation) ? row.rotation : void 0,
      archetype: row.archetype
    };
    if (row.position) {
      placement.position = {
        x: finite(row.position.x, 0),
        z: finite(row.position.z, 0),
        y: typeof row.position.y === "number" && Number.isFinite(row.position.y) ? row.position.y : void 0
      };
    }
    return placement;
  }
  function containerFromIR(container) {
    const draws = Math.floor(container.draws ?? 0);
    return {
      type: container.type ?? "container",
      locked: container.locked === true,
      keyItem: container.keyItem,
      lootTable: container.lootTable,
      draws: Number.isFinite(draws) && draws > 0 ? draws : void 0
    };
  }
  function finite(value, fallback) {
    return typeof value === "number" && Number.isFinite(value) ? value : fallback;
  }
  function placeOf(placement) {
    return placement.container === void 0 ? { kind: "world", holder: placement.location } : { kind: "container", holder: placement.container };
  }
  function isContainerPlacement(placement) {
    return placement.declares !== void 0;
  }
  function lootTablesFromIR(tables) {
    const out = /* @__PURE__ */ new Map();
    for (const table of tables ?? []) {
      if (!table || typeof table.enemyType !== "string" || table.enemyType === "") continue;
      out.set(table.enemyType, {
        id: table.enemyType,
        entries: (table.entries ?? []).filter((entry) => typeof entry?.itemId === "string" && entry.itemId !== "").map((entry) => ({
          item: entry.itemId,
          chance: normalizedChance(entry.dropChance),
          minQuantity: Math.max(1, Math.floor(finite(entry.minQuantity, 1))),
          maxQuantity: Math.max(1, Math.floor(finite(entry.maxQuantity, 1)))
        })).sort((a, b) => compareIds(a.item, b.item)),
        goldMin: Math.max(0, Math.floor(finite(table.goldMin, 0))),
        goldMax: Math.max(0, Math.floor(finite(table.goldMax, 0)))
      });
    }
    return out;
  }
  function normalizedChance(value) {
    const chance = finite(value, 0);
    if (chance <= 0) return 0;
    if (chance <= 1) return chance;
    return Math.min(1, chance / 100);
  }
  function generateLoot(input) {
    const tuning = input.tuning ?? DEFAULT_PLACEMENT_TUNING;
    const cycle = Math.floor(input.cycle ?? 0);
    if (input.table) {
      const entries = [];
      for (const entry of input.table.entries) {
        const roll2 = derivedStream(input.seed, input.container, cycle, entry.item)();
        if (roll2 >= entry.chance) continue;
        const span = Math.max(0, entry.maxQuantity - entry.minQuantity);
        const extra = Math.floor(
          derivedStream(input.seed, input.container, cycle, entry.item, "qty")() * (span + 1)
        );
        entries.push({ item: entry.item, quantity: entry.minQuantity + Math.min(span, extra) });
      }
      const goldSpan = Math.max(0, input.table.goldMax - input.table.goldMin);
      const gold = input.table.goldMin + Math.min(
        goldSpan,
        Math.floor(derivedStream(input.seed, input.container, cycle, "gold")() * (goldSpan + 1))
      );
      return { entries: entries.sort((a, b) => compareIds(a.item, b.item)), gold };
    }
    return {
      entries: drawItems({
        seed: input.seed,
        subject: input.container,
        cycle,
        candidates: input.catalogue ?? [],
        size: input.draws ?? tuning.lootDraws,
        depth: tuning.lootDepth
      }),
      gold: 0
    };
  }

  // @insimul/core/src/routines/movement.ts
  var DEFAULT_MOVEMENT_TUNING = Object.freeze({
    // Above the 50 an ordinary routine block is worth: a shift about to start, a
    // quest step, an appointment.
    hurriedAt: 60,
    // Flight, alarm, a threat. Deliberately high — an NPC that runs everywhere
    // reads as broken, and `urgent` is the one rung a host may actually run on.
    urgentAt: 85,
    // A goal worth nothing much. Zero rather than negative so a world that authors
    // `priority: 0` gets the stroll it asked for.
    idleAt: 0,
    attemptsBeforeReplan: 2
  });
  function urgencyFor(priority, tuning = DEFAULT_MOVEMENT_TUNING) {
    if (typeof priority !== "number" || !Number.isFinite(priority)) return "ordinary";
    const value = Math.trunc(priority);
    if (value >= tuning.urgentAt) return "urgent";
    if (value >= tuning.hurriedAt) return "hurried";
    if (value <= tuning.idleAt) return "idle";
    return "ordinary";
  }
  function movementIntent(input) {
    if (input.suspended === true) return null;
    if (!input.destination || !input.from) return null;
    const tuning = input.tuning ?? DEFAULT_MOVEMENT_TUNING;
    return {
      actor: input.actor,
      from: input.from,
      destination: input.destination,
      urgency: urgencyFor(input.priority, tuning),
      stance: input.stance ?? "standing"
    };
  }
  function inPlace(intent) {
    return intent !== null && intent.from === intent.destination;
  }
  var NAVIGATION_FAILURES = Object.freeze([
    "unplaced",
    "no_route",
    "refused",
    "not_arrived"
  ]);
  function shouldReplan(failures, tuning = DEFAULT_MOVEMENT_TUNING) {
    return failures >= Math.max(1, Math.trunc(tuning.attemptsBeforeReplan));
  }

  // @insimul/core/src/routines/animation.ts
  var VOCABULARY = new Set(ANIMATION_INTENTS);
  function isAnimationIntent(value) {
    return typeof value === "string" && VOCABULARY.has(value);
  }
  var NO_AUTHORED_ANIMATIONS = /* @__PURE__ */ new Map();
  function animationIntentFor(action, authored = NO_AUTHORED_ANIMATIONS) {
    return authored.get(action) ?? getActionAnimation(action) ?? DEFAULT_ANIMATION_INTENT;
  }

  // @insimul/core/src/conformance/__tests__/headless-routine-host.ts
  var RecordingKb = class {
    constructor() {
      /** Every write, in order, as `+clause` / `-clause`. The whole record. */
      __publicField(this, "log", []);
      __publicField(this, "held", /* @__PURE__ */ new Set());
    }
    async assertFact(fact) {
      this.log.push(`+${fact}`);
      this.held.add(fact);
      return true;
    }
    async retractFact(fact) {
      this.log.push(`-${fact}`);
      return this.held.delete(fact);
    }
    /** Everything the KB now holds, canonically sorted. */
    facts() {
      return [...this.held].sort();
    }
    /** The writes since the mark, as `{ retract, assert }` — one step's delta. */
    since(mark) {
      const written = this.log.slice(mark);
      return {
        retract: written.filter((entry) => entry.startsWith("-")).map((entry) => entry.slice(1)),
        assert: written.filter((entry) => entry.startsWith("+")).map((entry) => entry.slice(1))
      };
    }
    /** How many writes have happened. The mark {@link since} counts from. */
    mark() {
      return this.log.length;
    }
    /** Satisfies the one parameter `RoutineDirector` takes. See {@link RoutineKbWriter}. */
    asEngine() {
      return this;
    }
  };
  var RecordingPlans = class {
    constructor() {
      __publicField(this, "interrupts", []);
    }
    interrupt(agent, reason) {
      this.interrupts.push({ agent, reason: reason ?? null });
    }
  };

  // corebridge/js/host-corpus.js
  function combatFactsFor(c, resolved) {
    if (resolved.damage <= 0) return resolutionFacts(resolved);
    const threat = threatAfterDamage(resolved.damage, resolved.targetMaxHealth, c.threatBefore ?? 0);
    return resolutionFacts(resolved, { threat, priorThreat: c.threatBefore });
  }
  function runCombatResolution(c) {
    if (c.kind === "defense") {
      const resolved2 = resolveDefense(c.input);
      return { resolution: resolved2, facts: defenseFacts(resolved2) };
    }
    const resolved = resolveAttack(c.input);
    const out = { resolution: resolved, facts: combatFactsFor(c, resolved) };
    if (c.expected && c.expected.threat !== void 0) {
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
      defensive: table.defensiveActions().map((row) => row.id)
    };
  }
  var ACT_CONTEXT = {
    event: "evt:act:1",
    actor: { kind: "ent", namespace: "insimul:world:alderforest", localId: "npc-thief" },
    object: { kind: "ent", namespace: "insimul:world:alderforest", localId: "npc-guard" },
    coarseActor: { kind: "ent", namespace: "insimul:world:alderforest", localId: "someone" }
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
      perceivedFacts: result.perception.perceivedFacts
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
      percepts: rows.map((row) => ({ id: row.id, percept: stealthActFor(row, ACT_CONTEXT) ?? null }))
    };
  }
  function runTraversalAffordances(c) {
    const input = c.input;
    const resolved = resolveAffordances(input);
    return {
      affordances: resolved,
      best: c.best === null ? null : bestAffordance(resolved, c.best) ?? null,
      route: c.route === null ? null : findRoute({ ...input, ...c.route }) ?? null,
      graphFacts: traversalGraphFacts(input.links, input.tuning)
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
      tuning: input.graphTuning
    });
    const plan = route === void 0 ? null : planFastTravel({
      seed: input.seed,
      actor: input.actor,
      from: input.from,
      to: input.to,
      journey: input.journey,
      route,
      tuning: input.tuning
    });
    return {
      route: route ?? null,
      plan,
      arrival: plan === null ? null : fastTravelArrivalDelta(input.actor, input.from, input.to),
      discovery: plan === null ? null : discoveryDelta(input.to, false),
      discoveryWhenAlreadyKnown: plan === null ? null : discoveryDelta(input.to, true)
    };
  }
  function runTraversalVehicles(c) {
    const resolution = resolveVehicleVerb({
      vehicle: c.vehicle,
      state: c.state,
      actor: c.actor,
      at: c.at,
      verb: c.verb
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
      anothers: isAnothersVehicle(c.state, c.actor)
    };
  }
  function runSkillAdvance(c) {
    const input = c.input;
    const skill = input.skill ?? void 0;
    const max = maxLevelOf(skill, input.tuning);
    const curve = [];
    for (let level = 0; level <= max + 1; level += 1) curve.push(xpForLevel(skill, level, input.tuning));
    return { resolution: resolveAdvance({ ...input, skill }), curve, maxLevel: max };
  }
  function runSkillUnlock(c) {
    const input = c.input;
    const node = input.node ?? void 0;
    return {
      resolution: resolveUnlock({ ...input, node }),
      requirements: node ? [...nodeRequirements(node)] : [],
      cost: node ? nodeCost(node, input.tuning) : 0
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
      modifierOf: modifierOf(input.effects, input.parameter)
    };
  }
  function runSkillTrees(c) {
    const input = c.input;
    const depths = {};
    for (const tree of input.trees) for (const n of tree.nodes) depths[n.id] = nodeDepth(tree, n.id);
    return {
      view: buildSkillView(input),
      funded: treesFundedBy(input.trees, input.trees[0]?.skill ?? ""),
      depths
    };
  }
  function wornFrom(input) {
    const declared = [...input.slots].sort((a, b) => a.order - b.order || a.id.localeCompare(b.id)).map((slot) => slot.id);
    const order2 = (slot) => {
      const index = declared.indexOf(slot);
      return index === -1 ? declared.length : index;
    };
    return input.stacks.filter((stack) => stack.place.kind === "equipped" && stack.place.holder === input.actor).slice().sort(
      (a, b) => order2(a.place.slot ?? "") - order2(b.place.slot ?? "") || (a.place.slot ?? "").localeCompare(b.place.slot ?? "") || a.item.localeCompare(b.item)
    ).map((stack) => stack.item);
  }
  function runItemsEquipping(c) {
    const input = c.input;
    const item = input.item ?? void 0;
    const definitions = new Map(input.catalogue.map((row) => [row.id, row]));
    const worn = wornFrom(input);
    const mine = input.stacks.filter(
      (stack) => (stack.place.kind === "inventory" || stack.place.kind === "equipped") && stack.place.holder === input.actor
    );
    const weight = carriedWeight(mine, definitions);
    return {
      resolution: resolveEquip({
        actor: input.actor,
        item,
        itemId: input.itemId,
        slot: item?.equipSlot ? findSlot(input.slots, item.equipSlot) : void 0,
        occupied: input.occupied,
        held: input.held,
        equipped: input.equipped,
        levels: input.levels,
        tuning: input.tuning
      }),
      unmet: item ? unmetRequirements(item, input.levels) : [],
      facts: sortStacks(input.stacks).flatMap(
        (stack) => placeFacts(stack.place, stack.item, stack.quantity)
      ),
      worn,
      weight,
      encumbered: encumbered(weight, input.tuning.carryCapacity),
      armor: armorValue(worn, definitions),
      modifiers: equipmentModifierTotals(
        worn.map((id) => definitions.get(id)).filter((row) => !!row)
      )
    };
  }
  function runItemsPricing(c) {
    const input = c.input;
    return {
      price: resolvePrice({
        actor: input.actor,
        item: input.item ?? void 0,
        itemId: input.itemId,
        direction: input.direction,
        quantity: input.quantity,
        market: input.market ?? void 0,
        tuning: input.tuning
      })
    };
  }
  function runItemsTransactions(c) {
    const input = c.input;
    return {
      resolution: resolveTransaction({
        actor: input.actor,
        item: input.item ?? void 0,
        itemId: input.itemId,
        direction: input.direction,
        quantity: input.quantity,
        market: input.market ?? void 0,
        vendorId: input.vendorId,
        supply: input.supply,
        actorGold: input.actorGold,
        vendorGold: input.vendorGold,
        tuning: input.tuning
      })
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
        table: named ? tables.get(named) : void 0,
        catalogue: input.catalogue,
        draws: row.declares?.draws,
        tuning
      });
    }
    return {
      tuning,
      placements,
      places,
      containers: placements.filter(isContainerPlacement).map((row) => row.id),
      loot
    };
  }
  function runRoutineGoals(c) {
    const { tuning, clock, agent } = c.input;
    const authored = c.input.routines.routines?.find((r) => r.id === c.input.routine);
    if (authored === void 0) throw new Error(`${c.name} names a routine it did not author`);
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
        active === null ? null : { goal: active.goal, priority: active.priority }
      )
    };
  }
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
        case "assign":
          await director.assign(step.agent, step.routine);
          break;
        case "tick":
          outcomes = [...(await director.tick(step.clock, input.roster)).outcomes];
          break;
        case "preempt":
          await director.preempt(step.agent, step.reason, step.block);
          break;
        case "resume":
          await director.resume(step.agent);
          break;
        case "forget":
          await director.forget(step.agent);
          break;
      }
      steps.push({
        ...outcomes === void 0 ? {} : { outcomes },
        delta: kb.since(mark),
        interrupts: plans.interrupts.slice(before)
      });
    }
    return { steps, facts: kb.facts(), state: director.serialize() };
  }
  function runRoutineIntents(c) {
    const input = c.input;
    const authored = new Map(
      Object.entries(input.authored).flatMap(
        ([action, intent2]) => isAnimationIntent(intent2) ? [[action, intent2]] : []
      )
    );
    const intent = movementIntent({
      actor: input.actor,
      from: input.from,
      destination: input.destination,
      priority: input.priority,
      stance: input.stance,
      suspended: input.suspended,
      tuning: input.tuning
    });
    return {
      intent,
      inPlace: inPlace(intent),
      urgency: urgencyFor(input.priority, input.tuning),
      replan: shouldReplan(input.failures, input.tuning),
      animation: animationIntentFor(input.action, authored)
    };
  }
  var CORPUS_AREAS = {
    "combat-resolution": runCombatResolution,
    "combat-action-table": runCombatActionTable,
    "stealth-detection": runStealthDetection,
    "stealth-actions": runStealthActions,
    "traversal-affordances": runTraversalAffordances,
    "traversal-fast-travel": runTraversalFastTravel,
    "traversal-vehicles": runTraversalVehicles,
    "skills-advancement": runSkillAdvance,
    "skills-unlocks": runSkillUnlock,
    "skills-effects": runSkillEffects,
    "skills-trees": runSkillTrees,
    "items-equipping": runItemsEquipping,
    "items-pricing": runItemsPricing,
    "items-transactions": runItemsTransactions,
    "items-placement": runItemsPlacement,
    "routine-goals": runRoutineGoals,
    "routine-intents": runRoutineIntents,
    "routine-interruption": runRoutineInterruption
  };
  var CORPUS_AREAS_BY_MODULE = {
    combat: ["combat-resolution", "combat-action-table"],
    perception: ["stealth-detection", "stealth-actions"],
    traversal: ["traversal-affordances", "traversal-fast-travel", "traversal-vehicles"],
    skill: ["skills-advancement", "skills-unlocks", "skills-effects", "skills-trees"],
    equipment: ["items-equipping", "items-pricing", "items-transactions", "items-placement"],
    routine: ["routine-goals", "routine-intents", "routine-interruption"],
    // `stamina` has no decision corpus of its own: StaminaPool's arithmetic is
    // pinned inside conformance/combat/resolution.json (every attack case
    // carries the meter and pins `attackerStaminaAfter`) and its vocabulary in
    // conformance/prolog/mechanic-stamina.json. Recorded as an empty list rather
    // than omitted, so "no corpus" is a statement and not an oversight.
    stamina: []
  };
  async function runCorpusCase(area, testCase) {
    const runner = CORPUS_AREAS[area];
    if (!runner) {
      throw new Error(
        `insimulcore: no conformance runner for area "${area}" \u2014 add one in gdextension/corebridge/js/host-corpus.js, or the vendored corpus is a checked-in file nothing executes.`
      );
    }
    return await runner(testCase);
  }

  // corebridge/js/entry.js
  var MECHANIC_MODULES = {
    combat: {
      layers: ["CombatResolver"],
      hostInterfaces: ["ICombatSystem", "ITrajectoryProbe"],
      rows: ["combat.create", "combat.attack", "combat.defend", "combat.endDefense", "combat.state"]
    },
    stamina: {
      layers: ["StaminaPool"],
      hostInterfaces: ["ISurvivalSystem"],
      rows: ["stamina.create", "stamina.spend", "stamina.rest", "stamina.state"]
    },
    perception: {
      layers: ["DetectionTracker"],
      hostInterfaces: ["IPerceptionProbe"],
      rows: ["perception.create", "perception.observe", "perception.state"]
    },
    traversal: {
      layers: ["TraversalPlanner"],
      hostInterfaces: ["ITraversalProbe", "ILocomotionHost"],
      rows: ["traversal.create", "traversal.traverse", "traversal.affordances", "traversal.state"]
    },
    skill: {
      layers: ["SkillProgression"],
      hostInterfaces: ["ISkillModifierSink"],
      rows: ["skill.create", "skill.award", "skill.unlock", "skill.state"]
    },
    equipment: {
      layers: ["EquipmentManager"],
      hostInterfaces: ["ICombatStatSink"],
      rows: ["equipment.create", "equipment.equip", "equipment.unequip", "equipment.state"]
    },
    routine: {
      layers: ["RoutineDirector"],
      hostInterfaces: ["ILocomotionHost"],
      rows: ["routine.create", "routine.tick", "routine.state"]
    }
  };
  function staminaOf(args) {
    return args.stamina === void 0 || args.stamina === null ? void 0 : session({ session: args.stamina }, "stamina").layer;
  }
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
    "quest.hydrate": (args) => ({
      quest: computeHydrationExpected({
        content: args.content,
        ...args.status ? { status: args.status } : {}
      })
    }),
    /**
     * `quest.radiantTick` — core's deterministic radiant distributor.
     * args: `{ quests: [{id, tags, status}], maxOffering: number, ticks: number }`
     * result: `{ facts: [{predicate, args}] }` (an order-independent multiset)
     */
    "quest.radiantTick": (args) => ({
      facts: radiantTick({
        quests: args.quests || [],
        maxOffering: args.maxOffering,
        ticks: args.ticks
      })
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
    "combat.create": async (args) => {
      const engine = await sessionEngine(args, createPrologEngine);
      const s = beginCall(newSession("combat", engine), args);
      const layer = new CombatResolver({
        engine,
        seed: args.seed ?? 0,
        ...args.tuning ? { tuning: args.tuning } : {},
        ...args.actions ? { actions: new CombatActionTable(args.actions) } : {},
        stamina: staminaOf(args),
        combat: combatSystemShim(s),
        host: adapterFor(s)
      });
      return created(s, layer, async () => {
        for (const combatant of args.combatants ?? []) layer.register(combatant);
        if (engine && args.actions) await layer.publishActionTable();
      });
    },
    "combat.attack": async (args) => {
      const s = beginCall(session(args, "combat"), args);
      return endCall(
        s,
        await s.layer.attack({
          attackerId: args.attackerId,
          targetId: args.targetId,
          action: args.action,
          ...args.separation === void 0 ? {} : { separation: args.separation },
          tick: args.tick ?? 0
        })
      );
    },
    "combat.defend": async (args) => {
      const s = beginCall(session(args, "combat"), args);
      return endCall(
        s,
        await s.layer.defend({
          actorId: args.actorId,
          action: args.action,
          tick: args.tick ?? 0,
          ...args.legality ? { legality: args.legality } : {}
        })
      );
    },
    /**
     * The host owns the clock, so the host is what closes an evasion window —
     * core hands the authored duration over and never counts it down.
     */
    "combat.endDefense": async (args) => {
      const s = beginCall(session(args, "combat"), args);
      return endCall(s, await s.layer.endDefense(args.actorId));
    },
    "combat.state": (args) => {
      const s = session(args, "combat");
      return { state: s.layer.serialize(), roster: s.layer.roster() };
    },
    // ── stamina ───────────────────────────────────────────────────────────────
    "stamina.create": async (args) => {
      const engine = await sessionEngine(args, createPrologEngine);
      const s = beginCall(newSession("stamina", engine), args);
      const layer = new StaminaPool({
        engine,
        ...args.tuning ? { tuning: args.tuning } : {},
        ...args.costs ? { costs: args.costs } : {},
        // `ISurvivalSystem` takes no actor argument — it is the host's own meter
        // for the entity the host owns — so core forwards only this actor's
        // spends. Absent means none reach the host, which core documents.
        ...args.survivalActorId ? { survivalActorId: args.survivalActorId } : {},
        ...args.state ? { state: args.state } : {},
        survival: survivalShim(s)
      });
      return created(s, layer, async () => {
        for (const actor of args.actors ?? []) layer.register(actor);
        if (engine && args.publishTuning) await layer.publishTuning();
      });
    },
    "stamina.spend": async (args) => {
      const s = beginCall(session(args, "stamina"), args);
      return endCall(
        s,
        await s.layer.spend(args.actorId, {
          action: args.action,
          ...args.cost === void 0 ? {} : { cost: args.cost }
        })
      );
    },
    "stamina.rest": async (args) => {
      const s = beginCall(session(args, "stamina"), args);
      return endCall(
        s,
        await s.layer.rest(args.actorId, {
          ticks: args.ticks ?? 1,
          ...args.inCombat === void 0 ? {} : { inCombat: args.inCombat },
          ...args.encumbered === void 0 ? {} : { encumbered: args.encumbered }
        })
      );
    },
    "stamina.state": (args) => {
      const s = session(args, "stamina");
      return { state: s.layer.serialize(), roster: s.layer.roster() };
    },
    // ── perception ────────────────────────────────────────────────────────────
    //
    // The one module whose inbound half core already supports directly:
    // `DetectionTracker.observe({readings})` takes the host's measurements, which
    // is how the corpus and a headless world drive it. `IPerceptionProbe` is the
    // same data one pair at a time, and the shim serves any pair the host left
    // out. Nothing about what a reading is WORTH crosses either way.
    "perception.create": async (args) => {
      const engine = await sessionEngine(args, createPrologEngine);
      const s = beginCall(newSession("perception", engine), args);
      const layer = new DetectionTracker({
        engine,
        seed: args.seed ?? 0,
        // A CURIE, and required: belief is stamped at a world derived from it,
        // so core cannot invent one. The host passes the playthrough it is in.
        playthrough: args.playthrough,
        ...args.namespace ? { namespace: args.namespace } : {},
        ...args.tuning ? { tuning: args.tuning } : {},
        ...args.actions ? { actions: args.actions } : {},
        host: adapterFor(s)
      });
      return created(s, layer, async () => {
        for (const observer of args.observers ?? []) layer.registerObserver(observer);
        for (const target of args.targets ?? []) layer.registerTarget(target);
        if (engine && args.actions) await layer.publishActions();
      });
    },
    "perception.observe": async (args) => {
      const s = beginCall(session(args, "perception"), args);
      return endCall(
        s,
        await s.layer.observe({
          tick: args.tick ?? 0,
          ...args.readings ? { readings: args.readings } : {}
        })
      );
    },
    "perception.state": (args) => {
      const s = session(args, "perception");
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
    "traversal.create": async (args) => {
      const engine = await sessionEngine(args, createPrologEngine);
      const s = beginCall(newSession("traversal", engine), args);
      const layer = new TraversalPlanner({
        engine,
        ...args.links ? { links: args.links } : {},
        ...args.tuning ? { tuning: args.tuning } : {},
        stamina: staminaOf(args),
        host: adapterFor(s),
        ...args.state ? { state: args.state } : {}
      });
      return created(s, layer, async () => {
        for (const actor of args.actors ?? []) await layer.register(actor);
        if (engine && args.links) await layer.publishGraph();
      });
    },
    "traversal.traverse": async (args) => {
      const s = beginCall(session(args, "traversal"), args);
      return endCall(
        s,
        await s.layer.traverse(args.actorId, args.to, args.intent ?? void 0)
      );
    },
    "traversal.affordances": async (args) => {
      const s = beginCall(session(args, "traversal"), args);
      return endCall(s, { affordances: await s.layer.affordances(args.actorId) });
    },
    "traversal.state": (args) => {
      const s = session(args, "traversal");
      return { state: s.layer.serialize() };
    },
    // ── skill ─────────────────────────────────────────────────────────────────
    //
    // Drawing a tree is NOT an interface — it is the value `buildSkillView`
    // returns — so the only thing that leaves through a host hook here is a
    // `modifies(Param, Amount)` effect whose parameter names a quantity only the
    // engine holds. Absolute totals, once per change to an actor's taken nodes.
    "skill.create": async (args) => {
      const engine = await sessionEngine(args, createPrologEngine);
      const s = beginCall(newSession("skill", engine), args);
      const layer = new SkillProgression({
        engine,
        ...args.skills ? { skills: args.skills } : {},
        ...args.trees ? { trees: args.trees } : {},
        ...args.tuning ? { tuning: args.tuning } : {},
        ...args.state ? { state: args.state } : {},
        skillModifiers: skillModifierSinkShim(s)
      });
      return created(s, layer, async () => {
        if (engine && (args.skills || args.trees)) await layer.publishWorld();
        for (const actor of args.actors ?? []) await layer.register(actor);
      });
    },
    "skill.award": async (args) => {
      const s = beginCall(session(args, "skill"), args);
      return endCall(s, await s.layer.award(args.actorId, args.skill, args.amount ?? 0));
    },
    "skill.unlock": async (args) => {
      const s = beginCall(session(args, "skill"), args);
      return endCall(s, await s.layer.unlock(args.actorId, args.node));
    },
    "skill.state": (args) => {
      const s = session(args, "skill");
      return { state: s.layer.serialize() };
    },
    // ── equipment ─────────────────────────────────────────────────────────────
    //
    // The only interface that runs both ways, and therefore the cheapest place to
    // see the inversion whole: `getBaseStats` is a reading the host gathered
    // before the call, `applyStats` is an order it drains after.
    "equipment.create": (args) => {
      const s = beginCall(newSession("equipment", void 0), args);
      const layer = new EquipmentManager({
        ...args.entityId ? { entityId: args.entityId } : {},
        ...args.state ? { state: args.state } : {},
        combatStats: combatStatSinkShim(s)
      });
      return created(s, layer);
    },
    "equipment.equip": (args) => {
      const s = beginCall(session(args, "equipment"), args);
      return endCall(s, s.layer.equip(args.item));
    },
    "equipment.unequip": (args) => {
      const s = beginCall(session(args, "equipment"), args);
      return endCall(s, s.layer.unequip(args.slot));
    },
    "equipment.state": (args) => {
      const s = session(args, "equipment");
      return { state: s.layer.getState(), bonuses: s.layer.getBonuses() };
    },
    // ── routine ───────────────────────────────────────────────────────────────
    //
    // `RoutineDirector` writes one `agent_goal/3` and stops; walking to the forge
    // because your day says so leaves through `ILocomotionHost` like any other
    // movement, which is why this module names no interface of its own.
    "routine.create": async (args) => {
      const engine = await sessionEngine(args, createPrologEngine);
      const s = beginCall(newSession("routine", engine), args);
      const layer = new RoutineDirector({
        engine,
        ...args.routines ? { routines: args.routines } : {},
        ...args.tuning ? { tuning: args.tuning } : {}
      });
      return created(s, layer, async () => {
        if (engine && args.routines) await layer.publishRoutines();
        for (const assignment of args.assign ?? []) {
          await layer.assign(assignment.agent, assignment.routine ?? null);
        }
      }).then((result) => ({ ...result, issues: layer.issues() }));
    },
    "routine.tick": async (args) => {
      const s = beginCall(session(args, "routine"), args);
      return endCall(
        s,
        await s.layer.tick(args.clock ?? { day: 1, hour: 0 }, args.agents ?? [])
      );
    },
    "routine.state": (args) => {
      const s = session(args, "routine");
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
    "mechanic.dispose": (args) => ({ disposed: closeSession(args.session) }),
    /** Every open session — a leak in a game shows up here as growth. */
    "mechanic.sessions": () => ({ sessions: openSessions() }),
    /**
     * `mechanic.modules` — which modules this build can reach, by name, with the
     * rows and host interfaces each one uses. Asking the BINARY is the only
     * honest way to know what it can do; a version stamp is not (Unity §12.6
     * item 2). The gate diffs this against core's own module manifest.
     */
    "mechanic.modules": () => ({
      modules: MECHANIC_MODULES,
      hostInterfaces: HOST_INTERFACES
    }),
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
    "prolog.run": async (args) => {
      const program = Array.isArray(args.kb) ? args.kb.join("\n") : String(args.kb ?? "");
      const engine = await createPrologEngine();
      try {
        const consulted = await engine.consult(program);
        if (!consulted.success) {
          return { ok: false, stage: "consult", error: consulted.error ?? "consult failed", solutions: [] };
        }
        const result = await engine.query(String(args.query ?? ""), args.maxResults ?? 1e3);
        if (!result.success) {
          return { ok: false, stage: "query", error: result.error ?? "query failed", solutions: [] };
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
    "conformance.run": async (args) => ({
      result: await runCorpusCase(String(args.area ?? ""), args.case ?? {})
    }),
    /**
     * `conformance.areas` — which decision corpora this build can execute, and
     * which module owns each. Asking the binary, again: a corpus vendored into
     * `conformance/` with no runner behind it is exactly the failure this whole
     * story exists to close, and it is only visible by comparing these two lists.
     */
    "conformance.areas": () => ({
      areas: Object.keys(CORPUS_AREAS).sort(),
      byModule: CORPUS_AREAS_BY_MODULE
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

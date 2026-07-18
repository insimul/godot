// Structural syntax scanner for the native engine trees (C#, GDScript, C++).
//
// WHY THIS EXISTS: Unity/Godot/Unreal editors, the .NET SDK, and the Unreal
// Build Tool are NOT available in this harness (see tools/README.md). A full
// compile is therefore impossible. This scanner is a *structural* gate: it
// tokenizes each file with a language-aware lexer (comments, string / char /
// raw / interpolated / triple-quoted literals) and asserts that
//   1. every ( [ { is closed by a matching ) ] } (no cross-nesting), and
//   2. every string / char / block-comment literal is terminated.
//
// This catches GROSS syntactic breakage — a dropped brace, an unterminated
// string, a stray closer — which is exactly the class of error a fresh-context
// codegen/refactor iteration is most likely to introduce. It does NOT and
// cannot catch type errors, undeclared identifiers, bad API usage, or any
// semantic mistake. Document that honestly; do not oversell it.
//
// No external dependencies (matches scripts/engines/*.mjs house style).

/** @typedef {{line:number,col:number,msg:string}} SyntaxError_ */

const OPENERS = { '(': ')', '[': ']', '{': '}' };
const CLOSERS = { ')': '(', ']': '[', '}': '{' };

const LANGS = {
  cs: {
    exts: ['.cs'],
    line: '//',
    block: ['/*', '*/'],
    charLit: true, // '...' is a char literal
    verbatim: true, // @"..." ("" escapes)
    interp: true, // $"..." with {expr} holes
  },
  cpp: {
    exts: ['.cpp', '.h', '.hpp', '.cc', '.inl'],
    line: '//',
    block: ['/*', '*/'],
    charLit: true,
    raw: true, // R"delim(...)delim"
  },
  gd: {
    exts: ['.gd'],
    line: '#',
    block: null,
    triple: true, // """...""" and '''...'''
  },
};

function isIdentChar(ch) {
  return ch !== undefined && /[A-Za-z0-9_]/.test(ch);
}

/**
 * Scan a single source text. Returns the list of structural errors found
 * (empty => structurally sound). Reports at most a handful per file so a
 * cascade from one dropped brace does not bury the signal.
 *
 * @param {string} text
 * @param {'cs'|'cpp'|'gd'} lang
 * @returns {SyntaxError_[]}
 */
export function scanText(text, lang) {
  const cfg = LANGS[lang];
  if (!cfg) throw new Error(`unknown lang: ${lang}`);
  const errors = [];
  // Unified context stack. Entries:
  //   {kind:'bracket', char, line, col}
  //   {kind:'string',  quote, verbatim, interpolated, tripleLen, line, col}
  //   {kind:'interp',  line, col}   -- a {expr} hole inside an interpolated string
  const stack = [];
  let line = 1;
  let col = 0;
  const n = text.length;

  const push = (e) => stack.push(e);
  const top = () => (stack.length ? stack[stack.length - 1] : null);
  const err = (msg, l = line, c = col) => {
    if (errors.length < 8) errors.push({ line: l, col: c, msg });
  };
  const inString = () => top() && top().kind === 'string';

  for (let i = 0; i < n; i++) {
    let ch = text[i];
    if (ch === '\n') {
      line++;
      col = 0;
      const t = top();
      // A single/double-quoted string (non-verbatim, non-triple) must not span
      // a newline. Verbatim (@""), triple ("""), and raw strings may.
      if (t && t.kind === 'string' && !t.verbatim && !t.tripleLen && !t.raw) {
        err(`unterminated string literal`, t.line, t.col);
        stack.pop();
      }
      continue;
    }
    col++;

    // ---- inside a string literal ----------------------------------------
    if (inString()) {
      const s = top();
      if (s.tripleLen) {
        // triple-quoted: close on a run of >= tripleLen of the same quote
        if (ch === s.quote) {
          let run = 1;
          while (text[i + run] === s.quote) run++;
          if (run >= s.tripleLen) {
            i += s.tripleLen - 1;
            col += s.tripleLen - 1;
            stack.pop();
          } else {
            i += run - 1;
            col += run - 1;
          }
        }
        continue;
      }
      if (s.raw) {
        // C++ raw string: close on )delim"
        if (ch === ')' && text.startsWith(s.close, i)) {
          i += s.close.length - 1;
          col += s.close.length - 1;
          stack.pop();
        }
        continue;
      }
      if (s.verbatim) {
        if (ch === s.quote) {
          if (text[i + 1] === s.quote) {
            i++;
            col++;
            continue;
          } // "" escaped quote
          stack.pop();
          continue;
        }
        // interpolation holes inside $@"..." are possible but not used in this
        // corpus; fall through treating braces as literal text.
        continue;
      }
      // normal / interpolated string
      if (ch === '\\') {
        i++;
        col++;
        continue;
      } // escape
      if (s.interpolated && ch === '{') {
        if (text[i + 1] === '{') {
          i++;
          col++;
          continue;
        } // {{ literal
        push({ kind: 'interp', line, col });
        continue; // enter code mode inside the hole
      }
      if (s.interpolated && ch === '}' && text[i + 1] === '}') {
        i++;
        col++;
        continue;
      } // }} literal
      if (ch === s.quote) {
        stack.pop();
        continue;
      }
      continue;
    }

    // ---- code mode -------------------------------------------------------
    // line comment
    if (cfg.line && text.startsWith(cfg.line, i)) {
      const nl = text.indexOf('\n', i);
      if (nl === -1) break;
      col += nl - i - 1;
      i = nl - 1;
      continue;
    }
    // block comment
    if (cfg.block && text.startsWith(cfg.block[0], i)) {
      const end = text.indexOf(cfg.block[1], i + cfg.block[0].length);
      if (end === -1) {
        err(`unterminated block comment`);
        break;
      }
      for (let j = i; j < end + cfg.block[1].length; j++) {
        if (text[j] === '\n') {
          line++;
          col = 0;
        } else col++;
      }
      i = end + cfg.block[1].length - 1;
      continue;
    }
    // C++ raw string R"delim( ... )delim"
    if (cfg.raw && ch === 'R' && text[i + 1] === '"' && !isIdentChar(text[i - 1])) {
      const open = text.indexOf('(', i + 2);
      if (open === -1) {
        err(`malformed raw string literal`);
        break;
      }
      const delim = text.slice(i + 2, open);
      push({ kind: 'string', raw: true, close: `)${delim}"`, line, col });
      col += open - i;
      i = open;
      continue;
    }
    // C# verbatim @"..."  (optionally interpolated $@ / @$ — not in corpus)
    if (cfg.verbatim && ch === '@' && text[i + 1] === '"') {
      push({ kind: 'string', quote: '"', verbatim: true, line, col });
      i++;
      col++;
      continue;
    }
    // C# interpolated $"..."
    if (cfg.interp && ch === '$' && text[i + 1] === '"') {
      push({ kind: 'string', quote: '"', interpolated: true, line, col });
      i++;
      col++;
      continue;
    }
    // string / triple-string opener
    if (ch === '"' || (cfg.triple && ch === "'")) {
      if (cfg.triple) {
        let run = 1;
        while (text[i + run] === ch) run++;
        if (run >= 3) {
          push({ kind: 'string', quote: ch, tripleLen: 3, line, col });
          i += 2;
          col += 2;
          continue;
        }
        if (run === 2 && ch === '"') {
          i += 1;
          col += 1;
          continue;
        } // empty string ""
      }
      if (ch === '"') {
        // C# / C++: a bare "" empty string (run of exactly 2) -> consume both
        push({ kind: 'string', quote: '"', line, col });
        continue;
      }
      // gd single-quote string
      push({ kind: 'string', quote: "'", line, col });
      continue;
    }
    // char literal (cs / cpp) — treat like a mini string closed by next '
    if (cfg.charLit && ch === "'") {
      push({ kind: 'string', quote: "'", line, col });
      continue;
    }
    // brackets
    if (ch === '(' || ch === '[' || ch === '{') {
      push({ kind: 'bracket', char: ch, line, col });
      continue;
    }
    if (ch === ')' || ch === ']' || ch === '}') {
      const t = top();
      if (ch === '}' && t && t.kind === 'interp') {
        stack.pop();
        continue;
      } // close interpolation hole
      if (!t || t.kind !== 'bracket') {
        err(`unexpected '${ch}' with no matching '${CLOSERS[ch]}'`);
        continue;
      }
      if (t.char !== CLOSERS[ch]) {
        err(`'${ch}' does not match '${t.char}' opened at ${t.line}:${t.col}`);
        // pop anyway to keep scanning
        stack.pop();
        continue;
      }
      stack.pop();
      continue;
    }
  }

  // EOF: anything left open is an error.
  for (const t of stack) {
    if (t.kind === 'bracket') {
      err(`unclosed '${t.char}'`, t.line, t.col);
    } else if (t.kind === 'string') {
      err(`unterminated string/char literal`, t.line, t.col);
    } else if (t.kind === 'interp') {
      err(`unterminated interpolation hole`, t.line, t.col);
    }
  }
  return errors;
}

export function langForExt(ext) {
  for (const [name, cfg] of Object.entries(LANGS)) {
    if (cfg.exts && cfg.exts.includes(ext)) return name;
  }
  return null;
}

export { LANGS };

#!/usr/bin/env python3
"""Structural GDScript lint — a dependency-free stand-in for `godot --check-only`.

The Ralph harness has no `godot` binary, so the template `.gd` tree cannot be
parsed by the real engine. This lint is an HONEST structural check, not a full
GDScript parser: it catches the classes of breakage a bad edit most commonly
introduces — unbalanced brackets, unterminated string literals, `func`/`if`/…
header lines missing their trailing `:`, and space-based indentation in a
tab-indented file. It deliberately does NOT check types, name resolution, or
runtime semantics; those need a real Godot binary (`smoke/test_smoke.gd`,
`tests/conformance_runner.gd`) and are gated by `autoMerge: false` review.

Usage:
    python3 gdscript_structural_lint.py [ROOT ...]

With no ROOT args it lints the Godot template scripts and the GDExtension `.gd`
files relative to the repo root. Exits 0 when every file is structurally clean,
1 otherwise (with a per-issue report).
"""
import os
import sys

OPEN = {"(": ")", "[": "]", "{": "}"}
CLOSE = {")": "(", "]": "[", "}": "{"}

# Header keywords whose line must end with ':' (after stripping trailing comment).
BLOCK_KEYWORDS = ("func ", "if ", "elif ", "else", "for ", "while ", "match ", "class ")


def _strip_trailing_comment(code_line):
    """Return the line with any trailing `# ...` comment removed, respecting
    string literals so a `#` inside a string is not treated as a comment."""
    in_str = None
    esc = False
    for i, ch in enumerate(code_line):
        if in_str is not None:
            if esc:
                esc = False
            elif ch == "\\":
                esc = True
            elif ch == in_str:
                in_str = None
            continue
        if ch in ("'", '"'):
            in_str = ch
        elif ch == "#":
            return code_line[:i]
    return code_line


def _has_top_level_colon(code):
    """True if `code` contains a ':' outside brackets and strings — the block
    colon of a header. Excludes type-hint/dict/slice colons nested in ()/[]/{}
    and inline-body statements are fine (an `if c: return x` still qualifies)."""
    depth = 0
    in_str = None
    esc = False
    for ch in code:
        if in_str is not None:
            if esc:
                esc = False
            elif ch == "\\":
                esc = True
            elif ch == in_str:
                in_str = None
            continue
        if ch in ("'", '"'):
            in_str = ch
        elif ch in OPEN:
            depth += 1
        elif ch in CLOSE:
            depth = max(0, depth - 1)
        elif ch == ":" and depth == 0:
            return True
    return False


def lint_file(path):
    """Return a list of (lineno, message) structural issues for one .gd file."""
    issues = []
    with open(path, "r", encoding="utf-8") as fh:
        text = fh.read()

    # Per-line flags (1-indexed): does the line's first character sit inside a
    # triple-quoted string, and what is the bracket depth at the line's start?
    # Continuation lines (depth > 0, or the previous line ended with '\') are not
    # logical-statement starts, so the indentation / header checks skip them.
    n_lines = text.count("\n") + 1
    line_start_in_triple = [False] * (n_lines + 2)
    line_start_depth = [0] * (n_lines + 2)

    stack = []            # (char, lineno) of open brackets
    in_triple = None      # '"""' or "'''"
    in_str = None         # '"' or "'"  (single-line string)
    esc = False
    lineno = 1
    i = 0
    length = len(text)
    while i < length:
        ch = text[i]
        if ch == "\n":
            lineno += 1
            if lineno < len(line_start_in_triple):
                line_start_in_triple[lineno] = in_triple is not None
                line_start_depth[lineno] = len(stack)
            if in_str is not None:
                issues.append((lineno - 1, "unterminated string literal"))
                in_str = None
                esc = False
            i += 1
            continue

        if in_triple is not None:
            if text.startswith(in_triple, i):
                in_triple = None
                i += 3
                continue
            i += 1
            continue

        if in_str is not None:
            if esc:
                esc = False
            elif ch == "\\":
                esc = True
            elif ch == in_str:
                in_str = None
            i += 1
            continue

        # Not inside any string.
        if ch == "#":
            # Skip to end of line (comment).
            nl = text.find("\n", i)
            i = length if nl == -1 else nl
            continue
        if text.startswith('"""', i) or text.startswith("'''", i):
            in_triple = text[i:i + 3]
            i += 3
            continue
        if ch in ('"', "'"):
            in_str = ch
            i += 1
            continue
        if ch in OPEN:
            stack.append((ch, lineno))
        elif ch in CLOSE:
            if not stack:
                issues.append((lineno, "unmatched closing '%s'" % ch))
            else:
                open_ch, open_line = stack.pop()
                if OPEN[open_ch] != ch:
                    issues.append((lineno, "mismatched '%s' (opened '%s' at line %d)" % (ch, open_ch, open_line)))
        i += 1

    if in_triple is not None:
        issues.append((lineno, "unterminated triple-quoted string"))
    for open_ch, open_line in stack:
        issues.append((open_line, "unclosed '%s'" % open_ch))

    # Line-level checks operate on LOGICAL lines: a physical line that starts a
    # new statement (bracket depth 0 at its start, not inside a triple string,
    # and the previous physical line did not end with a '\' continuation), joined
    # with the continuation lines that follow it. This tolerates multi-line func
    # signatures, `if (...) or \` splits, and array literals spanning lines.
    lines = text.split("\n")

    def in_triple_at(ln):
        return line_start_in_triple[ln] if ln < len(line_start_in_triple) else False

    def depth_at(ln):
        return line_start_depth[ln] if ln < len(line_start_depth) else 0

    def code_of(idx):
        return _strip_trailing_comment(lines[idx]).rstrip()

    def is_continued(idx):
        # True if physical line `idx` (0-based) continues onto the next line.
        return depth_at(idx + 2) > 0 or code_of(idx).endswith("\\")

    idx = 0
    n = len(lines)
    while idx < n:
        ln = idx + 1  # 1-based
        if in_triple_at(ln) or depth_at(ln) > 0 or (idx > 0 and is_continued(idx - 1)):
            idx += 1
            continue  # continuation line or inside a triple string — not a start
        raw = lines[idx]
        if not raw.strip():
            idx += 1
            continue
        # Indentation of the logical-start line must be tabs (this tree is
        # tab-indented). Continuation lines may align with spaces, so only the
        # start line is checked.
        lead = raw[:len(raw) - len(raw.lstrip())]
        if " " in lead:
            issues.append((ln, "space-based indentation (expected tabs)"))
        # Join the logical line (start + continuations) for the header-colon check.
        parts = [code_of(idx)]
        j = idx
        while is_continued(j) and j + 1 < n:
            j += 1
            parts.append(code_of(j).lstrip())
        joined = " ".join(p.rstrip("\\").rstrip() for p in parts).rstrip()
        stripped = joined.lstrip()
        if stripped:
            for kw in BLOCK_KEYWORDS:
                if stripped == kw.strip() or stripped.startswith(kw):
                    if not _has_top_level_colon(joined):
                        # Ternary `x if c else y` legitimately has no block colon.
                        if not (" if " in stripped and " else " in stripped):
                            issues.append((ln, "block header '%s...' missing block ':'" % kw.strip()))
                    break
        idx = j + 1
    return issues


def _default_roots(repo_root):
    return [
        os.path.join(repo_root, "packages", "godot", "templates", "scripts"),
        os.path.join(repo_root, "packages", "godot", "gdextension"),
        os.path.join(repo_root, "packages", "godot", "addons"),
    ]


def main(argv):
    here = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.abspath(os.path.join(here, "..", "..", "..", ".."))
    roots = argv[1:] if len(argv) > 1 else _default_roots(repo_root)

    gd_files = []
    for root in roots:
        if os.path.isfile(root) and root.endswith(".gd"):
            gd_files.append(root)
            continue
        for dirpath, _dirs, names in os.walk(root):
            for name in sorted(names):
                if name.endswith(".gd"):
                    gd_files.append(os.path.join(dirpath, name))
    gd_files.sort()

    total_issues = 0
    for path in gd_files:
        issues = lint_file(path)
        if issues:
            total_issues += len(issues)
            rel = os.path.relpath(path, repo_root)
            for ln, msg in issues:
                print("FAIL %s:%d — %s" % (rel, ln, msg))

    print("gdscript-structural-lint: %d file(s), %d issue(s)" % (len(gd_files), total_issues))
    if total_issues:
        return 1
    print("gdscript-structural-lint: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

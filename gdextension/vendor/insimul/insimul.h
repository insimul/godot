/*
 * insimul.h — CONTRACT COPY of the libinsimul C ABI.
 *
 * ⚠ This is a vendored *contract* header, not the shipping library. libinsimul
 * itself is produced by the `libinsimul-bootstrap` PRD (insimul-native/, plan
 * §3.1). Until that lands and its dist/ header + libs are consumed per
 * insimul-native/docs/consuming.md, this file exists so the GDExtension layer
 * (src/insimul_prolog.cpp) can be *syntax-gated* against the exact ABI we intend
 * to link. When libinsimul-bootstrap merges, replace this file with the real
 * dist header and drop the note in insimul.gdextension / THIRD_PARTY.md.
 *
 * The ABI mirrors libinsimul US-LI2 verbatim:
 *   - extern "C", no Trealla types leaked.
 *   - One KB == one thread. No global state.
 *   - Query solutions are emitted as JSON binding-set strings; see prolog_value.h
 *     for the format and its decode into godot Variants.
 */

#ifndef INSIMUL_H
#define INSIMUL_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Opaque handles — implementation types live inside libinsimul. */
typedef struct insimul_kb insimul_kb;
typedef struct insimul_query insimul_query;

/* --- KB lifecycle --------------------------------------------------------- */

/* Create an empty knowledge base. Returns NULL on allocation failure. */
insimul_kb *insimul_kb_create(void);

/* Destroy a KB and release all owned resources. Safe on NULL. */
void insimul_kb_destroy(insimul_kb *kb);

/* --- Program / fact mutation ---------------------------------------------- */

/* Consult (load) Prolog program text (clauses, directives). Returns 1 on
 * success, 0 on error — call insimul_last_error() for the reason. */
int insimul_kb_consult(insimul_kb *kb, const char *source);

/* Assert a single fact/clause (e.g. "quest(q1, active)."). 1 ok / 0 error. */
int insimul_kb_assert(insimul_kb *kb, const char *fact);

/* Retract the first matching fact/clause. 1 ok / 0 error. */
int insimul_kb_retract(insimul_kb *kb, const char *fact);

/* --- Query iteration ------------------------------------------------------ */

/* Start a query for `goal`. Returns NULL on parse error (see last_error). The
 * returned iterator is owned by the caller and MUST be freed with
 * insimul_query_stop(). */
insimul_query *insimul_query_start(insimul_kb *kb, const char *goal);

/* Advance to the next solution. Returns a NUL-terminated JSON binding-set
 * string (owned by the query; valid until the next _next/_stop call), or NULL
 * when solutions are exhausted. `{}` denotes a solution with no bindings. */
const char *insimul_query_next(insimul_query *q);

/* Release a query iterator. Safe on NULL. */
void insimul_query_stop(insimul_query *q);

/* --- Snapshot / restore (save-file bridge) -------------------------------- */

/* Serialize the KB's dynamic-fact set as canonical Prolog text (deterministic
 * ordering). Returned string is owned by the KB, valid until the next snapshot
 * call. NULL on error. */
const char *insimul_kb_snapshot(insimul_kb *kb);

/* Replace the KB's dynamic-fact set from a snapshot image. 1 ok / 0 error. */
int insimul_kb_restore(insimul_kb *kb, const char *image);

/* --- Diagnostics ---------------------------------------------------------- */

/* Human-readable message for the most recent failure on this KB, or "" if none.
 * Owned by the KB. */
const char *insimul_last_error(insimul_kb *kb);

/* Library version string ("<semver>+<git-sha> (trealla <pin>)"). */
const char *insimul_version(void);

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* INSIMUL_H */

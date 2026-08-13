// test_mechanic_bridge.cpp — the band-120 mechanic gate (tasklist 147, US-1).
//
// Drives the SEVEN band-120 decision layers across the C ABI, end to end, on the
// natively linked libinsimul. Nothing here is mocked: `combat.attack` runs core's
// `CombatResolver` over core's `resolution.ts`, asks the KB `can_attack/2`
// through the real Trealla, and writes its fact delta into a real KB.
//
// ── WHAT IT IS FOR ──────────────────────────────────────────────────────────
//
// US-1's acceptance is "a bridge method plus a host implementation, with no
// second copy of core's logic — proven by pointing at the entry.js rows rather
// than asserting it". A row that exists and a row that WORKS are different
// claims, and only the second one is worth anything, so this file executes them.
//
// The four claims it holds to account:
//
//   1. REACHABILITY. `mechanic.modules` names seven modules and every row it
//      claims is in `core.methods`. Asking the binary is the only honest way to
//      know what a build can do — a version stamp is not (Unity's §12.6 item 2).
//   2. THE INVERSION. Readings handed in reach core; every call core would have
//      made to a host interface comes back out as an order. `ICombatStatSink` is
//      the one interface that runs both ways, so it is checked both ways.
//   3. THE HOST CANNOT DECIDE. The same shot is fired with a clear line and with
//      a blocked one, and the difference is core's to make: the blocked one is
//      refused, and NOTHING else about the resolution moves. A host that lied in
//      either direction still cannot change a damage number.
//   4. THE SEAM. `applied: true` means the fact delta reached a real KB through
//      `host-prolog-engine.js`'s assert/retract path, and a query afterwards
//      finds what was asserted. That path did not exist before this story.
//
// ── WHAT IT IS NOT ──────────────────────────────────────────────────────────
//
// It is not a conformance run. Core's own vectors for these modules
// (`conformance/combat/`, `stealth/`, `traversal/`, `skills/`, `items/`,
// `routines/`) are US-2's job — vendoring them and executing them is what proves
// PARITY, and this proves REACHABILITY. The numbers asserted below are therefore
// deliberately few and structural (a refusal is a refusal, a total is the sum of
// its parts); pinning core's damage arithmetic here would be a second copy of
// the corpus in C++.

#include "json_value.h"

extern "C" {
#include "insimulcore.h"
}

#include <cstdio>
#include <string>
#include <vector>

using insimul::JsonValue;
using insimul::JsonValuePtr;

namespace {

int failures = 0;
int checks = 0;

void ok(const std::string &what) {
	checks++;
	std::printf("  ✓ %s\n", what.c_str());
}

void fail(const std::string &what, const std::string &detail) {
	checks++;
	failures++;
	std::printf("  ✗ %s\n      %s\n", what.c_str(), detail.c_str());
}

void check(bool condition, const std::string &what, const std::string &detail = std::string()) {
	if (condition) {
		ok(what);
	} else {
		fail(what, detail.empty() ? "expectation not met" : detail);
	}
}

/** One bridge call, parsed. A failed call is a failed check, never a crash. */
JsonValuePtr call(insimul_core *core, const char *method, const std::string &args,
		const std::string &what) {
	const char *raw = insimul_core_call(core, method, args.empty() ? nullptr : args.c_str());
	if (!raw) {
		fail(what, std::string(method) + " failed: " + insimul_core_last_error(core));
		return nullptr;
	}
	insimul::JsonParseResult parsed = insimul::parse_json(raw);
	if (!parsed.ok) {
		fail(what, std::string(method) + " returned unparseable JSON: " + parsed.error);
		return nullptr;
	}
	return parsed.root;
}

/** The `orders` array of a row result, or an empty one. */
std::vector<const JsonValue *> orders_of(const JsonValuePtr &result, const char *host,
		const char *callName) {
	std::vector<const JsonValue *> found;
	if (!result) return found;
	const JsonValue *orders = result->find("orders");
	if (!orders || !orders->is_array()) return found;
	for (const JsonValuePtr &item : orders->array_items) {
		if (!item || !item->is_object()) continue;
		if (item->get_string("host") != host) continue;
		if (callName && item->get_string("call") != callName) continue;
		found.push_back(item.get());
	}
	return found;
}

const JsonValue *path(const JsonValue *node, const std::vector<std::string> &keys) {
	const JsonValue *at = node;
	for (const std::string &key : keys) {
		if (!at) return nullptr;
		at = at->find(key);
	}
	return at;
}

std::string session_of(const JsonValuePtr &result) {
	if (!result) return "0";
	const JsonValue *handle = result->find("session");
	return handle ? std::to_string(handle->as_int(0)) : "0";
}

// ── the scenarios ───────────────────────────────────────────────────────────

/**
 * Claim 1 — what this build can reach, asked of the build.
 */
void check_reachability(insimul_core *core) {
	std::printf("\nreachability — mechanic.modules against core.methods\n");
	JsonValuePtr methods = call(core, "core.methods", "", "core.methods answers");
	JsonValuePtr modules = call(core, "mechanic.modules", "", "mechanic.modules answers");
	if (!methods || !modules) return;

	std::vector<std::string> names;
	const JsonValue *list = methods->find("methods");
	if (list && list->is_array()) {
		for (const JsonValuePtr &item : list->array_items) names.push_back(item->as_string());
	}
	auto has_method = [&names](const std::string &name) {
		for (const std::string &known : names) {
			if (known == name) return true;
		}
		return false;
	};

	const JsonValue *table = modules->find("modules");
	check(table && table->is_object(), "mechanic.modules returns a module table");
	if (!table || !table->is_object()) return;
	check(table->object_items.size() == 7,
			"seven band-120 modules are reachable",
			"got " + std::to_string(table->object_items.size()));

	int rows = 0;
	for (const auto &entry : table->object_items) {
		const JsonValue *module_rows = entry.second->find("rows");
		if (!module_rows || !module_rows->is_array()) {
			fail(entry.first + " declares rows", "no rows array");
			continue;
		}
		for (const JsonValuePtr &row : module_rows->array_items) {
			rows++;
			if (!has_method(row->as_string())) {
				fail(entry.first + " row " + row->as_string() + " is callable",
						"declared by mechanic.modules but absent from core.methods");
			}
		}
	}
	ok("every declared row (" + std::to_string(rows) + ") is in core.methods");
	// A row that vanishes must fail here, so the floor is asserted rather than
	// reported — the discipline run_radiant_tests.sh applies to its case count.
	check(rows >= 26, "the adopted mechanic surface is at least 26 rows",
			"got " + std::to_string(rows));
}

/**
 * Claims 2, 3 and 4 — combat and the shared meter, which are one scenario
 * because they are one mechanic: a swing spends the same `energy/3` a climb does.
 */
void check_combat_and_stamina(insimul_core *core) {
	std::printf("\ncombat + stamina — orders out, readings in, decisions core's\n");

	// The shared meter first: combat borrows it rather than growing its own.
	JsonValuePtr pool = call(core, "stamina.create",
			R"({"kb":"","costs":{"crossbow_shot":12},"survivalActorId":"nessa",
			    "actors":[{"id":"nessa","max":100}]})",
			"stamina.create opens a session");
	const std::string pool_id = session_of(pool);

	JsonValuePtr spend = call(core, "stamina.spend",
			"{\"session\":" + pool_id + ",\"actorId\":\"nessa\",\"action\":\"crossbow_shot\"}",
			"stamina.spend answers");
	const JsonValue *spent = path(spend.get(), {"report", "spend"});
	check(spent && spent->get_int("spent") == 12,
			"core charged the AUTHORED cost (12), not one the host invented",
			spent ? "spent=" + std::to_string(spent->get_int("spent")) : "no spend report");
	check(path(spend.get(), {"report", "applied"}) &&
					path(spend.get(), {"report", "applied"})->as_bool(),
			"the energy/3 delta reached a real KB through the Prolog seam");
	auto consume = orders_of(spend, "ISurvivalSystem", "consumeStamina");
	check(consume.size() == 1 && consume[0]->get_int("amount") == 12,
			"ISurvivalSystem was TOLD the spend core decided",
			"orders=" + std::to_string(consume.size()));

	// Combat, wired to the same pool. `can_attack/2` is authored in the KB: the
	// legality gate is the world's rule, not a flag in the request.
	JsonValuePtr fight = call(core, "combat.create",
			"{\"kb\":\"can_attack(nessa, boar).\\ncan_attack(boar, nessa).\\n\",\"seed\":7,"
			"\"stamina\":" + pool_id + ","
			R"("combatants":[{"id":"nessa","health":30,"maxHealth":30},
			                 {"id":"boar","health":20,"maxHealth":20}],
			   "actions":[{"id":"crossbow_shot","delivery":"projectile","range":20,"damage":6,
			               "accuracy":1,"staminaCost":12}]})",
			"combat.create opens a session");
	const std::string fight_id = session_of(fight);
	auto registrations = orders_of(fight, "ICombatSystem", "registerEntity");
	check(registrations.size() == 2,
			"registering a combatant is an ORDER, not a bridge-side write",
			"orders=" + std::to_string(registrations.size()));

	// The shot with a clear line.
	JsonValuePtr hit = call(core, "combat.attack",
			"{\"session\":" + fight_id + ",\"attackerId\":\"nessa\",\"targetId\":\"boar\","
			R"("action":"crossbow_shot","separation":8,"tick":3,"trajectory":{"clear":true}})",
			"combat.attack (clear line) answers");
	const JsonValue *clear_res = path(hit.get(), {"report", "resolution"});
	check(clear_res && clear_res->get_string("outcome") == "hit",
			"a clear line resolves as a hit",
			clear_res ? clear_res->get_string("outcome") : "no resolution");
	auto asked = path(hit.get(), {"asked"});
	check(asked && asked->size() == 1,
			"ITrajectoryProbe was asked EXACTLY ONCE for the ranged shot",
			asked ? "asked=" + std::to_string(asked->size()) : "no asked array");
	auto damage_orders = orders_of(hit, "ICombatSystem", "applyDamage");
	const long long dealt = clear_res ? clear_res->get_int("damage") : -1;
	check(damage_orders.size() == 1 && damage_orders[0]->get_int("damage") == dealt,
			"ICombatSystem is told the damage CORE computed, unrounded by the host",
			"order damage vs resolution damage");
	check(path(hit.get(), {"report", "applied"}) && path(hit.get(), {"report", "applied"})->as_bool(),
			"the combat fact delta reached the KB");
	const JsonValue *stamina_leg = path(hit.get(), {"report", "stamina"});
	check(stamina_leg && stamina_leg->find("spend"),
			"the swing was paid for out of the SHARED meter, reported as its own delta");

	// The same shot with the line blocked. The host answers a QUESTION; core
	// decides what follows from the answer.
	JsonValuePtr blocked = call(core, "combat.attack",
			"{\"session\":" + fight_id + ",\"attackerId\":\"nessa\",\"targetId\":\"boar\","
			R"("action":"crossbow_shot","separation":8,"tick":4,
			   "trajectory":{"clear":false,"blockedBy":"crate"}})",
			"combat.attack (blocked line) answers");
	const JsonValue *blocked_res = path(blocked.get(), {"report", "resolution"});
	check(blocked_res && blocked_res->get_int("damage") == 0,
			"a blocked line does no damage — core's decision, from the host's reading",
			blocked_res ? "damage=" + std::to_string(blocked_res->get_int("damage")) : "none");
	check(orders_of(blocked, "ICombatSystem", "applyDamage").empty(),
			"nothing is applied for a shot that never arrived");
	const JsonValue *line = path(blocked.get(), {"report", "lineOfFire"});
	check(line && line->get_string("blockedBy") == "crate",
			"the host's reason is CARRIED, never interpreted",
			line ? line->get_string("blockedBy") : "no lineOfFire");

	// And with no reading at all — the documented fallback, which is what a
	// turn-based world and a headless simulation run in.
	JsonValuePtr unprobed = call(core, "combat.attack",
			"{\"session\":" + fight_id + ",\"attackerId\":\"nessa\",\"targetId\":\"boar\","
			R"("action":"crossbow_shot","separation":8,"tick":5})",
			"combat.attack (no reading) answers");
	const JsonValue *unprobed_res = path(unprobed.get(), {"report", "resolution"});
	check(unprobed_res && unprobed_res->get_int("damage") > 0,
			"a world with no geometry still fights — reach and accuracy alone",
			unprobed_res ? "damage=" + std::to_string(unprobed_res->get_int("damage")) : "none");

	call(core, "mechanic.dispose", "{\"session\":" + fight_id + "}", "combat session disposed");
	call(core, "mechanic.dispose", "{\"session\":" + pool_id + "}", "stamina session disposed");
}

/** Perception — readings in, and the belief that is not the truth. */
void check_perception(insimul_core *core) {
	std::printf("\nperception — the host measures, core decides what it is worth\n");
	JsonValuePtr tracker = call(core, "perception.create",
			R"({"kb":"","seed":11,
			    "playthrough":{"kind":"world","namespace":"insimul","localId":"pt1"},
			    "observers":[{"id":"guard","senses":[{"channel":"sight","acuity":1}]}],
			    "targets":[{"id":"nessa","location":"courtyard","light":80,"stance":"standing"}]})",
			"perception.create opens a session");
	const std::string id = session_of(tracker);
	if (id == "0") return;

	// Square in view: the host says what its senses reached, nothing else.
	JsonValuePtr seen = call(core, "perception.observe",
			"{\"session\":" + id + ",\"tick\":1,"
			R"("readings":[{"observer":"guard","target":"nessa","visibility":1,"light":90}]})",
			"perception.observe (clear view) answers");
	const JsonValue *updates = path(seen.get(), {"report", "updates"});
	check(updates && updates->size() == 1,
			"one pair, one update",
			updates ? "updates=" + std::to_string(updates->size()) : "none");
	check(path(seen.get(), {"report", "applied"}) &&
					path(seen.get(), {"report", "applied"})->as_bool(),
			"the detection delta reached the KB");

	// The same pair, unseen. Suspicion is core's curve over the host's number.
	JsonValuePtr unseen = call(core, "perception.observe",
			"{\"session\":" + id + ",\"tick\":2,"
			R"("readings":[{"observer":"guard","target":"nessa","visibility":0}]})",
			"perception.observe (no view) answers");
	const JsonValue *dark = path(unseen.get(), {"report", "updates"});
	check(dark && dark->size() == 1, "a pair with nothing to see is still an answer");

	call(core, "mechanic.dispose", "{\"session\":" + id + "}", "perception session disposed");
}

/** Traversal — the probe answers, the locomotion host is ordered. */
void check_traversal(insimul_core *core) {
	std::printf("\ntraversal — probe asked, locomotion ordered, cost charged\n");
	JsonValuePtr pool = call(core, "stamina.create",
			R"({"kb":"","actors":[{"id":"nessa","max":100}]})", "stamina.create for traversal");
	const std::string pool_id = session_of(pool);

	// The KB carries `forbidden_by/4` because a WORLD's rule pack does. Core's
	// `checkAction` throws when the goal raises rather than reading an undefined
	// procedure as a permit — deliberately, and identically on the wasm engine —
	// so a session whose KB is missing the pack a module's gate reads fails the
	// call. That is a host obligation, and it is why the Godot host consults the
	// packs before it opens a session (RUNTIME_CORE_ADOPTION.md §12.3).
	JsonValuePtr planner = call(core, "traversal.create",
			"{\"kb\":\":- dynamic(forbidden_by/4).\\n\",\"stamina\":" + pool_id + ","
			R"("links":[{"id":"gap_west","from":"ledge","to":"ridge","mode":"jump","cost":9,
			             "geometric":true},
			            {"id":"path_east","from":"ledge","to":"camp","mode":"walk","cost":2}],
			   "actors":[{"id":"nessa","location":"ledge","modes":["walk","jump"]}]})",
			"traversal.create opens a session");
	const std::string id = session_of(planner);
	if (id == "0") return;

	// A geometric link the host says is not jumpable from here.
	JsonValuePtr refused = call(core, "traversal.traverse",
			"{\"session\":" + id + ",\"actorId\":\"nessa\",\"to\":\"ridge\","
			R"("probe":{"gap_west":{"passable":false,"blockedBy":"wet_rock"}}})",
			"traversal.traverse (impassable) answers");
	check(path(refused.get(), {"report", "performed"}) &&
					!path(refused.get(), {"report", "performed"})->as_bool(),
			"a link the host says is impassable is not ordered");
	check(orders_of(refused, "ILocomotionHost", "travel").empty(),
			"no locomotion order goes out for a refused movement");

	// The same link, passable. One order, carrying an intent and no path.
	JsonValuePtr made = call(core, "traversal.traverse",
			"{\"session\":" + id + ",\"actorId\":\"nessa\",\"to\":\"ridge\","
			R"("probe":{"gap_west":{"passable":true}},"intent":{"urgency":"hurried"}})",
			"traversal.traverse (passable) answers");
	auto travel = orders_of(made, "ILocomotionHost", "travel");
	check(travel.size() == 1, "one movement, one order",
			"orders=" + std::to_string(travel.size()));
	if (travel.size() == 1) {
		const JsonValue *order = travel[0]->find("order");
		check(order && order->get_string("to") == "ridge" &&
						order->get_string("mode") == "jump",
				"the order names a location atom and a mode — no path, no speed");
		check(order && order->get_string("urgency") == "hurried",
				"the caller's intent rides out on the order, unread by core");
		// 9 authored on the link, times the world's `jump` multiplier of 2. The
		// host is told what was CHARGED, not what was authored, and it is told
		// after the fact — the meter moved before this order existed.
		check(order && order->get_int("cost") == 18,
				"the order carries the resolved cost core already charged",
				order ? "cost=" + std::to_string(order->get_int("cost")) : "no order");
	}
	check(path(made.get(), {"report", "location"}) &&
					path(made.get(), {"report", "location"})->as_string() == "ridge",
			"core learns ONE thing about where the actor went: the location atom");

	call(core, "mechanic.dispose", "{\"session\":" + id + "}", "traversal session disposed");
	call(core, "mechanic.dispose", "{\"session\":" + pool_id + "}", "traversal meter disposed");
}

/** Skills — the one effect whose subject only the engine holds. */
void check_skill(insimul_core *core) {
	std::printf("\nskill — absolute modifier totals, told once per change\n");
	JsonValuePtr progression = call(core, "skill.create",
			R"({"kb":":- dynamic(forbidden_by/4).\n",
			    "skills":[{"id":"athletics","category":"physical","maxLevel":10,"requires":[]}],
			    "trees":[{"id":"athletics_tree","skill":"athletics","nodes":[
			      {"id":"fleet_footed","tree":"athletics_tree","cost":1,"parents":[],"requires":[],
			       "effects":[{"kind":"modifies","args":["move_speed",2]}]}]}],
			    "actors":[{"id":"nessa","levels":{"athletics":3},"points":{"athletics_tree":2}}]})",
			"skill.create opens a session");
	const std::string id = session_of(progression);
	if (id == "0") return;

	JsonValuePtr unlocked = call(core, "skill.unlock",
			"{\"session\":" + id + ",\"actorId\":\"nessa\",\"node\":\"fleet_footed\"}",
			"skill.unlock answers");
	check(path(unlocked.get(), {"report", "performed"}) &&
					path(unlocked.get(), {"report", "performed"})->as_bool(),
			"the node was taken");
	auto modifiers = orders_of(unlocked, "ISkillModifierSink", "applyModifiers");
	check(modifiers.size() >= 1,
			"ISkillModifierSink is told the whole modifier set",
			"orders=" + std::to_string(modifiers.size()));
	if (!modifiers.empty()) {
		const JsonValue *set = modifiers.back()->find("modifiers");
		const JsonValue *speed = set ? set->find("move_speed") : nullptr;
		check(speed && speed->as_int(0) == 2,
				"the parameter is the WORLD's spelling and the total is absolute",
				speed ? "move_speed=" + std::to_string(speed->as_int(0)) : "absent");
	}

	call(core, "mechanic.dispose", "{\"session\":" + id + "}", "skill session disposed");
}

/** Equipment — the only interface that runs both ways. */
void check_equipment(insimul_core *core) {
	std::printf("\nequipment — a reading in and an order out, on one interface\n");
	JsonValuePtr loadout = call(core, "equipment.create",
			R"({"entityId":"nessa"})", "equipment.create opens a session");
	const std::string id = session_of(loadout);
	if (id == "0") return;

	JsonValuePtr equipped = call(core, "equipment.equip",
			"{\"session\":" + id + ","
			R"("item":{"id":"iron_sword","name":"Iron Sword","equipSlot":"weapon",
			           "effects":{"attack":4}},
			   "baseStats":{"nessa":{"attackPower":5,"defense":2,"dodgeChance":0.1}}})",
			"equipment.equip answers");
	const JsonValue *asked = equipped ? equipped->find("asked") : nullptr;
	check(asked && asked->size() == 1,
			"ICombatStatSink.getBaseStats was ASKED — the reading the host gathered",
			asked ? "asked=" + std::to_string(asked->size()) : "none");
	auto applied = orders_of(equipped, "ICombatStatSink", "applyStats");
	check(applied.size() == 1, "and the recomputed totals came back out as an order");
	if (applied.size() == 1) {
		const JsonValue *stats = applied[0]->find("stats");
		const JsonValue *attack = stats ? stats->find("attackPower") : nullptr;
		check(attack && attack->as_int(0) == 9,
				"base 5 + the sword's 4 — summed by core, applied by the host",
				attack ? "attackPower=" + std::to_string(attack->as_int(0)) : "absent");
	}

	call(core, "mechanic.dispose", "{\"session\":" + id + "}", "equipment session disposed");
}

/** Routines — one `agent_goal/3`, and a destination that is not a waypoint. */
void check_routine(insimul_core *core) {
	std::printf("\nroutine — one adopted goal per tick, and nothing else\n");
	JsonValuePtr director = call(core, "routine.create",
			R"({"kb":"","routines":[{"id":"smith_day","name":"Smith's day","blocks":[
			      {"id":"forge_shift","goal":"work_forge","startHour":8,"endHour":17,
			       "days":[],"place":"forge","priority":60}]}],
			    "assign":[{"agent":"brann","routine":"smith_day"}]})",
			"routine.create opens a session");
	const std::string id = session_of(director);
	if (id == "0") return;

	JsonValuePtr midday = call(core, "routine.tick",
			"{\"session\":" + id + ",\"clock\":{\"day\":1,\"hour\":10},\"agents\":[\"brann\"]}",
			"routine.tick (inside the block) answers");
	const JsonValue *outcomes = path(midday.get(), {"report", "outcomes"});
	check(outcomes && outcomes->size() == 1, "one agent, one outcome");
	if (outcomes && outcomes->size() == 1) {
		const JsonValue *outcome = outcomes->array_items[0].get();
		check(outcome->get_string("goal") == "work_forge",
				"the block's goal is adopted", outcome->get_string("goal"));
		check(outcome->get_string("destination") == "forge",
				"the destination is a place atom — getting there is the host's problem",
				outcome->get_string("destination"));
	}

	JsonValuePtr night = call(core, "routine.tick",
			"{\"session\":" + id + ",\"clock\":{\"day\":1,\"hour\":3},\"agents\":[\"brann\"]}",
			"routine.tick (outside the block) answers");
	const JsonValue *idle = path(night.get(), {"report", "outcomes"});
	check(idle && idle->size() == 1 && idle->array_items[0]->find("goal") &&
					idle->array_items[0]->find("goal")->is_null(),
			"a gap in a routine is a real answer, not a fallback goal");

	call(core, "mechanic.dispose", "{\"session\":" + id + "}", "routine session disposed");
}

/**
 * Sessions — the answer to "which instance?", which the adopted surface never
 * had to give before (Unity's §12.2 finding 2).
 */
void check_sessions(insimul_core *core) {
	std::printf("\nsessions — stateful layers behind a stateless ABI\n");
	JsonValuePtr first = call(core, "equipment.create", R"({"entityId":"a"})", "session A opens");
	JsonValuePtr second = call(core, "equipment.create", R"({"entityId":"b"})", "session B opens");
	const std::string a = session_of(first);
	const std::string b = session_of(second);
	check(a != b, "two sessions of one module are distinct", a + " vs " + b);

	call(core, "equipment.equip",
			"{\"session\":" + a + ","
			R"("item":{"id":"sword","name":"Sword","equipSlot":"weapon"}})",
			"A equips something");
	JsonValuePtr state_b = call(core, "equipment.state", "{\"session\":" + b + "}", "B is read");
	const JsonValue *worn_b = state_b ? state_b->find("state") : nullptr;
	check(worn_b && worn_b->is_object() && worn_b->object_items.empty(),
			"B did not see A's equipment — separate state, not a global");

	call(core, "mechanic.dispose", "{\"session\":" + a + "}", "A disposed");
	const char *stale = insimul_core_call(core, "equipment.state",
			("{\"session\":" + a + "}").c_str());
	check(stale == nullptr, "a disposed handle is an ERROR, not an empty answer",
			stale ? std::string("returned ") + stale : "");

	JsonValuePtr open = call(core, "mechanic.sessions", "", "mechanic.sessions answers");
	const JsonValue *list = open ? open->find("sessions") : nullptr;
	check(list && list->size() == 1, "exactly the sessions still open are reported",
			list ? "open=" + std::to_string(list->size()) : "none");
	call(core, "mechanic.dispose", "{\"session\":" + b + "}", "B disposed");
}

/**
 * The Prolog seam's new path, checked directly: what a module asserted is
 * QUERYABLE afterwards, and a re-assert does not double it.
 */
void check_prolog_seam(insimul_core *core) {
	std::printf("\nprolog seam — assert/retract in place, mirroring core's bookkeeping\n");
	JsonValuePtr pool = call(core, "stamina.create",
			R"({"kb":"","costs":{"sprint":5},"actors":[{"id":"nessa","max":100}]})",
			"stamina.create opens a session with a KB");
	const std::string id = session_of(pool);
	if (id == "0") return;

	for (int i = 0; i < 3; i++) {
		call(core, "stamina.spend",
				"{\"session\":" + id + ",\"actorId\":\"nessa\",\"action\":\"sprint\"}",
				"spend " + std::to_string(i + 1) + " of 3");
	}
	JsonValuePtr state = call(core, "stamina.state", "{\"session\":" + id + "}", "the meter is read");
	const JsonValue *actors = path(state.get(), {"state", "actors"});
	const JsonValue *actor = actors && actors->size() == 1 ? actors->array_items[0].get() : nullptr;
	check(actor && actor->get_int("current") == 85,
			"three spends of five leave 85 — the retract/assert cycle held",
			actor ? "current=" + std::to_string(actor->get_int("current")) : "no actor");

	call(core, "mechanic.dispose", "{\"session\":" + id + "}", "seam session disposed");
}

} // namespace

int main() {
	insimul_core *core = insimul_core_create();
	if (!core) {
		std::fprintf(stderr, "error: insimul_core_create() failed — the bridge could not start\n");
		return 1;
	}
	std::printf("libinsimulcore %s\n", insimul_core_version());

	check_reachability(core);
	check_combat_and_stamina(core);
	check_perception(core);
	check_traversal(core);
	check_skill(core);
	check_equipment(core);
	check_routine(core);
	check_sessions(core);
	check_prolog_seam(core);

	JsonValuePtr leaked = call(core, "mechanic.sessions", "", "no session was left open");
	const JsonValue *list = leaked ? leaked->find("sessions") : nullptr;
	check(list && list->size() == 0, "every session this gate opened was disposed",
			list ? "still open=" + std::to_string(list->size()) : "none");

	insimul_core_destroy(core);

	std::printf("\n%d check(s), %d failure(s)\n", checks, failures);
	if (checks < 40) {
		std::fprintf(stderr, "error: the gate ran only %d checks — it must not shrink silently\n",
				checks);
		return 1;
	}
	if (failures > 0) {
		std::printf("FAILED\n");
		return 1;
	}
	std::printf("PASSED\n");
	return 0;
}

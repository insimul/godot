class_name InsimulMechanicActivator
extends RefCounted
## Opens exactly the sessions a world's [InsimulModuleActivation] names, wires
## exactly the host interfaces those modules declare, and says out loud what it
## could not reach — tasklist 147, US-3.
##
## [InsimulModuleActivation] answers *what this world selected*;
## [InsimulMechanicSurface] answers *what this BUILD can drive*. Neither is the
## other, and the interesting cases are where they disagree:
##
## [codeblock]
## selected + reachable    a session is opened, its hosts are wired.  -> opened()
## selected + no row       the vocabulary is in the KB and its gates
##                         evaluate, but no decision layer is bundled
##                         to run it.                            -> unreachable()
## not selected            nothing. No pack in the KB, no session,
##                         no wired host, no fallback host.
## [/codeblock]
##
## The second row is not hypothetical and is not a defect in this plugin: a genre
## bundle can select a module whose decision layers no engine has adopted yet.
## Reporting it is the whole point — a game that silently skipped it would look
## identical to a game where the mechanic works.
##
## [codeblock]
## var activation := InsimulModuleActivation.for_world(DataLoader.load_world_data())
## var live := InsimulMechanicActivator.activate(activation, world_facts, {
##     # per module, core's own create arguments — see the rows in entry.js
##     "<module id>": {"seed": 7, "actors": [...]},
## }, {
##     "<IInterfaceName>": my_host,
## })
## for line in live.report():
##     print(line)
## var session := live.session("<module id>")
## [/codeblock]
##
## ## Nothing here names a mechanic
##
## Same rule as [InsimulModuleActivation], same gate: the module ids arrive from
## the activation, the interface names arrive from the module descriptors, the
## rows arrive from the build. Adding a module to a bundle in core changes what
## this class opens without a line changing here.

## A session is open for this module.
const OPENED := "opened"
## Selected, and this build carries no rows for it — see the class doc.
const NO_ROW := "no_row"
## Selected and reachable, but the session refused to open. The reason is in
## [method last_error] for that module.
const REFUSED := "refused"

var _activation: InsimulModuleActivation = null
var _sessions := {}
var _states := {}
var _errors := {}


## Open a session for every selected module this build can drive.
##
## `world_facts`    the world's own Prolog facts. The active packs are prepended
##                  by [method InsimulModuleActivation.kb_with]; a module the
##                  world did not select contributes no vocabulary to it.
## `args_by_module` module id -> that module's create arguments, in core's own
##                  field names. A module with no entry opens with defaults.
##                  Any value of the form `{"session": "<module id>"}` is
##                  replaced by the handle of that module's already-opened
##                  session, which is how one module's create takes another's
##                  (a shared meter is the case that needs it) without this
##                  class knowing which modules those are.
## `hosts`          interface name -> implementation. Filtered per module to the
##                  interfaces that module declares, so an implementation is
##                  never handed to a session whose module did not ask for it.
static func activate(
	activation: InsimulModuleActivation,
	world_facts: String = "",
	args_by_module: Dictionary = {},
	hosts: Dictionary = {}
) -> InsimulMechanicActivator:
	var live := InsimulMechanicActivator.new()
	live._activation = activation
	if activation == null:
		return live
	var surface := InsimulMechanicSurface.new()
	var kb := activation.kb_with(world_facts)
	for module_id in activation.module_ids():
		var state := surface.status(module_id)
		if state != InsimulMechanicSurface.READY:
			live._states[module_id] = NO_ROW
			live._errors[module_id] = state
			continue
		var args: Dictionary = {}
		var declared: Variant = args_by_module.get(module_id, {})
		if declared is Dictionary:
			args = live._resolve_links((declared as Dictionary).duplicate(true))
		args["kb"] = kb
		var session := InsimulMechanicSession.open(
			module_id, args, live._hosts_for(module_id, hosts)
		)
		if session == null:
			live._states[module_id] = REFUSED
			live._errors[module_id] = "the module refused to open"
			continue
		live._sessions[module_id] = session
		live._states[module_id] = OPENED
	return live


## The activation these sessions were opened for.
func activation() -> InsimulModuleActivation:
	return _activation


## The open session for a module, or null when there is none — which is the
## same answer for "this world did not select it" and "this build cannot drive
## it". [method state_of] tells them apart.
func session(module_id: String) -> InsimulMechanicSession:
	return _sessions.get(module_id, null)


## Every module with an open session.
func opened() -> PackedStringArray:
	var out := PackedStringArray()
	for module_id in _sessions.keys():
		out.append(String(module_id))
	out.sort()
	return out


## Selected modules with no open session, as module id -> why. Never silent.
func unreachable() -> Dictionary:
	var out := {}
	for module_id in _states.keys():
		if _states[module_id] != OPENED:
			out[module_id] = _errors.get(module_id, _states[module_id])
	return out


## One of [constant OPENED], [constant NO_ROW], [constant REFUSED], or "" for a
## module this world did not select.
func state_of(module_id: String) -> String:
	return String(_states.get(module_id, ""))


## Why a module has no session, or "".
func last_error(module_id: String) -> String:
	return String(_errors.get(module_id, ""))


## A boot-log block: one line per selected module, with what it got.
func report() -> PackedStringArray:
	var lines := PackedStringArray()
	if _activation == null:
		lines.append("[Insimul] mechanics: nothing activated (no activation)")
		return lines
	lines.append(
		"[Insimul] activated %d of %d selected module(s)"
		% [_sessions.size(), _activation.module_ids().size()]
	)
	for module_id in _activation.module_ids():
		lines.append(
			"  %-11s %-9s %s"
			% [
				module_id,
				state_of(module_id),
				", ".join(_activation.interfaces_for(module_id)),
			]
		)
	return lines


## Close every open session. Safe to call twice.
func dispose_all() -> void:
	for module_id in _sessions.keys():
		var session: InsimulMechanicSession = _sessions[module_id]
		session.dispose()
	_sessions.clear()


# ── wiring ───────────────────────────────────────────────────────────────────

## The subset of `hosts` this module declares an interface for. An
## implementation the module never asks for is not passed to it — that is what
## "an inactive module registers no system" means on the wiring side.
func _hosts_for(module_id: String, hosts: Dictionary) -> Dictionary:
	var out := {}
	for interface_name in _activation.interfaces_for(module_id):
		if hosts.has(interface_name):
			out[interface_name] = hosts[interface_name]
	return out


## Replace every `{"session": "<module id>"}` with that module's open handle.
## Recursive, so a nested argument works the same way.
func _resolve_links(args: Dictionary) -> Dictionary:
	for key in args.keys():
		var value: Variant = args[key]
		if value is Dictionary:
			var nested: Dictionary = value
			if nested.size() == 1 and nested.has("session") and nested["session"] is String:
				var linked: InsimulMechanicSession = _sessions.get(String(nested["session"]), null)
				args[key] = linked.handle if linked != null else null
			else:
				args[key] = _resolve_links(nested)
		elif value is Array:
			var items: Array = value
			for i in items.size():
				if items[i] is Dictionary:
					items[i] = _resolve_links(items[i])
	return args

extends SceneTree
## The card hooks against the card base, headless:
##   godot --headless --path . -s res://tests/hooks_test.gd [-- all]
## The engine finds a card's code by the name of a method ("enter_pieclops", see
## rules/base.gd); a typo in a name is no error, the card just does nothing. This test
## reads every method of the rules files and the card base and prints:
##   - extra hooks: a hook whose card id (or hero card, or hero event) is not in the base;
##   - missing hooks: a spell without spell_<id>, a floop card without floop_<id>, a card
##     with an activated ability without act_<id>, a hero card nothing in the code knows;
##   - engine prefixes: a prefix the engine calls ("enter_" + id) that is not in
##     Game.HOOK_PREFIXES, so methods with it are never found.
## Any of these fails the test. With "all" it also lists the cards with a text but
## no code at all (vanilla wording, kept in the engine as a quoted id, or not done).

const Game = preload("res://scripts/core/game.gd")
const CardDB = preload("res://scripts/core/card_db.gd")

## Methods with a hook prefix that are not hooks (helpers of a rules file).
const NOT_HOOKS := []

var failures := 0


func _initialize() -> void:
	var show_all := OS.get_cmdline_user_args().has("all")
	CardDB.ensure_loaded()
	var cards := {}
	for id: String in CardDB.card_ids():
		cards[id] = CardDB.get_def(id)
	var hero_cards: Array = CardDB.hero_card_ids()
	var sources := _sources()
	var events := _hero_events(sources)
	var called := _called_prefixes(sources)
	var hooks := {}             # method name -> rules file
	var hooked_ids := {}        # card or hero card id -> true
	for script: GDScript in Game.RULES:
		var file := script.resource_path.get_file()
		for m in script.get_script_method_list():
			var n: String = m["name"]
			if _prefix(n) != "" and not NOT_HOOKS.has(n):
				hooks[n] = file

	print("hooks: %d in %d rules files, cards %d, hero cards %d" % [hooks.size(), Game.RULES.size(), cards.size(), hero_cards.size()])

	# Extra hooks: names that point at nothing.
	var extra := []
	for n: String in hooks:
		if n.begins_with("hero_"):
			var hc := _hero_card_of(n, hero_cards)
			var ev := n.trim_prefix("hero_").trim_suffix("_" + hc)
			if hc == "":
				extra.append("%s (%s): no such hero card" % [n, hooks[n]])
			elif not events.has(ev):
				extra.append("%s (%s): the engine has no hero event «%s»" % [n, hooks[n], ev])
			else:
				hooked_ids[hc] = true
			continue
		var pre := _longest(n, called)
		if pre == "":
			extra.append("%s (%s): the engine never calls a hook of this kind" % [n, hooks[n]])
			continue
		var id := n.substr(pre.length())
		if cards.has(id):
			hooked_ids[id] = true
		else:
			extra.append("%s (%s): no card «%s»" % [n, hooks[n], id])
	_report("extra hooks", extra)

	# Missing hooks: what the card says it does and the engine would call. A ФЛЮП or an
	# activated ability may work through other hooks (Огненная стена-торнадо: atk_ while flooped).
	var missing := []
	for id: String in cards:
		var d: Dictionary = cards[id]
		if String(d.get("text", "")).strip_edges() == "":
			continue
		if d["kind"] == "spell" and not hooks.has("spell_" + id):
			missing.append("%s «%s»: a spell without spell_%s" % [id, d["name"], id])
		if d.get("floop", false) and not hooked_ids.has(id):
			missing.append("%s «%s»: ФЛЮП without floop_%s" % [id, d["name"], id])
		if d.has("activated") and not hooked_ids.has(id):
			missing.append("%s «%s»: an activated ability without act_%s" % [id, d["name"], id])
	for hc: String in hero_cards:
		if String(CardDB.hero_card(hc).get("text", "")).strip_edges() != "" and not hooked_ids.has(hc) \
				and not _quoted(sources, hc):
			missing.append("hero card %s «%s»: no hero_<event>_%s and no code that names it" % [hc, CardDB.hero_card(hc)["name"], hc])
	_report("missing hooks", missing)

	# Prefixes the engine and the rules put before an id, that the hook table does not know.
	var bad_prefixes := []
	var re := RegEx.create_from_string("(?:call_hook|run_hook|has_hook|_notify|_hooks\\.has)\\(\\s*\"([a-z_]+_)\"")
	for path: String in sources:
		for m in re.search_all(sources[path]):
			var pre := m.get_string(1)
			if _prefix(pre + "x") == "":
				bad_prefixes.append("%s: «%s» is not in Game.HOOK_PREFIXES" % [path.get_file(), pre])
	_report("engine prefixes", bad_prefixes)

	if show_all:
		var silent := []
		for id: String in cards:
			var d: Dictionary = cards[id]
			if String(d.get("text", "")).strip_edges() != "" and not hooked_ids.has(id) and not _quoted(sources, id):
				silent.append("%s «%s» (%s): %s" % [id, d["name"], d["kind"], d["text"]])
		print("\ncards with a text and no code (%d):" % silent.size())
		for line: String in silent:
			print("  " + line)

	print("hooks test: %d problems" % failures)
	quit(1 if failures > 0 else 0)


## The hook prefix of a method name as the engine sees it (Game._build_hook_table), "" for none.
func _prefix(n: String) -> String:
	for p: String in Game.HOOK_PREFIXES:
		if n.begins_with(p):
			return p
	return ""


## The hero card a "hero_<event>_<card>" name ends with (the longest that fits).
func _hero_card_of(n: String, hero_cards: Array) -> String:
	var best := ""
	for hc: String in hero_cards:
		if n.ends_with("_" + hc) and hc.length() > best.length() and n.length() > ("hero__" + hc).length():
			best = hc
	return best


## Events the engine and the rules ask hero cards about: hero_hook(p, "<event>"), _hero_event(p, "<event>").
func _hero_events(sources: Dictionary) -> Dictionary:
	var out := {}
	var re := RegEx.create_from_string("(?:hero_hook|_hero_event)\\([^\\n,]*,\\s*\"([a-z0-9_]+)\"")
	for path: String in sources:
		for m in re.search_all(sources[path]):
			out[m.get_string(1)] = true
	return out


## Prefixes the code puts before an id to call a hook: "enter_" + id, _notify("on_enter_", ...),
## _trigger_own(p, "start_"). "hero_" names are checked apart.
func _called_prefixes(sources: Dictionary) -> Array:
	var out := []
	var res := [RegEx.create_from_string("\"([a-z_]+_)\"\\s*\\+"),
		RegEx.create_from_string("(?:_notify|_trigger_own)\\([^\"\\n]*?\"([a-z_]+_)\"")]
	for path: String in sources:
		for re: RegEx in res:
			for m in re.search_all(sources[path]):
				var pre := m.get_string(1)
				if _prefix(pre + "x") != "" and not out.has(pre):
					out.append(pre)
	return out


## The longest of the prefixes that n begins with, "" for none.
func _longest(n: String, prefixes: Array) -> String:
	var best := ""
	for pre: String in prefixes:
		if n.begins_with(pre) and pre.length() > best.length():
			best = pre
	return best


## The code of the engine and of every rules file, path -> text.
func _sources() -> Dictionary:
	var out := {}
	var paths := ["res://scripts/core/game.gd", "res://scripts/train/train_rules.gd"]
	for script: GDScript in Game.RULES:
		paths.append(script.resource_path)
	for path: String in paths:
		out[path] = FileAccess.get_file_as_string(path)
	return out


func _quoted(sources: Dictionary, id: String) -> bool:
	for path: String in sources:
		if sources[path].contains("\"%s\"" % id):
			return true
	return false


func _report(title: String, lines: Array) -> void:
	failures += lines.size()
	if lines.is_empty():
		print("%s: none" % title)
		return
	print("\n%s (%d):" % [title, lines.size()])
	for line: String in lines:
		print("  " + line)

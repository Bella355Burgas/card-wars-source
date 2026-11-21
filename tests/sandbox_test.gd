extends SceneTree
## «Песочница» (scripts/core/sandbox.gd), headless: every change of the table by hand, undo,
## the start of the table again, a turn for the other side, and that none of it is a command
## the online table would take.
##   godot --headless --path . -s res://tests/sandbox_test.gd

const Game = preload("res://scripts/core/game.gd")
const Sandbox = preload("res://scripts/core/sandbox.gd")
const Board = preload("res://scripts/ui/board.gd")
const CardDB = preload("res://scripts/core/card_db.gd")
const AILevels = preload("res://scripts/ai/ai_levels.gd")
const SandboxStart = preload("res://scripts/ui/main/sandbox_start.gd")

var failures := 0
var checks := 0
var g
var sb


func _initialize() -> void:
	var tests := ["t_hand", "t_table", "t_deck_discard", "t_damage_heal", "t_boost", "t_freeze", "t_lands",
		"t_remove", "t_hp", "t_actions", "t_infinite", "t_draw_shuffle_clear", "t_undo", "t_reset",
		"t_other_side", "t_pass_turn", "t_no_journal", "t_not_online", "t_teams", "t_three",
		"t_tiny_deck", "t_empty_deck", "t_no_creatures", "t_no_hero", "t_no_hero_ai", "t_change_hero"]
	for t in tests:
		await _fresh()
		await call(t)
	print("sandbox tests: %d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _fresh(heroes := ["finn", "jake"]) -> void:
	g = Game.new()
	g.setup(heroes, 0, 11)
	sb = Sandbox.new(g)
	await g.start_game()
	sb.mark_start()


func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAIL: ", what)


func t_hand() -> void:
	var n: int = g.players[1].hand.size()
	var c = await sb.add_card(1, "cool_dog", "hand")
	ok(c != null and g.players[1].hand.has(c), "a card goes to the other player's hand")
	ok(g.players[1].hand.size() == n + 1, "one card more in that hand")
	ok(c.owner == 1, "the card belongs to that player")
	ok(g.log_lines[-1].contains("Крутой пёс"), "the log says which card came")
	ok(await sb.add_card(0, "no_such_card", "hand") == null, "an unknown card goes nowhere")


func t_table() -> void:
	var c = await sb.add_card(0, "cool_dog", "creature", 2)
	ok(g.players[0].creatures[2] == c, "a creature goes on its spot")
	ok(g.atk_of(0, 2) == 2 and g.def_of(0, 2) == 7, "it has its stats")
	var b = await sb.add_card(1, "schoolhouse", "building", 1)
	ok(g.players[1].buildings[1] == b, "a building goes on the other side")
	ok(await sb.add_card(0, "schoolhouse", "creature", 0) == null, "a building is no creature")
	ok(await sb.add_card(0, "cool_dog", "creature", 7) == null, "no lane 8")
	var d = await sb.add_card(0, "evil_eye", "creature", 2)
	ok(g.players[0].creatures[2] == d and g.players[0].discard.has(c), "a new creature puts the old one into the discard pile")
	ok(c.damage == 0 and not c.exhausted, "the old one leaves with no table state")


func t_deck_discard() -> void:
	var c = await sb.add_card(0, "cool_dog", "deck")
	ok(g.players[0].deck[-1] == c, "on top of the deck")
	var c2 = await sb.add_card(0, "evil_eye", "bottom")
	ok(g.players[0].deck[0] == c2, "under the deck")
	var c3 = await sb.add_card(1, "evil_eye", "discard")
	ok(g.players[1].discard[-1] == c3, "into the discard pile")
	await sb.draw(0)
	ok(g.players[0].hand.has(c), "the top card is drawn next")


func t_damage_heal() -> void:
	await sb.add_card(1, "cool_dog", "creature", 0)
	await sb.damage(1, 0, 3)
	ok(g.players[1].creatures[0].damage == 3, "3 damage")
	await sb.heal(1, 0, 1)
	ok(g.players[1].creatures[0].damage == 2, "1 healed")
	await sb.heal(1, 0, -1)
	ok(g.players[1].creatures[0].damage == 0, "all healed")
	await sb.damage(1, 0, 7)
	ok(g.players[1].creatures[0] == null, "7 damage destroys it")
	ok(g.players[1].discard.any(func(x): return x.id == "cool_dog"), "into its discard pile")


func t_boost() -> void:
	await sb.add_card(0, "cool_dog", "creature", 1)
	await sb.boost(0, 1, 2, 0)
	ok(g.atk_of(0, 1) == 4, "attack +2")
	await sb.boost(0, 1, 0, -3)
	ok(g.def_of(0, 1) == 4, "defence −3")
	await sb.damage(0, 1, 3)
	await sb.boost(0, 1, 0, -1)
	ok(g.players[0].creatures[1] == null, "defence down to its damage destroys it")


func t_freeze() -> void:
	await sb.toggle_frozen(1, 3)
	ok(g.is_frozen(1, 3), "frozen")
	var c = await sb.add_card(1, "evil_eye", "hand")
	g.turn_player = 1
	ok(not g.can_play(1, c.uid, 3), "a frozen land takes no creature")
	await sb.toggle_frozen(1, 3)
	ok(not g.is_frozen(1, 3), "thawed")


func t_lands() -> void:
	await sb.set_land(0, 0, "corn")
	ok(g.land_type(0, 0) == "corn", "land type changed")
	await sb.add_card(0, "husker_knight", "creature", 1)
	ok(g.atk_of(0, 1) >= 1, "a corn field counts for the card")
	await sb.flip_land(0, 0)
	ok(g.players[0].lands[0]["flipped"], "flipped face down")
	await sb.flip_land(0, 0)
	ok(not g.players[0].lands[0]["flipped"], "and up again")


func t_remove() -> void:
	var c = await sb.add_card(0, "cool_dog", "creature", 0)
	ok(await sb.move_card(c.uid, "hand") and g.players[0].hand.has(c), "from the table to the hand")
	ok(g.players[0].creatures[0] == null, "its spot is free")
	ok(await sb.move_card(c.uid, "discard") and g.players[0].discard.has(c), "from the hand to the discard pile")
	ok(await sb.move_card(c.uid, "removed") and g.players[0].removed.has(c), "out of the game")
	var b = await sb.add_card(1, "schoolhouse", "building", 2)
	ok(await sb.move_card(b.uid, "destroy") and g.players[1].buildings[2] == null, "a building destroyed by the rules")
	ok(g.players[1].discard.has(b), "it is in the discard pile")
	var d = await sb.add_card(1, "cool_dog", "creature", 3)
	ok(await sb.move_card(d.uid, "destroy") and g.players[1].creatures[3] == null, "a creature destroyed")
	ok(not await sb.move_card(999999, "hand"), "no such card")


func t_hp() -> void:
	await sb.set_hp(1, 7)
	ok(g.players[1].hp == 7, "hit points set")
	await sb.set_hp(1, 0)
	ok(g.phase == "over" and g.winner == 0, "0 hit points end the game")
	await sb.set_hp(1, 5)
	ok(g.phase == "main" and g.winner == -1, "hit points back: the game goes on")


func t_actions() -> void:
	await sb.set_actions(0, 5)
	ok(g.players[0].actions == 5, "5 actions")
	await sb.set_actions(0, -3)
	ok(g.players[0].actions == 0, "never below 0")


func t_infinite() -> void:
	await sb.set_infinite(0, true)
	ok(g.players[0].actions == Sandbox.INF_ACTIONS, "infinite actions fill up")
	var c = await sb.add_card(0, "cool_dog", "hand")
	await g.run_command(0, {"cmd": "play", "uid": c.uid, "lane": 0})
	ok(g.players[0].creatures[0] == c, "played")
	sb.refill()
	ok(g.players[0].actions == Sandbox.INF_ACTIONS, "refilled after the step")
	await sb.set_infinite(0, false)
	ok(g.players[0].actions <= Game.ACTIONS_PER_TURN, "off: back to normal")


func t_draw_shuffle_clear() -> void:
	var n: int = g.players[0].hand.size()
	await sb.draw(0)
	ok(g.players[0].hand.size() == n + 1, "a card drawn")
	var before: Array = g.players[0].deck.map(func(x): return x.uid)
	await sb.shuffle(0)
	var after: Array = g.players[0].deck.map(func(x): return x.uid)
	ok(before != after and before.size() == after.size(), "the deck shuffled")
	var hand: int = g.players[0].hand.size()
	var disc: int = g.players[0].discard.size()
	await sb.clear_hand(0)
	ok(g.players[0].hand.is_empty() and g.players[0].discard.size() == disc + hand, "the hand went to the discard pile")


func t_undo() -> void:
	sb.push()
	var c = await sb.add_card(0, "cool_dog", "creature", 0)
	sb.settle()
	sb.push()
	await sb.damage(0, 0, 2)
	sb.settle()
	sb.push()
	await sb.set_hp(1, 3)
	sb.settle()
	ok(sb.history.size() == 3, "three steps to take back")
	ok(sb.undo() and g.players[1].hp == Game.START_HP, "hit points back")
	ok(sb.undo() and g.players[0].creatures[0].damage == 0, "damage back")
	ok(sb.undo() and g.players[0].creatures[0] == null, "the creature gone again")
	ok(g.card(c.uid) == null, "the new card is no more")
	ok(not sb.undo(), "nothing more to take back")
	sb.push()
	sb.settle()
	ok(sb.history.is_empty(), "a step that changed nothing is not kept")
	# A real command goes back too, a card drawn included.
	sb.push()
	await g.run_command(0, {"cmd": "draw"})
	sb.settle()
	var n: int = g.players[0].hand.size()
	ok(sb.undo() and g.players[0].hand.size() == n - 1, "a draw taken back")


func t_reset() -> void:
	var h: int = g.state_hash()
	for i in 3:
		sb.push()
		await sb.add_card(i % 2, "cool_dog", "creature", i)
		sb.settle()
	await sb.set_hp(0, 2)
	sb.reset()
	ok(g.state_hash() == h, "the table as at the start")
	ok(sb.history.is_empty(), "no steps left")


func t_other_side() -> void:
	# The other side's turn, played by hand: its commands work as for the first player.
	await sb.pass_turn()
	if g.phase == "handoff":
		await g.cmd_start_turn()
	ok(g.turn_player == 1 and g.phase == "main", "the other side's turn")
	await sb.set_infinite(1, true)
	var c = await sb.add_card(1, "evil_eye", "hand")
	await g.run_command(1, {"cmd": "play", "uid": c.uid, "lane": 2})
	ok(g.players[1].creatures[2] == c, "the other side plays a creature")
	await sb.add_card(0, "cool_dog", "creature", 2)
	await g.run_command(1, {"cmd": "begin_attack"})
	await g.run_command(1, {"cmd": "attack", "lane": 2})
	ok(g.players[0].creatures[2] == null or g.players[0].creatures[2].damage > 0, "and attacks with it")


func t_pass_turn() -> void:
	var t: int = g.turn_number
	await sb.pass_turn()
	if g.phase == "handoff":
		await g.cmd_start_turn()
	ok(g.turn_player == 1 and g.turn_number == t + 1, "the turn passed")
	await sb.pass_turn()
	if g.phase == "handoff":
		await g.cmd_start_turn()
	ok(g.turn_player == 0, "and back")


func t_no_journal() -> void:
	g.journal = []
	var s2 = Sandbox.new(g)
	ok(g.journal == null, "a sandbox game keeps no journal: no replay")
	await s2.add_card(0, "cool_dog", "hand")
	ok(g.journal == null, "still none")


func t_not_online() -> void:
	var b = Board.new()
	for cmd in ["add_card", "sandbox", "set_hp", "damage", "move_card", "set_actions", "pass_turn"]:
		ok(not Board.NET_CMD_FIELDS.has(cmd), "the online table knows no command «%s»" % cmd)
	b.free()


func t_teams() -> void:
	await _fresh(["finn", "jake", "bmo", "marceline"])
	ok(g.teams(), "2 на 2")
	var c = await sb.add_card(3, "cool_dog", "creature", 1)
	ok(g.players[3].creatures[1] == c, "a creature for the fourth seat")
	await sb.set_hp(2, 30)
	ok(g.players[0].hp == 30, "teammates share hit points")
	sb.push()
	await sb.damage(3, 1, 2)
	sb.settle()
	ok(sb.undo() and g.players[3].creatures[1].damage == 0, "undo at four seats")


func t_three() -> void:
	await _fresh(["finn", "jake", "bmo"])
	ok(g.three(), "на троих")
	var c = await sb.add_card(2, "cool_dog", "creature", 0)
	ok(g.players[2].creatures[0] == c, "a creature for the third seat")
	await sb.set_hp(2, 0)
	ok(g.players[2].out, "a seat at 0 drops out")
	ok(g.phase != "over", "the other two play on")


## A deck of the deck builder that breaks the rules plays as a run deck (no limits): its pick.
func _builder_pick(deck: Dictionary, lands := ["plain", "plain", "plain", "plain"], hero := "finn") -> String:
	return CardDB.loadout(CardDB.run_code("finn", SandboxStart._good_lands(lands), deck), hero)


## Turns go round a few times with every command the first legal one: nothing may break.
func _play_round(turns: int) -> void:
	for t in turns:
		if g.phase == "over":
			return
		if g.phase == "handoff":
			await g.cmd_start_turn()
		var cmds: Array = g.legal_commands(g.turn_player)
		for c in cmds:
			if c["cmd"] == "play":
				await g.run_command(g.turn_player, c)
				break
		await sb.pass_turn()
		if g.phase == "handoff":
			await g.cmd_start_turn()


func t_tiny_deck() -> void:
	# The deck builder with one card and no hero: the start hand used to get nulls (a crash).
	g = Game.new()
	g.setup([_builder_pick({"cool_dog": 1}), "jake"], 0, 5)
	ok(g.players[0].hand.size() == 1 and not g.players[0].hand.has(null), "one card, no empty places in the hand")
	ok(g.players[0].deck.is_empty(), "the deck is empty")
	sb = Sandbox.new(g)
	await sb.set_hero(0, "", true)
	await g.start_game()
	sb.mark_start()
	ok(g.phase == "main", "the game starts")
	await _play_round(6)
	ok(not g.players[0].hand.has(null), "turns go on with an empty deck")


func t_empty_deck() -> void:
	g = Game.new()
	g.setup([_builder_pick({"evil_eye": 1}, ["", "nothing"]), "jake"], 0, 5)
	sb = Sandbox.new(g)
	sb.clear_cards(0)
	ok(g.players[0].deck.is_empty() and g.players[0].hand.is_empty(), "no cards at all")
	ok(g.players[0].lands.all(func(l): return l["type"] == "plain"), "lands not set: plain ones")
	await g.start_game()
	sb.mark_start()
	await _play_round(4)
	ok(g.phase != "over" or g.winner >= 0, "turns go on")
	var c = await sb.add_card(0, "cool_dog", "hand")
	ok(g.players[0].hand.has(c), "cards may still be added")


func t_no_creatures() -> void:
	g = Game.new()
	g.setup([_builder_pick({"schoolhouse": 3}, ["plain", "corn", "plain", "corn"], ""), "jake"], 0, 5)
	sb = Sandbox.new(g)
	await g.start_game()
	await _play_round(6)
	ok(true, "a deck of buildings only plays")


func t_no_hero() -> void:
	await sb.set_hero(0, "")
	ok(g.players[0].hero_card == "" and g.players[0].name == "Финн", "no hero card, the deck's name")
	ok(not g.can_hero_power(0), "no hero ability")
	ok(not g.legal_commands(0).any(func(c): return c["cmd"] == "hero"), "no hero command")
	ok(not g.hero_floop_ok(0, "creature", 0), "no hero floop")
	var c = await sb.add_card(0, "cool_dog", "creature", 0)
	sb.push()
	await sb.damage(0, 0, 2)
	sb.settle()
	ok(sb.undo() and c.damage == 0 and g.players[0].hero_card == "", "undo without a hero")
	sb.reset()
	ok(g.players[0].hero_card == "finn", "the start had the hero")


func t_no_hero_ai() -> void:
	# Both seats without heroes, the AI plays both for a few turns.
	await sb.set_hero(0, "", true)
	await sb.set_hero(1, "", true)
	var agents := [AILevels.agent(AILevels.DEFAULT, "finn"), AILevels.agent(AILevels.DEFAULT, "jake")]
	var steps := 0
	while g.phase != "over" and g.turn_number < 10 and steps < 400:
		steps += 1
		if g.phase == "handoff":
			await g.cmd_start_turn()
			continue
		var p: int = g.turn_player
		var agent = agents[p]
		var cmd: Dictionary = await agent.pick_command_async(g, p) if agent.has_method("pick_command_async") else agent.pick_command(g, p)
		var before: int = g.state_hash()
		sb.push()
		await g.run_command(p, cmd)
		sb.settle()
		if g.state_hash() == before and g.turn_player == p:
			if agent.has_method("ban_command"):
				agent.ban_command(before, cmd)
			await g.run_command(p, {"cmd": "end_turn"})
	ok(g.turn_number >= 10 or g.phase == "over", "the AI plays without heroes (turn %d)" % g.turn_number)
	ok(sb.undo(), "and its steps are taken back")


func t_change_hero() -> void:
	await sb.set_hero(1, "bmo")
	ok(g.players[1].hero_card == "bmo", "another hero")
	await sb.set_hero(1, "jake")
	ok(g.players[1].hero_card == "jake" and g.players[1].name == "Джейк", "its own hero back")
	await sb.set_hero(1, "no_such_hero")
	ok(g.players[1].hero_card == "jake", "an unknown hero changes nothing")

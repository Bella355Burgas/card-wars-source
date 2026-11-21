extends "res://scripts/core/rules/base.gd"
## Hero card abilities. Each player picks a hero card along with their deck
## (any card with any deck). The engine calls "hero_<event>_<hero card id>",
## always with the hero's player first:
##
##   hero_atk_<id>(p, c, lane) -> int        ATK bonus for p's creature
##   hero_def_<id>(p, c, lane) -> int        DEF bonus for p's creature
##   hero_power_ok_<id>(p) -> bool / hero_power_<id>(p)       active ability (command "hero")
##   hero_floop_ok_<id>(p, c, lane) -> bool / hero_floop_<id>(p, c, lane)   extra floop of p's creatures
##   hero_setup_<id>(p)                      before the first turn
##   hero_battle_<id>(p)                     start of p's fight phase
##   hero_attack_empty_<id>(p, c, lane)      p's creature attacks an empty lane
##   hero_hit_player_<id>(p, c, amount)      p's creature damaged the opponent
##   hero_building_<id>(p, lane)             a building entered play under p's control
##   hero_replaced_<id>(p)                   p replaced a creature on their own turn
##   hero_to_hand_<id>(p, c)                 one of p's creatures came back to p's hand on p's turn
##   hero_played_<id>(p, c)                  p played a card


## "Once per turn" abilities share one flag: a hero has one ability.
func _ready_once(p: int) -> bool:
	return not players(p).turn.get("hero_used", false)


func _use(p: int) -> void:
	players(p).turn["hero_used"] = true


func _pay_action(p: int) -> void:
	players(p).actions -= 1
	await g.emit_event({"type": "actions", "p": p})


# Финн
func hero_floop_ok_finn(_p, c, _lane) -> bool:
	return c != null and c.damage == 0


func hero_floop_finn(p, _c, _lane) -> void:
	var t = await g.pick_creature(p, g.sides(), "Флюп Финна: нанеси 1 урон выбранному существу")
	if t != null:
		await hit(t["p"], t["lane"], 1, p)


# Джейк
func hero_atk_jake(p, _c, lane) -> int:
	return 2 if players(p).lands[lane]["flipped"] else 0


# Принцесса Бубльгум
func hero_power_ok_pb(p) -> bool:
	return _ready_once(p) and g.creature_count(p) > 0


func hero_power_pb(p) -> void:
	var t = await g.pick_creature(p, [p], "Принцесса Бубльгум: какому своему существу нанести 1 урон (+1 ATK)?",
		Callable(), true)
	if t == null:
		return
	_use(p)
	var c = creature(p, t["lane"])
	await hit(p, t["lane"], 1, p)
	if creature(p, t["lane"]) == c and g.hp_of(p, t["lane"]) > 0:
		await g.buff(c, 1)


# Принцесса Пупырка
func hero_replaced_lsp(p) -> void:
	await _first_replace(p)


func _first_replace(p: int) -> void:
	if players(p).turn.get("hero_replaced", false):
		return
	players(p).turn["hero_replaced"] = true
	await say("%s: первая замена за ход — берёт карту." % players(p).name)
	await g._draw(p)


# Гран-при: a creature played this turn goes back to the hand, comes again for free and takes 3 damage.
func _played_now(p: int) -> Callable:
	var uids: Array = players(p).turn.get("played_uids", [])
	return func(c, _s, _l): return uids.has(c.uid)


func hero_power_ok_grand_prix(p) -> bool:
	return _ready_once(p) and not g.creature_opts(p, [p], _played_now(p)).is_empty()


func hero_power_grand_prix(p) -> void:
	var t = await g.pick_creature(p, [p], "Гран-при: какое существо, сыгранное в этот ход, вернуть и сыграть снова?",
		_played_now(p), true)
	if t == null:
		return
	_use(p)
	var c = creature(p, t["lane"])
	await g.bounce_creature(p, t["lane"])
	if g.where(c.uid).get("zone", "") != "hand":
		return
	if not await g.play_free(p, c, "Гран-при: куда снова сыграть «%s»?" % c.card_name()):
		return
	var w: Dictionary = g.where(c.uid)
	if w.get("zone", "") == "creature":
		await say("Гран-при: на «%s» кладётся 3 урона." % c.card_name())
		await g.damage_creature(w["p"], w["lane"], 3, {"kind": "effect", "p": p})


# Бимо
func hero_power_ok_bmo(p) -> bool:
	return not players(p).hand.is_empty() and not g.creature_opts(p, g.sides()).is_empty()


func hero_power_bmo(p) -> void:
	if await g.force_discard(p, 1, "Бимо: сбрось карту, чтобы нанести 1 урон", Callable(), true) == 0:
		return
	var t = await g.pick_creature(p, g.sides(), "Бимо: нанеси 1 урон выбранному существу")
	if t != null:
		await hit(t["p"], t["lane"], 1, p)


# Леди Ливнерог
func hero_to_hand_rainicorn(p, _c) -> void:
	var t: Dictionary = players(p).turn
	t["hero_returned"] = int(t.get("hero_returned", 0)) + 1
	if t["hero_returned"] == 2:
		await say("Леди Ливнерог: в руку вернулись два существа.")
		await g.heal_player(p, 2)


# Снежный король
func hero_attack_empty_ice_king(p, c, _lane) -> void:
	if players(p).turn.get("hero_empty_attack", false):
		return
	players(p).turn["hero_empty_attack"] = true
	await g.buff(c, 1)


# Марселин
func hero_atk_marceline(_p, c, _lane) -> int:
	return 1 if c.damage >= 5 else 0


# Лимонохват
func hero_battle_lemongrab(p) -> void:
	if not g.empty_lanes(p).is_empty():
		await say("Лимонохват: есть пустая земля.")
		await g.heal_player(p, 1)


# Гантер
func hero_atk_gunter(p, _c, lane) -> int:
	return 1 if g.is_frozen(p, lane) else 0


# Фионна
func hero_atk_fionna(p, c, lane) -> int:
	return 1 if g.unique_land_types(p) == 1 and g.is_type(c, "rainbow", p, lane) else 0


# Кейк
# Every creature of p's in a lane with p's building heals 2.
func hero_building_cake(p, _lane) -> void:
	for l in LANES:
		var c = creature(p, l)
		if c != null and c.damage > 0 and not g.buildings_at(p, l).is_empty():
			await say("Кейк: строение лечит «%s»." % c.card_name())
			await g.heal_creature(p, l, 2)


# Тётушка Древесная
# «Пирог» in the name: the Russian name, or the English one (Pie, Pieclops… but not Pied Piper).
func _is_pie(c) -> bool:
	var ru: String = c.card_name().to_lower()
	if ru.contains("пирог") or ru.contains("пирож"):
		return true
	for w in String(c.def().get("en", "")).to_lower().split(" "):
		if w.begins_with("pie") and not w.begins_with("pied"):
			return true
	return false


func hero_power_ok_tree_trunks(p) -> bool:
	return _ready_once(p) and players(p).hand.any(_is_pie)


func hero_power_tree_trunks(p) -> void:
	if await g.force_discard(p, 1, "Тётушка Древесная: сбрось пирог, чтобы получить 1 действие", _is_pie, true) == 0:
		return
	_use(p)
	await g.gain_actions(p, 1)


# Лич: once a turn, with more cards in hand than an opponent, 1 damage to that opponent and 1 HP back.
func _fewer_cards(p: int) -> Callable:
	return func(q): return players(q).hand.size() < players(p).hand.size()


func hero_power_ok_lich(p) -> bool:
	return _ready_once(p) and g.foes(p).any(_fewer_cards(p))


func hero_power_lich(p) -> void:
	var o: int = await g.pick_foe(p, "Лич: какому сопернику нанести 1 урон?", _fewer_cards(p))
	if o < 0:
		return
	_use(p)
	await g.damage_player(o, 1, null, {"kind": "effect", "p": p})
	await g.heal_player(p, 1)


# Моникер
func hero_power_ok_monica(p) -> bool:
	return _ready_once(p) and not g.creature_opts(p, [p], func(c, _s, _l): return c.flooped).is_empty()


func hero_power_monica(p) -> void:
	var t = await g.pick_creature(p, [p], "Моникер: какое флюпнутое существо подготовить?",
		func(c, _s, _l): return c.flooped, true)
	if t == null:
		return
	_use(p)
	var c = creature(p, t["lane"])
	c.exhausted = false
	c.flooped = false
	await say("Моникер: «%s» снова готово." % c.card_name())
	await g.emit_event({"type": "ready", "p": p, "uid": c.uid})


# Джейк (Парный турнир)
func hero_hit_player_jake_2x2(p, _c, _amount) -> void:
	if g.turn_player != p or not _ready_once(p):
		return
	# «В одной из своих зон»: p's creatures and the ones across from them (2 на 2: not the other foe's).
	var t = await g.pick_creature(p, g.sides(), "Джейк (Парный турнир): нанести 1 урон выбранному существу?",
		func(_x, s2, l2): return range(LANES).any(func(ml): return g.on_lane(p, ml, s2, l2)), true)
	if t == null:
		return
	_use(p)
	await hit(t["p"], t["lane"], 1, p)


# Чарли
func _free_adjacent(p: int, lane: int) -> Array:
	return adj(lane).filter(func(a): return creature(p, a) == null)


func hero_power_ok_charlie(p) -> bool:
	return _ready_once(p) and not g.creature_opts(p, [p],
		func(_c, _s, lane): return not _free_adjacent(p, lane).is_empty()).is_empty()


func hero_power_charlie(p) -> void:
	var t = await g.pick_creature(p, [p], "Чарли: какое существо переместить?",
		func(_c, _s, lane): return not _free_adjacent(p, lane).is_empty(), true)
	if t == null:
		return
	var dest: int = await g.pick_lane(p, p, _free_adjacent(p, t["lane"]), "Чарли: на какую соседнюю зону?")
	if dest < 0:
		return
	_use(p)
	await g.move_creature(p, t["lane"], dest)


# Рикардио
func hero_power_ok_ricardio(p) -> bool:
	return _ready_once(p) and players(p).hp > 1 and not players(p).deck.is_empty()


func hero_power_ricardio(p) -> void:
	_use(p)
	players(p).hp -= 1
	await g.emit_event({"type": "player_damage", "p": p, "amount": 1, "uid": -1})
	var top = players(p).deck.back()
	await say("Рикардио: %s тратит 1 HP и открывает «%s»." % [players(p).name, top.card_name()])
	await g.emit_event({"type": "reveal", "p": p, "uids": [top.uid]})
	var pick = await g.pick_card(p, [top], "Рикардио: нажми на карту, чтобы сбросить её, или пропусти — она останется сверху",
		true)
	if pick != null:
		await g.mill(p)


# Призмо
func hero_def_prismo_classic(p, _c, _lane) -> int:
	var seen := {}
	for lane in LANES:
		var t: String = g.land_type(p, lane)
		if t == "":
			continue
		if seen.has(t):
			return 0
		seen[t] = true
	return 1


# Сьюзан Стронг
func hero_power_ok_susan_strong(p) -> bool:
	return players(p).actions >= 1 and g.creature_count(p) > 0


func hero_power_susan_strong(p) -> void:
	var t = await g.pick_creature(p, [p], "Сьюзан Стронг: какое своё существо уничтожить?", Callable(), true)
	if t == null:
		return
	var n: int = creature(p, t["lane"]).def()["cost"]
	await _pay_action(p)
	await g.destroy_creature(p, t["lane"])
	if n > 0:
		await say("Сьюзан Стронг: %d урона каждому существу соперника." % n)
		await hit_foes(p, n)


# Космическая Сова
func hero_power_ok_cosmic_owl(p) -> bool:
	return players(p).actions >= 1 and players(p).deck.size() >= 2


func hero_power_cosmic_owl(p) -> void:
	await _pay_action(p)
	var deck: Array = players(p).deck
	var top := []
	for i in mini(4, deck.size()):
		top.append(deck[deck.size() - 1 - i])
	var order := []
	var left := top.duplicate()
	while left.size() > 1:
		var pick = await g.pick_card(p, left, "Космическая Сова: какую карту положить %s?" %
			("наверх колоды" if order.is_empty() else "под неё"))
		if pick == null:
			pick = left[0]
		order.append(pick)
		left.erase(pick)
	order.append(left[0])
	for c in top:
		deck.erase(c)
	# The first pick goes on top, i.e. to the back of the array.
	order.reverse()
	deck.append_array(order)
	await say("%s перекладывает верхние карты колоды." % players(p).name)


# Охотница-волшебница
func _words(name: String) -> Array:
	var out := []
	var cur := ""
	for ch in name.to_lower() + " ":
		if ch.to_upper() != ch.to_lower():
			cur += ch
		elif cur != "":
			out.append(cur)
			cur = ""
	return out


func hero_setup_huntress_wizard(p) -> void:
	var counts := {}
	for c in players(p).deck + players(p).hand:
		var seen := {}
		for w: String in _words(c.card_name()):
			if w.length() >= 3 and not seen.has(w):
				seen[w] = true
				counts[w] = int(counts.get(w, 0)) + 1
	var words: Array = counts.keys()
	words.sort_custom(func(a, b): return counts[a] > counts[b] or (counts[a] == counts[b] and a < b))
	words = words.slice(0, 10)
	if words.is_empty():
		return
	var pick = await g.pick_option(p, words,
		"%s, Охотница-волшебница: выбери слово. Карты с ним в названии будут ранить врагов" % players(p).name)
	players(p).hero_state["word"] = String(pick)
	await say("Охотница-волшебница (%s) выбирает слово «%s»." % [players(p).name, pick])


func hero_played_huntress_wizard(p, c) -> void:
	var w: String = players(p).hero_state.get("word", "")
	if w == "" or not _words(c.card_name()).has(w):
		return
	var t = await g.pick_creature(p, g.foes(p), "Охотница-волшебница: «%s» — нанеси 1 урон существу соперника" % w)
	if t != null:
		await hit(t["p"], t["lane"], 1, p)


# Волшебник
func hero_played_magic_man_classic(p, c) -> void:
	if int(c.def()["cost"]) != 2:
		return
	var t = await g.pick_creature(p, g.foes(p), "Волшебник: «%s» стоит 2 — нанеси 2 урона существу соперника" %
		c.card_name())
	if t != null:
		await hit(t["p"], t["lane"], 2, p)


# Абракадэниел
func hero_power_ok_abracadaniel(p) -> bool:
	return players(p).actions >= 1 and not players(p).deck.is_empty()


func hero_power_abracadaniel(p) -> void:
	await _pay_action(p)
	var top = players(p).deck.back()
	await g.emit_event({"type": "reveal", "p": p, "uids": [top.uid]})
	if not g.is_type(top, "rainbow"):
		await say("Абракадэниел: сверху колоды «%s», не радужная карта — она остаётся на месте." % top.card_name())
		return
	await say("Абракадэниел: сверху радужная карта «%s» — играем её!" % top.card_name())
	if not await g.play_free(p, top, "Абракадэниел: куда сыграть «%s»?" % top.card_name()):
		await say("«%s» сыграть некуда — карта остаётся сверху." % top.card_name())


# Огненная Принцесса: once a game, every opposing creature burns.
func hero_power_ok_flame_princess(p) -> bool:
	return not players(p).hero_state.get("used", false) and not g.creature_opts(p, g.foes(p)).is_empty()


func hero_power_flame_princess(p) -> void:
	players(p).hero_state["used"] = true
	for o in g.foes(p):
		for l in LANES:
			if creature(o, l) != null:
				await g.burn_creature(p, o, l)


# Ферн: once a turn, after a replace the next creature of cost 1 this turn is free.
func hero_replaced_fern(p) -> void:
	if not _ready_once(p):
		return
	_use(p)
	players(p).turn["fern_free"] = true
	var uids: Array = players(p).turn.get("played_uids", [])
	players(p).turn["fern_by"] = uids.back() if not uids.is_empty() else -1
	await say("Ферн: следующее существо стоимостью 1 в этот ход бесплатно.")


func hero_cost_fern(p, c) -> int:
	if players(p).turn.get("fern_free", false) and c.uid != int(players(p).turn.get("fern_by", -1)) and c.kind() == "creature" and int(c.def()["cost"]) == 1:
		return -1
	return 0


func hero_played_fern(p, c) -> void:
	if c.uid == int(players(p).turn.get("fern_by", -1)):
		return
	if players(p).turn.get("fern_free", false) and c.kind() == "creature" and int(c.def()["cost"]) == 1:
		players(p).turn.erase("fern_free")


# Призмо (Kickstarter 2): once a turn, after 2 cards of different land types, an attack token.
func hero_power_ok_prismo(p) -> bool:
	return _ready_once(p) and g.played_types(p) >= 2 and g.creature_count(p) > 0


func hero_power_prismo(p) -> void:
	var t = await g.pick_creature(p, [p], "Призмо: на какое существо положить жетон атаки?", Callable(), true)
	if t == null:
		return
	_use(p)
	await g.add_atk_tokens(creature(p, t["lane"]))


# Мятный Дворецкий (Kickstarter 2): once a turn, with 1 card in hand or none, 2 damage to a creature.
func hero_power_ok_peppermint_butler(p) -> bool:
	return _ready_once(p) and players(p).hand.size() <= 1 and not g.creature_opts(p, g.sides()).is_empty()


func hero_power_peppermint_butler(p) -> void:
	var t = await g.pick_creature(p, g.sides(), "Мятный Дворецкий: какому существу 2 урона?", Callable(), true)
	if t == null:
		return
	_use(p)
	await hit(t["p"], t["lane"], 2, p)


# Волшебник (Kickstarter 2): discard a spell >>> draw a card, once a turn.
func _spell(c) -> bool:
	return c.kind() == "spell"


func hero_power_ok_magic_man(p) -> bool:
	return _ready_once(p) and players(p).hand.any(_spell)


func hero_power_magic_man(p) -> void:
	if await g.force_discard(p, 1, "Волшебник: сбрось заклинание, чтобы взять карту", _spell, true) == 0:
		return
	_use(p)
	await g._draw(p)


# ---------------------------------------------------------------- Промо, Kickstarter 1 и 2

# Огненная Принцесса (промо): as the Flame Princess of her deck.
func hero_power_ok_flame_princess_promo(p) -> bool:
	return hero_power_ok_flame_princess(p)


func hero_power_flame_princess_promo(p) -> void:
	await hero_power_flame_princess(p)


# Снежная Королева: in the opponents' turns, undamaged creatures +1 ATK.
func hero_atk_ice_queen(p, c, _lane) -> int:
	return 1 if g.turn_player != p and c.damage == 0 else 0


# Мяу-Мяу: the first exactly-1 damage to an opposing creature each turn removes the bottom card of a deck.
## «Не чаще одного раза за ход для каждого существа соперника»: once a turn per creature hit.
func hero_dmg1_me_mow(p, c) -> void:
	if g.turn_player != p:
		return
	var hit_uids: Array = players(p).turn.get("me_mow", [])
	if hit_uids.has(c.uid):
		return
	var o: int = await g.pick_foe(p, "Мяу-Мяу: чью нижнюю карту колоды убрать из игры?", func(q): return not players(q).deck.is_empty())
	if o < 0:
		return
	hit_uids.append(c.uid)
	players(p).turn["me_mow"] = hit_uids
	var x = players(o).deck.front()
	await g.remove_from_game(x)


# Крахмалик: once a turn, a creature from any discard pile leaves the game, draw a card.
func _dead_creatures() -> Array:
	var out := []
	for s in g.sides():
		out.append_array(players(s).discard.filter(func(x): return x.kind() == "creature"))
	return out


func hero_power_ok_starchy(p) -> bool:
	return _ready_once(p) and not _dead_creatures().is_empty()


func hero_power_starchy(p) -> void:
	var pick = await g.pick_card(p, _dead_creatures(), "Крахмалик: какое существо из сброса убрать из игры?", true)
	if pick == null:
		return
	_use(p)
	await g.remove_from_game(pick)
	await g._draw(p)


# Улитка
func hero_extra_draws_the_snail(p) -> int:
	var hp: int = players(p).hp
	return (1 if hp <= 15 else 0) + (1 if hp <= 5 else 0)


# Спонсор 10-летия: the first KICKSTARTER card of the turn shows the top card; a KICKSTARTER card is drawn.
func _ks(c) -> bool:
	return String(c.def().get("set", "")) in ["ks1", "ks2"]


func hero_played_kickstarter_backer(p, c) -> void:
	if g.turn_player != p or not _ks(c) or players(p).turn.get("backer", false) or players(p).deck.is_empty():
		return
	players(p).turn["backer"] = true
	var top = players(p).deck.back()
	await g.emit_event({"type": "reveal", "p": p, "uids": [top.uid]})
	if _ks(top):
		await say("Спонсор 10-летия: «%s» — карта Kickstarter, на руку." % top.card_name())
		await g._draw(p)


# Коричный Пончик: 2 damage to your creature >>> 2 HP, once a turn.
func hero_power_ok_cinnamon_bun(p) -> bool:
	return _ready_once(p) and g.creature_count(p) > 0


func hero_power_cinnamon_bun(p) -> void:
	var t = await g.pick_creature(p, [p], "Коричный Пончик: какому своему существу 2 урона?", Callable(), true)
	if t == null:
		return
	_use(p)
	await hit(p, t["lane"], 2, p)
	await g._check_state()
	await g.heal_player(p, 2)


# Смерть: turn your land face down >>> 4 damage to the opponent, once a turn.
func hero_power_ok_death(p) -> bool:
	return _ready_once(p) and range(LANES).any(func(l): return not players(p).lands[l]["flipped"])


func hero_power_death(p) -> void:
	var land = await g.pick_land(p, g.land_opts([p], func(_s, l): return not players(p).lands[l]["flipped"]), "Смерть: какую свою землю перевернуть?", true)
	if land == null:
		return
	_use(p)
	await g.flip_land(p, land["lane"], true)
	var o: int = await g.pick_foe(p, "Смерть: какому сопернику 4 урона?")
	if o >= 0:
		await g.damage_player(o, 4, null, {"kind": "effect", "p": p})


# Джеймс Бакстер: once in your turn draw; the opponent may draw too.
func hero_power_ok_james_baxter(p) -> bool:
	return _ready_once(p) and not players(p).deck.is_empty()


func hero_power_james_baxter(p) -> void:
	_use(p)
	await g._draw(p)
	for o in g.foes(p):
		if await g.pick_option(o, ["Взять карту", "Нет"], "Джеймс Бакстер: %s, взять карту?" % players(o).name) == "Взять карту":
			await g._draw(o)
		break


# НЕПТР: once in your turn the top card goes to the discard pile; a creature or a pie comes to the hand.
func hero_power_ok_neptr(p) -> bool:
	return _ready_once(p) and not players(p).deck.is_empty()


func hero_power_neptr(p) -> void:
	_use(p)
	var x = await g.mill(p)
	if x != null and (x.kind() == "creature" or _is_pie(x)):
		await say("НЕПТР: «%s» — на руку." % x.card_name())
		await g.return_to_hand(x)


# Бог Вечеринок: a creature that changes lanes +1 ATK this turn.
func hero_moved_party_god(_p, c) -> void:
	await g.buff(c, 1)


# Мятный Дворецкий (Kickstarter 1): once in your turn, when your creature leaves play, 2 damage to an opposing creature.
func hero_left_peppermint_butler_ks1(p, _c) -> void:
	if g.turn_player != p or not _ready_once(p) or g.creature_opts(p, g.foes(p)).is_empty():
		return
	_use(p)
	var t = await g.pick_creature(p, g.foes(p), "Мятный Дворецкий: какому существу соперника 2 урона?")
	if t != null:
		await hit(t["p"], t["lane"], 2, p)


# Лич (Kickstarter 1): destroy your creature >>> 1 action, once a turn.
func hero_power_ok_lich_ks1(p) -> bool:
	return _ready_once(p) and g.creature_count(p) > 0


func hero_power_lich_ks1(p) -> void:
	var t = await g.pick_creature(p, [p], "Лич: какое своё существо уничтожить ради действия?", Callable(), true)
	if t == null:
		return
	_use(p)
	await g.destroy_creature(p, t["lane"])
	await g.gain_actions(p, 1)


# Малыши Финн и Джейк: at the start of the fight phase one of your creatures +3 ATK.
func hero_battle_baby_finn_and_jake(p) -> void:
	if g.creature_count(p) == 0:
		return
	var t = await g.pick_creature(p, [p], "Малыши Финн и Джейк: какое существо получит +3 к атаке?")
	if t != null:
		await g.buff(creature(p, t["lane"]), 3)


# Банановый человек: once a turn, the bottom card of the deck is discarded or put on top.
func hero_power_ok_banana_man(p) -> bool:
	return _ready_once(p) and not players(p).deck.is_empty()


func hero_power_banana_man(p) -> void:
	_use(p)
	var deck: Array = players(p).deck
	var x = deck.front()
	await g.emit_event({"type": "peek", "p": p, "uids": [x.uid]})
	var pick = await g.pick_option(p, ["Наверх колоды", "Сбросить"], "Банановый человек: снизу «%s»." % x.card_name())
	deck.erase(x)
	if pick == "Сбросить":
		await g._to_discard(x, "deck")
	else:
		deck.append(x)


# Бетти: five different spells of cost 1 are set aside as Исследовательские заметки;
# 1 action >>> a random one is played for free, once a turn.
# Her deck is 5 cards over the minimum and the notes come out of it, so here the
# 40-card deck stays whole and the notes are copies of its 1-cost spells, filled up
# with 1-cost spells of her lands when the deck has fewer than 5 different ones.
func hero_setup_betty(p) -> void:
	var ids := []
	for x in players(p).deck:
		if x.kind() == "spell" and int(x.def()["cost"]) == 1 and not ids.has(x.id):
			ids.append(x.id)
	if ids.size() > 5:
		ids = ids.slice(0, 5)
	if ids.size() < 5:
		var types: Array = players(p).lands.map(func(l): return l["type"])
		var extra: Array = CardDB.pool_ids().filter(func(id):
			var d: Dictionary = CardDB.get_def(id)
			return d["kind"] == "spell" and int(d["cost"]) == 1 and not ids.has(id) \
				and (types.has(d.get("land", "")) or d.get("land", "") == "rainbow"))
		extra.sort()
		while ids.size() < 5 and not extra.is_empty():
			ids.append(extra.pop_at(g.rng.randi() % extra.size()))
	var notes: Array = ids.map(func(id): return g._make_card(id, p))
	players(p).hero_state["notes"] = notes
	if not notes.is_empty():
		await say("Бетти откладывает Исследовательские заметки: %d карт." % notes.size())


func hero_power_ok_betty(p) -> bool:
	return _ready_once(p) and players(p).actions >= 1 and not players(p).hero_state.get("notes", []).is_empty()


func hero_power_betty(p) -> void:
	var notes: Array = players(p).hero_state.get("notes", [])
	_use(p)
	await _pay_action(p)
	var x = notes[g.rng.randi() % notes.size()]
	notes.erase(x)
	players(p).hand.append(x)
	await say("Бетти: из заметок «%s»." % x.card_name())
	await g.emit_event({"type": "reveal", "p": p, "uids": [x.uid]})
	if not await g.play_free(p, x):
		players(p).hand.erase(x)
		notes.append(x)


# Гусь-выбирусь: a letter at the start; the first card of the turn with that letter costs 1 less.
func _first_letter(c) -> String:
	return c.card_name().substr(0, 1).to_upper()


func hero_setup_choose_goose(p) -> void:
	var counts := {}
	for x in players(p).deck + players(p).hand:
		counts[_first_letter(x)] = int(counts.get(_first_letter(x), 0)) + 1
	var letters: Array = counts.keys()
	letters.sort_custom(func(a, b): return counts[a] > counts[b])
	var pick = await g.pick_option(p, letters.slice(0, 10), "Гусь-выбирусь: выбери букву")
	players(p).hero_state["letter"] = String(pick)
	await say("Гусь-выбирусь (%s) выбирает букву «%s»." % [players(p).name, pick])


func hero_cost_choose_goose(p, c) -> int:
	if players(p).turn.get("goose_used", false) or g.turn_player != p:
		return 0
	return -1 if _first_letter(c) == String(players(p).hero_state.get("letter", "")) else 0


func hero_played_choose_goose(p, c) -> void:
	if _first_letter(c) == String(players(p).hero_state.get("letter", "")):
		players(p).turn["goose_used"] = true


# Принцесса-призрак: once a game, chosen players take 3 random cards of their discard pile,
# heal 2 for each creature among them and shuffle the rest of the pile into the deck.
func hero_power_ok_ghost_princess(p) -> bool:
	return not players(p).hero_state.get("used", false) and not players(p).discard.is_empty()


func hero_power_ghost_princess(p) -> void:
	players(p).hero_state["used"] = true
	for s in g.seats_from(p):
		if players(s).discard.is_empty():
			continue
		if s != p and await g.pick_option(p, ["Да", "Нет"], "Принцесса-призрак: и для %s тоже?" % players(s).name) != "Да":
			continue
		var pile: Array = players(s).discard
		var heal := 0
		for i in mini(3, pile.size()):
			var x = pile[g.rng.randi() % pile.size()]
			await g.return_to_hand(x)
			if x.kind() == "creature":
				heal += 2
		for x in pile.duplicate():
			pile.erase(x)
			players(s).deck.append(x)
		await g.shuffle_deck(s)
		if heal > 0:
			await g.heal_player(s, heal)


# Гроб Гоб Глоб Грод: 4 creatures with a combined cost of 8 or more: +3 ATK in your turn.
func hero_atk_grob_gob_glob_grod(p, _c, _lane) -> int:
	if g.turn_player != p or g.creature_count(p) < 4:
		return 0
	var total := 0
	for l in LANES:
		total += int(creature(p, l).def()["cost"])
	return 3 if total >= 8 else 0


# Принцесса Хот-Дог
func hero_start_hot_dog_princess(p) -> void:
	for l in LANES:
		var x = creature(p, l)
		if x != null and x.damage >= 5:
			await g.add_atk_tokens(x)


# Мистер Лис: once a turn the top card is shown; a card of cost 0 may go to the hand.
func hero_power_ok_mr_fox(p) -> bool:
	return _ready_once(p) and not players(p).deck.is_empty()


func hero_power_mr_fox(p) -> void:
	_use(p)
	var top = players(p).deck.back()
	await g.emit_event({"type": "reveal", "p": p, "uids": [top.uid]})
	await say("Мистер Лис: сверху «%s»." % top.card_name())
	if int(top.def()["cost"]) == 0 and await g.pick_option(p, ["Взять на руку", "Оставить"], "Мистер Лис: взять «%s»?" % top.card_name()) == "Взять на руку":
		await g._draw(p)


# Принцесса Мускулов: 1 action >>> an attack token and/or an opposing creature moved to an empty land, once a turn.
func hero_power_ok_muscle_princess(p) -> bool:
	return _ready_once(p) and players(p).actions >= 1 and (g.creature_count(p) > 0 or not g.creature_opts(p, g.foes(p)).is_empty())


func hero_power_muscle_princess(p) -> void:
	_use(p)
	await _pay_action(p)
	if g.creature_count(p) > 0:
		var t = await g.pick_creature(p, [p], "Принцесса Мускулов: на какое существо жетон атаки?", Callable(), true)
		if t != null:
			await g.add_atk_tokens(creature(p, t["lane"]))
	var f = await g.pick_creature(p, g.foes(p), "Принцесса Мускулов: передвинуть существо соперника?",
		func(_x, s, _l): return not g.empty_lanes(s).is_empty(), true)
	if f != null:
		var dest: int = await g.pick_lane(p, f["p"], g.empty_lanes(f["p"]), "Принцесса Мускулов: на какую пустую землю?")
		if dest >= 0:
			await g.move_creature(f["p"], f["lane"], dest)


# Саймон Петриков: the first frost token removed in a turn draws a card.
func hero_thaw_simon_petrikov(p, _side) -> void:
	var t: Dictionary = players(g.turn_player).turn
	if t.get("simon_%d" % p, false) or g.phase == "setup":
		return
	t["simon_%d" % p] = true
	await say("Саймон Петриков: %s берёт карту." % players(p).name)
	await g._draw(p)


# Олень: discard 3 cards >>> an opposing creature leaves the game if your creature of its lane has more DEF.
func _stag_targets(p: int) -> Callable:
	return func(_x, s, l):
		var a: Array = g.across(s, l)
		return a[0] == p and creature(p, a[1]) != null and g.def_of(p, a[1]) > g.def_of(s, l)


func hero_power_ok_the_stag(p) -> bool:
	return _ready_once(p) and players(p).hand.size() >= 3 and not g.creature_opts(p, g.foes(p), _stag_targets(p)).is_empty()


func hero_power_the_stag(p) -> void:
	var t = await g.pick_creature(p, g.foes(p), "Олень: какое существо соперника убрать из игры?", _stag_targets(p), true)
	if t == null:
		return
	_use(p)
	await g.force_discard(p, 3, "Олень: сбрось 3 карты")
	var x = creature(t["p"], t["lane"])
	if x != null:
		g.players[t["p"]].creatures[t["lane"]] = null
		await say("Олень: «%s» убран из игры." % x.card_name())
		await g._leave_play(x, t["p"], t["lane"], "creature", "remove", "removed")


# Принцесса Черепах: attack tokens of her creatures may stop as much damage.
func hero_prevent_turtle_princess(p, c, amount) -> int:
	var have: int = g.tokens(c, "atk_tok")
	var most: int = mini(have, amount)
	var opts := []
	for n in range(most, 0, -1):
		opts.append("Убрать %d" % n)
	opts.append("Не убирать")
	var pick = await g.pick_option(p, opts, "Принцесса Черепах: убрать жетоны атаки с «%s», чтобы предотвратить урон (%d)?" % [c.card_name(), amount])
	if pick == "Не убирать" or pick == null:
		return 0
	var n := int(String(pick).get_slice(" ", 1))
	await g.remove_token(c, "atk_tok", n)
	return n


# Король вампиров: damage his player removes from a creature may go to any creature instead.
func hero_heal_vampire_king(p, c, _side, _lane, n) -> bool:
	var t = await g.pick_creature(p, g.sides(), "Король вампиров: нанести %d урона существу вместо того, чтобы снять его с «%s»?" % [n, c.card_name()], Callable(), true)
	if t == null:
		return false
	var x = creature(t["p"], t["lane"])
	await say("Король вампиров: урон с «%s» не снят, %d урона получает «%s»." % [c.card_name(), n, x.card_name()])
	await g.damage_creature(t["p"], t["lane"], n, {"kind": "effect", "p": p})
	return true

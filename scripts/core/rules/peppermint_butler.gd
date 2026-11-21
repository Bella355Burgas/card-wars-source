extends "res://scripts/core/rules/base.gd"
## Мятный Дворецкий (Бесполезные болота и Лавовые равнины): почти пустая рука (1 карта или
## меньше) и сброс карт ради выгоды.


func _low(p: int) -> bool:
	return players(p).hand.size() <= 1


func _low_players() -> int:
	return g.sides().filter(func(s): return _low(s)).size()


func _all_creatures(p: int) -> bool:
	return not g.creature_opts(p, g.sides()).is_empty()


## Played for free from the discard pile when discarded from the hand (Призыв слизи, Болотуко).
func _replay(c, p: int) -> void:
	if await g.pick_option(p, ["Сыграть бесплатно", "Нет"], "«%s» сброшена. Сыграть её бесплатно?" % c.card_name()) == "Сыграть бесплатно":
		await g.play_free(p, c)


# Пиявкунай (cost: discard, once a turn)
func act_ok_bulkunai_the_leech(c, _p, _kind, _lane) -> bool:
	return c.damage > 0


func act_bulkunai_the_leech(_c, p, _kind, lane) -> void:
	await g.heal_creature(p, lane, 3)


# День подарков
func spell_boxing_day(_c, p) -> void:
	for l in LANES:
		if creature(p, l) != null:
			await g.add_atk_tokens(creature(p, l))


# Расплавленный ритуалист
func floop_molten_ritualist(_c, p, _kind, _lane) -> void:
	for s in g.seats_from(p):
		if _low(s):
			await g._draw(s)


# Грязатана Эксплуататор
func atk_muckatana_the_exploiter(_c, _p, _lane) -> int:
	return 2 * _low_players()


# Мушкагинава Свободный
func cost_mushkaginawa_the_free(c, p) -> int:
	return -2 if players(p).hand.size() == 1 and players(p).hand[0] == c else 0


# Обжигающее озарение
func playable_searing_insight(_c, p) -> bool:
	return _all_creatures(p)


func spell_searing_insight(_c, p) -> void:
	var t = await g.pick_creature(p, g.sides(), "Обжигающее озарение: какое существо поджечь?")
	if t != null:
		await g.burn_creature(p, t["p"], t["lane"])
	if _low(p):
		await g.draw_cards(p, 3)


# Призыв слизи
func spell_summon_sludge(_c, p) -> void:
	await hit_foes(p, 2)


func discarded_hand_summon_sludge(c, p) -> void:
	await _replay(c, p)


# Болотуко Преследователь
func discarded_hand_marshuko_the_stalker(c, p) -> void:
	await _replay(c, p)


# Времятрон
func enter_timematron(_c, p, _lane) -> void:
	await g.force_discard(p, 2, "Времятрон: сбрось 2 карты")


func leave_timematron(_c, p, _lane, _reason, _info) -> void:
	await g.draw_cards(p, 2)


# Испытание огнём: of the top two cards one is discarded (or taken), the other played for free.
func spell_trial_by_fire(_c, p) -> void:
	var deck: Array = players(p).deck
	if deck.is_empty():
		return
	var cards := [deck[deck.size() - 1]]
	if deck.size() >= 2:
		cards.append(deck[deck.size() - 2])
	await g.emit_event({"type": "reveal", "p": p, "uids": cards.map(func(x): return x.uid)})
	var play_it = cards[0]
	if cards.size() == 2:
		play_it = await g.pick_card(p, cards, "Испытание огнём: какую карту сыграть бесплатно? (другая уйдёт в сброс)")
		if play_it == null:
			play_it = cards[0]
	var dropped = null
	for x in cards:
		if x == play_it:
			continue
		deck.erase(x)
		if _low(p) and await g.pick_option(p, ["Взять на руку", "Сбросить"], "Испытание огнём: «%s» — взять на руку?" % x.card_name()) == "Взять на руку":
			players(p).hand.append(x)
			await g.emit_event({"type": "to_hand", "p": p, "uid": x.uid, "from": "deck"})
		else:
			await g._to_discard(x, "deck")
			dropped = x
	if not await g.play_free(p, play_it, "Испытание огнём: куда сыграть «%s»?" % play_it.card_name()):
		await say("«%s» сыграть нельзя — карта остаётся сверху." % play_it.card_name())
	# You discard it yourself: Болотуко, Призыв слизи may be played for free, once the spell is done.
	if dropped != null and g.where(dropped.uid)["zone"] == "discard" and g.phase != "over" \
			and g._hooks.has("discarded_hand_" + dropped.ab()):
		await g.run_hook("discarded_hand_" + dropped.ab(), [dropped, p])


# Пламинго — хранитель пепла
func enter_flameingo_ash_keeper(_c, p, _lane) -> void:
	if players(p).hand.is_empty() or g.creature_opts(p, g.foes(p)).is_empty():
		return
	if await g.force_discard(p, 1, "Хранитель пепла: сбросить карту, чтобы поджечь существо соперника?", Callable(), true) == 0:
		return
	var t = await g.pick_creature(p, g.foes(p), "Хранитель пепла: какое существо соперника поджечь?")
	if t != null:
		await g.burn_creature(p, t["p"], t["lane"])


# Блестящая вспышка (the end of the turn: Game._end_turn)
func spell_brilliant_flare(_c, p) -> void:
	await g.draw_cards(p, 5)
	players(p).turn["flare"] = true


# Лавовые миноги (cost: discard)
func act_ok_lava_lamprey_eels(_c, p, _kind, _lane) -> bool:
	return _all_creatures(p)


func act_lava_lamprey_eels(_c, p, _kind, _lane) -> void:
	var t = await g.pick_creature(p, g.sides(), "Лавовые миноги: какое существо поджечь?")
	if t != null:
		await g.burn_creature(p, t["p"], t["lane"])


# Светлячок-фонарщик: with 1 card in hand or none the top card of the deck lies open and is
# played like a card from the hand, as with Рентгеновские очки (Game.xray_top, Game.cost_of).


# Волшебник пустошей
func enter_wasteland_wizard(_c, p, _lane) -> void:
	await g.force_discard(p, 1, "Волшебник пустошей: сбрось карту")


# Некромаг
func enter_necromagus(_c, p, _lane) -> void:
	for s in g.seats_from(p):
		var pool: Array = g.discard_pool(s, func(x): return x.kind() == "creature")
		if pool.is_empty():
			continue
		var pick = await g.pick_card(s, pool, "Некромаг: %s, какое существо из сброса взять на руку?" % players(s).name)
		if pick != null:
			await g.return_to_hand(pick)


# Удивлённый стригаль
func floop_ok_surprised_shearer(c, p, _kind, _lane) -> bool:
	return not g.creature_opts(p, g.sides(), func(x, _s, _l): return x != c).is_empty()


func floop_surprised_shearer(c, p, _kind, _lane) -> void:
	var t = await g.pick_creature(p, g.sides(), "Удивлённый стригаль: какому существу 2 урона?", func(x, _s, _l): return x != c)
	if t == null:
		return
	await hit(t["p"], t["lane"], 2, p)
	await g._draw(int(t["p"]))
	await g._check_state()


# Сумракама Предатель
func enter_duskama_the_betrayer(_c, p, _lane) -> void:
	for s in g.seats_from(p):
		if players(s).hand.is_empty() or g.creature_count(s) == 0:
			continue
		if await g.force_discard(s, 1, "Сумракама: %s, сбросить карту ради жетона атаки?" % players(s).name, Callable(), true) == 0:
			continue
		var t = await g.pick_creature(s, [s], "Сумракама: на какое своё существо жетон атаки?")
		if t != null:
			await g.add_atk_tokens(creature(s, t["lane"]))


# Фенунчаку Отступник
func enter_fenunchaku_the_renegade(_c, p, _lane) -> void:
	for x in players(p).hand.duplicate():
		await g.discard_card(p, x)


# Испепеление
func playable_incinerate(_c, p) -> bool:
	return _all_creatures(p)


func spell_incinerate(_c, p) -> void:
	var n := 5 if _low(p) else 2
	var t = await g.pick_creature(p, g.sides(), "Испепеление: %d урона выбранному существу" % n)
	if t != null:
		await hit(t["p"], t["lane"], n, p)


# Тройная угроза
func playable_triple_threat(_c, p) -> bool:
	return _all_creatures(p)


func spell_triple_threat(_c, p) -> void:
	var t = await g.pick_creature(p, g.sides(), "Тройная угроза: на какое существо 3 жетона атаки?")
	if t != null:
		await g.add_atk_tokens(creature(t["p"], t["lane"]), 3)
	await g.force_discard(p, 1, "Тройная угроза: сбрось карту")


# Храм факела
func floop_ok_temple_of_the_torch(_c, p, _kind, lane) -> bool:
	return not g.creature_opts(p, g.sides(), func(_x, s, l): return g.bld_on_lane(p, lane, s, l)).is_empty()


func floop_temple_of_the_torch(_c, p, _kind, lane) -> void:
	var t = await g.pick_creature(p, g.sides(), "Храм факела: какое существо в этой зоне поджечь?",
		func(_x, s, l): return g.bld_on_lane(p, lane, s, l))
	if t != null:
		await g.burn_creature(p, t["p"], t["lane"], 2 if _low(p) else 1)


# Общинная кузница
func aura_atk_community_forge(_src, sp, slane, _c, p, lane) -> int:
	return 2 if g.on_lane(sp, slane, p, lane) else 0

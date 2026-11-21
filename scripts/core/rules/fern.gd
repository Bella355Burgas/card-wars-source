extends "res://scripts/core/rules/base.gd"
## Ферн (Добрые земли и Кукурузные поля): початкогоблины с «Хрум» (Game.gobbles: a replaced
## one goes under the new creature, which gains its ATK, DEF and tokens) and броненосцы с «Бух»
## (Game.cost_of: a creature replaced by one makes it cheaper by its cost).


func _with_tokens() -> Callable:
	return func(x, _s, _l): return g.non_damage_tokens(x) > 0


func _friendly(p: int) -> Array:
	return [p] if not g.teams() else [p, (p + 2) % 4]


# Обожаемый початкогоблин
func floop_adored_cobnoblin(_c, p, _kind, _lane) -> void:
	g.add_turn(p, "creature_discount", 1)
	await say("Следующее существо игрока %s стоит на 1 меньше." % players(p).name)


# Заветный початкогоблин: 1 or 2 tokens off a creature, as many attack tokens on a friendly one.
func floop_ok_cherished_cobnoblin(_c, p, _kind, _lane) -> bool:
	return not g.creature_opts(p, g.sides(), _with_tokens()).is_empty()


func floop_cherished_cobnoblin(_c, p, _kind, _lane) -> void:
	var t = await g.pick_creature(p, g.sides(), "Заветный початкогоблин: с какого существа убрать жетоны?", _with_tokens())
	if t == null:
		return
	var x = creature(t["p"], t["lane"])
	var n := 1
	if g.non_damage_tokens(x) >= 2:
		n = 2 if await g.pick_option(p, ["Убрать 2", "Убрать 1"], "Заветный початкогоблин: сколько жетонов убрать?") == "Убрать 2" else 1
	var done := 0
	for i in n:
		if await take_token(p, x) != "":
			done += 1
	var f = await g.pick_creature(p, _friendly(p), "Заветный початкогоблин: на какое своё существо положить жетоны атаки (%d)?" % done)
	if f != null and done > 0:
		await g.add_atk_tokens(creature(f["p"], f["lane"]), done)


# Милый початкогоблин
func floop_ok_darling_cobnoblin(_c, p, _kind, _lane) -> bool:
	return g.creature_count(p) > 0


func floop_darling_cobnoblin(_c, p, _kind, _lane) -> void:
	var f = await g.pick_creature(p, _friendly(p), "Милый початкогоблин: на какое существо положить жетон атаки?")
	if f != null:
		await g.add_atk_tokens(creature(f["p"], f["lane"]))


# Драгоценный початкогоблин
func floop_ok_precious_cobnoblin(_c, p, _kind, _lane) -> bool:
	return not g.creature_opts(p, _friendly(p)).is_empty()


func floop_precious_cobnoblin(_c, p, _kind, _lane) -> void:
	var f = await g.pick_creature(p, _friendly(p), "Драгоценный початкогоблин: какое своё существо?")
	if f == null:
		return
	var x = creature(f["p"], f["lane"])
	var opts := ["Снять 2 урона"]
	if g.non_damage_tokens(x) > 0:
		opts.append("Убрать жетон")
	var pick = await g.pick_option(p, opts, "Драгоценный початкогоблин: что сделать с «%s»?" % x.card_name())
	if pick == "Снять 2 урона":
		await g.heal_creature(f["p"], f["lane"], 2, p)
	else:
		await take_token(p, x)


# Драгоценнейший початкогоблин
func floop_treasured_cobnoblin(_c, p, _kind, _lane) -> void:
	await g._draw(p)


# Рыцарственный броненосец
func enter_chivalrous_armourdillo(c, p, _lane) -> void:
	var t = await g.pick_creature(p, g.sides(), "Рыцарственный броненосец: снять 3 урона с другого существа?",
		func(x, _s, _l): return x != c, true)
	if t == null:
		return
	await g.heal_creature(t["p"], t["lane"], 3, p)
	var x = creature(t["p"], t["lane"])
	if x != null and x.damage > 0:
		await g._draw(p)


# Отважный броненосец
func killed_courageous_armourdillo(_c, p, _lane, _victim, _vp, _vlane) -> void:
	await g.heal_player(p, 2)
	var o: int = await g.pick_foe(p, "Отважный броненосец: какому сопернику 2 урона?")
	if o >= 0:
		await g.damage_player(o, 2, null, {"kind": "effect", "p": p})


# Кенгуру-мышь
func dealt_kangaroo_bat(c, _p, _lane, _amount, target) -> void:
	if target == "player":
		await g.add_atk_tokens(c)


# Утончённый броненосец: free after a creature of cost 2 or more this turn.
func cost_refined_armourdillo(c, p) -> int:
	for id in g.turn_value(p, "played", []):
		var d: Dictionary = CardDB.get_def(id)
		if d["kind"] == "creature" and int(d["cost"]) >= 2:
			return -int(c.def()["cost"])
	return 0


# Доблестный броненосец
func enter_valiant_armourdillo(c, p, lane) -> void:
	if c.flags.get("from_hand", false) and opposite_open(p, lane):
		var a: Array = g.across(p, lane)
		await g.destroy_creature(a[0], a[1])


# Красноречивый броненосец
func enter_eloquent_armourdillo(c, _p, _lane) -> void:
	if c.flags.get("replaced", false):
		await g.add_atk_tokens(c)


# Галантный броненосец: the top card of the deck is played for free.
func enter_gallant_armourdillo(c, p, _lane) -> void:
	if not c.flags.get("replaced", false) or players(p).deck.is_empty():
		return
	var top = players(p).deck.back()
	await say("Галантный броненосец: сверху колоды «%s»." % top.card_name())
	await g.emit_event({"type": "reveal", "p": p, "uids": [top.uid]})
	if not await g.play_free(p, top, "Галантный броненосец: куда сыграть «%s»?" % top.card_name()):
		await say("«%s» сыграть нельзя — карта остаётся сверху." % top.card_name())


# Носорог: the first card played this turn.
func enter_rhinoceros(c, p, _lane) -> void:
	if c.flags.get("from_hand", false) and g.turn_value(p, "played", []).size() == 1:
		await g.add_atk_tokens(c)


# Травяные метатели
func spell_herbal_hurlers(_c, p) -> void:
	players(p).turn["herbal"] = true
	await say("В этот ход существа игрока %s лечатся на нанесённый урон." % players(p).name)


# Эмблема чемпиона
func playable_champions_emblem(_c, p) -> bool:
	return not g.creature_opts(p, g.sides()).is_empty()


func spell_champions_emblem(_c, p) -> void:
	var t = await g.pick_creature(p, g.sides(), "Эмблема чемпиона: с какого существа снять 3 урона?")
	if t == null:
		return
	await g.heal_creature(t["p"], t["lane"], 3, p)
	if creature(t["p"], t["lane"]).damage > 0:
		await g.gain_actions(p, 1)


# Тотем ярости
func playable_ragepop_totem(_c, p) -> bool:
	return g.creature_count(p) > 0


func spell_ragepop_totem(_c, p) -> void:
	var t = await g.pick_creature(p, _friendly(p), "Тотем ярости: какое существо получит +2 к атаке?")
	if t != null:
		var x = creature(t["p"], t["lane"])
		await g.buff(x, 2)
		x.flags["ragepop"] = g.turn_number


# Обновление зерна
func playable_kernel_renewal(_c, p) -> bool:
	return not g.creature_opts(p, [p], func(x, _s, _l): return x.damage > 0).is_empty()


func spell_kernel_renewal(_c, p) -> void:
	var src = await g.pick_creature(p, [p], "Обновление зерна: урон какого своего существа взять?",
		func(x, _s, _l): return x.damage > 0)
	if src == null:
		return
	var n: int = creature(p, src["lane"]).damage
	var t = await g.pick_creature(p, g.sides(), "Обновление зерна: %d урона выбранному существу" % n)
	if t != null:
		await hit(t["p"], t["lane"], n, p)


# Священная коса
func playable_sacred_scythe(_c, p) -> bool:
	return not g.creature_opts(p, g.sides()).is_empty()


func spell_sacred_scythe(_c, p) -> void:
	var t = await g.pick_creature(p, g.sides(), "Священная коса: какое существо уничтожить?")
	if t == null:
		return
	var owner: int = creature(t["p"], t["lane"]).owner
	await g.destroy_creature(t["p"], t["lane"])
	await g.heal_player(owner, 5)


# Башня жизни
func start_lifeward_tower(_c, p, _kind, lane) -> void:
	for l in bld_targets(p, lane):
		var x = creature(p, l)
		if x != null and await g.heal_creature(p, l, 1) > 0:
			await say("Башня жизни: с «%s» снят 1 урон." % x.card_name())


# Мшистое убежище: a token off a friendly creature or a frost token off p's land.
func start_mossglen_retreat(_c, p, _kind, _lane) -> void:
	var opts := []
	if not g.creature_opts(p, _friendly(p), _with_tokens()).is_empty():
		opts.append("С существа")
	if g.frozen_count(p) > 0:
		opts.append("Жетон мороза с земли")
	if opts.is_empty():
		return
	var pick = await g.pick_option(p, opts + ["Ничего"], "Мшистое убежище: убрать жетон?")
	if pick == "С существа":
		var t = await g.pick_creature(p, _friendly(p), "Мшистое убежище: с какого существа?", _with_tokens())
		if t != null:
			await take_token(p, creature(t["p"], t["lane"]))
	elif pick == "Жетон мороза с земли":
		var land = await g.pick_land(p, g.land_opts([p], func(s, l): return g.is_frozen(s, l)), "Мшистое убежище: с какой земли?")
		if land != null:
			await g.thaw(land["p"], land["lane"])


# Резонансная твердыня чар: a creature played into this lane brings back a cheaper spell.
func sees_enter_resonant_spellhold(_src, sp, _skind, slane, _c, p, lane) -> bool:
	return p == sp and lane == slane and p == g.turn_player


func on_enter_resonant_spellhold(_src, _sp, _skind, _slane, c, p, _lane) -> void:
	var n: int = c.def()["cost"]
	var pool: Array = g.discard_pool(p, func(x): return x.kind() == "spell" and int(x.def()["cost"]) < n)
	if pool.is_empty():
		return
	var pick = await g.pick_card(p, pool, "Резонансная твердыня чар: вернуть на руку заклинание?", true)
	if pick != null:
		await g.return_to_hand(pick)


# Амбар вознесения: once a turn.
func on_leave_ascension_silo(src, sp, _skind, slane, c, p, lane, _reason) -> void:
	if not g.bld_own_lane(sp, slane, p, lane, c) or int(src.flags.get("silo_turn", -1)) == g.turn_number:
		return
	src.flags["silo_turn"] = g.turn_number
	await say("Амбар вознесения: %s берёт карту." % players(sp).name)
	await g._draw(sp)

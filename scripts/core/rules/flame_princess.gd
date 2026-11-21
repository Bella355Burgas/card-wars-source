extends "res://scripts/core/rules/base.gd"
## Огненная Принцесса (Лавовые равнины): жетоны огня. A burning creature takes 1 damage for
## each burn token at the start of its controller's turn (Game.burn_creature, Game._burn_damage).


func _burning() -> Callable:
	return func(x, _s, _l): return g.burning(x)


# Жаркие кольца
func playable_broils_coils(_c, p) -> bool:
	return not g.creature_opts(p, g.sides()).is_empty()


func spell_broils_coils(_c, p) -> void:
	var t = await g.pick_creature(p, g.sides(), "Жаркие кольца: 3 урона выбранному существу")
	if t == null:
		return
	var victim = creature(t["p"], t["lane"])
	await hit(t["p"], t["lane"], 3, p)
	await g._check_state()
	if g.where(victim.uid)["zone"] != "creature":
		await g.gain_actions(p, 1)


# Меткий выстрел
func playable_hot_shot(_c, p) -> bool:
	return not g.creature_opts(p, g.sides()).is_empty()


func spell_hot_shot(_c, p) -> void:
	var t = await g.pick_creature(p, g.sides(), "Меткий выстрел: какое существо поджечь?")
	if t != null:
		await g.burn_creature(p, t["p"], t["lane"])
		await hit(t["p"], t["lane"], 1, p)


# Расплавленное зелье
func playable_molten_potion(_c, p) -> bool:
	return not g.creature_opts(p, g.sides()).is_empty()


func spell_molten_potion(_c, p) -> void:
	var t = await g.pick_creature(p, g.sides(), "Расплавленное зелье: какое существо поджечь?")
	if t != null:
		await g.burn_creature(p, t["p"], t["lane"])
	await hit_foes(p, 2, func(x, _s, _l): return g.burning(x))


# Амулет погибели титанов
func playable_titanbane_amulet(_c, p) -> bool:
	return not g.creature_opts(p, g.sides()).is_empty()


func spell_titanbane_amulet(_c, p) -> void:
	var t = await g.pick_creature(p, g.sides(), "Амулет погибели титанов: какое существо уничтожить?")
	if t == null:
		return
	var n: int = g.atk_of(t["p"], t["lane"])
	await g.destroy_creature(t["p"], t["lane"])
	await g.lose_hp(p, n, "Амулет погибели титанов")


# Вулканическая живость: each opposing creature gets as many burn tokens again.
func spell_volcanic_vitality(_c, p) -> void:
	for o in g.foes(p):
		for l in LANES:
			var x = creature(o, l)
			if g.burning(x):
				await g.burn_creature(p, o, l, g.tokens(x, "burn"))


# Уютная печь
func on_leave_cozy_kiln(_src, sp, _skind, slane, c, p, lane, _reason) -> void:
	if g.is_foe(sp, p) and g.on_lane(sp, slane, p, lane) and int(g.leaving.get("flags", {}).get("burn", 0)) > 0:
		await say("Уютная печь: %s загорается." % players(c.owner).name)
		await g.burn_player(sp, c.owner)


# Горячие хижины
func on_burn_hot_huts(_src, sp, _skind, _slane, by_p, side, lane, _c) -> void:
	if by_p == sp and g.is_foe(sp, side):
		await hit(side, lane, 1, sp)


# Крепость пиропара: FLOOP and remove a burn token from a creature >>> 3 damage to it.
func floop_ok_pyrovent_fortress(_c, p, _kind, _lane) -> bool:
	return not g.creature_opts(p, g.sides(), _burning()).is_empty()


func floop_pyrovent_fortress(_c, p, _kind, _lane) -> void:
	var t = await g.pick_creature(p, g.sides(), "Крепость пиропара: убери жетон огня с существа — 3 урона ему", _burning())
	if t != null:
		await g.remove_token(creature(t["p"], t["lane"]), "burn")
		await hit(t["p"], t["lane"], 3, p)


# Врата палящего камня (FLOOP and pay 1 action)
func floop_ok_scorchstone_gateway(_c, p, _kind, lane) -> bool:
	return not g.creature_opts(p, g.sides(), func(_x, s, l): return g.bld_on_lane(p, lane, s, l)).is_empty()


func floop_scorchstone_gateway(_c, p, _kind, lane) -> void:
	var t = await g.pick_creature(p, g.sides(), "Врата палящего камня: какое существо в этой зоне поджечь?",
		func(_x, s, l): return g.bld_on_lane(p, lane, s, l))
	if t != null:
		await g.burn_creature(p, t["p"], t["lane"])


# Пламинго-огнестраж: remove a burn token from an opposing creature >>> 1 damage to an opponent.
func act_ok_flameingo_burnwarden(_c, p, _kind, _lane) -> bool:
	return not g.creature_opts(p, g.foes(p), _burning()).is_empty()


func act_flameingo_burnwarden(_c, p, _kind, _lane) -> void:
	var t = await g.pick_creature(p, g.foes(p), "Пламинго-огнестраж: с какого существа соперника убрать жетон огня?", _burning())
	if t == null:
		return
	await g.remove_token(creature(t["p"], t["lane"]), "burn")
	var o: int = await g.pick_foe(p, "Пламинго-огнестраж: какому сопернику 1 урон?")
	if o >= 0:
		await g.damage_player(o, 1, null, {"kind": "effect", "p": p})


# Пламинго-огнеплёт: every creature in the chosen lane burns.
func floop_flameingo_flameweaver(_c, p, _kind, _lane) -> void:
	var dest: int = await g.pick_lane(p, p, range(LANES), "Пламинго-огнеплёт: в какой зоне поджечь существ?")
	if dest < 0:
		return
	for s in g.lane_spots(p, dest):
		if creature(s[0], s[1]) != null:
			await g.burn_creature(p, s[0], s[1])


# Пламинго-сорвиголова
func attack_flameingo_hotshot(c, p, lane) -> void:
	if not g.burning(opposite(p, lane)):
		return
	var a: Array = g.across(p, lane)
	var t = await g.pick_creature(p, g.sides(), "Пламинго-сорвиголова: нанести 2 урона другому существу?",
		func(x, s, l): return x != c and not (s == a[0] and l == a[1]), true)
	if t == null:
		return
	var x = creature(t["p"], t["lane"])
	var was: bool = g.burning(x)
	await hit(t["p"], t["lane"], 2, p)
	if not was and g.where(x.uid)["zone"] == "creature":
		var w: Dictionary = g.where(x.uid)
		await g.burn_creature(p, w["p"], w["lane"])
	await g._check_state()


# Пламинго-капитан
func dealt_flameingo_captain(_c, p, _lane, _amount, target) -> void:
	if target == "player":
		await g.burn_player(p, int(g.dealt_to["p"]))


# Пламинго — вождь огнепёрых
func cost_flameingo_fireplume_chief(_c, _p) -> int:
	return -g.burn_tokens_in_play()


func dealt_flameingo_fireplume_chief(_c, p, _lane, _amount, target) -> void:
	if target == "creature":
		await _burn_hit(p, false)


# Пламинго-искорка: only a creature that was not burning yet.
func dealt_flameingo_blazeling(_c, p, _lane, _amount, target) -> void:
	if target == "creature":
		await _burn_hit(p, true)


func _burn_hit(p: int, only_new: bool) -> void:
	var x = g.dealt_to.get("card")
	if x == null or (only_new and g.burning(x)):
		return
	var w: Dictionary = g.where(x.uid)
	if w["zone"] == "creature":
		await g.burn_creature(p, w["p"], w["lane"])


# Пламинго-жаропожиратель: the first burn of the turn draws.
func on_burn_flameingo_heat_eater(_src, sp, _skind, _slane, by_p, _side, _lane, _c) -> void:
	if by_p == sp and int(g.turn_value(sp, "burned")) == 1:
		await say("Пламинго-жаропожиратель: %s берёт карту." % players(sp).name)
		await g._draw(sp)


# Жаропрыги
func on_burn_heat_leapers(src, sp, _skind, _slane, by_p, _side, _lane, _c) -> void:
	if by_p == sp:
		await g.add_atk_tokens(src)


# Горячее колесо: draw and show a card, burn a creature in this lane as many times as it costs.
func act_hot_wheel(_c, p, _kind, lane) -> void:
	if players(p).deck.is_empty():
		return
	await g._draw(p)
	var drawn = players(p).hand.back()
	await say("Горячее колесо: %s открывает «%s»." % [players(p).name, drawn.card_name()])
	await g.emit_event({"type": "reveal", "p": p, "uids": [drawn.uid]})
	var n: int = drawn.def()["cost"]
	if n <= 0:
		return
	var t = await g.pick_creature(p, g.sides(), "Горячее колесо: какое существо в этой зоне поджечь (%d)?" % n,
		func(_x, s, l): return g.on_lane(p, lane, s, l))
	if t != null:
		await g.burn_creature(p, t["p"], t["lane"], n)


# Яростный феникс
func atk_furious_phoenix(_c, _p, _lane) -> int:
	return g.burn_tokens_in_play()


# Огненный пёс
func enter_fire_dog(_c, p, _lane) -> void:
	var n: int = g.burn_tokens_in_play()
	if n <= 0:
		return
	var t = await g.pick_creature(p, g.sides(), "Огненный пёс: нанести %d урона выбранному существу?" % n, Callable(), true)
	if t != null:
		await hit(t["p"], t["lane"], n, p)
		await g._check_state()


# Свампир, свин ночи
func attack_hampire_pig_of_the_night(_c, p, lane) -> void:
	var n: int = g.atk_of(p, lane)
	if n > 0:
		await g.heal_player(p, n)


# Кенгуру-кот: the first time only (while it is in play).
func dealt_kangaroo_cat(c, _p, _lane, _amount, target) -> void:
	if target == "player" and not c.flags.has("first_hit"):
		c.flags["first_hit"] = true
		await g.add_atk_tokens(c)


# Палеполз
func on_leave_scorchcrawler(_src, sp, _skind, _slane, _c, p, _lane, _reason) -> void:
	var n := int(g.leaving.get("flags", {}).get("burn", 0))
	if n <= 0 or not g.is_foe(sp, p):
		return
	var t = await g.pick_creature(sp, g.sides(), "Палеполз: поджечь выбранное существо (%d)?" % n, Callable(), true)
	if t != null:
		await g.burn_creature(sp, t["p"], t["lane"], n)

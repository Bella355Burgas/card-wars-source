extends "res://scripts/core/rules/base.gd"
## Леди Ливнерог (Песчаные земли): creatures entering play.


func _sandy(c, p: int, lane: int) -> bool:
	return g.is_type(c, "sandy", p, lane)


# Песчаный сфинкс
func floop_ok_sand_sphinx(_c, p, _kind, lane) -> bool:
	return not bld_targets(p, lane).is_empty()


func floop_sand_sphinx(_c, p, _kind, lane) -> void:
	var l: int = await bld_target(p, lane, "Песчаный сфинкс: какое существо вернуть на руку?")
	if l >= 0:
		await g.bounce_creature(p, l)


# Пляжная мумия
# Any creature in an adjacent lane: p's own or the one across.
func _in_adjacent_lane(p: int, lane: int) -> Callable:
	return func(_x, s, l): return adj(lane).any(func(a): return g.on_lane(p, a, s, l))


func floop_ok_beach_mummy(_c, p, _kind, lane) -> bool:
	return not g.creature_opts(p, g.sides(), _in_adjacent_lane(p, lane)).is_empty()


func floop_beach_mummy(_c, p, _kind, lane) -> void:
	var pick = await g.pick_creature(p, g.sides(), "Пляжная мумия: какое существо из соседней зоны вернуть на руку?",
		_in_adjacent_lane(p, lane))
	if pick != null:
		await g.bounce_creature(pick["p"], pick["lane"])


# Стена песка
func atk_wall_of_sand(c, p, _lane) -> int:
	if p != g.turn_player:
		return 0
	for uid in g.turn_value(p, "sandy_entered", []):
		if uid != c.uid:
			return 2
	return 0


# Песчаная ведьма: 1 damage to the opponent for itself and each later creature.
func sees_enter_sandwitch(_src, sp, _skind, _slane, _c, p, _lane) -> bool:
	return p == sp


func on_enter_sandwitch(_src, sp, _skind, _slane, _c, _p, _lane) -> void:
	var o: int = await g.foe_to_hit(sp, "Песчаная ведьма: какому сопернику 1 урон?")
	await say("Песчаная ведьма: 1 урон игроку %s." % players(o).name)
	await g.damage_player(o, 1)


# Акула
# Each Sandy creature entering on your turn, the Shark itself too, has +1 ATK this turn.
func sees_enter_shark(_src, sp, _skind, _slane, c, p, lane) -> bool:
	return p == sp and sp == g.turn_player and _sandy(c, p, lane)


func on_enter_shark(_src, _sp, _skind, _slane, c, _p, _lane) -> void:
	await g.buff(c, 1)


# Персиковый джинн
func sees_enter_peach_djinni(_src, sp, _skind, _slane, c, p, lane) -> bool:
	return p == sp and _sandy(c, p, lane)


func on_enter_peach_djinni(src, _sp, _skind, _slane, _c, _p, _lane) -> void:
	await g.buff(src, 1)


# Песчаный крылоглаз
func sees_enter_sand_eyebat(src, sp, _skind, _slane, c, p, _lane) -> bool:
	return p == sp and c != src


func on_enter_sand_eyebat(src, _sp, _skind, _slane, _c, _p, _lane) -> void:
	src.perm_def += 1
	await flash(src, "+1 DEF")


# Мариачи
func floop_ok_the_mariachi(_c, p, _kind, _lane) -> bool:
	return g.entered_this_turn > 0 and not g.creature_opts(p, g.sides()).is_empty()


func floop_the_mariachi(_c, p, _kind, _lane) -> void:
	var n: int = g.entered_this_turn
	var pick = await g.pick_creature(p, g.sides(), "Мариачи: %d урона выбранному существу" % n)
	if pick != null:
		await hit(pick["p"], pick["lane"], n, p)


# Песчаный змей
func enter_sandsnake(_c, p, lane) -> void:
	if opposite_open(p, lane):
		var a: Array = g.across(p, lane)
		await hit(a[0], a[1], 4, p)


# Слабомумия
func floop_fummy(_c, p, _kind, _lane) -> void:
	await g.gain_actions(p, 1)


# Зелёная кактугидра
func atk_green_cactiball(_c, p, _lane) -> int:
	return 2 * g.count_text(p, "green_cactiball")


# Блудный голем
func cost_lost_golem(_c, p) -> int:
	return -g.turn_value(p, "played_uids", []).size()


# Песчаные рыцари
func atk_sand_knights(_c, p, _lane) -> int:
	return 2 if g.land_count(p, "plain") > 0 else 0


# Дюнный дьяволёнок
func enter_sandhorn_devil(_c, _p, _lane) -> void:
	for side in g.sides():
		for l in LANES:
			if creature(side, l) != null:
				await hit(side, l, 1, g.opp(side))
	await g._check_state()


# Мисс мумия
func start_ms_mummy(_c, p, _kind, lane) -> void:
	var has_sandy := false
	for l in LANES:
		var t = creature(p, l)
		if t != null and l != lane and _sandy(t, p, l):
			has_sandy = true
	if not has_sandy:
		return
	var pick = await g.pick_option(p, ["Вернуть (+1 DEF Песчаному)", "Оставить"], "Мисс мумия: вернуть её в руку?")
	if pick != "Вернуть (+1 DEF Песчаному)":
		return
	await g.bounce_creature(p, lane)
	var t = await g.pick_creature(p, [p], "Мисс мумия: какое Песчаное существо получит +1 DEF?",
		func(x, s, l): return _sandy(x, s, l))
	if t != null:
		var cr = creature(p, t["lane"])
		cr.perm_def += 1
		await flash(cr, "+1 DEF")


# Фолианкх
func spell_tome_of_ankhs(_c, p) -> void:
	await g.draw_cards(p, g.empty_lanes(p).size())


# Волшебные семена Зазо
func playable_zazos_magic_seeds(_c, p) -> bool:
	return not g.creature_opts(p, [p], func(x, s, l): return _sandy(x, s, l)).is_empty()


func spell_zazos_magic_seeds(_c, p) -> void:
	var pick = await g.pick_creature(p, [p], "Волшебные семена Зазо: выбери своё Песчаное существо",
		func(x, s, l): return _sandy(x, s, l))
	if pick == null:
		return
	var per_lane: Dictionary = players(p).turn.get("entered_lane", {})
	var n := 0
	for a in adj(pick["lane"]):
		n += int(per_lane.get(a, 0))
	await g.buff(creature(p, pick["lane"]), 2 * n)


# Непустой гроб
func spell_unempty_coffin(_c, p) -> void:
	g.add_turn(p, "creature_discount", 2)
	await say("Следующее существо игрока %s в этом ходу стоит на 2 действия меньше." % players(p).name)

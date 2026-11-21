extends "res://scripts/core/rules/base.gd"
## Бимо (Бесплодные болота): cards that grow with the discard pile.


func atk_dark_angel(_c, p, _lane) -> int:
	return g.discard_fives(p)


func def_mouthball(_c, p, _lane) -> int:
	return 2 * g.discard_fives(p)


# Пригоревший крылоглаз
func playable_hot_eyebat(_c, p) -> bool:
	return players(p).discard.size() >= 10


# Остролист
func cost_teeth_leaf(_c, p) -> int:
	return -2 if players(p).discard.size() >= 10 else 0


func _random_back(p: int, pred: Callable) -> void:
	var pool: Array = g.discard_pool(p, pred)
	if pool.is_empty():
		await say("В сбросе нет подходящих карт.")
		return
	await g.return_to_hand(pool[g.rng.randi() % pool.size()])


func _swamp_creature(c) -> bool:
	return c.kind() == "creature" and c.def()["land"] == "swamp"


# Костяная палочка
func playable_bone_wand(_c, p) -> bool:
	for l in LANES:
		var t = creature(p, l)
		if t != null and g.is_type(t, "swamp", p, l):
			return true
	return false


func spell_bone_wand(_c, p) -> void:
	var o: int = await g.pick_foe(p, "Костяная палочка: кто из соперников сбросит карту?")
	await g.force_discard(o, 1, "Костяная палочка: %s сбрасывает карту" % players(o).name)


# Кольцо змееглаза
func spell_snake_eye_ring(_c, p) -> void:
	await _random_back(p, _swamp_creature)


# Газы огра
func spell_ogre_gas(_c, p) -> void:
	var deck: Array = players(p).deck
	var top := []
	for i in mini(3, deck.size()):
		top.append(deck[deck.size() - 1 - i])
	if top.is_empty():
		return
	await g.emit_event({"type": "reveal", "p": p, "uids": top.map(func(c): return c.uid)})
	var keep = await g.pick_card(p, top, "Газы огра: какую карту положить вниз колоды? Остальные уйдут в сброс")
	if keep == null:
		keep = top[0]
	for c in top:
		deck.erase(c)
	deck.push_front(keep)
	await say("«%s» уходит вниз колоды." % keep.card_name())
	for c in top:
		if c != keep:
			await g._to_discard(c, "deck")


# Лысый бродяга
func start_wandering_bald_man(_c, p, _kind, _lane) -> void:
	await g.mill(p)


# Зелёная русалка (cost: destroy itself)
func act_green_mermaid(_c, p, _kind, _lane) -> void:
	await hit_foes(p, 1)


# Зелёный русал
func floop_green_merman(_c, p, _kind, _lane) -> void:
	var top = await g.mill(p)
	if top != null:
		var n: int = top.def()["cost"]
		await say("Зелёный русал: %d урона каждому существу соперника." % n)
		await hit_foes(p, n)


# Мимимимик
## «каждому сопернику, у которого нет карт на руке»: both foes in 2 на 2 and на троих.
func start_chest_burster(_c, p, _kind, _lane) -> void:
	for o in g.foes(p):
		if players(o).hand.is_empty() and not players(o).out and g.phase != "over":
			await say("У %s нет карт в руке, Мимимимик кусает на 3." % players(o).name)
			await g.damage_player(o, 3)


# Док Смерть (cost: destroy one of your creatures)
func floop_ok_dr_death(_c, p, _kind, lane) -> bool:
	return not opposite_opts(p, lane).is_empty()


func floop_dr_death(_c, p, _kind, lane) -> void:
	if not opposite_opts(p, lane).is_empty():
		var a: Array = g.across(p, lane)
		await g.destroy_creature(a[0], a[1])


# Удивительный нечеловек-паук
func start_extraordinary_spider(_c, p, _kind, _lane) -> void:
	var n: int = g.discard_fives(p)
	if n > 0:
		var o: int = await g.foe_to_hit(p, "Удивительный нечеловек-паук: какому сопернику %d урона?" % n)
		await say("Удивительный нечеловек-паук: %d урона сопернику." % n)
		await g.damage_player(o, n)


# Серый крылоглаз
func act_ok_gray_eyebat(_c, p, _kind, _lane) -> bool:
	return not g.discard_pool(p, _swamp_creature).is_empty()


func act_gray_eyebat(_c, p, _kind, _lane) -> void:
	await _random_back(p, _swamp_creature)


# Красный дьяволёнок
func floop_ok_red_eyeling(_c, p, _kind, _lane) -> bool:
	return not g.discard_pool(p, func(x): return x.def()["cost"] == 0).is_empty()


func floop_red_eyeling(_c, p, _kind, _lane) -> void:
	var pick = await g.pick_card(p, g.discard_pool(p, func(x): return x.def()["cost"] == 0),
		"Красный дьяволёнок: верни карту стоимостью 0 в руку")
	if pick != null:
		await g.return_to_hand(pick)


# Башня духа (cost: 1 action)
func floop_ok_spirit_tower(_c, p, _kind, lane) -> bool:
	return creature(p, lane) == null and opposite_open(p, lane)


func floop_spirit_tower(_c, p, _kind, lane) -> void:
	var a: Array = g.across(p, lane)
	var t = creature(a[0], a[1])
	if t == null or creature(p, lane) != null:
		return
	await g.take_control(a[0], a[1], p, lane)
	t.exhausted = false
	t.flooped = false
	t.flags["borrowed"] = a[0]
	if a[1] != lane:
		t.flags["borrowed_lane"] = a[1]
	await g.emit_event({"type": "ready", "p": p, "uid": t.uid})


# Нотная тетрадь смерти
func spell_abraca_amadeus(_c, p) -> void:
	var n: int = g.discard_fives(p)
	var o: int = await g.pick_foe(p, "Нотная тетрадь смерти: кто из соперников сбросит карты?")
	await g.force_discard(o, n, "Нотная тетрадь смерти: %s сбрасывает карту" % players(o).name)


# Колдунский перстень
func spell_magic_ring_ding(_c, p) -> void:
	var n: int = g.discard_fives(p)
	for l in LANES:
		if creature(p, l) != null and n > 0:
			await g.buff(creature(p, l), n)


# Древо нежизни
func floop_ok_tree_of_undeath(_c, p, _kind, _lane) -> bool:
	return not g.discard_pool(p, func(x): return x.kind() == "creature").is_empty()


func floop_tree_of_undeath(_c, p, _kind, _lane) -> void:
	await _random_back(p, func(x): return x.kind() == "creature")


# Ошарашенный пень (cost: destroy itself)
func act_mace_stump(_c, p, _kind, _lane) -> void:
	var n: int = g.discard_fives(p)
	var o: int = await g.pick_foe(p, "Ошарашенный пень: кто из соперников сбросит карты?")
	await g.force_discard(o, n, "Ошарашенный пень: %s сбрасывает карту" % players(o).name)

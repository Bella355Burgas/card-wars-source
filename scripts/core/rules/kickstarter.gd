extends "res://scripts/core/rules/base.gd"
## Промо, Kickstarter 1 и Kickstarter 2: отдельные карты для своих колод.


func _any(p: int) -> bool:
	return not g.creature_opts(p, g.sides()).is_empty()


func _coin(p: int) -> bool:
	var heads: bool = g.rng.randi_range(0, 1) == 0
	await say("%s бросает монетку: %s." % [players(p).name, "орёл" if heads else "решка"])
	await g.emit_event({"type": "hero_text", "p": p, "text": "Орёл" if heads else "Решка", "good": true})
	return heads


## The first letter of a card's (Russian) name.
func _letter(x) -> String:
	return x.card_name().substr(0, 1).to_upper()


## A letter chosen from the first letters of the names that matter.
func _pick_letter(p: int, cards: Array, prompt: String) -> String:
	var counts := {}
	for x in cards:
		counts[_letter(x)] = int(counts.get(_letter(x), 0)) + 1
	if counts.is_empty():
		return "А"
	var letters: Array = counts.keys()
	letters.sort_custom(func(a, b): return counts[a] > counts[b] or (counts[a] == counts[b] and a < b))
	return String(await g.pick_option(p, letters.slice(0, 12), prompt))


func _pig(x) -> bool:
	return x.card_name().to_lower().contains("свин") or String(x.def().get("en", "")).to_lower().contains("pig")


## Research notes (Бетти): the cards set aside, kept in the hero state.
func _notes(p: int) -> Array:
	if not players(p).hero_state.has("notes"):
		players(p).hero_state["notes"] = []
	return players(p).hero_state["notes"]


# ---------------------------------------------------------------- Промо

# Сладкое вкусное мясо
func spell_sweet_delicious_meats(_c, p) -> void:
	var n := 0
	for s in g.sides():
		n += players(s).removed.size()
	var names: Array = g.sides().map(func(s): return players(s).name)
	var who: int = g.sides()[maxi(names.find(await g.pick_option(p, names, "Сладкое вкусное мясо: кто восстановит %d жизней?" % n)), 0)]
	await g.heal_player(who, n)


# Воскресная пломбирная школа
func aura_atk_sundae_school(_src, sp, slane, _c, p, lane) -> int:
	return 2 if sp == p and slane == lane and players(sp).hp % 2 == 0 else 0


# Свинарник
func aura_def_the_pigsty(_src, sp, slane, c, p, lane) -> int:
	if sp != p or slane != lane:
		return 0
	return 5 if _pig(c) else 2


# Бродяга синих равнин: once a turn swap with another of your creatures, both +1 ATK.
func act_ok_blue_plains_drifter(_c, p, _kind, _lane) -> bool:
	return g.creature_count(p) >= 2


func act_blue_plains_drifter(c, p, _kind, lane) -> void:
	var t = await g.pick_creature(p, [p], "Бродяга синих равнин: с кем поменяться зонами?", func(x, _s, _l): return x != c)
	if t == null:
		return
	var other = creature(p, t["lane"])
	await g.swap_creatures(p, lane, t["lane"])
	await g.buff(c, 1)
	await g.buff(other, 1)


# Циклоп: +1 DEF for each open eye on your other creatures. Counted on the art of every creature:
# everyone drawn on the card counts, shut or hidden eyes do not; two unless listed.
const EYES := {
	"aeromancer": 0, "ancient_healer": 0, "archer_dan": 0, "archer_danica": 0, "ban_she_princess": 0, "bayou_boa": 0,
	"blonde_merwitch": 0, "bouncing_zebracorn": 0, "brew_haha": 0, "bulkunai_the_leech": 0, "business_dog": 0,
	"canopic_the_ceremonial": 0, "carrier_crab": 0, "chivalrous_armourdillo": 0, "clampire_sanguine_shell": 0,
	"cool_dog": 0, "corn_dog": 0, "corn_lord": 0, "corn_ronin": 0, "cornataur": 0, "corns_templar": 0, "cottonpult": 0,
	"dark_angel": 0, "dragon_claw": 0, "dragon_foot": 0, "dynastic_defector": 0, "embarrassing_bard": 0,
	"erlenmeyer_the_calm": 0, "feedman": 0, "filthflinger": 0, "frosted_deanimator": 0, "fumigator": 0,
	"gallant_armourdillo": 0, "genteel_armourdillo": 0, "geomancer": 0, "ghost_sorceress": 0, "giant_mummy_hand": 0,
	"giddy_giraffe": 0, "gracious_armourdillo": 0, "green_mermaid": 0, "green_zebracorn": 0, "headphone_jerk": 0,
	"helping_hand": 0, "hexbreeze_drifter": 0, "hot_wheel": 0, "husker_champion": 0, "husker_knight": 0,
	"husker_valkyrie": 0, "husker_worm": 0, "husky_parrotrooper": 0, "hydromancer": 0, "icefang_avalancheetah": 0,
	"impossible_possum": 0, "infant_scholar": 0, "infinite_figure": 0, "kernel_queen": 0, "kind_ling": 0,
	"lab_assistant": 0, "legion_of_earlings": 0, "lifeguard_lobster": 0, "longboard_lobster": 0, "mocha_launcher": 0,
	"motley_otters": 0, "mouth_beater": 0, "mouthball": 0, "ms_fluff": 0, "necromancer": 0, "oasis_guardian": 0,
	"pied_piper": 0, "pink_merwitch": 0, "popcorn_butterfly": 0, "president_sweetcorn": 0, "prismatarchia": 0,
	"pyromancer": 0, "quaffius_the_chemist": 0, "refined_armourdillo": 0, "sand_angel": 0, "sand_knights": 0,
	"sandwitch": 0, "sewn_sloth": 0, "skeletal_hand": 0, "smoldering_phantom": 0, "softie_recruit": 0,
	"spellbound_mystic": 0, "spirit_soldier": 0, "sprucy_lucy": 0, "static_parrotrooper": 0, "strawberry_slimey": 0,
	"struzann_jinn": 0, "sun_king": 0, "tectonic_tardigrade": 0, "tentacreeper": 0, "the_barrel": 0, "the_cooper": 0,
	"timmy_magic_eyes": 0, "toddler_scholar": 0, "tornado_wall_of_fire": 0, "ultra_dog": 0, "weakened_warrior": 0,
	"winter_weaver": 0, "woadic_blazetrail_sprinter": 0, "woadic_enchantress": 0, "woadic_marauder": 0,
	"woadic_matriarch": 0, "woadic_ring_leader": 0, "young_zebracorn_husker": 0,
	"albino_eyebat": 1, "apple_pieclops": 1, "blue_plains_drifter": 1, "blueberry_pieclops": 1, "bog_eyesnek": 1,
	"brain_gooey": 1, "cerulean_eyesnek": 1, "chameleon": 1, "corn_bat": 1, "cotton_devil": 1, "cotton_eyebat": 1,
	"courageous_armourdillo": 1, "cyclops": 1, "dark_o_mint": 1, "davey_bones": 1, "dazzling_eyesnek": 1, "dogboy": 1,
	"dr_pieclops": 1, "earth_mover": 1, "emboldened_retriever": 1, "evil_eye": 1, "eye_viner": 1, "fancy_zebracorn": 1,
	"field_stalker": 1, "fire_dog": 1, "flameingo_ash_keeper": 1, "flameingo_blazeling": 1, "flameingo_burnwarden": 1,
	"flameingo_captain": 1, "flameingo_fireplume_chief": 1, "flameingo_flame_tamer": 1, "flameingo_flameweaver": 1,
	"flameingo_heat_eater": 1, "flameingo_hotshot": 1, "flameingo_ignisbeak": 1, "frostcrown_avalancheetah": 1,
	"furious_chick": 1, "furious_hen": 1, "furious_phoenix": 1, "furious_rooster": 1, "future_scholar": 1,
	"ghost_ninja": 1, "gold_ninja": 1, "gray_eyebat": 1, "grizzled_zebracorn": 1, "heavenly_gazer": 1, "herculeye": 1,
	"hillside_eyesnek": 1, "holographic_rabbit": 1, "hot_eyebat": 1, "hunkclops": 1, "jinxed_parrotrooper": 1,
	"kangaroo_pat": 1, "lime_slimey": 1, "little_freezy": 1, "molten_eyesnek": 1, "molten_ritualist": 1, "ms_mummy": 1,
	"music_mallard": 1, "niceasaurus_rex": 1, "ol_corn_eye": 1, "patchy_pumpkin": 1, "pieclops": 1, "pirate_bear": 1,
	"pit_python": 1, "polished_armourdillo": 1, "polterclops": 1, "pony": 1, "protector_of_the_realm": 1,
	"psionic_architect": 1, "rainbow_eyebat": 1, "rebounding_zebracorn": 1, "red_eyeling": 1, "rhinoceros": 1,
	"sand_eyebat": 1, "sandasaurus_rex": 1, "sandhorn_devil": 1, "sandsnake": 1, "shark": 1, "shielded_zebracorn": 1,
	"snakemint": 1, "snow_dog": 1, "snowblind_eyesnek": 1, "spiked_zebracorn": 1, "stalk_eyesnek": 1,
	"sunscorch_eyesnek": 1, "swamp_horn": 1, "the_dog": 1, "tiny_elephant": 1, "trained_zebracorn_husker": 1,
	"unicyclops": 1, "well_dressed_wolf": 1, "zebracorn_seige_shucker": 1,
	"chalice_the_cruel": 3, "fatapillar": 3, "mace_stump": 3, "prismatic_war_beetle": 3, "slashy_sand_crab": 3,
	"adored_cobnoblin": 4, "basalt_behemoth": 4, "broog_rider": 4, "courtly_armourdillo": 4, "dualcast_adept": 4,
	"lava_lamprey_eels": 4, "slay_rider": 4, "support_saguaro": 4, "tailgator": 4, "timematron": 4,
	"frozen_fish": 5, "icy_intruder": 5, "mudpie_zombies": 5, "propagator": 5,
	"abnegator": 6, "extraordinary_spider": 6, "fenunchaku_the_renegade": 6, "muckatana_the_exploiter": 6,
	"quadurai": 6, "subjugator": 6, "surprised_shearer": 6, "urfwurm": 6,
	"big_foot": 8, "lava_ants": 8,
	"beach_worm": 9,
	"ancient_magic_pharaoh_dragon": 10,
	"probably_too_many_unicorns": 11,
	"green_cactiball": 12, "pentacutie": 12,
	"crazy_cat_lady": 18,
	"eye_guy": 19,
	"the_pigs": 54,
}


func _eyes(x) -> int:
	return EYES.get(x.id, 2)


func def_cyclops(c, p, _lane) -> int:
	var n := 0
	for l in LANES:
		var x = creature(p, l)
		if x != null and x != c:
			n += _eyes(x)
	return n


# Наверное, слишком много единорогов
func _reveal_creatures_off(p: int, o: int, n: int, from_bottom: bool) -> int:
	var deck: Array = players(o).deck
	var cards := []
	for i in mini(n, deck.size()):
		cards.append(deck[i] if from_bottom else deck[deck.size() - 1 - i])
	if cards.is_empty():
		return 0
	await g.emit_event({"type": "reveal", "p": o, "uids": cards.map(func(x): return x.uid)})
	var gone := 0
	for x in cards:
		deck.erase(x)
		if x.kind() == "creature":
			gone += 1
			await g._to_discard(x, "deck")
	for x in cards:
		if x.kind() != "creature":
			deck.append(x)
	await say("%s: существ в сброс — %d." % [players(p).name, gone])
	return gone


func _target_player(p: int, prompt: String) -> int:
	var sides: Array = g.sides().filter(func(s): return not players(s).deck.is_empty())
	if sides.is_empty():
		return -1
	var names: Array = sides.map(func(s): return players(s).name)
	return sides[maxi(names.find(await g.pick_option(p, names, prompt)), 0)]


func enter_probably_too_many_unicorns(_c, p, _lane) -> void:
	var o: int = await _target_player(p, "Слишком много единорогов: чью колоду открыть снизу?")
	if o >= 0:
		await _reveal_creatures_off(p, o, 4, true)


func slain_probably_too_many_unicorns(c, _p, _lane, _killer) -> void:
	var w: Dictionary = g.where(c.uid)
	if w["zone"] == "discard":
		players(c.owner).discard.erase(c)
		players(c.owner).deck.push_front(c)
		await say("«%s» уходит под низ колоды." % c.card_name())


# Дракон времени
func enter_time_drake(c, p, _lane) -> void:
	var o: int = await _target_player(p, "Дракон времени: чью колоду открыть?")
	if o >= 0:
		var n: int = await _reveal_creatures_off(p, o, 5, false)
		await g.add_atk_tokens(c, n)


# Свинья (промо, Kickstarter): as Свинья.
func _pig_floop(p: int, lane: int) -> void:
	var pick = await g.pick_land(p, g.land_opts(g.sides(), func(s, l): return g.on_lane(p, lane, s, l) and g.land_type(s, l) == "corn"),
		"Свинья: выбери кукурузное поле в этой зоне")
	if pick != null:
		await g.flip_land(pick["p"], pick["lane"], true)


func floop_ok_the_pig_promo(_c, p, _kind, lane) -> bool:
	return g.lane_spots(p, lane).any(func(s): return g.land_type(s[0], s[1]) == "corn")


func floop_the_pig_promo(_c, p, _kind, lane) -> void:
	await _pig_floop(p, lane)


func floop_ok_the_pig_kickstarter(_c, p, _kind, lane) -> bool:
	return g.lane_spots(p, lane).any(func(s): return g.land_type(s[0], s[1]) == "corn")


func floop_the_pig_kickstarter(_c, p, _kind, lane) -> void:
	await _pig_floop(p, lane)


# Свиньи
func _pigs_hit(p: int) -> void:
	if not _any(p):
		return
	var t = await g.pick_creature(p, g.sides(), "Свиньи: нанести 1 урон выбранному существу?", Callable(), true)
	if t != null:
		await hit(t["p"], t["lane"], 1, p)


func enter_the_pigs(_c, p, _lane) -> void:
	await _pigs_hit(p)


func leave_the_pigs(_c, p, _lane, _reason, _info) -> void:
	await _pigs_hit(p)


# ---------------------------------------------------------------- Kickstarter 1

# Древняя комета
func spell_ancient_comet(_c, p) -> void:
	if await _coin(p):
		for l in LANES:
			if creature(p, l) != null:
				await hit(p, l, 2, p)
		await g._check_state()
	else:
		for l in LANES:
			if creature(p, l) != null:
				await g.buff(creature(p, l), 2)


# Пляжный мяч (one a turn)
func playable_beach_ball(_c, p) -> bool:
	return not players(p).turn.get("beach_ball", false)


func spell_beach_ball(c, p) -> void:
	players(p).turn["beach_ball"] = true
	await g.heal_player(p, 4)
	await g._draw(p)
	if await g.pick_option(p, ["Отдать сопернику", "Оставить"], "Пляжный мяч: отдать мяч сопернику и взять ещё карту?") == "Отдать сопернику":
		# The player's opponent, not the owner's: a stolen ball would fly back to the thief.
		c.flags["to_foe"] = true
		c.flags["giver"] = p
		c.flags["foe_seat"] = await g.pick_foe(p, "Пляжный мяч: какому сопернику отдать мяч?") if g.three() else g.opp(p)
		await g._draw(p)


func discarded_beach_ball(c) -> void:
	if not c.flags.get("to_foe", false):
		return
	c.flags.erase("to_foe")
	var giver: int = int(c.flags.get("giver", c.owner))
	var o: int = int(c.flags.get("foe_seat", g.opp(giver)))
	c.flags.erase("foe_seat")
	c.flags.erase("giver")
	if g.is_out(o):
		o = g.opp(giver)
	players(c.owner).discard.erase(c)
	players(o).hand.append(c)
	await g.emit_event({"type": "to_hand", "p": o, "uid": c.uid, "from": "discard"})
	await say("Пляжный мяч улетает к игроку %s." % players(o).name)


# Бесконечные пироги: free with another Бесконечные пироги in your discard pile.
func cost_infinite_pies(c, p) -> int:
	return -int(c.def()["cost"]) if players(p).discard.any(func(x): return x.id == "infinite_pies") else 0


func spell_infinite_pies(_c, p) -> void:
	var o: int = await g.pick_foe(p, "Бесконечные пироги: какому сопернику 2 урона?")
	if o >= 0:
		await g.damage_player(o, 2, null, {"kind": "effect", "p": p})


# Последняя воля и вред: the card lies under an opposing creature (Game._die deals the 4).
func playable_last_will_and_detriment(_c, p) -> bool:
	return not g.creature_opts(p, g.foes(p)).is_empty()


func spell_last_will_and_detriment(_c, p) -> void:
	var t = await g.pick_creature(p, g.foes(p), "Последняя воля и вред: под какое существо соперника?")
	if t != null:
		creature(t["p"], t["lane"]).flags["last_will"] = p
		await flash(creature(t["p"], t["lane"]), "Последняя воля")


# Энергия вечеринки: all your creatures to new lanes of p's choosing, +2 ATK each.
## Every way to give each creature another lane (no two on one lane): lane -> new lane.
func _new_lanes(lanes: Array, open: Array) -> Array:
	var out := []
	_new_lanes_from(lanes, open, 0, {}, out)
	return out


func _new_lanes_from(lanes: Array, open: Array, i: int, cur: Dictionary, out: Array) -> void:
	if i == lanes.size():
		out.append(cur.duplicate())
		return
	for to in open:
		if to != lanes[i] and not cur.values().has(to):
			cur[lanes[i]] = to
			_new_lanes_from(lanes, open, i + 1, cur, out)
			cur.erase(lanes[i])


func spell_party_energy(_c, p) -> void:
	var lanes: Array = g.creature_lanes(p)
	if lanes.is_empty():
		return
	var open: Array = range(LANES).filter(func(l): return g._lane_open(l))
	var ways: Array = _new_lanes(lanes, open)
	if ways.is_empty():
		await say("Энергия вечеринки: существам некуда перейти.")
		return
	# p places the creatures one by one; only lanes that still leave a place for the rest are offered.
	for l in lanes:
		var dests := []
		for w in ways:
			if not dests.has(w[l]):
				dests.append(w[l])
		var to: int = dests[0]
		if dests.size() > 1:
			var x = creature(p, l)
			to = await g.pick_lane(p, p, dests, "Энергия вечеринки: куда перейдёт «%s»?" % x.card_name())
			if to < 0 or not dests.has(to):
				to = dests[0]
		ways = ways.filter(func(w): return w[l] == to)
	var order: Dictionary = ways[0]
	var old: Array = players(p).creatures.duplicate()
	for l in lanes:
		players(p).creatures[l] = null
	for l in lanes:
		players(p).creatures[order[l]] = old[l]
	await say("Энергия вечеринки: существа игрока %s переходят в новые зоны." % players(p).name)
	for l in lanes:
		var x = old[l]
		await g.emit_event({"type": "move", "p": p, "uid": x.uid, "from": l, "to": order[l]})
		await g.buff(x, 2)
	for l in lanes:
		var x = old[l]
		if g.where(x.uid)["zone"] == "creature":
			await g.changed_lanes(x, p, l, int(order[l]))
			await g.left_lane(x, p, l, p, int(order[l]))


# Орудия ремесла
func spell_tools_of_the_trade(_c, p) -> void:
	for l in LANES:
		if creature(p, l) != null:
			await g.buff(creature(p, l), 1)
	players(p).turn["tools"] = true


# Прихоти судьбы
func spell_whims_of_fate(_c, p) -> void:
	if await _coin(p):
		var t = await g.pick_creature(p, [p], "Прихоти судьбы: какое своё существо уничтожить?")
		if t != null:
			await g.destroy_creature(p, t["lane"])
	else:
		var pool: Array = g.discard_pool(p, func(x): return x.kind() == "creature")
		if pool.is_empty() or g.empty_lanes(p).is_empty():
			return
		var pick = await g.pick_card(p, pool, "Прихоти судьбы: какое существо из сброса вернуть в игру?")
		if pick != null:
			var dest: int = await g.pick_lane(p, p, g.empty_lanes(p), "Прихоти судьбы: на какую пустую землю?")
			if dest >= 0:
				await g._put_creature(p, pick, dest)


# Буйная пекарня: once in your turn discard for a damage token; FLOOP >>> 1 damage for each.
func act_ok_berserk_bakery(c, p, _kind, _lane) -> bool:
	return not players(p).hand.is_empty() and int(c.flags.get("bakery_turn", -1)) != g.turn_number


func act_berserk_bakery(c, p, _kind, _lane) -> void:
	if await g.force_discard(p, 1, "Буйная пекарня: сбрось карту ради жетона урона") > 0:
		c.flags["bakery_turn"] = g.turn_number
		c.damage += 1
		await flash(c, "Жетонов: %d" % c.damage)


func floop_ok_berserk_bakery(c, p, _kind, lane) -> bool:
	return c.damage > 0 and opposite_open(p, lane)


func floop_berserk_bakery(c, p, _kind, lane) -> void:
	var a: Array = g.across(p, lane)
	await hit(a[0], a[1], c.damage, p)


# Жуткий склеп
func on_leave_creepy_crypt(_src, sp, _skind, slane, c, p, lane, _reason) -> void:
	if g.bld_own_lane(sp, slane, p, lane, c):
		var o: int = await g.pick_foe(sp, "Жуткий склеп: какому сопернику 2 урона?")
		if o >= 0:
			await g.damage_player(o, 2, null, {"kind": "effect", "p": sp})


# Монолит рока: your creature of its lane destroyed: the monolith and every creature go.
func on_leave_monolith_of_doom(_src, sp, skind, slane, c, p, lane, reason) -> void:
	if reason != "destroy" or not g.bld_own_lane(sp, slane, p, lane, c) or g.slot(sp, skind, slane) == null:
		return
	await say("Монолит рока рушится: гибнут все существа.")
	await g.destroy_building(sp, slane, skind)
	for s in g.sides():
		for l in LANES:
			if creature(s, l) != null:
				await g.destroy_creature(s, l)


# Оазис вечеринок
func floop_ok_party_oasis(_c, p, _kind, lane) -> bool:
	return creature(p, lane) != null and not g.empty_lanes(p).is_empty()


func floop_party_oasis(_c, p, _kind, lane) -> void:
	var dest: int = await g.pick_lane(p, p, g.empty_lanes(p), "Оазис вечеринок: в какую пустую зону уйдёт существо?")
	if dest < 0:
		return
	await g.move_creature(p, lane, dest)
	var t = await g.pick_creature(p, [p], "Оазис вечеринок: переместить другое своё существо в эту зону?", func(_x, _s, l): return l != dest, true)
	if t != null:
		await g.move_creature(p, t["lane"], lane)


# Ужасная башня: FLOOP and destroy your creature of this lane >>> the top 2 cards are played for free.
func floop_ok_terrible_tower(_c, p, _kind, lane) -> bool:
	return not bld_targets(p, lane).is_empty()


func floop_terrible_tower(_c, p, _kind, lane) -> void:
	var l: int = await bld_target(p, lane, "Ужасная башня: какое своё существо уничтожить?")
	if l < 0:
		return
	await g.destroy_creature(p, l)
	for i in 2:
		if players(p).deck.is_empty():
			return
		var top = players(p).deck.back()
		await g.emit_event({"type": "reveal", "p": p, "uids": [top.uid]})
		if not await g.play_free(p, top, "Ужасная башня: куда сыграть «%s»?" % top.card_name()):
			players(p).deck.erase(top)
			await g._to_discard(top, "deck")


# Древний целитель
func enter_ancient_healer(_c, p, lane) -> void:
	if players(p).lands[lane]["flipped"]:
		await g.flip_land(p, lane, false)
		await g.heal_player(p, 4)


# Тёмномят
func leave_dark_o_mint(_c, p, _lane, reason, _info) -> void:
	if reason != "destroy":
		return
	var o: int = await g.pick_foe(p, "Тёмномят: какой соперник сбросит 2 карты?")
	if o >= 0:
		await g.force_discard(o, 2, "%s: сбрось 2 карты" % players(o).name)


# Счастливый призрак Лаки
func _lucky(p: int) -> void:
	if players(p).deck.is_empty():
		return
	var top = players(p).deck.back()
	await g.emit_event({"type": "peek", "p": p, "uids": [top.uid]})
	if g.is_type(top, "rainbow") and await g.pick_option(p, ["Взять", "Оставить"], "Лаки: сверху «%s». Взять на руку?" % top.card_name()) == "Взять":
		await g._draw(p)


func enter_happy_ghost_lucky(_c, p, _lane) -> void:
	await _lucky(p)


func attack_happy_ghost_lucky(_c, p, _lane) -> void:
	await _lucky(p)


# ---------------------------------------------------------------- Kickstarter 2

# Прилив в протоке
func spell_bayou_surge(_c, p) -> void:
	var lane: int = await g.pick_lane(p, p, range(LANES), "Прилив в протоке: в какой зоне уничтожить всех существ?")
	if lane < 0:
		return
	var spots: Array = g.lane_spots(p, lane)
	for s in spots:
		if creature(s[0], s[1]) != null:
			await g.destroy_creature(s[0], s[1])
	for q in g.seats_from(p):
		for s in spots:
			if s[0] != q or creature(q, s[1]) != null or not g.creature_lane_ok(q, s[1]):
				continue
			var pool: Array = players(q).hand.filter(func(x): return x.kind() == "creature")
			if pool.is_empty():
				continue
			var pick = await g.pick_card(q, pool, "Прилив в протоке: %s, ввести существо с руки в эту зону?" % players(q).name, true)
			if pick != null:
				await g._put_creature(q, pick, s[1])


# Болотный циклон
func spell_bog_cyclone(c, p) -> void:
	var pile: Array = players(p).discard.filter(func(x): return x != c)
	for i in mini(2, pile.size()):
		var x = pile[g.rng.randi() % pile.size()]
		pile.erase(x)
		await g.return_to_hand(x)
	for x in pile:
		players(p).discard.erase(x)
		players(p).deck.push_front(x)
	c.flags["remove_me"] = true


func discarded_bog_cyclone(c) -> void:
	if c.flags.get("remove_me", false):
		c.flags.erase("remove_me")
		await g.remove_from_game(c)


# Блестящее открытие
func spell_brilliant_discovery(_c, p) -> void:
	await g.draw_cards(p, 2)
	for i in 2:
		var pool: Array = g.discard_pool(p, func(x): return x.kind() == "spell")
		if pool.is_empty():
			return
		var pick = await g.pick_card(p, pool, "Блестящее открытие: замешать заклинание в Исследовательские заметки?", true)
		if pick == null:
			return
		players(p).discard.erase(pick)
		_notes(p).append(pick)


# Аккуратная тасовка
func spell_careful_shuffle(_c, p) -> void:
	var letter: String = await _pick_letter(p, g.all_cards(p), "Аккуратная тасовка: выбери букву")
	var deck: Array = players(p).deck
	var top := []
	for i in mini(3, deck.size()):
		top.append(deck[deck.size() - 1 - i])
	await g.emit_event({"type": "reveal", "p": p, "uids": top.map(func(x): return x.uid)})
	for x in top:
		deck.erase(x)
		if _letter(x) == letter:
			players(p).hand.append(x)
			await g.emit_event({"type": "to_hand", "p": p, "uid": x.uid, "from": "deck"})
		else:
			await g._to_discard(x, "deck")


# Баю-бай-бай
func spell_cull_uh_bye(_c, _p) -> void:
	for s in g.sides():
		for l in LANES:
			if creature(s, l) != null and g.atk_of(s, l) >= 4:
				await g.destroy_creature(s, l)


# Бранные слова
func spell_curse_words(_c, p) -> void:
	var all := []
	for s in g.sides():
		for l in LANES:
			if creature(s, l) != null:
				all.append(creature(s, l))
	var letter: String = await _pick_letter(p, all, "Бранные слова: выбери букву (её существа уцелеют)")
	for s in g.sides():
		for l in LANES:
			var x = creature(s, l)
			if x != null and _letter(x) != letter:
				await hit(s, l, 4, p)
	await g._check_state()


# Дельта-господство
func playable_delta_domination(_c, p) -> bool:
	return _any(p)


func spell_delta_domination(_c, p) -> void:
	var n := 0
	for e in g.in_play():
		if e[1] == p:
			n += int(e[0].def()["cost"])
	var t = await g.pick_creature(p, g.sides(), "Дельта-господство: %d урона выбранному существу" % n)
	if t != null and n > 0:
		await hit(t["p"], t["lane"], n, p)


# Божественное право
func spell_divine_right(_c, p) -> void:
	for s in g.seats_from(p):
		await g.heal_player(s, 15)


# Королевское процветание
func spell_royal_prosperity(_c, p) -> void:
	for s in g.seats_from(p):
		await g.draw_cards(s, 2)


# Рентгеновские очки: till the end of the turn the top card lies open and may be played
# like a card from the hand, each one more action dearer (Game.xray_top, Game.cost_of).
func spell_x_ray_specs(_c, p) -> void:
	players(p).turn["xray"] = true
	if not players(p).deck.is_empty():
		await g.emit_event({"type": "reveal", "p": p, "uids": [players(p).deck.back().uid]})


# Святилище государя
func floop_sovereigns_sanctuary(_c, p, _kind, lane) -> void:
	for s in g.bld_spots(p, lane):
		if creature(s[0], s[1]) != null:
			await g.heal_creature(s[0], s[1], 3, p)


# Ледник
func on_thaw_the_icebox(_src, sp, _skind, _slane, side, _lane) -> void:
	if g.thaw_by_discard and g.is_foe(sp, side):
		await g.damage_player(side, 1, null, {"kind": "effect", "p": sp})
		await g.heal_player(sp, 1)


# АбнеГатор: discarded from the hand or the deck, an action in your turn, a card in the opponent's.
func _abnegator(c) -> void:
	if g.turn_player == c.owner:
		await g.gain_actions(c.owner, 1)
	else:
		await g._draw(c.owner)


func discarded_abnegator(c) -> void:
	if g.discard_from == "deck":
		await _abnegator(c)


func discarded_hand_abnegator(c, _p) -> void:
	await _abnegator(c)


# Рождённый вьюгой (creatures onto frozen lands: Game.creature_lane_ok)
func enter_blizzard_born(_c, p, _lane) -> void:
	var o: int = await g.pick_foe(p, "Рождённый вьюгой: чьи земли заморозить?")
	for s in [p, o]:
		if s < 0:
			continue
		for l in LANES:
			await g.freeze(s, l)


# Отмеченный канцлером
func enter_chancellors_commended(c, p, _lane) -> void:
	c.flags["letter"] = await _pick_letter(p, g.all_cards(p), "Отмеченный канцлером: выбери букву")


func aura_atk_chancellors_commended(src, sp, _slane, c, p, _lane) -> int:
	return 3 if sp == p and c != src and _letter(c) == String(src.flags.get("letter", "")) else 0


# Кризисный монарх: Барьеров в игре нет, способность ничего не делает.


# Династический перебежчик: leaving play, its owner may play it onto another player's empty land.
func leave_dynastic_defector(c, _p, _lane, _reason, _info) -> void:
	var o: int = c.owner
	if g.where(c.uid)["zone"] != "discard":
		return
	var spots := []
	for s in g.sides():
		if s != o:
			for l in g.empty_lanes(s):
				spots.append({"p": s, "lane": l})
	if spots.is_empty():
		return
	if await g.pick_option(o, ["Сыграть к сопернику", "Нет"], "Династический перебежчик: сыграть его на пустую землю другого игрока?") != "Сыграть к сопернику":
		return
	var pick = await g.pick_spot(o, spots, "Династический перебежчик: на какую землю?")
	if pick != null:
		await g._put_creature(int(pick["p"]), c, int(pick["lane"]))


# Ледяной страж
func aura_dmg_icewarden(_src, sp, _slane, _c, p, lane, amount, _info) -> int:
	return amount if g.is_foe(sp, p) and g.is_frozen(p, lane) else 0


# Юный кузнец клинков
func sees_enter_neonate_bladesmith(src, sp, _skind, _slane, c, p, lane) -> bool:
	return p == sp and c != src and g.atk_of(p, lane) <= 3


func on_enter_neonate_bladesmith(src, _sp, _skind, _slane, _c, _p, _lane) -> void:
	await g.add_atk_tokens(src)


# Нейромант: a card of cost 0 from the discard pile, gone at the end of the turn.
func floop_ok_neuromancer(_c, p, _kind, _lane) -> bool:
	return not g.discard_pool(p, func(x): return int(x.def()["cost"]) == 0).is_empty()


func floop_neuromancer(_c, p, _kind, _lane) -> void:
	var pool: Array = g.discard_pool(p, func(x): return int(x.def()["cost"]) == 0)
	var pick = await g.pick_card(p, pool, "Нейромант: какую карту за 0 сыграть из сброса?")
	if pick != null and await g.play_free(p, pick):
		pick.flags["neuro"] = g.turn_number


# Утконос
func atk_platypus(_c, p, _lane) -> int:
	var ids := {}
	for x in players(p).discard:
		if int(x.def()["cost"]) == 0:
			ids[x.id] = true
	return ids.size()


# ПропаГатор
func enter_propagator(_c, p, _lane) -> void:
	if players(p).deck.is_empty():
		return
	var names := []
	for x in g.all_cards(p):
		if not names.has(x.card_name()):
			names.append(x.card_name())
	names.sort()
	var named = await g.pick_option(p, names, "ПропаГатор: назови карту")
	var top = players(p).deck.back()
	await g.emit_event({"type": "reveal", "p": p, "uids": [top.uid]})
	if top.card_name() == named:
		await g.mill(p)
		await g.gain_actions(p, 2)


# Защитник королевства: Проклятий в игре нет, способность нельзя применить.
func act_ok_protector_of_the_realm(_c, _p, _kind, _lane) -> bool:
	return false


# Контролёр качества: leaving play, it goes into the Research Notes.
func leave_quality_controller(c, _p, _lane, _reason, _info) -> void:
	if g.where(c.uid)["zone"] == "discard":
		players(c.owner).discard.erase(c)
		_notes(c.owner).append(c)
		await say("Контролёр качества уходит в Исследовательские заметки.")


# Большая свинья
func start_the_big_pig(_c, p, _kind, _lane) -> void:
	var in_hand: Array = players(p).hand.filter(func(x): return _pig(x) and x.kind() != "spell")
	var in_play: Array = g.creature_opts(p, [p], func(x, _s, _l): return _pig(x) and x.id != "the_big_pig")
	var opts := []
	if not in_hand.is_empty():
		opts.append("Ввести с руки")
	if not in_play.is_empty():
		opts.append("Вернуть на руку")
	if opts.is_empty():
		return
	var pick = await g.pick_option(p, opts + ["Ничего"], "Большая свинья: что сделать со свиньёй?")
	if pick == "Ввести с руки":
		var x = await g.pick_card(p, in_hand, "Большая свинья: какую карту ввести в игру?")
		if x != null:
			await g.play_free(p, x)
	elif pick == "Вернуть на руку":
		var t = await g.pick_creature(p, [p], "Большая свинья: какое существо вернуть на руку?", func(x, _s, _l): return _pig(x) and x.id != "the_big_pig")
		if t != null:
			await g.bounce_creature(p, t["lane"])


# Грамотей-карапуз
func dealt_toddler_scholar(_c, p, _lane, amount, target) -> void:
	if target == "player":
		await g.draw_cards(p, amount)


# Урфвурм: defeated, a creature of cost 1 from the hand may take its land for free.
func slain_urfwurm(c, p, lane, _killer) -> void:
	if c.owner != p or creature(p, lane) != null:
		return
	var pool: Array = players(p).hand.filter(func(x): return x.kind() == "creature" and int(x.def()["cost"]) == 1)
	if pool.is_empty():
		return
	var pick = await g.pick_card(p, pool, "Урфвурм: сыграть бесплатно на его землю существо стоимостью 1?", true)
	if pick != null:
		await g._put_creature(p, pick, lane)

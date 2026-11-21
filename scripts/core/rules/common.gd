extends "res://scripts/core/rules/base.gd"
## Cards shared by several decks.


# Прохладный младенец: +3 ATK while the opposite lane is empty.
func atk_nice_ice_baby(_c, p, lane) -> int:
	return 3 if opposite(p, lane) == null else 0


# Небесный замок
func aura_def_celestial_castle(_src, sp, slane, _c, p, lane) -> int:
	return 3 if sp == p and slane == lane else 0


# Кровавая крепость (Кровавая крепость works the same)
func aura_atk_blood_fortress(_src, sp, slane, _c, p, lane) -> int:
	return 1 if sp == p and slane == lane else 0


# Телепорт
func playable_teleport(_c, p) -> bool:
	return g.creature_count(p) > 0 and not g.empty_lanes(p).is_empty()


func spell_teleport(_c, p) -> void:
	await move_own_creature(p, "Телепорт: выбери своё существо")


# Церебральный кровавый шторм
func spell_cerebral_bloodstorm(_c, p) -> void:
	await hit_foes(p, 1)

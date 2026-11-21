extends RefCounted
## Everything one player owns or controls.

var index := 0
var hero := ""              # deck id
var hero_card := ""         # hero card id (its ability), see rules/heroes.gd
var hero_state: Dictionary = {}   # what the hero card remembers for the whole game
var name := ""
## 2 на 2: teammates share their hit points, team_hp is then the same one-element array
## in both seats. Empty in an ordinary game: the seat keeps its own.
var team_hp: Array = []
var hp: int:
	get:
		return _hp if team_hp.is_empty() else team_hp[0]
	set(value):
		if team_hp.is_empty():
			_hp = value
		else:
			team_hp[0] = value
var _hp := 25
var max_hp := 25            # healing stops here («Бесконечный поезд» gives the enemies less)
var stats: Dictionary = {}  # «Бесконечный поезд» hero stats, TrainRules.set_stats: crit, crit_dmg, dodge,
                            # armor, lifesteal, thorns, regen, draw, hand (missing = 0)
var item_state: Dictionary = {}   # and what the rules of the hero's items remember for the whole game
var actions := 0
var mulligan_used := false
var burn := 0               # жетоны огня on the player: 1 damage for each at the start of the turn
var next_actions := 0       # Зелье энергии: actions added to the player's next turn
var teamwork = null         # the командная карта in play by the player's lands (Парный турнир), or null
var out := false            # на троих: the player has dropped out (Game._drop_out), the other two play on 1 на 1

var deck: Array = []        # top of the deck is the back of the array
var hand: Array = []
var discard: Array = []
var removed: Array = []     # removed from the game

## Four lanes, left to right as seen from player 0's seat (2 на 2: from the seat's own place,
## lanes 0 and 1 face the next seat, 2 and 3 the one before, see Game.across).
## Land: {"type", "flipped", "art", "frozen", "override", "override_until", "flip_until"}
var lands: Array = []
var creatures: Array = [null, null, null, null]
var buildings: Array = [null, null, null, null]
var extra_buildings: Array = [[], [], [], []]   # Крепкий лесоруб: more buildings on one land

## Counters and effects that last for the current turn only (both players'
## dictionaries are cleared when any turn starts).
var turn: Dictionary = {}

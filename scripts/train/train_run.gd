extends RefCounted
## «Бесконечный поезд», the roguelike run. The player starts with half of a ready deck
## and builds it up with trophies; hit points carry over from fight to fight. Wagon after
## wagon the player picks one of the doors: a fight, an elite fight, a rest, a chest, a
## shop or an event.
## Every TRAIN_LEN-th wagon is the locomotive with a boss. The enemies grow with every
## wagon passed: more hit points, a stronger AI, elites and bosses with stats of their own.
## Won fights give experience; a new level lets the player raise one of the hero's stats
## (crits, dodging and the like, see STATS; TrainRules.set_stats plays them in fights).
## Items (train_items.gd) drop from chests, elites, bosses and now and then a common
## fight; they stay for the whole run and add to the stats or change the run's rules.
## One of the fight doors leads into a wagon with a rule for its fight (train_wagons.gd),
## the locomotive has the boss's rule.
## A rest heals, throws a card out, improves a card or changes one of the four lands.
## A "double" door is a fight with two enemies one after the other.
## The score is the number of wagons passed.
## Pure state: the run screen shows it and main.gd plays its fights. Saved to PATH after
## every step, so a closed game goes on from the same place (a fight starts over).
##
## The run deck: `cards` (card id -> copies) is what the fights are played with. The copies
## counted in `upgraded` (card id -> how many of them are improved, never more than the
## copies) play as improved. An improved copy is not another card: the deck code of a fight
## (CardDB.run_code) is the same, and prepare_fight() marks that many CardInst of the
## player's deck (CardInst.upgraded, which stays on the card in every zone). A creature
## gets +1 ATK and +1 DEF, a spell and a building cost 1 less (never below 0); cards that
## cost nothing are not improved. A rest can throw an improved copy out like any other.
## `lands` are the four lands in the order of the lanes; changing one keeps the others
## where they are, and the trophies are offered by the new lands (payable).
##
## A "double" door is one fight against two enemies. The door has the first enemy like
## every fight door and `second` = {enemy, hp, level, stats} for the other. When the first
## falls the hit points, the hand, the field and the deck of the player stay as they are,
## and the second walks in with its own deck, hit points and starting hand (TrainRules.set_follow,
## TrainRules.next_enemy). The wagon's rule works the whole fight, the AI of the second plays at
## its own level.
##
## Coins (`coins`): a won fight gives COIN_WIN of its kind; the shop door ("shop", phase
## "shop", `shop` = the shelf: cards, items and the services not bought yet) takes them. The
## prices are all constants here (PRICE_*): a card PRICE_CARD + PRICE_PER_COST per cost point,
## an item by rarity, and once per visit an improved copy, a card thrown out, a curse taken off.
## The shop comes from wagon SHOP_FROM, never right after another one.
## An event door ("event", phase "event", `event` = {id, stage: options | pick | result, pick,
## result, got}) is a hero with two or three offers (train_events.gd): the price and the
## reward are paid at once (choose_event), a card or a curse to pick comes next (event_pick),
## then the result is read (finish_event). All of it is in the save; a chance is decided by the
## run's `rng`, so a reloaded event gives the same.
## The curses of the Lich (`curses`, train_items.gd CURSES) work like items (bonus() adds up
## the mods of both) but are not thrown out: a shop or an event takes them off. Their own run
## keys are played here: enemy_hp and enemy_crit and junk in prepare_fight, fight_loss in
## fight_won; hand, bleed and spell_tax go to the game with the other stats.
## A dark door (`dark` in the door; DARK_KINDS): the wagon behind it is hidden (the door shows "?" and
## "Тёмная дверь"), its `kind` is the real one, as for every door. Its reward is bigger: DARK_COINS of the
## coins of a won fight, one more item to take (or a trophy when the fight offers none), one more item in
## a chest. The dark doors come from the run's own random numbers, so the same train has them.
## The train of the day (`daily` = its date, UTC): start_daily() takes the seed and the ready
## deck from the date, the save is DAILY_PATH, and the doors of a wagon depend on the seed
## and the wagon's number only (the generator is re-seeded), so everybody meets the same doors.
## Its result (daily_result) goes to the table of the server (scripts/net/daily_board.gd) with the
## run's journal (`journal_path`, next to its save, a JSON line per step): the server plays the whole
## run again from the date (scripts/train/run_check.gd) and takes the score it gets, not the one sent.
## A step is {"a": an action, "x": its arguments, "ph", "n", "c", "hp": the phase, the wagons passed, the
## coins and the HP before it}; the first is {"a": "start", "date", "pick", "seed", "difficulty", "rules", "format"}, a fight that
## starts writes {"a": "go"} (one started over after the game was closed writes it again) and a fight
## that ends {"a": "fight", "steps": the game's journal, "hash"} before its
## fight_won or lose, and {"a": "load"} says the run was read from its save there (restore_from).
## An ordinary run keeps its journal too: a new record of the player goes to the server with it
## (scripts/net/social.gd report_best), and the server's check plays that run again from its seed.
## Difficulty (`difficulty`, DIFFICULTY): a plain run picks a level 0-10 before it starts. Every level has
## a penalty of its own on top of the lower ones: more HP for the enemies, a weaker rest and win heal,
## elites more often and with one more stat, a dearer shop, fewer trophies and coins, a stronger AI,
## a weaker start. They work in the doors and in the fights (_enemy_hp, _door_kind, shop_price and the
## like) and the level is in the save. The train of the day is always level 0. A beaten locomotive
## of a plain run opens the next level (unlocks()); main.gd keeps the open levels and the records
## of every deck and every level in the game settings.
## The chronicle (`chronicle`, `fell`) is the whole run's road, wagon after wagon, for the end screen:
## `history`, `met` and `wagons` start over with every train, the chronicle does not.
## Save FORMAT 9; saves of formats 2-8 load, what they lack is empty (difficulty 0, a chronicle
## made from the train going on, a shop without the curse sale).

const CardDB = preload("res://scripts/core/card_db.gd")
const Game = preload("res://scripts/core/game.gd")
const Replay = preload("res://scripts/core/replay.gd")
const TrainItems = preload("res://scripts/train/train_items.gd")
const TrainEvents = preload("res://scripts/train/train_events.gd")
const TrainWagons = preload("res://scripts/train/train_wagons.gd")
const TrainRules = preload("res://scripts/train/train_rules.gd")
const PATH := "user://run.json"
const DAILY_PATH := "user://run_daily.json"
const FORMAT := 9
## Rules of the train itself (rewards, items, the shop), in the journal's start line: the server
## checks a run by the rules it was played with. 1: up to build 55; 2: build 56, copies of items
## and no командные карты; 3: no top for the hero stats (an hour in build 57, too strong with many
## items); 4: tops back, only the health has none, slow steps of the percent stats, and the enemies
## grow stronger after wagon LATE_FROM (late_tier). 5: the hero card's deck limit holds for
## every card the run gives (Малыши Финн и Джейк: no creatures with more than 3 ATK).
const TRAIN_RULES := 5
const TRAIN_LEN := 10
const START_HP := 30
const START_CARDS := 20         # half of the ready deck: trophies build the rest
const START_CREATURES := 10
const MIN_DECK := 10            # a rest cannot thin the deck below this
const REST_HEAL := 10
const FIGHT_HEAL := 5           # every won fight heals this much
const BOSS_HEAL := 12           # a beaten boss heals this much instead
const DOUBLE_HEAL := 6          # and a beaten pair
const OFFERS := 3
# Enemies: hit points at the start of the run, and how they grow. Measured with tools/train_balance.gd
# (docs/BALANCE.md): an AI player of medium level with a greedy run policy clears about half of the first train, then 60-75% of every next
# one; the later trains grow with the hero (HP_TRAIN_PCT, TRAIN_STATS).
const FIGHT_HP := 7
const ELITE_HP := 11
const BOSS_HP := 13
const HP_PER_WAGON := 0.4       # every wagon passed adds this to all enemies
# and every train after the first makes their hit points this many percent bigger (by the kind of the fight)
const HP_TRAIN_PCT := {"fight": 5, "double": 5, "elite": 10, "boss": 12}
# What every enemy has on top of its own stats, train after train (an elite and a locomotive one train earlier, but for actions): from the train
# `from` on `step` more of the stat with every train, at most `max`. FIGHT_STATS and STATS keys, as for the hero.
const TRAIN_STATS := {
	"atk": {"from": 3, "step": 1, "max": 6},
	"crit": {"from": 3, "step": 8, "max": 40},
	"actions": {"from": 4, "step": 1, "max": 2},
}
# Locomotives that were too easy or too hard in the measures (docs/BALANCE.md): their hit points, in percent.
const BOSS_HP_PCT := {"lemongrab": 160, "ice_king": 130}
const ENEMY_DECK_MIN := 20      # the enemy plays with as many cards as the hero has, but not fewer than this (TrainRules.limit_enemy_deck)
const WAGONS_PER_LEVEL := 6     # the AI gets one level stronger every this many wagons
# Hero stats: what one level-up step adds and the most a stat can have (TrainRules.set_stats).
const STATS := {
	"max_hp": {"name": "Здоровье", "step": 5, "max": 999, "about": "Максимум HP"},
	"crit": {"name": "Шанс крита", "step": 8, "max": 61, "about": "Атака существа бьёт сильнее"},
	"crit_dmg": {"name": "Сила крита", "step": 50, "max": 200, "about": "Урон крита"},
	"dodge": {"name": "Уклонение", "step": 7, "max": 35, "about": "Удар по герою проходит мимо"},
	"armor": {"name": "Броня", "step": 1, "max": 2, "about": "Урон герою меньше, но не меньше 1"},
	"lifesteal": {"name": "Вампиризм", "step": 25, "max": 100, "about": "Урон твоих существ лечит героя"},
	"thorns": {"name": "Шипы", "step": 1, "max": 3, "about": "Урон существу, ударившему героя"},
	"regen": {"name": "Регенерация", "step": 1, "max": 2, "about": "HP в начале хода, пока есть колода"},
	"draw": {"name": "Добор", "step": 20, "max": 60, "about": "Шанс лишней карты в начале хода"},
	"hand": {"name": "Стартовая рука", "step": 1, "max": 2, "about": "Карт в начале боя"},
	"luck": {"name": "Удача", "step": 1, "max": 2, "about": "Трофеев на выбор"},
}
# Stats only items give, played in fights (TrainRules.set_stats).
const FIGHT_STATS := {
	"actions": {"name": "Действия", "about": "Лишние действия в каждом ходу"},
	"atk": {"name": "Сила существ", "about": "ATK всех твоих существ"},
	"bleed": {"name": "Потеря HP", "about": "HP в начале хода"},
}
# Rules only items give, played in fights like the stats (Game: cost_of, def_of, _die
# and the like). They are not shown with the stats: the item's text says what each does.
const ITEM_RULES := ["enter_def", "first_free", "death_heal", "death_draw", "kill_atk", "lone",
	"edge_def", "face_dmg", "vs_atk", "first_crit", "kill_action", "death_bleed", "first_return",
	"weak_up", "spell_cheap", "spell_dmg", "spell_heal", "spell_buff", "third_spell", "spell_draw",
	"building_def", "building_draw", "building_cheap", "building_regen", "rainbow_cheap", "no_freeze",
	"floop_draw", "floop_def", "first_action", "last_stand", "revive", "spell_tax"]
const START_STATS := {"crit": 5}
# Items: how many to pick one of; a common fight gives one now and then, a boss no common ones.
const ITEM_OFFERS := {"treasure": 3, "elite": 2, "boss": 3, "double": 2}
const FIGHT_ITEM_CHANCE := 0.15
const DOUBLE_ITEM_CHANCE := 0.4
# The doors with two enemies: the weight among the doors, and the first wagon of a train that has them.
const DOUBLE_WEIGHT := 8
const DOUBLE_FROM := 4
const XP := {"fight": 1, "elite": 2, "boss": 3, "double": 2}
const SKIP_HEAL := 3            # leaving the trophies heals this much while the hero is hurt, else gives SKIP_XP
const SKIP_XP := 1
# Trophies of a won fight to pick one by one (a common fight gives 1).
const PICKS := {"elite": 2, "double": 2}
const PERK_OFFERS := 3
const NO_CAP := 1000000000      # a hero stat has no top from train rules 3 on
# Elites and bosses get stats too: so many of these (one more every train).
const ENEMY_STATS := {"crit": 20, "dodge": 20, "armor": 1, "thorns": 2, "regen": 1, "lifesteal": 30}
const ENEMY_STAT_COUNT := {"fight": 0, "elite": 1, "boss": 2}
# Coins: what a won fight gives, and the prices of the shop (all of them here).
const COIN_WIN := {"fight": 5, "elite": 10, "double": 9, "boss": 20}
const SHOP_TRAIN_PCT := 15      # and every train after the first makes everything in the shop this many percent dearer
const SHOP_FROM := 3            # the first wagon that can have a shop
const SHOP_WEIGHT := 12
const SHOP_CARDS := 4           # cards on the shelf
const SHOP_ITEMS := 2           # items on the shelf
const PRICE_CARD := 5           # a card: this much and PRICE_PER_COST for every cost point
const PRICE_PER_COST := 3
const PRICE_ITEM := {"common": 14, "rare": 24, "legend": 40}
const PRICE_UPGRADE := 8        # one copy improved
const PRICE_REMOVE := 10        # one card thrown out
const PRICE_UNCURSE := 16       # one curse taken off
const PRICE_REROLL := 2         # a new shelf: this much, one more with every roll of the same shop
const EVENT_FROM := 2           # the first wagon that can have an event
const EVENT_WEIGHT := 14
# Dark doors: the wagon behind one is hidden ("?"), its kind is one of DARK_KINDS (one dark door a wagon).
# A won fight behind one pays DARK_COINS times the coins and one more item (or one more trophy when the
# fight offers none); a chest one more item.
const DARK_FROM := 3
const DARK_WEIGHT := 8
const DARK_KINDS := ["fight", "elite", "treasure"]
const DARK_COINS := 1.5
# The cards of the curse of junk: two lands of their type play them, so a hero without these lands cannot.
const JUNK := ["husker_knight", "fatapillar"]
const RAINBOW := "rainbow"
const FIGHTS := ["fight", "elite", "boss", "double"]
# Enemy strength: AI levels from weak to strong (ai_levels.gd ids).
const LEVELS := ["novice", "easy", "medium", "hard", "impossible"]
const BOSSES := ["lich", "ice_king", "lemongrab", "marceline"]
# Difficulty ("Сложность"): 0 is the plain train. Level n (1..MAX_DIFFICULTY) has the penalties of
# DIFFICULTY[0..n-1] together, each level adds its own to all the lower ones. A run keeps its level
# for good; the train of the day is always level 0. A beaten locomotive of a plain run opens the next
# level (unlocks(); the open levels are kept in the game settings, see main.gd).
# Keys: enemy_hp (every enemy), rest (healing of a rest), elite_weight (the weight of the elite door),
# shop_pct (prices of the shop, %), elite_stats (stats of an elite), win_heal (healing of a won
# fight), offers (trophies to pick from), coins_pct (coins of a won fight, %), ai_level (AI levels
# of the enemies), start_hp (the hero's hit points at the start).
const MAX_DIFFICULTY := 10
const DIFFICULTY := [
	{"text": "Врагам +2 HP", "enemy_hp": 2},
	{"text": "Отдых лечит на 3 меньше", "rest": -3},
	{"text": "Элиты чаще", "elite_weight": 12},
	{"text": "Лавка дороже на 25%", "shop_pct": 25},
	{"text": "У элит на один стат больше", "elite_stats": 1},
	{"text": "Победа лечит на 2 меньше", "win_heal": -2},
	{"text": "Трофеев на выбор на один меньше", "offers": -1},
	{"text": "Монет за победу на четверть меньше", "coins_pct": -25},
	{"text": "ИИ врагов на уровень сильнее", "ai_level": 1},
	{"text": "Старт с 5 HP меньше", "start_hp": -5},
]

var seed_value := 0
var train_rules := TRAIN_RULES  # set before start(); older ones only for the server's check
var rng := RandomNumberGenerator.new()
var deck_id := ""               # the ready deck the run started from
var hero_card := ""
var lands: Array = []
var cards: Dictionary = {}      # the run deck: card id -> copies
var upgraded: Dictionary = {}   # card id -> how many of its copies are improved (at most the copies)
var pool: Dictionary = {}       # the other half of the ready deck: trophies come from it too
var hp := START_HP
var max_hp := START_HP
var stats: Dictionary = {}      # hero stats from level-ups: STATS keys but max_hp, missing = 0
var items: Array = []           # item ids (train_items.gd), in the order taken
var curses: Array = []          # curse ids (train_items.gd CURSES): work like items, but are not thrown out
var item_offers: Array = []     # phase "item": item ids to take one of
var level := 1
var xp := 0                     # experience toward the next level
var levels_due := 0             # level-ups not spent yet
var perks: Array = []           # a level-up: stat keys to raise one of
var train := 1
var wagon := 0                  # wagons passed in this train; the next one is wagon + 1
var passed := 0                 # wagons passed in the whole run: the score
var wins := 0
var history: Array = []         # kinds of the wagons passed in this train
var met: Array = []             # and who was in them (enemy deck ids, "" for no fight)
var wagons: Array = []          # and their rules (train_wagons.gd ids, "" for none)
var coins := 0                  # the currency of the run: fights give them, the shop takes them
var event: Dictionary = {}      # phase "event": {id, stage: options | pick | result, pick, result, got: lines of what happened}
var seen_events: Array = []     # events met in this run: not met again before all have come
var shop: Dictionary = {}       # phase "shop": {cards, items: ids on the shelf, upgrade, remove, uncurse: the services still free}
var phase := "doors"            # doors | fight | level | item | reward | rest | shop | event | over
var doors: Array = []           # the next wagon to pick: {kind, enemy?, hp?, level?, seed?, stats?, wagon?, second?}
var current: Dictionary = {}    # the wagon being played
var offers: Array = []          # reward: card ids to take one of
var picks_left := 0
var last_enemy := ""
var daily := ""                 # the train of the day: its date (UTC, "2026-10-16"); "" for an ordinary run
var difficulty := 0             # 0..MAX_DIFFICULTY, see DIFFICULTY; set at the start, never changes
var bosses := 0                 # locomotives beaten in this run
var chronicle: Array = []       # every wagon passed in the run: {kind, enemy, wagon, second?}; never emptied between trains
var fell: Dictionary = {}       # the fight lost to end the run: {kind, enemy, wagon}; {} when it was given up
var save_path := PATH           # tests keep their runs elsewhere; "" keeps no save (the server's check)
var journal_path := ""          # the train of the day: its journal; "" keeps none


## A new run with a ready deck and a hero card ("deck" or "deck@hero card").
func start(pick: String, with_seed := -1, p_daily := "", p_difficulty := 0) -> void:
	daily = p_daily
	difficulty = 0 if p_daily != "" else clampi(p_difficulty, 0, MAX_DIFFICULTY)
	bosses = 0
	chronicle = []
	fell = {}
	seed_value = with_seed if with_seed >= 0 else randi() & 0x7fffffff
	rng.seed = seed_value
	journal_path = save_path.get_basename() + ".log" if save_path != "" else ""
	if journal_path != "":
		var f := FileAccess.open(journal_path, FileAccess.WRITE)
		if f != null:
			f.store_line(JSON.stringify({"a": "start", "date": daily, "pick": pick, "seed": seed_value, "difficulty": difficulty,
				"rules": Replay.RULES, "format": FORMAT, "train_rules": train_rules}))
	deck_id = CardDB.loadout_deck(pick)
	hero_card = CardDB.loadout_card(pick)
	var h := CardDB.hero(deck_id)
	lands = h["lands"].duplicate()
	var creatures := []
	var others := []
	for id: String in h["deck"]:
		if not _gives(id):
			continue
		for n in int(h["deck"][id]):
			(creatures if CardDB.get_def(id)["kind"] == "creature" else others).append(id)
	_shuffle(creatures)
	_shuffle(others)
	var take := mini(START_CREATURES, creatures.size())
	var first: Array = creatures.slice(0, take) + others.slice(0, START_CARDS - take)
	var rest: Array = creatures.slice(take) + others.slice(START_CARDS - take)
	while first.size() < START_CARDS and not rest.is_empty():
		first.append(rest.pop_back())
	cards = _count(first)
	upgraded = {}
	pool = _count(rest)
	hp = maxi(START_HP + penalty("start_hp"), 1)
	max_hp = hp
	stats = START_STATS.duplicate()
	items = []
	curses = []
	item_offers = []
	coins = 0
	shop = {}
	event = {}
	seen_events = []
	_make_doors()
	save()


## The train of the day (save_path = DAILY_PATH, so it never meets an ordinary run's save): the
## seed and the ready deck come from the date, the same for everybody.
## The doors of a wagon depend only on the seed and the number of the wagon (_make_doors).
func start_daily(date: String) -> void:
	start(daily_deck(date), daily_seed(date), date)


## Today's date for the train of the day: the same day for the whole world (UTC).
static func daily_date() -> String:
	return Time.get_date_string_from_system(true)


static func daily_seed(date: String) -> int:
	var n := 7
	for ch in date.to_utf8_buffer():
		n = (n * 131 + ch) % 2147483629
	return n


## The ready deck of the day, with its own hero card.
static func daily_deck(date: String) -> String:
	var ids: Array = CardDB.hero_ids()
	return ids[daily_seed(date) % ids.size()]


## What a train of the day is remembered by: the wagons passed, the wins, the hero and the deck.
func daily_result() -> Dictionary:
	return {"date": daily, "score": passed, "wins": wins, "hero": deck_id, "deck": deck_code()}


## The run deck as "card:copies,card:copies", sorted: for the table of the day.
func deck_code() -> String:
	var ids: Array = cards.keys()
	ids.sort()
	return ",".join(ids.map(func(id): return "%s:%d" % [id, int(cards[id])]))


## The player's pick for a fight: the run deck with the hero card.
func player_pick() -> String:
	return CardDB.loadout(CardDB.run_code(deck_id, lands, cards), hero_card)


func deck_size() -> int:
	var n := 0
	for id in cards:
		n += int(cards[id])
	return n


## The value of a hero stat (max_hp included): level-ups and items together, within
## the stat's maximum (an item may take one below zero; the starting hand down to 3).
func stat(key: String) -> int:
	if key == "max_hp":
		return max_hp
	var hi: int = stat_cap(key) if STATS.has(key) else 99
	return clampi(int(stats.get(key, 0)) + bonus(key), -2 if key == "hand" else 0, hi)


## What the hero's items add to a stat or a rule of the run (train_items.gd "mods").
func bonus(key: String) -> int:
	var n := 0
	for id: String in items:
		n += int(TrainItems.item(id)["mods"].get(key, 0))
	for id: String in curses:
		n += int(TrainItems.curse(id)["mods"].get(key, 0))
	for set_id: String in TrainItems.SETS:
		if set_done(set_id):
			n += int(TrainItems.SETS[set_id]["mods"].get(key, 0))
	return n


## How many items of a set (TrainItems.SETS) the hero has.
func set_count(set_id: String) -> int:
	var n := 0
	for id: String in TrainItems.SETS[set_id]["items"]:
		if items.has(id):
			n += 1
	return n


## Whether the hero has enough items of a set for its mods to count.
func set_done(set_id: String) -> bool:
	return set_count(set_id) >= int(TrainItems.SETS[set_id]["need"])


## The stats a fight plays with (TrainRules.set_stats): every one that is not zero.
func fight_stats() -> Dictionary:
	var out := {}
	for key: String in STATS.keys() + FIGHT_STATS.keys() + ITEM_RULES:
		if key != "max_hp" and stat(key) != 0:
			out[key] = stat(key)
	return out


func rest_amount() -> int:
	return maxi(REST_HEAL + bonus("rest_heal") + penalty("rest"), 1)


# ---------------------------------------------------------------- difficulty

## What the difficulty level adds up to for one key of DIFFICULTY (all the levels up to this run's).
func penalty(key: String) -> int:
	return difficulty_sum(difficulty, key)


static func difficulty_sum(lv: int, key: String) -> int:
	var n := 0
	for i in clampi(lv, 0, MAX_DIFFICULTY):
		n += int(DIFFICULTY[i].get(key, 0))
	return n


## The penalty a level adds, a short line; "" for level 0.
static func difficulty_text(lv: int) -> String:
	return "" if lv < 1 or lv > MAX_DIFFICULTY else String(DIFFICULTY[lv - 1]["text"])


## Every penalty of a level, the lowest level's first.
static func difficulty_lines(lv: int) -> Array:
	var out := []
	for i in clampi(lv, 0, MAX_DIFFICULTY):
		out.append(String(DIFFICULTY[i]["text"]))
	return out


## The highest difficulty this run opens: a beaten locomotive of a plain run opens the next level
## after the run's own; 0 when none is beaten (and always in the train of the day).
func unlocks() -> int:
	return 0 if bosses < 1 or daily != "" else mini(difficulty + 1, MAX_DIFFICULTY)


## A price of the shop with the difficulty's markup.
func shop_price(base: int) -> int:
	var price := roundi(base * (100 + penalty("shop_pct") + SHOP_TRAIN_PCT * (train - 1)) / 100.0)
	if bool(shop.get("sale", false)):
		return maxi(ceili(price / 2.0), 1)
	return price


## The deck a rest cannot thin below.
func min_deck() -> int:
	return maxi(MIN_DECK + bonus("min_deck"), 1)


## Experience a level-up needs: one more for every level.
func xp_needed() -> int:
	return level + 1


## A stat as the player sees it: "13%", "×2,5", "+1".
static func stat_text(key: String, value: int) -> String:
	match key:
		"crit", "dodge", "lifesteal", "draw":
			return "%d%%" % value
		"crit_dmg":
			return "×" + String.num((TrainRules.CRIT_BASE + value) / 100.0, 1).replace(".", ",").trim_suffix(",0")
		"hand":
			return str(Game.START_HAND + value)
		"actions", "atk":
			return "%+d" % value
		"bleed":
			return "−%d" % value
		"luck":
			return str(OFFERS + value)
		"regen":
			return "+%d" % value
	return str(value)


## Short lines about an enemy's stats for its door: "Шанс крита 20%".
static func enemy_stat_lines(st: Dictionary) -> Array:
	var out := []
	for key: String in st:
		if ENEMY_RULE_NAMES.has(key):
			out.append(ENEMY_RULE_NAMES[key])
		else:
			out.append("%s %s" % [(STATS[key] if STATS.has(key) else FIGHT_STATS[key])["name"], stat_text(key, int(st[key]))])
	return out


## Sets up a fight of the current wagon in a game already set up with player_pick()
## against the door's enemy: hit points and stats of both sides, the wagon's rule, the
## improved cards of the deck and, in a double wagon, the second enemy.
## The run's HP stay as they are (fight_hp is for this fight): a fight left halfway
## starts over the same.
func prepare_fight(game) -> void:
	var rule := String(current.get("wagon", ""))
	var st: Array = [fight_stats(), current.get("stats", {}).duplicate()]
	if bonus("enemy_crit") > 0:
		st[1]["crit"] = int(st[1].get("crit", 0)) + bonus("enemy_crit")
	var enemy_hp := int(current["hp"]) + bonus("enemy_hp")
	game.players[0].hp = mini(hp + bonus("fight_hp"), max_hp)
	game.players[0].max_hp = max_hp
	game.players[1].hp = enemy_hp
	game.players[1].max_hp = enemy_hp
	for p in 2:
		game.players[p].hp += _rule_start(rule, st[p])
		game.players[p].max_hp = maxi(game.players[p].max_hp, game.players[p].hp)
		game.train.set_stats(p, st[p])
	game.train.set_wagon(rule)
	_mark_upgrades(game)
	_add_junk(game)
	game.train.limit_enemy_deck(ENEMY_DECK_MIN)
	if current.has("second"):
		var sec: Dictionary = current["second"]
		var st2: Dictionary = sec.get("stats", {}).duplicate()
		if bonus("enemy_crit") > 0:
			st2["crit"] = int(st2.get("crit", 0)) + bonus("enemy_crit")
		game.train.set_follow(String(sec["enemy"]), int(sec["hp"]) + bonus("enemy_hp") + _rule_start(rule, st2), st2, ENEMY_DECK_MIN)


## What the wagon's rule changes at the start of a fight for one side with these stats
## (changed in place); returns the hit points it adds.
func _rule_start(rule: String, st: Dictionary) -> int:
	match rule:
		"fair":
			st["hand"] = int(st.get("hand", 0)) + 1
		"fireworks":
			st["crit"] = int(st.get("crit", 0)) + 20
			st.erase("dodge")
		"sugar":
			return 3
	return 0


## A curse of the Lich (junk) puts cards the hero cannot use into the deck, each in a place
## the random numbers of the game pick.
func _add_junk(game) -> void:
	for n in bonus("junk"):
		var c = game._make_card(junk_card(), 0)
		var deck: Array = game.players[0].deck
		deck.insert(game.rng.randi() % (deck.size() + 1), c)


## The card the junk is: one whose lands the hero has not got, so it cannot be played.
func junk_card() -> String:
	for id: String in JUNK:
		if lands.count(CardDB.get_def(id)["land"]) < int(CardDB.get_def(id)["cost"]):
			return id
	return JUNK[0]


## The improved copies are marked on that many cards of the player's deck, the first
## ones by their numbers (the deck is shuffled, so which of them comes first is luck).
func _mark_upgrades(game) -> void:
	var owned: Array = game.all_cards(0)
	for id: String in upgraded:
		var left := int(upgraded[id])
		for c in owned:
			if left <= 0:
				break
			if c.id == id and not c.upgraded:
				c.upgraded = true
				left -= 1


## Cards the train never gives: the командные карты are for 2 на 2 only.
static func train_card(id: String) -> bool:
	return String(CardDB.get_def(id)["kind"]) != "teamwork"


## train_card by the rules of this run (the older ones gave командные карты too), and the
## deck limit of the hero card (since rules 5).
func _gives(id: String) -> bool:
	if train_rules >= 5 and not hero_allows(hero_card, id):
		return false
	return train_rules < 2 or train_card(id)


## Whether the hero card lets the deck have this card (CardDB.HERO_MAX_ATK).
static func hero_allows(card: String, id: String) -> bool:
	if not CardDB.HERO_MAX_ATK.has(card):
		return true
	var d := CardDB.get_def(id)
	return d.get("kind", "") != "creature" or int(d.get("atk", 0)) <= int(CardDB.HERO_MAX_ATK[card])


## Whether the lands can pay for a card: as many lands of its type as it costs
## (a rainbow card counts every land).
func payable(id: String) -> bool:
	var d := CardDB.get_def(id)
	var have: int = lands.size() if d["land"] == RAINBOW else lands.count(d["land"])
	return int(d["cost"]) <= have


# ---------------------------------------------------------------- steps

## The player goes through door i.
func enter(i: int) -> void:
	_note("enter", [i])
	if phase != "doors" or i < 0 or i >= doors.size():
		return
	current = doors[i]
	doors = []
	match String(current["kind"]):
		"rest":
			phase = "rest"
		"shop":
			_stock_shop()
			phase = "shop"
		"event":
			event = {"id": String(current["event"]), "stage": "options", "pick": "", "result": "", "got": []}
			if not seen_events.has(event["id"]):
				seen_events.append(event["id"])
			phase = "event"
		"treasure":
			_offer_items(int(ITEM_OFFERS["treasure"]) + (1 if _dark() else 0))
			phase = "item"
			if item_offers.is_empty():      # every item is taken: a card instead
				picks_left = 1
				_offer_cards([])
				phase = "reward"
		_:
			phase = "fight"
	save()


## The fight of the current wagon is won with hp_left hit points: level-ups, an item
## and trophies next. A win heals FIGHT_HEAL, a boss BOSS_HEAL (items add).
func fight_won(hp_left: int, revived := false) -> void:
	_note("fight_won", [hp_left, revived])
	if phase != "fight":
		return
	if revived:      # Слеза Принцессы Пламени saved the hero in this fight: it is gone for good
		items.erase("princess_tear")
	wins += 1
	hp = clampi(hp_left, 1, max_hp)
	max_hp += bonus("hp_per_win")
	hp += bonus("hp_per_win")
	var kind := String(current["kind"])
	if kind == "boss":
		bosses += 1
	hp = clampi(hp + {"boss": BOSS_HEAL, "double": DOUBLE_HEAL}.get(kind, FIGHT_HEAL) + bonus("win_heal") + penalty("win_heal"), 1, max_hp)
	last_enemy = String(current["enemy"])
	picks_left = int(PICKS.get(kind, 1))
	_offer_cards(_beaten())
	phase = "reward"
	var n_items: int = ITEM_OFFERS.get(kind, 0)
	if kind == "fight" and rng.randf() < FIGHT_ITEM_CHANCE:
		n_items = 1
	elif kind == "double" and rng.randf() >= DOUBLE_ITEM_CHANCE:
		n_items = 0
	if _dark():         # one more item in the offer, or a trophy when there is none
		if n_items > 0:
			n_items += 1
		else:
			picks_left += 1
	_offer_items(n_items, kind == "boss", String(TrainItems.TROPHIES.get(String(current["enemy"]), "")) if kind == "boss" else "")
	if not item_offers.is_empty():
		phase = "item"
	var coin := coin_reward(kind)
	coins += roundi(coin * DARK_COINS) if _dark() else coin
	hp = maxi(hp - bonus("fight_loss"), 1)
	_gain_xp(int(XP.get(kind, 1)) + bonus("xp_win") + (bonus("xp_elite") if kind == "elite" else 0))
	if levels_due > 0:
		_offer_perks()
		phase = "level"
	save()


## Experience: every level it fills adds one level-up to levels_due.
func _gain_xp(amount: int) -> void:
	xp += amount
	while xp >= xp_needed():
		xp -= xp_needed()
		level += 1
		levels_due += 1


## A level-up: raises one of the offered stats. The item and the trophies come after
## the last one.
func pick_perk(key: String) -> void:
	_note("pick_perk", [key])
	if phase != "level" or not perks.has(key):
		return
	if key == "max_hp":
		max_hp += stat_step(key)
		hp += stat_step(key)
	else:
		stats[key] = mini(int(stats.get(key, 0)) + stat_step(key), stat_cap(key))
	levels_due -= 1
	if levels_due > 0:
		_offer_perks()
	else:
		perks = []
		phase = "reward" if item_offers.is_empty() else "item"
	save()


## Takes an offered item. Its max HP count now (the current HP grow with them, never
## drop below 1).
func take_item(id: String) -> void:
	_note("take_item", [id])
	if phase != "item" or not item_offers.has(id):
		return
	_add_item(id)
	_leave_items()


## The item is the hero's now.
func _add_item(id: String) -> void:
	items.append(id)
	_grow_max_hp(int(TrainItems.item(id)["mods"].get("max_hp", 0)))


## Max HP change for good (the item's max_hp): the current HP grow with it, never below 1.
func _grow_max_hp(more: int) -> void:
	max_hp = maxi(max_hp + more, 1)
	hp = clampi(hp + maxi(more, 0), 1, max_hp)


## Leaves the items.
func skip_item() -> void:
	_note("skip_item", [])
	if phase == "item":
		_leave_items()


## After the item: the trophies of a fight, the next wagon after a chest.
func _leave_items() -> void:
	item_offers = []
	if String(current.get("kind", "")) == "treasure":
		_finish_wagon()
	else:
		phase = "reward"
		save()


## The run is over (a fight is lost or the player gave up). The save is removed. `by_fight`: it was
## the wagon being played that ended the run (kept in `fell` for the chronicle).
func lose(by_fight := false) -> void:
	_note("lose", [by_fight])
	fell = {}
	if by_fight and phase == "fight":
		fell = _chronicle_entry()
	hp = 0
	phase = "over"
	if save_path != "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))


## Takes an offered card into the deck.
func take(id: String) -> void:
	_note("take", [id])
	if phase != "reward" or not offers.has(id):
		return
	cards[id] = int(cards.get(id, 0)) + 1
	if pool.has(id):
		pool[id] = int(pool[id]) - 1
		if int(pool[id]) <= 0:
			pool.erase(id)
	picks_left -= 1
	if picks_left > 0:
		_offer_cards(_beaten())
		save()
	else:
		_finish_wagon()


## Leaves the trophies: a hurt hero gets SKIP_HEAL HP back, a full one SKIP_XP experience. The
## level-ups it fills wait for the next won fight (fight_won offers them).
func skip() -> void:
	_note("skip", [])
	if phase != "reward":
		return
	if hp < max_hp:
		hp = mini(hp + SKIP_HEAL, max_hp)
	else:
		_gain_xp(SKIP_XP)
	_finish_wagon()


func rest_heal() -> void:
	_note("rest_heal", [])
	if phase == "rest":
		hp = mini(hp + rest_amount(), max_hp)
		_finish_wagon()


func can_remove() -> bool:
	return deck_size() > min_deck()


## Throws one copy of a card out of the deck (a rest instead of healing): an improved
## one when `improved` is asked for (and there is one), else a plain one if there is one.
func remove_card(id: String, improved := false) -> void:
	_note("remove_card", [id, improved])
	if phase == "rest" and _throw_out(id, improved):
		_finish_wagon()


## Takes one copy of a card out of the deck (the plain one first). False when it cannot go.
func _throw_out(id: String, improved: bool) -> bool:
	if not cards.has(id) or not can_remove():
		return false
	var ups := upgrade_count(id)
	if ups > 0 and (improved or ups >= int(cards[id])):
		upgraded[id] = ups - 1
		if ups == 1:
			upgraded.erase(id)
	cards[id] = int(cards[id]) - 1
	if int(cards[id]) <= 0:
		cards.erase(id)
		upgraded.erase(id)
	return true


## Whether a card is better for an improvement: a creature always, a spell or a building
## when it costs something.
static func upgradable(id: String) -> bool:
	var d := CardDB.get_def(id)
	return d["kind"] == "creature" or int(d["cost"]) > 0


## What the improvement does to a card, as a short label: "+1/+1" or "−1".
static func upgrade_text(id: String) -> String:
	return "+1/+1" if CardDB.get_def(id)["kind"] == "creature" else "−1"


## Improved copies of a card in the run deck.
func upgrade_count(id: String) -> int:
	return int(upgraded.get(id, 0))


## Copies of a card that are not improved yet.
func plain_count(id: String) -> int:
	return int(cards.get(id, 0)) - upgrade_count(id)


func can_upgrade(id: String) -> bool:
	return phase in ["rest", "shop"] and plain_count(id) > 0 and upgradable(id)


## Whether any card of the deck can still be improved, in any phase.
func _has_plain_upgrades() -> bool:
	for id: String in cards:
		if plain_count(id) > 0 and upgradable(id):
			return true
	return false


## Whether a rest has any card to improve.
func has_upgrades() -> bool:
	for id: String in cards:
		if can_upgrade(id):
			return true
	return false


## Improves one copy of a card (a rest instead of healing).
func upgrade_card(id: String) -> void:
	_note("upgrade_card", [id])
	if phase == "rest" and can_upgrade(id):
		upgraded[id] = upgrade_count(id) + 1
		_finish_wagon()


## Changes the land of one lane into another type (a rest instead of healing).
func change_land(lane: int, type: String) -> void:
	_note("change_land", [lane, type])
	if phase != "rest" or lane < 0 or lane >= lands.size() or type == lands[lane] or not CardDB.land_types().has(type):
		return
	lands[lane] = type
	_finish_wagon()


# ---------------------------------------------------------------- curses

## A curse of the Lich is the hero now.
func add_curse(id: String) -> void:
	if curses.has(id) or not TrainItems.CURSES.has(id):
		return
	curses.append(id)
	_grow_max_hp(int(TrainItems.curse(id)["mods"].get("max_hp", 0)))
	save()


## The curse sale of a shop: a random curse goes to the hero and every price of this shop is halved
## (shop_price), once a visit.
func can_sale() -> bool:
	return phase == "shop" and not bool(shop.get("sale", false)) and not _curses_left().is_empty()


func shop_sale() -> void:
	_note("shop_sale", [])
	if not can_sale():
		return
	shop["sale"] = true
	add_curse(_roll_curse())


## A curse is taken off: its max HP come back.
func remove_curse(id: String) -> void:
	if not curses.has(id):
		return
	curses.erase(id)
	_grow_max_hp(-int(TrainItems.curse(id)["mods"].get("max_hp", 0)))
	save()


## The curses the hero has not got yet (the random numbers are not used here).
func _curses_left() -> Array:
	var ids := []
	for id: String in TrainItems.CURSES:
		if not curses.has(id):
			ids.append(id)
	return ids


## A random curse the hero has not got, "" when it has them all.
func _roll_curse() -> String:
	var ids := _curses_left()
	return "" if ids.is_empty() else String(ids[rng.randi() % ids.size()])


# ---------------------------------------------------------------- events

## The events that can come in wagon w: not met yet in this run (when all were met, all again),
## and the ones that need a curse only for a hero who has one.
func _events_open(w: int) -> Array:
	var ids := []
	for id: String in TrainEvents.EVENTS:
		var ev: Dictionary = TrainEvents.event(id)
		if w >= int(ev["from"]) and (ev["needs"] != "curse" or not curses.is_empty()):
			ids.append(id)
	var fresh := ids.filter(func(id): return not seen_events.has(id))
	return fresh if not fresh.is_empty() else ids


func _pick_event(w: int) -> String:
	var ids := _events_open(w)
	return ids[rng.randi() % ids.size()]


func event_options() -> Array:
	return TrainEvents.options(String(event["id"]))


## Why option i cannot be taken, a short line; "" when it can.
func event_block(i: int) -> String:
	var opt: Dictionary = event_options()[i]
	var fx: Dictionary = opt.get("cost", {}).duplicate()
	fx.merge(opt.get("gain", {}))
	for key: String in fx:
		var n := int(fx[key])
		var is_cost: bool = opt.get("cost", {}).has(key)
		match key:
			"hp":
				if is_cost and hp <= n:
					return "Не хватает HP"
			"coins":
				if is_cost and coins < n:
					return "Не хватает монет"
			"curse":
				if _curses_left().is_empty():      # the screen asks this: no random numbers here
					return "Проклятий нет"
			"remove":
				if not can_remove():
					return "Колода мала"
			"upgrade":
				if not _has_plain_upgrades():
					return "Нечего улучшать"
			"uncurse":
				if curses.is_empty():
					return "Проклятий нет"
	return ""


## Takes option i of the event: the price and the reward at once; a card or a curse to
## pick comes next (stage "pick"), else the result.
func choose_event(i: int) -> void:
	_note("choose_event", [i])
	if phase != "event" or event["stage"] != "options" or i < 0 or i >= event_options().size() or event_block(i) != "":
		return
	var opt: Dictionary = event_options()[i]
	var got: Array = []
	var pick := ""
	var result := String(opt.get("result", ""))
	if opt.has("chance"):
		var ch: Dictionary = opt["chance"]
		var won := rng.randi() % 100 < int(ch["p"])
		pick = _apply_effects(ch["win"] if won else ch["lose"], not won, got)
		result = String(opt["win_result"] if won else opt["lose_result"])
	else:
		pick = _apply_effects(opt.get("cost", {}), true, got)
		var more := _apply_effects(opt.get("gain", {}), false, got)
		pick = more if more != "" else pick
	event["result"] = result
	event["got"] = got
	event["stage"] = "result" if pick == "" else "pick"
	event["pick"] = pick
	save()


## Applies effects: what is lost (cost) or what is given. Returns the pick still to be
## made ("remove" | "upgrade" | "curse"), adds what happened to `got`.
func _apply_effects(fx: Dictionary, cost: bool, got: Array) -> String:
	var pick := ""
	for key: String in fx:
		var n := int(fx[key])
		match key:
			"hp":
				if cost:
					hp = maxi(hp - n, 1)
				else:
					hp = mini(hp + n, max_hp)
				got.append(("−%d HP" if cost else "+%d HP") % n)
			"coins":
				coins = maxi(coins + (-n if cost else n), 0)
				got.append(("−" if cost else "+") + coins_text(n))
			"max_hp":
				_grow_max_hp(-n if cost else n)
				got.append(("Макс. HP −%d" if cost else "Макс. HP +%d") % n)
			"curse":
				for k in n:
					var id := _roll_curse()
					if id != "":
						add_curse(id)
						got.append("Проклятие: " + String(TrainItems.curse(id)["name"]))
			"item", "item_rare":
				var found := _roll_items(n, key == "item_rare")
				for id: String in found:
					_add_item(id)
					got.append("Предмет: " + String(TrainItems.item(id)["name"]))
				if found.is_empty():        # every item is taken: coins instead
					coins += 15
					got.append("+" + coins_text(15))
			"card":
				for id: String in _roll_cards(n):
					cards[id] = int(cards.get(id, 0)) + 1
					if pool.has(id):
						pool[id] = int(pool[id]) - 1
						if int(pool[id]) <= 0:
							pool.erase(id)
					got.append("Карта: " + String(CardDB.get_def(id)["name"]))
			"stat":
				for k in n:
					var line := _raise_random_stat()
					if line != "":
						got.append(line)
			"remove":
				pick = "remove"
			"upgrade":
				pick = "upgrade"
			"uncurse":
				pick = "curse"
	return pick


## A random stat grows one step, as at a level-up. Returns what grew, "" when all are at the top.
func _raise_random_stat() -> String:
	var keys := []
	for key: String in STATS:
		if stat(key) < stat_cap(key) and (key == "max_hp" or int(stats.get(key, 0)) < stat_cap(key)):
			keys.append(key)
	if keys.is_empty():
		return ""
	var key: String = keys[rng.randi() % keys.size()]
	var step := stat_step(key)
	if key == "max_hp":
		_grow_max_hp(step)
	else:
		stats[key] = mini(int(stats.get(key, 0)) + step, stat_cap(key))
	return "%s +%s" % [STATS[key]["name"], stat_text(key, step)]


## n different cards the lands can pay for, of any deck.
func _roll_cards(n: int) -> Array:
	var ids: Array = CardDB.card_ids().duplicate()
	_shuffle(ids)
	var out := []
	for id: String in ids:
		if out.size() >= n:
			break
		if _gives(id) and payable(id):
			out.append(id)
	return out


## The card (or the curse) the event asked for is picked. `improved`: the improved copy goes.
func event_pick(id: String, improved := false) -> void:
	_note("event_pick", [id, improved])
	if phase != "event" or event["stage"] != "pick":
		return
	match String(event["pick"]):
		"remove":
			if not _throw_out(id, improved):
				return
			event["got"].append("Карта убрана")
		"upgrade":
			if plain_count(id) <= 0 or not upgradable(id):
				return
			upgraded[id] = upgrade_count(id) + 1
			event["got"].append("Карта улучшена")
		"curse":
			if not curses.has(id):
				return
			remove_curse(id)
			event["got"].append("Снято: " + String(TrainItems.curse(id)["name"]))
	event["stage"] = "result"
	event["pick"] = ""
	save()


## The event is left without taking anything.
func leave_event() -> void:
	_note("leave_event", [])
	if phase == "event" and event["stage"] == "options":
		event = {}
		_finish_wagon()


## The result is read: on to the next wagon.
func finish_event() -> void:
	_note("finish_event", [])
	if phase == "event" and event["stage"] == "result":
		event = {}
		_finish_wagon()


## "1 монета", "3 монеты", "5 монет".
static func coins_text(n: int) -> String:
	return TrainEvents.coins_text(n)


# ---------------------------------------------------------------- coins and the shop

## Coins a won fight of this kind gives.
func coin_reward(kind: String) -> int:
	var base := int(COIN_WIN.get(kind, 0))
	return maxi(roundi(base * (100 + penalty("coins_pct")) / 100.0), 1) if base > 0 else 0


static func card_price(id: String) -> int:
	return PRICE_CARD + PRICE_PER_COST * int(CardDB.get_def(id)["cost"])


static func item_price(id: String) -> int:
	return int(PRICE_ITEM[TrainItems.item(id)["rarity"]])


## The shelf of a shop: cards the lands can pay for (two of the other half of the ready
## deck when it has any, the rest of any deck), items the hero has not got. Every service
## (a card improved, thrown out, a curse taken off) can be bought once. The curse sale (shop_sale)
## takes a curse and halves every price of the shop (`sale`), once a visit too.
func _stock_shop() -> void:
	shop = {"upgrade": true, "remove": true, "uncurse": true, "sale": false, "rerolls": 0}
	_fill_shelf()


## The cards and the items on the shelf of the shop (a new one, or a roll of it).
func _fill_shelf() -> void:
	var ids: Array = []
	for src: Array in [[pool.keys(), SHOP_CARDS - 2], [CardDB.card_ids(), SHOP_CARDS]]:
		var mine: Array = src[0].duplicate()
		_shuffle(mine)
		for id: String in mine:
			if ids.size() >= int(src[1]):
				break
			if not ids.has(id) and _gives(id) and payable(id):
				ids.append(id)
	shop["cards"] = ids
	shop["items"] = _roll_items(SHOP_ITEMS, false)


## What the next roll of the shelf costs: the price grows with every roll of this shop.
func reroll_price() -> int:
	return shop_price(PRICE_REROLL + int(shop.get("rerolls", 0)))


## Pays for a new shelf: the cards and the items are rolled again (once more every time).
func shop_reroll() -> void:
	_note("shop_reroll", [])
	if phase != "shop" or not can_pay(reroll_price()):
		return
	coins -= reroll_price()
	shop["rerolls"] = int(shop.get("rerolls", 0)) + 1
	_fill_shelf()
	save()


func can_pay(price: int) -> bool:
	return coins >= price


## Buys one of the cards on the shelf.
func buy_card(id: String) -> void:
	_note("buy_card", [id])
	if phase != "shop" or not shop["cards"].has(id) or not can_pay(shop_price(card_price(id))):
		return
	coins -= shop_price(card_price(id))
	shop["cards"].erase(id)
	cards[id] = int(cards.get(id, 0)) + 1
	if pool.has(id):
		pool[id] = int(pool[id]) - 1
		if int(pool[id]) <= 0:
			pool.erase(id)
	save()


## Buys one of the items on the shelf.
func buy_item(id: String) -> void:
	_note("buy_item", [id])
	if phase != "shop" or not shop["items"].has(id) or not can_pay(shop_price(item_price(id))):
		return
	coins -= shop_price(item_price(id))
	shop["items"].erase(id)
	_add_item(id)
	save()


## Pays for improving a copy of a card (once in a shop visit).
func shop_upgrade(id: String) -> void:
	_note("shop_upgrade", [id])
	if phase != "shop" or not shop["upgrade"] or not can_pay(shop_price(PRICE_UPGRADE)) or not can_upgrade(id):
		return
	coins -= shop_price(PRICE_UPGRADE)
	shop["upgrade"] = false
	upgraded[id] = upgrade_count(id) + 1
	save()


## Pays for throwing a card out of the deck (once in a shop visit).
func shop_remove(id: String, improved := false) -> void:
	_note("shop_remove", [id, improved])
	if phase != "shop" or not shop["remove"] or not can_pay(shop_price(PRICE_REMOVE)):
		return
	if _throw_out(id, improved):
		coins -= shop_price(PRICE_REMOVE)
		shop["remove"] = false
		save()


## Pays for taking a curse off (once in a shop visit).
func shop_uncurse(id: String) -> void:
	_note("shop_uncurse", [id])
	if phase != "shop" or not shop.get("uncurse", false) or not can_pay(shop_price(PRICE_UNCURSE)) or not curses.has(id):
		return
	coins -= shop_price(PRICE_UNCURSE)
	shop["uncurse"] = false
	remove_curse(id)


## The shop is left.
func leave_shop() -> void:
	_note("leave_shop", [])
	if phase == "shop":
		shop = {}
		_finish_wagon()


## The wagon being played as the chronicle writes it.
func _chronicle_entry() -> Dictionary:
	var e := {"kind": String(current.get("kind", "")), "enemy": String(current.get("enemy", "")), "wagon": String(current.get("wagon", ""))}
	if current.has("second"):
		e["second"] = String(current["second"]["enemy"])
	return e


func _finish_wagon() -> void:
	chronicle.append(_chronicle_entry())
	history.append(String(current.get("kind", "")))
	met.append(String(current.get("enemy", "")))
	wagons.append(String(current.get("wagon", "")))
	wagon += 1
	passed += 1
	offers = []
	picks_left = 0
	if wagon >= TRAIN_LEN:
		train += 1
		wagon = 0
		history = []
		met = []
		wagons = []
	_make_doors()
	save()


# ---------------------------------------------------------------- generation

## Two doors (sometimes three) to the next wagon; the locomotive has one, its boss.
## Right before the locomotive one of the doors is always a rest.
func _make_doors() -> void:
	if daily != "":
		rng.seed = (seed_value * 31 + passed * 7919 + 13) & 0x7fffffff
	phase = "doors"
	current = {}
	doors = []
	var w := wagon + 1
	if w == TRAIN_LEN:
		doors.append(_fight_door("boss"))
		var boss_rule := TrainWagons.boss_rule(String(doors[0]["enemy"]))
		if boss_rule != "":
			doors[0]["wagon"] = boss_rule
		return
	var count := 3 if w >= 3 and rng.randf() < 0.35 else 2
	var kinds := []                 # {kind, dark} of each door
	if w == TRAIN_LEN - 1:
		kinds.append({"kind": "rest", "dark": false})
	while kinds.size() < count:
		var k := _door_kind(w)
		var dark := k == "dark"
		if dark:
			if not kinds.filter(func(d): return d["dark"]).is_empty():
				continue
			k = _dark_kind(kinds)
		elif k in ["rest", "treasure", "double", "shop", "event"] and not kinds.filter(func(d): return d["kind"] == k).is_empty():
			continue
		kinds.append({"kind": k, "dark": dark})
	for d: Dictionary in kinds:
		var k: String = d["kind"]
		if FIGHTS.has(k):
			doors.append(_fight_door(k))
		elif k == "event":
			doors.append({"kind": "event", "event": _pick_event(w)})
		else:
			doors.append({"kind": k})
		if d["dark"]:
			doors[-1]["dark"] = true
	var fights := []
	for i in doors.size():
		if FIGHTS.has(doors[i]["kind"]):
			fights.append(i)
	if not fights.is_empty():
		var rule := _pick_wagon(w)
		if rule != "":
			doors[fights[rng.randi() % fights.size()]]["wagon"] = rule


## The rule of a wagon, rarer the harder it is: never the rule of the wagon just passed,
## no more than HEAVY_PER_TRAIN heavy ones a train, the first wagons light or festive.
func _pick_wagon(w: int) -> String:
	var last := String(wagons.back()) if not wagons.is_empty() else ""
	var heavy := wagons.filter(func(id): return id != "" and TrainWagons.wagon(id)["level"] == "heavy").size()
	var ids := []
	var total := 0
	for id: String in TrainWagons.WAGONS:
		var lv := String(TrainWagons.wagon(id)["level"])
		if lv == "boss" or id == last or (lv == "heavy" and heavy >= TrainWagons.HEAVY_PER_TRAIN):
			continue
		if w <= TrainWagons.EASY_START and not lv in ["light", "festive"]:
			continue
		ids.append(id)
		total += int(TrainWagons.LEVELS[lv]["weight"])
	if total <= 0:
		return ""
	var r := rng.randi() % total
	for id: String in ids:
		r -= int(TrainWagons.level(id)["weight"])
		if r < 0:
			return id
	return ""


## The kind hidden behind a dark door: one of DARK_KINDS that the wagon can still have (one chest a wagon).
func _dark_kind(kinds: Array) -> String:
	var choices := []
	for k: String in DARK_KINDS:
		if k != "treasure" or kinds.filter(func(d): return d["kind"] == k).is_empty():
			choices.append(k)
	return choices[rng.randi() % choices.size()]


## Whether the door of the wagon being played is a dark one (its wagon is hidden until it is entered).
func _dark() -> bool:
	return bool(current.get("dark", false))


func _door_kind(w: int) -> String:
	var after_rest: bool = not history.is_empty() and history.back() == "rest"
	var after_shop: bool = not history.is_empty() and history.back() == "shop"
	var after_event: bool = not history.is_empty() and history.back() == "event"
	var weights := {"fight": 50, "elite": 20 + penalty("elite_weight") if w >= 3 else 0, "rest": 18 if w >= 3 and not after_rest else 0,
		"treasure": 12 if w >= 2 else 0, "double": DOUBLE_WEIGHT if w >= DOUBLE_FROM else 0,
		"shop": SHOP_WEIGHT if w >= SHOP_FROM and not after_shop else 0,
		"event": EVENT_WEIGHT if w >= EVENT_FROM and not after_event and not _events_open(w).is_empty() else 0,
		"dark": DARK_WEIGHT if w >= DARK_FROM else 0}
	var total := 0
	for k in weights:
		total += int(weights[k])
	var r := rng.randi() % total
	for k: String in weights:
		r -= int(weights[k])
		if r < 0:
			return k
	return "fight"


## A fight door: an enemy deck not met right before and not behind another door,
## its hit points and AI level, and the seed of its game (the same when it starts over).
## A double door has the second enemy as well, another deck.
func _fight_door(kind: String) -> Dictionary:
	var taken := []
	for d: Dictionary in doors:
		taken.append(d.get("enemy", ""))
		taken.append(d.get("second", {}).get("enemy", ""))
	var enemy := _pick_enemy(kind, taken)
	var door := {"kind": kind, "enemy": enemy, "hp": _enemy_hp(kind, enemy),
		"level": _enemy_level(kind), "seed": rng.randi() & 0x7fffffff, "stats": _enemy_stats(kind)}
	if kind == "double":
		taken.append(door["enemy"])
		door["second"] = {"enemy": _pick_enemy(kind, taken), "hp": _enemy_hp(kind), "level": _enemy_level(kind), "stats": _train_stats(kind)}
	return door


## A deck for an enemy that is not the player's, not just met and not in `taken`.
func _pick_enemy(kind: String, taken: Array) -> String:
	var choices := []
	for id: String in (BOSSES if kind == "boss" else CardDB.hero_ids()):
		if CardDB.has_hero(id) and id != deck_id and id != last_enemy and not taken.has(id):
			choices.append(id)
	if choices.is_empty():
		choices = CardDB.hero_ids().filter(func(id): return id != deck_id and not taken.has(id))
	return choices[rng.randi() % choices.size()]


## Fights are short at first; every wagon passed adds HP_PER_WAGON.
func _enemy_hp(kind: String, enemy := "") -> int:
	var base: int = {"boss": BOSS_HP, "elite": ELITE_HP}.get(kind, FIGHT_HP)
	var pct: int = int(BOSS_HP_PCT.get(enemy, 100)) if kind == "boss" else 100
	var hp_base := roundi((base + floori(passed * HP_PER_WAGON)) * (100 + int(HP_TRAIN_PCT.get(kind, 5)) * (train - 1)) * pct / 10000.0)
	hp_base = roundi(hp_base * (100 + LATE_HP_PCT * late_tier(kind)) / 100.0)
	return hp_base + penalty("enemy_hp")


# Late wagons (train rules 4): from LATE_FROM on the enemies get stronger, and with a big step every LATE_EVERY
# wagons. late_tier is the number of steps passed; past LATE_SOFT of them every third one counts, so a run
# that is a few hundred wagons long does not meet a wall. An elite and a boss are one step ahead.
const LATE_FROM := 100
const LATE_EVERY := 50
const LATE_SOFT := 3
const LATE_HP_PCT := 6          # more hit points for every step, percent (measured: docs/BALANCE.md)
## What the late steps add to every enemy: the stat grows by `per` for every `every` steps, at most `max`.
const LATE_STATS := {
	"atk": {"per": 1, "every": 4, "max": 4},
	"crit": {"per": 2, "every": 1, "max": 20},
	"crit_dmg": {"per": 8, "every": 1, "max": 60},
	"armor": {"per": 1, "every": 5, "max": 2},
	"regen": {"per": 1, "every": 5, "max": 2},
	"thorns": {"per": 1, "every": 4, "max": 3},
	"dodge": {"per": 2, "every": 1, "max": 20},
	"lifesteal": {"per": 3, "every": 1, "max": 30},
	"actions": {"per": 1, "every": 6, "max": 1},
}
## Rules an enemy gets like the hero's items (from this step on, who gets it: "all" or "strong": an elite and a boss).
const LATE_RULES := {"first_crit": [4, "all"], "last_stand": [3, "strong"], "revive": [5, "strong"]}
## How these rules read in the enemy's line on its door.
const ENEMY_RULE_NAMES := {"first_crit": "Травяной меч", "last_stand": "Желание Призмо", "revive": "Слеза"}


func late_tier(kind := "fight") -> int:
	if train_rules < 4 or passed < LATE_FROM:
		return 0
	var t := (passed - LATE_FROM) / LATE_EVERY + 1 + (1 if kind in ["elite", "boss"] else 0)
	return t if t <= LATE_SOFT else LATE_SOFT + (t - LATE_SOFT) / 3


## The stats and rules of the late steps for an enemy of this kind (see LATE_STATS, LATE_RULES).
func _late_stats(kind: String) -> Dictionary:
	var out := {}
	var t := late_tier(kind)
	if t == 0:
		return out
	for key: String in LATE_STATS:
		var spec: Dictionary = LATE_STATS[key]
		var n := mini(t / int(spec["every"]) * int(spec["per"]), int(spec["max"]))
		if n > 0:
			out[key] = n
	for key: String in LATE_RULES:
		var rule: Array = LATE_RULES[key]
		if t >= int(rule[0]) and (rule[1] == "all" or kind in ["elite", "boss"]):
			out[key] = 1
	return out


## The AI starts at its weakest and gets a level stronger every WAGONS_PER_LEVEL
## wagons; an elite and a boss play one level above.
func _enemy_level(kind: String) -> String:
	var k := floori((passed + 1) / float(WAGONS_PER_LEVEL)) + (0 if kind in ["fight", "double"] else 1) + penalty("ai_level")
	return LEVELS[clampi(k, 0, LEVELS.size() - 1)]


## How much a level-up (or an event) adds to a stat. From train rules 3 the percent stats grow
## slowly (the steps of STATS were 8, 50, 7, 25, 20): with no top they would be maxed in a few levels.
const SLOW_STEPS := {"crit": 2, "crit_dmg": 10, "dodge": 2, "lifesteal": 3, "draw": 3}


func stat_step(key: String) -> int:
	if train_rules >= 3 and SLOW_STEPS.has(key):
		return int(SLOW_STEPS[key])
	return int(STATS[key]["step"])


## The top of a hero stat (STATS), items and level-ups together. Rules 1 and 2: every stat has one,
## the health too, and with all at the top a level-up had nothing to offer (a run stuck at level 53).
## Rules 3 had none, and the bonuses of a hundred items took the dodge past 100%. From rules 4 the
## tops are back for everything but the health: it can always grow, so a level-up always offers it.
func stat_cap(key: String) -> int:
	if train_rules == 3 or train_rules >= 4 and key == "max_hp":
		return NO_CAP
	return int(STATS[key]["max"])


## PERK_OFFERS different stats that can still grow.
func _offer_perks() -> void:
	var keys := []
	for key: String in STATS:
		if stat(key) < stat_cap(key) and (key == "max_hp" or int(stats.get(key, 0)) < stat_cap(key)):
			keys.append(key)
	_shuffle(keys)
	perks = keys.slice(0, PERK_OFFERS)


## Elites and bosses get ENEMY_STAT_COUNT stats, one more every train after the first.
func _enemy_stats(kind: String) -> Dictionary:
	var n: int = ENEMY_STAT_COUNT.get(kind, 0)
	if n == 0:
		return _train_stats(kind)
	if kind == "elite":
		n += penalty("elite_stats")
	var keys: Array = ENEMY_STATS.keys()
	_shuffle(keys)
	var out := {}
	for key: String in keys.slice(0, mini(n + train - 1, keys.size())):
		out[key] = ENEMY_STATS[key]
	var more := _train_stats(kind)
	for key: String in more:
		out[key] = int(out.get(key, 0)) + int(more[key])
	return out


## What every enemy has on top (TRAIN_STATS): the stats of its kind grow with the train, a locomotive is a train ahead.
func _train_stats(kind := "fight") -> Dictionary:
	var out := {}
	for key: String in TRAIN_STATS:
		var spec: Dictionary = TRAIN_STATS[key]
		var tr := train + (1 if kind in ["elite", "boss"] and train > 1 and key != "actions" else 0)
		if tr >= int(spec["from"]):
			out[key] = mini((tr - int(spec["from"]) + 1) * int(spec["step"]), int(spec["max"]))
	var late := _late_stats(kind)
	for key: String in late:
		out[key] = int(out.get(key, 0)) + int(late[key])
	return out


## n different items the hero has not got, rarer ones less often; rare: no common ones.
## A beaten locomotive offers its trophy first (unless the hero has it), the rest rolled.
func _offer_items(n: int, rare := false, trophy := "") -> void:
	item_offers = []
	if trophy != "" and not items.has(trophy):
		item_offers.append(trophy)
	item_offers.append_array(_roll_items(n - item_offers.size(), rare))


## Items for the rewards and the shop: never the trophies of the locomotives. An item the
## hero has can come again as a copy (its mods add up), half as often as a new one, and
## only while the copy still does something (copy_useful).
func _roll_items(n: int, rare: bool) -> Array:
	var out := []
	var ids := []
	for id: String in TrainItems.ITEMS:
		if not TrainItems.is_trophy(id) and not (rare and TrainItems.item(id)["rarity"] == "common") and (not items.has(id) or train_rules >= 2 and copy_useful(id)):
			ids.append(id)
	while out.size() < n and not ids.is_empty():
		var total := 0
		for id: String in ids:
			total += _item_weight(id)
		var r := rng.randi() % total
		for id: String in ids:
			r -= _item_weight(id)
			if r < 0:
				out.append(id)
				ids.erase(id)
				break
	return out


func _item_weight(id: String) -> int:
	if train_rules < 2:
		return int(TrainItems.rarity(id)["weight"])
	return int(TrainItems.rarity(id)["weight"]) * (1 if items.has(id) else 2)


## Rules of the fight a second copy adds nothing to: they work once, or just are on.
const ONCE_RULES := ["first_free", "first_crit", "first_return", "last_stand", "no_freeze", "third_spell",
	"kill_action", "death_draw", "spell_draw", "floop_draw", "spell_cheap", "rainbow_cheap"]


## Whether one more copy of an item the hero has would change anything: a mod that is
## not a once-only rule and, for a stat with a top (STATS), the stat is not at the top yet.
func copy_useful(id: String) -> bool:
	var mods: Dictionary = TrainItems.item(id)["mods"]
	for key: String in mods:
		if key == "min_deck":
			if int(mods[key]) < 0 and min_deck() > 1:
				return true
			continue
		if int(mods[key]) <= 0 or key in ONCE_RULES:
			continue
		if STATS.has(key) and key != "max_hp" and stat(key) >= stat_cap(key):
			continue
		return true
	return false


func offer_count() -> int:
	return maxi(OFFERS + stat("luck") + penalty("offers"), 1)


## The decks of the enemies just beaten: one, two in a double wagon.
func _beaten() -> Array:
	var out := [String(current.get("enemy", ""))]
	if current.has("second"):
		out.append(String(current["second"]["enemy"]))
	return out


## OFFERS cards the lands can pay for: after a fight up to two come from the beaten
## deck (the beaten decks together), the rest from the other half of the ready deck (or
## all of it); a chest gives cards of any deck. Удача offers more.
func _offer_cards(beaten: Array) -> void:
	offers = []
	var n := offer_count()
	var sources: Array = []
	if not beaten.is_empty() and beaten[0] != "":
		var theirs := []
		for enemy: String in beaten:
			for id: String in CardDB.hero(enemy)["deck"].keys():
				if not theirs.has(id):
					theirs.append(id)
		sources.append([theirs, n - 1])
		sources.append([pool.keys(), n])
		sources.append([CardDB.hero(deck_id)["deck"].keys(), n])
	else:
		sources.append([CardDB.card_ids(), n])
	for src in sources:
		var ids: Array = src[0].duplicate()
		_shuffle(ids)
		for id: String in ids:
			if offers.size() >= int(src[1]):
				break
			if not offers.has(id) and _gives(id) and payable(id):
				offers.append(id)


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


# ---------------------------------------------------------------- saving

func to_dict() -> Dictionary:
	return {"format": FORMAT, "seed": seed_value, "rng": str(rng.state), "deck": deck_id, "hero_card": hero_card,
		"lands": lands, "cards": cards, "upgraded": upgraded, "pool": pool, "hp": hp, "max_hp": max_hp, "stats": stats, "items": items, "item_offers": item_offers, "level": level,
		"coins": coins, "shop": shop, "event": event, "seen_events": seen_events, "curses": curses, "xp": xp, "levels_due": levels_due, "perks": perks, "train": train,
		"wagon": wagon, "passed": passed, "wins": wins, "history": history, "met": met, "wagons": wagons, "daily": daily, "phase": phase, "doors": doors,
		"current": current, "offers": offers, "picks_left": picks_left, "last_enemy": last_enemy,
		"difficulty": difficulty, "bosses": bosses, "chronicle": chronicle}


## A step of the run to its journal (see the top), with what the run is before it.
func _note(action: String, args: Array) -> void:
	_journal({"a": action, "x": args, "ph": phase, "n": passed, "c": coins, "hp": hp})


## The fight of the wagon starts (main.gd).
func note_go() -> void:
	_journal({"a": "go"})


## The run was read from its save to go on (main.gd).
func note_load() -> void:
	_journal({"a": "load", "tr": train_rules})


## What save() writes, read back (the server's check at a "load").
func reload() -> void:
	restore_from(JSON.parse_string(JSON.stringify(to_dict(), "	")))


## The fight of the wagon is over: its game goes to the journal.
func note_fight(game) -> void:
	if journal_path == "" or game.journal == null:
		return
	_journal({"a": "fight", "steps": game.journal, "hash": game.state_hash()})


func _journal(step: Dictionary) -> void:
	if journal_path == "":
		return
	var f := FileAccess.open(journal_path, FileAccess.READ_WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(JSON.stringify(step))


## The journal of the run packed for the server (gzip), empty when there is none.
func packed_journal() -> PackedByteArray:
	if journal_path == "" or not FileAccess.file_exists(journal_path):
		return PackedByteArray()
	return FileAccess.get_file_as_bytes(journal_path).compress(FileAccess.COMPRESSION_GZIP)


func save() -> void:
	if phase == "over" or save_path == "":
		return
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(to_dict(), "\t"))


## The saved run, if there is one going on. False when there is none (or it is broken).
func restore() -> bool:
	if not FileAccess.file_exists(save_path):
		return false
	return restore_from(JSON.parse_string(FileAccess.get_file_as_string(save_path)))


## The run of a save's dictionary (its text parsed). The server's check reads the run the same way
## where the game was closed and opened (note_load): a run read back is not quite the one written
## (JSON keeps the keys of the dictionaries sorted, and the random picks go through them in order).
func restore_from(d) -> bool:
	if not d is Dictionary or not int(d.get("format", 0)) in [2, 3, 4, 5, 6, 7, 8, FORMAT]:
		return false
	seed_value = int(d["seed"])
	daily = String(d.get("daily", ""))
	journal_path = save_path.get_basename() + ".log" if save_path != "" else ""
	rng.seed = seed_value
	rng.state = String(d["rng"]).to_int()
	deck_id = String(d["deck"])
	hero_card = String(d["hero_card"])
	lands = d["lands"]
	cards = _ints(d["cards"])
	upgraded = _ints(d.get("upgraded", {}))      # formats before 6: no improved cards
	for id: String in upgraded.keys():
		upgraded[id] = mini(int(upgraded[id]), int(cards.get(id, 0)))
		if int(upgraded[id]) <= 0:
			upgraded.erase(id)
	pool = _ints(d["pool"])
	hp = int(d["hp"])
	max_hp = int(d["max_hp"])
	stats = _ints(d.get("stats", START_STATS))     # format 2 runs had no stats yet
	items = d.get("items", []).filter(func(id): return TrainItems.ITEMS.has(id))   # format 3: no items
	item_offers = d.get("item_offers", []).filter(func(id): return TrainItems.ITEMS.has(id))
	coins = int(d.get("coins", 0))                      # formats before 7: no coins, no shop
	shop = _shop_from(d.get("shop", {}))
	event = d.get("event", {})
	seen_events = d.get("seen_events", []).filter(func(id): return TrainEvents.has(id))
	curses = d.get("curses", []).filter(func(id): return TrainItems.CURSES.has(id))
	level = int(d.get("level", 1))
	xp = int(d.get("xp", 0))
	levels_due = int(d.get("levels_due", 0))
	perks = d.get("perks", [])
	if String(d["phase"]) == "level" and perks.is_empty() and levels_due > 0:    # a save stuck on an empty level screen
		_offer_perks()
	train = int(d["train"])
	wagon = int(d["wagon"])
	passed = int(d["passed"])
	wins = int(d["wins"])
	history = d["history"]
	met = d["met"]
	wagons = d.get("wagons", history.map(func(_k): return ""))    # format 4: no wagon rules yet
	difficulty = clampi(int(d.get("difficulty", 0)), 0, MAX_DIFFICULTY)     # formats before 8: the plain train
	bosses = int(d.get("bosses", int(d["train"]) - 1))
	chronicle = _chronicle_from(d)
	fell = {}
	phase = String(d["phase"])
	if phase == "event" and (not event.has("id") or not TrainEvents.has(String(event["id"]))):    # an event that is gone
		phase = "rest"
		event = {}
	doors = d["doors"].map(_door_ints)
	current = _door_ints(d["current"])
	offers = d["offers"]
	picks_left = int(d["picks_left"])
	last_enemy = String(d["last_enemy"])
	return CardDB.valid_loadout(player_pick()) and phase != "over"


## The chronicle of a save. Before format 8 only the train going on was written down: the wagons
## before it are blank (no kind), so the numbers of the wagons stay right.
func _chronicle_from(d: Dictionary) -> Array:
	var out: Array = []
	for e: Dictionary in d.get("chronicle", []):
		var entry := {"kind": String(e.get("kind", "")), "enemy": String(e.get("enemy", "")), "wagon": String(e.get("wagon", ""))}
		if e.has("second"):
			entry["second"] = String(e["second"])
		out.append(entry)
	if d.has("chronicle"):
		return out
	for i in int(d["passed"]) - d["history"].size():
		out.append({"kind": "", "enemy": "", "wagon": ""})
	for i in d["history"].size():
		out.append({"kind": String(d["history"][i]), "enemy": String(d["met"][i]) if i < d["met"].size() else "",
			"wagon": String(d["wagons"][i]) if d.has("wagons") and i < d["wagons"].size() else ""})
	return out


## The shelf of a saved shop: only the cards and the items that still exist.
func _shop_from(d: Dictionary) -> Dictionary:
	if d.is_empty():
		return {}
	return {"cards": d["cards"].filter(func(id): return CardDB.has_def(id)), "items": d["items"].filter(func(id): return TrainItems.ITEMS.has(id)),
		"upgrade": bool(d["upgrade"]), "remove": bool(d["remove"]), "uncurse": bool(d.get("uncurse", true)),
		"sale": bool(d.get("sale", false)), "rerolls": int(d.get("rerolls", 0))}


func _count(ids: Array) -> Dictionary:
	var out := {}
	for id: String in ids:
		out[id] = int(out.get(id, 0)) + 1
	return out


func _ints(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[k] = int(d[k])
	return out


## JSON gives numbers back as floats.
func _door_ints(d: Dictionary) -> Dictionary:
	var out := d.duplicate()
	for k in ["hp", "seed"]:
		if out.has(k):
			out[k] = int(out[k])
	if out.has("stats"):
		out["stats"] = _ints(out["stats"])
	if out.has("second"):
		out["second"] = _door_ints(out["second"])
	if out.has("wagon") and not TrainWagons.has(String(out["wagon"])):
		out.erase("wagon")
	if out.get("kind", "") == "event" and not TrainEvents.has(String(out.get("event", ""))):
		out = {"kind": "rest"}
	return out

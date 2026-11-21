extends RefCounted
## Events of «Бесконечный поезд» (docs/TRAIN_EVENTS.md): a door with a hero of «Времени
## приключений» behind it and two or three offers, each with a price and a reward. The
## door says who is there (TrainRun._event_door), the run plays the offer
## (TrainRun.choose_event). An option is
##   text:    the label of the offer,
##   cost:    what it takes, gain: what it gives, as effects: {key: amount},
##   chance:  instead of a fixed outcome, {p: percent, win: effects, lose: effects}
##            (the effects that are not in `cost` and `gain`),
##   result:  the line after it (a chance has win_result and lose_result).
## The cost keys: hp (never to the last one), coins, max_hp, curse (a random curse of the
## Lich, train_items.gd), remove (a card of the player's choice thrown out).
## The gain keys: hp, coins, max_hp, item (a random item), item_rare (one that is not
## common), card (a random card the lands can pay for), stat (a random hero stat grows
## one step), upgrade (a card of the player's choice improved), remove (a card thrown
## out), uncurse (a curse of the player's choice taken off).
## Every event may be left without taking anything. "needs": "curse" is for an event that
## makes sense only for a hero with a curse. "art" is the hero card shown on the door ("" = none).
## "look" is what the hero does: for the description file.

const EVENTS := {
	"magic_man": {"name": "Магический человек", "art": "magic_man", "from": 2, "needs": "",
		"text": "Магический человек открывает чемодан. Всё продаётся. Почти всё бесплатно.",
		"look": "Высокий человек в плаще с карточными картинками. Чемодан у него на ремне открывается сам.",
		"options": [
			{"text": "Редкий предмет", "cost": {"curse": 1}, "gain": {"item_rare": 1},
				"result": "Чемодан захлопывается. По спине бежит холодок."},
			{"text": "Предмет за кровь", "cost": {"hp": 8}, "gain": {"item": 1},
				"result": "Короткий укол, и вещь у тебя в кармане."},
			{"text": "Фокус", "chance": {"p": 50, "win": {"item_rare": 1}, "lose": {"curse": 1}},
				"win_result": "Фокус удался. Он даже поклонился.", "lose_result": "Фокус удался. Но не тебе."},
		]},
	"mint_butler": {"name": "Мятный дворецкий", "art": "", "from": 2, "needs": "",
		"text": "Мятный дворецкий кланяется. Есть дело, не для чужих ушей.",
		"look": "Мятный человечек во фраке с двумя пуговицами. Говорит шёпотом и всё время оглядывается.",
		"options": [
			{"text": "Стереть карту", "cost": {"hp": 6}, "gain": {"remove": 1},
				"result": "Он шепчет что-то тёмное, и карта пропадает из колоды."},
			{"text": "Продать карту", "cost": {"remove": 1}, "gain": {"coins": 14},
				"result": "Он берёт карту двумя пальцами. Монеты звякают."},
			{"text": "Тёмный обряд", "cost": {"hp": 7}, "gain": {"upgrade": 1},
				"result": "Свечи гаснут. Карта становится сильнее."},
		]},
	"prismo": {"name": "Призмо", "art": "prismo", "from": 3, "needs": "",
		"text": "Призмо появляется из ниоткуда. Одно желание. Подумай хорошо.",
		"look": "Зелёный человечек с дырой вместо тела. Повсюду сыплются блёстки и жёлтые часы.",
		"options": [
			{"text": "Здоровье", "cost": {"coins": 12}, "gain": {"max_hp": 6},
				"result": "Желание сбылось. Ты чувствуешь себя крепче."},
			{"text": "Богатство", "cost": {"hp": 6}, "gain": {"coins": 16},
				"result": "Желание сбылось. Монеты сыплются из потолка."},
			{"text": "Сила", "cost": {"coins": 8}, "gain": {"stat": 1},
				"result": "Желание сбылось. Не совсем так, как хотелось."},
		]},
	"lemongrab": {"name": "Лимонохват", "art": "lemongrab", "from": 3, "needs": "",
		"text": "Неприемлемо! Лимонохват требует налог за проезд.",
		"look": "Жёлтый человек в лимонной корке. Кричит так, что звенит в вагоне.",
		"options": [
			{"text": "Заплатить налог", "cost": {"coins": 8}, "gain": {"hp": 10},
				"result": "Он доволен. И даже угощает лимонным компотом."},
			{"text": "Спеть ему", "chance": {"p": 50, "win": {"coins": 20}, "lose": {"hp": 8}},
				"win_result": "Ему понравилось! Он в слезах и платит монетами.", "lose_result": "Неприемлемо! Он бросает в тебя лимоном."},
			{"text": "Отдать карту", "cost": {"remove": 1}, "gain": {"max_hp": 6},
				"result": "Он коллекционирует карты. Тебе достаётся его уважение."},
		]},
	"tree_trunks": {"name": "Тётушка Древесная", "art": "tree_trunks", "from": 2, "needs": "",
		"text": "Тётушка Древесная печёт пирог. Угощайся, герой!",
		"look": "Слониха в красном платке с корзиной яблок. Пирог остывает на подоконнике поезда.",
		"options": [
			{"text": "Съесть пирог", "cost": {"coins": 6}, "gain": {"hp": 14},
				"result": "Вкусно. Она даже не взяла лишнего."},
			{"text": "Пирог с собой", "cost": {"coins": 12}, "gain": {"max_hp": 5},
				"result": "Тёплый свёрток греет всю дорогу."},
			{"text": "Помочь с яблоками", "cost": {"hp": 3}, "gain": {"card": 1},
				"result": "Спасибо! Вот тебе карта из её коллекции."},
		]},
	"lich": {"name": "Лич", "art": "lich", "from": 4, "needs": "",
		"text": "Лич не двигается. Сила за небольшую плату.",
		"look": "Высокий скелет в рваном плаще. Глаза зелёные, голос ниже любого колокола.",
		"options": [
			{"text": "Взять силу", "cost": {"curse": 1}, "gain": {"stat": 1, "max_hp": 5},
				"result": "Сила течёт по венам. Вместе с чем-то ещё."},
			{"text": "Взять золото", "cost": {"curse": 1}, "gain": {"coins": 25},
				"result": "Золото тяжёлое и холодное. Ты тоже теперь немного холодный."},
			{"text": "Отдать кровь", "cost": {"hp": 10}, "gain": {"stat": 1},
				"result": "Он принимает кровь молча. Сила остаётся."},
		]},
	"huntress_wizard": {"name": "Охотница-волшебница", "art": "huntress_wizard", "from": 3, "needs": "curse",
		"text": "Охотница-волшебница смотрит сквозь тебя. На тебе тень.",
		"look": "Зелёная колдунья в плаще из листьев и с ушастым совёнком на плече. Видит то, чего не видят остальные.",
		"options": [
			{"text": "Снять за кровь", "cost": {"hp": 6}, "gain": {"uncurse": 1},
				"result": "Тень сходит с тебя клочьями."},
			{"text": "Снять за монеты", "cost": {"coins": 12}, "gain": {"uncurse": 1},
				"result": "Она берёт монеты и шепчет что-то древесное. Легче."},
		]},
}


static func event(id: String) -> Dictionary:
	return EVENTS[id]


static func has(id: String) -> bool:
	return EVENTS.has(id)


static func options(id: String) -> Array:
	return EVENTS[id]["options"]


## The short lines of an effect set, for the player: ["−8 HP", "Проклятие"]. cost: what it takes.
static func lines(fx: Dictionary, cost: bool) -> Array:
	var out := []
	for key: String in fx:
		var n := int(fx[key])
		match key:
			"hp":
				out.append(("−%d HP" if cost else "+%d HP") % n)
			"coins":
				out.append(("−" if cost else "+") + coins_text(n))
			"max_hp":
				out.append(("Макс. HP −%d" if cost else "Макс. HP +%d") % n)
			"curse":
				out.append("Проклятие")
			"remove":
				out.append("Карта из колоды" if cost else "Убрать карту")
			"item":
				out.append("Предмет")
			"item_rare":
				out.append("Редкий предмет")
			"card":
				out.append("Карта")
			"stat":
				out.append("Характеристика")
			"upgrade":
				out.append("Улучшить карту")
			"uncurse":
				out.append("Снять проклятие")
	return out


## "1 монета", "3 монеты", "5 монет".
static func coins_text(n: int) -> String:
	var word := "монет"
	if n % 100 < 11 or n % 100 > 14:
		if n % 10 == 1:
			word = "монета"
		elif n % 10 in [2, 3, 4]:
			word = "монеты"
	return "%d %s" % [n, word]

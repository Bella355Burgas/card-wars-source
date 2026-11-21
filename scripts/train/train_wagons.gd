extends RefCounted
## Wagons of «Бесконечный поезд» (docs/TRAIN_WAGONS.md): a rule for one fight, the same for
## both sides. One of the fight doors to the next wagon leads into a wagon with a rule,
## and the door shows its name and rule (TrainRun._pick_wagon picks it). The locomotive's
## boss brings a rule of its own ("boss_" + the boss deck id). TrainRules.set_wagon plays the
## rule: game.gd checks `wagon` where the rule changes the game; a rule "at the start of
## the turn" or "at the end of the turn" is for the player whose turn it is.
## The boards and the AI hide what fog and night hide (TrainRules.field_hidden, numbers_hidden).
## "look" is what the wagon looks like: for its picture later.

const LEVELS := {
	"light": {"name": "Лёгкий", "weight": 10, "color": Color(0.55, 0.9, 0.5)},
	"medium": {"name": "Средний", "weight": 7, "color": Color(1.0, 0.84, 0.35)},
	"heavy": {"name": "Тяжёлый", "weight": 5, "color": Color(1.0, 0.45, 0.35)},
	"festive": {"name": "Праздник", "weight": 6, "color": Color(1.0, 0.6, 0.85)},
	"boss": {"name": "Босс", "weight": 0, "color": Color(1.0, 0.34, 0.3)},
}
const HEAVY_PER_TRAIN := 2
const EASY_START := 2           # the first wagons of a train are light or festive

const WAGONS := {
	"burning": {"name": "Горящий вагон", "level": "light",
		"text": "В начале своего хода каждый получает 1 урона.",
		"look": "Тамбур в копоти, из-под пола дым. Кто-то курил, и вагон теперь курит тоже."},
	"ice": {"name": "Ледяной вагон", "level": "medium",
		"text": "В начале своего хода у каждого замерзает случайная земля.",
		"look": "Окна в инее, сиденья покрыты коркой. Снежный король катался на коньках и ничего не убрал."},
	"lazy": {"name": "Ленивый вагон", "level": "medium",
		"text": "В конце своего хода существо, которое не атаковало, получает 1 урона.",
		"look": "На полу листья и мох. Кто не двигается, того оплетает."},
	"pb_lab": {"name": "Лаборатория Пи Би", "level": "medium",
		"text": "Каждое существо, которое входит в игру, получает 1 урона.",
		"look": "Пробирки пузырятся, на стенах чертежи. Принцесса проверяет новую версию себя."},
	"fog": {"name": "Туман", "level": "medium",
		"text": "Карт соперника не видно: рука и поле рубашкой.",
		"look": "Снаружи белое ничего. Ооо говорит, что это облако, на нём можно сидеть."},
	"night": {"name": "Ночной вагон", "level": "light",
		"text": "Не видно силы и цены карт соперника. Названия видно.",
		"look": "Свет выключен, кондукторов нет. Гантер сэкономил на лампочках."},
	"glass": {"name": "Прозрачный вагон", "level": "light",
		"text": "Руки видны обоим, поле соперника скрыто.",
		"look": "Стенки из стекла. Все видят, что у тебя в руке, и никто не видит, что ты на поле."},
	"jam": {"name": "Пробка", "level": "medium",
		"text": "У каждого одно действие за ход.",
		"look": "Пробка на Лимонной дороге. Стоять можно, ехать нельзя."},
	"lsp": {"name": "Вагон Лумпи Спейс", "level": "medium",
		"text": "В начале своего хода каждый сбрасывает случайную карту из руки.",
		"look": "Карты летают по вагону, а одна из них выпала в окно. Лумпи сказала, что они ей не идут."},
	"heat": {"name": "Жара", "level": "light",
		"text": "Существа стоят на 1 землю дороже.",
		"look": "Кондиционер сломан, на стекле капли. Снежный король ждёт, когда его починят."},
	"silence": {"name": "Тишина", "level": "heavy",
		"text": "Заклинания нельзя играть. Существа и строения можно.",
		"look": "Библиотека, все шепчут. Финн, тише."},
	"books": {"name": "Книжный вагон", "level": "festive",
		"text": "В начале хода +1 карта, если на руке меньше 4.",
		"look": "Полки до потолка, страницы шуршат сами."},
	"narrow": {"name": "Узкий проход", "level": "medium",
		"text": "Работают только две средние зоны.",
		"look": "Ооо застрял в дверях. Опять."},
	"carousel": {"name": "Карусель", "level": "light",
		"text": "В конце своего хода каждый сдвигает существ в зону вправо, с крайней на первую.",
		"look": "Парк аттракционов, всё едет по кругу, даже головы."},
	"crypt": {"name": "Склеп", "level": "medium",
		"text": "Погибшие существа возвращаются в руку владельца.",
		"look": "Пыль, гробы, мягкий свет. Лич подаёт обед, и все снова в строю."},
	"shield": {"name": "Щит Магического человека", "level": "heavy",
		"text": "Героя нельзя атаковать, пока у него есть существа на поле.",
		"look": "Человек в цилиндре стоит между героем и полем. Не любит, когда его бьют без очереди."},
	"concert": {"name": "Концерт Марселины", "level": "medium",
		"text": "У всех существ +1 ATK и −1 DEF. DEF не ниже 1.",
		"look": "Чёрный бас играет сам. Публика в шоке, особенно существа."},
	"fireworks": {"name": "Фейерверк", "level": "light",
		"text": "У всех шанс крита +20%. Уклонения нет.",
		"look": "Салют над рельсами. Кто уклонился, тот не смотрел."},
	"jake_trip": {"name": "Растяжка Джейка", "level": "medium",
		"text": "Существо, которое атакует, получает 1 урона.",
		"look": "Джейк растянулся поперёк прохода. Кто споткнулся, тот и виноват."},
	"picnic": {"name": "Пикник", "level": "festive",
		"text": "В начале своего хода каждый лечится на 1 HP, пока в колоде есть карты.",
		"look": "Пледы на полу, бутерброды на всех. Лич взял два."},
	"sugar": {"name": "Сахарный вагон", "level": "festive",
		"text": "В начале боя каждый получает +3 HP.",
		"look": "Воздух сладкий, на столе кто-то уже облизывает ложку."},
	"fair": {"name": "Ярмарка Ооо", "level": "festive",
		"text": "В стартовой руке у каждого +1 карта.",
		"look": "Прилавки с картами, торговцы улыбаются. Цену не спрашивайте."},
	"lich_dice": {"name": "Кубик Лича", "level": "heavy",
		"text": "В начале хода кубик: 1–3 — всем существам 1 урона, 4–6 — героям +2 HP, пока есть колода.",
		"look": "Кубик из льда на нитке. Лич играет с судьбой, судьба играет с Личом."},
	"gunter": {"name": "Вагон Гунтера", "level": "medium",
		"text": "В начале своего хода каждый меняет местами два своих существа.",
		"look": "Гунтер переставляет мебель. Всё на своих местах, кроме того, что нужно."},
	# The locomotives: the rule of the whole fight with the boss.
	"boss_lich": {"name": "Проклятие Лича", "level": "boss",
		"text": "В начале своего хода каждый теряет 1 HP, если на руке больше 5 карт.",
		"look": "Паровоз Лича: зелёный дым и черепа на трубе."},
	"boss_ice_king": {"name": "Метель", "level": "boss",
		"text": "Каждый третий ход одна случайная зона закрыта для обоих.",
		"look": "Паровоз Ледяного короля: снег валит прямо из топки."},
	"boss_lemongrab": {"name": "Требования Лемонграда", "level": "boss",
		"text": "Кто за ход не сыграл ни одной карты, в следующем ходу теряет действие.",
		"look": "Паровоз Лемонграда: всё жёлтое, и всё кричит «Неприемлемо!»."},
	"boss_marceline": {"name": "Укус Марселины", "level": "boss",
		"text": "Вампиризм вдвое слабее. Существо, ударившее героя, получает +1 ATK.",
		"look": "Паровоз Марселины: красные фонари и бас вместо гудка."},
}


static func has(id: String) -> bool:
	return WAGONS.has(id)


static func wagon(id: String) -> Dictionary:
	return WAGONS[id]


static func level(id: String) -> Dictionary:
	return LEVELS[WAGONS[id]["level"]]


## The rule of a boss's locomotive, "" when the boss has none.
static func boss_rule(enemy: String) -> String:
	return "boss_" + enemy if WAGONS.has("boss_" + enemy) else ""

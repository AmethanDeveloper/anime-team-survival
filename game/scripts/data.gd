class_name Data
## Все игровые числа в одном месте: герои, способности, волны. Предметы — в data_items.gd.
## Механика и структура крафта повторяют карту Anime Team Survival 4.9 (масштаб уменьшен под матч 15–25 минут).

const TEAM_NAMES: Array[String] = ["Лазурные", "Алые", "Изумрудные"]
const TEAM_COLORS: Array[Color] = [Color(0.26, 0.56, 1.0), Color(0.95, 0.27, 0.27), Color(0.25, 0.85, 0.45)]
const MONSTER_TEAM := 3

const START_GOLD := 300
const FIRST_WAVE := 20.0
const WAVE_INTERVAL := 32.0
const BOSS_EVERY := 5
## Башни лагеря (неуязвимые): урон не растёт со временем
const TOWER_DAMAGE := 65.0
const TOWER_CD := 1.1
const TOWER_RANGE := 11.0
const DUEL_INTERVAL := 300.0
const DUEL_LIMIT := 150.0
const DUEL_REWARD := 400
const MAX_LEVEL := 40

## Как атрибуты влияют на героя (как в WC3, но в масштабе этой игры)
const STR_HP := 22.0
const STR_REGEN := 0.04
const AGI_ARMOR := 0.15
const AGI_AS := 0.015
const INT_MP := 14.0
const INT_REGEN := 0.05

## Уровень героя, с которого открываются Q W E R
const UNLOCK: Array[int] = [1, 1, 1, 6, 1, 1, 1, 1, 1, 1, 1, 1]  # Q W E R, врождённая [D], сет [T], книга заклинаний
## Прокачка: очко за уровень героя. Q, W, E — до 3 уровней (уровень n — с уровня героя 2n−1), R — на 6, 11 и 16.
## Лишние очки — в атрибуты.
const SKILL_MAX: Array[int] = [3, 3, 3, 3]
const ULT_LEVELS: Array[int] = [6, 11, 16]
const STAT_POINT := 2.0
## Таланты: на этих уровнях героя — выбор одного из двух усилений
const TALENT_LEVELS: Array[int] = [10, 15, 20, 25]
const TALENTS := [
	[{"name": "+250 здоровья", "hp": 250.0}, {"name": "+20 урона", "damage": 20.0}],
	[{"name": "+25% скорости атаки", "attack_speed": 0.25}, {"name": "+12% силы способностей", "spell_amp": 0.12}],
	[{"name": "+6 брони и +10% защиты от магии", "armor": 6.0, "magic_resist": 0.1}, {"name": "+10 ко всем атрибутам", "all": 10.0}],
	[{"name": "+15% вампиризма", "lifesteal": 0.15}, {"name": "+10% уклонения и +0.8 скорости", "evasion": 0.1, "speed": 0.8}],
]

## Герои и способности — из карты (см. tools/wc3_import/gen_heroes.py → data_heroes.gd)
const HERO_ORDER: Array = HeroData.HERO_ORDER
const HEROES := HeroData.HEROES

## Урон способности = (str·Сила + agi·Ловкость + int·Интеллект) × (1 + 0.1·(уровень−1)).
## Типы: line, leap_strike, slashes, empower, passive, bolt, ice_blocks, blink, transform, time_stop, mugetsu, metamorphosis,
## nova (удар по области вокруг себя), aoe_point (удар по области в точке).
const ABILITIES := HeroData.ABILITIES

## Предметы и лавки — из карты (см. tools/gen_items.py → data_items.gd)
const ITEMS := ItemData.ITEMS
const SHOP_TABS := ItemData.SHOP_TABS

## Цели сборки ботов (по порядку)
const BOT_GOALS := HeroData.BOT_GOALS

const STAT_NAMES := {
	"str": "Сила", "agi": "Ловкость", "int": "Интеллект", "all": "Все атрибуты", "damage": "Урон", "armor": "Броня",
	"hp": "Здоровье", "mp": "Мана", "hp_regen": "Реген. здоровья", "mp_regen": "Реген. маны",
	"attack_speed": "Скорость атаки", "speed": "Скорость бега", "spell_amp": "Урон способностей",
	"crit_chance": "Шанс крита", "crit_mult": "Множитель крита", "evasion": "Уклонение", "lifesteal": "Вампиризм",
	"seven": "Семь чувств (доп. урон атаки)", "stun_chance": "Шанс оглушить", "reflect": "Отражение урона",
	"absorb": "Блок урона за удар", "mana_burn": "Сжигание маны за удар", "magic_resist": "Сопротивление магии",
	"reduction": "Снижение всего урона", "aura_armor": "Аура брони союзникам", "burn": "Аура пламени, урон/с",
	"vision": "Обзор на арене +м, видит невидимых",
}
const PERCENT_STATS := ["attack_speed", "spell_amp", "crit_chance", "evasion", "lifesteal", "seven", "stun_chance",
	"reflect", "magic_resist", "reduction"]
const FLAG_STATS := {"cold": "Удары замедляют врагов", "stealth": "На арене враги замечают вас только вблизи"}


static func _num(v: float) -> String:
	return str(int(v)) if v == floorf(v) else "%.1f" % v


static func active_desc(a: Dictionary) -> String:
	match a.type:
		"heal":
			return "лечение +%d здоровья" % int(a.amount)
		"heal_pct":
			return "полностью восстанавливает здоровье"
		"spell_shield":
			return "антимагия: %d с без урона от способностей" % int(a.dur)
		"freeze_nova":
			return "ледяная нова: %d урона вокруг и заморозка на %s с" % [int(a.dmg), _num(a.freeze)]
		"root":
			return "ловушка: ближайший вражеский герой обездвижен на %s с" % _num(a.dur)
		"invis":
			return "невидимость на %d с, все удары критические" % int(a.dur)
		"snipe":
			return "выстрел: %d урона и оглушение на %d с ближайшему вражескому герою" % [int(a.dmg), int(a.stun)]
		"immortal":
			return "бессмертие на %d с: здоровье не падает ниже 1" % int(a.dur)
		"hex":
			return "проклятие: ближайший вражеский герой бездействует %s с" % _num(a.dur)
		"mirror":
			return "двойники: +%d%% урона на %d с" % [int(a.mult * 100), int(a.dur)]
		"attack_buff":
			return "+%d%% урона на %d с" % [int(a.pct * 100), int(a.dur)]
		"confuse":
			return "облако жажды: враги вокруг замедлены на %d%% на %d с" % [int(a.slow * 100), int(a.dur)]
		"spirit":
			return "дух-защитник: +40%% урона и скорости атаки на %d с" % int(a.dur)
	return ""


static func item_desc(id: String) -> String:
	var d: Dictionary = ITEMS[id]
	var parts: PackedStringArray = []
	for k in STAT_NAMES:
		if not d.has(k):
			continue
		var v: float = d[k]
		if k in PERCENT_STATS:
			parts.append("%s +%d%%" % [STAT_NAMES[k], int(round(v * 100.0))])
		elif k == "crit_mult":
			parts.append("%s ×%s" % [STAT_NAMES[k], _num(v)])
		else:
			parts.append("%s +%s" % [STAT_NAMES[k], _num(v)])
	for k in FLAG_STATS:
		if d.has(k):
			parts.append(FLAG_STATS[k])
	var s := ", ".join(parts)
	if d.get("consumable", false):
		var n := int(d.get("charges", 1))
		var what := ""
		if d.has("heal"):
			what = "Восстанавливает %d здоровья за 3 с" % int(d.heal)
		elif d.has("mana"):
			what = "Восстанавливает %d маны за 3 с" % int(d.mana)
		elif d.has("invuln"):
			what = "Неуязвимость на %d с" % int(d.invuln)
		elif d.has("vamp"):
			what = "%d с: +25%% урона и вампиризм 25%%" % int(d.vamp)
		elif d.has("tp"):
			what = "Переносит в свой лагерь, к фонтанам. Каст %d с: стойте на месте, оглушение сбивает. Перезарядка %d с" % [int(d.tp), int(d.cd)]
		s = what + (" · зарядов: %d" % n if n > 1 else "")
	if d.has("tome"):
		var t: Dictionary = d.tome
		var tp: PackedStringArray = []
		for k in t:
			if k == "xp":
				tp.append("+%d опыта" % int(t[k]))
			else:
				tp.append("%s +%d навсегда" % [STAT_NAMES.get(k, k), int(t[k])])
		s = "Читается сразу при покупке: " + ", ".join(tp)
	if d.has("active"):
		s += (". " if s != "" else "") + "Применение [1–6]: " + active_desc(d.active) + " (перезарядка %d с)" % int(d.active.cd)
	if d.has("note"):
		s += (". " if s != "" else "") + d.note
	return s


static func recipe_total(id: String) -> int:
	var d: Dictionary = ITEMS[id]
	var total: int = d.price
	for c in d.get("recipe", []):
		total += recipe_total(c)
	return total

static func xp_to_next(level: int) -> float:
	return 110.0 + 80.0 * (level - 1)


static func creep_stats(wave: int, boss: bool) -> Dictionary:
	var w := float(wave - 1)
	var hp := 130.0 * pow(1.09, w) + 25.0 * w
	var dmg := 12.0 * pow(1.07, w) + 1.2 * w
	var d := {
		"hp": hp, "damage": dmg, "armor": 1.0 + w * 0.3, "speed": 4.6 + minf(w * 0.04, 1.4),
		"gold": 12.0 + w * 2.2, "xp": 24.0 + w * 8.0, "cd": 1.3, "range": 1.5, "scale": 1.0,
	}
	if boss:
		d.hp *= 8.0
		d.damage *= 2.6
		d.armor += 4.0
		d.speed *= 0.85
		d.gold *= 11.0
		d.xp *= 7.0
		d.cd = 1.8
		d.range = 2.6
	return d


## Нейтральные монстры в лесу у лагеря
static func neutral_stats(level: int, big: bool) -> Dictionary:
	var d := creep_stats(maxi(level, 1), false)
	d.hp *= 1.3
	d.damage *= 1.1
	d.gold *= 1.4
	d.xp *= 1.3
	d.speed = 4.4
	if big:
		d.hp *= 2.2
		d.damage *= 1.5
		d.armor += 2.0
		d.gold *= 2.2
		d.xp *= 2.2
		d.range = 1.9
	return d

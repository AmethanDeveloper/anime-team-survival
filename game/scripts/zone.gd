class_name Zone
extends RefCounted
## Остров одной команды по схеме карты. Локальные координаты: x — поперёк острова, z — от лагеря (внизу) к лесу (вверху).
##
##   ◇ врата монстров             лес (вход только телепортом 2)          врата монстров ◇
##   │ левая тропа                 [2] фонтаны жизни и маны              правая тропа │
##   └──────────────┐                                          ┌──────────────┘
##   [4] плато ════ лестница ═══ центр [1] ═══ лестница ════ плато [3]
##   ┌──────────────┘                                          └──────────────┐
##   │ тропа          ┃ уступ ┃  лагерь: кристалл, лавки, [1][2]  ┃ уступ ┃         тропа │
##   └──────────────────── вход между двумя башнями ─────────────────────────┘
##
## Монстры идут двумя тропами из двух врат, сходятся в центре, огибают лагерь по бокам
## и входят в него снизу, между башнями. Уступы вокруг лагеря непроходимы.

## Острова стоят в ряд, все одинаково: лагерь внизу, лес вверху. Арена — ниже, под островами.
## Масштаб острова: все локальные координаты схемы ниже умножаются на него (2 — остров вдвое больше схемы).
## Здания, деревья и камни-препятствия при этом сохраняют свой размер.
const S := 2.0
const SPACING := 80.0 * S
const ORIGIN_Z := -8.0
const BOUNDS := Rect2(-32.0, -5.0, 64.0, 102.0)

## Проходимые области (без леса)
const WALK := [
	Rect2(-17.5, -4.0, 35.0, 7.5),    # нижний обход лагеря
	Rect2(-17.5, 3.5, 7.5, 25.5),     # левая нижняя тропа
	Rect2(10.0, 3.5, 7.5, 25.5),      # правая нижняя тропа
	Rect2(-10.0, 3.5, 20.0, 25.5),    # лагерь (уступы — препятствия)
	Rect2(-17.5, 29.0, 35.0, 9.0),    # развилка под центром
	Rect2(-5.0, 38.0, 10.0, 17.0),    # центр
	Rect2(-31.0, 43.5, 26.0, 9.0),    # левое плато с лестницей
	Rect2(5.0, 43.5, 26.0, 9.0),      # правое плато с лестницей
	Rect2(-17.5, 55.0, 35.0, 9.0),    # развилка над центром
	Rect2(-17.5, 64.0, 7.0, 32.0),    # левая верхняя тропа
	Rect2(10.5, 64.0, 7.0, 32.0),     # правая верхняя тропа
	Rect2(-1.7, 63.5, 3.4, 3.6),      # лестница из мини-леса вниз, к развилке над центром
]
## Лес: отделён от троп полосой деревьев, попасть можно только телепортом 2
const FOREST := Rect2(-8.5, 66.5, 17.0, 28.5)
## Земля под лесом вместе с полосой деревьев
const FOREST_GROUND := Rect2(-10.5, 64.0, 21.0, 32.0)
const BASE := Rect2(-10.0, 3.5, 20.0, 25.5)
## Плато: высота и где начинается подъём
const PLATEAU_H := 1.4
const RAMP_X0 := 9.0
const RAMP_X1 := 19.0
const PLAT_Z0 := 43.5
const PLAT_Z1 := 52.5
## Радиус срабатывания телепортов
const PAD_R := 1.3

var index := 0
## Мировая точка локального (0, 0): x — смещение острова в ряду
var origin := Vector3.ZERO
var crystal_pos := Vector3.ZERO
var shop_pos := Vector3.ZERO
var hero_spawn := Vector3.ZERO
var fountain_life := Vector3.ZERO
var fountain_mana := Vector3.ZERO
var forest_center := Vector3.ZERO
## Врата монстров (по одним на тропу)
var spawns: Array[Vector3] = []
## Две тропы монстров
var lanes: Array = []  # [Array[Vector3], Array[Vector3]]
## Точки, где стоят защитники троп
var guard_points: Array[Vector3] = []
var towers: Array[Vector3] = []
## Порталов «3» и «4» между островами больше нет: на чужой остров — только через общий лес
var portals: Array = []
## Телепорты: [{id, pos, exit, to_name, cast, area, to_area, own, color}] — «1» лагерь→центр, «2» лагерь→мини-лес,
## «gate» — врата мини-лес→общий лес
var pads: Array = []
var camps: Array[Vector3] = []
## Куда выводит телепорт «1»
var center_mark := Vector3.ZERO
## Препятствия: [{r: Rect2 (локально), kind: String}]
var obstacles: Array = []
## Дополнительные непроходимые места (крупные декорации), в координатах схемы
var extra_obstacles: Array = []
var nav := NavArea.new()


func _init(i: int) -> void:
	index = i
	# в ряду: «4» ведёт к соседу слева, «3» — к соседу справа (0 — в середине, 1 — справа, 2 — слева)
	origin = Vector3([0.0, SPACING, -SPACING][i], 0.0, ORIGIN_Z)
	crystal_pos = to_world(0.0, 19.5)
	shop_pos = to_world(0.0, 17.0)
	hero_spawn = to_world(0.0, 14.0)
	# фонтаны — в верхних углах лагеря: лечат только хозяев, чужих героев рядом бьют
	fountain_life = to_world(-5.9, 24.4)
	fountain_mana = to_world(5.9, 24.4)
	forest_center = to_world(0.0, 80.0)
	spawns = [to_world(-14.0, 92.0), to_world(14.0, 92.0)]
	for side in [-1.0, 1.0]:
		var pts: Array[Vector3] = []
		for p in [[14.0, 90.0], [14.0, 78.0], [14.0, 66.0], [8.0, 59.5], [2.5, 53.0], [2.5, 40.5], [8.0, 34.0],
				[14.0, 27.0], [14.0, 13.0], [13.5, 0.5], [6.0, -0.5], [0.5, 1.0], [0.0, 7.0], [0.0, 13.5]]:
			pts.append(to_world(side * p[0], p[1]))
		lanes.append(pts)
	guard_points = [to_world(-9.5, 33.0), to_world(9.5, 33.0), to_world(0.0, 9.0)]
	towers = [to_world(-4.5, 10.5), to_world(4.5, 10.5)]
	camps = [to_world(-4.5, 88.0), to_world(4.5, 88.0), to_world(-1.5, 79.0)]
	# «1» — из лагеря в центр, сразу; «2» — из лагеря в свой мини-лес, каст 3 с. Оба в одну сторону:
	# назад — пешком по лестнице или свитком телепорта. Врата в глубине мини-леса ведут в общий лес (каст 3 с).
	var gc := Forest2.clearing("gate")
	pads = [
		{"id": "1", "pos": to_world(-6.9, 14.5), "exit": to_world(0.0, 46.0), "to_name": "Центр", "cast": 0.0,
			"area": i, "to_area": i, "own": true, "color": Color(1.0, 0.82, 0.35)},
		{"id": "2", "pos": to_world(-6.9, 6.8), "exit": to_world(0.0, 71.0), "to_name": "Мини-лес", "cast": Wild.CAST,
			"area": i, "to_area": i, "own": true, "color": Color(0.45, 1.0, 0.45)},
		{"id": "gate", "pos": to_world(gc.x, gc.y + 0.6), "exit": Wild.gate_exit(i), "to_name": "Общий лес", "cast": Wild.CAST,
			"area": i, "to_area": Wild.AREA, "own": false, "color": Color(0.75, 0.5, 1.0)},
	]
	center_mark = to_world(0.0, 46.0)
	obstacles = [
		# уступы вокруг лагеря — монстры обходят лагерь и входят снизу, между башнями
		{"r": Rect2(-10.0, 3.5, 1.6, 25.5), "kind": "cliff"},
		{"r": Rect2(8.4, 3.5, 1.6, 25.5), "kind": "cliff"},
		{"r": Rect2(-8.4, 27.4, 16.8, 1.6), "kind": "cliff"},
		{"r": Rect2(-8.4, 3.5, 5.4, 1.6), "kind": "cliff"},
		{"r": Rect2(3.0, 3.5, 5.4, 1.6), "kind": "cliff"},
		# лагерь
		{"r": Rect2(-5.3, 9.7, 1.6, 1.6), "kind": "tower"},
		{"r": Rect2(3.7, 9.7, 1.6, 1.6), "kind": "tower"},
		# лес
		{"r": Rect2(-7.3, 23.0, 2.8, 2.8), "kind": "fountain_life"},
		{"r": Rect2(4.5, 23.0, 2.8, 2.8), "kind": "fountain_mana"},
		# камни на тропах
		{"r": Rect2(-17.4, 71.0, 2.0, 2.4), "kind": "rocks"},
		{"r": Rect2(15.4, 82.0, 2.0, 2.4), "kind": "rocks"},
		{"r": Rect2(-17.4, 15.0, 2.0, 2.4), "kind": "rocks"},
		{"r": Rect2(15.4, 20.0, 2.0, 2.4), "kind": "rocks"},
	]
	# мини-лес: поляны с лагерями, тропы, сплошная чаща вокруг — она непроходима
	camps = []
	for kind in Forest2.CAMPS:
		camps.append(to_world(Forest2.clearing(kind).x, Forest2.clearing(kind).y))
	extra_obstacles.append_array(Forest2.blocked_rects())
	# постройки и деревья сохраняют размер: их прямоугольник сжимается к центру обратно масштабу острова
	for o in obstacles:
		if o.kind != "cliff":
			var r0: Rect2 = o.r
			var sz := r0.size / S
			o.r = Rect2(r0.get_center() - sz / 2.0, sz)
	# телега и ящики в лагере (декорации) — их размер задан сразу в схеме
	for r in Decor.island_blockers():
		obstacles.append({"r": r, "kind": "decor"})
	# сетка проходимости — в метрах (1 клетка = 1 м), поэтому схему переводим в метры
	var rects: Array = []
	for o in obstacles:
		rects.append(_m(o.r))
	for r in extra_obstacles:
		rects.append(_m(r))
	var walk: Array = []
	for r: Rect2 in WALK:
		walk.append(_m(r))
	walk.append(_m(FOREST))
	nav.setup(_m(BOUNDS), walk, rects, func(v: Vector2) -> Vector3: return to_world(v.x / S, v.y / S),
		func(p: Vector3) -> Vector2: return to_local(p) * S)
	nav.height_fn = func(p: Vector3) -> float: return height_local(to_local(p))
	crystal_pos = ground(crystal_pos)


## Прямоугольник схемы → метры от начала острова (для сетки проходимости).
static func _m(r: Rect2) -> Rect2:
	return Rect2(r.position * S, r.size * S)


func to_world(lx: float, lz: float) -> Vector3:
	return Vector3(origin.x + lx * S, 0.0, origin.z - lz * S)


## Точка с высотой земли (для плато).
func to_world_h(lx: float, lz: float) -> Vector3:
	var p := to_world(lx, lz)
	p.y = height_local(Vector2(lx, lz))
	return p


func ground(p: Vector3) -> Vector3:
	return Vector3(p.x, height_local(to_local(p)), p.z)


func to_local(p: Vector3) -> Vector2:
	return Vector2((p.x - origin.x) / S, (origin.z - p.z) / S)


## Высота земли: плато с телепортами 3 и 4 и лестницы к ним.
static func height_local(l: Vector2) -> float:
	if l.y < PLAT_Z0 or l.y > PLAT_Z1:
		return 0.0
	var ax := absf(l.x)
	if ax <= RAMP_X0:
		return 0.0
	if ax >= RAMP_X1:
		return PLATEAU_H
	return PLATEAU_H * (ax - RAMP_X0) / (RAMP_X1 - RAMP_X0)


func contains(p: Vector3, margin := 0.0) -> bool:
	var l := to_local(p)
	for r: Rect2 in WALK:
		if r.grow(margin).has_point(l):
			return true
	return FOREST_GROUND.grow(margin).has_point(l)


func in_forest(p: Vector3) -> bool:
	return FOREST.grow(0.5).has_point(to_local(p))


func in_base(p: Vector3) -> bool:
	return BASE.has_point(to_local(p))


## На какой части острова точка: «forest», «base», «center» (центр и плато) или «lane».
func region(p: Vector3) -> String:
	var l := to_local(p)
	if FOREST.grow(0.5).has_point(l):
		return "forest"
	if BASE.has_point(l):
		return "base"
	if l.y >= 38.0 and l.y <= 55.0:
		return "center"
	return "lane"


func clamp_pos(p: Vector3) -> Vector3:
	return nav.clamp(p)


## Угол поворота модели (вокруг Y), чтобы она смотрела к центру карты.
func facing_inward() -> float:
	return 0.0


## Угол, под которым модель смотрит вдоль локальной оси +x (поперёк линии).
func facing_side() -> float:
	return PI * 0.5

class_name Decor
extends RefCounted
## Декорации из наборов Quaternius (CC0, assets/quaternius): деревья, кусты, трава, камни, дома деревни.
## Модели собраны заранее (tools/build_decor.gd); здесь — расстановка. Одинаковые модели рисуются одним
## MultiMesh на кусок карты, поэтому сотни деревьев почти ничего не стоят.
## Данные экземпляра (шейдер decor_*.gdshader): r — снег сверху, g — разброс яркости, b — фаза ветра, a — иней.

const DIR := "res://assets/quaternius/mesh/"
## Мелочь без теней, которую не рисуем издалека
const SMALL := ["Grass", "Flower", "Clover", "Plant_", "Pebble", "Mushroom", "Fern", "RockPath", "Prop_Brick", "Bush"]
const CHUNK := 56.0
## Вся земля острова (схема): за пределами троп — лес, скалы и дома
const LAND := Rect2(-27.0, -9.0, 54.0, 108.0)

const PINES := ["Pine_1", "Pine_2", "Pine_3", "Pine_4", "Pine_5"]
const COMMON := ["CommonTree_1", "CommonTree_2", "CommonTree_3", "CommonTree_4", "CommonTree_5"]
const DEAD := ["DeadTree_1", "DeadTree_2", "DeadTree_3", "DeadTree_4", "DeadTree_5"]
const TWISTED := ["TwistedTree_1", "TwistedTree_2", "TwistedTree_3", "TwistedTree_4", "TwistedTree_5"]
const ROCKS := ["Rock_Medium_1", "Rock_Medium_2", "Rock_Medium_3"]
const GRASS := ["Grass_Common_Short", "Grass_Common_Tall", "Grass_Wispy_Short", "Grass_Wispy_Tall"]
const FLOWERS := ["Flower_3_Group", "Flower_4_Group", "Flower_3_Single", "Flower_4_Single"]

## Дома вдоль троп (схема острова): [модель, x, z, куда смотрит дверь: «x+», «x-», «z+»]
const HOUSES := [
	["House_A", -21.6, 7.0, "x+"], ["House_B", -21.0, 16.5, "x+"], ["House_C", -21.6, 27.0, "x+"],
	["Watchtower", -22.5, 39.0, "x+"],
	["House_C", -21.6, 61.0, "x+"], ["House_A", -21.6, 72.0, "x+"], ["House_B", -21.0, 83.0, "x+"],
	["House_B", 21.0, 6.5, "x-"], ["House_A", 21.6, 17.0, "x-"], ["House_B", 21.0, 27.5, "x-"],
	["Watchtower", 22.5, 39.0, "x-"],
	["House_A", 21.6, 62.0, "x-"], ["House_C", 21.6, 73.0, "x-"], ["House_B", 21.0, 84.0, "x-"],
	["House_C", -9.0, -6.6, "z+"], ["House_B", 9.0, -6.7, "z+"],
]
## Радиус занятого места (м) у крупных моделей
const RADIUS := {"House_A": 5.2, "House_B": 4.0, "House_C": 4.8, "Watchtower": 3.3, "Prop_Wagon": 2.2}

static var _meshes := {}

var items := {}
var rng := RandomNumberGenerator.new()
## Занятые круги: Vector3(x, z, r) в мире
var used: Array[Vector3] = []


static func mesh(n: String) -> Mesh:
	if not _meshes.has(n):
		var path := DIR + n + ".res"
		_meshes[n] = load(path) if ResourceLoader.exists(path) else null
		if _meshes[n] == null:
			push_warning("Нет декорации " + n)
	return _meshes[n]


func pick(list: Array) -> String:
	return list[rng.randi() % list.size()]


func add(n: String, pos: Vector3, yaw := INF, s := 1.0, snow := 0.0, frost := 0.0) -> void:
	if yaw == INF:
		yaw = rng.randf() * TAU
	var b := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s)
	if not items.has(n):
		items[n] = []
	items[n].append([Transform3D(b, pos), Color(snow * 0.06, rng.randf_range(-0.1, 0.1), rng.randf(), frost * 0.08)])


func free_at(p: Vector3, r: float) -> bool:
	for u in used:
		if Vector2(p.x - u.x, p.z - u.y).length() < r + u.z:
			return false
	return true


func occupy(p: Vector3, r: float) -> void:
	used.append(Vector3(p.x, p.z, r))


func build(parent: Node3D) -> void:
	if OS.get_environment("ATS_DECOR_STATS") != "":
		var tot := 0
		var tris := 0
		var nodes := 0
		for n: String in items:
			var m := mesh(n)
			var t := 0
			if m:
				for s in m.get_surface_count():
					t += (m as ArrayMesh).surface_get_array_index_len(s) / 3
			tot += items[n].size()
			tris += t * items[n].size()
			print("DECOR %-28s x%4d  %6d tris" % [n, items[n].size(), t])
		print("DECOR total instances=%d tris(LOD0)=%d" % [tot, tris])
	for n: String in items:
		var m := mesh(n)
		if m == null:
			continue
		var small := false
		for s: String in SMALL:
			if n.begins_with(s):
				small = true
		var cells := {}
		for it in items[n]:
			var t: Transform3D = it[0]
			var key := Vector2i(int(floorf(t.origin.x / CHUNK)), int(floorf(t.origin.z / CHUNK)))
			if not cells.has(key):
				cells[key] = []
			cells[key].append(it)
		for key in cells:
			var arr: Array = cells[key]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = m
			mm.instance_count = arr.size()
			for i in arr.size():
				mm.set_instance_transform(i, arr[i][0])
				mm.set_instance_custom_data(i, arr[i][1])
			var mi := MultiMeshInstance3D.new()
			mi.name = "%s_%d_%d" % [n, key.x, key.y]
			mi.multimesh = mm
			mi.set_meta("decor_small" if small else "decor", true)
			if small:
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mi.visibility_range_end = 140.0
				mi.visibility_range_end_margin = 12.0
				mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			parent.add_child(mi)


# ----------------------------------------------------------------- остров команды
## Расстояние (в единицах схемы) от точки до ближайшего прямоугольника.
static func dist_rects(p: Vector2, rects: Array) -> float:
	var best := 1e9
	for r: Rect2 in rects:
		var dx := maxf(maxf(r.position.x - p.x, 0.0), p.x - r.end.x)
		var dz := maxf(maxf(r.position.y - p.y, 0.0), p.y - r.end.y)
		best = minf(best, sqrt(dx * dx + dz * dz))
	return best


static func in_rects(p: Vector2, rects: Array) -> bool:
	for r: Rect2 in rects:
		if r.has_point(p):
			return true
	return false


## Расстояние от точки до ломаной (мир, по горизонтали).
static func dist_poly(p: Vector3, pts: Array) -> float:
	var best := 1e9
	var q := Vector2(p.x, p.z)
	for i in pts.size() - 1:
		var a := Vector2(pts[i].x, pts[i].z)
		var b := Vector2(pts[i + 1].x, pts[i + 1].z)
		best = minf(best, q.distance_to(Geometry2D.get_closest_point_to_segment(q, a, b)))
	return best


static func _yaw(face: String) -> float:
	match face:
		"x+":
			return PI * 0.5
		"x-":
			return -PI * 0.5
		"z+":
			return PI
	return 0.0


## Места, занятые крупными декорациями внутри проходимых областей (схема) — они становятся препятствиями.
static func island_blockers() -> Array:
	return [
		Rect2(6.8, 11.0, 1.1, 2.1),    # телега у лавки
		Rect2(6.6, 8.6, 1.3, 1.2),     # ящики
	]


func island(z: Zone) -> void:
	var S := Zone.S
	var busy: Array = Zone.WALK.duplicate()
	busy.append(Zone.FOREST_GROUND)
	# дома вдоль троп, со снегом на крышах
	for hv in HOUSES:
		var p := z.to_world(hv[1], hv[2])
		p.y = -0.02
		add(hv[0], p, _yaw(hv[3]) + rng.randf_range(-0.04, 0.04), 1.0, 0.8)
		occupy(p, RADIUS[hv[0]])
		# у дома — ящики, забор, кусты
		var side := 1.0 if hv[3] == "x+" else (-1.0 if hv[3] == "x-" else 0.0)
		if side != 0.0 and hv[0] != "Watchtower":
			var c := p + Vector3(side * 4.2, 0, rng.randf_range(-3.0, 3.0))
			add("Prop_Crate", c, rng.randf() * TAU, rng.randf_range(0.8, 1.0), 0.7)
			if rng.randf() < 0.6:
				add("Prop_Crate", c + Vector3(0, 0, 1.2), rng.randf() * TAU, 0.8, 0.7)
			for k in 2:
				add("Prop_WoodenFence_Single", p + Vector3(side * 5.0, 0, -4.0 + k * 8.0), PI * 0.5, 1.0, 0.6)
	# телега и ящики в лагере у лавки
	add("Prop_Wagon", z.to_world(7.35, 11.5), 0.0, 1.0, 0.5)
	add("Prop_Crate", z.to_world(7.5, 9.0), 0.3, 1.0, 0.6)
	add("Prop_Crate", z.to_world(6.95, 9.3), 1.1, 0.9, 0.6)
	add("Prop_Crate", z.to_world(7.25, 9.15) + Vector3(0, 1.0, 0), 0.6, 0.8, 0.7)
	_camp(z)
	# центр: два кольца каменных плит вокруг знака телепорта «1»
	var cm := z.to_local(z.center_mark)
	for ring in [[1.75, 7], [3.25, 13]]:
		var a0 := rng.randf() * TAU
		for k in int(ring[1]):
			var a: float = a0 + TAU * k / float(ring[1])
			var lp: Vector2 = cm + Vector2(cos(a), sin(a)) * float(ring[0])
			add("RockPath_Round_Wide", z.to_world(lp.x, lp.y) + Vector3(0, 0.012, 0), INF, rng.randf_range(1.45, 1.6), 0.2)

	# лес и скалы на всей земле вне троп: чем дальше от тропы, тем крупнее
	var step := 2.6
	var gx := LAND.position.x
	while gx < LAND.end.x:
		var gz := LAND.position.y
		while gz < LAND.end.y:
			var lp := Vector2(gx + rng.randf() * step, gz + rng.randf() * step)
			gz += step
			if not LAND.has_point(lp):
				continue
			var dm := dist_rects(lp, busy) * S
			if dm < 1.2:
				continue
			var p := z.to_world(lp.x, lp.y)
			p.y = -0.02
			if dm < 3.6:
				# край тропы: кусты, трава, небольшие камни под инеем
				var r := rng.randf()
				if r < 0.3:
					add(pick(GRASS), p, INF, rng.randf_range(1.0, 1.6), 0.0, 0.55)
				elif r < 0.45:
					add("Bush_Common_Flowers" if rng.randf() < 0.3 else "Bush_Common", p, INF, rng.randf_range(0.9, 1.3), 0.6, 0.35)
				elif r < 0.6 and free_at(p, 1.2):
					add(pick(ROCKS), p + Vector3(0, -0.3, 0), INF, rng.randf_range(0.45, 0.8), 0.75)
					occupy(p, 1.2)
				continue
			if not free_at(p, 2.0):
				continue
			var r2 := rng.randf()
			if r2 < 0.72:
				add(pick(PINES), p, INF, rng.randf_range(0.85, 1.35), rng.randf_range(0.55, 0.85))
				occupy(p, 2.2)
			elif r2 < 0.82:
				add(pick(DEAD), p, INF, rng.randf_range(0.55, 0.8), 0.5)
				occupy(p, 2.0)
			elif r2 < 0.95:
				add(pick(ROCKS), p + Vector3(0, -0.4, 0), INF, rng.randf_range(0.9, 1.6), 0.8)
				occupy(p, 2.2)
			else:
				add(pick(GRASS), p, INF, 1.4, 0.0, 0.55)
		gx += step

	# камни у берега
	var per: Array = [[Vector2(LAND.position.x, LAND.position.y), Vector2(LAND.end.x, LAND.position.y)],
		[Vector2(LAND.end.x, LAND.position.y), Vector2(LAND.end.x, LAND.end.y)],
		[Vector2(LAND.end.x, LAND.end.y), Vector2(LAND.position.x, LAND.end.y)],
		[Vector2(LAND.position.x, LAND.end.y), Vector2(LAND.position.x, LAND.position.y)]]
	for seg in per:
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		var n := int(a.distance_to(b) / 3.2)
		for k in n:
			var lp: Vector2 = a.lerp(b, (k + rng.randf()) / n)
			if absf(lp.x) > 20.0 and lp.y > Zone.PLAT_Z0 - 1.5 and lp.y < Zone.PLAT_Z1 + 1.5:
				continue   # тут к краю выходит плато с порталом
			var p := z.to_world(lp.x, lp.y) + Vector3(rng.randf_range(-1.0, 1.0), -0.9, rng.randf_range(-1.0, 1.0))
			add(pick(ROCKS), p, INF, rng.randf_range(1.3, 2.4), 0.7)

	# у троп внутри острова: иней на траве у краёв, мелкие камни; сами тропы монстров чистые
	var gx2 := -31.0
	while gx2 < 31.0:
		var gz2 := -4.0
		while gz2 < 96.0:
			var lp := Vector2(gx2 + rng.randf() * 2.0, gz2 + rng.randf() * 2.0)
			gz2 += 2.0
			if not in_rects(lp, Zone.WALK) or Zone.BASE.grow(-1.0).has_point(lp) or rng.randf() < 0.45:
				continue
			var edge := false
			for dv in [Vector2(1.3, 0), Vector2(-1.3, 0), Vector2(0, 1.3), Vector2(0, -1.3)]:
				if not in_rects(lp + dv, Zone.WALK):
					edge = true
			if not edge:
				continue
			var p := z.to_world_h(lp.x, lp.y)
			if dist_poly(p, z.lanes[0]) < 5.5 or dist_poly(p, z.lanes[1]) < 5.5:
				continue
			if rng.randf() < 0.75:
				add(pick(GRASS), p, INF, rng.randf_range(0.9, 1.4), 0.0, 0.55)
			else:
				add("Pebble_Round_%d" % (1 + rng.randi() % 3), p, INF, rng.randf_range(1.5, 2.5), 0.6)
		gx2 += 2.0

	if Forest2.enabled:
		Forest2.decorate(self, z)
	else:
		_forest(z)


## Лагерь: площадь из камня вокруг кристалла и лавки, трава и кусты вдоль уступов.
func _camp(z: Zone) -> void:
	var gx := -3.75
	while gx <= 3.8:
		var gz := 12.75
		while gz <= 21.3:
			var edge := absf(gx) > 3.0 or gz < 13.0 or gz > 21.0
			if not (edge and rng.randf() < 0.35) and (gz > 18.0 or absf(gx) < 1.0):
				add("RockPath_Round_Wide", z.to_world(gx, gz) + Vector3(0, 0.015, 0), (rng.randi() % 4) * PI * 0.5 +
					rng.randf_range(-0.1, 0.1), rng.randf_range(1.5, 1.6), 0.2)
			gz += 1.5
		gx += 1.5
	var avoid: Array = [Vector2(-6.9, 14.5), Vector2(-6.9, 6.8), Vector2(-7.2, 20.0), Vector2(7.2, 20.0),
		Vector2(6.8, 17.0), Vector2(6.5, 15.0), Vector2(7.0, 6.5), Vector2(-6.4, 23.8), Vector2(6.4, 23.8),
		Vector2(-2.6, 5.8), Vector2(2.6, 5.8)]
	for k in 70:
		var side := rng.randi() % 3
		var lp: Vector2
		if side == 0:
			lp = Vector2(-7.9 + rng.randf() * 0.7, rng.randf_range(5.6, 26.4))
		elif side == 1:
			lp = Vector2(7.9 - rng.randf() * 0.7, rng.randf_range(5.6, 26.4))
		else:
			lp = Vector2(rng.randf_range(-7.8, 7.8), 26.8 - rng.randf() * 0.6)
		var bad := false
		for a: Vector2 in avoid:
			if lp.distance_to(a) < 1.7:
				bad = true
		for r: Rect2 in island_blockers():
			if r.grow(0.5).has_point(lp):
				bad = true
		if bad:
			continue
		var p := z.to_world(lp.x, lp.y)
		var r2 := rng.randf()
		if r2 < 0.6:
			add(pick(GRASS), p, INF, rng.randf_range(0.9, 1.4), 0.0, 0.55)
		elif r2 < 0.8:
			add("Bush_Common_Flowers", p, INF, rng.randf_range(0.8, 1.1), 0.5, 0.3)
		else:
			add("Pebble_Round_%d" % (1 + rng.randi() % 3), p, INF, rng.randf_range(1.5, 2.5), 0.5)


## Лес: зелёный оазис — стена деревьев по краю, клён-момидзи, трава, цветы, грибы.
func _forest(z: Zone) -> void:
	var f := Zone.FOREST_GROUND
	var fo := Zone.FOREST
	var keep: Array = []   # [центр, радиус (схема)]
	for cp in z.camps:
		keep.append([z.to_local(cp), 4.2])
	keep.append([z.to_local(z.fountain_life), 2.6])
	keep.append([z.to_local(z.fountain_mana), 2.6])
	for pd in z.pads:
		keep.append([z.to_local(pd.pos), 2.0])
		if pd.to_name == "Лес":
			keep.append([z.to_local(pd.exit), 2.2])
	for o in z.obstacles:
		if o.kind == "trees":
			keep.append([(o.r as Rect2).get_center(), 1.4])
	# стена деревьев: по середине полосы между лесом и тропами
	var rows: Array = [
		[Vector2(f.position.x + 1.0, f.position.y + 1.2), Vector2(f.position.x + 1.0, f.end.y - 0.5)],
		[Vector2(f.end.x - 1.0, f.position.y + 1.2), Vector2(f.end.x - 1.0, f.end.y - 0.5)],
		[Vector2(f.position.x + 2.0, f.position.y + 1.2), Vector2(f.end.x - 2.0, f.position.y + 1.2)],
		[Vector2(f.position.x + 2.0, f.end.y - 0.5), Vector2(f.end.x - 2.0, f.end.y - 0.5)],
	]
	for row in rows:
		var a: Vector2 = row[0]
		var b: Vector2 = row[1]
		var n := int(a.distance_to(b) / 1.75)
		for k in n + 1:
			var lp: Vector2 = a.lerp(b, float(k) / n) + Vector2(rng.randf_range(-0.25, 0.25), rng.randf_range(-0.25, 0.25))
			var p := z.to_world(lp.x, lp.y)
			p.y = 0.0
			if rng.randf() < 0.82:
				add(pick(COMMON), p, INF, rng.randf_range(0.95, 1.25))
			else:
				add(pick(PINES), p, INF, rng.randf_range(0.9, 1.15))
			if rng.randf() < 0.5:
				add("Bush_Common_Flowers", p + Vector3(rng.randf_range(-1.5, 1.5), 0, rng.randf_range(-1.5, 1.5)), INF,
					rng.randf_range(0.9, 1.3))
	# деревья-препятствия внутри леса: два больших клёна и рощица
	var tw := 0
	for o in z.obstacles:
		if o.kind != "trees":
			continue
		var c: Vector2 = (o.r as Rect2).get_center()
		var p := z.to_world(c.x, c.y)
		if tw < 2:
			add(TWISTED[(z.index + tw) % TWISTED.size()], p, INF, rng.randf_range(0.75, 0.85))
		else:
			add(pick(COMMON), p, INF, 1.15)
			add("Bush_Common", p + Vector3(1.4, 0, 0.8), INF, 1.0)
		tw += 1
	# поляна: трава, цветы, клевер, папоротник, грибы
	var gx := fo.position.x + 0.3
	while gx < fo.end.x - 0.3:
		var gz := fo.position.y + 0.3
		while gz < fo.end.y - 0.3:
			var lp := Vector2(gx + rng.randf() * 1.3, gz + rng.randf() * 1.3)
			gz += 1.3
			var blocked := false
			for kp in keep:
				if lp.distance_to(kp[0]) < kp[1]:
					blocked = true
					break
			if blocked or rng.randf() < 0.25:
				continue
			var p := z.to_world(lp.x, lp.y)
			p.y = 0.02
			var r := rng.randf()
			if r < 0.5:
				add(pick(GRASS), p, INF, rng.randf_range(0.9, 1.5))
			elif r < 0.66:
				add(pick(FLOWERS), p, INF, rng.randf_range(0.7, 1.0))
			elif r < 0.76:
				add("Clover_%d" % (1 + rng.randi() % 2), p, INF, rng.randf_range(0.8, 1.2))
			elif r < 0.83:
				add("Fern_1", p, INF, rng.randf_range(0.6, 0.9))
			elif r < 0.89:
				add("Plant_1" if rng.randf() < 0.5 else "Plant_7_Big", p, INF, rng.randf_range(0.8, 1.2))
			elif r < 0.95:
				add("Mushroom_Common" if rng.randf() < 0.6 else "Mushroom_Laetiporus", p, INF, rng.randf_range(0.8, 1.3))
			else:
				var edge := lp.x < fo.position.x + 1.5 or lp.x > fo.end.x - 1.5
				add("Bush_Common_Flowers" if edge else pick(GRASS), p, INF, rng.randf_range(0.8, 1.1))
		gx += 1.3
	# дорожка из камней от телепорта к фонтанам
	var a2 := z.to_local(z.pads[2].pos)
	var b2 := (z.to_local(z.fountain_life) + z.to_local(z.fountain_mana)) * 0.5 + Vector2(0, -1.8)
	var n2 := int(a2.distance_to(b2) / 0.75)
	for k in n2 + 1:
		var lp: Vector2 = a2.lerp(b2, float(k) / n2) + Vector2(rng.randf_range(-0.2, 0.2), rng.randf_range(-0.2, 0.2))
		add("RockPath_Round_Small_%d" % (1 + rng.randi() % 3), z.to_world(lp.x, lp.y) + Vector3(0, 0.03, 0), INF,
			rng.randf_range(1.0, 1.3))

class_name NavArea
extends RefCounted
## Сетка проходимости 1×1 м для одной области (остров команды или арена).
## Работает в локальных координатах области: Vector2(x, z). Пути — через AStarGrid2D.

var x0 := 0.0
var z0 := 0.0
var w := 0
var h := 0
var solid := PackedByteArray()
var astar := AStarGrid2D.new()
var has_obstacles := false
var to_world_fn: Callable
var to_local_fn: Callable
## Высота земли в мировой точке (для плато); если не задана — 0
var height_fn: Callable


func _y(x: float, z: float) -> float:
	if height_fn.is_valid():
		return height_fn.call(Vector3(x, 0.0, z))
	return 0.0


## bounds — общий прямоугольник; walk — проходимые прямоугольники; obstacles — препятствия (всё в локальных координатах).
func _grid(bounds: Rect2, tw: Callable, tl: Callable) -> void:
	to_world_fn = tw
	to_local_fn = tl
	x0 = floorf(bounds.position.x)
	z0 = floorf(bounds.position.y)
	w = int(ceilf(bounds.end.x - x0))
	h = int(ceilf(bounds.end.y - z0))
	solid.resize(w * h)
	astar.region = Rect2i(0, 0, w, h)
	astar.cell_size = Vector2.ONE
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()


## Как setup, но проходимая область и препятствия — многоугольники (шестиугольная арена, повёрнутые стены).
func setup_poly(bounds: Rect2, walk_poly: PackedVector2Array, obstacle_polys: Array, tw: Callable, tl: Callable,
		pad := 0.6) -> void:
	_grid(bounds, tw, tl)
	var walk_in: Array = Geometry2D.offset_polygon(walk_poly, -pad)
	var obs: Array = []
	for poly: PackedVector2Array in obstacle_polys:
		obs.append_array(Geometry2D.offset_polygon(poly, pad, Geometry2D.JOIN_MITER))
	for j in h:
		for i in w:
			var c := Vector2(x0 + i + 0.5, z0 + j + 0.5)
			var ok := false
			for wp: PackedVector2Array in walk_in:
				if Geometry2D.is_point_in_polygon(c, wp):
					ok = true
					break
			if ok:
				for op: PackedVector2Array in obs:
					if Geometry2D.is_point_in_polygon(c, op):
						ok = false
						break
			solid[j * w + i] = 0 if ok else 1
			if not ok:
				astar.set_point_solid(Vector2i(i, j), true)
	has_obstacles = obstacle_polys.size() > 0


## Проходимость задаётся функцией от центра клетки (общий лес: поляны и тропы среди чащи).
func setup_fn(bounds: Rect2, ok_fn: Callable, tw: Callable, tl: Callable) -> void:
	_grid(bounds, tw, tl)
	for j in h:
		for i in w:
			var ok: bool = ok_fn.call(Vector2(x0 + i + 0.5, z0 + j + 0.5))
			solid[j * w + i] = 0 if ok else 1
			if not ok:
				astar.set_point_solid(Vector2i(i, j), true)
	has_obstacles = true


func setup(bounds: Rect2, walk: Array, obstacles: Array, tw: Callable, tl: Callable, pad := 0.6) -> void:
	_grid(bounds, tw, tl)
	var obs_out: Array[Rect2] = []
	for r: Rect2 in obstacles:
		obs_out.append(r.grow(pad))
	# отступ от края считаем по объединению прямоугольников, чтобы на стыках не было щелей
	var probes: Array[Vector2] = [Vector2.ZERO, Vector2(pad, 0), Vector2(-pad, 0), Vector2(0, pad), Vector2(0, -pad),
		Vector2(pad, pad) * 0.7, Vector2(-pad, pad) * 0.7, Vector2(pad, -pad) * 0.7, Vector2(-pad, -pad) * 0.7]
	# быстрые проверки: глубоко внутри одного прямоугольника — точно можно; далеко от всех — точно нельзя
	var inner: Array[Rect2] = []
	var outer: Array[Rect2] = []
	for r: Rect2 in walk:
		if r.size.x > pad * 2.0 and r.size.y > pad * 2.0:
			inner.append(r.grow(-pad))
		outer.append(r.grow(pad))
	for j in h:
		for i in w:
			var c := Vector2(x0 + i + 0.5, z0 + j + 0.5)
			var ok := false
			var known := false
			for r in inner:
				if r.has_point(c):
					ok = true
					known = true
					break
			if not known:
				known = true
				for r in outer:
					if r.has_point(c):
						known = false
						break
			if not known:
				ok = true
				for pr in probes:
					var q := c + pr
					var inside := false
					for r: Rect2 in walk:
						if r.has_point(q):
							inside = true
							break
					if not inside:
						ok = false
						break
			if ok:
				for o in obs_out:
					if o.has_point(c):
						ok = false
						break
			solid[j * w + i] = 0 if ok else 1
			if not ok:
				astar.set_point_solid(Vector2i(i, j), true)
	has_obstacles = obstacles.size() > 0


func _cell(lp: Vector2) -> Vector2i:
	return Vector2i(int(floorf(lp.x - x0)), int(floorf(lp.y - z0)))


func _cell_ok(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < w and c.y < h and solid[c.y * w + c.x] == 0


func _center(c: Vector2i) -> Vector2:
	return Vector2(x0 + c.x + 0.5, z0 + c.y + 0.5)


func walkable_local(lp: Vector2) -> bool:
	return _cell_ok(_cell(lp))


func walkable(p: Vector3) -> bool:
	return walkable_local(to_local_fn.call(p))


func _nearest_cell(c: Vector2i, max_r := 40) -> Vector2i:
	if _cell_ok(c):
		return c
	for r in range(1, max_r):
		var best := Vector2i(-1, -1)
		var bd := 1e9
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var q := c + Vector2i(dx, dy)
				if _cell_ok(q):
					var d := float(dx * dx + dy * dy)
					if d < bd:
						bd = d
						best = q
		if best.x >= 0:
			return best
	return c


## Ближайшая проходимая точка.
func clamp(p: Vector3) -> Vector3:
	var lp: Vector2 = to_local_fn.call(p)
	if walkable_local(lp):
		return Vector3(p.x, _y(p.x, p.z), p.z)
	var c := _nearest_cell(_cell(lp))
	var cp := _center(c)
	# прижимаемся к краю клетки со стороны исходной точки
	cp.x = clampf(lp.x, cp.x - 0.49, cp.x + 0.49)
	cp.y = clampf(lp.y, cp.y - 0.49, cp.y + 0.49)
	var r: Vector3 = to_world_fn.call(cp)
	r.y = _y(r.x, r.z)
	return r


## Шаг из from в to с обходом стены вдоль осей.
func slide(from: Vector3, to: Vector3) -> Vector3:
	if walkable(to):
		return Vector3(to.x, _y(to.x, to.z), to.z)
	var a := Vector3(to.x, 0.0, from.z)
	if walkable(a):
		a.y = _y(a.x, a.z)
		return a
	var b := Vector3(from.x, 0.0, to.z)
	if walkable(b):
		b.y = _y(b.x, b.z)
		return b
	return Vector3(from.x, _y(from.x, from.z), from.z)


## Прямая видимость/проходимость между двумя точками.
func los(a: Vector3, b: Vector3) -> bool:
	var la: Vector2 = to_local_fn.call(a)
	var lb: Vector2 = to_local_fn.call(b)
	var d := la.distance_to(lb)
	var n := int(d / 0.4) + 1
	for k in range(1, n + 1):
		if not walkable_local(la.lerp(lb, float(k) / n)):
			return false
	return true


## Путь из a в b: массив мировых точек (последняя — сама цель или ближайшая к ней доступная).
func find_path(a: Vector3, b: Vector3) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var la: Vector2 = to_local_fn.call(a)
	var lb: Vector2 = to_local_fn.call(b)
	var ca := _nearest_cell(_cell(la), 6)
	var cb := _nearest_cell(_cell(lb), 12)
	if not _cell_ok(ca) or not _cell_ok(cb):
		return out
	var ids := astar.get_id_path(ca, cb, true)
	if ids.is_empty():
		return out
	var pts: Array[Vector2] = []
	for id in ids:
		pts.append(_center(id))
	var goal := lb if walkable_local(lb) else _center(cb)
	pts[pts.size() - 1] = goal
	# сглаживание: пропускаем точки, до которых видно напрямую
	var smooth: Array[Vector2] = []
	var cur := la
	var i := 0
	while i < pts.size():
		var far := i
		var k := mini(pts.size() - 1, i + 24)
		while k > i:
			if _los_local(cur, pts[k]):
				far = k
				break
			k -= 1
		smooth.append(pts[far])
		cur = pts[far]
		i = far + 1
	for p in smooth:
		var wp: Vector3 = to_world_fn.call(p)
		wp.y = _y(wp.x, wp.z)
		out.append(wp)
	return out


func _los_local(la: Vector2, lb: Vector2) -> bool:
	var d := la.distance_to(lb)
	var n := int(d / 0.4) + 1
	for k in range(1, n + 1):
		if not walkable_local(la.lerp(lb, float(k) / n)):
			return false
	return true


## Случайная проходимая точка в прямоугольнике (локальные координаты).
func random_point(rng: RandomNumberGenerator, area: Rect2) -> Vector3:
	for t in 60:
		var lp := Vector2(rng.randf_range(area.position.x, area.end.x), rng.randf_range(area.position.y, area.end.y))
		if walkable_local(lp):
			var wp: Vector3 = to_world_fn.call(lp)
			wp.y = _y(wp.x, wp.z)
			return wp
	var c := _nearest_cell(_cell(area.get_center()))
	var r: Vector3 = to_world_fn.call(_center(c))
	r.y = _y(r.x, r.z)
	return r

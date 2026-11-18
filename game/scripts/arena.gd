class_name Arena
extends RefCounted
## Арена битвы команд: шестиугольник на троих. Каждая команда появляется в своём углу (через угол),
## и все три ищут друг друга в тумане войны. Раскладка повторяется через каждые 120°, так что у всех
## одинаковые условия: заслон перед углом появления, коридоры с перегородками, руины между командами
## и площадь с колоннами в центре.

## Радиус шестиугольника (до угла)
const R := 46.0
## Центр арены в мире: под рядом островов
const CENTER := Vector3(0.0, 0.0, 74.0)
const VISION := 12.0
const STEALTH_VISION := 6.5
## Направления углов появления команд 0, 1, 2 (в плоскости xz, градусы)
const TEAM_ANGLES := [-90.0, 30.0, 150.0]
const SPAWN_DIST := 37.0

## Стены одного сектора в координатах (a — к углу команды, b — поперёк):
## [центр a, центр b, длина, толщина, угол стены к оси (градусы), высота]; b ≠ 0 — зеркалятся.
const SECTOR := [
	[27.3, 4.0, 6.4, 1.2, 103.0, 3.0],     # шеврон-заслон перед углом появления
	[31.5, 12.5, 2.2, 2.2, 0.0, 3.4],      # колонны по бокам угла
	[13.5, 0.0, 7.0, 1.2, 90.0, 3.0],      # стена перед площадью
]
## Радиальные перегородки между коридорами и короткие стены у внешнего края: [r0, r1, угол от оси, толщина]
const RADIAL := [[17.0, 25.5, 30.0, 1.2]]
const FLANK := [[33.0, 30.0, 6.5, 1.2]]   # [расстояние, угол от оси, длина, толщина] — вдоль края
## Руины на оси между командами (угол +60° от оси команды): [n, m, длина, толщина, угол к оси, высота]
const RUIN := [
	[33.5, 0.0, 10.0, 1.2, 90.0, 3.2],
	[29.1, 5.0, 7.8, 1.2, 0.0, 3.0],
	[29.1, -5.0, 7.8, 1.2, 0.0, 3.0],
]
const PLAZA_R := 9.0

## Стены: {c: Vector2 (локально), len, thick, ang (радианы, направление длины в xz), h}
var walls: Array = []
## Многоугольники стен (локально) — для сетки проходимости и миникарты
var wall_polys: Array = []
var hex := PackedVector2Array()
var nav := NavArea.new()
var fog: MeshInstance3D = null
var fog_mat: ShaderMaterial = null
var wall_mat: ShaderMaterial = null
var floor_mat: ShaderMaterial = null

const FOG_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;
uniform vec4 eyes[3];
uniform int count = 0;
uniform float strength = 0.0;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float vis = 0.0;
	for (int i = 0; i < 3; i++) {
		if (i < count) {
			float d = distance(wpos.xz, eyes[i].xz);
			vis = max(vis, 1.0 - smoothstep(eyes[i].w * 0.75, eyes[i].w, d));
		}
	}
	ALBEDO = vec3(0.01, 0.01, 0.03);
	ALPHA = (1.0 - vis) * 0.86 * strength;
}
"""

const WALL_SHADER := """
shader_type spatial;
uniform vec4 eyes[3];
uniform int count = 0;
uniform float strength = 0.0;
uniform vec3 stone_a : source_color = vec3(0.20, 0.20, 0.25);
uniform vec3 stone_b : source_color = vec3(0.11, 0.11, 0.15);
uniform vec3 glow : source_color = vec3(0.6, 0.25, 1.0);
uniform float band_y = 2.75;
varying vec3 wpos;
varying vec3 lpos;
varying vec3 lnorm;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	lpos = VERTEX;
	lnorm = NORMAL;
}
void fragment() {
	// кладка — в координатах самой стены, чтобы повёрнутые стены выглядели так же
	vec2 uv = abs(lnorm.x) > 0.5 ? vec2(lpos.z, wpos.y) : (abs(lnorm.z) > 0.5 ? vec2(lpos.x, wpos.y) : lpos.xz);
	vec2 b = uv / vec2(1.2, 0.55);
	b.x += floor(b.y) * 0.5;
	vec2 f = fract(b);
	float mortar = step(0.06, f.x) * step(0.08, f.y);
	float n = hash(floor(b));
	vec3 col = mix(stone_b, stone_a, n) * (0.55 + 0.45 * mortar);
	float band = smoothstep(0.06, 0.0, abs(wpos.y - band_y));
	col += glow * band * 0.9;
	float vis = 1.0;
	if (strength > 0.0) {
		vis = 0.0;
		for (int i = 0; i < 3; i++) {
			if (i < count) {
				float d = distance(wpos.xz, eyes[i].xz);
				vis = max(vis, 1.0 - smoothstep(eyes[i].w * 0.75, eyes[i].w, d));
			}
		}
		vis = mix(1.0, 0.25 + 0.75 * vis, strength);
	}
	ALBEDO = col * vis;
	EMISSION = glow * band * 0.6 * vis;
	ROUGHNESS = 0.85;
}
"""

const FLOOR_SHADER := """
shader_type spatial;
uniform vec3 tile_a : source_color = vec3(0.17, 0.17, 0.21);
uniform vec3 tile_b : source_color = vec3(0.10, 0.10, 0.13);
uniform vec3 rune : source_color = vec3(0.55, 0.25, 1.0);
varying vec3 wpos;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 t = wpos.xz / 2.0;
	vec2 f = fract(t);
	float grout = step(0.04, f.x) * step(0.04, f.y);
	float n = hash(floor(t));
	vec3 col = mix(tile_b, tile_a, n * 0.8 + 0.2) * (0.5 + 0.5 * grout);
	float hx = step(0.93, hash(floor(t * 0.5) + 3.1));
	col = mix(col, col * 1.35 + vec3(0.03, 0.02, 0.06), hx);
	ALBEDO = col;
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
}
"""


static func dir(deg: float) -> Vector2:
	return Vector2(cos(deg_to_rad(deg)), sin(deg_to_rad(deg)))


func _add_wall(c: Vector2, length: float, thick: float, ang: float, h: float) -> void:
	var d := Vector2(cos(ang), sin(ang))
	var nrm := Vector2(-d.y, d.x)
	var hl := d * length * 0.5
	var ht := nrm * thick * 0.5
	walls.append({"c": c, "len": length, "thick": thick, "ang": ang, "h": h})
	wall_polys.append(PackedVector2Array([c - hl - ht, c + hl - ht, c + hl + ht, c - hl + ht]))


## Стена в координатах оси: a — вдоль оси (угол axis), b — поперёк; rel — угол стены к оси.
func _axis_wall(axis: float, a: float, b: float, length: float, thick: float, rel: float, h: float) -> void:
	var u := dir(axis)
	var v := dir(axis + 90.0)
	_add_wall(u * a + v * b, length, thick, deg_to_rad(axis + rel), h)


func _init() -> void:
	for k in 6:
		hex.append(dir(-90.0 + 60.0 * k) * R)
	for ax: float in TEAM_ANGLES:
		for w in SECTOR:
			_axis_wall(ax, w[0], w[1], w[2], w[3], w[4], w[5])
			if w[1] != 0.0:
				_axis_wall(ax, w[0], -w[1], w[2], w[3], -w[4], w[5])
		for rd in RADIAL:
			for sg in [1.0, -1.0]:
				var a: float = ax + rd[2] * sg
				var u := dir(a)
				_add_wall(u * (rd[0] + rd[1]) * 0.5, rd[1] - rd[0], rd[3], deg_to_rad(a), 3.0)
		for fl in FLANK:
			for sg in [1.0, -1.0]:
				var a2: float = ax + fl[1] * sg
				_add_wall(dir(a2) * fl[0], fl[2], fl[3], deg_to_rad(a2 + 90.0), 3.0)
		var na: float = ax + 60.0
		for w in RUIN:
			_axis_wall(na, w[0], w[1], w[2], w[3], w[4], w[5])
		# колонны площади — между осью команды и осью руин
		for sg in [1.0, -1.0]:
			_add_wall(dir(ax + 30.0 * sg) * PLAZA_R, 1.8, 1.8, deg_to_rad(ax + 30.0 * sg), 4.2)
	nav.setup_poly(Rect2(-R - 1.0, -R - 1.0, R * 2.0 + 2.0, R * 2.0 + 2.0), hex, wall_polys,
		func(v: Vector2) -> Vector3: return Vector3(v.x + CENTER.x, 0.0, v.y + CENTER.z),
		func(p: Vector3) -> Vector2: return Vector2(p.x - CENTER.x, p.z - CENTER.z))


## Точки появления команды (номер команды = номер угла).
func spawn_points(slot: int) -> Array[Vector3]:
	var ax: float = TEAM_ANGLES[slot % 3]
	var u := dir(ax)
	var v := dir(ax + 90.0)
	var base := u * SPAWN_DIST
	var out: Array[Vector3] = []
	for o in [Vector2.ZERO, v * 2.6 - u * 1.6, -v * 2.6 - u * 1.6]:
		var p: Vector2 = base + o
		out.append(CENTER + Vector3(p.x, 0, p.y))
	return out


## Мировая точка по локальной (от центра арены).
static func world(l: Vector2) -> Vector3:
	return CENTER + Vector3(l.x, 0, l.y)


static func _shader(code: String) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = code
	var m := ShaderMaterial.new()
	m.shader = sh
	return m


func build(game: Node3D) -> void:
	var root := Node3D.new()
	root.name = "Arena"
	root.position = CENTER
	game.add_child(root)
	floor_mat = _shader(FLOOR_SHADER)
	wall_mat = load("res://assets/approved_materials/materials.gd").wall_material().duplicate()
	wall_mat.set_shader_parameter("glow", Color(0.6, 0.25, 1.0))
	fog_mat = _shader(FOG_SHADER)
	# пол — шестиугольная плита; вокруг — заснеженный берег с лесом (см. decorate)
	var fl := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = R + 2.0
	cm.bottom_radius = R + 2.0
	cm.height = 10.0
	cm.radial_segments = 6
	cm.rings = 1
	fl.mesh = cm
	fl.material_override = floor_mat
	fl.position = Vector3(0, -5.0, 0)
	root.add_child(fl)
	var rim := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = R + 17.0
	rm.bottom_radius = R + 19.0
	rm.height = 10.0
	rm.radial_segments = 6
	rm.rings = 1
	rim.mesh = rm
	var ice := World.shader_mat(World.TERRAIN_SHADER)
	rim.material_override = ice
	rim.position = Vector3(0, -5.06, 0)
	root.add_child(rim)
	# внешняя стена по краям шестиугольника
	var ap := R * cos(deg_to_rad(30.0))
	for k in 6:
		var mid := -60.0 + 60.0 * k
		var c := dir(mid) * (ap + 0.75)
		_wall_mesh(root, {"c": c, "len": R + 1.6, "thick": 1.5, "ang": deg_to_rad(mid + 90.0), "h": 3.6})
	for w in walls:
		_wall_mesh(root, w)
	# руны в углах появления и на центральной площади
	var rune_pts: Array = [Vector2.ZERO]
	for ax: float in TEAM_ANGLES:
		rune_pts.append(dir(ax) * SPAWN_DIST)
	for p: Vector2 in rune_pts:
		var ring := MeshInstance3D.new()
		ring.mesh = Fx.flat_ring_mesh(2.6, 3.0, 48)
		ring.material_override = Fx.glow_mat(Color(0.6, 0.3, 1.0), 1.4, false, 0.65)
		ring.position = Vector3(p.x, 0.04, p.y)
		root.add_child(ring)
		var ring2 := MeshInstance3D.new()
		ring2.mesh = Fx.flat_ring_mesh(1.1, 1.3, 6)
		ring2.material_override = Fx.glow_mat(Color(0.9, 0.3, 0.4), 1.2, false, 0.6)
		ring2.position = Vector3(p.x, 0.05, p.y)
		root.add_child(ring2)
	# цвет команды под углом появления
	for t in 3:
		var p2: Vector2 = dir(TEAM_ANGLES[t]) * SPAWN_DIST
		var disc := MeshInstance3D.new()
		disc.mesh = Fx.flat_ring_mesh(3.3, 3.7, 48)
		disc.material_override = Fx.glow_mat(Data.TEAM_COLORS[t], 1.6, false, 0.7)
		disc.position = Vector3(p2.x, 0.045, p2.y)
		root.add_child(disc)
	# колонны площади
	for w in walls:
		if w.len < 2.0 and w.h > 4.0:
			var pl := World.prop("ArenaPillar")
			pl.position = Vector3(w.c.x, 0, w.c.y)
			root.add_child(pl)
	# жаровни: в руинах между командами и у площади
	for ax: float in TEAM_ANGLES:
		for p3: Vector2 in [dir(ax + 60.0) * 30.0, dir(ax) * 8.0]:
			var br := World.prop("Brazier")
			br.position = Vector3(p3.x, 0, p3.y)
			root.add_child(br)
			var l := OmniLight3D.new()
			l.light_color = Color(0.75, 0.45, 1.0)
			l.light_energy = 2.0
			l.omni_range = 11.0
			l.position = br.position + Vector3(0, 2.0, 0)
			root.add_child(l)
	# туман войны поверх пола
	fog = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(R * 2.0 + 4.0, R * 2.0 + 4.0)
	fog.mesh = pm
	fog.material_override = fog_mat
	fog.position = Vector3(0, 0.07, 0)
	fog.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(fog)
	set_fog([], 0.0)


func _wall_mesh(root: Node3D, w: Dictionary) -> void:
	var c: Vector2 = w.c
	var h: float = w.h
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w.len, h, w.thick)
	mi.mesh = bm
	mi.material_override = wall_mat
	mi.position = Vector3(c.x, h / 2.0, c.y)
	mi.rotation.y = -float(w.ang)
	root.add_child(mi)
	var cap := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(w.len + 0.25, 0.22, w.thick + 0.25)
	cap.mesh = cm
	cap.material_override = wall_mat
	cap.position = Vector3(c.x, h + 0.11, c.y)
	cap.rotation.y = -float(w.ang)
	root.add_child(cap)


## Берег вокруг арены: сосны, мёртвые деревья, камни, сторожевые башни у углов руин; иней на плитах.
func decorate(d: Decor) -> void:
	var ap := R * cos(deg_to_rad(30.0))
	# сторожевые башни снаружи — у углов между командами
	for ax: float in TEAM_ANGLES:
		var p := world(dir(ax + 60.0) * (R + 7.5))
		d.add("Watchtower", p, -deg_to_rad(ax + 60.0) - PI * 0.5, 1.0, 0.8)
		d.occupy(p, 4.0)
	# лес по кругу: от стены до берега
	var rr := ap + 4.0
	while rr < R + 15.0:
		var n := int(TAU * rr / 6.5)
		for k in n:
			var a := TAU * (k + d.rng.randf() * 0.6) / n
			var lp := Vector2(cos(a), sin(a)) * (rr + d.rng.randf_range(-1.2, 1.2))
			if not _outside_hex(lp, 3.5) or not _inside_hex(lp, R + 15.5):
				continue
			var p := world(lp)
			p.y = -0.08
			if not d.free_at(p, 2.0):
				continue
			var r := d.rng.randf()
			if r < 0.65:
				d.add(d.pick(Decor.PINES), p, INF, d.rng.randf_range(0.9, 1.4), d.rng.randf_range(0.6, 0.85))
			elif r < 0.8:
				d.add(d.pick(Decor.DEAD), p, INF, d.rng.randf_range(0.6, 0.9), 0.5)
			else:
				d.add(d.pick(Decor.ROCKS), p + Vector3(0, -0.4, 0), INF, d.rng.randf_range(1.0, 1.8), 0.8)
			d.occupy(p, 2.1)
		rr += 5.5
	# у берега — валуны
	var rs := R + 17.0
	for k in 40:
		var a := TAU * (k + d.rng.randf()) / 40.0
		var p := world(Vector2(cos(a), sin(a)) * rs * d.rng.randf_range(0.86, 0.96)) + Vector3(0, -0.9, 0)
		d.add(d.pick(Decor.ROCKS), p, INF, d.rng.randf_range(1.4, 2.4), 0.75)
	# внутри: иней на траве вдоль стен, редкие камешки
	for i in 260:
		var lp := Vector2(d.rng.randf_range(-R, R), d.rng.randf_range(-R, R))
		if not _inside_hex(lp, R - 1.5) or lp.length() < PLAZA_R + 2.0:
			continue
		var near := false
		for poly: PackedVector2Array in wall_polys:
			if Geometry2D.is_point_in_polygon(lp, poly):
				near = false
				break
			for j in poly.size():
				var q := Geometry2D.get_closest_point_to_segment(lp, poly[j], poly[(j + 1) % poly.size()])
				if q.distance_to(lp) < 1.6:
					near = true
		if not near and _inside_hex(lp, R - 3.0):
			continue
		var p2 := world(lp)
		if d.rng.randf() < 0.8:
			d.add(d.pick(Decor.GRASS), p2, INF, d.rng.randf_range(0.8, 1.2), 0.0, 0.7)
		else:
			d.add("Pebble_Round_%d" % (1 + d.rng.randi() % 3), p2, INF, d.rng.randf_range(1.5, 2.5), 0.4)


## Точка внутри шестиугольника радиуса rad (до угла)?
static func _inside_hex(p: Vector2, rad: float) -> bool:
	var ap := rad * cos(deg_to_rad(30.0))
	for k in 6:
		var n := dir(-60.0 + 60.0 * k)
		if p.dot(n) > ap:
			return false
	return true


static func _outside_hex(p: Vector2, margin: float) -> bool:
	return not _inside_hex(p, R + margin / cos(deg_to_rad(30.0)))


## eyes — [Vector4(x, 0, z, радиус)]; strength 0 — тумана нет.
func set_fog(eyes: Array, strength: float) -> void:
	var arr := PackedVector4Array()
	for i in 3:
		arr.append(eyes[i] if i < eyes.size() else Vector4.ZERO)
	for m in [fog_mat, wall_mat]:
		if m == null:
			continue
		m.set_shader_parameter("eyes", arr)
		m.set_shader_parameter("count", mini(eyes.size(), 3))
		m.set_shader_parameter("strength", strength)
	if fog:
		fog.visible = strength > 0.0

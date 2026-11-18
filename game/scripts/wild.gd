class_name Wild
extends RefCounted
## Общий лес — отдельный остров за вратами, симметричный на три стороны. Сюда попадают только через врата
## мини-лесов. У каждой команды свой сектор: врата, развилка, три средних лагеря, два древних у логова.
## Между секторами — святилища рун и площадки Рогов; в центре — логово хвостатого, к нему три узких прохода.
## Всё, что не поляна и не тропа, — чаща: сквозь неё не пройти и не видно.
## Локальные координаты — метры от центра: Vector2(x, z), +z — на юг, к островам.

## Номер области (у островов 0..2, у арены −1)
const AREA := -2
## Каст врат и телепорта «2», секунды
const CAST := 3.0
const CAST_SCROLL := 4.0
const R := 60.0
const CENTER := Vector3(0.0, 0.0, -278.0)
## Направления секторов команд 0, 1, 2 (градусы в плоскости xz): команда 0 — с юга, от островов
const TEAM_ANGLES := [90.0, -30.0, 210.0]
## Обзор героя в общем лесу (чаща его перекрывает)
const VISION := 18.0
const STEALTH_VISION := 7.0
## Полуширина троп и узких проходов к логову
const PATH_W := 2.5
const PASS_W := 1.9
const LAIR_R := 9.0

## Поляны сектора в координатах (a — вдоль оси от центра к вратам, b — поперёк): [a, b, радиус, вид]
const SECTOR := [
	[50.0, 0.0, 6.2, "gate"],
	[34.0, 0.0, 4.2, "hub"],
	[41.0, 14.0, 4.6, "medium"],
	[41.0, -14.0, 4.6, "medium"],
	[29.0, 11.5, 4.3, "medium"],
	[16.5, 9.5, 4.3, "ancient"],
	[16.5, -9.5, 4.3, "ancient"],
]
## Поляны на границе секторов (ось +60° от оси команды): [расстояние, радиус, вид]
const SPOKE := [[25.0, 3.8, "shrine"], [43.0, 6.4, "horn"]]
## Тропы сектора: [полуширина, точки (a, b)...]
const SECTOR_PATHS := [
	[PATH_W, [50.0, 0.0], [42.0, 1.2], [34.0, 0.0]],
	[PASS_W, [34.0, 0.0], [26.0, -1.0], [18.0, 0.6], [7.5, 0.0]],
	[PATH_W, [50.0, 0.0], [46.5, 8.0], [41.0, 14.0]],
	[PATH_W, [50.0, 0.0], [46.5, -8.0], [41.0, -14.0]],
	[PATH_W, [34.0, 0.0], [32.5, 6.5], [29.0, 11.5]],
	[PATH_W, [29.0, 11.5], [22.5, 12.2], [16.5, 9.5]],
	[PATH_W, [34.0, 0.0], [26.5, -6.2], [16.5, -9.5]],
	[PATH_W, [16.5, 9.5], [15.6, 16.0], [12.5, 21.65]],
	[PATH_W, [16.5, -9.5], [15.6, -16.0], [12.5, -21.65]],
	[PATH_W, [12.5, 21.65], [18.6, 28.6], [21.5, 37.2]],
	[PATH_W, [41.0, 14.0], [33.5, 27.0], [21.5, 37.2]],
	[PATH_W, [41.0, -14.0], [33.5, -27.0], [21.5, -37.2]],
]
const MASK_PX := 2.0

## Поляны: {c: Vector2, r, kind, team (−1 — ничья), k (номер стороны/оси)}
static var clearings: Array = []
## Тропы: {pts: Array[Vector2], w}
static var paths: Array = []
static var _ready := false
## Расстояние до открытого места по сетке 1 м (отрицательное — внутри), с неровным краем
static var _grid := PackedFloat32Array()
static var _gn := 0

var nav := NavArea.new()
var fog: MeshInstance3D = null
var fog_mat: ShaderMaterial = null
## Телепорты общего леса (врата команд): тот же вид, что Zone.pads
var pads: Array = []

const FOG_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled;
uniform vec4 eyes[6];
uniform int count = 0;
uniform float strength = 1.0;
varying vec3 wpos;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	// туман висит над кронами: круг обзора считаем по земле под лучом камеры, а не по самой плоскости
	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 g = wpos + (wpos - cam) * (wpos.y / max(cam.y - wpos.y, 0.01));
	float vis = 0.0;
	for (int i = 0; i < 6; i++) {
		if (i < count) {
			float d = distance(g.xz, eyes[i].xz);
			vis = max(vis, 1.0 - smoothstep(eyes[i].w * 0.72, eyes[i].w * 1.05, d));
		}
	}
	float n = noise(g.xz * 0.07 + vec2(TIME * 0.02, TIME * 0.013)) * 0.6 + noise(g.xz * 0.19 - vec2(TIME * 0.015)) * 0.4;
	ALBEDO = mix(vec3(0.015, 0.03, 0.035), vec3(0.05, 0.08, 0.08), n);
	ALPHA = (1.0 - vis) * (0.84 + 0.1 * n) * strength;
}
"""


static func dir(deg: float) -> Vector2:
	var a := deg_to_rad(deg)
	return Vector2(cos(a), sin(a))


## Мировая точка по локальной.
static func world(l: Vector2) -> Vector3:
	return CENTER + Vector3(l.x, 0.0, l.y)


static func local(p: Vector3) -> Vector2:
	return Vector2(p.x - CENTER.x, p.z - CENTER.z)


## Точка сектора команды t: a — от центра к вратам, b — поперёк.
static func sector(t: int, a: float, b: float) -> Vector2:
	var ang: float = TEAM_ANGLES[t % 3]
	return dir(ang) * a + dir(ang + 90.0) * b


## Где стоят врата команды t в общем лесу и куда из них выходят.
static func gate_pos(t: int) -> Vector3:
	return world(sector(t, 52.6, 0.0))


static func gate_exit(t: int) -> Vector3:
	return world(sector(t, 47.2, 0.0))


static func lair() -> Vector3:
	return CENTER


static func _dseg(p: Vector2, a: Vector2, b: Vector2) -> float:
	var d := b - a
	var l := d.length_squared()
	var t := clampf((p - a).dot(d) / l, 0.0, 1.0) if l > 0.0 else 0.0
	return p.distance_to(a + d * t)


static func ensure() -> void:
	if _ready:
		return
	_ready = true
	clearings.append({"c": Vector2.ZERO, "r": LAIR_R, "kind": "lair", "team": -1, "k": 0})
	for t in 3:
		for s in SECTOR:
			clearings.append({"c": sector(t, s[0], s[1]), "r": float(s[2]), "kind": str(s[3]), "team": t, "k": t})
		var na: float = TEAM_ANGLES[t] + 60.0
		for s in SPOKE:
			clearings.append({"c": dir(na) * float(s[0]), "r": float(s[1]), "kind": str(s[2]), "team": -1, "k": t})
		for sp in SECTOR_PATHS:
			var pts: Array[Vector2] = []
			for i in range(1, sp.size()):
				pts.append(sector(t, sp[i][0], sp[i][1]))
			paths.append({"pts": pts, "w": float(sp[0])})
	# сетка расстояний: шаг 1 м, по краю — лёгкая «рваность», чтобы поляны не были ровными кругами
	_gn = int(R * 2.0) + 9
	_grid.resize(_gn * _gn)
	for j in _gn:
		for i in _gn:
			var p := Vector2(i - _gn / 2, j - _gn / 2)
			var d := _d_exact(p)
			d += 0.45 * sin(p.x * 0.43 + 1.3) * sin(p.y * 0.39 + 0.7) + 0.3 * sin(p.x * 0.97 + p.y * 0.71)
			# остров кончается: за радиусом — обрыв
			d = maxf(d, p.length() - (R - 1.5))
			_grid[j * _gn + i] = d


static func _d_exact(p: Vector2) -> float:
	var best := 1e9
	for c in clearings:
		best = minf(best, p.distance_to(c.c) - float(c.r))
	for pl in paths:
		var pts: Array[Vector2] = pl.pts
		for i in pts.size() - 1:
			best = minf(best, _dseg(p, pts[i], pts[i + 1]) - float(pl.w))
	return best


## Расстояние до открытого места (поляны или тропы) в локальной точке; отрицательное — на открытом месте.
static func d_open(p: Vector2) -> float:
	ensure()
	var fx := clampf(p.x + _gn / 2, 0.0, _gn - 1.001)
	var fy := clampf(p.y + _gn / 2, 0.0, _gn - 1.001)
	var ix := int(fx)
	var iy := int(fy)
	var tx := fx - ix
	var ty := fy - iy
	var a := _grid[iy * _gn + ix]
	var b := _grid[iy * _gn + ix + 1]
	var c := _grid[(iy + 1) * _gn + ix]
	var d := _grid[(iy + 1) * _gn + ix + 1]
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), ty)


## Расстояние до ближайшей тропы (для рисунка земли).
static func d_path(p: Vector2) -> float:
	var best := 1e9
	for pl in paths:
		var pts: Array[Vector2] = pl.pts
		for i in pts.size() - 1:
			best = minf(best, _dseg(p, pts[i], pts[i + 1]) - float(pl.w) + PATH_W)
	return best


static func of_kind(kind: String) -> Array:
	ensure()
	return clearings.filter(func(c: Dictionary) -> bool: return c.kind == kind)


## Лагеря общего леса: [{pos, kind («medium»/«ancient»), team}]
static func camp_list() -> Array:
	var out: Array = []
	for c in clearings:
		if c.kind == "medium" or c.kind == "ancient":
			out.append({"pos": world(c.c), "kind": c.kind, "team": c.team})
	return out


static func points(kind: String) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for c in of_kind(kind):
		out.append(world(c.c))
	return out


func _init() -> void:
	ensure()
	nav.setup_fn(Rect2(-R - 2.0, -R - 2.0, R * 2.0 + 4.0, R * 2.0 + 4.0),
		func(c: Vector2) -> bool: return d_open(c) < -0.55,
		func(v: Vector2) -> Vector3: return Vector3(v.x + CENTER.x, 0.0, v.y + CENTER.z),
		func(p: Vector3) -> Vector2: return Vector2(p.x - CENTER.x, p.z - CENTER.z))
	for t in 3:
		pads.append({"id": "gate", "pos": gate_pos(t), "exit": Vector3.ZERO, "to_name": Data.TEAM_NAMES[t], "cast": CAST,
			"area": AREA, "to_area": t, "own": false, "color": Data.TEAM_COLORS[t], "team": t})


# ----------------------------------------------------------------- земля и эффекты
func build(game: Node3D) -> void:
	var root := Node3D.new()
	root.name = "Wild"
	game.add_child(root)
	# земля: диск с рисунком троп, полян и песком логова
	var size := R * 2.0 + 8.0
	var n := int(size * MASK_PX)
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var sand_spots: Array = of_kind("lair") + of_kind("horn")
	for y in n:
		for x in n:
			# шейдер земли считает «север» вверх: строка картинки — это −z
			var p := Vector2(-size * 0.5 + (x + 0.5) / MASK_PX, size * 0.5 - (y + 0.5) / MASK_PX)
			var dop := d_open(p)
			var path := 1.0 - smoothstep(-0.9, 0.2, d_path(p) - PATH_W)
			var gl := 1.0 - smoothstep(-2.2, 0.6, dop)
			var sand := 0.0
			for c in sand_spots:
				var r: float = c.r
				sand = maxf(sand, 1.0 - smoothstep(r - 2.4, r + 0.3, p.distance_to(c.c)))
			var shade := smoothstep(0.2, 3.0, dop)
			img.set_pixel(x, y, Color(path, gl, sand, shade))
	var mat := Forest2._mat(Forest2.GROUND_SHADER, {
		"mask": ImageTexture.create_from_image(img),
		"m_rect": Vector4(-size * 0.5, -size * 0.5, size, size),
		"z_origin": Vector2(CENTER.x, CENTER.z),
		"s_k": 1.0,
	})
	var ground := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = R + 2.5
	cyl.bottom_radius = R - 3.0
	cyl.height = 12.0
	cyl.radial_segments = 48
	ground.mesh = cyl
	ground.material_override = mat
	ground.position = CENTER + Vector3(0, -5.98, 0)
	root.add_child(ground)

	# туман войны над кронами
	fog = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(size + 30.0, size + 30.0)
	fog.mesh = pm
	fog_mat = Forest2._mat(FOG_SHADER)
	fog.material_override = fog_mat
	fog.position = CENTER + Vector3(0, 11.0, 0)
	fog.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fog.sorting_offset = 50.0
	root.add_child(fog)
	set_fog([], 1.0)

	# светлячки
	var ff := CPUParticles3D.new()
	ff.amount = 260
	ff.lifetime = 7.0
	ff.preprocess = 7.0
	ff.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	ff.emission_box_extents = Vector3(R * 0.72, 1.3, R * 0.72)
	ff.position = CENTER + Vector3(0, 1.7, 0)
	ff.direction = Vector3(0, 1, 0)
	ff.spread = 180.0
	ff.gravity = Vector3.ZERO
	ff.initial_velocity_min = 0.15
	ff.initial_velocity_max = 0.5
	var qm := QuadMesh.new()
	qm.size = Vector2(0.17, 0.17)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fm.vertex_color_use_as_albedo = true
	fm.albedo_color = Color(1.0, 1.0, 0.55)
	fm.disable_receive_shadows = true
	fm.disable_fog = true
	qm.material = fm
	ff.mesh = qm
	var grad := Gradient.new()
	grad.set_color(0, Color(0.7, 1.0, 0.35, 0.0))
	grad.set_color(1, Color(0.7, 1.0, 0.35, 0.0))
	grad.add_point(0.2, Color(0.85, 1.0, 0.45, 1.0))
	grad.add_point(0.5, Color(0.5, 0.9, 0.3, 0.3))
	grad.add_point(0.8, Color(0.9, 1.0, 0.5, 1.0))
	ff.color_ramp = grad
	ff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ff)

	# солнечные пятна на полянах, низкий туман в чаще
	var sun_mat := Forest2._mat(Forest2.SUN_SHADER)
	var fog_low := Forest2._mat(Forest2.FOG_SHADER)
	for c in clearings:
		if c.kind == "lair" or c.kind == "horn":
			continue
		var mi := MeshInstance3D.new()
		var pl := PlaneMesh.new()
		pl.size = Vector2.ONE * (float(c.r) * 2.0 + 3.0)
		mi.mesh = pl
		mi.material_override = sun_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = world(c.c) + Vector3(0, 0.06, 0)
		root.add_child(mi)
	for k in 12:
		var lp := dir(15.0 + k * 30.0) * (30.0 if k % 2 == 0 else 46.0)
		var mi := MeshInstance3D.new()
		var pl := PlaneMesh.new()
		pl.size = Vector2(24.0, 24.0)
		mi.mesh = pl
		mi.material_override = fog_low
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = world(lp) + Vector3(0, 0.8, 0)
		root.add_child(mi)

	# логово: тлеющий свет и пыль
	_light(root, CENTER + Vector3(0, 3.0, 0), Color(1.0, 0.42, 0.18), 2.4, 16.0)
	var dust := CPUParticles3D.new()
	dust.amount = 50
	dust.lifetime = 4.0
	dust.preprocess = 4.0
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	dust.emission_sphere_radius = LAIR_R * 0.85
	dust.position = CENTER + Vector3(0, 0.6, 0)
	dust.gravity = Vector3(0, 0.15, 0)
	dust.initial_velocity_min = 0.2
	dust.initial_velocity_max = 0.6
	dust.direction = Vector3(1, 0.2, 0)
	dust.spread = 180.0
	var dq := QuadMesh.new()
	dq.size = Vector2(1.0, 1.0)
	var dmat := StandardMaterial3D.new()
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dmat.vertex_color_use_as_albedo = true
	dmat.disable_fog = true
	dq.material = dmat
	dust.mesh = dq
	var dg := Gradient.new()
	dg.set_color(0, Color(0.75, 0.6, 0.4, 0.0))
	dg.set_color(1, Color(0.75, 0.6, 0.4, 0.0))
	dg.add_point(0.4, Color(0.8, 0.65, 0.42, 0.28))
	dust.color_ramp = dg
	dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(dust)

	# святилища рун: постамент (сама руна появляется по расписанию)
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.42, 0.44, 0.46)
	stone.roughness = 0.9
	for c in of_kind("shrine"):
		var sp := world(c.c)
		var ped := MeshInstance3D.new()
		var pc := CylinderMesh.new()
		pc.top_radius = 0.5
		pc.bottom_radius = 0.7
		pc.height = 0.9
		ped.mesh = pc
		ped.material_override = stone
		ped.position = sp + Vector3(0, 0.45, 0)
		root.add_child(ped)
		_light(root, sp + Vector3(0, 2.0, 0), Color(0.45, 0.85, 1.0), 1.4, 8.0)
		Forest2._label(root, sp + Vector3(0, 4.2, 0), "Святилище рун", Color(0.6, 0.9, 1.0))
	for c in of_kind("horn"):
		var hp := world(c.c)
		_light(root, hp + Vector3(0, 3.0, 0), Color(1.0, 0.75, 0.3), 1.8, 12.0)
		for a in [0.4, 2.5, 4.6]:
			var b := World.prop("Brazier")
			b.position = hp + Vector3(cos(a), 0, sin(a)) * (float(c.r) - 0.8)
			root.add_child(b)
	for t in 3:
		var gp := world(sector(t, 50.0, 0.0))
		_light(root, gp + Vector3(0, 3.0, 0), Data.TEAM_COLORS[t], 2.2, 13.0)
		for sgn in [-1.0, 1.0]:
			var ln := World.prop("Lantern")
			ln.position = world(sector(t, 46.5, 3.6 * sgn))
			ln.scale = Vector3.ONE * 1.2
			root.add_child(ln)
		var hub := World.prop("Lantern")
		hub.position = world(sector(t, 34.0, 2.6))
		hub.scale = Vector3.ONE * 1.25
		root.add_child(hub)
		_light(root, hub.position + Vector3(0, 2.2, 0), Color(1.0, 0.75, 0.45), 1.3, 8.0)


static func _light(root: Node3D, pos: Vector3, col: Color, energy: float, rng_m: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng_m
	l.position = pos
	root.add_child(l)


## Туман войны для игрока: eyes — Vector4(x, 0, z, радиус) своих героев в общем лесу.
func set_fog(eyes: Array, strength: float) -> void:
	if fog_mat == null:
		return
	var arr: Array = []
	for e in eyes:
		if arr.size() < 6:
			arr.append(e)
	var cnt := arr.size()
	while arr.size() < 6:
		arr.append(Vector4.ZERO)
	fog_mat.set_shader_parameter("eyes", arr)
	fog_mat.set_shader_parameter("count", cnt)
	fog_mat.set_shader_parameter("strength", strength)
	fog.visible = strength > 0.01


# ----------------------------------------------------------------- деревья, кусты, камни, руины
## Камера смотрит с юга: высокое дерево к югу от открытого места закрыло бы его. Такие — ниже или кусты.
static func _shadow_k(lp: Vector2) -> float:
	if d_open(lp + Vector2(0, -2.8)) < 0.5:
		return 0.0
	if d_open(lp + Vector2(0, -5.2)) < 0.5:
		return 0.6
	if d_open(lp + Vector2(0, -7.6)) < 0.5:
		return 0.8
	return 1.0


static func _tree(d: Decor, lp: Vector2, rng: RandomNumberGenerator, k: float) -> void:
	var p := world(lp)
	var sk := _shadow_k(lp)
	if sk <= 0.0:
		d.add("Bush_Common_Flowers", p, INF, rng.randf_range(1.1, 1.5))
		return
	k *= sk * 0.86
	var r := rng.randf()
	# ближе к логову лес мрачнее: больше сосен и сухих деревьев
	var dark := 1.0 - clampf((lp.length() - 12.0) / 26.0, 0.0, 1.0)
	if r < 0.5 - dark * 0.3:
		d.add(d.pick(Decor.COMMON), p, INF, rng.randf_range(0.9, 1.25) * k)
	elif r < 0.86 - dark * 0.12:
		d.add(d.pick(Decor.PINES), p, INF, rng.randf_range(0.9, 1.25) * k)
	elif r < 0.96:
		d.add(d.pick(Decor.DEAD), p, INF, rng.randf_range(0.7, 1.0) * k)
	else:
		d.add(d.pick(Decor.ROCKS), p + Vector3(0, -0.3, 0), INF, rng.randf_range(0.9, 1.5))


static func _ring(d: Decor, c: Vector2, r: float, n: int, model: String, s0: float, s1: float, rng: RandomNumberGenerator,
		y := 0.0) -> void:
	for k in n:
		var a := TAU * k / n + rng.randf_range(-0.12, 0.12)
		var lp := c + Vector2(cos(a), sin(a)) * (r + rng.randf_range(-0.2, 0.2))
		if d_path(lp) < PATH_W + 0.4:
			continue   # проход на тропу остаётся свободным
		d.add(model, world(lp) + Vector3(0, y, 0), INF, rng.randf_range(s0, s1))


func decorate(d: Decor) -> void:
	var rng := d.rng
	# чаща: дерево на каждые ~2,2 м, под ними кусты и папоротник; у самого обрыва — только камни
	var z := -R
	while z < R:
		var x := -R
		while x < R:
			var lp := Vector2(x + rng.randf() * 1.6, z + rng.randf() * 1.6)
			x += 2.15
			if lp.length() > R + 0.5:
				continue
			var dop := d_open(lp)
			if dop < 0.75:
				continue
			if lp.length() > R - 2.2:
				if rng.randf() < 0.3:
					d.add(d.pick(Decor.ROCKS), world(lp) + Vector3(0, -0.3, 0), INF, rng.randf_range(0.9, 1.6))
				continue
			if dop > 1.5:
				_tree(d, lp, rng, 0.95 + minf(dop, 6.0) * 0.06)
			if rng.randf() < 0.5:
				var p := world(lp + Vector2(rng.randf_range(-0.8, 0.8), rng.randf_range(-0.8, 0.8)))
				var r := rng.randf()
				if r < 0.45:
					d.add("Bush_Common_Flowers", p, INF, rng.randf_range(1.0, 1.4))
				elif r < 0.7:
					d.add("Fern_1", p, INF, rng.randf_range(0.9, 1.3))
				elif r < 0.85:
					d.add("Plant_1_Big", p, INF, rng.randf_range(0.8, 1.1))
				else:
					d.add("Mushroom_Laetiporus", p, INF, rng.randf_range(1.0, 1.5))
		z += 2.15
	# кромка у полян и троп: кусты, папоротник, трава — мягкий переход
	z = -R
	while z < R:
		var x2 := -R
		while x2 < R:
			var lp := Vector2(x2 + rng.randf() * 1.4, z + rng.randf() * 1.4)
			x2 += 1.5
			var dop := d_open(lp)
			if dop < -0.4 or dop > 0.9 or rng.randf() < 0.3:
				continue
			var p := world(lp)
			var r := rng.randf()
			if r < 0.33:
				d.add("Bush_Common_Flowers", p, INF, rng.randf_range(0.8, 1.15))
			elif r < 0.58:
				d.add("Fern_1", p, INF, rng.randf_range(0.8, 1.2))
			elif r < 0.86:
				d.add(d.pick(Decor.GRASS), p, INF, rng.randf_range(1.0, 1.5))
			else:
				d.add("Mushroom_Common", p, INF, rng.randf_range(0.9, 1.3))
		z += 1.5
	# тропы: камни-ступени и галька
	for pl in paths:
		var pts: Array[Vector2] = pl.pts
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var n := int(a.distance_to(b) / 1.7)
			for k in n:
				var lp: Vector2 = a.lerp(b, (k + rng.randf() * 0.5) / n)
				var side := (b - a).orthogonal().normalized() * rng.randf_range(-0.9, 0.9)
				var p := world(lp + side) + Vector3(0, 0.03, 0)
				if rng.randf() < 0.36:
					d.add("RockPath_Round_Small_%d" % (1 + rng.randi() % 3), p, INF, rng.randf_range(0.9, 1.25))
				elif rng.randf() < 0.4:
					d.add("Pebble_Round_%d" % (1 + rng.randi() % 3), p, INF, rng.randf_range(1.2, 1.9))
	# поляны
	for c in clearings:
		var cp: Vector2 = c.c
		var r: float = c.r
		match str(c.kind):
			"gate":
				_ring(d, cp, r - 0.6, 14, "RockPath_Round_Wide", 1.2, 1.5, rng, 0.03)
				_grass(d, cp, r, rng, true)
			"hub":
				d.add("RockPath_Square_Wide", world(cp) + Vector3(0, 0.04, 0), 0.0, 1.6)
				_grass(d, cp, r, rng, true)
			"medium":
				# звериное логово: камни, грибы кругом, кости-обломки
				_ring(d, cp, r - 1.0, 9, "Mushroom_Common", 1.1, 1.7, rng)
				for k in 4:
					var lp := cp + Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * (r - 1.0)
					if d_path(lp) > PATH_W + 0.5:
						d.add(d.pick(Decor.ROCKS), world(lp) + Vector3(0, -0.35, 0), INF, rng.randf_range(0.5, 0.8))
				_grass(d, cp, r, rng, false)
			"ancient":
				# руины: арка, обломки стен, кирпичи, лианы
				var out := cp.normalized()
				var side := out.orthogonal()
				var yaw := atan2(out.x, out.y)
				d.add("Wall_Arch", world(cp + out * (r - 0.9)), yaw, 1.0)
				d.add("Wall_UnevenBrick_Straight", world(cp + out * (r - 2.2) + side * (r - 1.2)), yaw + PI * 0.5 + 0.15, 1.0)
				d.add("Wall_UnevenBrick_Window_Wide_Round", world(cp + out * (r - 1.8) - side * (r - 1.4)), yaw - 0.35, 0.9)
				for k in 8:
					var lp := cp + Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * (r - 0.8)
					d.add("Prop_Brick%d" % (1 + rng.randi() % 2), world(lp), INF, rng.randf_range(0.9, 1.3))
				for k in 3:
					d.add("Prop_Vine%d" % (5 + rng.randi() % 2), world(cp + out * (r - 1.0) + side * (k - 1.0) * 1.3), INF, 1.0)
				_ring(d, cp, r - 0.4, 10, "Pebble_Square_%d" % (1 + rng.randi() % 2), 1.4, 2.0, rng)
			"shrine":
				_ring(d, cp, 2.4, 8, "RockPath_Round_Wide", 1.0, 1.2, rng, 0.03)
				d.add("RockPath_Square_Wide", world(cp) + Vector3(0, 0.04, 0), 0.0, 1.6)
				# клёны-момидзи — красные деревья есть только у святилищ
				var o2 := cp.normalized()
				d.add(Decor.TWISTED[0], world(cp + o2 * (r + 2.8) + o2.orthogonal() * 2.2), INF, 0.44)
				d.add(Decor.TWISTED[2], world(cp + o2 * (r + 2.6) - o2.orthogonal() * 2.6), INF, 0.4)
			"horn":
				_ring(d, cp, r - 0.3, 16, "Rock_Medium_1", 0.9, 1.4, rng, -0.45)
				for k in 3:
					var a := PI + 0.5 + k * 0.9
					d.add(d.pick(Decor.DEAD), world(cp + Vector2(cos(a), sin(a)) * (r + 1.2)), INF, rng.randf_range(0.8, 1.0))
			"lair":
				_ring(d, cp, r - 0.3, 26, "Rock_Medium_1", 1.1, 1.8, rng, -0.45)
				_ring(d, cp, r - 1.6, 16, "Pebble_Round_2", 1.6, 2.6, rng)
				# сухие деревья — только с севера: с юга они закрыли бы логово от камеры
				for k in 5:
					var a := PI + 0.35 + k * 0.6
					d.add(d.pick(Decor.DEAD), world(cp + Vector2(cos(a), sin(a)) * (r + 1.6)), INF, rng.randf_range(0.85, 1.1))


static func _grass(d: Decor, cp: Vector2, r: float, rng: RandomNumberGenerator, flowers: bool) -> void:
	var cnt := int(r * r * 0.9)
	for k in cnt:
		var a := rng.randf() * TAU
		var lp := cp + Vector2(cos(a), sin(a)) * sqrt(rng.randf()) * (r - 0.5)
		if d_path(lp) < PATH_W * 0.8:
			continue
		var p := world(lp) + Vector3(0, 0.02, 0)
		var t := rng.randf()
		if t < 0.6:
			d.add(d.pick(Decor.GRASS), p, INF, rng.randf_range(0.9, 1.4))
		elif t < 0.82 and flowers:
			d.add(d.pick(Decor.FLOWERS), p, INF, rng.randf_range(0.8, 1.1))
		elif t < 0.92:
			d.add("Clover_%d" % (1 + rng.randi() % 2), p, INF, rng.randf_range(0.9, 1.2))

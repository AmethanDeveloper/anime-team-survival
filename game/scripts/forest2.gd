class_name Forest2
extends RefCounted
## Мини-лес команды: чаща с тропинками и полянами.
## У входа (телепорт «2») опушка и лестница вниз, к центру острова; две тропы ведут к малому и среднему лагерям,
## оттуда — к развилке с каменным кругом; от развилки две узкие тропы: к большому лагерю и к вратам в общий лес.
## Всё, что не поляна и не тропа, — сплошной лес: туда не пройти и сквозь него не видно.
## Координаты — схемы острова (как в Zone): x поперёк, z от лагеря к лесу.

static var enabled := true
## Виды полян с лагерями нейтралов (слабые лагеря мини-леса)
const CAMPS := ["small", "medium", "big"]

## Поляны: [центр, радиус, вид]
const CLEARINGS := [
	[Vector2(-3.8, 70.0), 2.9, "entry"],
	[Vector2(3.3, 70.4), 3.1, "entry"],
	[Vector2(-5.0, 78.2), 2.4, "small"],
	[Vector2(5.0, 79.6), 2.6, "medium"],
	[Vector2(0.0, 82.8), 1.9, "shrine"],
	[Vector2(-5.0, 89.8), 2.9, "big"],
	[Vector2(5.0, 90.2), 3.2, "gate"],
]
## Тропинки (ломаные)
const PATHS := [
	[Vector2(0.0, 63.6), Vector2(0.0, 70.4)],
	[Vector2(-2.0, 72.4), Vector2(-3.6, 75.4), Vector2(-5.0, 78.2)],
	[Vector2(2.2, 73.2), Vector2(3.9, 76.6), Vector2(5.0, 79.6)],
	[Vector2(-5.0, 78.2), Vector2(-2.6, 80.8), Vector2(0.0, 82.8)],
	[Vector2(5.0, 79.6), Vector2(2.6, 81.4), Vector2(0.0, 82.8)],
	[Vector2(0.0, 82.8), Vector2(-1.8, 85.6), Vector2(-3.6, 87.6), Vector2(-5.0, 89.8)],
	[Vector2(0.0, 82.8), Vector2(1.8, 85.6), Vector2(3.6, 87.8), Vector2(5.0, 90.2)],
]
## Полуширина тропы и запас от чащи (схема; 1 = 2 м)
const PATH_W := 1.3
const EDGE := 0.35
const MASK_PX := 4.0


static func clearing(kind: String) -> Vector2:
	for c in CLEARINGS:
		if c[2] == kind:
			return c[0]
	return Vector2.ZERO


static func clearing_r(kind: String) -> float:
	for c in CLEARINGS:
		if c[2] == kind:
			return c[1]
	return 0.0


static func _dseg(p: Vector2, a: Vector2, b: Vector2) -> float:
	var d := b - a
	var l := d.length_squared()
	var t := clampf((p - a).dot(d) / l, 0.0, 1.0) if l > 0.0 else 0.0
	return p.distance_to(a + d * t)


static func d_path(p: Vector2) -> float:
	var best := 1e9
	for pl: Array in PATHS:
		for i in pl.size() - 1:
			best = minf(best, _dseg(p, pl[i], pl[i + 1]))
	return best


## Расстояние до открытого места (поляны или тропы); отрицательное — внутри.
static func d_open(p: Vector2) -> float:
	var best := d_path(p) - PATH_W
	for c in CLEARINGS:
		best = minf(best, p.distance_to(c[0]) - float(c[1]))
	return best


## Сплошной лес — клетки 1×1 схемы (2×2 м), склеенные по рядам. Они становятся препятствиями.
static func blocked_rects() -> Array:
	var out: Array = []
	var f := Zone.FOREST
	var z := f.position.y
	while z < f.end.y - 0.01:
		var h := minf(1.0, f.end.y - z)
		var run_x := INF
		var x := f.position.x
		while x < f.end.x + 0.5:
			var blocked := x < f.end.x - 0.01 and d_open(Vector2(x + 0.5, z + h * 0.5)) > EDGE
			if blocked and run_x == INF:
				run_x = x
			elif not blocked and run_x != INF:
				out.append(Rect2(run_x, z, minf(x, f.end.x) - run_x, h))
				run_x = INF
			x += 1.0
		z += 1.0
	return out


static func is_blocked(p: Vector2) -> bool:
	return Zone.FOREST.has_point(p) and d_open(p) > EDGE


# ----------------------------------------------------------------- земля
const GROUND_SHADER := """
shader_type spatial;
uniform sampler2D mask : filter_linear, repeat_disable;
uniform vec4 m_rect;
uniform vec2 z_origin;
uniform float s_k = 2.0;
varying vec3 wpos;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) { float v = 0.0; float a = 0.5; for (int i = 0; i < 4; i++) { v += a * noise(p); p *= 2.03; a *= 0.5; } return v; }
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 l = vec2((wpos.x - z_origin.x) / s_k, (z_origin.y - wpos.z) / s_k);
	vec2 uv = (l - m_rect.xy) / m_rect.zw;
	vec4 m = texture(mask, uv);
	float n = fbm(wpos.xz * 0.35);
	float n2 = noise(wpos.xz * 2.3);
	// мох под деревьями, трава на полянах, утоптанная земля троп, песок логова
	vec3 moss = mix(vec3(0.035, 0.07, 0.035), vec3(0.08, 0.13, 0.06), n) * (0.85 + 0.25 * n2);
	vec3 grass = mix(vec3(0.13, 0.25, 0.08), vec3(0.24, 0.38, 0.12), n) * (0.88 + 0.2 * n2);
	vec3 dirt = mix(vec3(0.20, 0.14, 0.08), vec3(0.33, 0.24, 0.14), n) * (0.85 + 0.3 * n2);
	vec3 sand = mix(vec3(0.36, 0.27, 0.16), vec3(0.52, 0.40, 0.24), n) * (0.85 + 0.25 * n2);
	float crack = smoothstep(0.48, 0.5, abs(fbm(wpos.xz * 0.9 + 7.0) - 0.5) * 2.0 + 0.47);
	sand *= 1.0 - 0.45 * (1.0 - crack);
	vec3 c = mix(moss, grass, m.g);
	float pe = smoothstep(0.25, 0.75, m.r + (n - 0.5) * 0.5);
	c = mix(c, dirt, pe);
	c = mix(c, sand, smoothstep(0.2, 0.8, m.b + (n - 0.5) * 0.4));
	c *= 1.0 - 0.45 * m.a;
	ALBEDO = c;
	ROUGHNESS = 0.92;
	SPECULAR = 0.25;
}
"""


static func ground_material(z: Zone) -> ShaderMaterial:
	var f := Zone.FOREST_GROUND
	var w := int(f.size.x * MASK_PX)
	var h := int(f.size.y * MASK_PX)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var lair := clearing("gate")
	var lair_r := clearing_r("gate")
	for y in h:
		for x in w:
			var p := f.position + Vector2((x + 0.5) / MASK_PX, (y + 0.5) / MASK_PX)
			var dp := d_path(p)
			var path := 1.0 - smoothstep(PATH_W - 0.45, PATH_W + 0.05, dp)
			var gl := 0.0
			for c in CLEARINGS:
				var r: float = c[1]
				gl = maxf(gl, 1.0 - smoothstep(r - 1.2, r + 0.4, p.distance_to(c[0])))
			var sand := 1.0 - smoothstep(lair_r - 1.4, lair_r + 0.2, p.distance_to(lair))
			var shade := smoothstep(0.1, 1.6, d_open(p))
			if not Zone.FOREST.grow(0.3).has_point(p):
				shade = 1.0
			img.set_pixel(x, y, Color(path, gl, sand, shade))
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = GROUND_SHADER
	mat.shader = sh
	mat.set_shader_parameter("mask", ImageTexture.create_from_image(img))
	mat.set_shader_parameter("m_rect", Vector4(f.position.x, f.position.y, f.size.x, f.size.y))
	mat.set_shader_parameter("z_origin", Vector2(z.origin.x, z.origin.z))
	mat.set_shader_parameter("s_k", Zone.S)
	return mat


# ----------------------------------------------------------------- деревья, кусты, камни, руины
static func decorate(d: Decor, z: Zone) -> void:
	var rng := d.rng
	var f := Zone.FOREST_GROUND
	var fo := Zone.FOREST
	# стена деревьев по краю (как раньше, только гуще)
	var rows: Array = [
		[Vector2(f.position.x + 1.0, f.position.y + 1.2), Vector2(f.position.x + 1.0, f.end.y - 0.5)],
		[Vector2(f.end.x - 1.0, f.position.y + 1.2), Vector2(f.end.x - 1.0, f.end.y - 0.5)],
		[Vector2(f.position.x + 2.0, f.position.y + 1.2), Vector2(f.end.x - 2.0, f.position.y + 1.2)],
		[Vector2(f.position.x + 2.0, f.end.y - 0.5), Vector2(f.end.x - 2.0, f.end.y - 0.5)],
	]
	for row in rows:
		var a: Vector2 = row[0]
		var b: Vector2 = row[1]
		var n := int(a.distance_to(b) / 1.45)
		for k in n + 1:
			var lp: Vector2 = a.lerp(b, float(k) / n) + Vector2(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.3, 0.3))
			if d_open(lp) < 0.6:
				continue
			_tree(d, z, lp, rng, 1.0)
	# чаща: каждая клетка леса — дерево, под ним кусты и папоротник
	var gz := fo.position.y + 0.1
	while gz < fo.end.y:
		var gx := fo.position.x + 0.1
		while gx < fo.end.x:
			var lp := Vector2(gx + rng.randf() * 0.8, gz + rng.randf() * 0.8)
			gx += 0.95
			var dop := d_open(lp)
			if dop <= EDGE + 0.1:
				continue
			if dop > 0.75:
				_tree(d, z, lp, rng, 0.92 + minf(dop, 3.0) * 0.1)
			if rng.randf() < 0.55:
				var p := z.to_world(lp.x + rng.randf_range(-0.4, 0.4), lp.y + rng.randf_range(-0.4, 0.4))
				var r := rng.randf()
				if r < 0.45:
					d.add("Bush_Common_Flowers", p, INF, rng.randf_range(1.0, 1.4))
				elif r < 0.7:
					d.add("Fern_1", p, INF, rng.randf_range(0.9, 1.3))
				elif r < 0.85:
					d.add("Plant_1_Big", p, INF, rng.randf_range(0.8, 1.1))
				else:
					d.add("Mushroom_Laetiporus", p, INF, rng.randf_range(1.0, 1.5))
		gz += 0.95
	# кромка чащи у полян и троп: кусты, папоротник, цветы — мягкий переход
	gz = fo.position.y
	while gz < fo.end.y:
		var gx2 := fo.position.x
		while gx2 < fo.end.x:
			var lp := Vector2(gx2 + rng.randf() * 0.7, gz + rng.randf() * 0.7)
			gx2 += 0.7
			var dop := d_open(lp)
			if dop < -0.15 or dop > EDGE + 0.15 or rng.randf() < 0.35:
				continue
			var p := z.to_world(lp.x, lp.y)
			var r := rng.randf()
			if r < 0.35:
				d.add("Bush_Common_Flowers", p, INF, rng.randf_range(0.8, 1.15))
			elif r < 0.6:
				d.add("Fern_1", p, INF, rng.randf_range(0.8, 1.2))
			elif r < 0.85:
				d.add(d.pick(Decor.GRASS), p, INF, rng.randf_range(1.0, 1.5))
			else:
				d.add("Mushroom_Common", p, INF, rng.randf_range(0.9, 1.3))
		gz += 0.7
	# тропинки: камни-ступени и галька
	for pl: Array in PATHS:
		for i in pl.size() - 1:
			var a: Vector2 = pl[i]
			var b: Vector2 = pl[i + 1]
			var n := int(a.distance_to(b) / 0.8)
			for k in n:
				var lp: Vector2 = a.lerp(b, (k + rng.randf() * 0.5) / n)
				var side := (b - a).orthogonal().normalized() * rng.randf_range(-0.35, 0.35)
				var p := z.to_world(lp.x + side.x, lp.y + side.y) + Vector3(0, 0.03, 0)
				if rng.randf() < 0.38:
					d.add("RockPath_Round_Small_%d" % (1 + rng.randi() % 3), p, INF, rng.randf_range(0.85, 1.15))
				elif rng.randf() < 0.4:
					d.add("Pebble_Round_%d" % (1 + rng.randi() % 3), p, INF, rng.randf_range(1.2, 1.8))
	# поляны: трава и цветы
	for c in CLEARINGS:
		var cp: Vector2 = c[0]
		var r: float = c[1]
		var kind: String = c[2]
		if kind == "gate" or kind == "shrine":
			continue
		var cnt := int(r * r * 3.2)
		for k in cnt:
			var a := rng.randf() * TAU
			var rr := sqrt(rng.randf()) * (r - 0.3)
			var lp := cp + Vector2(cos(a), sin(a)) * rr
			if d_path(lp) < PATH_W * 0.8 or _near_keep(z, lp):
				continue
			var p := z.to_world(lp.x, lp.y) + Vector3(0, 0.02, 0)
			var t := rng.randf()
			if t < 0.55:
				d.add(d.pick(Decor.GRASS), p, INF, rng.randf_range(0.9, 1.4))
			elif t < 0.8 and kind == "entry":
				d.add(d.pick(Decor.FLOWERS), p, INF, rng.randf_range(0.8, 1.1))
			elif t < 0.9:
				d.add("Clover_%d" % (1 + rng.randi() % 2), p, INF, rng.randf_range(0.9, 1.2))
	_small_camp(d, z, rng)
	_medium_camp(d, z, rng)
	_shrine(d, z, rng)
	_ancient(d, z, rng)
	_lair(d, z, rng)


static func _near_keep(z: Zone, lp: Vector2) -> bool:
	for p in [z.pads[2].pos, z.pads[1].exit]:
		if lp.distance_to(z.to_local(p)) < 1.9:
			return true
	return false


## Камера смотрит с юга под углом: высокое дерево прямо «под» поляной или тропой закрыло бы их.
## Такие деревья ниже, а самые близкие к открытому месту заменяются кустами.
static func _shadow_k(lp: Vector2) -> float:
	if d_open(lp + Vector2(0, 1.4)) < EDGE:
		return 0.0
	if d_open(lp + Vector2(0, 2.6)) < EDGE:
		return 0.62
	if d_open(lp + Vector2(0, 3.8)) < EDGE:
		return 0.8
	return 1.0


static func _tree(d: Decor, z: Zone, lp: Vector2, rng: RandomNumberGenerator, k: float) -> void:
	var p := z.to_world(lp.x, lp.y)
	var sk := _shadow_k(lp)
	if sk <= 0.0:
		d.add("Bush_Common_Flowers", p, INF, rng.randf_range(1.1, 1.5))
		return
	k *= sk * 0.82
	var r := rng.randf()
	if r < 0.5:
		d.add(d.pick(Decor.COMMON), p, INF, rng.randf_range(0.9, 1.2) * k)
	elif r < 0.84:
		d.add(d.pick(Decor.PINES), p, INF, rng.randf_range(0.9, 1.2) * k)
	elif r < 0.95:
		d.add(d.pick(Decor.DEAD), p, INF, rng.randf_range(0.7, 0.95) * k)
	else:
		d.add(d.pick(Decor.ROCKS), p + Vector3(0, -0.3, 0), INF, rng.randf_range(0.9, 1.4))


static func _ring(d: Decor, z: Zone, c: Vector2, r: float, n: int, model: String, s0: float, s1: float, rng: RandomNumberGenerator,
		skip_dir := Vector2.ZERO, y := 0.0) -> void:
	for k in n:
		var a := TAU * k / n + rng.randf_range(-0.12, 0.12)
		var dir := Vector2(cos(a), sin(a))
		if skip_dir != Vector2.ZERO and dir.dot(skip_dir) > 0.82:
			continue
		var lp := c + dir * (r + rng.randf_range(-0.15, 0.15))
		d.add(model, z.to_world(lp.x, lp.y) + Vector3(0, y, 0), INF, rng.randf_range(s0, s1))


## Малый лагерь — звериная поляна: грибы кругом, пни-камни.
static func _small_camp(d: Decor, z: Zone, rng: RandomNumberGenerator) -> void:
	var c := clearing("small")
	_ring(d, z, c, 1.6, 9, "Mushroom_Common", 1.1, 1.6, rng)
	for k in 3:
		var lp := c + Vector2(rng.randf_range(-1.8, 1.8), rng.randf_range(-1.8, 1.8))
		if d_path(lp) > PATH_W:
			d.add(d.pick(Decor.ROCKS), z.to_world(lp.x, lp.y) + Vector3(0, -0.35, 0), INF, rng.randf_range(0.45, 0.7))


## Средний лагерь — стоянка охотников-отступников: забор, ящики, телега.
static func _medium_camp(d: Decor, z: Zone, rng: RandomNumberGenerator) -> void:
	var c := clearing("medium")
	d.add("Prop_Wagon", z.to_world(c.x + 1.7, c.y + 1.2), 0.9, 0.9)
	d.add("Prop_Crate", z.to_world(c.x + 2.1, c.y - 0.3), rng.randf() * TAU, 0.9)
	d.add("Prop_Crate", z.to_world(c.x + 1.6, c.y - 0.8), rng.randf() * TAU, 0.8)
	for k in 3:
		d.add("Prop_WoodenFence_Single", z.to_world(c.x - 1.9 + k * 0.95, c.y + 2.2), 0.05 * k, 1.0)
	d.add(d.pick(Decor.ROCKS), z.to_world(c.x - 2.0, c.y - 1.2) + Vector3(0, -0.3, 0), INF, 0.6)


## Святилище рун на развилке: круг каменных плит.
static func _shrine(d: Decor, z: Zone, rng: RandomNumberGenerator) -> void:
	var c := clearing("shrine")
	_ring(d, z, c, 1.25, 8, "RockPath_Round_Wide", 1.0, 1.15, rng, Vector2.ZERO, 0.03)
	d.add("RockPath_Square_Wide", z.to_world(c.x, c.y) + Vector3(0, 0.04, 0), 0.0, 1.5)
	# два клёна-момидзи у святилища — единственные красные деревья леса
	d.add(Decor.TWISTED[0], z.to_world(c.x - 3.2, c.y + 0.8), INF, 0.42)
	d.add(Decor.TWISTED[2], z.to_world(c.x + 3.3, c.y + 1.0), INF, 0.38)


## Древний лагерь — руины: арка, обломки стен, кирпичи.
static func _ancient(d: Decor, z: Zone, rng: RandomNumberGenerator) -> void:
	var c := clearing("big")
	d.add("Wall_Arch", z.to_world(c.x - 0.3, c.y + 2.2), 0.0, 1.0)
	d.add("Wall_UnevenBrick_Straight", z.to_world(c.x - 2.4, c.y + 1.2), PI * 0.5 + 0.15, 1.0)
	d.add("Wall_UnevenBrick_Window_Wide_Round", z.to_world(c.x + 1.9, c.y + 1.6), -0.35, 0.9)
	for k in 7:
		var lp := c + Vector2(rng.randf_range(-2.2, 2.2), rng.randf_range(-1.6, 2.0))
		d.add("Prop_Brick%d" % (1 + rng.randi() % 2), z.to_world(lp.x, lp.y), INF, rng.randf_range(0.9, 1.3))
	for k in 3:
		d.add("Prop_Vine%d" % (5 + rng.randi() % 2), z.to_world(c.x - 1.2 + k * 1.2, c.y + 2.1), INF, 1.0)
	_ring(d, z, c, 2.7, 10, "Pebble_Square_%d" % (1 + rng.randi() % 2), 1.4, 2.0, rng)


## Логово зверя: песчаная яма, кольцо валунов с проходом к тропе, мёртвые деревья.
static func _lair(d: Decor, z: Zone, rng: RandomNumberGenerator) -> void:
	var c := clearing("gate")
	var r := clearing_r("gate")
	var gate := (Vector2(3.6, 87.8) - c).normalized()
	_ring(d, z, c, r - 0.2, 14, "Rock_Medium_1", 1.0, 1.6, rng, gate, -0.45)
	_ring(d, z, c, r - 0.9, 9, "Pebble_Round_2", 1.6, 2.4, rng, gate)
	for k in 3:
		var a := PI * 0.3 + k * 0.9
		var lp := c + Vector2(cos(a), sin(a)) * (r + 0.4)
		d.add(d.pick(Decor.DEAD), z.to_world(lp.x, lp.y), INF, rng.randf_range(0.8, 1.05))


# ----------------------------------------------------------------- светлячки, лучи, туман, святилище
const SUN_SHADER := """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform vec4 col : source_color = vec4(1.0, 0.9, 0.55, 1.0);
uniform float power = 0.42;
varying vec3 wpos;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float r = length(UV - vec2(0.5)) * 2.0;
	float fall = 1.0 - smoothstep(0.3, 1.0, r);
	vec2 p = wpos.xz * 0.55 + vec2(TIME * 0.04, TIME * 0.025);
	float leaf = smoothstep(0.42, 0.68, noise(p) * 0.65 + noise(p * 2.6 + 3.0) * 0.35);
	ALBEDO = col.rgb * fall * (0.25 + 0.75 * leaf) * power;
}
"""

const FOG_SHADER := """
shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform vec4 col : source_color = vec4(0.62, 0.75, 0.62, 1.0);
uniform float amount = 0.32;
varying vec3 wpos;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = wpos.xz * 0.12 + vec2(TIME * 0.03, TIME * 0.015);
	float n = noise(p) * 0.6 + noise(p * 2.3 + 5.0) * 0.4;
	float edge = 1.0 - smoothstep(0.3, 0.5, length(UV - vec2(0.5)));
	ALBEDO = col.rgb;
	ALPHA = smoothstep(0.35, 0.8, n) * edge * amount;
}
"""

const GLOW_SHADER := """
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, shadows_disabled, fog_disabled;
uniform vec4 col : source_color = vec4(0.5, 0.9, 1.0, 1.0);
void vertex() { VERTEX.y += sin(TIME * 2.2) * 0.16; }
void fragment() {
	float f = pow(1.0 - abs(dot(NORMAL, VIEW)), 1.5);
	ALBEDO = col.rgb * (0.6 + 1.6 * (1.0 - f)) * (0.85 + 0.15 * sin(TIME * 3.0));
}
"""


static func _mat(code: String, params := {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var s := Shader.new()
	s.code = code
	m.shader = s
	for k in params:
		m.set_shader_parameter(k, params[k])
	return m


static func build_fx(root: Node3D, z: Zone) -> void:
	var fo := Zone.FOREST
	var center := z.to_world(fo.get_center().x, fo.get_center().y)
	# светлячки над чащей и полянами
	var ff := CPUParticles3D.new()
	ff.amount = 110
	ff.lifetime = 7.0
	ff.preprocess = 7.0
	ff.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	ff.emission_box_extents = Vector3(fo.size.x * Zone.S * 0.5, 1.2, fo.size.y * Zone.S * 0.5)
	ff.position = center + Vector3(0, 1.6, 0)
	ff.direction = Vector3(0, 1, 0)
	ff.spread = 180.0
	ff.gravity = Vector3.ZERO
	ff.initial_velocity_min = 0.15
	ff.initial_velocity_max = 0.5
	var qm := QuadMesh.new()
	qm.size = Vector2(0.16, 0.16)
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
	# солнечные пятна сквозь кроны на полянах и тропах (рисуются на земле, под травой)
	var sun_mat := _mat(SUN_SHADER)
	for c in CLEARINGS:
		var r0: float = c[1]
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2.ONE * (r0 * 2.0 + 1.4) * Zone.S
		mi.mesh = pm
		mi.material_override = sun_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = z.to_world(c[0].x, c[0].y) + Vector3(0, 0.05, 0)
		root.add_child(mi)
	# низкий туман в чаще
	var fog_mat := _mat(FOG_SHADER)
	for lp in [Vector2(-6.5, 74.0), Vector2(6.8, 75.0), Vector2(0.0, 77.0), Vector2(-6.5, 84.0), Vector2(6.8, 85.5),
			Vector2(0.0, 89.5), Vector2(-3.0, 93.5), Vector2(4.0, 93.8)]:
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(13.0, 13.0)
		mi.mesh = pm
		mi.material_override = fog_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = z.to_world(lp.x, lp.y) + Vector3(0, 0.7, 0)
		root.add_child(mi)
	# врата в общий лес: фиолетовый отсвет
	var lp2 := z.to_world(clearing("gate").x, clearing("gate").y)
	var ll := OmniLight3D.new()
	ll.light_color = Color(0.7, 0.45, 1.0)
	ll.light_energy = 2.2
	ll.omni_range = 11.0
	ll.position = lp2 + Vector3(0, 2.4, 0)
	root.add_child(ll)


static func _label(root: Node3D, pos: Vector3, text: String, col: Color) -> void:
	var lbl := Label3D.new()
	lbl.text = text
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.font_size = 48
	lbl.outline_size = 10
	lbl.modulate = col
	lbl.pixel_size = 0.012
	lbl.position = pos
	root.add_child(lbl)

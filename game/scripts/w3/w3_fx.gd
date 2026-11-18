class_name W3Fx
## Эффекты карты: модели на земле и на юнитах, молнии, замена отсутствующих моделей.

const ATTACH := {"origin": 0.0, "foot": 0.03, "feet": 0.03, "legs": 0.25, "chest": 0.55, "hand": 0.6,
	"weapon": 0.6, "head": 0.88, "overhead": 1.05, "sprite": 0.5, "rear": 0.4, "mount": 0.5}


## Сколько одинаковых эффектов может быть в сцене одновременно (больше — не видно разницы, а кадр тяжелеет)
const SAME_FX_MAX := 14


## Эффект не создаётся: далеко от камеры (на другом острове никто не смотрит) или таких уже слишком много.
static func skip_fx(path: String, pos: Vector3) -> bool:
	if Game.I == null or Game.I.sim:
		return false
	var dx := pos.x - W3Model.cam_pos.x
	var dz := pos.z - W3Model.cam_pos.z
	if dx * dx + dz * dz > W3Model.cam_r2:
		return true
	return W3Model.live_count(W3Model.norm_key(path)) >= SAME_FX_MAX


static func _empty(rt: W3Runtime, path: String, pos: Vector3) -> W3Model:
	var m := W3Model.new()
	m.key = W3Model.norm_key(path)
	m.fallback = true
	m.skipped = true
	if rt.fx_parent:
		rt.fx_parent.add_child(m)
	m.global_position = pos
	return m


static func at(rt: W3Runtime, path: String, pos: Vector3) -> W3Model:
	if skip_fx(path, pos):
		return _empty(rt, path, pos)
	var m := W3Model.create(path, true)
	if rt.fx_parent:
		rt.fx_parent.add_child(m)
	m.global_position = pos
	m.scale = Vector3.ONE * W3Runtime.FX_K
	if m.fallback and not m.skipped:
		fallback_fx(rt, path, pos, W3Runtime.FX_K)
	return m


static func unit_height(u: Unit) -> float:
	if u is W3Unit and (u as W3Unit).w3m:
		return 1.2 * (u as W3Unit).base_scale / W3Runtime.FX_K
	return maxf(1.0, u.bar_height - 0.35)


static func on_unit(rt: W3Runtime, path: String, u: Unit, attach: String) -> W3Model:
	if skip_fx(path, u.global_position):
		return _empty(rt, path, u.global_position)
	var m := W3Model.create(path, true)
	if rt.fx_parent:
		rt.fx_parent.add_child(m)
	var h := unit_height(u)
	var a := attach.to_lower().strip_edges()
	var k := 0.0
	for w in a.split(" ", false):
		if ATTACH.has(w):
			k = maxf(k, float(ATTACH[w]))
	m.follow = u
	m.follow_off = Vector3(0, h * k, 0)
	m.global_position = u.global_position + m.follow_off
	# на юните — в пропорции к юниту (герои в игре меньше, чем в WC3)
	var s := W3Runtime.FX_K * (0.6 if u is Hero else 1.0)
	if u is W3Unit:
		s = (u as W3Unit).base_scale if (u as W3Unit).w3m else W3Runtime.FX_K * 0.6
	m.scale = Vector3.ONE * s
	if m.fallback and not m.skipped:
		fallback_fx(rt, path, m.global_position, s)
	return m


## Модели нет (стандартная модель Warcraft не извлечена) — похожий эффект из средств игры.
static func fallback_fx(rt: W3Runtime, path: String, pos: Vector3, s: float) -> void:
	var p := path.to_lower()
	if p == "" or p.ends_with("dummy.mdl") or p.ends_with("dummy.mdx") or p == "_" or rt.fx_parent == null:
		return
	if Game.I and Game.I.sim:
		return
	var parent := rt.fx_parent
	var r := 0.6 * s
	var col := Color(1.0, 0.95, 0.85)
	if p.contains("fire") or p.contains("flame") or p.contains("immolat") or p.contains("burn") or p.contains("volcano"):
		col = Color(1.0, 0.5, 0.15)
	elif p.contains("frost") or p.contains("ice") or p.contains("blizzard") or p.contains("freez") or p.contains("cold"):
		col = Color(0.55, 0.85, 1.0)
	elif p.contains("blood") or p.contains("red"):
		col = Color(0.9, 0.1, 0.12)
	elif p.contains("lightning") or p.contains("bolt") or p.contains("thunder") or p.contains("monsoon"):
		col = Color(0.6, 0.8, 1.0)
	elif p.contains("heal") or p.contains("rejuv") or p.contains("tranquil"):
		col = Color(0.4, 1.0, 0.5)
	elif p.contains("holy") or p.contains("light") or p.contains("resurrect") or p.contains("divine"):
		col = Color(1.0, 0.9, 0.45)
	elif p.contains("dark") or p.contains("death") or p.contains("shadow") or p.contains("black") or p.contains("doom"):
		col = Color(0.55, 0.2, 0.75)
	elif p.contains("poison") or p.contains("acid"):
		col = Color(0.4, 0.9, 0.2)
	if p.contains("stomp") or p.contains("clap") or p.contains("nova") or p.contains("shockwave") or p.contains("explo") \
			or p.contains("impact") or p.contains("blast"):
		Fx.ring_burst(parent, pos + Vector3(0, 0.15, 0), maxf(1.5, r * 2.5), col, 0.5, 0.5)
		Fx.burst(parent, pos + Vector3(0, 0.6, 0), col, 18, 6.0, 0.3, 0.5)
	elif p.contains("missile"):
		Fx.burst(parent, pos + Vector3(0, 0.8, 0), col, 6, 2.0, 0.25, 0.3)
	elif p.contains("caster") or p.contains("target") or p.contains("special"):
		Fx.burst(parent, pos + Vector3(0, 0.8, 0), col, 14, 3.5, 0.25, 0.5)
		Fx.pillar(parent, pos, 0.6, 2.4, col, 0.45)
	else:
		Fx.burst(parent, pos + Vector3(0, 0.6, 0), col, 12, 3.0, 0.25, 0.45)


# ------------------------------------------------------------------ молнии
const LIGHTNING_COLORS := {"CLPB": Color(0.55, 0.75, 1.0), "CLSB": Color(0.55, 0.75, 1.0), "DRAB": Color(0.4, 0.6, 1.0),
	"DRAL": Color(1.0, 0.25, 0.25), "DRAM": Color(0.4, 0.5, 1.0), "AFOD": Color(0.6, 0.1, 0.15),
	"FORK": Color(0.6, 0.8, 1.0), "HWPB": Color(0.4, 1.0, 0.5), "HWSB": Color(0.4, 1.0, 0.5),
	"CHIM": Color(0.5, 0.7, 1.0), "LEAS": Color(0.9, 0.9, 0.6), "MBUR": Color(0.5, 0.4, 1.0),
	"MFPB": Color(0.6, 0.5, 1.0), "SPLK": Color(0.6, 0.6, 1.0)}


class Bolt:
	extends Node3D
	var a := Vector3.ZERO
	var b := Vector3.ZERO
	var col := Color(0.6, 0.8, 1.0)
	var im := ImmediateMesh.new()
	var mi := MeshInstance3D.new()
	var t := 0.0

	func _ready() -> void:
		mi.mesh = im
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.vertex_color_use_as_albedo = true
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		mi.material_override = m
		mi.top_level = true
		mi.extra_cull_margin = 50.0
		add_child(mi)
		mi.global_transform = Transform3D.IDENTITY
		_build()

	func _process(delta: float) -> void:
		t += delta
		if t > 0.05:
			t = 0.0
			_build()

	func _build() -> void:
		im.clear_surfaces()
		var d := b - a
		var len := d.length()
		if len < 0.01:
			return
		var cam := get_viewport().get_camera_3d()
		var view := (cam.global_position - (a + b) * 0.5).normalized() if cam else Vector3.UP
		var side := d.cross(view).normalized()
		var n := clampi(int(len / 0.6), 3, 40)
		for pass_i in 2:
			var w := 0.18 if pass_i == 0 else 0.06
			var c := Color(col.r, col.g, col.b, col.a * (0.55 if pass_i == 0 else 1.0))
			if pass_i == 1:
				c = c.lightened(0.6)
			im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
			var jit := 0.25
			for i in n + 1:
				var k := float(i) / float(n)
				var off := Vector3.ZERO
				if i > 0 and i < n:
					off = side * randf_range(-jit, jit) + Vector3.UP * randf_range(-jit, jit) * 0.5
				var p := a.lerp(b, k) + off
				im.surface_set_color(c)
				im.surface_add_vertex(p + side * w)
				im.surface_set_color(c)
				im.surface_add_vertex(p - side * w)
			im.surface_end()


static func lightning(rt: W3Runtime, code: String, a: Vector3, b: Vector3) -> Node3D:
	var l := Bolt.new()
	l.a = a
	l.b = b
	l.col = LIGHTNING_COLORS.get(code.to_upper(), Color(0.6, 0.8, 1.0))
	if rt.fx_parent:
		rt.fx_parent.add_child(l)
	return l


static func move_lightning(l: Node3D, a: Vector3, b: Vector3) -> void:
	if l is Bolt:
		(l as Bolt).a = a
		(l as Bolt).b = b


static func color_lightning(l: Node3D, c: Color) -> void:
	if l is Bolt:
		(l as Bolt).col = c


# ------------------------------------------------------------------ снаряд способности
class Missile:
	extends Node3D
	var rt: W3Runtime
	var target: Unit
	var goal := Vector3.ZERO
	var speed := 15.0
	var arc := 0.0
	var on_hit: Callable
	var model: W3Model
	var start := Vector3.ZERO
	var travelled := 0.0

	func _physics_process(delta: float) -> void:
		var tp := goal
		if target and is_instance_valid(target) and target.alive:
			tp = target.global_position + Vector3(0, 1.0, 0)
		var to := tp - global_position
		var step := speed * delta
		if to.length() <= step + 0.2:
			global_position = tp
			if on_hit.is_valid():
				on_hit.call()
			if model and is_instance_valid(model):
				model.destroy_fx()
				var gp := model.global_transform
				remove_child(model)
				rt.fx_parent.add_child(model)
				model.global_transform = gp
			queue_free()
			return
		global_position += to.normalized() * step
		look_at(tp, Vector3.UP, true)


static func missile(rt: W3Runtime, art: String, from: Vector3, target: Unit, goal: Vector3, speed_w3: float,
		on_hit: Callable) -> void:
	var m := Missile.new()
	m.rt = rt
	m.target = target
	m.goal = goal
	m.speed = maxf(speed_w3, 300.0) * W3Runtime.U
	m.on_hit = on_hit
	if rt.fx_parent:
		rt.fx_parent.add_child(m)
	m.global_position = from
	if art != "":
		# снаряд далеко от камеры — без модели; модель ещё не загружена — шарик, а модель догрузится в фоне
		var far := skip_fx(art, from) and Game.I and W3Model.live_count(W3Model.norm_key(art)) < SAME_FX_MAX
		var mdl := W3Model.new() if far else W3Model.create(art, true)
		if far:
			mdl.fallback = true
			mdl.skipped = true
		m.add_child(mdl)
		mdl.scale = Vector3.ONE * W3Runtime.FX_K * 0.8
		mdl.rotation.y = PI
		m.model = mdl
		if mdl.fallback and not far and Game.I and not Game.I.sim:
			var orb := Fx.add_mesh(m, SphereMesh.new(), Fx.glow_mat(Color(0.8, 0.85, 1.0), 2.0, true))
			orb.scale = Vector3.ONE * 0.35

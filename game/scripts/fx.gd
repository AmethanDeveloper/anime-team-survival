class_name Fx
## Визуальные эффекты: снаряды, вспышки, кольца, частицы. Всё строится кодом.


## Узел, который каждый кадр вызывает tick(node, delta). Если tick вернул false — узел удаляется.
class FxNode extends Node3D:
	var tick: Callable
	var life := 10.0
	var t := 0.0
	var data := {}

	func _process(delta: float) -> void:
		if Game.I and Game.I.time_stop_left > 0.0 and data.get("owner") != Game.I.time_stop_owner:
			return
		t += delta
		life -= delta
		var keep := true
		if tick.is_valid():
			keep = tick.call(self, delta)
		if not keep or life <= 0.0:
			queue_free()


static var _mat_cache := {}


const ENERGY_K := 0.45


static func glow_mat(color: Color, energy := 2.0, additive := false, alpha := 0.9) -> StandardMaterial3D:
	var key := "%s|%s|%s|%s" % [color.to_html(), energy, additive, alpha]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy * ENERGY_K
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	_mat_cache[key] = m
	return m


## Отдельный (не кешированный) материал — для плавного исчезновения.
static func fade_mat(color: Color, energy := 2.0, additive := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy * ENERGY_K
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func flat_ring_mesh(inner: float, outer: float, segments := 48) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in segments:
		var a0 := TAU * i / segments
		var a1 := TAU * (i + 1) / segments
		var p0 := Vector3(cos(a0), 0, sin(a0))
		var p1 := Vector3(cos(a1), 0, sin(a1))
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(0, 0)); st.add_vertex(p0 * inner)
		st.set_uv(Vector2(1, 0)); st.add_vertex(p0 * outer)
		st.set_uv(Vector2(1, 1)); st.add_vertex(p1 * outer)
		st.set_uv(Vector2(0, 0)); st.add_vertex(p0 * inner)
		st.set_uv(Vector2(1, 1)); st.add_vertex(p1 * outer)
		st.set_uv(Vector2(0, 1)); st.add_vertex(p1 * inner)
	return st.commit()


static func disc_mesh(radius: float, segments := 40) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in segments:
		var a0 := TAU * i / segments
		var a1 := TAU * (i + 1) / segments
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(Vector3(cos(a0), 0, sin(a0)) * radius)
		st.add_vertex(Vector3(cos(a1), 0, sin(a1)) * radius)
	return st.commit()


## Серп (полумесяц) в плоскости XZ, выпуклостью вперёд (+Z).
static func crescent_mesh(width: float, depth: float, segments := 18) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var outer: Array[Vector3] = []
	var inner: Array[Vector3] = []
	for i in segments + 1:
		var u := float(i) / segments
		var a := lerpf(-PI * 0.42, PI * 0.42, u)
		var thick := sin(u * PI)
		outer.append(Vector3(sin(a) * width * 0.5, 0, cos(a) * depth))
		inner.append(Vector3(sin(a) * width * 0.45, 0, cos(a) * depth - thick * depth * 0.55))
	for i in segments:
		st.set_normal(Vector3.UP)
		st.add_vertex(inner[i]); st.add_vertex(outer[i]); st.add_vertex(outer[i + 1])
		st.add_vertex(inner[i]); st.add_vertex(outer[i + 1]); st.add_vertex(inner[i + 1])
	return st.commit()


static func star_mesh(radius: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 4:
		var a := TAU * i / 4.0
		var tip := Vector3(cos(a), 0, sin(a)) * radius
		var l := Vector3(cos(a + 0.5), 0, sin(a + 0.5)) * radius * 0.28
		var r := Vector3(cos(a - 0.5), 0, sin(a - 0.5)) * radius * 0.28
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3.ZERO); st.add_vertex(r); st.add_vertex(tip)
		st.add_vertex(Vector3.ZERO); st.add_vertex(tip); st.add_vertex(l)
	return st.commit()


static func spawn(parent: Node, pos: Vector3, life: float, tick: Callable) -> FxNode:
	var n := FxNode.new()
	n.life = life
	n.tick = tick
	parent.add_child(n)
	n.global_position = pos
	return n


static func add_mesh(n: Node3D, mesh: Mesh, mat: Material, offset := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = offset
	n.add_child(mi)
	return mi


## Расширяющееся кольцо по земле.
static func ring_burst(parent: Node, pos: Vector3, radius: float, color: Color, time := 0.45, thickness := 0.35) -> void:
	var m := fade_mat(color, 3.0)
	var n := spawn(parent, pos + Vector3(0, 0.12, 0), time, func(node: FxNode, _d: float) -> bool:
		var k := node.t / time
		node.scale = Vector3.ONE * lerpf(0.25, 1.0, ease(k, 0.4))
		m.albedo_color.a = 1.0 - k
		return true)
	add_mesh(n, flat_ring_mesh(radius - thickness, radius), m)


## Вспышка частиц.
static func burst(parent: Node, pos: Vector3, color: Color, amount := 24, speed := 6.0, size := 0.25, life := 0.6) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = amount
	p.lifetime = life
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -6, 0)
	p.scale_amount_min = size * 0.5
	p.scale_amount_max = size
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 6
	sm.rings = 3
	p.mesh = sm
	p.material_override = glow_mat(color, 3.0)
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	var tw := p.create_tween()
	tw.tween_interval(life + 0.2)
	tw.tween_callback(p.queue_free)


## Столб света/огня, растущий из земли.
static func pillar(parent: Node, pos: Vector3, radius: float, height: float, color: Color, time := 0.7) -> void:
	var m := fade_mat(color, 3.5)
	var n := spawn(parent, pos, time, func(node: FxNode, _d: float) -> bool:
		var k := node.t / time
		node.scale = Vector3(lerpf(0.4, 1.0, ease(k, 0.3)), lerpf(0.1, 1.0, ease(k, 0.2)), lerpf(0.4, 1.0, ease(k, 0.3)))
		m.albedo_color.a = clampf((1.0 - k) * 1.1, 0.0, 0.75)
		return true)
	var cm := CylinderMesh.new()
	cm.top_radius = radius * 0.6
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 16
	cm.cap_top = false
	cm.cap_bottom = false
	add_mesh(n, cm, m, Vector3(0, height / 2.0, 0))


## Круг-предупреждение на земле перед ударом.
static func telegraph(parent: Node, pos: Vector3, radius: float, color: Color, time: float) -> void:
	var m := fade_mat(color, 1.5)
	var mf := fade_mat(color, 0.8)
	var n := spawn(parent, pos + Vector3(0, 0.08, 0), time, func(node: FxNode, _d: float) -> bool:
		var k := node.t / time
		m.albedo_color.a = 0.9
		mf.albedo_color.a = 0.08 + 0.25 * k
		(node.get_child(1) as Node3D).scale = Vector3.ONE * maxf(k, 0.01)
		return true)
	add_mesh(n, flat_ring_mesh(radius - 0.18, radius), m)
	add_mesh(n, disc_mesh(radius), mf)


## Послеобраз героя (для рывков).
static func afterimage(parent: Node, pos: Vector3, yaw: float, color: Color) -> void:
	var m := fade_mat(color, 1.6)
	var n := spawn(parent, pos, 0.45, func(node: FxNode, _d: float) -> bool:
		m.albedo_color.a = 0.55 * (1.0 - node.t / 0.45)
		return true)
	n.rotation.y = yaw
	var cap := CapsuleMesh.new()
	cap.radius = 0.38
	cap.height = 2.2
	add_mesh(n, cap, m, Vector3(0, 1.15, 0))


## Всплывающая цифра урона — рисуется в HUD.
static func number(pos: Vector3, text: String, color: Color, big := false) -> void:
	if Game.I and Game.I.hud:
		Game.I.hud.add_float_text(pos, text, color, big)


## Маркер приказа «идти сюда» (как зелёная стрелка в WC3).
static func order_marker(parent: Node, pos: Vector3, color: Color) -> void:
	var m := fade_mat(color, 2.0)
	var n := spawn(parent, pos + Vector3(0, 0.1, 0), 0.5, func(node: FxNode, _d: float) -> bool:
		var k := node.t / 0.5
		node.scale = Vector3.ONE * lerpf(1.0, 0.3, k)
		m.albedo_color.a = 1.0 - k
		return true)
	add_mesh(n, flat_ring_mesh(0.55, 0.8, 24), m)
	add_mesh(n, flat_ring_mesh(0.0, 0.18, 12), m)

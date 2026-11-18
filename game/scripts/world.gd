class_name World
## Строит карту: три острова команд (лагерь + лес + линия), арену в центре, воду, свет и декор.
## Стиль — по мотивам карты: ледяной грунт с тёмными разводами, низкие тёмные стены, красные кристаллы,
## заснеженные сосны, японский Дом выживания, золотые обелиск и пагода.

const TERRAIN_SHADER := """
shader_type spatial;
uniform vec3 base_a : source_color = vec3(0.80, 0.87, 0.93);
uniform vec3 base_b : source_color = vec3(0.58, 0.72, 0.84);
uniform vec3 dark : source_color = vec3(0.05, 0.07, 0.10);
uniform float dark_amount = 1.0;
uniform float blot_scale = 0.09;
uniform vec3 rock_a : source_color = vec3(0.30, 0.32, 0.38);
uniform vec3 rock_b : source_color = vec3(0.15, 0.16, 0.20);
varying vec3 wpos;
varying vec3 wnorm;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) { float v = 0.0; float a = 0.5; for (int i = 0; i < 5; i++) { v += a * noise(p); p *= 2.07; a *= 0.5; } return v; }
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	float top = smoothstep(0.55, 0.85, wnorm.y);
	float n = fbm(wpos.xz * blot_scale);
	float n2 = noise(wpos.xz * 1.7);
	float n3 = fbm(wpos.xz * 0.6 + 11.0);
	vec3 g = mix(base_b, base_a, n3) * (0.92 + 0.12 * n2);
	float blot = smoothstep(0.50, 0.535, n * 0.8 + n3 * 0.3);
	float rim = smoothstep(0.47, 0.50, n * 0.8 + n3 * 0.3) - blot;
	g = mix(g, dark * (0.8 + 0.5 * n2), blot * dark_amount);
	g = mix(g, g * 0.55, rim * dark_amount * 0.8);
	float strata = sin(wpos.y * 5.0 + n * 6.0) * 0.5 + 0.5;
	vec3 r = mix(rock_b, rock_a, strata * 0.55 + n * 0.45);
	ALBEDO = mix(r, g, top);
	ROUGHNESS = mix(0.95, 0.55, top * (1.0 - blot));
	SPECULAR = 0.35;
}
"""

const PATH_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec3 path_a : source_color = vec3(0.07, 0.08, 0.11);
uniform vec3 path_b : source_color = vec3(0.03, 0.04, 0.06);
varying vec3 wpos;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float n = noise(wpos.xz * 0.45) * 0.6 + noise(wpos.xz * 2.2) * 0.4;
	float edge = 1.0 - abs(UV.x - 0.5) * 2.0;
	ALBEDO = mix(path_b, path_a, n);
	ROUGHNESS = 0.6;
	SPECULAR = 0.4;
	ALPHA = edge;
	ALPHA_SCISSOR_THRESHOLD = 0.2 + n * 0.45;
}
"""

const WATER_SHADER := """
shader_type spatial;
render_mode specular_schlick_ggx;
uniform vec3 deep : source_color = vec3(0.02, 0.05, 0.12);
uniform vec3 shallow : source_color = vec3(0.05, 0.18, 0.30);
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float t = TIME;
	float w = sin(wpos.x * 0.31 + t * 1.1) * 0.5 + sin(wpos.z * 0.27 - t * 0.9) * 0.5 + sin((wpos.x + wpos.z) * 0.63 + t * 1.7) * 0.25;
	float d = clamp(length(wpos.xz) / 170.0, 0.0, 1.0);
	ALBEDO = mix(shallow, deep, d * 0.7 + 0.15 + 0.08 * w);
	vec3 n = normalize(vec3(cos(wpos.x * 0.31 + t * 1.1) * 0.12 + cos((wpos.x + wpos.z) * 0.63 + t * 1.7) * 0.08,
		1.0, cos(wpos.z * 0.27 - t * 0.9) * 0.12));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	ROUGHNESS = 0.06;
	SPECULAR = 0.7;
	METALLIC = 0.1;
}
"""

static var props_scene: Node3D = null
static var g_env: Environment = null


static func prop(name: String) -> Node3D:
	if name == "SpawnGate":
		return load("res://assets/approved_portal/spawn_portal.gd").make()
	if name == "Portal":
		return load("res://assets/visual_refresh/visual_props.gd").portal()
	if props_scene == null:
		props_scene = (load("res://models/props.glb") as PackedScene).instantiate()
	var src := props_scene.get_node_or_null(name) as Node3D
	if src == null:
		push_warning("Нет пропа " + name)
		return Node3D.new()
	var n := src.duplicate() as Node3D
	n.transform = Transform3D.IDENTITY
	if name == "LowWall":
		load("res://assets/approved_materials/materials.gd").apply_wall(n)
	if name in ["Crystal", "Tower"]:
		load("res://assets/visual_refresh/visual_props.gd").decorate(n, name)
	return n


static func recolor(n: Node, mat_name: String, color: Color, energy := 1.5) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var m := mi.get_active_material(s)
			if m and m.resource_name == mat_name:
				if m is ShaderMaterial:
					var sm := m.duplicate() as ShaderMaterial
					sm.set_shader_parameter("tint", color)
					sm.set_shader_parameter("energy", energy)
					if mi.material_override != null:
						mi.material_override = sm
					else:
						mi.set_surface_override_material(s, sm)
					continue
				var nm := (m as StandardMaterial3D).duplicate() as StandardMaterial3D
				nm.albedo_color = color
				nm.emission_enabled = true
				nm.emission = color
				nm.emission_energy_multiplier = energy
				if mi.material_override != null:
					mi.material_override = nm
				else:
					mi.set_surface_override_material(s, nm)
	for c in n.get_children():
		recolor(c, mat_name, color, energy)


static func shader_mat(code: String) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = code
	var m := ShaderMaterial.new()
	m.shader = sh
	return m


static func build(game: Node3D) -> void:
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.20, 0.27, 0.45)
	sm.sky_horizon_color = Color(0.62, 0.70, 0.82)
	sm.ground_horizon_color = Color(0.45, 0.52, 0.62)
	sm.ground_bottom_color = Color(0.08, 0.12, 0.2)
	sm.sun_angle_max = 20.0
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.95
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.ssao_enabled = true
	env.ssao_radius = 1.5
	env.ssao_intensity = 1.2
	env.fog_enabled = true
	env.fog_light_color = Color(0.6, 0.68, 0.8)
	env.fog_density = 0.0016
	env.fog_sky_affect = 0.3
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.0
	env.adjustment_contrast = 1.05
	env_node.environment = env
	game.add_child(env_node)
	g_env = env

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
	sun.light_color = Color(1.0, 0.93, 0.81)
	sun.light_energy = 1.05
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 140.0
	sun.directional_shadow_blend_splits = true
	game.add_child(sun)

	var water := MeshInstance3D.new()
	var wm := PlaneMesh.new()
	wm.size = Vector2(1000, 1000)
	water.mesh = wm
	water.material_override = shader_mat(WATER_SHADER)
	water.position = Vector3(0, -1.6, 0)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	game.add_child(water)

	var ice := ShaderMaterial.new()
	ice.shader = load("res://assets/visual_refresh/terrain.gdshader")
	load("res://assets/approved_materials/materials.gd").soil_maps(ice)
	var forest := ice.duplicate() as ShaderMaterial
	var path_mat := ShaderMaterial.new()
	path_mat.shader = load("res://assets/visual_refresh/path.gdshader")
	load("res://assets/approved_materials/materials.gd").soil_maps(path_mat)

	var g: Game = game
	var decor := Decor.new()
	decor.rng.seed = 4242
	for z: Zone in g.zones:
		_build_zone(g, z, ice, forest, path_mat)
		decor.island(z)
	if g.arena:
		g.arena.decorate(decor)
	if g.wild:
		g.wild.decorate(decor)
	_islets(g, decor, ice)
	var droot := Node3D.new()
	droot.name = "Decor"
	game.add_child(droot)
	decor.build(droot)


## Островки в проливах и вокруг карты: скалы, сосны, иногда клён.
static func _islets(g: Game, d: Decor, ice: Material) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var root := Node3D.new()
	root.name = "Islets"
	g.add_child(root)
	var placed: Array[Vector3] = []
	var tries := 0
	while placed.size() < 26 and tries < 600:
		tries += 1
		var p := Vector3(rng.randf_range(-300.0, 300.0), 0.0, rng.randf_range(-280.0, 170.0))
		var r := rng.randf_range(5.0, 11.0)
		var bad := Vector2(p.x - Arena.CENTER.x, p.z - Arena.CENTER.z).length() < Arena.R + 22.0 + r
		for z: Zone in g.zones:
			var l := z.to_local(p)
			if Decor.LAND.grow(6.0 + r / Zone.S).has_point(l) or Rect2(-33.0, 40.0, 66.0, 16.0).grow(r / Zone.S + 4.0).has_point(l):
				bad = true
		for q in placed:
			if Vector2(p.x - q.x, p.z - q.z).length() < r + q.y + 10.0:
				bad = true
		if bad:
			continue
		placed.append(Vector3(p.x, r, p.z))
		var base := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = r
		cm.bottom_radius = r * 1.25
		cm.height = 3.0
		cm.radial_segments = 9
		cm.rings = 1
		base.mesh = cm
		base.material_override = ice
		base.position = p + Vector3(0, -1.6, 0)
		base.rotation.y = rng.randf() * TAU
		root.add_child(base)
		var top := p + Vector3(0, -0.1, 0)
		for k in int(r / 2.2):
			var a := rng.randf() * TAU
			var q := top + Vector3(cos(a), 0, sin(a)) * r * rng.randf_range(0.75, 1.05) + Vector3(0, -0.6, 0)
			d.add(d.pick(Decor.ROCKS), q, INF, rng.randf_range(1.2, 2.2), 0.75)
		var trees := int(r / 3.0) + 1
		for k in trees:
			var a := rng.randf() * TAU
			var q := top + Vector3(cos(a), 0, sin(a)) * r * rng.randf_range(0.0, 0.55)
			if k == 0 and rng.randf() < 0.3:
				d.add(d.pick(Decor.TWISTED), q, INF, rng.randf_range(0.55, 0.7), 0.45)
			else:
				d.add(d.pick(Decor.PINES) if rng.randf() < 0.8 else d.pick(Decor.DEAD), q, INF, rng.randf_range(0.8, 1.3),
					rng.randf_range(0.6, 0.85))


static func _box(root: Node3D, z: Zone, rect: Rect2, top: float, mat: Material, depth := 10.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(rect.size.x * Zone.S, depth, rect.size.y * Zone.S)
	mi.mesh = bm
	mi.material_override = mat
	var c := rect.get_center()
	mi.position = z.to_world(c.x, c.y) + Vector3(0, top - depth / 2.0, 0)
	mi.rotation.y = z.facing_inward()
	root.add_child(mi)
	return mi


static func _place(root: Node3D, z: Zone, name: String, lx: float, lz: float, rot := 0.0, s := 1.0) -> Node3D:
	var n := prop(name)
	n.position = z.to_world_h(lx, lz)
	n.rotation.y = z.facing_inward() + rot
	n.scale = Vector3.ONE * s
	root.add_child(n)
	return n


## Ряд низких стен вдоль отрезка (локальные координаты), с красными кристаллами на концах.
static func _wall_line(root: Node3D, z: Zone, a: Vector2, b: Vector2, crystals := true) -> void:
	var d := b - a
	var len_m := d.length() * Zone.S
	var n := maxi(1, int(round(len_m / 4.0)))
	var along_x := absf(d.x) > absf(d.y)
	for i in n:
		var p := a + d * ((i + 0.5) / n)
		var w := _place(root, z, "LowWall", p.x, p.y, (0.0 if along_x else PI * 0.5))
		w.scale = Vector3(len_m / n / 4.0 * 1.02, 1.0, 1.0)
	if crystals:
		for p in [a, b]:
			_place(root, z, "RedCrystal", p.x, p.y, randf() * TAU, 0.9)


static func _light(root: Node3D, pos: Vector3, col: Color, energy: float, rng_m: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng_m
	l.position = pos
	root.add_child(l)


static func _build_zone(g: Game, z: Zone, ice: ShaderMaterial, forest: ShaderMaterial, path_mat: ShaderMaterial) -> void:
	var team_col: Color = Data.TEAM_COLORS[z.index]
	var root := Node3D.new()
	root.name = "Zone%d" % z.index
	g.add_child(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + z.index * 17

	# вся земля острова (вне троп — лес, скалы и дома деревни, см. Decor)
	_box(root, z, Decor.LAND, -0.03, ice, 10.0)
	# земля: тропы, лагерь, центр; плато поднято, к нему ведёт лестница
	for r: Rect2 in Zone.WALK:
		if r.size.x > 20.0 and r.position.y > 40.0 and r.position.y < 50.0:
			continue  # плато строим отдельно
		_box(root, z, r, 0.0, ice)
	for side: float in [-1.0, 1.0]:
		var x_in: float = Zone.RAMP_X1 if side > 0 else -Zone.RAMP_X1
		var x_out: float = 31.0 * side
		var x_c: float = 5.0 * side
		var pz := Zone.PLAT_Z0
		var ph := Zone.PLAT_Z1 - Zone.PLAT_Z0
		# пол у центра (до лестницы)
		_box(root, z, Rect2(minf(x_c, x_in), pz, absf(x_in - x_c), ph), 0.0, ice)
		# плато
		_box(root, z, Rect2(minf(x_in, x_out), pz, absf(x_out - x_in), ph), Zone.PLATEAU_H, ice)
		# лестница
		var steps := 8
		var sw := (Zone.RAMP_X1 - Zone.RAMP_X0) / steps
		for k in steps:
			var xa: float = (Zone.RAMP_X0 + k * sw) * side
			var top := Zone.PLATEAU_H * (k + 0.6) / float(steps)
			_box(root, z, Rect2(minf(xa, xa + sw * side), pz + 0.6, sw, ph - 1.2), top, preload("res://assets/approved_materials/materials.gd").wall_material(), top + 0.02)
		# перила лестницы и стены по краю плато
		_wall_line(root, z, Vector2(side * 19.5, pz + 0.3), Vector2(side * 30.5, pz + 0.3))
		_wall_line(root, z, Vector2(side * 19.5, Zone.PLAT_Z1 - 0.3), Vector2(side * 30.5, Zone.PLAT_Z1 - 0.3))
		for zz in [pz + 0.9, Zone.PLAT_Z1 - 0.9]:
			var ln := _place(root, z, "Lantern", side * 8.4, zz, 0.0, 1.0)
			_light(root, ln.position + Vector3(0, 2.0, 0), Color(1.0, 0.75, 0.45), 1.2, 6.0)
		var br := _place(root, z, "Brazier", side * 30.0, pz + 1.6)
		_light(root, br.position + Vector3(0, 2.0, 0), Color(1.0, 0.6, 0.3), 1.6, 8.0)

	# низкие стены с красными кристаллами по внешнему краю троп (за ними — лес и дома)
	for side in [-1.0, 1.0]:
		for seg in [[-4.0, 38.0], [55.0, 96.0]]:
			_wall_line(root, z, Vector2(side * 17.8, seg[0] + 0.5), Vector2(side * 17.8, seg[1] - 0.5))

	# тропы монстров
	for li in 2:
		var lane := MeshInstance3D.new()
		lane.mesh = _ribbon(z.lanes[li], 9.0)
		lane.material_override = path_mat
		lane.position.y = 0.03 + li * 0.015
		lane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(lane)

	# куда выводит телепорт «1» (обратно — только пешком)
	var mark := MeshInstance3D.new()
	mark.mesh = Fx.flat_ring_mesh(1.0, 1.35, 32)
	mark.material_override = Fx.glow_mat(Color(1.0, 0.82, 0.35), 1.0, true, 0.45)
	mark.position = z.center_mark + Vector3(0, 0.05, 0)
	root.add_child(mark)

	# врата монстров (ромбы вверху троп)
	for sp in z.spawns:
		var l := z.to_local(sp)
		_place(root, z, "SpawnGate", l.x, l.y + 2.2, 0.0, 1.1)
		var dark := MeshInstance3D.new()
		dark.mesh = Fx.disc_mesh(2.6, 24)
		var portal_ground := ShaderMaterial.new()
		portal_ground.shader = load("res://assets/approved_portal/ground.gdshader")
		dark.material_override = portal_ground
		dark.position = sp + Vector3(0, 0.06, 0)
		root.add_child(dark)
		_light(root, sp + Vector3(0, 3.0, 0), Color(0.7, 0.3, 1.0), 2.0, 9.0)

	# препятствия
	for o in z.obstacles:
		var r: Rect2 = o.r
		var c := r.get_center()
		match o.kind:
			"cliff":
				_box(root, z, r, 2.3, preload("res://assets/approved_materials/materials.gd").wall_material(), 2.4)
				var long_x := r.size.x > r.size.y
				var len := maxf(r.size.x, r.size.y)
				var k := 0.8
				while k < len - 0.5:
					var px := r.position.x + (k if long_x else r.size.x * 0.5)
					var pz2 := r.position.y + (r.size.y * 0.5 if long_x else k)
					var rk := _place(root, z, "Rock1" if rng.randf() < 0.6 else "IceRock", px, pz2, rng.randf() * TAU,
						rng.randf_range(0.55, 0.8))
					rk.position.y = 2.05
					k += rng.randf_range(2.2, 3.4)
			"house":
				_place(root, z, "House", c.x, c.y, 0.0, 0.95)
			"obelisk":
				_place(root, z, "Obelisk", c.x, c.y)
			"pagoda":
				_place(root, z, "Pagoda", c.x, c.y, PI * 0.25)
			"tower":
				var t := _place(root, z, "Tower", c.x, c.y, 0.0, 1.0)
				recolor(t, "TowerGem", team_col, 1.8)
				_light(root, t.position + Vector3(0, 6.2, 0), team_col, 1.6, 7.0)
			"fountain_life", "fountain_mana":
				var life: bool = o.kind == "fountain_life"
				var col := Color(1.0, 0.25, 0.3) if life else Color(0.3, 0.55, 1.0)
				var f := _place(root, z, "Fountain", c.x, c.y)
				recolor(f, "FountainWater", col, 1.6)
				_light(root, f.position + Vector3(0, 2.5, 0), col, 2.2, 8.0)
				_fountain_particles(root, f.position, col)
				var lbl := Label3D.new()
				lbl.text = "Фонтан жизни" if life else "Фонтан маны"
				lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				lbl.font_size = 48
				lbl.outline_size = 10
				lbl.modulate = col.lightened(0.4)
				lbl.pixel_size = 0.012
				lbl.position = f.position + Vector3(0, 3.6 + (0.0 if life else 0.7), 0)
				root.add_child(lbl)
			"trees", "decor":
				pass   # деревья леса, телега и ящики — в Decor
			"rocks":
				_place(root, z, "IceRock", c.x, c.y, rng.randf() * TAU, 1.4)
				_place(root, z, "IceCrystal", c.x + 0.6, c.y - 0.8, rng.randf() * TAU, 1.0)

	# лагерь: флаги, снеговик, фонари
	for lx in [-4.0, 4.0]:
		var b := _place(root, z, "Banner", lx, 16.5)
		recolor(b, "TeamCloth", team_col, 0.4)
	_place(root, z, "Snowman", 6.5, 15.0, 0.6)
	_place(root, z, "IceCrystal", 7.0, 6.5, 0.3, 0.9)
	for k in [[-7.2, 20.0], [7.2, 20.0], [-2.6, 5.8], [2.6, 5.8]]:
		var ln := _place(root, z, "Lantern", k[0], k[1], 0.0, 1.1)
		_light(root, ln.position + Vector3(0, 2.0, 0), Color(1.0, 0.75, 0.45), 1.3, 7.0)
	# фонари на развилках
	for k in [[-16.0, 36.0], [16.0, 36.0], [-16.0, 57.0], [16.0, 57.0], [-16.0, 1.5], [16.0, 1.5]]:
		var ln := _place(root, z, "Lantern", k[0], k[1], 0.0, 1.2)
		_light(root, ln.position + Vector3(0, 2.0, 0), Color(1.0, 0.75, 0.45), 1.3, 7.0)

	# лес: своя зелёная земля (деревья, трава и цветы — в Decor)
	_box(root, z, Zone.FOREST_GROUND, 0.02, Forest2.ground_material(z) if Forest2.enabled else forest)
	if Forest2.enabled:
		Forest2.build_fx(root, z)
	var fl := Label3D.new()
	fl.text = "Мини-лес"
	fl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	fl.font_size = 64
	fl.outline_size = 12
	fl.modulate = Color(0.6, 1.0, 0.6, 0.85)
	fl.pixel_size = 0.014
	fl.position = z.to_world(0.0, 93.0) + Vector3(0, 5.0, 0)
	root.add_child(fl)


static func _fountain_particles(root: Node3D, pos: Vector3, col: Color) -> void:
	var p := CPUParticles3D.new()
	p.amount = 24
	p.lifetime = 1.4
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.4
	p.direction = Vector3.UP
	p.spread = 20.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 2.2
	p.gravity = Vector3(0, -0.6, 0)
	p.scale_amount_min = 0.08
	p.scale_amount_max = 0.18
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 6
	sm.rings = 3
	p.mesh = sm
	p.material_override = Fx.glow_mat(col, 2.5)
	p.position = pos + Vector3(0, 2.3, 0)
	root.add_child(p)


static func _ribbon(points: Array[Vector3], width: float) -> ArrayMesh:
	var pts: Array[Vector3] = []
	var n := points.size()
	for i in n - 1:
		var p0 := points[maxi(i - 1, 0)]
		var p1 := points[i]
		var p2 := points[i + 1]
		var p3 := points[mini(i + 2, n - 1)]
		for s in 8:
			pts.append(_catmull(p0, p1, p2, p3, s / 8.0))
	pts.append(points[n - 1])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var along := 0.0
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var dir := (b - a).normalized()
		var side := Vector3(-dir.z, 0, dir.x) * width * 0.5
		var dir2 := dir
		if i + 2 < pts.size():
			dir2 = (pts[i + 2] - b).normalized()
		var side2 := Vector3(-dir2.z, 0, dir2.x) * width * 0.5
		var l := a.distance_to(b)
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(0, along)); st.add_vertex(a - side)
		st.set_uv(Vector2(1, along + l)); st.add_vertex(b + side2)
		st.set_uv(Vector2(1, along)); st.add_vertex(a + side)
		st.set_uv(Vector2(0, along)); st.add_vertex(a - side)
		st.set_uv(Vector2(0, along + l)); st.add_vertex(b - side2)
		st.set_uv(Vector2(1, along + l)); st.add_vertex(b + side2)
		along += l
	return st.commit()


static func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)



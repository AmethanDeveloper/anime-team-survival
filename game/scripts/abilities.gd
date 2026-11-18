class_name Abilities
## Исполнение способностей героев и их эффекты.


static func execute(h: Hero, i: int, point: Vector3, unit: Unit) -> void:
	var a: Dictionary = h.abilities[i].def
	var dmg := h.ability_power(i)
	match a.type:
		"w3":
			if W3Runtime.I:
				W3Abil.hero_cast(W3Runtime.I, h, i, point, unit, int(h.pending.get("w3id", 0)))
		"line":
			_line(h, a, dmg, point)
		"leap_strike":
			_leap_strike(h, a, dmg, point)
		"slashes":
			_slashes(h, a, dmg)
		"empower":
			h.add_buff(h.abilities[i].id, a, a.duration)
			_buff_fx(h, a.color, a.duration)
		"bolt":
			_bolt(h, a, dmg, unit)
		"ice_blocks":
			_ice_blocks(h, a, dmg, point)
		"blink":
			_blink(h, a, point)
		"transform":
			var extra := {}
			if a.has("bonus_hp"):
				extra["bonus_hp"] = float(a.bonus_hp) + float(a.get("bonus_hp_str", 0.0)) * h.s_str
			var was_full := h.hp
			h.add_buff(h.abilities[i].id, a, a.duration, extra)
			if extra.has("bonus_hp"):
				h.hp = minf(h.max_hp, was_full + extra.bonus_hp)
			_transform_fx(h, a, h.abilities[i].id)
		"time_stop":
			Game.I.start_time_stop(h, a.duration)
		"mugetsu":
			_mugetsu(h, a, dmg, point)
		"metamorphosis":
			h.add_buff("akame_d", a, a.duration)
			_transform_fx(h, a, "akame_d")
		"nova":
			_nova(h, a, dmg)
		"aoe_point":
			_aoe_point(h, a, dmg, point)


static func _dir_to(h: Unit, p: Vector3) -> Vector3:
	var d := p - h.global_position
	d.y = 0.0
	if d.length() < 0.1:
		d = h.global_transform.basis.z
		d.y = 0.0
	return d.normalized()


## Эффекты способности при попадании: замедление, оглушение, заморозка, яд/горение.
static func effects(a: Dictionary) -> Dictionary:
	var e := {}
	if a.has("slow"):
		e["slow"] = float(a.slow)
		e["slow_time"] = float(a.get("slow_time", 2.0))
	if a.has("stun"):
		e["stun"] = float(a.stun)
	if a.has("freeze"):
		e["freeze"] = float(a.freeze)
	if a.has("poison"):
		e["poison"] = float(a.poison)
		e["poison_time"] = float(a.get("poison_time", 4.0))
	return e


static func apply_effects(h: Hero, u: Unit, dmg: float, e: Dictionary) -> void:
	if e.has("slow"):
		u.apply_slow(e.slow, e.slow_time)
	if e.has("stun"):
		u.apply_stun(e.stun)
	if e.has("freeze"):
		u.apply_freeze(e.freeze)
	if e.has("poison") and is_instance_valid(h):
		u.apply_poison(h, dmg * float(e.poison), float(e.poison_time))


static func _hit_enemies(h: Hero, pos: Vector3, r: float, dmg: float, extra := {}) -> int:
	var n := 0
	for u in Game.I.enemies_in_radius(pos, r, h, false):
		Game.I.deal_damage(h, u, dmg, "spell")
		if extra.has("slow"):
			u.apply_slow(extra.slow, extra.slow_time)
		if extra.has("stun"):
			u.apply_stun(extra.stun)
		if extra.has("freeze"):
			u.apply_freeze(extra.freeze)
		if extra.has("poison"):
			u.apply_poison(h, dmg * float(extra.poison), float(extra.poison_time))
		n += 1
	return n


# ----------------------------------------------------------------- снаряд по линии
static func _line(h: Hero, a: Dictionary, dmg: float, point: Vector3) -> void:
	var shots := int(a.get("shots", 1))
	_line_once(h, a, dmg, point, 0.0)
	for k in range(1, shots):
		var side := (0.35 if k % 2 == 1 else -0.35) * float((k + 1) / 2)
		Game.I.get_tree().create_timer(0.14 * k, false).timeout.connect(func() -> void:
			if is_instance_valid(h) and h.alive:
				_line_once(h, a, dmg, point, side))


static func _line_once(h: Hero, a: Dictionary, dmg: float, point: Vector3, side: float) -> void:
	var dir := _dir_to(h, point)
	var start := h.global_position + Vector3(0, 1.2, 0) + dir * 0.8 + dir.cross(Vector3.UP) * side
	var dist: float = a.range
	var speed: float = a.speed
	var width: float = a.width
	var col: Color = a.color
	var shape: String = a.get("shape", "")
	# Ичиго: в Банкае и форме Пустого волна чёрно-красная и сильнее
	if h.hero_id == "ichigo":
		var qm := 1.0
		for id in ["ichigo_e", "ichigo_r"]:
			if h.has_buff(id):
				qm = maxf(qm, float(h.buffs[id].def.get("q_mult", 1.0)))
		if qm > 1.0:
			dmg *= qm
			col = Color(0.75, 0.05, 0.08)
			width *= 1.25
	var extra := effects(a)
	var hit := {}
	var src := h
	var area := h.area
	var travelled := [0.0]
	var n := Fx.spawn(Game.I.fx_root, start, dist / speed + 0.2, func(node: Fx.FxNode, d: float) -> bool:
		var step := speed * d
		var from := node.global_position
		node.global_position += dir * step
		travelled[0] += step
		if not is_instance_valid(src):
			return false
		for u in Game.I.units:
			if not u.alive or u.area != area or u.kind == Unit.Kind.CRYSTAL or u.team == src.team or hit.has(u):
				continue
			var p := Geometry3D.get_closest_point_to_segment(u.global_position + Vector3(0, 1.2, 0), from, node.global_position)
			var dd := Vector2(p.x - u.global_position.x, p.z - u.global_position.z).length()
			if dd <= width * 0.5 + u.radius:
				hit[u] = true
				Game.I.deal_damage(src, u, dmg, "spell")
				apply_effects(src, u, dmg, extra)
				Fx.burst(Game.I.fx_root, u.global_position + Vector3(0, 1.2, 0), col, 10, 4.0, 0.2, 0.35)
		return travelled[0] < dist)
	n.data["owner"] = h
	n.look_at(start + dir, Vector3.UP, true)
	match shape:
		"crescent":
			Fx.add_mesh(n, Fx.crescent_mesh(width * 1.5, 1.5), Fx.glow_mat(col, 3.0))
			Fx.add_mesh(n, Fx.crescent_mesh(width * 1.15, 1.0), Fx.glow_mat(col.lightened(0.5), 2.0, false, 0.6), Vector3(0, 0.05, -0.1))
			_trail(n, col, 0.4)
		"shards":
			var m := Fx.glow_mat(col, 2.5, false, 0.85)
			for k in 7:
				var pm := PrismMesh.new()
				pm.size = Vector3(0.35, 1.6, 0.35)
				var mi := Fx.add_mesh(n, pm, m, Vector3((k - 3) * width * 0.14, randf_range(-0.3, 0.3), -absf(k - 3) * 0.35))
				mi.rotation.x = PI / 2.0
			_trail(n, col, 0.3)
		_:
			var orb := SphereMesh.new()
			orb.radius = clampf(width * 0.18, 0.25, 1.4)
			orb.height = orb.radius * 2.0
			Fx.add_mesh(n, orb, Fx.glow_mat(col, 3.0))
			var glow := SphereMesh.new()
			glow.radius = orb.radius * 1.8
			glow.height = glow.radius * 2.0
			Fx.add_mesh(n, glow, Fx.glow_mat(col.lightened(0.3), 1.5, false, 0.35))
			_trail(n, col, clampf(width * 0.12, 0.25, 0.9))


static func _trail(n: Node3D, col: Color, size: float) -> void:
	var p := CPUParticles3D.new()
	p.amount = 30
	p.lifetime = 0.4
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 1.0
	p.gravity = Vector3.ZERO
	p.scale_amount_min = size * 0.6
	p.scale_amount_max = size
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 6
	sm.rings = 3
	p.mesh = sm
	p.material_override = Fx.glow_mat(col, 2.0, false, 0.6)
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve
	n.add_child(p)


# ----------------------------------------------------------------- рывок-удар Акаме
static func _leap_strike(h: Hero, a: Dictionary, dmg: float, point: Vector3) -> void:
	var dir := _dir_to(h, point)
	var dist := minf(h.flat_dist_p(point), a.range)
	var start := h.global_position
	var end := h.clamp_area(start + dir * dist)
	var col: Color = a.color
	for k in 5:
		Fx.afterimage(Game.I.fx_root, start.lerp(end, float(k) / 5.0), h.rotation.y, col)
	h.global_position = end
	h.yaw_target = atan2(dir.x, dir.z)
	h.invulnerable = 0.15
	_hit_enemies(h, end, a.radius, dmg, effects(a))
	Fx.ring_burst(Game.I.fx_root, end, a.radius, col, 0.4, 0.5)
	_cross_slash(end + Vector3(0, 1.2, 0), col, 2.6)
	Fx.burst(Game.I.fx_root, end + Vector3(0, 1.0, 0), col, 26, 7.0, 0.3, 0.5)


static func _cross_slash(p: Vector3, col: Color, size := 1.0) -> void:
	var m := Fx.fade_mat(col, 3.5)
	var n := Fx.spawn(Game.I.fx_root, p, 0.35, func(node: Fx.FxNode, _d: float) -> bool:
		m.albedo_color.a = 1.0 - node.t / 0.35
		node.scale = Vector3.ONE * size * (1.0 + node.t * 2.0)
		return true)
	for k in 2:
		var bm := BoxMesh.new()
		bm.size = Vector3(0.12, 3.0, 0.04)
		var mi := Fx.add_mesh(n, bm, m)
		mi.rotation.z = 0.8 if k == 0 else -0.8
	if Game.I.camera:
		n.look_at(Game.I.camera.global_position, Vector3.UP)


# ----------------------------------------------------------------- серия разрезов вокруг себя
static func _slashes(h: Hero, a: Dictionary, dmg: float) -> void:
	var hits: int = a.hits
	var dur: float = a.duration
	var r: float = a.radius
	var col: Color = a.color
	var done := [0]
	var n := Fx.spawn(Game.I.fx_root, h.global_position, dur + 0.1, func(node: Fx.FxNode, _d: float) -> bool:
		if not is_instance_valid(h) or not h.alive:
			return false
		node.global_position = h.global_position
		var want := int(node.t / dur * hits)
		while done[0] < mini(want, hits):
			done[0] += 1
			_hit_enemies(h, h.global_position, r, dmg)
			var off := Vector3(randf_range(-r, r), 0, randf_range(-r, r)) * 0.5
			_cross_slash(h.global_position + off + Vector3(0, 1.2, 0), col, 1.2)
			Audio.sfx("swing", h.global_position, 0.6, 0.2, 0.05)
		return true)
	n.data["owner"] = h
	Fx.ring_burst(Game.I.fx_root, h.global_position, r, col, 0.5, 0.4)


## Разрез по области (пассивка Метаморфозы).
static func auto_slash(h: Hero, pos: Vector3, dmg: float) -> void:
	_hit_enemies(h, pos, 3.5, dmg)
	_cross_slash(pos + Vector3(0, 1.2, 0), Color(0.9, 0.05, 0.1), 1.6)
	Fx.ring_burst(Game.I.fx_root, pos, 3.5, Color(0.9, 0.05, 0.1), 0.35, 0.3)


## Мгновенный шаг Акаме в Метаморфозе (без перезарядки).
static func instant_step(h: Hero, point: Vector3, max_range: float) -> void:
	var dir := _dir_to(h, point)
	var dist := minf(h.flat_dist_p(point), max_range)
	var start := h.global_position
	Fx.burst(Game.I.fx_root, start + Vector3(0, 1.0, 0), Color(0.9, 0.05, 0.1), 16, 4.0, 0.3, 0.4)
	for k in 4:
		Fx.afterimage(Game.I.fx_root, start.lerp(start + dir * dist, float(k) / 4.0), h.rotation.y, Color(0.9, 0.05, 0.1))
	h.global_position = h.clamp_area(start + dir * dist)
	h.yaw_target = atan2(dir.x, dir.z)
	h.rotation.y = h.yaw_target
	h.order = "idle"
	Audio.sfx("blink", h.global_position, 0.8)


# ----------------------------------------------------------------- ледяной молот
static func _bolt(h: Hero, a: Dictionary, dmg: float, target: Unit) -> void:
	if target == null or not is_instance_valid(target) or not target.alive:
		return
	var col: Color = a.color
	var stun: float = a.get("stun", 0.0)
	var ice: bool = a.get("shape", "ice" if h.hero_id == "esdeath" else "") == "ice"
	var e := effects(a)
	e.erase("stun")
	var start := h.global_position + Vector3(0, 2.0, 0)
	var n := Fx.spawn(Game.I.fx_root, start, 3.0, func(node: Fx.FxNode, d: float) -> bool:
		if not is_instance_valid(target) or not target.alive:
			return false
		var aim := target.global_position + Vector3(0, 1.2, 0)
		var to := aim - node.global_position
		var step := 26.0 * d
		node.rotate_y(d * 8.0)
		if to.length() <= step + 0.4:
			if is_instance_valid(h):
				Game.I.deal_damage(h, target, dmg, "spell")
				apply_effects(h, target, dmg, e)
			if stun > 0.0:
				if ice:
					target.apply_freeze(stun)
				else:
					target.apply_stun(stun)
			Fx.burst(Game.I.fx_root, aim, col, 26, 7.0, 0.3, 0.5)
			Fx.ring_burst(Game.I.fx_root, target.global_position, 2.2, col, 0.4, 0.4)
			Audio.sfx("ice_shatter" if ice else "hit", aim, 0.8)
			return false
		node.global_position += to.normalized() * step
		return true)
	n.data["owner"] = h
	if ice:
		var bm := BoxMesh.new()
		bm.size = Vector3(1.0, 1.0, 1.0)
		var mi := Fx.add_mesh(n, bm, _ice_mat())
		mi.rotation = Vector3(0.6, 0.3, 0.4)
	else:
		var sm := SphereMesh.new()
		sm.radius = 0.45
		sm.height = 0.9
		Fx.add_mesh(n, sm, Fx.glow_mat(col, 3.0))
		var sg := SphereMesh.new()
		sg.radius = 0.8
		sg.height = 1.6
		Fx.add_mesh(n, sg, Fx.glow_mat(col.lightened(0.3), 1.4, false, 0.35))
	_trail(n, col, 0.35)


static var _ice: StandardMaterial3D = null


static func _ice_mat() -> StandardMaterial3D:
	if _ice == null:
		_ice = StandardMaterial3D.new()
		_ice.albedo_color = Color(0.75, 0.92, 1.0, 0.85)
		_ice.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ice.roughness = 0.08
		_ice.emission_enabled = true
		_ice.emission = Color(0.45, 0.75, 1.0)
		_ice.emission_energy_multiplier = 0.6
	return _ice


# ----------------------------------------------------------------- ледяные глыбы (Хагельшпрунг)
static func _ice_blocks(h: Hero, a: Dictionary, dmg: float, point: Vector3) -> void:
	var count := 1 + int((h.level - Data.UNLOCK[3]) / float(a.blocks_lvl))
	count = clampi(count, 1, 4)
	var r: float = a.radius
	var col: Color = a.color
	var stun: float = a.stun
	for k in count:
		var off := Vector3.ZERO if k == 0 else Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * r * 0.8
		var p := h.clamp_area(point + off)
		var delay := 0.8 + k * 0.45
		Fx.telegraph(Game.I.fx_root, p, r, col, delay)
		var top := p + Vector3(0, 22, 0)
		var landed := [false]
		var n := Fx.spawn(Game.I.fx_root, top, delay + 0.05, func(node: Fx.FxNode, d: float) -> bool:
			var t := clampf(node.t / delay, 0.0, 1.0)
			node.global_position = top.lerp(p + Vector3(0, r * 0.5, 0), t * t)
			node.rotate_y(d * 0.8)
			if t >= 1.0 and not landed[0]:
				landed[0] = true
				if is_instance_valid(h):
					_hit_enemies(h, p, r, dmg, {"freeze": stun})
				Fx.ring_burst(Game.I.fx_root, p, r * 1.2, col, 0.6, 0.8)
				Fx.burst(Game.I.fx_root, p + Vector3(0, 1.0, 0), col, 50, 12.0, 0.45, 0.9)
				_ice_spikes(p, r, col)
				Audio.sfx("ice_shatter", p, 1.0)
				if Game.I.camera:
					Game.I.camera.shake(0.35)
				return false
			return true)
		n.data["owner"] = h
		var bm := BoxMesh.new()
		bm.size = Vector3(r * 1.1, r * 1.1, r * 1.1)
		var mi := Fx.add_mesh(n, bm, _ice_mat())
		mi.rotation = Vector3(0.3, 0.5, 0.2)


static func _ice_spikes(p: Vector3, r: float, col: Color) -> void:
	var m := Fx.fade_mat(col, 1.5)
	var n := Fx.spawn(Game.I.fx_root, p, 1.2, func(node: Fx.FxNode, _d: float) -> bool:
		var k := node.t / 1.2
		node.scale.y = minf(1.0, node.t * 6.0)
		m.albedo_color.a = clampf((1.0 - k) * 1.5, 0.0, 0.8)
		return true)
	for k in 9:
		var ang := TAU * k / 9.0 + randf() * 0.3
		var pm := PrismMesh.new()
		pm.size = Vector3(0.6, randf_range(1.5, 3.0), 0.6)
		var mi := Fx.add_mesh(n, pm, m, Vector3(cos(ang), 0, sin(ang)) * r * randf_range(0.3, 0.9) + Vector3(0, pm.size.y / 2.0, 0))
		mi.rotation = Vector3(randf_range(-0.3, 0.3), 0, randf_range(-0.3, 0.3))


# ----------------------------------------------------------------- сюмпо
static func _blink(h: Hero, a: Dictionary, point: Vector3) -> void:
	var dir := _dir_to(h, point)
	var dist := minf(h.flat_dist_p(point), a.range)
	var col: Color = a.color
	var start := h.global_position
	Fx.burst(Game.I.fx_root, start + Vector3(0, 1.0, 0), col, 18, 5.0, 0.25, 0.4)
	for k in 3:
		Fx.afterimage(Game.I.fx_root, start.lerp(start + dir * dist, float(k) / 3.0), h.rotation.y, col)
	h.global_position = h.clamp_area(start + dir * dist)
	h.yaw_target = atan2(dir.x, dir.z)
	h.rotation.y = h.yaw_target
	Fx.ring_burst(Game.I.fx_root, h.global_position, 1.8, col, 0.3, 0.3)


# ----------------------------------------------------------------- усиления и превращения
static func _buff_fx(h: Hero, col: Color, dur: float) -> void:
	Fx.ring_burst(Game.I.fx_root, h.global_position, 2.2, col, 0.5)
	var m := Fx.fade_mat(col, 2.0)
	var n := Fx.spawn(Game.I.fx_root, h.global_position, dur, func(node: Fx.FxNode, d: float) -> bool:
		if not is_instance_valid(h) or not h.alive:
			return false
		node.global_position = h.global_position + Vector3(0, 0.15, 0)
		node.rotate_y(d * 4.0)
		m.albedo_color.a = 0.7 * clampf((dur - node.t) * 2.0, 0.0, 1.0)
		return true)
	n.data["owner"] = h
	Fx.add_mesh(n, Fx.flat_ring_mesh(1.0, 1.35, 6), m)


static func _transform_fx(h: Hero, a: Dictionary, buff_id: String) -> void:
	var cv = a.get("aura", a.color)
	var col: Color = Color(cv[0], cv[1], cv[2]) if cv is Array else cv
	Fx.pillar(Game.I.fx_root, h.global_position, 2.2, 10.0, col, 1.0)
	Fx.ring_burst(Game.I.fx_root, h.global_position, 6.0, col, 0.7, 0.8)
	Fx.burst(Game.I.fx_root, h.global_position + Vector3(0, 1.5, 0), col, 60, 10.0, 0.4, 0.9)
	if Game.I.camera:
		Game.I.camera.shake(0.25)
	var dur: float = a.duration
	var m := Fx.fade_mat(col, 1.6)
	var n := Fx.spawn(Game.I.fx_root, h.global_position, dur, func(node: Fx.FxNode, d: float) -> bool:
		if not is_instance_valid(h) or not h.alive or not h.has_buff(buff_id):
			return false
		node.global_position = h.global_position
		node.rotate_y(d * 2.5)
		m.albedo_color.a = 0.55
		return true)
	n.data["owner"] = h
	Fx.add_mesh(n, Fx.flat_ring_mesh(1.3, 1.7, 24), m, Vector3(0, 0.1, 0))
	var p := CPUParticles3D.new()
	p.amount = 40
	p.lifetime = 0.8
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_radius = 1.0
	p.emission_ring_inner_radius = 0.5
	p.emission_ring_height = 0.1
	p.emission_ring_axis = Vector3.UP
	p.direction = Vector3.UP
	p.spread = 15.0
	p.initial_velocity_min = 2.5
	p.initial_velocity_max = 4.5
	p.gravity = Vector3.ZERO
	p.scale_amount_min = 0.1
	p.scale_amount_max = 0.25
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 6
	sm.rings = 3
	p.mesh = sm
	p.material_override = Fx.glow_mat(col, 2.5)
	n.add_child(p)


# ----------------------------------------------------------------- Мугэцу
static func _mugetsu(h: Hero, a: Dictionary, dmg: float, point: Vector3) -> void:
	var dir := _dir_to(h, point)
	var dist: float = a.range
	var width: float = a.width
	var start := h.global_position + dir * 1.0
	var end := h.clamp_area(h.global_position + dir * dist)
	var area := h.area
	var hit := {}
	var speed := dist / 0.9
	var travelled := [0.0]
	var col := Color(0.05, 0.0, 0.02)
	var red := Color(0.8, 0.05, 0.08)
	if Game.I.camera:
		Game.I.camera.shake(0.8)
	Game.I.flash_screen(Color(0, 0, 0, 0.55), 0.6)
	var n := Fx.spawn(Game.I.fx_root, start, 1.2, func(node: Fx.FxNode, d: float) -> bool:
		var step := speed * d
		var from := node.global_position
		node.global_position += dir * step
		travelled[0] += step
		if is_instance_valid(h):
			for u in Game.I.units:
				if not u.alive or u.area != area or u.kind == Unit.Kind.CRYSTAL or u.team == h.team or hit.has(u):
					continue
				var p := Geometry3D.get_closest_point_to_segment(u.global_position, from - Vector3(0, from.y, 0), node.global_position - Vector3(0, node.global_position.y, 0))
				if p.distance_to(u.global_position) <= width * 0.5 + u.radius:
					hit[u] = true
					Game.I.deal_damage(h, u, dmg, "spell", true)
					Fx.burst(Game.I.fx_root, u.global_position + Vector3(0, 1.0, 0), red, 16, 6.0, 0.3, 0.5)
		return travelled[0] < dist)
	n.data["owner"] = h
	n.look_at(start + dir, Vector3.UP, true)
	var wall := Fx.glow_mat(col, 0.5, false, 0.92)
	var edge := Fx.glow_mat(red, 3.0, false, 0.85)
	var bm := BoxMesh.new()
	bm.size = Vector3(width, 9.0, 1.6)
	Fx.add_mesh(n, bm, wall, Vector3(0, 4.5, 0))
	var em := BoxMesh.new()
	em.size = Vector3(width * 1.05, 0.3, 1.8)
	Fx.add_mesh(n, em, edge, Vector3(0, 9.0, 0))
	Fx.add_mesh(n, Fx.crescent_mesh(width * 1.4, 2.5), edge, Vector3(0, 0.3, 0.6))
	_trail(n, red, 1.0)
	# след на земле
	var m := Fx.fade_mat(col, 0.5)
	var scar := Fx.spawn(Game.I.fx_root, (start + end) / 2.0 + Vector3(0, 0.05, 0), 3.0, func(node: Fx.FxNode, _d: float) -> bool:
		m.albedo_color.a = 0.75 * (1.0 - node.t / 3.0)
		return true)
	var pm := PlaneMesh.new()
	pm.size = Vector2(width, start.distance_to(end))
	var mi := Fx.add_mesh(scar, pm, m)
	mi.rotation.y = atan2(dir.x, dir.z)
	h.add_buff("weak", {"name": "Истощение"}, float(a.weak_time))


# ----------------------------------------------------------------- удар по области вокруг себя
static func _nova(h: Hero, a: Dictionary, dmg: float) -> void:
	var r: float = a.get("radius", 5.5)
	var col: Color = a.color
	var waves := int(a.get("waves", 1))
	var e := effects(a)
	for k in waves:
		var delay := 0.55 * k
		if delay <= 0.0:
			_nova_wave(h, r, dmg, col, e)
		else:
			Game.I.get_tree().create_timer(delay, false).timeout.connect(func() -> void:
				if is_instance_valid(h) and h.alive:
					_nova_wave(h, r, dmg, col, e))


static func _nova_wave(h: Hero, r: float, dmg: float, col: Color, e: Dictionary) -> void:
	_hit_enemies(h, h.global_position, r, dmg, e)
	Fx.ring_burst(Game.I.fx_root, h.global_position, r, col, 0.5, 0.7)
	Fx.ring_burst(Game.I.fx_root, h.global_position, r * 0.6, col.lightened(0.3), 0.35, 0.5)
	Fx.burst(Game.I.fx_root, h.global_position + Vector3(0, 1.0, 0), col, int(20 + r * 4), r * 1.6, 0.35, 0.6)
	if r >= 7.0:
		Fx.pillar(Game.I.fx_root, h.global_position, 1.6, 8.0, col, 0.6)
		if Game.I.camera:
			Game.I.camera.shake(0.3)
	if e.has("freeze"):
		_ice_spikes(h.global_position, r, col)


# ----------------------------------------------------------------- удар по области в точке
static func _aoe_point(h: Hero, a: Dictionary, dmg: float, point: Vector3) -> void:
	var r: float = a.get("radius", 4.5)
	var col: Color = a.color
	var waves := int(a.get("waves", 1))
	var delay: float = a.get("delay", 0.6)
	var e := effects(a)
	var center := h.clamp_area(point)
	for k in waves:
		var p := center
		if waves > 1 and k > 0:
			p = h.clamp_area(center + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * r * randf_range(0.2, 0.5))
		var t := delay + 0.5 * k
		Fx.telegraph(Game.I.fx_root, p, r, col, t)
		var falling := waves == 1 and r >= 5.5
		var top := p + Vector3(0, 18, 0)
		var done := [false]
		var n := Fx.spawn(Game.I.fx_root, top if falling else p, t + 0.05, func(node: Fx.FxNode, _d: float) -> bool:
			var f := clampf(node.t / t, 0.0, 1.0)
			if falling:
				node.global_position = top.lerp(p + Vector3(0, 1.0, 0), f * f)
			if f >= 1.0 and not done[0]:
				done[0] = true
				if is_instance_valid(h):
					_hit_enemies(h, p, r, dmg, e)
				Fx.ring_burst(Game.I.fx_root, p, r * 1.1, col, 0.45, 0.6)
				Fx.burst(Game.I.fx_root, p + Vector3(0, 0.8, 0), col, int(18 + r * 5), r * 1.8, 0.4, 0.7)
				if e.has("freeze"):
					_ice_spikes(p, r, col)
				Audio.sfx(a.get("sfx", "crystal_break"), p, 0.7, 0.1, 0.1)
				if r >= 6.0 and Game.I.camera:
					Game.I.camera.shake(0.2)
				return false
			return true)
		n.data["owner"] = h
		if falling:
			var sm := SphereMesh.new()
			sm.radius = r * 0.35
			sm.height = r * 0.7
			Fx.add_mesh(n, sm, Fx.glow_mat(col, 2.5))
			_trail(n, col, 0.8)


# ----------------------------------------------------------------- Акаме: Козырь Мурасамэ (сет)
## Облик Акаме в «Козыре»: тёмно-красная аура по телу, проклятые метки, алый свет, герой чуть выше.
static func akame_form(u, on: bool) -> void:
	var h := u as Hero
	if h == null or not is_instance_valid(h):
		return
	var old := h.get_node_or_null("AkameForm")
	if old:
		old.queue_free()
	if h.model:
		for mi in h.model.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).material_overlay = null
		if h.has_meta("akame_scale"):
			h.model.scale = h.get_meta("akame_scale")
			h.remove_meta("akame_scale")
	h.remove_buff("akame_form")
	if not on or Game.I == null:
		return
	h.add_buff("akame_form", {"name": "Козырь Мурасамэ"}, 60.0)
	if Game.I.sim:
		return
	var col := Color(0.95, 0.04, 0.1)
	if h.model:
		var ov := ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode blend_add, unshaded, cull_back, depth_draw_never;
void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 1.6);
	float veins = smoothstep(0.55, 0.9, sin(UV.x * 38.0 + TIME * 2.0) * sin(UV.y * 31.0 - TIME * 1.3));
	ALBEDO = vec3(1.0, 0.05, 0.12) * (0.35 + rim * 2.2 + veins * 1.5);
	ALPHA = clamp(0.25 + rim * 0.75 + veins * 0.6, 0.0, 1.0);
}
"""
		ov.shader = sh
		for mi in h.model.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).material_overlay = ov
		h.set_meta("akame_scale", h.model.scale)
		h.model.scale *= 1.12
	var root := Node3D.new()
	root.name = "AkameForm"
	h.add_child(root)
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = 2.6
	l.omni_range = 6.0
	l.position.y = 1.6
	root.add_child(l)
	var ring := MeshInstance3D.new()
	ring.mesh = Fx.flat_ring_mesh(1.2, 1.7, 32)
	ring.material_override = Fx.glow_mat(col, 2.4, true, 0.7)
	ring.position.y = 0.1
	root.add_child(ring)
	var p := CPUParticles3D.new()
	p.amount = 46
	p.lifetime = 1.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.8
	p.position.y = 1.0
	p.direction = Vector3.UP
	p.spread = 25.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 3.2
	p.gravity = Vector3.ZERO
	p.scale_amount_min = 0.06
	p.scale_amount_max = 0.16
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.6
	sm.radial_segments = 5
	sm.rings = 3
	p.mesh = sm
	p.material_override = Fx.glow_mat(Color(0.6, 0.0, 0.05), 2.5)
	root.add_child(p)
	Fx.pillar(Game.I.fx_root, h.global_position, 2.0, 9.0, col, 0.9)
	Fx.ring_burst(Game.I.fx_root, h.global_position, 6.0, col, 0.7, 0.8)
	if Game.I.camera and h == Game.I.player:
		Game.I.camera.shake(0.3)


## Мгновенный шаг Акаме в «Козыре»: остаточные силуэты по пути, алые разряды в начале и в конце.
static func akame_blink_fx(u, from: Vector3) -> void:
	var h := u as Hero
	if h == null or Game.I == null or Game.I.sim:
		return
	var to := h.global_position
	var col := Color(0.95, 0.05, 0.12)
	for k in 6:
		Fx.afterimage(Game.I.fx_root, from.lerp(to, float(k) / 6.0), h.rotation.y, col)
	for p in [from, to]:
		Fx.burst(Game.I.fx_root, p + Vector3(0, 1.0, 0), col, 26, 6.0, 0.3, 0.5)
		Fx.ring_burst(Game.I.fx_root, p, 2.4, col, 0.35)
		if W3Runtime.I:
			W3Abil.fx_at(W3Runtime.I, "Abilities\\Spells\\Orc\\LightningShield\\LightningShieldTarget.mdl", p + Vector3(0, 0.9, 0))
	# след-разрез вдоль пути
	var mid := (from + to) * 0.5 + Vector3(0, 1.0, 0)
	var d := to - from
	d.y = 0.0
	if d.length() > 0.5:
		var slash := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.12, 0.05, d.length())
		slash.mesh = bm
		var m := Fx.glow_mat(col, 3.0, true, 0.9)
		slash.material_override = m
		Game.I.fx_root.add_child(slash)
		slash.global_position = mid
		slash.rotation.y = atan2(d.x, d.z)
		var tw := slash.create_tween()
		tw.tween_property(slash, "scale", Vector3(0.1, 1.0, 1.0), 0.35)
		tw.tween_callback(slash.queue_free)
	Audio.sfx("blink", to, 0.8)

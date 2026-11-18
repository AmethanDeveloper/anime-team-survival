class_name Unit
extends Node3D
## Базовый юнит: здоровье, движение, автоатака, анимации. Крипы и боссы думают здесь же.

enum Kind { HERO, CREEP, BOSS, CRYSTAL }

var kind: Kind = Kind.CREEP
var team := Data.MONSTER_TEAM
var area := 0  # номер острова 0..2, -1 — арена, -2 — общий лес
var display_name := ""

var max_hp := 100.0
var hp := 100.0
var max_mp := 0.0
var mp := 0.0
var hp_regen := 0.0
var mp_regen := 0.0
var base_damage := 10.0
var attack_range := 1.5
var attack_cd := 1.2
var armor := 0.0
var move_speed := 5.0
var radius := 0.6
var ranged := false
var proj_color := Color.WHITE
var bounty_gold := 0.0
var bounty_xp := 0.0
var bar_height := 2.6

var alive := true
var invulnerable := 0.0

# приказы
var order := "idle"  # idle, move, attack, attack_move, cast, hold, crystal
var target_unit: Unit = null
var target_point := Vector3.ZERO
var attack_timer := 0.0
var swing_left := -1.0
var swing_target: Unit = null
var cast_lock := 0.0

# эффекты
var stun := 0.0
var frozen_ice := 0.0
var slow := 0.0
## Немота: нельзя применять способности и предметы (Цукуёми Итачи)
var silence := 0.0
var slow_time := 0.0
var bonus_attack_speed := 0.0
var bonus_move := 0.0
var buff_time := 0.0
var heal_over_time := 0.0
var heal_time := 0.0
var mana_over_time := 0.0
var mana_time := 0.0
var dot_dps := 0.0
var dot_time := 0.0
var dot_src: Unit = null
var portal_cd := 0.0
var knock := Vector3.ZERO
var root_time := 0.0
var spell_shield := 0.0
var immortal := 0.0
var invis := 0.0
## Постоянная невидимость (Apiv, Shadowmeld): держится, пока есть способность / юнит стоит
var perm_invis := false
## Иллюзия (Mirror Image, предметы): множитель получаемого урона, урон по героям не засчитывается
var illusion := false
var dmg_taken_k := 1.0
## Сопротивление магии (магический урон режет оно, физический — броня)
var magic_resist := 0.0
## Модель полупрозрачна для своих (невидим для врагов)
var ghost := false
# триггеры карты Warcraft 3 (W3Runtime): пауза и своя анимация
var w3_paused := false
var w3_anim_lock := 0.0
# варианты анимации атаки (attack, attack 2, attack slam...) и снаряд дальней атаки из карты
var attack_variants: Array = []
var missile_art := ""
## видят ли этого юнита команды 0..2 (на арене — туман войны)
var seen: Array[bool] = [true, true, true]

# навигация
var path: Array[Vector3] = []
var path_goal := Vector3(INF, 0, INF)
var path_t := 0.0

# визуал
var model: Node3D = null
var anim: AnimationPlayer = null
var anim_map := {}
var cur_anim := ""
var yaw_target := 0.0
var ring: MeshInstance3D = null
var death_time := 0.0
var was_frozen := false
var ice_shell: MeshInstance3D = null
var proc_anim := ""
var proc_t := 0.0
var model_base_pos := Vector3.ZERO

# крипы
var think_timer := 0.0
var lane_index := 0
## Номер тропы монстра (0 — левая, 1 — правая)
var lane_id := 0
var home_zone := 0
var neutral := false
var home_pos := Vector3.ZERO
## Нейтрал: с какого расстояния замечает врага и как далеко уходит от своего места
var n_aggro := 6.5
var n_leash := 13.0
var camp: Dictionary = {}

static var _scene_cache := {}


static func load_scene(path: String) -> PackedScene:
	if not _scene_cache.has(path):
		_scene_cache[path] = load(path)
	return _scene_cache[path]


func setup_model(path: String, scale_k: float) -> void:
	attach_model(load_scene(path).instantiate(), {})
	model.scale = Vector3.ONE * scale_k


func attach_model(m: Node3D, amap: Dictionary) -> void:
	model = m
	add_child(model)
	model_base_pos = model.position
	anim = find_anim(model)
	anim_map = amap
	if anim:
		for n in ["Idle", "Run"]:
			var real := _anim_name(n)
			if real != "" and anim.has_animation(real):
				anim.get_animation(real).loop_mode = Animation.LOOP_LINEAR
	_set_shadows(model)
	play_anim("Idle")


func _set_shadows(n: Node) -> void:
	for c in n.get_children():
		if c is GeometryInstance3D:
			(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_set_shadows(c)


static func find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := find_anim(c)
		if r:
			return r
	return null


func _anim_name(n: String) -> String:
	if anim_map.has(n):
		return anim_map[n]
	if anim and anim.has_animation(n):
		return n
	return ""


func play_anim(n: String, speed := 1.0, restart := false) -> void:
	if w3_anim_lock > 0.0 and n != "Death":
		return
	var real := _anim_name(n)
	if anim == null or real == "":
		# своей анимации нет — простая программная
		if proc_anim != n or restart:
			proc_anim = n
			proc_t = 0.0
		cur_anim = n
		return
	if cur_anim == n and not restart:
		anim.speed_scale = speed
		return
	cur_anim = n
	if model is W3Model:
		# тело из модели карты (форма перевоплощения): её частицы и прозрачность частей идут за анимацией
		var wm := model as W3Model
		wm.queue.clear()
		wm.play(real, 1 if n in ["Idle", "Run"] else 0)
		wm.set_time_scale(speed)
		return
	anim.speed_scale = speed
	anim.play(real, 0.12)
	if restart:
		anim.seek(0.0, true)


func anim_busy() -> bool:
	if anim and _anim_name(cur_anim) != "":
		return anim.is_playing() and cur_anim in ["Attack", "Cast"]
	return proc_anim in ["Attack", "Cast"] and proc_t < 0.45


func _process(delta: float) -> void:
	if model == null or anim != null and _anim_name(cur_anim) != "":
		return
	if Game.I and Game.I.is_frozen(self):
		return
	proc_t += delta
	var p := model_base_pos
	var r := Vector3.ZERO
	match proc_anim:
		"Idle":
			p.y += sin(proc_t * 2.2) * 0.03
		"Run":
			p.y += absf(sin(proc_t * 11.0)) * 0.14
			r.x = 0.12
			r.z = sin(proc_t * 11.0) * 0.05
		"Attack":
			var k := clampf(proc_t / 0.4, 0.0, 1.0)
			p.z += sin(k * PI) * 0.5
			r.x = sin(k * PI) * 0.35
		"Cast":
			var k2 := clampf(proc_t / 0.45, 0.0, 1.0)
			p.y += sin(k2 * PI) * 0.25
			r.x = -sin(k2 * PI) * 0.2
		"Death":
			var k3 := clampf(proc_t / 0.7, 0.0, 1.0)
			r.x = -k3 * PI * 0.5
			p.y -= k3 * 0.3
	model.position = p
	model.rotation.x = r.x
	model.rotation.z = r.z


# ----------------------------------------------------------------- характеристики
func damage_value() -> float:
	return base_damage


func effective_attack_cd() -> float:
	var as_mult := 1.0 + bonus_attack_speed
	if slow_time > 0.0:
		as_mult *= (1.0 - slow * 0.5)
	return attack_cd / maxf(as_mult, 0.2)


func effective_speed() -> float:
	var s := move_speed * (1.0 + bonus_move)
	if slow_time > 0.0:
		s *= (1.0 - slow)
	return s


func is_enemy(o: Unit) -> bool:
	return o != null and o.team != team


func valid_target(o) -> bool:
	if not is_instance_valid(o) or not (o is Unit):
		return false
	return o != null and is_instance_valid(o) and o.alive and o.area == area and o.kind != Kind.CRYSTAL \
		and o.visible and (team == Data.MONSTER_TEAM or Game.I.can_see(team, o)) and Game.I.same_side(self, o)


func flat_dist(o: Unit) -> float:
	var a := global_position
	var b := o.global_position
	return Vector2(a.x - b.x, a.z - b.z).length()


func flat_dist_p(p: Vector3) -> float:
	var a := global_position
	return Vector2(a.x - p.x, a.z - p.z).length()


func edge_dist(o: Unit) -> float:
	return flat_dist(o) - radius - o.radius


# ----------------------------------------------------------------- приказы
func issue_move(p: Vector3) -> void:
	order = "move"
	target_point = p
	target_unit = null
	if kind == Kind.HERO and W3Runtime.I:
		W3Runtime.I.on_order(self, "move", null, p)


func issue_attack(u: Unit) -> void:
	if u == null or u == self:
		return
	order = "attack"
	target_unit = u
	if kind == Kind.HERO and W3Runtime.I:
		W3Runtime.I.on_order(self, "attack", u, null)


func issue_attack_move(p: Vector3) -> void:
	order = "attack_move"
	target_point = p
	target_unit = null


func issue_stop() -> void:
	order = "idle"
	target_unit = null


func issue_hold() -> void:
	order = "hold"
	target_unit = null


# ----------------------------------------------------------------- цикл
func _physics_process(delta: float) -> void:
	if not alive:
		_dead_process(delta)
		return
	if Game.I == null or Game.I.state == "over":
		return
	if Game.I.is_frozen(self):
		if not was_frozen:
			was_frozen = true
			if anim:
				anim.speed_scale = 0.0
		return
	if was_frozen:
		was_frozen = false
		if anim:
			anim.speed_scale = 1.0
	_timers(delta)
	if w3_anim_lock > 0.0:
		w3_anim_lock -= delta
	if w3_paused:
		return
	if kind == Kind.CRYSTAL:
		return
	if knock.length() > 0.05:
		global_position = clamp_area(global_position + knock * delta)
		knock = knock.lerp(Vector3.ZERO, 1.0 - exp(-8.0 * delta))
	if swing_left >= 0.0:
		swing_left -= delta
		if swing_left < 0.0:
			_land_attack()
	if stun > 0.0:
		if anim:
			anim.speed_scale = 0.0 if frozen_ice > 0.0 else 0.3
		return
	elif anim and anim.speed_scale == 0.0:
		anim.speed_scale = 1.0
	if cast_lock > 0.0:
		cast_lock -= delta
		_turn(delta)
		if cast_lock <= 0.0:
			_on_cast_finished()
		return
	if kind == Kind.CREEP or kind == Kind.BOSS:
		think_timer -= delta
		if think_timer <= 0.0:
			think_timer = 0.25 + randf() * 0.1
			creep_think()
	_brain(delta)
	_process_order(delta)
	_turn(delta)


func _timers(delta: float) -> void:
	attack_timer -= delta
	invulnerable = maxf(0.0, invulnerable - delta)
	stun = maxf(0.0, stun - delta)
	silence = maxf(0.0, silence - delta)
	root_time = maxf(0.0, root_time - delta)
	spell_shield = maxf(0.0, spell_shield - delta)
	immortal = maxf(0.0, immortal - delta)
	invis = maxf(0.0, invis - delta)
	if frozen_ice > 0.0:
		frozen_ice -= delta
		if frozen_ice <= 0.0 and ice_shell:
			ice_shell.queue_free()
			ice_shell = null
	portal_cd = maxf(0.0, portal_cd - delta)
	if slow_time > 0.0:
		slow_time -= delta
	if buff_time > 0.0:
		buff_time -= delta
		if buff_time <= 0.0:
			_on_buff_end()
	var regen := hp_regen
	if heal_time > 0.0:
		heal_time -= delta
		regen += heal_over_time
	if regen > 0.0 and hp < max_hp:
		hp = minf(max_hp, hp + regen * delta)
	var mregen := mp_regen
	if mana_time > 0.0:
		mana_time -= delta
		mregen += mana_over_time
	if mregen > 0.0 and mp < max_mp:
		mp = minf(max_mp, mp + mregen * delta)
	if dot_time > 0.0:
		dot_time -= delta
		Game.I.deal_damage(dot_src if is_instance_valid(dot_src) else null, self, dot_dps * delta, "dot")


func _on_buff_end() -> void:
	bonus_attack_speed = 0.0
	bonus_move = 0.0


func _on_cast_finished() -> void:
	pass


## Переопределяется героем (ИИ ботов).
func _brain(_delta: float) -> void:
	pass


func _process_order(delta: float) -> void:
	match order:
		"idle", "hold":
			if swing_left < 0.0:
				var t := _auto_acquire(order == "hold")
				if t:
					if order == "hold":
						if edge_dist(t) <= attack_range:
							_try_attack(t)
						else:
							play_anim("Idle")
					else:
						target_unit = t
						order = "attack"
				elif not anim_busy():
					play_anim("Idle")
		"move", "home":
			if move_to(target_point, delta):
				if order == "move":
					order = "idle"
		"attack":
			if not valid_target(target_unit):
				order = "idle"
				target_unit = null
				return
			if edge_dist(target_unit) > attack_range:
				if swing_left < 0.0:
					move_to(target_unit.global_position, delta)
			else:
				_try_attack(target_unit)
		"attack_move":
			if swing_left < 0.0:
				var t := _auto_acquire(false)
				if t:
					if edge_dist(t) > attack_range:
						move_to(t.global_position, delta)
					else:
						_try_attack(t)
				elif move_to(target_point, delta):
					order = "idle"
		"cast":
			_process_cast(delta)
		"crystal":
			_brain_crystal(delta)


func _process_cast(_delta: float) -> void:
	order = "idle"


func acquire_range() -> float:
	return maxf(attack_range + 4.0, 8.0)


func _auto_acquire(only_in_range: bool) -> Unit:
	var r := attack_range + radius + 0.5 if only_in_range else acquire_range()
	return Game.I.nearest_enemy(global_position, r, self)


func _try_attack(t: Unit) -> void:
	yaw_target = yaw_to(t.global_position)
	if swing_left >= 0.0:
		return
	if attack_timer > 0.0:
		if not anim_busy():
			play_anim("Idle")
		return
	var cd := effective_attack_cd()
	attack_timer = cd
	var spd := maxf(1.0, 0.75 / cd)
	var dp := 0.36
	if attack_variants.size() > 1 and anim and not anim.has_animation(str(attack_variants[0])):
		attack_variants = []   # модель сменилась (превращение) — старые удары не подходят
	if attack_variants.size() > 1 and anim:
		# разные удары подряд, точка урона — по длине анимации
		var cur_n: String = anim_map.get("Attack", "")
		var pick: String = attack_variants[randi() % attack_variants.size()]
		if pick == cur_n:
			pick = attack_variants[(attack_variants.find(pick) + 1) % attack_variants.size()]
		anim_map["Attack"] = pick
		var alen := anim.get_animation(pick).length
		spd = maxf(spd, alen / maxf(cd * 0.95, 0.2))
		dp = clampf(alen * 0.42, 0.2, 0.7)
		cur_anim = ""
	swing_left = dp / spd
	swing_target = t
	play_anim("Attack", spd, true)
	if W3Runtime.I:
		W3Runtime.I.on_attacked(self, t)
	if kind == Kind.HERO:
		Audio.sfx("swing", global_position, 0.5, 0.15, 0.05)


func _land_attack() -> void:
	var t := swing_target
	swing_target = null
	if t == null or not is_instance_valid(t) or not t.alive or t.area != area:
		return
	if ranged:
		_launch_projectile(t)
	elif edge_dist(t) <= attack_range + 1.2:
		var r := roll_attack(t)
		Game.I.deal_damage(self, t, r[0], "attack", r[1])
		on_attack_landed(t)
		_hit_flash(t, bool(r[1]))


## Вспышка удара героя (готовый эффект), только рядом с камерой.
func _hit_flash(t: Unit, crit: bool) -> void:
	if kind != Kind.HERO or not W3Vfx.active() or not is_instance_valid(t):
		return
	var cam = Game.I.camera
	if cam == null or cam.focus.distance_to(t.global_position) > 30.0:
		return
	var c := Color(1.0, 0.85, 0.6)
	if self is Hero:
		c = Color((self as Hero).def.get("color", c))
	VfxLib.spawn(Game.I.fx_root, "hit2" if crit else "hit", t.global_position + Vector3(0, 1.0, 0),
		c.lerp(Color.WHITE, 0.25), 1.1 if crit else 0.75)


## [урон, крит?] — герой переопределяет (криты, усиления).
func roll_attack(_t: Unit) -> Array:
	return [damage_value(), false]


func on_attack_landed(_t: Unit) -> void:
	pass


func _launch_projectile(t: Unit) -> void:
	var src := self
	# криты, усиления и эффекты атаки героя работают и для дальнего боя
	var roll := roll_attack(t)
	var dmg: float = roll[0]
	var crit: bool = roll[1]
	var start := global_position + Vector3(0, 1.6, 0) + global_transform.basis.z * 0.5
	var col := proj_color
	# слабые ссылки: стрелок или цель могут исчезнуть, пока снаряд летит
	var wsrc: WeakRef = weakref(src)
	var wt: WeakRef = weakref(t)
	var n := Fx.spawn(Game.I.fx_root, start, 4.0, func(node: Fx.FxNode, d: float) -> bool:
		var tt: Unit = wt.get_ref() as Unit
		if tt == null or not tt.alive:
			return false
		var ss: Unit = wsrc.get_ref() as Unit
		var aim := tt.global_position + Vector3(0, 1.0, 0)
		var to := aim - node.global_position
		var step := 24.0 * d
		if to.length() <= step + 0.3:
			var alive_src := ss != null and ss.alive
			Game.I.deal_damage(ss if alive_src else null, tt, dmg, "attack", crit)
			if alive_src and tt.alive:
				ss.on_attack_landed(tt)
			if node.has_meta("vfx") and W3Vfx.active():
				VfxLib.spawn(Game.I.fx_root, "hit", aim, col, 0.6)
			else:
				Fx.burst(Game.I.fx_root, aim, col, 8, 3.0, 0.15, 0.3)
			return false
		node.global_position += to.normalized() * step
		if node.has_meta("face") and to.length() > 0.05:
			node.look_at(aim, Vector3.UP, true)
		elif node.has_meta("vfx") and to.length() > 0.05:
			node.global_rotation = Vector3(0.0, atan2(-to.z, to.x), 0.0)
		return true)
	if missile_art != "" and W3Model.has_model(missile_art) and not W3Model.is_cached(missile_art):
		W3Model.preload_paths([missile_art])
	elif missile_art != "" and W3Model.has_model(missile_art) and not W3Fx.skip_fx(missile_art, global_position):
		var mdl := W3Model.create(missile_art)
		n.add_child(mdl)
		mdl.scale = Vector3.ONE * W3Runtime.FX_K * 0.7
		n.look_at(t.global_position + Vector3(0, 1.0, 0), Vector3.UP, true)
		n.set_meta("face", true)
		return
	if W3Vfx.active() and Game.I.camera and Game.I.camera.focus.distance_to(global_position) < 40.0:
		var orb := VfxLib.make("orb", col, false)
		if orb:
			n.add_child(orb)
			orb.scale = Vector3.ONE * 0.8
			VfxLib.start(orb)
			n.set_meta("vfx", true)
			return
	var sm := SphereMesh.new()
	sm.radius = 0.22
	sm.height = 0.44
	Fx.add_mesh(n, sm, Fx.glow_mat(col, 3.0))


# ----------------------------------------------------------------- движение
func move_to(p: Vector3, delta: float) -> bool:
	var to := p - global_position
	to.y = 0.0
	var d := to.length()
	if d < 0.25:
		path.clear()
		return true
	if root_time > 0.0:
		yaw_target = atan2(to.x, to.z)
		play_anim("Idle")
		return false
	var spd := effective_speed()
	var nav := Game.I.nav_of(area)
	var aim := p
	if nav.has_obstacles:
		path_t -= delta
		if path_t <= 0.0 or path.is_empty() or Vector2(path_goal.x - p.x, path_goal.z - p.z).length() > 1.5:
			path_t = 0.45 + randf() * 0.25
			path_goal = p
			if nav.los(global_position, p):
				path = [p]
			else:
				path = nav.find_path(global_position, p)
				if path.is_empty():
					path = [nav.clamp(p)]
		while path.size() > 1 and flat_dist_p(path[0]) < 0.7:
			path.remove_at(0)
		aim = path[0]
	var dv := aim - global_position
	dv.y = 0.0
	var dl := dv.length()
	if dl < 0.05:
		path.clear()
		return d < 0.6
	var dir := dv / dl
	var step := minf(dl, spd * delta)
	var before := global_position
	global_position = nav.slide(global_position, global_position + dir * step)
	if before.distance_to(global_position) < step * 0.2:
		path_t = 0.0  # упёрлись — пересчитать путь
	yaw_target = atan2(dir.x, dir.z)
	play_anim("Run", clampf(spd / 6.5, 0.6, 1.8))
	return d - step < 0.25


func clamp_area(p: Vector3) -> Vector3:
	return Game.I.clamp_to_area(p, area)


func yaw_to(p: Vector3) -> float:
	var d := p - global_position
	return atan2(d.x, d.z)


func _turn(delta: float) -> void:
	rotation.y = lerp_angle(rotation.y, yaw_target, 1.0 - exp(-14.0 * delta))


# ----------------------------------------------------------------- урон и смерть
func take_damage(amount: float) -> float:
	if not alive or invulnerable > 0.0:
		return 0.0
	amount *= dmg_taken_k
	hp -= amount
	if immortal > 0.0 and hp < 1.0:
		hp = 1.0
	if hp <= 0.0:
		hp = 0.0
	return amount


## Невидим для врагов (временная невидимость или постоянная).
func is_invisible() -> bool:
	return invis > 0.0 or perm_invis


func apply_slow(k: float, t: float) -> void:
	slow = maxf(slow if slow_time > 0.0 else 0.0, k)
	slow_time = maxf(slow_time, t)


func apply_stun(t: float) -> void:
	if kind == Kind.BOSS:
		t *= 0.5
	stun = maxf(stun, t)
	swing_left = -1.0
	swing_target = null


func apply_freeze(t: float) -> void:
	apply_stun(t)
	frozen_ice = maxf(frozen_ice, stun)
	if ice_shell == null and model:
		ice_shell = MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = radius + 0.25
		cm.bottom_radius = radius + 0.45
		cm.height = bar_height * 0.85
		cm.radial_segments = 6
		ice_shell.mesh = cm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.7, 0.9, 1.0, 0.45)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 0.1
		m.metallic_specular = 1.0
		m.emission_enabled = true
		m.emission = Color(0.4, 0.7, 1.0)
		m.emission_energy_multiplier = 0.4
		ice_shell.material_override = m
		ice_shell.position.y = cm.height / 2.0
		add_child(ice_shell)


func apply_poison(src: Unit, dps: float, t: float) -> void:
	if dps * t > dot_dps * dot_time:
		dot_dps = dps
		dot_time = t
		dot_src = src


func die() -> void:
	alive = false
	death_time = 0.0
	swing_left = -1.0
	order = "idle"
	target_unit = null
	dot_time = 0.0
	if anim:
		anim.speed_scale = 1.0
	play_anim("Death", 1.0, true)
	if ring:
		ring.visible = false
	if ice_shell:
		ice_shell.queue_free()
		ice_shell = null


func _dead_process(delta: float) -> void:
	death_time += delta
	if kind == Kind.CREEP or kind == Kind.BOSS:
		if death_time > 2.5:
			position.y -= delta * 1.2
		if death_time > 4.0:
			queue_free()


# ----------------------------------------------------------------- ИИ крипов
func creep_think() -> void:
	if kind == Kind.BOSS and has_meta("ncd_boss"):
		NcdFx.boss_think(self)
	if area == -1:
		return
	if neutral:
		_neutral_think()
		return
	if area < 0:
		return
	var zone: Zone = Game.I.zones[home_zone]
	var crystal: Unit = Game.I.teams[home_zone].crystal
	if order == "attack" and valid_target(target_unit) and target_unit.kind != Kind.CRYSTAL:
		var leash := zone.to_local(global_position).distance_to(zone.to_local(target_unit.global_position))
		if leash < 16.0:
			return
	var aggro := 10.0 if kind == Kind.BOSS else 8.5
	var t := Game.I.nearest_enemy(global_position, aggro, self)
	if t:
		order = "attack"
		target_unit = t
		return
	if crystal and crystal.alive:
		var dc := flat_dist(crystal) - crystal.radius - radius
		if dc <= attack_range + 0.3:
			order = "crystal"
			target_unit = crystal
			return
		var lane: Array = zone.lanes[lane_id]
		while lane_index < lane.size() - 1 and flat_dist_p(lane[lane_index]) < 3.0:
			lane_index += 1
		var p: Vector3 = lane[lane_index]
		if lane_index == lane.size() - 1:
			p = crystal.global_position
		order = "move"
		target_point = p + Vector3(sin(get_instance_id() * 0.7), 0, cos(get_instance_id() * 1.3)) * 1.5
	else:
		order = "idle"


## Лесной монстр: стоит в лагере, нападает на подошедших героев, далеко не уходит.
func _neutral_think() -> void:
	var home_d := flat_dist_p(home_pos)
	if order == "home":
		if home_d < 1.5:
			order = "idle"
			# лесные боссы, вернувшись на место, не лечатся: увести и «сбросить» их нельзя
			if kind != Kind.BOSS:
				hp = max_hp
		return
	if home_d > n_leash:
		order = "home"
		issue_move(home_pos)
		order = "home"
		target_point = home_pos
		return
	if order == "attack" and valid_target(target_unit) and target_unit.flat_dist_p(home_pos) < n_leash + 1.0:
		return
	var t := Game.I.nearest_enemy(global_position, n_aggro, self)
	if t and t.flat_dist_p(home_pos) < n_leash - 1.0:
		order = "attack"
		target_unit = t
	elif home_d > 2.5:
		order = "move"
		target_point = home_pos
	else:
		order = "idle"


func _brain_crystal(delta: float) -> void:
	var c := target_unit
	if c == null or not is_instance_valid(c) or not c.alive:
		order = "idle"
		return
	if flat_dist(c) - c.radius - radius > attack_range + 0.5:
		move_to(c.global_position, delta)
		return
	yaw_target = yaw_to(c.global_position)
	if swing_left < 0.0 and attack_timer <= 0.0:
		attack_timer = effective_attack_cd()
		play_anim("Attack", 1.0, true)
		Game.I.deal_damage(self, c, damage_value(), "attack")
	elif attack_timer > 0.0 and not anim_busy():
		play_anim("Idle")

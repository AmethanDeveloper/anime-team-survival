class_name W3Unit
extends Unit
## Юнит, созданный триггерами карты: манекен с моделью эффекта (Aloc) или призванное существо.

var rt: W3Runtime = null
var type_id := 0
var udata: Dictionary = {}
var dummy := true
var is_hero_type := false
var owner_unit: Unit = null
var w3m: W3Model = null
var hero_model := ""
var timed_life := -1.0
var timed_paused := false
var fly_h := 0.0
var base_scale := 1.0
var default_speed := 0.0
var move_goal := Vector3.INF
var dying_t := -1.0
var time_k := 1.0
## Клон-герой (Куруми, Ёсинон, демоны Юу…): уровень и характеристики задают триггеры карты.
var w3_level := 1
var stats := {"str": 0.0, "agi": 0.0, "int": 0.0}
var base_hp := 100.0
var base_dmg := 10.0
var base_armor := 0.0
## Получил приказ игрока (ПКМ, A, S, H) — слушается его, а не только бьёт ближайших.
var manual := false
## Манекен-снаряд триггеров: если быстро летит — его модель заменяется готовым снарядом (W3Vfx).
var _vfx_prev := Vector3.INF
var _vfx_fast := 0.0
var _vfx_done := false


static func make(r: W3Runtime, tid: int, p, pos: Vector3, face: float, ud_override := {}) -> W3Unit:
	var u := W3Unit.new()
	u.rt = r
	u.type_id = tid
	var key := W3Runtime.fcc_str(tid)
	u.udata = ud_override if not ud_override.is_empty() else (r.data.get("units", {}) as Dictionary).get(key, {})
	u.dummy = u.udata.is_empty() or bool(u.udata.get("dummy", false))
	u.is_hero_type = key.substr(0, 1) == key.substr(0, 1).to_upper() and key.substr(0, 1) != key.substr(0, 1).to_lower()
	var d := r._d(u)
	d.player = p
	d.type = tid
	if p is W3Runtime.JPlayer:
		u.team = p.team
		u.owner_unit = p.hero if p.hero != null and is_instance_valid(p.hero) else null
	u.area = u.owner_unit.area if u.owner_unit else -99
	u.display_name = str(u.udata.get("name", key))
	u.kind = Unit.Kind.CREEP
	var parent: Node = Game.I if Game.I else r
	parent.add_child(u)
	u.global_position = pos
	r.set_facing(u, face)
	u._build_model()
	if u.dummy:
		u.add_to_group("w3_dummy")
		u.invulnerable = 1e9
		u.radius = 0.0
		u.bar_height = -100.0
	else:
		u._setup_summon()
		if u.model == null and W3Model.norm_key(str(u.udata.get("model", ""))).ends_with("dummy"):
			# невидимый юнит «системы кастеров» карты (e01C): без полоски здоровья, не толкается и не выбирается
			u.bar_height = -100.0
			u.radius = 0.0
	return u


func _build_model() -> void:
	var path: String = udata.get("model", "")
	var k := W3Model.norm_key(path)
	var sc := float(udata.get("scale", 1.0))
	var hm: Dictionary = rt.data.get("hero_models", {})
	if hm.has(k):
		hero_model = hm[k]
		var m: Node3D = HeroAssets.model_scene(hero_model).instantiate()
		var info := HeroAssets.fit_model(m, hero_model, 2.7)
		attach_model(m, info.anim_map)
		base_scale = m.scale.x * sc
		m.scale = Vector3.ONE * base_scale
		if anim:
			anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
		return
	if k == "" or k.ends_with("dummy") or k == "_":
		return
	w3m = W3Model.create(path)
	add_child(w3m)
	base_scale = W3Runtime.FX_K * sc
	w3m.scale = Vector3.ONE * base_scale
	model = w3m
	if w3m.fallback and dummy:
		W3Fx.fallback_fx(rt, path, global_position, base_scale)
		_fallback_visual(k, sc)


## Модели нет ни в карте, ни в извлечённых файлах: светящийся сгусток цвета способности,
## чтобы снаряды и волны из триггеров были видны.
func _fallback_visual(k: String, sc: float) -> void:
	if Game.I and Game.I.sim:
		return
	var col := Color(0.9, 0.85, 1.0)
	if owner_unit is Hero:
		col = Color((owner_unit as Hero).def.color).lightened(0.25)
	for kw in [["fire", Color(1.0, 0.5, 0.15)], ["ice", Color(0.55, 0.85, 1.0)], ["frost", Color(0.55, 0.85, 1.0)],
			["blood", Color(0.9, 0.1, 0.12)], ["dark", Color(0.55, 0.2, 0.8)], ["black", Color(0.45, 0.1, 0.6)],
			["light", Color(1.0, 0.9, 0.5)], ["water", Color(0.3, 0.6, 1.0)]]:
		if k.contains(kw[0]):
			col = kw[1]
			break
	var m := Fx.add_mesh(self, SphereMesh.new(), Fx.glow_mat(col, 3.0, true, 0.75))
	m.scale = Vector3.ONE * clampf(0.5 * sc, 0.3, 1.6)
	m.position.y = 0.9


func _setup_summon() -> void:
	max_hp = maxf(1.0, float(udata.get("hp", 100.0)))
	hp = max_hp
	max_mp = float(udata.get("mp", 0.0))
	mp = max_mp
	base_damage = float(udata.get("damage", 10.0)) * W3Runtime.DMG_K
	armor = float(udata.get("armor", 0.0))
	base_hp = max_hp
	base_dmg = base_damage
	base_armor = armor
	move_speed = float(udata.get("speed", 250.0)) / 46.0
	default_speed = move_speed
	attack_range = clampf(float(udata.get("range", 100.0)) / 60.0, 1.6, 12.0)
	ranged = float(udata.get("range", 100.0)) > 300.0
	attack_cd = maxf(0.3, float(udata.get("cool", 1.5)))
	radius = 0.6
	bounty_gold = 0.0
	bounty_xp = 0.0
	if Game.I:
		Game.I.units.append(self)
	order = "idle"


func _ready() -> void:
	add_to_group("w3_tracked")


func set_level(l: int) -> void:
	w3_level = maxi(1, l)


func set_stat(k: String, v: float) -> void:
	stats[k] = maxf(0.0, v)
	if dummy:
		return
	# как у героя игры: здоровье от силы, урон от главной характеристики, броня от ловкости
	var prim := "str"
	if owner_unit is Hero:
		prim = str((owner_unit as Hero).def.get("primary", "str"))
	var k_hp := hp / maxf(max_hp, 1.0)
	max_hp = base_hp + float(stats.str) * Data.STR_HP
	hp = clampf(max_hp * k_hp, 1.0, max_hp)
	base_damage = base_dmg + float(stats.get(prim, 0.0))
	armor = base_armor + float(stats.agi) * Data.AGI_ARMOR


## Призванный герою игрока юнит: слушается его приказов вместе с героем.
func player_squad() -> bool:
	return not dummy and alive and owner_unit != null and is_instance_valid(owner_unit) and owner_unit is Hero \
		and (owner_unit as Hero).is_player and not w3_paused and move_speed > 0.0


# ------------------------------------------------------------------ поведение
func creep_think() -> void:
	if manual:
		# приказ игрока: идёт и бьёт, куда сказали; без дела — как в WC3, бьёт врагов рядом
		match order:
			"move", "attack_move", "hold", "cast":
				return
			"attack":
				if valid_target(target_unit):
					return
		var t0 := Game.I.nearest_enemy(global_position, acquire_range(), self) if Game.I else null
		if t0:
			order = "attack"
			target_unit = t0
		elif owner_unit and is_instance_valid(owner_unit) and flat_dist(owner_unit) > 24.0:
			issue_move(owner_unit.global_position)
		else:
			order = "idle"
		return
	# призванный юнит: бьёт ближайших врагов, иначе держится хозяина
	var t := Game.I.nearest_enemy(global_position, 12.0, self) if Game.I else null
	if t:
		if order != "attack" or not valid_target(target_unit):
			order = "attack"
			target_unit = t
	elif owner_unit and is_instance_valid(owner_unit) and flat_dist(owner_unit) > 6.0:
		issue_move(owner_unit.global_position)


func _physics_process(delta: float) -> void:
	var dt := delta
	if timed_life > 0.0 and not timed_paused and alive:
		timed_life -= dt
		if timed_life <= 0.0:
			w3_die(null)
			return
	if dying_t >= 0.0:
		dying_t -= dt
		if dying_t < 0.0:
			_cleanup()
		return
	if model:
		model.position.y = model_base_pos.y + fly_h
	if not dummy:
		if w3_paused:
			return
		super._physics_process(delta)
		return
	if move_goal != Vector3.INF:
		var to := move_goal - global_position
		to.y = 0.0
		var step := maxf(move_speed, 4.0) * dt
		if to.length() <= step:
			global_position = move_goal
			move_goal = Vector3.INF
		else:
			global_position += to.normalized() * step
			rotation.y = atan2(to.x, to.z)
	if w3m and not _vfx_done:
		if _vfx_prev != Vector3.INF:
			var sp := Vector2(global_position.x - _vfx_prev.x, global_position.z - _vfx_prev.z).length() / maxf(dt, 0.001)
			_vfx_fast = _vfx_fast + dt if sp > 9.0 else maxf(0.0, _vfx_fast - dt)
			if _vfx_fast > 0.07:
				_vfx_done = true
				W3Vfx.make_projectile(w3m)
		_vfx_prev = global_position


func _process(_delta: float) -> void:
	pass


func w3_set_pos(p: Vector3) -> void:
	if dummy:
		global_position = p
	else:
		var q := p
		if Game.I and area != -99:
			q = Game.I.clamp_to_area(p, area)
		global_position = q


func w3_move_to(p: Vector3) -> void:
	if dummy:
		move_goal = p
	else:
		issue_move(p)


func w3_time_scale(k: float) -> void:
	time_k = k
	if w3m:
		w3m.set_time_scale(k)
	elif anim:
		anim.speed_scale = k


func w3_scale(k: float) -> void:
	var s := maxf(0.01, k) * (base_scale if not hero_model.is_empty() else base_scale)
	if model:
		model.scale = Vector3.ONE * s


func w3_die(killer: Unit) -> void:
	if not alive:
		return
	if illusion:
		if Game.I:
			Game.I.units.erase(self)
		alive = false
		if rt:
			rt.on_unit_death(self, killer)
			W3Abil.fx_at(rt, "Abilities\\Spells\\Orc\\MirrorImage\\MirrorImageDeathCaster.mdl", global_position)
		_cleanup()
		return
	alive = false
	if not dummy and Game.I:
		Game.I.units.erase(self)
	if rt:
		rt.on_unit_death(self, killer)
	var t := 0.0
	if w3m and is_instance_valid(w3m):
		if w3m.play("death", 0):
			t = w3m.cur_len
		else:
			w3m.destroy_fx()
			t = 0.6
	elif anim:
		var n := W3Model.pick_anim(Array(anim.get_animation_list()), "death")
		if n != "":
			anim.play(n)
			t = anim.get_animation(n).length
	dying_t = minf(t, 3.0)
	if dying_t <= 0.0:
		dying_t = 0.0


func w3_remove() -> void:
	alive = false
	if not dummy and Game.I:
		Game.I.units.erase(self)
	_cleanup()


func _cleanup() -> void:
	if w3m and is_instance_valid(w3m):
		# частицы эффекта досыпаются отдельно
		var keep_t := w3m._max_life()
		if keep_t > 0.05 and w3m.emitters.size() > 0 and rt and rt.fx_parent:
			var gp := w3m.global_transform
			remove_child(w3m)
			rt.fx_parent.add_child(w3m)
			w3m.global_transform = gp
			w3m.destroy_fx()
			w3m = null
	queue_free()


func die() -> void:
	# смерть от урона игры (для призванных)
	if rt and alive:
		alive = false
		rt.on_unit_death(self, null)
	super.die()
	if illusion:
		# иллюзия рассеивается сразу
		if rt:
			W3Abil.fx_at(rt, "Abilities\\Spells\\Orc\\MirrorImage\\MirrorImageDeathCaster.mdl", global_position)
		visible = false
		dying_t = 0.0


# ------------------------------------------------------------------ общие помощники для любых юнитов
## Анимация WC3 по имени ("spell channel", "attack 2") для юнита игры или манекена.
static func anim_on(u: Unit, q: String, queued: bool) -> void:
	if (u is W3Unit and (u as W3Unit).w3m) or u.model is W3Model:
		var m: W3Model = (u as W3Unit).w3m if u is W3Unit and (u as W3Unit).w3m else u.model as W3Model
		if queued:
			var n := m.find_anim(q)
			if n != "":
				m.queue.append(n)
		else:
			m.queue.clear()
			if m.play(q) and not (u is W3Unit):
				# тело героя или босса из модели карты: движок юнита не перебивает анимацию заклинания
				u.cur_anim = "w3:" + m.cur
				u.w3_anim_lock = 0.0 if m.cur_loop else minf(m.cur_len, 2.5)
		return
	var ap := u.anim
	if ap == null:
		return
	var n2 := W3Model.pick_anim(Array(ap.get_animation_list()), q)
	if n2 == "":
		return
	var a := ap.get_animation(n2)
	var looping := q.to_lower().begins_with("stand") or q.to_lower().begins_with("walk")
	a.loop_mode = Animation.LOOP_LINEAR if looping else Animation.LOOP_NONE
	if queued and ap.is_playing():
		ap.queue(n2)
	else:
		ap.play(n2, 0.1)
		ap.seek(0.0, true)
	u.cur_anim = "w3:" + n2
	u.w3_anim_lock = 0.0 if looping else a.length / maxf(0.1, absf(ap.speed_scale))


static func set_alpha(u: Node, a: float) -> void:
	for c in u.get_children():
		if c is GeometryInstance3D:
			(c as GeometryInstance3D).transparency = 1.0 - a
		set_alpha(c, a)

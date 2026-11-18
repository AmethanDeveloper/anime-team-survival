class_name NcdFx
## Боссы, крипы и Мадара из карты NCD 6.9 (данные — res://w3/ncd_data.json, модели — w3_fx_ncd.json).
## В NCD большую часть зрелищных навыков делают триггеры; их мы не переносим, а повторяем здесь:
## метеор Мадары, Гока Мэккяку (огненная волна), Мокутон (деревья из земли), удар Совершенного Сусаноо,
## дождь снарядов (Cluster Rockets: птицы Дейдары, огонь Какузу). Плюс ИИ боссов: когда и что применять.

const U := W3Runtime.U
const FX_K := W3Runtime.FX_K
## Модели карты: юнит размера 1.0 в WC3 ростом ~1.8 м по модели; герои игры — 2.7 м.
const BODY_K := 0.78


static func data() -> Dictionary:
	var rt := W3Runtime.I
	return rt.data.get("ncd", {}) if rt else {}


# ------------------------------------------------------------------ тело из модели карты
## Видимая высота модели в стойке (части, скрытые в «stand», не считаются: у Обито Рикудо в модели
## спрятан огромный шар).
static func stand_height(wm: W3Model) -> float:
	if wm.scene_root == null:
		return 0.0
	var ga: Dictionary = wm.info.get("geo_alpha", {})
	var stand := W3Model.pick_anim(wm.anim_names(), "stand")
	var out := AABB()
	var first := true
	for n in wm.scene_root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var per: Dictionary = ga.get(str(mi.name), {})
		if per.has(stand):
			var vis := 1.0
			for tr in per[stand]:
				vis *= W3Model._track_val(tr, 0.0, 1.0)
			if vis < 0.05:
				continue
		var xf := Transform3D.IDENTITY
		var p: Node = mi
		var chain: Array[Node3D] = []
		while p and p != wm:
			if p is Node3D:
				chain.push_front(p)
			p = p.get_parent()
		for c in chain:
			xf = xf * c.transform
		var bb := xf * mi.get_aabb()
		if first:
			out = bb
			first = false
		else:
			out = out.merge(bb)
	return out.size.y


## Тело юнита из модели карты: рост — по масштабу юнита в карте, в пределах [min_h, max_h] метров.
static func attach_body(u: Unit, path: String, model_scale: float, min_h: float, max_h: float) -> W3Model:
	var wm := W3Model.create(path)
	if wm.fallback or wm.scene_root == null:
		wm.free()
		return null
	var h := maxf(stand_height(wm), 0.05)
	var s := FX_K * BODY_K * model_scale
	var real_h := clampf(h * s, min_h, max_h)
	wm.scale = Vector3.ONE * (real_h / h)
	u.attach_model(wm, W3Abil._w3_anim_map(wm))
	u.bar_height = real_h + 0.5
	return wm


# ------------------------------------------------------------------ боссы
const NAMES := {
	"H021": "Кисамэ Хошигаки", "E054": "Итачи Учиха", "E057": "Дейдара", "E056": "Сасори", "H023": "Хидан",
	"H024": "Какузу", "H02B": "Конан", "E05N": "Пейн: Путь Дэвы", "E05M": "Тоби", "H022": "Зецу",
	"E05U": "Статуя Гедо", "E027": "Кабуто: мудрец Белой змеи", "E05I": "Мадара (Эдо Тэнсэй)",
	"H02A": "Му, Второй Цучикагэ", "E05J": "Обито Учиха", "E05K": "Мадара Учиха", "E05T": "Десятихвостый",
	"E05L": "Обито: Мудрец Шести Путей", "E06W": "Мадара: Мудрец Шести Путей", "E06V": "Кагуя Ооцуцуки",
}
## Сила босса относительно обычного босса волны (здоровье и урон)
const POWER := {"E05U": 1.5, "E05T": 1.6, "E05L": 1.3, "E06W": 1.5, "E06V": 1.7, "E05K": 1.25, "E05J": 1.15}


## Пара боссов волны (как в NCD: по одному на каждую тропу). k — номер волны с боссом от 1.
static func wave_bosses(k: int) -> Array:
	var w: Array = data().get("boss_waves", [])
	if w.is_empty():
		return []
	return w[(k - 1) % w.size()]


static func boss_name(tid: String) -> String:
	var ud: Dictionary = W3Abil.udata_of(W3Runtime.I, tid)
	return str(NAMES.get(str(ud.get("ncd", "")), ud.get("proper", ud.get("name", "Босс"))))


## Превращает созданного игрой босса в босса NCD: модель, атака, способности.
static func setup_boss(u: Unit, tid: String, k: int, huge := false) -> bool:
	var rt := W3Runtime.I
	if rt == null:
		return false
	var ud: Dictionary = W3Abil.udata_of(rt, tid)
	if ud.is_empty():
		return false
	var big := huge or tid in ["E05U", "E05T"] or str(ud.get("ncd", "")) in ["E05U", "E05T"]
	var wm := attach_body(u, str(ud.model), float(ud.get("scale", 1.0)) * 1.3, 3.6, 9.5 if big else 6.0)
	if wm == null:
		return false
	var ncd := str(ud.get("ncd", ""))
	var pw := float(POWER.get(ncd, 1.0)) * (1.0 + 0.35 * float((k - 1) / maxi(1, (data().get("boss_waves", []) as Array).size())))
	u.max_hp *= pw
	u.hp = u.max_hp
	u.base_damage *= pw
	u.display_name = boss_name(tid)
	var rng := float(ud.get("range", 100.0))
	u.ranged = rng >= 300.0
	u.attack_range = clampf(rng * U * 0.6, 6.0, 11.0) if u.ranged else 2.6
	if u.ranged:
		u.proj_color = Color(1.0, 0.35, 0.3)
	var mis := str(ud.get("missile", ""))
	if mis != "" and mis != "_":
		u.missile_art = mis
	u.attack_cd = clampf(float(ud.get("cool", 1.7)), 1.0, 2.4)
	u.magic_resist = 0.2
	u.radius = clampf(0.5 + wm.scale.x * 0.2, 1.0, 2.6 if big else 1.6)
	var d := rt._d(u)
	d.type = W3Runtime.fcc(tid)
	d.player = rt.players[12]
	var ab: Dictionary = d.abils
	for s in (ud.get("abilities", []) as Array) + (ud.get("hero_abilities", []) as Array):
		ab[W3Runtime.fcc(str(s))] = 1
	# числа NCD огромны: урон способностей приводится к атаке босса в игре
	d["spell_k"] = u.base_damage / maxf(1.0, float(ud.get("damage", 1.0))) * 1.4
	u.set_meta("ncd_boss", tid)
	# тёмно-красный круг под ногами — сразу видно, что это босс
	var ring := MeshInstance3D.new()
	ring.mesh = Fx.flat_ring_mesh(u.radius + 0.3, u.radius + 1.6)
	ring.material_override = Fx.glow_mat(Color(0.9, 0.1, 0.15), 2.5, true, 0.55)
	ring.position.y = 0.08
	u.add_child(ring)
	return true


## Белый Зецу — обычный монстр волны.
static func setup_creep(u: Unit) -> bool:
	var rt := W3Runtime.I
	var tid := str(data().get("creep", ""))
	if rt == null or tid == "":
		return false
	var ud: Dictionary = W3Abil.udata_of(rt, tid)
	if attach_body(u, str(ud.get("model", "")), 1.0, 2.2, 2.6) == null:
		return false
	u.display_name = "Белый Зецу"
	u.bar_height = 2.5
	return true


# ------------------------------------------------------------------ ИИ боссов
const SKIP := ["ANss", "AInv", "AIat", "Aoar", "AIsr", "AIva", "AOre", "AOcr", "ANca", "AEev", "AHbh", "Aroc", "AEar",
	"Aloc", "ANcl"]


## Раз в несколько секунд босс применяет одну из своих способностей NCD по ближайшему врагу.
static func boss_think(u: Unit) -> void:
	var rt := W3Runtime.I
	if rt == null or Game.I == null or not u.alive or u.stun > 0.0 or u.silence > 0.0 or u.cast_lock > 0.0 or u.w3_paused:
		return
	var d := rt._d(u)
	var now := Game.I.time
	if float(d.get("next_cast", 0.0)) > now:
		return
	var tgt := Game.I.nearest_enemy(u.global_position, 16.0, u)
	if tgt == null:
		return
	var cds: Dictionary = d.get("cds", {})
	d["cds"] = cds
	var dist := u.flat_dist(tgt)
	var opts: Array = []
	for id in d.abils:
		var ad := W3Abil.adata(rt, id)
		var code := str(ad.get("code", ""))
		if code in SKIP or code in W3Abil.PASSIVE_T or float(cds.get(id, 0.0)) > now:
			continue
		var lv := W3Abil.lvdata(ad, 1)
		var kind := W3Abil.target_of(code, lv)
		var rng := clampf(float(lv.get("rng", 600.0)) * U, 5.0, 16.0)
		var ok := true
		match kind:
			"unit", "point":
				ok = dist <= rng
			_:
				match code:
					"AOws", "AHtc", "AUfn", "AEsf":
						ok = dist <= clampf(float(lv.get("area", 300.0)) * U, 4.0, 10.0)
					"AOmi":
						ok = u.hp < u.max_hp * 0.85
					_:
						ok = dist <= 10.0
		if ok:
			opts.append([id, kind, lv, code])
	if opts.is_empty():
		d["next_cast"] = now + 1.0
		return
	var pick: Array = opts[randi() % opts.size()]
	var lv2: Dictionary = pick[2]
	cds[pick[0]] = now + maxf(7.0, float(lv2.get("cool", 8.0)) * 1.4)
	d["next_cast"] = now + 3.0
	u.yaw_target = u.yaw_to(tgt.global_position)
	u.rotation.y = u.yaw_target
	u.cast_lock = 0.7
	u.swing_left = -1.0
	var anim_q := str((W3Abil.adata(rt, pick[0]).get("art", {}) as Dictionary).get("anim", "spell")).replace(",", " ")
	W3Unit.anim_on(u, anim_q if anim_q.strip_edges() != "" else "spell", false)
	W3Abil.cast_base(rt, u, pick[0], 1, tgt if pick[1] == "unit" else null, tgt.global_position)


# ------------------------------------------------------------------ свои навыки (вместо триггеров NCD)
static func cast(rt: W3Runtime, c: Unit, kind: String, ad: Dictionary, lv: Dictionary, a: float, tu: Unit, p: Vector3) -> bool:
	match kind:
		"meteor":
			meteor(rt, c, ad, lv, a, p)
		"goka":
			goka(rt, c, ad, lv, a, p)
		"wood":
			wood(rt, c, ad, lv, a, p)
		"susanoo_slash":
			susanoo_slash(rt, c, ad, lv, a, p)
		"fireball":
			fireball(rt, c, ad, lv, a, p)
		"crow_blink":
			crow_blink(rt, c, ad, lv, p)
		"tsukuyomi":
			if tu == null:
				return false
			tsukuyomi(rt, c, ad, lv, a, tu)
		"sharingan":
			sharingan(rt, c, lv)
		_:
			return false
	return true


## Модель эффекта NCD; далеко от камеры — пустышка без картинки (логика способности та же, рисовать незачем).
static func _vis(path: String, pos: Vector3) -> W3Model:
	if Game.I and not Game.I.sim:
		var dx := pos.x - W3Model.cam_pos.x
		var dz := pos.z - W3Model.cam_pos.z
		if dx * dx + dz * dz > W3Model.cam_r2:
			var e := W3Model.new()
			e.key = W3Model.norm_key(path)
			e.fallback = true
			e.skipped = true
			return e
	return W3Model.create(path)


static func _model_at(rt: W3Runtime, path: String, pos: Vector3, k: float) -> W3Model:
	var m := _vis(path, pos)
	rt.fx_parent.add_child(m)
	m.global_position = pos
	m.scale = Vector3.ONE * FX_K * k
	return m


## Модели, которые рисуют способности NCD (их грузим заранее, до первого каста)
const FX_MODELS := ["war3mapImported\\katongoukamekkyaku体.mdl", "war3mapImported\\flamebomb体.mdl",
	"war3mapImported\\shutu体.mdl", "war3mapImported\\madarasusanoo.mdl", "war3mapImported\\meteor体.mdl",
	"Abilities\\Weapons\\AncientProtectorMissile\\AncientProtectorMissile.mdl",
	"Abilities\\Spells\\Other\\Stampede\\StampedeMissileDeath.mdl"]


static func _shake(pos: Vector3, k: float) -> void:
	if Game.I and Game.I.camera and Game.I.camera.focus.distance_to(pos) < 40.0:
		Game.I.camera.shake(k)


## Тэнгай Синсэй / Метеор: огромный камень падает с неба, взрыв огня по области, оглушение.
static func meteor(rt: W3Runtime, c: Unit, ad: Dictionary, lv: Dictionary, a: float, p: Vector3) -> void:
	var art: Dictionary = ad.get("art", {})
	var r := clampf(float(lv.get("area", 600.0)) * U, 4.0, 11.0)
	var fall := 1.3
	if Game.I and c.area != -99:
		p = Game.I.clamp_to_area(p, c.area)
	Fx.ring_burst(Game.I.fx_root, p, r, Color(1.0, 0.45, 0.15), fall, 0.5)
	var rock := _model_at(rt, str(art.get("missile", "war3mapImported\\meteor体.mdx")), p + Vector3(-r * 0.8, 26.0, r * 0.5), 0.7 + r * 0.06)
	if rock.find_anim("stand") != "":
		rock.play("stand")
	var tw := rock.create_tween()
	tw.tween_property(rock, "global_position", p, fall).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_property(rock, "rotation:x", 2.5, fall)
	rt.get_tree().create_timer(fall, false).timeout.connect(func() -> void:
		if is_instance_valid(rock):
			rock.destroy_fx()
		var boom := _model_at(rt, str(art.get("effect", "war3mapImported\\t_explosionbig体.mdx")), p, 1.6)
		boom.destroy_fx()
		for k in 6:
			var ang := TAU * k / 6.0
			W3Abil.fx_at(rt, "war3mapImported\\FireStomp体.mdx", p + Vector3(cos(ang), 0, sin(ang)) * r * 0.6)
		_shake(p, 0.9)
		Audio.sfx("boss_roar", p, 0.5, 0.1, 0.0)
		if c == null or not is_instance_valid(c):
			return
		for e in W3Abil.enemies(rt, c, p, r):
			W3Abil.dmg(rt, c, e, a)
			W3Abil.stun(rt, e, 1.5 if not (e is Hero) else 1.0)
			var push: Vector3 = e.global_position - p
			push.y = 0.0
			if push.length() > 0.1:
				e.knock = push.normalized() * 9.0)


## Единица WC3 → метры игры: герои игры (2.7 м) меньше героев WC3 (~3.7 м), поэтому × 0.75.
const WK := W3Runtime.U * 0.75
## Размер языков пламени Гока Мэккяку относительно модели карты (подбирается по превью)
const GOKA_K := 0.75


## Каждый кадр зовёт f(t, dt); f возвращает false — конец.
class Ticker extends Node:
	var f: Callable
	var t := 0.0

	func _physics_process(dt: float) -> void:
		t += dt
		if not f.call(t, dt):
			queue_free()


static func _ticker(rt: W3Runtime, f: Callable) -> void:
	var tk := Ticker.new()
	tk.f = f
	rt.fx_parent.add_child(tk)


static func _dir_to(c: Unit, p: Vector3) -> Vector3:
	var dir := p - c.global_position
	dir.y = 0.0
	if dir.length() < 0.2:
		dir = Vector3(sin(c.rotation.y), 0, cos(c.rotation.y))
	return dir.normalized()


## Катон: Гока Мэккяку — как в NCD: пять огненных шаров веером (0°, ±7.5°, ±15°) летят на 1200 единиц
## за 0.72 с и оставляют за собой облако пламени; в конце пути — взрывы. Каждый враг получает урон один раз.
static func goka(rt: W3Runtime, c: Unit, ad: Dictionary, lv: Dictionary, a: float, p: Vector3) -> void:
	var cp := c.global_position
	var dir := _dir_to(c, p)
	var start := cp + dir * 50.0 * WK + Vector3(0, 20.0 * WK, 0)
	var models: Array = []
	var dirs: Array = []
	for ang in [0.0, 7.5, 15.0, -7.5, -15.0]:
		var d2 := dir.rotated(Vector3.UP, deg_to_rad(ang))
		var m := _vis("war3mapImported\\katongoukamekkyaku体.mdl", start)
		rt.fx_parent.add_child(m)
		m.global_position = start
		m.scale = Vector3.ONE * FX_K * 1.2 * GOKA_K
		m.set_particle_cap(70)
		m.rotation.y = atan2(d2.x, d2.z)
		models.append(m)
		dirs.append(d2)
	var hit := {}
	var spd := 1667.0 * WK
	var total := 1200.0 * WK
	var bombs := [0]
	var burn := a * 0.1
	var k_sp := float(rt._d(c).get("spell_k", 1.0)) if c.has_meta("w3") else 1.0
	var src := rt.credit_of(c)
	var wc: WeakRef = weakref(c)
	_ticker(rt, func(t: float, _dt: float) -> bool:
		var dist := minf(t * spd, total)
		var cc := wc.get_ref() as Unit
		for i in models.size():
			var m: W3Model = models[i]
			if not is_instance_valid(m):
				continue
			var pos: Vector3 = start + dirs[i] * dist
			m.global_position = pos
			if cc != null and cc.alive:
				for e in W3Abil.enemies(rt, cc, pos, (150.0 + dist / WK / 7.0) * WK):
					if not hit.has(e):
						hit[e] = true
						W3Abil.dmg(rt, cc, e, a)
						e.apply_poison(src, burn * W3Runtime.DMG_K * k_sp, 3.0)
			if dist >= 900.0 * WK and bombs[0] < 10 and randf() < 0.45:
				bombs[0] += 1
				W3Abil.fx_at(rt, "war3mapImported\\flamebomb体.mdx", pos)
		if dist >= total:
			for m in models:
				if is_instance_valid(m):
					(m as W3Model).destroy_fx()
			return false
		return true)
	_shake(cp, 0.35)


## Мокутон, как в NCD: перед Мадарой из земли вырываются корни (shutu), волна идёт вперёд на 600 единиц;
## пять раз бьёт всех врагов в радиусе 300 и первые 300 единиц тащит задетых вперёд; посередине — второй,
## меньший взрыв корней.
static func wood(rt: W3Runtime, c: Unit, ad: Dictionary, lv: Dictionary, a: float, p: Vector3) -> void:
	var cp := c.global_position
	var dir := _dir_to(c, p)
	var face := atan2(dir.x, dir.z)
	_roots(rt, cp + dir * 80.0 * WK, face, 0.8)
	W3Abil.fx_at(rt, "Abilities\\Weapons\\AncientProtectorMissile\\AncientProtectorMissile.mdl", cp + dir * 80.0 * WK)
	var grabbed := {}
	var wc: WeakRef = weakref(c)
	var done := [0, false]
	var per := a / 3.0
	_ticker(rt, func(t: float, dt: float) -> bool:
		var cc := wc.get_ref() as Unit
		var dist := minf(t * 833.0, 600.0)
		var pos := cp + dir * (100.0 + dist) * WK
		# импульсы на 50, 150, 250, 350, 450 единиц пути
		while done[0] < 5 and dist >= 50.0 + 100.0 * done[0]:
			done[0] += 1
			if cc != null and cc.alive:
				for e in W3Abil.enemies(rt, cc, pos, 300.0 * WK):
					grabbed[e] = true
					W3Abil.dmg(rt, cc, e, per)
					W3Abil.fx_on(rt, "Abilities\\Spells\\Other\\Stampede\\StampedeMissileDeath.mdl", e, "chest")
			if done[0] == 3 and not done[1]:
				done[1] = true
				_roots(rt, pos, face, 0.4)
		# первые 300 единиц корни тащат задетых вперёд
		if dist < 300.0:
			for e in grabbed:
				if is_instance_valid(e) and (e as Unit).alive and not ((e as Unit) is Hero and (e as Unit).invulnerable > 0.0):
					var u := e as Unit
					var np := u.global_position + dir * 500.0 * WK * dt
					if Game.I and u.area != -99:
						np = Game.I.clamp_to_area(np, u.area)
					u.global_position = np
					if randf() < 0.05:
						W3Abil.fx_at(rt, "Abilities\\Weapons\\AncientProtectorMissile\\AncientProtectorMissile.mdl", np)
		return dist < 600.0)
	_shake(cp, 0.25)


## Взрыв корней из земли (модель shutu из NCD): рост на половинной скорости 1 с, потом увядание.
static func _roots(rt: W3Runtime, pos: Vector3, face: float, k: float) -> void:
	var m := _vis("war3mapImported\\shutu体.mdl", pos)
	rt.fx_parent.add_child(m)
	m.global_position = pos
	m.rotation.y = face
	m.scale = Vector3.ONE * FX_K * k * 0.75
	m.play("birth")
	m.set_time_scale(0.5)
	rt.get_tree().create_timer(1.0, false).timeout.connect(func() -> void:
		if is_instance_valid(m):
			m.set_time_scale(1.0)
			m.play("death")
			rt.get_tree().create_timer(2.4, false).timeout.connect(func() -> void:
				if is_instance_valid(m):
					m.destroy_fx()))


## Удар Совершенного Сусаноо: за спиной Мадары встаёт огромный Сусаноо и рубит вперёд по линии.
static func susanoo_slash(rt: W3Runtime, c: Unit, ad: Dictionary, lv: Dictionary, a: float, p: Vector3) -> void:
	var cp := c.global_position
	var dir := p - cp
	dir.y = 0.0
	if dir.length() < 0.2:
		dir = Vector3(sin(c.rotation.y), 0, cos(c.rotation.y))
	dir = dir.normalized()
	var m := _vis("war3mapImported\\madarasusanoo.mdl", cp)
	rt.fx_parent.add_child(m)
	m.global_position = cp - dir * 2.0
	m.rotation.y = atan2(dir.x, dir.z)
	var h := maxf(stand_height(m), 0.05)
	m.scale = Vector3.ONE * (11.0 / h)
	_tint(m, Color(0.45, 0.8, 1.8))   # синее, как Сусаноо Мадары
	m.play("attack")
	var len_line := 24.0
	var width := 7.0
	rt.get_tree().create_timer(0.55, false).timeout.connect(func() -> void:
		_shake(cp, 1.0)
		for k in 8:
			W3Abil.fx_at(rt, "war3mapImported\\darklightning体.mdx", cp + dir * (3.0 + k * 2.8))
		if c == null or not is_instance_valid(c):
			return
		for e in W3Abil.enemies(rt, c, cp + dir * len_line * 0.5, len_line * 0.55):
			var rel: Vector3 = e.global_position - cp
			rel.y = 0.0
			var along: float = rel.dot(dir)
			var side: float = absf(rel.dot(dir.cross(Vector3.UP)))
			if along >= -1.0 and along <= len_line and side <= width * 0.5 + e.radius:
				W3Abil.dmg(rt, c, e, a)
				W3Abil.stun(rt, e, 1.2)
				e.knock = dir * 12.0)
	rt.get_tree().create_timer(2.2, false).timeout.connect(func() -> void:
		if is_instance_valid(m):
			m.destroy_fx())


## Перекрасить модель (копии материалов, общие шаблоны не трогаем).
static func _tint(n: Node, c: Color) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh:
			for i in mi.mesh.get_surface_count():
				var mat := mi.get_active_material(i)
				if mat is BaseMaterial3D:
					var m2 := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
					m2.albedo_color = Color(m2.albedo_color.r * c.r, m2.albedo_color.g * c.g, m2.albedo_color.b * c.b, m2.albedo_color.a)
					mi.set_surface_override_material(i, m2)
	for ch in n.get_children():
		_tint(ch, c)


## Cluster Rockets / Inferno без своих триггеров: дождь снарядов по области.
static func rain(rt: W3Runtime, c: Unit, ad: Dictionary, lv: Dictionary, a: float, p: Vector3) -> void:
	var art: Dictionary = ad.get("art", {})
	var r := clampf(float(lv.get("area", 300.0)) * U, 3.0, 9.0)
	var t := clampf(float(lv.get("dur", 0.0)), 1.5, 4.0)
	var mis := str(art.get("missile", ""))
	var eff := str(art.get("effect", ""))
	if eff == "":
		eff = "Abilities\\Weapons\\Mortar\\MortarMissile.mdl"
	var n := int(t / 0.25)
	for i in n:
		rt.get_tree().create_timer(i * 0.25, false).timeout.connect(func() -> void:
			if c == null or not is_instance_valid(c):
				return
			var q := p + Vector3(randf_range(-r, r), 0, randf_range(-r, r)) * 0.75
			if mis != "":
				var m := _model_at(rt, mis, q + Vector3(randf_range(-3, 3), 10.0, randf_range(-3, 3)), 1.0)
				var tw := m.create_tween()
				tw.tween_property(m, "global_position", q, 0.35)
				tw.tween_callback(m.destroy_fx)
			rt.get_tree().create_timer(0.35 if mis != "" else 0.0, false).timeout.connect(func() -> void:
				# тяжёлый взрыв — через раз (иначе десяток взрывов одновременно и падение кадров)
				if i % 2 == 0:
					W3Abil.fx_at(rt, eff, q)
				if c and is_instance_valid(c):
					for e in W3Abil.enemies(rt, c, q, r * 0.4):
						W3Abil.dmg(rt, c, e, a * 0.35)))


# ------------------------------------------------------------------ Итачи
const CROW := "war3mapImported\\feathercrow体.mdx"


## Катон: Гокакю — огненный шар летит по прямой и взрывается о первого врага или в конце пути.
static func fireball(rt: W3Runtime, c: Unit, _ad: Dictionary, lv: Dictionary, a: float, p: Vector3) -> void:
	var cp := c.global_position
	var dir := _dir_to(c, p)
	var start := cp + dir * 60.0 * WK + Vector3(0, 30.0 * WK, 0)
	var m := _vis("war3mapImported\\katongoukamekkyaku体.mdl", start)
	rt.fx_parent.add_child(m)
	m.global_position = start
	m.scale = Vector3.ONE * FX_K * 0.85
	m.set_particle_cap(60)
	m.rotation.y = atan2(dir.x, dir.z)
	var spd := 1500.0 * WK
	var total := float(lv.get("rng", 1100.0)) * WK
	var r := float(lv.get("area", 300.0)) * WK
	var k_sp := float(rt._d(c).get("spell_k", 1.0)) if c.has_meta("w3") else 1.0
	var src := rt.credit_of(c)
	var wc: WeakRef = weakref(c)
	_ticker(rt, func(t: float, _dt: float) -> bool:
		var dist := minf(t * spd, total)
		var pos: Vector3 = start + dir * dist
		var cc := wc.get_ref() as Unit
		if is_instance_valid(m):
			m.global_position = pos
		var boom := dist >= total
		if cc != null and cc.alive and not W3Abil.enemies(rt, cc, pos, 110.0 * WK).is_empty():
			boom = true
		if not boom:
			return true
		if is_instance_valid(m):
			m.destroy_fx()
		for k in 4:
			W3Abil.fx_at(rt, "war3mapImported\\flamebomb体.mdx", pos + Vector3(cos(k * 1.6), 0, sin(k * 1.6)) * r * 0.45)
		_shake(pos, 0.4)
		if cc != null and cc.alive:
			for e in W3Abil.enemies(rt, cc, pos, r):
				W3Abil.dmg(rt, cc, e, a)
				e.apply_poison(src, a * 0.08 * W3Runtime.DMG_K * k_sp, 3.0)
		return false)


## Вороний шаг — Итачи рассыпается стаей ворон и мгновенно появляется в точке; секунду после прыжка невидим.
static func crow_blink(rt: W3Runtime, c: Unit, _ad: Dictionary, lv: Dictionary, p: Vector3) -> void:
	var cp := c.global_position
	var to := p
	var maxd := float(lv.get("rng", 1200.0)) * W3Runtime.U
	var dv := to - cp
	dv.y = 0.0
	if dv.length() > maxd:
		to = cp + dv.normalized() * maxd
	if Game.I and c.area != -99:
		to = Game.I.clamp_to_area(to, c.area)
	for k in 5:
		var off := Vector3(cos(k * 1.26), 0, sin(k * 1.26)) * 0.9
		W3Abil.fx_at(rt, CROW, cp + off + Vector3(0, 0.8, 0))
		W3Abil.fx_at(rt, CROW, to + off + Vector3(0, 0.8, 0))
	c.global_position = to
	c.path.clear()
	c.order = "idle"
	c.invis = maxf(c.invis, 1.0)


## Цукуёми — как Doom: цель не может применять способности и предметы, замедлена и получает урон всё время действия.
static func tsukuyomi(rt: W3Runtime, c: Unit, ad: Dictionary, lv: Dictionary, a: float, tu: Unit) -> void:
	var dur := float(lv.get("hdur", 5.0))
	if tu.kind == Unit.Kind.BOSS:
		dur *= 0.5
	var k_sp := float(rt._d(c).get("spell_k", 1.0)) if c.has_meta("w3") else 1.0
	tu.silence = maxf(tu.silence, dur)
	tu.apply_slow(0.5, dur)
	tu.apply_poison(rt.credit_of(c), a / maxf(dur, 1.0) * W3Runtime.DMG_K * k_sp, dur)
	var art: Dictionary = ad.get("art", {})
	W3Abil.fx_on(rt, str(art.get("target", "")), tu, "origin")
	# красная метка над целью на всё время действия
	if Game.I and not Game.I.sim:
		var wt: WeakRef = weakref(tu)
		var ring := MeshInstance3D.new()
		ring.mesh = Fx.flat_ring_mesh(0.7, 1.0, 24)
		ring.material_override = Fx.glow_mat(Color(1.0, 0.1, 0.15), 2.5, true, 0.8)
		tu.add_child(ring)
		ring.position.y = 0.1
		_ticker(rt, func(t: float, _dt: float) -> bool:
			var tt := wt.get_ref() as Unit
			if tt == null or not tt.alive or tt.silence <= 0.0 or t > dur:
				if is_instance_valid(ring):
					ring.queue_free()
				return false
			ring.rotate_y(0.15)
			return true)
	if tu is Hero and Game.I and Game.I.hud and tu == Game.I.player:
		Game.I.hud.announce("Цукуёми! Способности и предметы отключены на %d с" % int(dur), Color(1.0, 0.3, 0.3), 2.5)


## Шаринган — переключаемый режим: уклонение и криты, пока хватает маны (расход каждую секунду).
static func sharingan(rt: W3Runtime, c: Unit, lv: Dictionary) -> void:
	var h := c as Hero
	if h == null:
		return
	if h.has_buff("sharingan"):
		_sharingan_off(h)
		return
	var drain := float(lv.get("c", 6.0))
	if h.mp < drain * 2.0:
		return
	h.add_buff("sharingan", {"name": "Шаринган", "evasion": float(lv.get("d", 0.35)), "crit": float(lv.get("a", 25.0)) / 100.0,
		"crit_mult": float(lv.get("b", 2.5))}, 1e6)
	var serial := int(h.get_meta("sharingan_n", 0)) + 1
	h.set_meta("sharingan_n", serial)
	if Game.I and not Game.I.sim:
		var eye := OmniLight3D.new()
		eye.name = "SharinganGlow"
		eye.light_color = Color(1.0, 0.1, 0.1)
		eye.light_energy = 1.6
		eye.omni_range = 4.0
		eye.position.y = 1.7
		h.add_child(eye)
		Fx.ring_burst(Game.I.fx_root, h.global_position, 2.0, Color(1.0, 0.15, 0.15), 0.4)
	var wh: WeakRef = weakref(h)
	var acc := [0.0]
	_ticker(rt, func(_t: float, dt: float) -> bool:
		var hh := wh.get_ref() as Hero
		if hh == null or not hh.has_buff("sharingan") or int(hh.get_meta("sharingan_n", 0)) != serial:
			if hh != null and not hh.has_buff("sharingan"):
				_sharingan_off(hh)
			return false
		if not hh.alive:
			_sharingan_off(hh)
			return false
		acc[0] += dt
		if acc[0] >= 1.0:
			acc[0] -= 1.0
			if hh.mp < drain:
				_sharingan_off(hh)
				return false
			hh.mp -= drain
		return true)


static func _sharingan_off(h: Hero) -> void:
	h.remove_buff("sharingan")
	var eye := h.get_node_or_null("SharinganGlow")
	if eye:
		eye.queue_free()

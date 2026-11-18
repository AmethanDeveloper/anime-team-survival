class_name W3Abil
## Способности Warcraft 3: базовое действие (по коду способности и её данным из карты),
## события заклинаний для триггеров, уровни способностей героя, пассивки и баффы.

const BUFF_STUN := 1112757326     # 'BSTN'
const BUFF_BOLT := 1112560965     # 'BPSE'
const BUFF_SLOW := 1114860655     # 'Bslo'
const BUFF_FROST := 1113035375    # 'Bfro'
const BUFF_INVUL := 1115059564    # 'Bvul'

## Как выбирается цель (по базовому коду способности).
const UNIT_T := ["AHtb", "ANfb", "ACtb", "ANfd", "AUfn", "ACfn", "AUsl", "ACsl", "AOhx", "AChx", "Aslo", "ACsw",
	"Acri", "Scri", "Aprg", "ANdr", "Aweb", "ACwb", "AIinf", "Ainf", "AOhw", "ANso", "Alsh", "ANfl", "ACfl",
	"AOcl", "ACcl", "AUdc", "AHhb", "ANhs", "Aens", "ANsi", "AHdr", "ACdc"]
const POINT_T := ["AOsh", "AUcs", "ANbf", "ACbf", "ACcv", "AUim", "AHbz", "ACbz", "AHfs", "ACfs", "AUdd", "ANrc",
	"ANmo", "AEbl", "ANst", "ACsi", "AHfa", "ANcs", "AEfn", "AOsw", "ANvc"]
const NONE_T := ["AHtc", "ACtc", "AOws", "ANbr", "AEme", "ANrg", "Aroa", "ACro", "AOww", "AEfk", "AOwk", "Absk",
	"Afzy", "AEim", "AEsf", "ACsf", "AOvd", "AIhe", "AUls", "AHds", "AEsv", "AUan", "Aspb", "AOmi", "AOsf",
	"AOre", "AHav", "AIre", "ANtm", "ACmi"]
const PASSIVE_T := ["AOcr", "ACct", "AHbh", "ACbh", "AEev", "ACev", "ANdb", "ANca", "AUav", "ACvp", "AHad", "ACad",
	"AHab", "ACba", "AUau", "ACua", "AOae", "ACae", "AEar", "ACat", "Apxf", "ANpi", "ANic", "Asph", "AEah", "ACah",
	"Awar", "Afbk", "ANca", "Amim", "Aroc"]


static func target_of(code: String, lv: Dictionary) -> String:
	if code == "ANcl":
		match int(lv.get("b", 0)):
			1:
				return "unit"
			2, 3:
				return "point"
		return "none"
	if code in UNIT_T:
		return "unit"
	if code in POINT_T:
		return "point"
	if code in PASSIVE_T:
		return "passive"
	return "none"


static func adata(rt: W3Runtime, id: int) -> Dictionary:
	return (rt.data.get("abilities", {}) as Dictionary).get(W3Runtime.fcc_str(id), {})


static func lvdata(ad: Dictionary, lvl: int) -> Dictionary:
	var lv: Array = ad.get("levels", [])
	if lv.is_empty():
		return {}
	return lv[clampi(lvl - 1, 0, lv.size() - 1)]


# ------------------------------------------------------------------ уровни способностей героя
## Уровень способности [i] героя: открывается на Data.UNLOCK, растёт каждые 8 уровней героя (до 3).
static func hero_level(h: Hero, i: int) -> int:
	var a: Dictionary = h.abilities[i].def
	if a.get("set", false):
		return 1 + int(h.level >= 20) + int(h.level >= 30) if h.has_set() else 0
	if i < 4:
		return h.skill_level(i)
	# врождённая растёт сама: каждые 8 уровней героя (до 3)
	return mini(3, 1 + (h.level - 1) / 8)


static func init_hero(rt: W3Runtime, h: Hero) -> void:
	rt._d(h).abils = {}
	update_levels(rt, h)


static func update_levels(rt: W3Runtime, h: Hero) -> void:
	var ab: Dictionary = rt._d(h).abils
	var learned: Dictionary = rt._d(h).get("learned", {})
	rt._d(h)["learned"] = learned
	for i in h.abilities.size():
		var a: Dictionary = h.abilities[i].def
		var raw: String = a.get("w3", "")
		if raw == "":
			continue
		var id := W3Runtime.fcc(raw)
		var lvl := hero_level(h, i)
		if lvl <= 0:
			continue
		var old: int = learned.get(id, 0)
		if lvl > old:
			learned[id] = lvl
			ab[id] = lvl
			for k in range(old, lvl):
				rt.fire_learn(h, id)
			on_added(rt, h, id)
	h.recalc_stats()


static func available(rt: W3Runtime, h: Hero, i: int) -> bool:
	var raw: String = h.abilities[i].def.get("w3", "")
	if raw == "":
		return true
	var id := W3Runtime.fcc(raw)
	var d := rt._d(h)
	var lv := hero_level(h, i)
	if lv > 0 and int((d.get("learned", {}) as Dictionary).get(id, 0)) < lv:
		update_levels(rt, h)
	var sid := slot_id(rt, h, i)
	if sid != id:
		return true
	if lv > 0 and not (d.abils as Dictionary).has(id):
		return false
	var p = d.get("player")
	if p is W3Runtime.JPlayer and (p.avail as Dictionary).has(id):
		return false
	return true


# ------------------------------------------------------------------ второй этап способности
## Какую способность сейчас применяет ячейка героя. В карте триггеры подменяют кнопку следующим этапом
## (Miyuki Q → Q2, Kotori W → W2, режимы Эрзы, Хеката Синон...): добавляют герою новую способность
## с той же клавишей, а исходную выключают. Тогда ячейка применяет добавленную.
static func slot_id(rt: W3Runtime, h: Hero, i: int) -> int:
	if i >= h.abilities.size():
		return 0
	var raw: String = h.abilities[i].def.get("w3", "")
	if raw == "":
		return 0
	var base := W3Runtime.fcc(raw)
	if rt == null or not h.has_meta("w3"):
		return base
	var d := rt._d(h)
	var ab: Dictionary = d.get("abils", {})
	var p = d.get("player")
	var off: bool = (p is W3Runtime.JPlayer and (p.avail as Dictionary).has(base)) or \
		(hero_level(h, i) > 0 and not ab.has(base) and (d.get("learned", {}) as Dictionary).has(base))
	if not off:
		return base
	var hk := str(adata(rt, base).get("hotkey", "")).to_upper()
	if hk == "" and i < 6:
		hk = ["Q", "W", "E", "R", "D", "T"][i]
	var best := 0
	for id in ab:
		if id == base or _kit_has(h, id):
			continue
		var ad := adata(rt, id)
		if ad.is_empty() or str(ad.get("hotkey", "")).to_upper() != hk:
			continue
		var code: String = ad.get("code", "")
		if code in PASSIVE_T or code == "Aspb" or code == "Aloc":
			continue
		if p is W3Runtime.JPlayer and (p.avail as Dictionary).has(id):
			continue
		best = id
	return best if best != 0 else base


static func _kit_has(h: Hero, id: int) -> bool:
	var k := W3Runtime.fcc_str(id)
	for a in h.abilities:
		if str(a.def.get("w3", "")) == k:
			return true
	return false


## Подменённая ячейка: цель, дальность, мана, перезарядка — из данных добавленной способности.
static func slot_info(rt: W3Runtime, h: Hero, i: int) -> Dictionary:
	var sid := slot_id(rt, h, i)
	var raw: String = h.abilities[i].def.get("w3", "")
	if sid == 0 or raw == "" or sid == W3Runtime.fcc(raw):
		return {}
	var ad := adata(rt, sid)
	var lv := lvdata(ad, int((rt._d(h).abils as Dictionary).get(sid, 1)))
	return {"id": sid, "target": target_of(str(ad.get("code", "")), lv), "range": float(lv.get("rng", 0.0)) * W3Runtime.U,
		"mana": float(lv.get("cost", 0.0)), "cd": float(lv.get("cool", 0.0)), "name": str(ad.get("name", "")),
		"key": "x_" + W3Runtime.fcc_str(sid)}


# ------------------------------------------------------------------ каст героя
static func hero_cast(rt: W3Runtime, h: Hero, i: int, point: Vector3, unit: Unit, sid := 0) -> void:
	var a: Dictionary = h.abilities[i].def
	var id := W3Runtime.fcc(str(a.w3))
	var tgt_kind: String = a.target
	if sid != 0 and sid != id:
		id = sid
		var ad0 := adata(rt, id)
		tgt_kind = target_of(str(ad0.get("code", "")), lvdata(ad0, int((rt._d(h).abils as Dictionary).get(id, 1))))
	var lvl := int((rt._d(h).abils as Dictionary).get(id, maxi(1, hero_level(h, i))))
	var tx := point.x / W3Runtime.U
	var ty := -point.z / W3Runtime.U
	var has_point: bool = tgt_kind == "point"
	if unit and is_instance_valid(unit):
		tx = rt.wx(unit)
		ty = rt.wy(unit)
	var ad := adata(rt, id)
	var anim: String = (ad.get("art", {}) as Dictionary).get("anim", "spell")
	if anim != "" and anim != "stand":
		W3Unit.anim_on(h, anim.replace(",", " "), false)
	rt.fire_spell(W3Runtime.EVENT_PLAYER_UNIT_SPELL_CHANNEL, h, id, unit, tx, ty, has_point)
	rt.fire_spell(W3Runtime.EVENT_PLAYER_UNIT_SPELL_CAST, h, id, unit, tx, ty, has_point)
	rt.fire_spell(W3Runtime.EVENT_PLAYER_UNIT_SPELL_EFFECT, h, id, unit, tx, ty, has_point)
	cast_base(rt, h, id, lvl, unit, point if has_point or unit == null else unit.global_position)
	rt.fire_spell(W3Runtime.EVENT_PLAYER_UNIT_SPELL_FINISH, h, id, unit, tx, ty, has_point)
	rt.fire_spell(W3Runtime.EVENT_PLAYER_UNIT_SPELL_ENDCAST, h, id, unit, tx, ty, has_point)


## Манекен получил приказ заклинания: ищем у него способность с этим приказом.
static func dummy_order(rt: W3Runtime, u: Unit, order: String, target: Unit, point: Vector3) -> bool:
	var ids: Array = (rt._d(u).abils as Dictionary).keys()
	if u is W3Unit:
		for s in (u as W3Unit).udata.get("abilities", []):
			ids.append(W3Runtime.fcc(str(s)))
	var real := not (u is W3Unit and (u as W3Unit).dummy)
	for id in ids:
		var ad := adata(rt, id)
		if ad.is_empty():
			continue
		if str(ad.get("order", "")).to_lower() != order:
			continue
		var lvl := int((rt._d(u).abils as Dictionary).get(id, 1))
		# настоящий юнит (босс арены) не применяет способность чаще её перезарядки
		if real and Game.I:
			var cds: Dictionary = rt._d(u).get("cds", {})
			rt._d(u)["cds"] = cds
			if float(cds.get(id, -1e9)) > Game.I.time:
				return false
			cds[id] = Game.I.time + maxf(0.5, float(lvdata(ad, lvl).get("cool", 0.0)))
		var p := point if point != Vector3.INF else u.global_position
		var tx := p.x / W3Runtime.U
		var ty := -p.z / W3Runtime.U
		if target:
			rt.set_facing(u, rad_to_deg(atan2(-(target.global_position.z - u.global_position.z),
				target.global_position.x - u.global_position.x)))
		rt.fire_spell(W3Runtime.EVENT_PLAYER_UNIT_SPELL_CHANNEL, u, id, target, tx, ty, target == null)
		rt.fire_spell(W3Runtime.EVENT_PLAYER_UNIT_SPELL_CAST, u, id, target, tx, ty, target == null)
		rt.fire_spell(W3Runtime.EVENT_PLAYER_UNIT_SPELL_EFFECT, u, id, target, tx, ty, target == null)
		cast_base(rt, u, id, lvl, target, p)
		return true
	return false


# ------------------------------------------------------------------ помощники
static func enemies(rt: W3Runtime, caster: Unit, pos: Vector3, r: float) -> Array:
	var out: Array = []
	for u in rt.all_units():
		var uu: Unit = u
		if not uu.alive or uu.team == caster.team or not uu.visible or uu.kind == Unit.Kind.CRYSTAL:
			continue
		var dx := uu.global_position.x - pos.x
		var dz := uu.global_position.z - pos.z
		if dx * dx + dz * dz <= (r + uu.radius) * (r + uu.radius):
			out.append(uu)
	return out


static func allies(rt: W3Runtime, caster: Unit, pos: Vector3, r: float) -> Array:
	var out: Array = []
	for u in rt.all_units():
		var uu: Unit = u
		if uu.alive and uu.team == caster.team and uu.kind != Unit.Kind.CRYSTAL and \
				Vector2(uu.global_position.x - pos.x, uu.global_position.z - pos.z).length() <= r + uu.radius:
			out.append(uu)
	return out


static func dmg(rt: W3Runtime, caster: Unit, u: Unit, amount: float) -> void:
	if amount <= 0.0 or Game.I == null or u == null or not is_instance_valid(u):
		return
	# у боссов NCD числа карты огромные: их урон приводится к масштабу игры (spell_k)
	var k := 1.0
	if caster and is_instance_valid(caster) and caster.has_meta("w3"):
		k = float(rt._d(caster).get("spell_k", 1.0))
	Game.I.deal_damage(rt.credit_of(caster), u, amount * W3Runtime.DMG_K * k, "spell")


static func dur_for(lv: Dictionary, u: Unit) -> float:
	var d := float(lv.get("dur", 0.0))
	var hd := float(lv.get("hdur", 0.0))
	if u is Hero and hd > 0.0:
		return hd
	return d if d > 0.0 else hd


static func stun(rt: W3Runtime, u: Unit, t: float, buff := BUFF_STUN) -> void:
	if u == null or not u.alive or t <= 0.0:
		return
	u.apply_stun(t)
	add_buff(rt, u, buff, t)


static func fx_at(rt: W3Runtime, art: String, pos: Vector3) -> void:
	if art == "":
		return
	var m := W3Fx.at(rt, art, pos)
	m.destroy_fx()


static func fx_on(rt: W3Runtime, art: String, u: Unit, attach: String) -> void:
	if art == "" or u == null:
		return
	var m := W3Fx.on_unit(rt, art, u, attach)
	m.destroy_fx()


static func add_buff(rt: W3Runtime, u: Unit, code: int, t: float) -> void:
	var d := rt._d(u)
	if d.is_empty():
		return
	var bf: Dictionary = d.buffs
	bf[code] = maxf(float(bf.get(code, 0.0)), t)
	if not u.is_in_group("w3_tracked"):
		u.add_to_group("w3_tracked")


static func remove_buff(rt: W3Runtime, u: Unit, code: int) -> void:
	var d := rt._d(u)
	if d.is_empty():
		return
	(d.buffs as Dictionary).erase(code)
	if code == BUFF_STUN or code == BUFF_BOLT:
		u.stun = 0.0


static func has_buff(rt: W3Runtime, u: Unit, code: int) -> bool:
	var d := rt._d(u)
	if not d.is_empty() and float((d.buffs as Dictionary).get(code, 0.0)) > 0.0:
		return true
	if code == BUFF_STUN or code == BUFF_BOLT:
		return u.stun > 0.0 and u.frozen_ice <= 0.0
	if code == BUFF_INVUL:
		return u.invulnerable > 0.0
	if code == BUFF_SLOW or code == BUFF_FROST:
		return u.slow_time > 0.0
	return false


static func on_added(rt: W3Runtime, u: Unit, id: int) -> void:
	var ad := adata(rt, id)
	var code: String = ad.get("code", "")
	if u is Hero and (code in PASSIVE_T or code in ATTR_T or code == "Aspb"):
		(u as Hero).recalc_stats()
	if code in ["ANpi", "Apxf"]:
		_start_aura(rt, u, id)
	if code in INVIS_T:
		_update_perm_invis(rt, u)


static func on_removed(rt: W3Runtime, u: Unit, id: int) -> void:
	if u is Hero:
		(u as Hero).recalc_stats()
	var code: String = adata(rt, id).get("code", "")
	if code in INVIS_T:
		_update_perm_invis(rt, u)
	if code in ["AEim", "ACim"]:
		var d := rt._d(u)
		if (d.get("immo", {}) as Dictionary).has(id):
			_toggle_immolation(rt, u, id, {})


## Пассивные бонусы героя от способностей WC3 (крит, уклонение, оглушение, ауры на себя).
static func passive_mods(h: Hero) -> Dictionary:
	var out := {"crit": 0.0, "crit_mult": 0.0, "evasion": 0.0, "bash": 0.0, "lifesteal": 0.0, "armor": 0.0,
		"attack_speed": 0.0, "move": 0.0, "hp_regen": 0.0, "mp_regen": 0.0, "damage_pct": 0.0}
	var rt := W3Runtime.I
	if rt == null or not h.has_meta("w3"):
		return out
	var ab := all_abils(rt, h)
	for id in ab:
		var ad := adata(rt, id)
		var code: String = ad.get("code", "")
		if not (code in PASSIVE_T):
			continue
		var lv := lvdata(ad, int(ab[id]))
		var a := float(lv.get("a", 0.0))
		var b := float(lv.get("b", 0.0))
		match code:
			"AOcr", "ACct":
				if a / 100.0 > out.crit:
					out.crit = a / 100.0
					out.crit_mult = b
				# поле D — шанс уклонения: в NCD долей (0.3), в ATS процентами (10)
				var dv := float(lv.get("d", 0.0))
				out.evasion += dv if dv <= 1.0 else dv / 100.0
			"ANdb":
				out.evasion += a / 100.0 if a > 1.0 else a
				if b / 100.0 > out.crit:
					out.crit = b / 100.0 if b > 1.0 else b
					out.crit_mult = float(lv.get("c", 2.0))
			"AEev", "ACev":
				out.evasion += a if a <= 1.0 else a / 100.0
			"AHbh", "ACbh":
				out.bash = maxf(out.bash, a / 100.0 if a > 1.0 else a)
			"AUav", "ACvp":
				out.lifesteal += a
			"AHad", "ACad":
				out.armor += a
			"AHab", "ACba":
				out.mp_regen += a
			"AUau", "ACua":
				out.move += a
				out.hp_regen += b
			"AOae", "ACae":
				out.move += a
				out.attack_speed += b
			"AEar", "ACat":
				out.damage_pct += a
	return out


# ------------------------------------------------------------------ базовые действия способностей
static func cast_base(rt: W3Runtime, c: Unit, id: int, lvl: int, tu: Unit, p: Vector3) -> void:
	var ad := adata(rt, id)
	if ad.is_empty() or c == null or not is_instance_valid(c):
		return
	var code: String = ad.get("code", "")
	var lv := lvdata(ad, lvl)
	var art: Dictionary = ad.get("art", {})
	var a := float(lv.get("a", 0.0))
	var b := float(lv.get("b", 0.0))
	var cc := float(lv.get("c", 0.0))
	var dd := float(lv.get("d", 0.0))
	var area := float(lv.get("area", 0.0)) * W3Runtime.U
	var cp := c.global_position
	# урон от атрибута героя (способности Мадары: триггеров NCD нет, урон задан в данных)
	var da: Dictionary = ad.get("dmg_attr", {})
	if not da.is_empty() and c is Hero:
		var h0 := c as Hero
		var kk: Array = da.get("k", [1.0])
		var attr := h0.s_agi if str(da.get("attr", "agi")) == "agi" else (h0.s_str if str(da.attr) == "str" else h0.s_int)
		a = attr * float(kk[clampi(lvl - 1, 0, kk.size() - 1)]) * (1.0 + h0.spell_amp) / W3Runtime.DMG_K
	fx_on(rt, art.get("caster", ""), c, art.get("caster_attach", "origin"))
	_apply_data_buff(rt, c, code, lv, tu)
	var fxk := str(ad.get("fx", ""))
	if fxk != "" and NcdFx.cast(rt, c, fxk, ad, lv, a, tu, p):
		return
	match code:
		"AHtb", "ANfb", "ACtb", "ANfd", "AUdc", "ACdc", "ANso":
			if tu == null:
				return
			var hit := func() -> void:
				if tu and is_instance_valid(tu) and tu.alive:
					dmg(rt, c, tu, a)
					if code != "ANfd" and code != "ANso":
						stun(rt, tu, dur_for(lv, tu), BUFF_BOLT)
					fx_on(rt, art.get("target", ""), tu, art.get("target_attach", "origin"))
			if str(art.get("missile", "")) != "" or code in ["AHtb", "ANfb", "ACtb"]:
				W3Fx.missile(rt, art.get("missile", ""), cp + Vector3(0, 1.2, 0), tu, tu.global_position,
					float(art.get("missile_speed", 1000.0)), hit)
			else:
				hit.call()
		"AUfn", "ACfn":
			if tu == null:
				return
			dmg(rt, c, tu, b)
			for e in enemies(rt, c, tu.global_position, area):
				dmg(rt, c, e, a)
				e.apply_slow(0.3, dur_for(lv, e))
				add_buff(rt, e, BUFF_FROST, dur_for(lv, e))
			fx_on(rt, art.get("target", ""), tu, art.get("target_attach", "origin"))
		"AUsl", "ACsl", "AOhx", "AChx", "Aweb", "ACwb", "ANsi", "Aens":
			if tu:
				stun(rt, tu, dur_for(lv, tu))
				fx_on(rt, art.get("target", ""), tu, art.get("target_attach", "origin"))
		"Aslo", "ACsw", "Acri", "Scri", "Aprg":
			if tu:
				tu.apply_slow(clampf(absf(a), 0.1, 0.8), dur_for(lv, tu))
				add_buff(rt, tu, BUFF_SLOW, dur_for(lv, tu))
				fx_on(rt, art.get("target", ""), tu, art.get("target_attach", "origin"))
		"ANdr", "AHdr":
			if tu:
				_tick(rt, c, maxf(1.0, dur_for(lv, tu)), 1.0, func() -> void:
					if tu and is_instance_valid(tu) and tu.alive:
						dmg(rt, c, tu, a)
						if c and is_instance_valid(c) and c.alive:
							c.hp = minf(c.max_hp, c.hp + a * W3Runtime.DMG_K))
		"ANfl", "ACfl", "AOcl", "ACcl":
			if tu == null:
				return
			var n := int(b) if b > 0 else 3
			var cur := tu
			var done := [tu]
			var amount := a
			var from := cp + Vector3(0, 1.2, 0)
			for k in n:
				if cur == null:
					break
				var bolt := W3Fx.lightning(rt, art.get("lightning", "CLPB") if str(art.get("lightning", "")) != "" else "CLPB",
					from, cur.global_position + Vector3(0, 1.0, 0))
				rt.get_tree().create_timer(0.35).timeout.connect(bolt.queue_free)
				dmg(rt, c, cur, amount)
				fx_on(rt, art.get("target", ""), cur, "chest")
				from = cur.global_position + Vector3(0, 1.0, 0)
				if code == "AOcl" or code == "ACcl":
					amount *= 1.0 - clampf(cc, 0.0, 0.9)
				var nxt: Unit = null
				for e in enemies(rt, c, cur.global_position, 500.0 * W3Runtime.U):
					if not done.has(e):
						nxt = e
						break
				if nxt:
					done.append(nxt)
				cur = nxt
		"AHtc", "ACtc", "AOws", "AEfk", "ANvc":
			var r := area if area > 0.0 else 250.0 * W3Runtime.U
			for e in enemies(rt, c, cp, r):
				dmg(rt, c, e, a)
				if code == "AOws":
					stun(rt, e, dur_for(lv, e))
				elif code == "AHtc" or code == "ACtc":
					e.apply_slow(clampf(cc if cc > 0 else 0.3, 0.1, 0.7), dur_for(lv, e))
					add_buff(rt, e, BUFF_SLOW, dur_for(lv, e))
				fx_on(rt, art.get("target", ""), e, art.get("target_attach", "origin"))
			fx_at(rt, art.get("effect", ""), cp)
		"AOsh", "AUcs", "ANbf", "ACbf", "ACcv", "AUim":
			var dist := cc if cc > 0.0 else float(lv.get("rng", 800.0))
			var w0 := area if area > 0.0 else 120.0 * W3Runtime.U
			var w1 := dd * W3Runtime.U if dd > 0.0 else w0
			var amount := a
			if code == "AUim":
				dist = a if a > 0.0 else float(lv.get("rng", 800.0))
				amount = cc
			var dir := p - cp
			dir.y = 0.0
			if dir.length() < 0.1:
				dir = Vector3(sin(c.rotation.y), 0, cos(c.rotation.y))
			_wave(rt, c, cp, dir.normalized(), dist * W3Runtime.U, w0, w1, float(art.get("missile_speed", 1050.0)),
				art.get("missile", ""), func(e: Unit) -> void:
					dmg(rt, c, e, amount)
					if code == "AUim":
						stun(rt, e, dur_for(lv, e))
					if code == "ANbf" and float(lv.get("e", 0.0)) > 0.0:
						e.apply_poison(rt.credit_of(c), float(lv.e) * W3Runtime.DMG_K, maxf(1.0, dur_for(lv, e)))
					fx_on(rt, art.get("target", ""), e, art.get("target_attach", "origin")))
		"AHbz", "ACbz":
			var waves := maxi(1, int(a))
			var r2 := area if area > 0.0 else 200.0 * W3Runtime.U
			_tick(rt, c, float(waves), 1.0, func() -> void:
				if c == null or not is_instance_valid(c):
					return
				for k in 4:
					fx_at(rt, art.get("effect", ""), p + Vector3(randf_range(-r2, r2) * 0.7, 0, randf_range(-r2, r2) * 0.7))
				for e in enemies(rt, c, p, r2):
					dmg(rt, c, e, b)
					e.apply_slow(0.25, 1.0))
		"AHfs", "ACfs":
			var r3 := area if area > 0.0 else 200.0 * W3Runtime.U
			fx_at(rt, art.get("effect", ""), p)
			rt.get_tree().create_timer(1.0, false).timeout.connect(func() -> void:
				if c == null or not is_instance_valid(c):
					return
				fx_at(rt, art.get("special", "") if str(art.get("special", "")) != "" else art.get("effect", ""), p)
				_tick(rt, c, maxf(1.0, float(lv.get("dur", 3.0))), 1.0, func() -> void:
					if c and is_instance_valid(c):
						for e in enemies(rt, c, p, r3):
							dmg(rt, c, e, a)))
		"AEsf", "ACsf":
			var r4 := area if area > 0.0 else 650.0 * W3Runtime.U
			var iv := b if b > 0.0 else 1.0
			_tick(rt, c, maxf(iv, float(lv.get("dur", 15.0))), iv, func() -> void:
				if c == null or not is_instance_valid(c) or not c.alive:
					return
				for e in enemies(rt, c, c.global_position, r4):
					dmg(rt, c, e, a)
					fx_on(rt, art.get("effect", ""), e, "origin"))
		"AUdd":
			var r5 := area if area > 0.0 else 250.0 * W3Runtime.U
			fx_at(rt, art.get("effect", ""), p)
			_tick(rt, c, maxf(1.0, float(lv.get("dur", 10.0))), 1.0, func() -> void:
				if c and is_instance_valid(c):
					for e in enemies(rt, c, p, r5):
						dmg(rt, c, e, e.max_hp * clampf(a, 0.0, 0.2) / W3Runtime.DMG_K))
		"ANmo", "ANrc", "ANst", "Aroc":
			var r6 := area if area > 0.0 else 300.0 * W3Runtime.U
			var t6 := maxf(1.0, float(lv.get("dur", 3.0)))
			_tick(rt, c, t6, 0.5, func() -> void:
				if c == null or not is_instance_valid(c):
					return
				var q := p + Vector3(randf_range(-r6, r6) * 0.7, 0, randf_range(-r6, r6) * 0.7)
				fx_at(rt, art.get("effect", "") if str(art.get("effect", "")) != "" else art.get("missile", ""), q)
				for e in enemies(rt, c, q, r6 * 0.5):
					dmg(rt, c, e, a * 0.5))
		"AOww", "AUls":
			var r7 := area if area > 0.0 else 250.0 * W3Runtime.U
			if code == "AUls":
				r7 = minf(r7, 9.0)
			if code == "AOww":
				W3Unit.anim_on(c, "spell channel", false)
			var eff7 := str(art.get("effect", ""))
			var n7 := [0]
			_tick(rt, c, maxf(1.0, dur_for(lv, c)), 0.5, func() -> void:
				if c and is_instance_valid(c) and c.alive:
					n7[0] += 1
					if eff7 != "" and n7[0] % 2 == 1:
						var ang := randf() * TAU
						fx_at(rt, eff7, c.global_position + Vector3(cos(ang), 0, sin(ang)) * randf_range(1.0, r7 * 0.7))
					for e in enemies(rt, c, c.global_position, r7):
						dmg(rt, c, e, a * 0.5))
		"AEbl":
			var to := p
			var maxd := float(lv.get("rng", 1000.0)) * W3Runtime.U
			var dv := to - cp
			dv.y = 0.0
			if dv.length() > maxd:
				to = cp + dv.normalized() * maxd
			if Game.I and c.area != -99:
				to = Game.I.clamp_to_area(to, c.area)
			fx_at(rt, art.get("caster", ""), cp)
			c.global_position = to
			c.path.clear()
			c.order = "idle"
			fx_at(rt, art.get("target", ""), to)
		"AEme", "ANrg", "ANcr":
			morph(rt, c, id, code, lv)
		"ANcs", "ANin":
			NcdFx.rain(rt, c, ad, lv, a, p)
		"AOmi":
			var imgs := make_illusions(rt, c, maxi(1, int(a)), b if b > 0.0 else 1.0, cc if cc > 0.0 else 1.0,
				maxf(5.0, dur_for(lv, c)), art.get("special", ""))
			for u in imgs:
				fx_on(rt, art.get("target", ""), u, "origin")
		"AHwe", "ANsg", "ACsg", "AUan", "AEsv", "ACwe", "AHwe2":
			var tid := str(lv.get("unit", ""))
			if code == "AEsv" and (tid == "" or tid == "_"):
				tid = "espv"
			var n := maxi(1, int(a)) if code != "AEsv" else 1
			var t_sum := dur_for(lv, c)
			if tid != "" and tid != "_":
				for u in summon(rt, c, tid, n, t_sum, p if p != Vector3.INF else cp):
					fx_at(rt, art.get("target", "") if str(art.get("target", "")) != "" else art.get("special", ""), u.global_position)
			elif code == "AUan":
				# поднять павших: копии недавно погибших монстров рядом
				raise_dead(rt, c, n, t_sum, area if area > 0.0 else 900.0 * W3Runtime.U, art.get("special", ""))
		"AEim", "ACim":
			_toggle_immolation(rt, c, id, lv)
		"Aroa", "ACro", "ANbr", "Absk", "Afzy", "AIinf", "Ainf":
			var r8 := area if area > 0.0 else 600.0 * W3Runtime.U
			var t8 := maxf(1.0, dur_for(lv, c))
			var targets: Array = allies(rt, c, cp, r8) if code in ["Aroa", "ACro", "ANbr"] else [tu if tu else c]
			for u in targets:
				if u is Hero:
					var h: Hero = u
					h.buffs["w3_" + str(id)] = {"t": t8, "def": {"name": str(ad.get("name", "Усиление")),
						"damage_pct": a if code in ["Aroa", "ACro"] else 0.0, "attack_speed": b if code in ["Absk", "Afzy"] else 0.0,
						"armor": float(lv.get("b", 0.0)) if code in ["Aroa", "ACro"] else 0.0,
						"color": Color(1.0, 0.6, 0.3)}}
					h.recalc_stats()
				fx_on(rt, art.get("target", ""), u, art.get("target_attach", "overhead"))
		"AOwk":
			wind_walk(rt, c, lv)
		"AHds":
			c.invulnerable = maxf(c.invulnerable, maxf(1.0, dur_for(lv, c)))
			fx_on(rt, art.get("target", ""), c, "origin")
		"AOvd":
			var r9 := area if area > 0.0 else 800.0 * W3Runtime.U
			for u in allies(rt, c, cp, r9):
				u.invulnerable = maxf(u.invulnerable, maxf(1.0, float(lv.get("dur", 5.0))))
		"AIhe", "AHhb", "AOhw", "ANhs":
			var tgt: Unit = tu if tu else c
			tgt.hp = minf(tgt.max_hp, tgt.hp + a)
			fx_on(rt, art.get("target", ""), tgt, "origin")
		"ANcl":
			fx_at(rt, art.get("effect", ""), p)
		_:
			fx_at(rt, art.get("effect", ""), p)


## Бафф из данных способности (поле «buff»): триггеры карты проверяют его через UnitHasBuffBJ
## (например, Sephiroth R держится, пока на нём бафф Battle Roar).
const SELF_BUFF := ["ANbr", "Aroa", "ACro", "Absk", "Afzy", "AEme", "AOwk", "AHds", "AOvd", "AEsv", "ANrg",
	"AIhe", "AHhb", "AOhw", "ANhs", "AOmi", "AOre", "AHav", "AIre", "ANtm", "ACmi", "AUan"]


static func _apply_data_buff(rt: W3Runtime, c: Unit, code: String, lv: Dictionary, tu: Unit) -> void:
	var b := str(lv.get("buff", ""))
	if b == "" or b == "_":
		return
	var tgt: Unit = null
	if code in SELF_BUFF:
		tgt = tu if tu and code in ["AIhe", "AHhb", "AOhw", "ANhs"] else c
	elif code in UNIT_T and tu:
		tgt = tu
	if tgt == null or not is_instance_valid(tgt):
		return
	var t := dur_for(lv, tgt)
	if t <= 0.0:
		t = 5.0
	for one in b.split(","):
		if one.length() == 4:
			add_buff(rt, tgt, W3Runtime.fcc(one), t)


## Срабатывания при атаке героя: Pulverize (Awar) — шанс ударить по области, Feedback — сжечь ману.
static func on_attack(rt: W3Runtime, h: Unit, t: Unit) -> void:
	var d := rt._d(h)
	if d.is_empty() or t == null or not is_instance_valid(t):
		return
	# Wind Walk: первый удар из невидимости
	if d.has("windwalk"):
		if h.invis > 0.0:
			dmg(rt, h, t, float(d.windwalk))
			fx_on(rt, "Abilities\\Spells\\Other\\Stampede\\StampedeMissileDeath.mdl", t, "chest")
		d.erase("windwalk")
	for id in (d.abils as Dictionary):
		var ad := adata(rt, id)
		var code: String = ad.get("code", "")
		if code != "Awar" and code != "Afbk":
			continue
		var lv := lvdata(ad, int(d.abils[id]))
		var a := float(lv.get("a", 0.0))
		var art: Dictionary = ad.get("art", {})
		if code == "Awar":
			if randf() * 100.0 >= a:
				continue
			var full := float(lv.get("c", 200.0)) * W3Runtime.U
			var half := float(lv.get("d", 0.0)) * W3Runtime.U
			for e in enemies(rt, h, t.global_position, maxf(full, half)):
				var near: bool = e.global_position.distance_to(t.global_position) <= full + e.radius
				var amt := float(lv.get("b", 0.0)) * (1.0 if near else 0.5)
				# «шанс убить» (огромный урон) не убивает боссов, героев и кристаллы: им — 8% здоровья
				if amt >= 50000.0 and (e is Hero or e.kind == Unit.Kind.BOSS or e.kind == Unit.Kind.CRYSTAL):
					amt = e.max_hp * 0.08 / W3Runtime.DMG_K
				dmg(rt, h, e, amt)
			fx_at(rt, art.get("caster", "") if str(art.get("caster", "")) != "" else art.get("effect", ""), t.global_position)
		elif code == "Afbk" and a > 0.0:
			var burn := minf(a, t.mp)
			t.mp -= burn
			dmg(rt, h, t, burn)


## Повторяющееся действие (каждые iv секунд, всего t секунд).
static func _tick(rt: W3Runtime, c: Unit, t: float, iv: float, f: Callable) -> void:
	var n := maxi(1, int(round(t / maxf(iv, 0.05))))
	_tick_step(rt, c, n, iv, f)


## Повтор останавливается, когда применивший исчез (иначе замыкание получит удалённый объект).
static func _tick_step(rt: W3Runtime, c: Object, n: int, iv: float, f: Callable) -> void:
	if n <= 0 or not is_instance_valid(rt) or (c != null and not is_instance_valid(c)):
		return
	f.call()
	if n > 1:
		var wc: WeakRef = weakref(c) if c != null else null
		rt.get_tree().create_timer(iv, false, true).timeout.connect(func() -> void:
			var cc: Object = wc.get_ref() if wc else null
			if wc == null or cc != null:
				_tick_step(rt, cc, n - 1, iv, f))


class Wave:
	extends Node3D
	var rt: W3Runtime
	var caster: Unit
	var dir := Vector3.FORWARD
	var dist := 10.0
	var w0 := 1.0
	var w1 := 1.0
	var speed := 20.0
	var travelled := 0.0
	var hit: Dictionary = {}
	var on_hit: Callable
	var model: W3Model

	func _physics_process(delta: float) -> void:
		var step := speed * delta
		travelled += step
		global_position += dir * step
		if caster and is_instance_valid(caster):
			var w := lerpf(w0, w1, clampf(travelled / maxf(dist, 0.01), 0.0, 1.0))
			for e in W3Abil.enemies(rt, caster, global_position, w):
				var k := (e as Object).get_instance_id()
				if not hit.has(k):
					hit[k] = true
					on_hit.call(e)
		if travelled >= dist:
			if model and is_instance_valid(model):
				var gp := model.global_transform
				remove_child(model)
				rt.fx_parent.add_child(model)
				model.global_transform = gp
				model.destroy_fx()
			queue_free()


static func _wave(rt: W3Runtime, c: Unit, from: Vector3, dir: Vector3, dist: float, w0: float, w1: float,
		speed_w3: float, art: String, on_hit: Callable) -> void:
	var w := Wave.new()
	w.rt = rt
	w.caster = c
	w.dir = dir
	w.dist = maxf(dist, 1.0)
	w.w0 = w0
	w.w1 = w1
	w.speed = maxf(speed_w3, 400.0) * W3Runtime.U
	w.on_hit = on_hit
	rt.fx_parent.add_child(w)
	w.global_position = from
	w.rotation.y = atan2(dir.x, dir.z)
	if art != "":
		var m := W3Model.create(art)
		w.add_child(m)
		m.scale = Vector3.ONE * W3Runtime.FX_K
		m.position.y = 0.6
		w.model = m


## Аура урона вокруг юнита (Immolation, Phoenix Fire) — пока способность есть у юнита.
static func _start_aura(rt: W3Runtime, u: Unit, id: int) -> void:
	var ad := adata(rt, id)
	var lv := lvdata(ad, 1)
	var dps := float(lv.get("a", 0.0))
	var r := float(lv.get("area", 200.0)) * W3Runtime.U
	if dps <= 0.0:
		return
	var step := func(self_ref: Callable) -> void:
		if not is_instance_valid(u) or not u.alive or not (rt._d(u).abils as Dictionary).has(id):
			return
		for e in enemies(rt, u, u.global_position, r):
			dmg(rt, u, e, dps * flat_k(u))
		rt.get_tree().create_timer(1.0, false, true).timeout.connect(func() -> void: self_ref.call(self_ref))
	step.call(step)


## Постоянный урон вокруг героя (аура, Immolation) задан в карте одним числом на всю игру. Чтобы он не решал
## исход на первых уровнях, у героев он растёт с уровнем: 7% на 1-м, 24% на 15-м, 36% на 25-м.
static func flat_k(u: Unit) -> float:
	if u is Hero:
		return 0.06 + 0.012 * float((u as Hero).level)
	return 1.0


# ------------------------------------------------------------------ книги заклинаний и атрибуты
## Прибавки атрибутов (Attribute Bonus): благословения и проклятия Мику, предметы-способности.
const ATTR_T := ["AIab", "AIx1", "AIx2", "AIx5", "AIa1", "AIi1", "AIs1"]
## Постоянная невидимость, пока у юнита есть способность (Синон стоит на месте — триггер добавляет Apiv).
const INVIS_T := ["Apiv"]


## Способности юнита вместе с содержимым книг заклинаний (Aspb): {код: уровень}.
static func all_abils(rt: W3Runtime, u: Unit) -> Dictionary:
	var ab: Dictionary = rt._d(u).get("abils", {})
	var out := ab
	for id in ab:
		var ad := adata(rt, id)
		if str(ad.get("code", "")) != "Aspb":
			continue
		if out == ab:
			out = ab.duplicate()
		for s in ad.get("book", []):
			var bid := W3Runtime.fcc(str(s))
			if not out.has(bid):
				out[bid] = 1
	return out


static func attr_mods(h: Hero) -> Dictionary:
	var out := {"str": 0.0, "agi": 0.0, "int": 0.0}
	var rt := W3Runtime.I
	if rt == null or not h.has_meta("w3"):
		return out
	var ab := all_abils(rt, h)
	for id in ab:
		var ad := adata(rt, id)
		var code: String = ad.get("code", "")
		if not (code in ATTR_T):
			continue
		var lv := lvdata(ad, int(ab[id]))
		var a := float(lv.get("a", 0.0))
		match code:
			"AIab":
				out.agi += a
				out.int += float(lv.get("b", 0.0))
				out.str += float(lv.get("c", 0.0))
			"AIx1", "AIx2", "AIx5":
				out.str += a
				out.agi += a
				out.int += a
			"AIa1":
				out.agi += a
			"AIi1":
				out.int += a
			"AIs1":
				out.str += a
	return out


# ------------------------------------------------------------------ перевоплощение
const RANGED_WEAP := ["missile", "msplash", "mbounce", "mline", "artillery", "aline"]
static var _morph_serial := 0


static func udata_of(rt: W3Runtime, tid: String) -> Dictionary:
	return (rt.data.get("units", {}) as Dictionary).get(tid, {})


## Юнит карты, от которого считаются формы: у героя — его юнит в карте, у юнита триггеров — его тип.
static func _base_udata(rt: W3Runtime, c: Unit) -> Dictionary:
	if c is Hero:
		return udata_of(rt, str((c as Hero).def.get("map_unit", "")))
	if c is W3Unit:
		return (c as W3Unit).udata
	return {}


## Перевоплощение (Robo-Goblin ANrg, Metamorphosis AEme): тип юнита для триггеров, модель формы с её
## анимациями и ростом, атака (дальность, снаряд, скорость), бег, прибавки силы, брони и здоровья,
## способности формы. Обратно — повторным применением той же способности или когда выйдет время формы.
static func morph(rt: W3Runtime, c: Unit, id: int, code: String, lv: Dictionary) -> void:
	var alt := str(lv.get("unit", ""))
	if alt == "" or alt == "_" or not c.alive:
		return
	var d := rt._d(c)
	if not d.has("morphs"):
		d["morphs"] = []
	var stack: Array = d.morphs
	for k in range(stack.size() - 1, -1, -1):
		if int(stack[k].abil) == id:
			while stack.size() > k:
				unmorph(rt, c)
			return
	var ud := udata_of(rt, alt)
	var cur_ud := udata_of(rt, W3Runtime.fcc_str(rt.unit_type_id(c)))
	var base := _base_udata(rt, c)
	_morph_serial += 1
	var e := {"abil": id, "serial": _morph_serial, "type": int(d.get("type", 0)), "model": c.model, "anim": c.anim,
		"anim_map": c.anim_map.duplicate(), "base_pos": c.model_base_pos, "variants": c.attack_variants.duplicate(),
		"missile": c.missile_art, "scale": c.model.scale if c.model else Vector3.ONE, "added": [],
		"mods": (c as Hero).morph_mods.duplicate() if c is Hero else {},
		"stats": {"range": c.attack_range, "ranged": c.ranged, "cd": c.attack_cd, "dmg": c.base_damage,
			"armor": c.armor, "speed": c.move_speed, "hp": c.max_hp}}
	stack.append(e)
	d.type = W3Runtime.fcc(alt)
	if not ud.is_empty():
		_form_model(rt, c, ud, cur_ud, base)
	# обычные способности формы: пассивки и новые кнопки (их открывают триггеры карты)
	var ab: Dictionary = d.abils
	for sid in ud.get("abilities", []):
		var s2 := str(sid)
		if s2 in ["AInv", "Aloc", "Avul", "Amov", "Aatk", "Ahrl"]:
			continue
		var aid := W3Runtime.fcc(s2)
		if ab.has(aid) or (c is Hero and _kit_has(c as Hero, aid)):
			continue
		ab[aid] = 1
		(e.added as Array).append(aid)
		on_added(rt, c, aid)
	var ev := float(lv.get("e", 0.0))
	var fv := float(lv.get("f", 0.0))
	if c is Hero:
		var h := c as Hero
		var m: Dictionary = h.morph_mods.duplicate()
		if code == "ANrg":
			m["str"] = float(m.get("str", 0.0)) + ev
			m["armor"] = float(m.get("armor", 0.0)) + fv
		else:
			m["hp"] = float(m.get("hp", 0.0)) + ev
			m["armor"] = float(m.get("armor", 0.0)) + (fv if code == "ANcr" else 0.0)
		# Сусаноо Мадары: сопротивление магии, урон атаки от ловкости, удар по области вокруг цели
		m["mres"] = float(m.get("mres", 0.0)) + float(lv.get("mres", 0.0))
		m["agi_dmg"] = float(m.get("agi_dmg", 0.0)) + float(lv.get("agi_k", 0.0))
		if float(lv.get("splash", 0.0)) > 0.0:
			m["splash"] = maxf(float(m.get("splash", 0.0)), float(lv.splash))
		_attack_mods(m, ud, base, h.def)
		h.morph_mods = m
		h.recalc_stats()
	elif not ud.is_empty() and not base.is_empty():
		var m2 := {}
		_attack_mods(m2, ud, base, {"range": float(e.stats.range), "ranged": bool(e.stats.ranged)})
		c.attack_range = float(m2.get("range", c.attack_range))
		c.ranged = bool(m2.get("ranged", c.ranged))
		c.attack_cd = float(e.stats.cd) * float(m2.get("cd_k", 1.0))
		c.move_speed = float(e.stats.speed) * float(m2.get("speed_k", 1.0))
		c.base_damage = float(e.stats.dmg) + float(m2.get("damage", 0.0))
		c.armor = float(e.stats.armor) + fv
		if code == "AEme" and ev > 0.0:
			var k := c.hp / maxf(1.0, c.max_hp)
			c.max_hp += ev
			c.hp = c.max_hp * k
	if c.ranged and not (str(ud.get("missile", "")) in ["", "_"]):
		c.missile_art = str(ud.missile)
	# превращение занимает время: юнит стоит
	var tr := clampf(float(lv.get("dur", 0.0)), 0.0, 1.5)
	if tr > 0.05:
		c.cast_lock = maxf(c.cast_lock, tr * 0.6)
	# время формы (hdur); без него форма держится до повторного применения
	var t := float(lv.get("hdur", 0.0))
	if t <= 0.0 and code == "AEme" and float(lv.get("dur", 0.0)) > 3.0:
		t = float(lv.dur)
	if t > 0.0:
		var ser: int = e.serial
		rt.get_tree().create_timer(t, false).timeout.connect(func() -> void:
			if is_instance_valid(c):
				unmorph_serial(rt, c, ser))
	if OS.get_environment("W3_LOG") != "":
		print("[MORPH] ", c.display_name, " -> ", alt, " t=", t, " range=", c.attack_range, " ranged=", c.ranged,
			" cd=", c.attack_cd, " added=", (e.added as Array).map(func(x): return W3Runtime.fcc_str(x)))


## Атака формы относительно исходного юнита карты. Герои игры в своём масштабе, поэтому дальность,
## скорость атаки и бега берутся пропорционально; прибавка урона — разница урона юнитов карты.
static func _attack_mods(m: Dictionary, ud: Dictionary, base: Dictionary, def: Dictionary) -> void:
	if ud.is_empty() or base.is_empty():
		return
	var br := maxf(50.0, float(base.get("range", 100.0)))
	var ar := maxf(50.0, float(ud.get("range", br)))
	var weap := str(ud.get("weap", ""))
	# «normal» — ближний бой даже с длинной рукой (Сусаноо бьёт мечом на 300)
	var alt_ranged := weap in RANGED_WEAP or weap == "instant" or (weap != "normal" and ar >= 300.0)
	var base_range := float(def.get("range", br * W3Runtime.U))
	if absf(ar - br) > 1.0:
		if alt_ranged and not bool(def.get("ranged", false)):
			m["range"] = clampf(ar * W3Runtime.U, 6.0, 18.0)
		else:
			m["range"] = clampf(base_range * ar / br, 1.6, 18.0)
	else:
		m.erase("range")
	m["ranged"] = alt_ranged
	m["cd_k"] = clampf(float(ud.get("cool", 1.5)) / maxf(0.1, float(base.get("cool", 1.5))), 0.3, 12.0)
	var bs := float(base.get("speed", 0.0))
	if bs > 0.0:
		m["speed_k"] = clampf(float(ud.get("speed", bs)) / bs, 0.0, 2.0)
	m["damage"] = maxf(0.0, float(ud.get("damage", 0.0)) - float(base.get("damage", 0.0))) * W3Runtime.DMG_K


## Модель формы: модель героя (пак героев) или модель карты. Размер — как в WC3: модели карты в одних
## единицах, поэтому масштаб формы = (масштаб текущей модели / её масштаб в карте) × масштаб формы в карте.
static func _form_model(rt: W3Runtime, c: Unit, ud: Dictionary, cur_ud: Dictionary, _base: Dictionary) -> void:
	var path := str(ud.get("model", ""))
	var k := W3Model.norm_key(path)
	var cur_sc := maxf(0.1, float(cur_ud.get("scale", 1.0)))
	var new_sc := maxf(0.1, float(ud.get("scale", 1.0)))
	var cur_key := W3Model.norm_key(str(cur_ud.get("model", "")))
	if c.model == null:
		return
	if k == "" or k == "_" or k == cur_key:
		# та же модель — меняется только рост
		c.model.scale = c.model.scale * clampf(new_sc / cur_sc, 0.5, 2.0)
		return
	var gpn := c.model.scale.x / cur_sc
	var cur_h := HeroAssets._aabb(c.model, c.model.transform).size.y if not (c.model is W3Model) else 0.0
	var hm: Dictionary = rt.data.get("hero_models", {})
	var newm: Node3D = null
	var amap := {}
	if hm.has(k):
		var hid: String = hm[k]
		newm = HeroAssets.model_scene(hid).instantiate()
		var cfg := HeroAssets.config(hid)
		amap = HeroAssets.fit_model(newm, hid, 2.7).anim_map
		if cfg.has("model_height"):
			newm.scale = Vector3.ONE * gpn * new_sc
	elif W3Model.has_model(path):
		var wm := W3Model.create(path)
		if wm.fallback or wm.scene_root == null:
			wm.free()
			return
		wm.scale = Vector3.ONE * gpn * new_sc
		amap = _w3_anim_map(wm)
		newm = wm
	if newm == null:
		return
	# не больше двух ростов текущей модели и не меньше половины
	if cur_h > 0.1:
		var nh := HeroAssets._aabb(newm, newm.transform).size.y
		if nh > 0.01:
			var lim := clampf(nh, cur_h * 0.5, cur_h * 2.2)
			newm.scale *= lim / nh
	c.model.visible = false
	if c.anim:
		c.anim.stop()
	c.w3_anim_lock = 0.0
	c.cur_anim = ""
	c.attach_model(newm, amap)
	if c is Hero:
		var h := c as Hero
		World.recolor(newm, "TeamBand", Data.TEAM_COLORS[h.team], 0.35)
		h._collect_attack_variants()
		h._refresh_overlay()
	c.ghost = false


## Имена анимаций модели карты для движка юнита.
static func _w3_anim_map(wm: W3Model) -> Dictionary:
	var names := wm.anim_names()
	var m := {}
	for pair in [["Idle", "stand"], ["Run", "walk"], ["Attack", "attack"], ["Cast", "spell"], ["Death", "death"]]:
		var n := W3Model.pick_anim(names, pair[1])
		if n != "" and wm.ap and wm.ap.has_animation(n):
			m[pair[0]] = n
	if not m.has("Cast") and m.has("Attack"):
		m["Cast"] = m.Attack
	if not m.has("Run") and m.has("Idle"):
		m["Run"] = m.Idle
	return m


## Вернуть прежнюю форму (верхнюю в стопке форм).
static func unmorph(rt: W3Runtime, c: Unit) -> void:
	var d := rt._d(c)
	var stack: Array = d.get("morphs", [])
	if stack.is_empty():
		return
	var e: Dictionary = stack.pop_back()
	var old = e.model
	if c.model != old:
		var cur := c.model
		if is_instance_valid(cur):
			cur.queue_free()
		if is_instance_valid(old):
			(old as Node3D).visible = true
			W3Unit.set_alpha(old, 1.0)
			c.model = old
			c.anim = e.anim
			c.anim_map = e.anim_map
			c.model_base_pos = e.base_pos
	elif is_instance_valid(old):
		(old as Node3D).scale = e.scale
	c.attack_variants = e.variants
	c.missile_art = e.missile
	d.type = int(e.type)
	var ab: Dictionary = d.abils
	for aid in e.added:
		if ab.has(aid):
			ab.erase(aid)
			on_removed(rt, c, aid)
	if c is Hero:
		var h := c as Hero
		h.morph_mods = e.mods
		h.recalc_stats()
		h._refresh_overlay()
	else:
		var st: Dictionary = e.stats
		c.attack_range = float(st.range)
		c.ranged = bool(st.ranged)
		c.attack_cd = float(st.cd)
		c.base_damage = float(st.dmg)
		c.armor = float(st.armor)
		c.move_speed = float(st.speed)
		var k := c.hp / maxf(1.0, c.max_hp)
		c.max_hp = float(st.hp)
		c.hp = maxf(1.0, c.max_hp * k) if c.alive else c.hp
	c.ghost = false
	c.cur_anim = ""
	c.w3_anim_lock = 0.0
	if c.alive:
		c.play_anim("Idle")


static func unmorph_serial(rt: W3Runtime, c: Unit, ser: int) -> void:
	var stack: Array = rt._d(c).get("morphs", [])
	for k in range(stack.size() - 1, -1, -1):
		if int(stack[k].serial) == ser:
			while stack.size() > k:
				unmorph(rt, c)
			return


static func unmorph_all(rt: W3Runtime, c: Unit) -> void:
	if rt == null or c == null or not c.has_meta("w3"):
		return
	while not (rt._d(c).get("morphs", []) as Array).is_empty():
		unmorph(rt, c)


static func morphed(rt: W3Runtime, c: Unit) -> bool:
	return rt != null and c != null and c.has_meta("w3") and not (rt._d(c).get("morphs", []) as Array).is_empty()


# ------------------------------------------------------------------ иллюзии
static var _illusion_mat: StandardMaterial3D = null


## Иллюзии (Mirror Image, предметы-двойники): копии с моделью, атакой и здоровьем владельца.
## Наносят dealt × урона, получают taken × урона, исчезают через t секунд или от смерти.
## Владелец и иллюзии встают вперемешку, враг не знает, кто настоящий; свои видят иллюзии с голубым отливом.
static func make_illusions(rt: W3Runtime, c: Unit, n: int, dealt: float, taken: float, t: float, art := "") -> Array:
	var out: Array = []
	if rt == null or c == null or not c.alive:
		return out
	var tid := rt.unit_type_id(c)
	if tid == 0:
		return out
	var p = rt._d(c).get("player")
	var cp := c.global_position
	var spots: Array = [cp]
	for k in n:
		var ang := TAU * float(k) / float(n) + randf() * 0.6
		var q := cp + Vector3(cos(ang), 0, sin(ang)) * 2.4
		if Game.I and c.area != -99:
			q = Game.I.clamp_to_area(q, c.area)
		spots.append(q)
	spots.shuffle()
	if art != "":
		fx_at(rt, art, cp)
	c.global_position = spots[0]
	c.path.clear()
	var face := rt.GetUnitFacing(c)
	for k in n:
		var u := W3Unit.make(rt, tid, p, spots[k + 1], face)
		if u.dummy:
			u.w3_remove()
			continue
		u.illusion = true
		u.dmg_taken_k = maxf(0.0, taken)
		u.team = c.team
		u.area = c.area
		u.owner_unit = c
		u.display_name = c.display_name
		u.max_hp = c.max_hp
		u.hp = c.hp
		u.base_hp = c.max_hp
		u.max_mp = 0.0
		u.mp = 0.0
		u.base_damage = c.damage_value() * maxf(0.0, dealt)
		u.base_dmg = u.base_damage
		u.armor = c.armor
		u.base_armor = c.armor
		u.attack_range = c.attack_range
		u.ranged = c.ranged
		u.attack_cd = c.effective_attack_cd()
		u.move_speed = c.effective_speed()
		u.default_speed = u.move_speed
		u.missile_art = c.missile_art
		u.proj_color = c.proj_color
		u.radius = c.radius
		u.bar_height = c.bar_height
		u.timed_life = t
		u.bounty_gold = 0.0
		u.bounty_xp = 0.0
		u.attack_variants = c.attack_variants.duplicate()
		# рост как у владельца (модель героя в карте крупнее, чем у героя игры)
		if u.model and c.model and (c.model is W3Model) == (u.model is W3Model):
			u.model.scale = c.model.scale
			u.base_scale = c.model.scale.x
		if c.has_meta("w3"):
			rt._d(u)["spell_k"] = rt._d(c).get("spell_k", 1.0)
		if Game.I and Game.I.player and Game.I.player.team == c.team:
			_tint_illusion(u.model)
		out.append(u)
	return out


static func _tint_illusion(n: Node) -> void:
	if n == null:
		return
	if _illusion_mat == null:
		_illusion_mat = StandardMaterial3D.new()
		_illusion_mat.albedo_color = Color(0.35, 0.55, 1.0, 0.35)
		_illusion_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_illusion_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_illusion_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	if n is MeshInstance3D:
		(n as MeshInstance3D).material_overlay = _illusion_mat
	for ch in n.get_children():
		_tint_illusion(ch)


# ------------------------------------------------------------------ призывы
## Призыв юнитов карты (Water Elemental, Summon Bear, Spirit of Vengeance...) рядом с точкой на время t.
static func summon(rt: W3Runtime, c: Unit, tid: String, n: int, t: float, at: Vector3) -> Array:
	var out: Array = []
	if udata_of(rt, tid).is_empty():
		return out
	var p = rt._d(c).get("player")
	var face := rt.GetUnitFacing(c)
	for k in n:
		var ang := TAU * float(k) / float(maxi(n, 1)) + randf() * 0.5
		var q := at + (Vector3(cos(ang), 0, sin(ang)) * 1.6 if n > 1 else Vector3.ZERO)
		if Game.I and c.area != -99:
			q = Game.I.clamp_to_area(q, c.area)
		var u := W3Unit.make(rt, W3Runtime.fcc(tid), p, q, face)
		if u.dummy:
			u.w3_remove()
			continue
		u.area = c.area
		if not (p is W3Runtime.JPlayer):
			u.team = c.team
		if u.owner_unit == null and c is Hero:
			u.owner_unit = c
		if t > 0.0:
			u.timed_life = t
		if u.model == null or (u.w3m and u.w3m.fallback):
			_plain_body(u, Color(0.55, 0.6, 1.0))
		out.append(u)
	return out


## Модели призванного нет в паке — простое тело беса нужного цвета.
static func _plain_body(u: W3Unit, col: Color) -> void:
	if u.w3m and is_instance_valid(u.w3m):
		u.w3m.queue_free()
	u.w3m = null
	u.model = null
	u.setup_model("res://models/creep_imp.glb", 1.4)
	World.recolor(u.model, "ImpSkin", col, 0.05)
	u.base_scale = 1.4
	u.radius = maxf(u.radius, 0.55)
	u.bar_height = 2.2


## Павшие недавно (для Animate Dead): позиция, остров, характеристики.
static var corpses: Array = []


static func note_corpse(u: Unit) -> void:
	if u == null or u is Hero or u.illusion or (u is W3Unit and (u as W3Unit).dummy) or Game.I == null:
		return
	corpses.append({"pos": u.global_position, "area": u.area, "hp": u.max_hp, "dmg": u.base_damage,
		"armor": u.armor, "t": Game.I.time, "name": u.display_name})
	if corpses.size() > 64:
		corpses.pop_front()


## Animate Dead: поднять n павших рядом (самых свежих) на время t; если павших нет — встают у героя.
static func raise_dead(rt: W3Runtime, c: Unit, n: int, t: float, r: float, art: String) -> void:
	var got: Array = []
	for k in range(corpses.size() - 1, -1, -1):
		var cr: Dictionary = corpses[k]
		if int(cr.area) == c.area and Game.I.time - float(cr.t) < 90.0 and \
				Vector2(cr.pos.x - c.global_position.x, cr.pos.z - c.global_position.z).length() <= r:
			got.append(cr)
			corpses.remove_at(k)
			if got.size() >= n:
				break
	var p = rt._d(c).get("player")
	var lvl := float(c.get("level")) if c is Hero else 10.0
	while got.size() < n:
		var ang := randf() * TAU
		got.append({"pos": c.global_position + Vector3(cos(ang), 0, sin(ang)) * 2.0, "hp": 300.0 + 60.0 * lvl,
			"dmg": 20.0 + 4.0 * lvl, "armor": 2.0, "name": "Мертвец"})
	for cr in got:
		var q: Vector3 = cr.pos
		if Game.I and c.area != -99:
			q = Game.I.clamp_to_area(q, c.area)
		var ud := {"name": "Восставший " + str(cr.name), "model": "", "hp": float(cr.hp), "damage": float(cr.dmg) / W3Runtime.DMG_K,
			"armor": float(cr.armor), "speed": 260.0, "range": 100.0, "cool": 1.4, "abilities": []}
		var u := W3Unit.make(rt, W3Runtime.fcc("uske"), p, q, rt.GetUnitFacing(c), ud)
		u.area = c.area
		u.team = c.team
		u.owner_unit = c
		u.timed_life = t
		_plain_body(u, Color(0.35, 0.3, 0.45))
		if art != "":
			fx_at(rt, art, q)


# ------------------------------------------------------------------ невидимость
## Wind Walk: невидимость на время, прибавка бега; первый удар из невидимости — дополнительный урон.
static func wind_walk(rt: W3Runtime, c: Unit, lv: Dictionary) -> void:
	var t := maxf(1.0, dur_for(lv, c))
	c.invis = t
	var mv := float(lv.get("b", 0.0))
	mv = minf(mv if mv <= 1.0 else 0.5, 0.5)
	if c is Hero:
		(c as Hero).add_buff("w3_windwalk", {"name": "Шаг ветра", "move": mv}, t)
	else:
		c.bonus_move = maxf(c.bonus_move, mv)
		c.buff_time = maxf(c.buff_time, t)
	var bonus := float(lv.get("c", 0.0))
	if bonus > 0.0:
		rt._d(c)["windwalk"] = bonus


## Постоянная невидимость от способностей (Apiv): пока способность у юнита.
static func _update_perm_invis(rt: W3Runtime, u: Unit) -> void:
	var on := false
	for id in all_abils(rt, u):
		if str(adata(rt, id).get("code", "")) in INVIS_T:
			on = true
			break
	u.perm_invis = on


# ------------------------------------------------------------------ Immolation (вкл/выкл)
## Включается и выключается той же кнопкой: пока включена — бафф (его ждут триггеры), урон вокруг
## каждую секунду и расход маны; без маны выключается сама.
static func _toggle_immolation(rt: W3Runtime, c: Unit, id: int, lv: Dictionary) -> void:
	var d := rt._d(c)
	if not d.has("immo"):
		d["immo"] = {}
	var im: Dictionary = d.immo
	if im.has(id):
		var st: Dictionary = im[id]
		im.erase(id)
		for one in str(st.buff).split(","):
			if one.length() == 4:
				remove_buff(rt, c, W3Runtime.fcc(one))
		return
	if lv.is_empty():
		return
	var need := float(lv.get("c", 0.0))
	if c.max_mp > 0.0 and c.mp < minf(need, c.max_mp * 0.5):
		return
	_morph_serial += 1
	var ser := _morph_serial
	var st2 := {"buff": str(lv.get("buff", "")), "serial": ser}
	im[id] = st2
	for one in str(st2.buff).split(","):
		if one.length() == 4:
			add_buff(rt, c, W3Runtime.fcc(one), 1e6)
	var dps := float(lv.get("a", 0.0))
	var drain := float(lv.get("b", 0.0))
	var r := maxf(float(lv.get("area", 0.0)) * W3Runtime.U, 1.0)
	var art: Dictionary = adata(rt, id).get("art", {})
	var step := func(self_ref: Callable) -> void:
		if not is_instance_valid(c) or not c.alive or not im.has(id) or int(im[id].serial) != ser:
			if is_instance_valid(c) and im.has(id) and int(im[id].serial) == ser:
				_toggle_immolation(rt, c, id, {})
			return
		if drain > 0.0 and c.max_mp > 0.0:
			if c.mp < drain:
				_toggle_immolation(rt, c, id, {})
				return
			c.mp -= drain
		if dps > 0.0 and r > 1.01:
			for e in enemies(rt, c, c.global_position, r):
				dmg(rt, c, e, dps * flat_k(c))
				fx_on(rt, art.get("target", ""), e, "chest")
		rt.get_tree().create_timer(1.0, false, true).timeout.connect(func() -> void: self_ref.call(self_ref))
	step.call(step)


# ------------------------------------------------------------------ Reincarnation
## Перерождение (AOre): вместо смерти юнит падает и встаёт через a секунд с полным здоровьем
## (раз в перезарядку способности).
static func try_reincarnate(rt: W3Runtime, u: Unit) -> bool:
	if rt == null or u == null or not u.has_meta("w3") or Game.I == null or u.illusion:
		return false
	var d := rt._d(u)
	var ab := all_abils(rt, u)
	for id in ab:
		var ad := adata(rt, id)
		if str(ad.get("code", "")) != "AOre":
			continue
		var lv := lvdata(ad, int(ab[id]))
		var key := "reinc_" + str(id)
		if float(d.get(key, -1e9)) > Game.I.time:
			continue
		d[key] = Game.I.time + maxf(10.0, float(lv.get("cool", 120.0)))
		var delay := clampf(float(lv.get("a", 7.0)), 0.5, 15.0)
		u.hp = 1.0
		u.invulnerable = maxf(u.invulnerable, delay + 1.0)
		u.w3_paused = true
		u.swing_left = -1.0
		u.order = "idle"
		u.target_unit = null
		u.play_anim("Death", 1.0, true)
		u.w3_anim_lock = delay
		var art: Dictionary = ad.get("art", {})
		rt.get_tree().create_timer(delay, false).timeout.connect(func() -> void:
			if not is_instance_valid(u) or not u.alive:
				return
			u.w3_paused = bool(rt._d(u).get("paused", false))
			u.w3_anim_lock = 0.0
			u.hp = u.max_hp
			u.mp = u.max_mp
			u.cur_anim = ""
			u.play_anim("Idle")
			fx_at(rt, art.get("effect", "") if str(art.get("effect", "")) != "" else \
				"Abilities\\Spells\\Orc\\Reincarnation\\ReincarnationTarget.mdl", u.global_position))
		return true
	return false

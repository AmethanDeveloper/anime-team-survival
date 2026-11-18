class_name Hero
extends Unit
## Герой: атрибуты (Сила / Ловкость / Интеллект), уровни, способности, предметы, усиления, воскрешение.

const TATTOO_SHADER := """
shader_type spatial;
render_mode blend_mix, unshaded, cull_back, depth_draw_never;
uniform vec4 tint : source_color = vec4(0.9, 0.05, 0.1, 1.0);
uniform float strength = 1.0;
varying vec3 lpos;
float hash(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float noise(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
void vertex() { lpos = VERTEX; }
void fragment() {
	float n = noise(lpos * 9.0) * 0.6 + noise(lpos * 21.0) * 0.4;
	float vein = 1.0 - smoothstep(0.0, 0.06, abs(n - 0.5));
	float pulse = 0.6 + 0.4 * sin(TIME * 4.0 + lpos.y * 6.0);
	vec3 col = mix(vec3(0.02, 0.0, 0.0), tint.rgb * 2.0, pulse);
	ALBEDO = col;
	ALPHA = vein * strength * 0.95;
}
"""

const AURA_SHADER := """
shader_type spatial;
render_mode blend_add, unshaded, cull_back, depth_draw_never;
uniform vec4 tint : source_color = vec4(1.0, 0.2, 0.1, 1.0);
uniform float strength = 1.0;
void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.2);
	float pulse = 0.75 + 0.25 * sin(TIME * 6.0);
	ALBEDO = tint.rgb * 2.0;
	ALPHA = rim * strength * pulse;
}
"""

static var _tattoo_shader: Shader = null
static var _aura_shader: Shader = null

var hero_id := ""
var def := {}
var level := 1
var xp := 0.0
var gold := 0
var abilities: Array = []  # [{id, def, cd}]
var items: Array = ["", "", "", "", "", ""]
var stash: Array = ["", "", "", "", "", ""]
var item_ch: Array = [0, 0, 0, 0, 0, 0]
var stash_ch: Array = [0, 0, 0, 0, 0, 0]
## «В лагере»: куплено вне лагеря, ждёт курьера (или героя в лагере)
var base_items: Array = ["", "", "", "", "", ""]
var base_ch: Array = [0, 0, 0, 0, 0, 0]
var courier: Courier = null
var _collect_t := 0.0
var item_cd := {}
var w3_cd := {}   # перезарядка подменённых триггерами способностей (второй этап), по коду способности
var tome := {"str": 0.0, "agi": 0.0, "int": 0.0, "damage": 0.0}
var respawn_left := 0.0
var is_player := false
var ai: HeroAI = null
var kills := 0
var deaths := 0
var creep_kills := 0
var dueling := false
var pending := {}
## Каст телепорта (круг «2», врата или свиток): {pad, t, dur, nodes, scroll?}
var chan := {}
var resume_target: Unit = null
var last_hit_by: Hero = null
var last_hit_time := 0.0

# атрибуты
var s_str := 0.0
var s_agi := 0.0
var s_int := 0.0
var spell_amp := 0.0
var crit_chance := 0.0
var crit_mult := 2.0
var evasion := 0.0
var lifesteal := 0.0
var item_attack_speed := 0.0
var cdr := 0.0
var dmg_mult := 1.0
var souls := 0
## Прокачка: уровни Q, W, E, R; свободные очки; очки, вложенные в атрибуты; выбранные таланты (−1 — ещё не выбран)
var skill: Array[int] = [0, 0, 0, 0]
var skill_points := 1
var stat_points := 0
var talents: Array[int] = [-1, -1, -1, -1]
# пассивные свойства предметов
var seven := 0.0
var cold := false
var stun_chance := 0.0
var reflect := 0.0
var absorb := 0.0
var mana_burn := 0.0
var reduction := 0.0
var aura_armor := 0.0
var aura_bonus := 0.0
var burn := 0.0
var vision_bonus := 0.0
var stealth := false
var _aura_t := 0.0
var _burn_t := 0.0

# усиления: id -> {t, def}
var buffs := {}
var overlay_mat: ShaderMaterial = null
## Перевоплощение (W3Abil.morph): прибавки и замены характеристик альтернативной формы
## str, armor, hp — прибавки; range, ranged, cd_k, speed_k, damage — атака и движение формы.
var morph_mods := {}


func setup(id: String, t: int, player: bool) -> void:
	hero_id = id
	def = Data.HEROES[id]
	kind = Kind.HERO
	team = t
	home_zone = t
	area = t
	is_player = player
	display_name = def.name
	ranged = def.ranged
	proj_color = Color(def.color).lightened(0.25)
	radius = 0.65
	gold = Data.START_GOLD
	for a in def.abilities:
		abilities.append({"id": a, "def": Data.ABILITIES[a], "cd": 0.0})
	# личный предмет Ex не занимает ячейку: игрок его не видит, он нужен только для сборки сета
	ex_item = "ex_" + id if Data.ITEMS.has("ex_" + id) else ""
	if not player or (Game.I and Game.I.auto_skills()):
		auto_learn()
	recalc_stats(true)
	var m: Node3D = HeroAssets.model_scene(id).instantiate()
	var info := HeroAssets.fit_model(m, id, 2.7)
	attach_model(m, info.anim_map)
	World.recolor(model, "TeamBand", Data.TEAM_COLORS[t], 0.35)
	bar_height = 3.3
	_collect_attack_variants()


## Анимации атаки модели героя: все «Attack», «Attack 2», «Attack Slam»..., кроме служебных.
func _collect_attack_variants() -> void:
	attack_variants.clear()
	if anim == null:
		return
	var base: String = anim_map.get("Attack", "")
	for n in anim.get_animation_list():
		var low := String(n).to_lower()
		if not low.begins_with("attack"):
			continue
		if low.contains("walk") or low.contains("stand") or low.contains("spell") or low.contains("defend"):
			continue
		var a := anim.get_animation(n)
		if a.length < 0.25 or a.length > 2.2:
			continue
		attack_variants.append(n)
	if base != "" and not attack_variants.has(base):
		attack_variants.append(base)
	if attack_variants.size() > 4:
		attack_variants = attack_variants.slice(0, 4)
	var mu: String = def.get("map_unit", "")
	if ranged and mu != "" and W3Runtime.I == null:
		pass
	missile_art = _map_missile(mu)


static func _map_missile(mu: String) -> String:
	if mu == "":
		return ""
	var f := FileAccess.open("res://w3/w3_data.json", FileAccess.READ)
	if f == null:
		return ""
	if not _missiles_loaded:
		_missiles_loaded = true
		var d = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			for k in (d.get("units", {}) as Dictionary):
				var m: String = str(d.units[k].get("missile", ""))
				if m != "" and m != "_":
					_missiles[k] = m
	return _missiles.get(mu, "")


static var _missiles := {}
static var _missiles_loaded := false


# ----------------------------------------------------------------- атрибуты и статы
## Уровень способности в ячейке i: Q, W, E, R — по вложенным очкам; остальные открыты всегда.
func skill_level(i: int) -> int:
	return skill[i] if i < 4 else 1


## Можно ли сейчас вложить очко в способность i (пустая строка — можно).
func learn_error(i: int) -> String:
	if i < 0 or i >= 4 or i >= abilities.size() or abilities[i].def.type == "empty":
		return "Нет способности"
	if skill_points <= 0:
		return "Нет очков навыков"
	if skill[i] >= Data.SKILL_MAX[i]:
		return "Максимальный уровень"
	var need: int = Data.ULT_LEVELS[skill[i]] if i == 3 else skill[i] * 2 + 1
	if level < need:
		return "Нужен %d уровень героя" % need
	return ""


func learn(i: int) -> bool:
	if learn_error(i) != "":
		return false
	skill[i] += 1
	skill_points -= 1
	if W3Runtime.I:
		W3Abil.update_levels(W3Runtime.I, self)
	recalc_stats()
	if is_player and Game.I and Game.I.hud:
		Audio.sfx("buff_up", null, 0.5)
	return true


## Очко в атрибуты: когда способности вкачаны или игрок так решил.
func learn_stats() -> bool:
	if skill_points <= 0:
		return false
	skill_points -= 1
	stat_points += 1
	recalc_stats()
	return true


## Номер таланта, который ждёт выбора (−1 — нет).
func talent_pending() -> int:
	for t in talents.size():
		if talents[t] < 0 and level >= Data.TALENT_LEVELS[t]:
			return t
	return -1


func pick_talent(t: int, opt: int) -> void:
	if t < 0 or t >= talents.size() or talents[t] >= 0 or level < Data.TALENT_LEVELS[t]:
		return
	talents[t] = clampi(opt, 0, 1)
	recalc_stats()


## Бот вкладывает очки сам: ульт, как только можно; иначе по порядку из bot_skills героя (по умолчанию Q, E, W).
func auto_learn() -> void:
	var order: Array = def.get("bot_skills", [3, 0, 2, 1])
	var guard := 0
	while skill_points > 0 and guard < 60:
		guard += 1
		var done := false
		for i in order:
			if learn(int(i)):
				done = true
				break
		if not done:
			var full := true
			for i in 4:
				if i < abilities.size() and abilities[i].def.type != "empty" and skill[i] < Data.SKILL_MAX[i]:
					full = false
			if not full:
				break   # очки ждут нужного уровня героя
			learn_stats()
	var t := talent_pending()
	while t >= 0:
		pick_talent(t, 0 if def.primary == "str" or (def.primary == "agi" and t % 2 == 0) else 1)
		t = talent_pending()


func _item_sum(key: String) -> float:
	var s := 0.0
	for t in talents.size():
		if talents[t] >= 0:
			s += float(Data.TALENTS[t][talents[t]].get(key, 0.0))
	if key == "all":
		s += stat_points * Data.STAT_POINT
	for it in items:
		if it != "":
			s += float(Data.ITEMS[it].get(key, 0.0))
	return s


func buff_sum(key: String) -> float:
	var s := 0.0
	for b in buffs.values():
		s += float(b.def.get(key, 0.0))
	return s


func has_buff(id: String) -> bool:
	return buffs.has(id)


## Пассивные способности героя (тип passive с полем stats), которые уже открыты по уровню.
func passive_sum(key: String) -> float:
	var s := 0.0
	for i in abilities.size():
		var a: Dictionary = abilities[i].def
		if a.type == "passive" and a.has("stats") and skill_level(i) > 0:
			s += float(a.stats.get(key, 0.0))
	return s


func recalc_stats(full := false) -> void:
	var hp_k := hp / max_hp if max_hp > 0 else 1.0
	var mp_k := mp / max_mp if max_mp > 0 else 1.0
	var l := float(level - 1)
	var all := _item_sum("all")
	s_str = def.str + def.str_lvl * l + _item_sum("str") + all + tome.str + passive_sum("str")
	s_agi = def.agi + def.agi_lvl * l + _item_sum("agi") + all + tome.agi + passive_sum("agi")
	s_int = def.int + def.int_lvl * l + _item_sum("int") + all + tome.int + passive_sum("int")
	var wa := W3Abil.attr_mods(self)
	s_str += float(morph_mods.get("str", 0.0)) + float(wa.str)
	s_agi += float(wa.agi)
	s_int += float(wa.int)
	s_str *= 1.0 + buff_sum("str_mult")
	var prim := s_str
	if def.primary == "agi":
		prim = s_agi
	elif def.primary == "int":
		prim = s_int
	max_hp = def.hp + s_str * Data.STR_HP + _item_sum("hp") + float(morph_mods.get("hp", 0.0))
	max_mp = def.mp + s_int * Data.INT_MP + _item_sum("mp")
	hp_regen = 0.5 + s_str * Data.STR_REGEN + _item_sum("hp_regen") + passive_sum("hp_regen")
	mp_regen = 0.3 + s_int * Data.INT_REGEN + _item_sum("mp_regen") + passive_sum("mp_regen")
	base_damage = def.damage + prim + _item_sum("damage") + tome.damage + float(morph_mods.get("damage", 0.0)) \
		+ s_agi * float(morph_mods.get("agi_dmg", 0.0)) * W3Runtime.DMG_K
	armor = def.armor + s_agi * Data.AGI_ARMOR + _item_sum("armor") + buff_sum("armor") + aura_bonus + passive_sum("armor") \
		+ float(morph_mods.get("armor", 0.0))
	move_speed = (def.speed + _item_sum("speed")) * float(morph_mods.get("speed_k", 1.0))
	attack_range = float(morph_mods.get("range", def.range)) + buff_sum("range")
	attack_cd = def.cd * float(morph_mods.get("cd_k", 1.0))
	ranged = bool(morph_mods.get("ranged", def.ranged))
	item_attack_speed = s_agi * Data.AGI_AS + _item_sum("attack_speed") + buff_sum("attack_speed") + passive_sum("attack_speed")
	spell_amp = _item_sum("spell_amp")
	# крит не складывается: берётся лучший источник (как в WC3)
	crit_chance = float(def.get("crit_chance", 0.0))
	crit_mult = float(def.get("crit_mult", 2.0))
	for it in items:
		if it != "" and Data.ITEMS[it].has("crit_chance"):
			var d: Dictionary = Data.ITEMS[it]
			if float(d.crit_chance) * float(d.crit_mult) > crit_chance * crit_mult:
				crit_chance = d.crit_chance
				crit_mult = d.crit_mult
	evasion = minf(float(def.get("evasion", 0.0)) + _item_sum("evasion") + passive_sum("evasion") + buff_sum("evasion"), 0.5)
	lifesteal = float(def.get("lifesteal", 0.0)) + _item_sum("lifesteal") + buff_sum("lifesteal") + passive_sum("lifesteal")
	seven = _item_sum("seven") + passive_sum("seven")
	cold = _item_sum("cold") > 0.0
	stun_chance = minf(_item_sum("stun_chance"), 0.3)
	reflect = minf(_item_sum("reflect"), 0.5)
	absorb = _item_sum("absorb")
	mana_burn = _item_sum("mana_burn") + passive_sum("mana_burn")
	# у героя 15% сопротивления магии от природы, остальное — предметы, баффы, формы (Сусаноо)
	magic_resist = minf(0.15 + _item_sum("magic_resist") + buff_sum("magic_resist") + passive_sum("magic_resist")
		+ float(morph_mods.get("mres", 0.0)), 0.75)
	reduction = minf(_item_sum("reduction") + buff_sum("reduction") + passive_sum("reduction"), 0.5)
	aura_armor = 0.0
	burn = 0.0
	vision_bonus = 0.0
	for it in items:
		if it != "":
			var d2: Dictionary = Data.ITEMS[it]
			aura_armor = maxf(aura_armor, float(d2.get("aura_armor", 0.0)))
			burn = maxf(burn, float(d2.get("burn", 0.0)))
			vision_bonus = maxf(vision_bonus, float(d2.get("vision", 0.0)))
	stealth = _item_sum("stealth") > 0.0
	cdr = buff_sum("cdr")
	bonus_move = buff_sum("move") + passive_sum("move")
	dmg_mult = 1.0 + buff_sum("dmg_mult") + passive_sum("dmg_mult")
	if buffs.has("akame_d"):
		dmg_mult += float(buffs.akame_d.def.per_soul) * souls
	if buffs.has("weak"):
		dmg_mult *= 0.5
	if hero_id == "akame" and skill_level(1) > 0:
		dmg_mult *= 1.0 + float(Data.ABILITIES.akame_w.get("soul_bonus", 0.0)) * souls
	if hero_id == "esdeath" and skill_level(1) > 0:
		armor += float(Data.ABILITIES.esdeath_w.get("armor", 0.0)) + s_int * float(Data.ABILITIES.esdeath_w.get("armor_int", 0.0))
	for b in buffs.values():
		if b.has("bonus_hp"):
			max_hp += b.bonus_hp
	# пассивные способности карты (Critical Strike, Evasion, Bash, ауры) и усиления от её заклинаний
	var wm := W3Abil.passive_mods(self)
	if float(wm.crit) * maxf(float(wm.crit_mult), 1.0) > crit_chance * crit_mult:
		crit_chance = minf(float(wm.crit), 0.9)
		crit_mult = maxf(float(wm.crit_mult), 1.5)
	evasion = minf(evasion + float(wm.evasion), 0.6)
	# баффы с критом (Шаринган Итачи)
	for bf in buffs.values():
		if bf.def.has("crit") and float(bf.def.crit) * float(bf.def.crit_mult) > crit_chance * crit_mult:
			crit_chance = float(bf.def.crit)
			crit_mult = float(bf.def.crit_mult)
	stun_chance = minf(stun_chance + float(wm.bash), 0.4)
	lifesteal += float(wm.lifesteal)
	armor += float(wm.armor)
	item_attack_speed += float(wm.attack_speed)
	bonus_move += float(wm.move)
	hp_regen += float(wm.hp_regen)
	mp_regen += float(wm.mp_regen)
	dmg_mult *= 1.0 + float(wm.damage_pct) + buff_sum("damage_pct")
	if full:
		hp = max_hp
		mp = max_mp
	else:
		hp = clampf(max_hp * hp_k, 1.0, max_hp)
		mp = max_mp * mp_k


func damage_value() -> float:
	return base_damage * dmg_mult


func effective_attack_cd() -> float:
	var as_mult := 1.0 + bonus_attack_speed + item_attack_speed
	if slow_time > 0.0:
		as_mult *= (1.0 - slow * 0.5)
	return attack_cd / clampf(as_mult, 0.2, 5.0)


func acquire_range() -> float:
	return maxf(attack_range + 3.0, 7.0)


func stat_power(a: Dictionary) -> float:
	var base := float(a.get("str", 0.0)) * s_str + float(a.get("agi", 0.0)) * s_agi + float(a.get("int", 0.0)) * s_int
	return base * (1.0 + 0.1 * (level - 1)) * dmg_mult * (1.0 + spell_amp)


func ability_power(i: int) -> float:
	return stat_power(abilities[i].def)


# ----------------------------------------------------------------- атака
func roll_attack(t: Unit) -> Array:
	var d := damage_value() * (1.0 + seven)
	var crit := false
	if buffs.has("dark_seal"):
		d *= maxf(crit_mult, 2.5)
		crit = true
	elif crit_chance > 0.0 and randf() < crit_chance:
		d *= crit_mult
		crit = true
	if buffs.has("akame_r"):
		var a: Dictionary = buffs.akame_r.def
		d += stat_power(a)
	return [d, crit]


func on_attack_landed(t: Unit) -> void:
	if W3Runtime.I:
		W3Abil.on_attack(W3Runtime.I, self, t)
	if t is Hero:
		(t as Hero).last_hit_by = self
		(t as Hero).last_hit_time = 6.0
	Audio.sfx("hit", t.global_position, 0.55, 0.15, 0.04)
	if buffs.has("akame_r"):
		var a: Dictionary = buffs.akame_r.def
		t.apply_poison(self, stat_power(a) * float(a.poison), float(a.poison_time))
	if buffs.has("akame_d") and randf() < float(buffs.akame_d.def.auto_slash):
		var a2: Dictionary = buffs.akame_d.def
		Abilities.auto_slash(self, t.global_position, stat_power(a2))
	var fc := float(def.get("freeze_chance", 0.0))
	if fc > 0.0 and level >= 1 and randf() < fc and t.alive:
		t.apply_freeze(float(def.freeze_time))
		Audio.sfx("freeze", t.global_position, 0.7)
	invis = 0.0
	_splash(t)
	if not t.alive:
		return
	if cold:
		t.apply_slow(0.25, 1.5)
	if stun_chance > 0.0 and randf() < stun_chance:
		t.apply_stun(1.0)
	if mana_burn > 0.0 and t is Hero:
		t.mp = maxf(0.0, t.mp - mana_burn)
		mp = minf(max_mp, mp + mana_burn * 0.5)


## Удар по области (Сусаноо): 100% урона атаки в радиусе splash вокруг цели, 50% — до 1.5 радиуса.
func _splash(t: Unit) -> void:
	var r := float(morph_mods.get("splash", 0.0))
	if r <= 0.0 or Game.I == null:
		return
	var c := t.global_position
	var dv := damage_value()
	for e in Game.I.enemies_in_radius(c, r * 1.5, self, false):
		if e == t or not e.alive:
			continue
		var d := maxf(0.0, Vector2(e.global_position.x - c.x, e.global_position.z - c.z).length() - e.radius)
		Game.I.deal_damage(self, e, dv * (1.0 if d <= r else 0.5), "attack")
	if Game.I.camera and Game.I.camera.focus.distance_to(c) < 45.0:
		Fx.ring_burst(Game.I.fx_root, c, r * 1.5, Color(0.42, 0.55, 1.0), 0.35, 0.45)


# ----------------------------------------------------------------- опыт
func add_xp(amount: float) -> void:
	if level >= Data.MAX_LEVEL:
		return
	xp += amount
	var up := false
	while level < Data.MAX_LEVEL and xp >= Data.xp_to_next(level):
		xp -= Data.xp_to_next(level)
		level += 1
		skill_points += 1
		up = true
		if not is_player or (Game.I and Game.I.auto_skills()):
			auto_learn()
		recalc_stats()
		if W3Runtime.I:
			W3Abil.update_levels(W3Runtime.I, self)
		hp = minf(max_hp, hp + max_hp * 0.25)
	if up:
		Fx.ring_burst(Game.I.fx_root, global_position, 2.5, Color(1.0, 0.85, 0.3), 0.6)
		Fx.pillar(Game.I.fx_root, global_position, 1.0, 4.0, Color(1.0, 0.85, 0.35), 0.8)
		if is_player:
			Game.I.hud.announce("Уровень %d!" % level, Color(1.0, 0.85, 0.35), 1.6)
			Audio.sfx("level_up", null, 0.8)
			Audio.voice(hero_id, "level", 0.6)


func add_soul() -> void:
	if hero_id != "akame" or skill_level(1) <= 0 or souls >= int(Data.ABILITIES.akame_w.get("max_souls", 0)):
		return
	souls += 1
	recalc_stats()
	Fx.burst(Game.I.fx_root, global_position + Vector3(0, 1.5, 0), Color(0.9, 0.1, 0.2), 16, 3.0, 0.3, 0.6)
	if is_player:
		Game.I.hud.add_float_text(global_position + Vector3(0, 4.0, 0), "+душа (%d)" % souls, Color(1.0, 0.3, 0.35), true)


# ----------------------------------------------------------------- способности
func ability_slots() -> int:
	return abilities.size()


## Как выбирается цель способности (у Акаме в Метаморфозе [D] становится телепортом в точку).
func ability_target(i: int) -> String:
	if i == 4 and hero_id == "akame" and has_buff("akame_d"):
		return "point"
	var ov := w3_slot(i)
	if not ov.is_empty():
		return ov.target
	return abilities[i].def.target


func ability_range(i: int) -> float:
	if i == 4 and hero_id == "akame" and has_buff("akame_d"):
		return float(abilities[4].def.blink_range)
	var ov := w3_slot(i)
	if not ov.is_empty():
		return maxf(float(ov.range), 1.5)
	return float(abilities[i].def.get("range", 0.0))


## Второй этап способности карты, если триггеры сейчас подменили ячейку (иначе пусто).
func w3_slot(i: int) -> Dictionary:
	if i >= abilities.size() or abilities[i].def.type != "w3" or W3Runtime.I == null:
		return {}
	return W3Abil.slot_info(W3Runtime.I, self, i)


## Скрытый личный предмет героя (Ex): учитывается в рецептах, в инвентаре не показывается.
var ex_item := ""


func has_set() -> bool:
	return items.has("set_" + hero_id)


func cast_error(i: int) -> String:
	if not alive:
		return "Герой мёртв"
	var a: Dictionary = abilities[i].def
	if a.type == "empty":
		return "Нет способности"
	if silence > 0.0:
		return "Немота: способности отключены"
	if a.type == "book":
		return "Книга заклинаний: способности на клавишах F, G, V"
	if a.type == "passive":
		return "Это пассивная способность"
	if a.type == "w3" and W3Runtime.I and not W3Abil.available(W3Runtime.I, self, i):
		return "Сейчас недоступно"
	var ov := w3_slot(i)
	if not ov.is_empty():
		if float(w3_cd.get(ov.id, 0.0)) > 0.0:
			return "Ещё не готово"
		if mp < float(ov.mana):
			return "Не хватает маны"
		return "Оглушение" if stun > 0.0 else ""
	if a.get("set", false):
		if not has_set():
			return "Нужен Ультимативный сет героя"
		if i == 4 and hero_id == "akame" and has_buff("akame_d"):
			return "" if stun <= 0.0 else "Оглушение"
	elif skill_level(i) <= 0:
		return "Способность не изучена"
	if abilities[i].cd > 0.0:
		return "Ещё не готово"
	if mp < a.mana:
		return "Не хватает маны"
	if stun > 0.0:
		return "Оглушение"
	return ""


func cast(i: int, point: Vector3, unit: Unit = null) -> bool:
	if cast_error(i) != "":
		return false
	var a: Dictionary = abilities[i].def
	# Акаме в Метаморфозе: [D] — мгновенный шаг
	if i == 4 and hero_id == "akame" and has_buff("akame_d"):
		Abilities.instant_step(self, point, float(a.blink_range))
		return true
	var tk := ability_target(i)
	if tk == "unit" and (unit == null or not unit.alive or not is_enemy(unit) or unit.area != area):
		return false
	if order == "attack" and valid_target(target_unit):
		resume_target = target_unit
	else:
		resume_target = null
	pending = {"i": i, "point": point, "unit": unit, "target": tk}
	var ov := w3_slot(i)
	if not ov.is_empty():
		pending["w3id"] = ov.id
	order = "cast"
	return true


func _process_cast(delta: float) -> void:
	if pending.is_empty():
		order = "idle"
		return
	var i: int = pending.i
	var a: Dictionary = abilities[i].def
	var p: Vector3 = pending.point
	var u: Unit = pending.unit
	var need_range := -1.0
	match a.type:
		"ice_blocks", "aoe_point":
			need_range = a.range
		"w3":
			var tk: String = pending.get("target", a.target)
			if tk == "point":
				need_range = ability_range(i)
			elif tk == "unit":
				if u == null or not is_instance_valid(u) or not u.alive or u.area != area:
					pending = {}
					order = "idle"
					return
				p = u.global_position
				pending.point = p
				need_range = ability_range(i) + u.radius
		"bolt":
			if u == null or not is_instance_valid(u) or not u.alive or u.area != area:
				pending = {}
				order = "idle"
				return
			p = u.global_position
			pending.point = p
			need_range = a.range
	if need_range > 0.0 and flat_dist_p(p) > need_range:
		move_to(p, delta)
		return
	if str(pending.get("target", a.target)) != "none":
		yaw_target = yaw_to(p)
	var windup := 0.25
	var anim_name := "Cast"
	if a.type in ["leap_strike", "slashes", "line", "mugetsu"]:
		anim_name = "Attack"
		windup = 0.2
	if a.type in ["empower", "transform", "blink", "metamorphosis"]:
		windup = 0.12
	if a.type == "time_stop":
		windup = 0.35
	cast_lock = windup
	swing_left = -1.0
	if a.type == "w3":
		# анимацию заклинания запускает W3Abil (имя из данных карты)
		cast_lock = 0.15
		return
	play_anim(anim_name, 1.6, true)


func _on_cast_finished() -> void:
	if pending.is_empty() or not alive:
		pending = {}
		return
	var i: int = pending.i
	var a: Dictionary = abilities[i].def
	var pu: Variant = pending.get("unit")
	if pu != null and not is_instance_valid(pu):
		pu = null
	if str(pending.get("target", a.target)) == "unit" and (pu == null or not (pu as Unit).alive):
		pending = {}
		order = "idle"
		return
	var ov := w3_slot(i)
	if int(ov.get("id", 0)) != int(pending.get("w3id", 0)):
		pending = {}
		order = "idle"
		return
	if cast_error(i) == "":
		invis = 0.0
		if not ov.is_empty():
			mp -= float(ov.mana)
			w3_cd[ov.id] = float(ov.cd) * (1.0 - cdr)
		else:
			mp -= a.mana
			abilities[i].cd = a.cd * (1.0 - cdr)
		if a.get("set", false) and Game.I and Game.I.hud and (is_player or (Game.I.camera and \
				Game.I.camera.focus.distance_to(global_position) < 30.0)):
			Game.I.hud.super_ult_cutin(self, a)
		Abilities.execute(self, i, pending.point, pu)
		Audio.sfx(a.get("sfx", ""), global_position, 1.0)
		var vkey: String = ["q", "w", "e", "r", "d", "t"][i] if i < 6 else "d"
		if a.type == "w3":
			pass  # озвучку способности включают триггеры карты (PlaySoundBJ)
		elif is_player:
			Audio.voice(hero_id, vkey, 1.0, 0.5)
		elif i >= 3 and Game.I.camera and Game.I.camera.focus.distance_to(global_position) < 40.0:
			Audio.voice(hero_id, vkey, 1.0, 1.0)
	pending = {}
	if resume_target and valid_target(resume_target):
		order = "attack"
		target_unit = resume_target
	elif order == "cast":
		order = "idle"
	resume_target = null


func add_buff(id: String, d: Dictionary, t: float, extra := {}) -> void:
	var b := {"t": t, "def": d}
	b.merge(extra)
	buffs[id] = b
	recalc_stats()
	_refresh_overlay()


func remove_buff(id: String) -> void:
	if not buffs.has(id):
		return
	buffs.erase(id)
	recalc_stats()
	_refresh_overlay()
	if id == "ichigo_d":
		pass


func _refresh_overlay() -> void:
	var mat: ShaderMaterial = null
	if buffs.has("akame_d"):
		if _tattoo_shader == null:
			_tattoo_shader = Shader.new()
			_tattoo_shader.code = TATTOO_SHADER
		mat = ShaderMaterial.new()
		mat.shader = _tattoo_shader
		var aura := ShaderMaterial.new()
		aura.shader = _aura_shader_get()
		aura.set_shader_parameter("tint", Color(0.9, 0.05, 0.1))
		mat.next_pass = aura
	else:
		for id in buffs:
			var bd: Dictionary = buffs[id].def
			if bd.get("type", "") == "transform" and bd.has("aura"):
				mat = ShaderMaterial.new()
				mat.shader = _aura_shader_get()
				var av = bd.aura
				mat.set_shader_parameter("tint", Color(av[0], av[1], av[2]) if av is Array else av)
				break
	overlay_mat = mat
	_apply_overlay(model, mat)


static func _aura_shader_get() -> Shader:
	if _aura_shader == null:
		_aura_shader = Shader.new()
		_aura_shader.code = AURA_SHADER
	return _aura_shader


func _apply_overlay(n: Node, mat: Material) -> void:
	if n == null:
		return
	if n is GeometryInstance3D and n != ring and n != ice_shell:
		(n as GeometryInstance3D).material_overlay = mat
	for c in n.get_children():
		_apply_overlay(c, mat)


func _timers(delta: float) -> void:
	super._timers(delta)
	for a in abilities:
		if a.cd > 0.0:
			a.cd = maxf(0.0, a.cd - delta)
	for k in w3_cd.keys():
		w3_cd[k] -= delta
		if w3_cd[k] <= 0.0:
			w3_cd.erase(k)
	var expired: Array = []
	for id in buffs:
		buffs[id].t -= delta
		if buffs[id].t <= 0.0:
			expired.append(id)
	for id in expired:
		remove_buff(id)
	for k in item_cd.keys():
		item_cd[k] -= delta
		if item_cd[k] <= 0.0:
			item_cd.erase(k)
	# аура брони союзников (Легион небес)
	_aura_t -= delta
	if _aura_t <= 0.0:
		_aura_t = 1.0
		var best := 0.0
		for o in Game.I.heroes:
			if o.team == team and o.alive and o.area == area and o.aura_armor > 0.0 and o.flat_dist(self) < 12.0:
				best = maxf(best, o.aura_armor)
		if not is_equal_approx(best, aura_bonus):
			aura_bonus = best
			recalc_stats()
	# аура пламени (Утраченное пламя дракона)
	if burn > 0.0:
		_burn_t -= delta
		if _burn_t <= 0.0:
			_burn_t = 0.5
			for u in Game.I.enemies_in_radius(global_position, 3.6, self, false):
				Game.I.deal_damage(self, u, burn * 0.5, "dot")
	if last_hit_time > 0.0:
		last_hit_time -= delta


func _brain(delta: float) -> void:
	if ai:
		ai.think(self, delta)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if alive and Game.I and Game.I.state == "playing":
		Game.I.check_portal(self)
		_collect_t -= delta
		if _collect_t <= 0.0:
			_collect_t = 0.5
			if area == home_zone and Game.I.zones[home_zone].in_base(global_position) and base_items.count("") < 6:
				collect_base()
		_combine_t -= delta
		if _combine_t <= 0.0:
			_combine_t = 1.0
			try_auto_combine()
			# сет собран — открывается способность [T] (событие изучения для триггеров карты)
			if W3Runtime.I and has_set() != _w3_set:
				_w3_set = has_set()
				W3Abil.update_levels(W3Runtime.I, self)


func _dead_process(delta: float) -> void:
	death_time += delta
	if death_time > 3.0 and visible:
		visible = false
	if respawn_left > 0.0:
		respawn_left -= delta
		if respawn_left <= 0.0:
			Game.I.respawn_hero(self)


func die() -> void:
	super.die()
	if Game.I:
		Game.I._chan_stop(self)
	if hero_id == "akame" and has_buff("akame_form"):
		Abilities.akame_form(self, false)
	for id in buffs.keys():
		buffs.erase(id)
	recalc_stats()
	_refresh_overlay()
	if is_player:
		Audio.voice(hero_id, "death", 1.0, 0.5)


# ----------------------------------------------------------------- предметы
var _combine_t := 0.0
var _w3_set := false
var _combine_hint := {}


## Автосборка: как только все компоненты рецепта лежат в инвентаре или рюкзаке, предмет собирается сам
## (цена рецепта списывается автоматически). Из нескольких возможных рецептов берётся самый ценный.
func try_auto_combine() -> void:
	for _guard in 8:
		var best := ""
		var best_total := -1
		for id in Data.ITEMS:
			var d: Dictionary = Data.ITEMS[id]
			var recipe: Array = d.get("recipe", [])
			if recipe.is_empty() or not can_own(id) or not _carried_has_all(recipe):
				continue
			var tot := Data.recipe_total(id)
			if tot > best_total:
				best = id
				best_total = tot
		if best == "":
			return
		var bd: Dictionary = Data.ITEMS[best]
		if gold < int(bd.price):
			if is_player and Game.I.time - float(_combine_hint.get(best, -99.0)) > 20.0:
				_combine_hint[best] = Game.I.time
				Game.I.hud.error("Все части «%s» собраны — на сборку не хватает %d золота" % [bd.name, int(bd.price) - gold])
			return
		gold -= int(bd.price)
		for r in bd.recipe:
			_take_carried(r)
		_put(best, int(bd.get("charges", 0)))
		recalc_stats()
		_craft_fx(best)


func _carried_has_all(recipe: Array) -> bool:
	var need := {}
	for c in recipe:
		need[c] = need.get(c, 0) + 1
	for c in need:
		if items.count(c) + stash.count(c) + int(c == ex_item) < need[c]:
			return false
	return true


func _take_carried(id: String) -> void:
	if id == ex_item:
		ex_item = ""
		return
	var i := items.find(id)
	if i >= 0:
		items[i] = ""
		item_ch[i] = 0
		return
	i = stash.find(id)
	if i >= 0:
		stash[i] = ""
		stash_ch[i] = 0


## Анимация сборки: части слетаются к герою, вспышка и столб света цвета предмета.
func _craft_fx(id: String) -> void:
	var d: Dictionary = Data.ITEMS[id]
	var col: Color = Color(d.get("color", Color(1.0, 0.8, 0.3)))
	var parts: Array = d.get("recipe", [])
	var center := global_position + Vector3(0, 1.6, 0)
	var n := maxi(parts.size(), 3)
	for k in n:
		var ang := TAU * k / n
		var pc: Color = Color(Data.ITEMS[parts[k]].get("color", col)) if k < parts.size() else col
		var start := center + Vector3(cos(ang) * 2.6, 0.8 + 0.4 * sin(ang * 2.0), sin(ang) * 2.6)
		var src := self
		var orb := Fx.spawn(Game.I.fx_root, start, 0.5, func(node: Fx.FxNode, _dt: float) -> bool:
			var t := clampf(node.t / 0.45, 0.0, 1.0)
			var target := (src.global_position + Vector3(0, 1.6, 0)) if is_instance_valid(src) else center
			node.global_position = start.lerp(target, t * t)
			node.scale = Vector3.ONE * (1.0 - 0.5 * t)
			return t < 1.0)
		var sm := SphereMesh.new()
		sm.radius = 0.22
		sm.height = 0.44
		Fx.add_mesh(orb, sm, Fx.glow_mat(pc, 3.0))
	var me := self
	Game.I.get_tree().create_timer(0.45, false).timeout.connect(func() -> void:
		if not is_instance_valid(me):
			return
		var p := me.global_position
		Fx.burst(Game.I.fx_root, p + Vector3(0, 1.6, 0), col, 40, 7.0, 0.3, 0.7)
		Fx.burst(Game.I.fx_root, p + Vector3(0, 1.6, 0), Color(1.0, 0.95, 0.7), 20, 4.0, 0.2, 0.5)
		Fx.ring_burst(Game.I.fx_root, p, 3.2, col, 0.6, 0.5)
		Fx.pillar(Game.I.fx_root, p, 0.9, 7.0, col.lightened(0.2), 0.9)
		Audio.sfx("buff_up", p, 0.9)
		Audio.sfx("coin", p, 0.7)
		if me.is_player:
			Game.I.hud.add_float_text(p + Vector3(0, 4.2, 0), "Собрано: " + str(d.name), col.lightened(0.3), true)
			Game.I.hud.on_item_crafted(id))


func free_slots() -> int:
	return items.count("")


func count_owned(id: String) -> int:
	var n := items.count(id) + stash.count(id) + base_items.count(id) + int(id == ex_item and id != "")
	if courier:
		n += courier.count(id)
	return n


func has_item(id: String) -> bool:
	return count_owned(id) > 0


func can_own(id: String) -> bool:
	var h: String = Data.ITEMS[id].get("hero", "")
	return h == "" or h == hero_id


## Чего не хватает для рецепта (с учётом повторов).
func missing_components(id: String) -> Array:
	var need := {}
	for c in Data.ITEMS[id].get("recipe", []):
		need[c] = need.get(c, 0) + 1
	var out: Array = []
	for c in need:
		var have := count_owned(c)
		for k in need[c] - have:
			out.append(c)
	return out


func _take(id: String) -> bool:
	if id == ex_item and id != "":
		ex_item = ""
		return true
	var i := items.find(id)
	if i >= 0:
		items[i] = ""
		item_ch[i] = 0
		return true
	i = stash.find(id)
	if i >= 0:
		stash[i] = ""
		stash_ch[i] = 0
		return true
	i = base_items.find(id)
	if i >= 0:
		base_items[i] = ""
		base_ch[i] = 0
		return true
	if courier and courier.take(id):
		return true
	return false


## Положить предмет герою (зелья складываются в стопку). false — некуда.
func receive(id: String, charges: int) -> bool:
	if Data.ITEMS[id].get("consumable", false):
		var st := items.find(id)
		if st >= 0:
			item_ch[st] += charges
			return true
	return _put(id, charges)


## Забрать всё, что лежит «в лагере», пока герой в лагере.
func collect_base() -> void:
	var moved := false
	for i in 6:
		if base_items[i] != "" and receive(base_items[i], base_ch[i]):
			base_items[i] = ""
			base_ch[i] = 0
			moved = true
	if moved:
		recalc_stats()
		try_auto_combine()


func _put(id: String, charges := 0) -> bool:
	var i := items.find("")
	if i >= 0:
		items[i] = id
		item_ch[i] = charges
		return true
	i = stash.find("")
	if i >= 0:
		stash[i] = id
		stash_ch[i] = charges
		return true
	return false


## Дерево сборки для лавки и быстрой покупки: что уже есть (have) и сколько стоит докупить (cost).
## reserve — сколько своих предметов уже «занято» этим деревом (одна вещь не идёт в две ветки).
func recipe_plan(id: String, reserve := {}, top := true) -> Dictionary:
	var d: Dictionary = Data.ITEMS[id]
	var node := {"id": id, "have": false, "cost": 0, "kids": [], "err": ""}
	if not top and count_owned(id) - int(reserve.get(id, 0)) > 0:
		reserve[id] = int(reserve.get(id, 0)) + 1
		node.have = true
		return node
	if d.cls == "Ex":
		node.err = "Нужен личный предмет «%s»" % d.name
		return node
	if not can_own(id):
		node.err = "Это предмет другого героя"
		return node
	var cost := int(d.price)
	for c in d.get("recipe", []):
		var k := recipe_plan(c, reserve, false)
		node.kids.append(k)
		cost += int(k.cost)
		if str(k.err) != "" and node.err == "":
			node.err = k.err
	node.cost = cost
	return node


## Быстрая покупка (ПКМ в лавке): докупить всё недостающее для сборки и сразу собрать предмет,
## если хватает золота. Свои части (инвентарь, рюкзак, лагерь, курьер) идут в дело.
func quick_buy(id: String, remote := false) -> String:
	var d: Dictionary = Data.ITEMS[id]
	if (d.get("recipe", []) as Array).is_empty():
		return buy(id, remote)
	var reserve := {}
	var plan := recipe_plan(id, reserve, true)
	if str(plan.err) != "":
		return plan.err
	var cost := int(plan.cost)
	if gold < cost:
		return "Не хватает золота: нужно %d, есть %d" % [cost, gold]
	if not _qb_room(reserve, remote):
		return "В лагере нет места — отправьте курьера (C)" if remote else "Инвентарь и рюкзак заполнены"
	gold -= cost
	for c in reserve:
		for k in int(reserve[c]):
			_take(c)
	if remote:
		var bi := base_items.find("")
		base_items[bi] = id
		base_ch[bi] = int(d.get("charges", 0))
	else:
		_put(id, int(d.get("charges", 0)))
	recalc_stats()
	_craft_fx(id)
	try_auto_combine()
	return ""


## Хватит ли места под собранный предмет, если части из reserve уйдут в сборку.
func _qb_room(reserve: Dictionary, remote: bool) -> bool:
	var it := items.duplicate()
	var st := stash.duplicate()
	var bs := base_items.duplicate()
	var ex := ex_item
	for c in reserve:
		for k in int(reserve[c]):
			if c == ex:
				ex = ""
				continue
			var i := it.find(c)
			if i >= 0:
				it[i] = ""
				continue
			i = st.find(c)
			if i >= 0:
				st[i] = ""
				continue
			i = bs.find(c)
			if i >= 0:
				bs[i] = ""
	if remote:
		return bs.has("")
	return it.has("") or st.has("")


## Возвращает текст ошибки или пустую строку при успехе.
## remote — покупка вне лагеря: предмет кладётся «в лагерь», его привезёт курьер.
func buy(id: String, remote := false) -> String:
	var d: Dictionary = Data.ITEMS[id]
	if not can_own(id):
		return "Это предмет другого героя"
	if d.cls == "Ex":
		return "Этот предмет нельзя купить"
	var recipe: Array = d.get("recipe", [])
	var stack := -1
	if d.get("consumable", false):
		stack = (base_items if remote else items).find(id)
	if recipe.size() > 0:
		var miss := missing_components(id)
		if miss.size() > 0:
			return "Не хватает: " + ", ".join(miss.map(func(x): return Data.ITEMS[x].name))
		if remote and base_items.count("") == 0 and not recipe.any(func(c): return base_items.has(c)):
			return "В лагере нет места — отправьте курьера (C)"
	elif remote and not d.has("tome") and stack < 0 and base_items.count("") == 0:
		return "В лагере нет места — отправьте курьера (C)"
	elif not remote and not d.has("tome") and stack < 0 and free_slots() == 0 and stash.count("") == 0:
		return "Инвентарь и рюкзак заполнены"
	if gold < d.price:
		return "Не хватает золота (нужно %d)" % d.price
	gold -= d.price
	if d.has("tome"):
		var t: Dictionary = d.tome
		for k in t:
			if k == "xp":
				add_xp(float(t[k]))
			else:
				tome[k] = float(tome.get(k, 0.0)) + float(t[k])
		recalc_stats()
		return ""
	for r in recipe:
		_take(r)
	if remote:
		if stack >= 0:
			base_ch[stack] += int(d.get("charges", 1))
		else:
			var bi := base_items.find("")
			base_items[bi] = id
			base_ch[bi] = int(d.get("charges", 0))
	elif stack >= 0:
		item_ch[stack] += int(d.get("charges", 1))
	else:
		_put(id, int(d.get("charges", 0)))
	recalc_stats()
	if recipe.size() > 0:
		_craft_fx(id)
	try_auto_combine()
	return ""


func sell_base(slot: int) -> String:
	if base_items[slot] == "":
		return ""
	var d: Dictionary = Data.ITEMS[base_items[slot]]
	if d.get("no_sell", false):
		return "Этот предмет нельзя продать"
	var k := 1.0
	if d.get("consumable", false):
		k = float(base_ch[slot]) / maxf(1.0, float(d.get("charges", 1)))
	gold += int(Data.recipe_total(base_items[slot]) * 0.5 * k)
	base_items[slot] = ""
	base_ch[slot] = 0
	return ""


func sell(slot: int, from_stash: bool) -> String:
	var arr := stash if from_stash else items
	var ch := stash_ch if from_stash else item_ch
	if slot < 0 or slot >= arr.size() or arr[slot] == "":
		return ""
	var d: Dictionary = Data.ITEMS[arr[slot]]
	if d.get("no_sell", false):
		return "Этот предмет нельзя продать"
	var k := 1.0
	if d.get("consumable", false):
		k = float(ch[slot]) / maxf(1.0, float(d.get("charges", 1)))
	gold += int(Data.recipe_total(arr[slot]) * 0.5 * k)
	arr[slot] = ""
	ch[slot] = 0
	recalc_stats()
	return ""


func swap_stash(slot: int, from_stash: bool) -> String:
	if from_stash:
		if stash[slot] == "":
			return ""
		var i := items.find("")
		if i < 0:
			return "Инвентарь заполнен"
		items[i] = stash[slot]
		item_ch[i] = stash_ch[slot]
		stash[slot] = ""
		stash_ch[slot] = 0
	else:
		if items[slot] == "":
			return ""
		var j := stash.find("")
		if j < 0:
			return "Склад заполнен"
		stash[j] = items[slot]
		stash_ch[j] = item_ch[slot]
		items[slot] = ""
		item_ch[slot] = 0
	recalc_stats()
	return ""


func item_cooldown(id: String) -> float:
	return float(item_cd.get(id, 0.0))


func use_item(slot: int) -> String:
	if slot < 0 or slot >= items.size() or items[slot] == "":
		return ""
	var id: String = items[slot]
	var d: Dictionary = Data.ITEMS[id]
	if not alive:
		return "Герой мёртв"
	if silence > 0.0:
		return "Немота: предметы отключены"
	if d.has("tp"):
		# свиток телепорта тратится, только когда каст дочитан
		if item_cooldown(id) > 0.0:
			return "Свиток перезаряжается"
		if stun > 0.0:
			return "Оглушение"
		var terr := Game.I.start_scroll(self)
		if terr == "":
			item_cd[id] = 6.0
		return terr
	if d.get("consumable", false):
		item_ch[slot] -= 1
		if item_ch[slot] <= 0:
			items[slot] = ""
			item_ch[slot] = 0
		if d.has("heal"):
			heal_over_time = d.heal / 3.0
			heal_time = 3.0
			Fx.ring_burst(Game.I.fx_root, global_position, 1.8, Color(0.4, 1.0, 0.5), 0.5)
		elif d.has("mana"):
			mana_over_time = d.mana / 3.0
			mana_time = 3.0
			Fx.ring_burst(Game.I.fx_root, global_position, 1.8, Color(0.4, 0.6, 1.0), 0.5)
		elif d.has("invuln"):
			invulnerable = d.invuln
			Fx.pillar(Game.I.fx_root, global_position, 1.2, 4.0, Color(1.0, 0.9, 0.4), 0.8)
		elif d.has("vamp"):
			add_buff("vamp", {"name": "Вампиризм", "dmg_mult": 0.25, "lifesteal": 0.25}, d.vamp)
		Audio.sfx("potion", global_position, 0.7)
		return ""
	if not d.has("active"):
		return "Этот предмет действует сам"
	if item_cooldown(id) > 0.0:
		return "Предмет перезаряжается"
	if stun > 0.0:
		return "Оглушение"
	var err := _activate(d.active)
	if err == "":
		item_cd[id] = float(d.active.cd)
		Audio.sfx("buff_up", global_position, 0.6)
	return err


## Потратить один свиток телепорта (каст дочитан). false — свитка уже нет.
func spend_scroll() -> bool:
	var slot := items.find("tp_scroll")
	if slot < 0:
		return false
	item_ch[slot] -= 1
	if item_ch[slot] <= 0:
		items[slot] = ""
		item_ch[slot] = 0
	item_cd["tp_scroll"] = float(Data.ITEMS["tp_scroll"].cd)
	return true


func _nearest_enemy_hero(max_r: float) -> Hero:
	var best: Hero = null
	var bd := 1e9
	for o in Game.I.heroes:
		if o.alive and o.team != team and o.area == area and Game.I.can_see(team, o):
			var dd := flat_dist(o)
			if dd <= max_r and dd < bd:
				bd = dd
				best = o
	return best


## Применение активного свойства предмета.
func _activate(a: Dictionary) -> String:
	var fx := Game.I.fx_root
	match a.type:
		"heal":
			hp = minf(max_hp, hp + float(a.amount))
			Fx.ring_burst(fx, global_position, 2.2, Color(0.4, 1.0, 0.5), 0.6)
		"heal_pct":
			hp = max_hp
			Fx.pillar(fx, global_position, 1.4, 6.0, Color(1.0, 1.0, 0.8), 0.9)
		"spell_shield":
			spell_shield = float(a.dur)
			Fx.ring_burst(fx, global_position, 2.0, Color(0.7, 0.5, 1.0), 0.5)
		"freeze_nova":
			for u in Game.I.enemies_in_radius(global_position, float(a.radius), self, false):
				Game.I.deal_damage(self, u, float(a.dmg) * (1.0 + 0.05 * level), "spell")
				u.apply_freeze(float(a.freeze))
			Fx.ring_burst(fx, global_position, float(a.radius), Color(0.6, 0.9, 1.0), 0.6, 0.8)
			Audio.sfx("ice_shatter", global_position, 0.8)
		"root", "hex":
			var t := _nearest_enemy_hero(float(a.range))
			if t == null:
				return "Нет вражеского героя рядом"
			if a.type == "root":
				t.root_time = maxf(t.root_time, float(a.dur))
				Fx.ring_burst(fx, t.global_position, 1.6, Color(0.4, 0.9, 0.4), 0.8, 0.5)
			else:
				t.apply_stun(float(a.dur))
				Fx.pillar(fx, t.global_position, 1.0, 3.5, Color(0.8, 0.4, 1.0), 0.8)
		"invis":
			invis = float(a.dur)
			add_buff("dark_seal", {"name": "Тёмная печать"}, float(a.dur))
		"snipe":
			var t2 := _nearest_enemy_hero(400.0)
			if t2 == null:
				return "Нет вражеского героя в зоне видимости"
			Game.I.deal_damage(self, t2, float(a.dmg) * (1.0 + 0.05 * level), "spell", true)
			t2.apply_stun(float(a.stun))
			Fx.burst(fx, t2.global_position + Vector3(0, 1.2, 0), Color(1.0, 0.3, 0.2), 30, 8.0, 0.3, 0.5)
		"immortal":
			immortal = float(a.dur)
			Fx.pillar(fx, global_position, 1.2, 5.0, Color(1.0, 0.85, 0.4), 0.8)
		"mirror":
			# настоящие иллюзии героя: бьют mult от его урона, получают двойной урон
			var n := int(a.get("count", 1))
			var imgs: Array = []
			if W3Runtime.I and has_meta("w3"):
				imgs = W3Abil.make_illusions(W3Runtime.I, self, n, float(a.mult), float(a.get("taken", 2.0)),
					float(a.dur), "Abilities\\Spells\\Orc\\MirrorImage\\MirrorImageCaster.mdl")
			if imgs.is_empty():
				add_buff("mirror", {"name": "Двойники", "dmg_mult": float(a.mult)}, float(a.dur))
			for u in imgs:
				Fx.afterimage(fx, (u as Node3D).global_position, rotation.y, Color(0.6, 0.75, 1.0))
		"attack_buff":
			add_buff("attack_buff", {"name": "Ярость", "dmg_mult": float(a.pct)}, float(a.dur))
		"confuse":
			for u in Game.I.enemies_in_radius(global_position, float(a.radius), self, false):
				u.apply_slow(float(a.slow), float(a.dur))
			Fx.ring_burst(fx, global_position, float(a.radius), Color(0.8, 0.1, 0.15), 0.8, 1.0)
		"spirit":
			add_buff("spirit", {"name": "Дух-защитник", "dmg_mult": 0.4, "attack_speed": 0.4}, float(a.dur))
			Fx.pillar(fx, global_position, 1.6, 7.0, Color(1.0, 0.7, 0.9), 1.0)
	return ""


## Слот зелья лечения (самого слабого, чтобы не тратить дорогие зря).
func potion_slot() -> int:
	for id in ["potion", "potion_big", "potion_ultra"]:
		var i := items.find(id)
		if i >= 0:
			return i
	return -1


func mana_potion_slot() -> int:
	for id in ["mana_potion", "mana_potion_big"]:
		var i := items.find(id)
		if i >= 0:
			return i
	return -1

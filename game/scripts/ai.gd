class_name HeroAI
extends RefCounted
## Мозг героя-бота: защищает кристалл, фармит лес, лечится у фонтанов, собирает предметы до Ультимативного сета,
## ходит в общий лес за лагерями и хвостатым, в набеги — через врата и общий лес, ищет врагов в лабиринте арены.

var timer := 0.0
var mode := "defend"  # defend, invade, retreat, wild
var invade_zone := -1
var invade_time := 0.0
var invade_cooldown := 0.0
var slot := 0
var aggression := 1.0
var shop_t := 0.0
var farm_t := 0.0


func _init(s: int) -> void:
	slot = s
	invade_cooldown = randf_range(80.0, 150.0)
	aggression = randf_range(0.7, 1.3)


func think(h: Hero, delta: float) -> void:
	invade_cooldown -= delta
	shop_t -= delta
	farm_t -= delta
	if mode == "invade":
		invade_time += delta
	timer -= delta
	if timer > 0.0:
		return
	timer = 0.22 + randf() * 0.12
	if h.order == "cast" or h.cast_lock > 0.0:
		return
	# свиток телепорта читается — стоим, пока не напали вплотную
	if not h.chan.is_empty() and h.chan.get("scroll", false):
		if Game.I.enemies_in_radius(h.global_position, 4.0, h).is_empty() or h.hp < h.max_hp * 0.35:
			return
	_use_items(h)
	if h.dueling:
		_battle(h)
		return
	var zone: Zone = Game.I.zones[h.area] if h.area >= 0 else null
	var home: Zone = Game.I.zones[h.home_zone]

	if h.area == h.home_zone and shop_t <= 0.0 and home.in_base(h.global_position):
		shop_t = 1.0
		_shop(h)

	var low := h.hp < h.max_hp * 0.3
	if low and mode != "retreat":
		mode = "retreat"
	if mode == "retreat":
		if h.area != h.home_zone:
			_go_home(h)
			return
		if h.hp > h.max_hp * 0.85:
			mode = "defend"
		else:
			var fp0 := _fountain_pt(home, true)
			var threats := Game.I.enemies_in_radius(h.global_position, 5.0, h)
			if threats.size() > 0 and h.flat_dist_p(home.fountain_life) < 7.0:
				_fight(h, threats[0], threats)
			elif home.region(h.global_position) == "forest" and _use_scroll(h):
				pass
			elif h.flat_dist_p(fp0) > 2.0:
				_go(h, fp0)
			return

	var crystal_pos := home.crystal_pos
	var danger := Game.I.creeps_near(crystal_pos, 18.0, h.home_zone) >= 3 or Game.I.enemy_heroes_near(crystal_pos, 18.0, h) > 0

	if mode == "invade":
		# дорога через общий лес долгая (около 45 с в одну сторону) — на набег даём больше времени
		if danger or invade_time > 130.0 or not Game.I.team_alive(invade_zone):
			mode = "defend"
			invade_cooldown = randf_range(60.0, 120.0) / aggression

	# общий лес: лагеря своей стороны и хвостатый
	var beast: Unit = Game.I.beast
	var beast_up := beast != null and is_instance_valid(beast) and beast.alive
	if mode == "wild":
		if danger or h.hp < h.max_hp * 0.45 or (not beast_up and Game.I.wild_camp_for(h).is_empty()):
			mode = "defend"
		else:
			_wild_job(h, beast if beast_up else null)
			return
	elif mode == "defend" and not danger and h.hp > h.max_hp * 0.7 and h.level >= 5:
		var free_hands := slot == 2 and Game.I.camp_for_zone(h.home_zone, h).is_empty() and Game.I.creeps_in_zone(h.home_zone) <= 4
		if (beast_up and slot >= 1 and h.level >= 7) or (free_hands and not Game.I.wild_camp_for(h).is_empty()):
			mode = "wild"
			_wild_job(h, beast if beast_up else null)
			return

	if mode == "defend" and h.area != h.home_zone:
		_go_home(h)
		return

	if mode == "defend" and invade_cooldown <= 0.0 and h.level >= 6 and h.hp > h.max_hp * 0.75:
		var creeps_home := Game.I.creeps_in_zone(h.home_zone)
		var mates := Game.I.allies_home(h)
		if creeps_home <= 3 and mates >= 1 and not danger:
			var options: Array = []
			for t in 3:
				if t != h.team and Game.I.team_alive(t):
					options.append(t)
			if options.size() > 0:
				invade_zone = options.pick_random()
				mode = "invade"
				invade_time = 0.0
		invade_cooldown = randf_range(25.0, 50.0)

	if mode == "invade":
		if h.area != invade_zone:
			_travel(h, invade_zone)
			return
		var foes := Game.I.enemies_in_radius(h.global_position, 30.0, h)
		var best: Unit = null
		var best_score := -1e9
		for u in foes:
			if zone.region(u.global_position) == "forest":
				continue
			var s := -h.flat_dist(u)
			if u is Hero:
				s += 25.0 + (1.0 - u.hp / u.max_hp) * 20.0
			if u.neutral:
				s -= 30.0
			# под башнями чужого лагеря не лезем, если враг не добивается
			if Game.I.near_tower(u.global_position, h.area, 1.5) and not (u is Hero and u.hp < u.max_hp * 0.3):
				s -= 60.0
			if s > best_score:
				best_score = s
				best = u
		if best and best_score > -50.0:
			_fight(h, best, foes)
		else:
			h.issue_attack_move(zone.to_world(randf_range(-3, 3), randf_range(42.0, 58.0)))
		return

	# защита: роли — 0 держит левую тропу, 1 — правую, 2 — лесник
	var my_lane := slot if slot < 2 else -1
	var forest_job := slot == 2 and not danger and not Game.I.camp_for_zone(h.home_zone, h).is_empty()
	var target: Unit = null
	var best_d := 1e9
	var near := Game.I.enemies_in_radius(h.global_position, 140.0, h)
	for u in near:
		if u.neutral or u.area != h.home_zone:
			continue
		var at_base := u.flat_dist_p(crystal_pos) < 24.0
		if forest_job and not at_base:
			continue
		# назад из центра только пешком — далеко вверх по тропам не уходим, ждём монстров ниже
		if not at_base and home.to_local(u.global_position).y > 48.0 and h.flat_dist(u) > 12.0:
			continue
		var d := u.flat_dist_p(crystal_pos) * 0.6 + h.flat_dist(u) * 0.4
		if u is Hero:
			d -= 12.0
		elif my_lane >= 0 and u.lane_id != my_lane and not at_base:
			d += 12.0
		if d < best_d:
			best_d = d
			target = u
	if target:
		_engage(h, target, near)
		return
	if forest_job:
		var camp := Game.I.camp_for_zone(h.home_zone, h)
		var foes2: Array = []
		for u in camp.units:
			if is_instance_valid(u) and u.alive:
				foes2.append(u)
		var tgt: Unit = foes2[0]
		for u in foes2:
			if h.flat_dist(u) < h.flat_dist(tgt):
				tgt = u
		_engage(h, tgt, foes2)
		return
	# пусто: подлечиться у фонтанов или встать на свою позицию
	var to_wave := Game.I.next_wave - Game.I.time
	if (h.hp < h.max_hp * 0.65 or h.mp < h.max_mp * 0.35) and to_wave > 9.0:
		var fp := _fountain_pt(home, h.hp < h.max_hp * 0.65)
		if h.flat_dist_p(fp) > 2.5:
			_go(h, fp)
		return
	var gp: Vector3 = home.guard_points[mini(slot, 2)]
	if h.flat_dist_p(gp) > 3.0:
		_go(h, gp, true)
	elif h.order != "idle":
		h.issue_stop()


## Точка у фонтана жизни или маны (со стороны лагеря).
func _fountain_pt(home: Zone, life: bool) -> Vector3:
	var f := home.fountain_life if life else home.fountain_mana
	return f + (home.crystal_pos - f).normalized() * 3.2


## Куда идти, чтобы попасть в goal на своём острове: «1» быстро выводит из лагеря в центр, «2» — в мини-лес
## (каст 3 с). Обратно — пешком: из мини-леса вниз ведёт лестница.
func _route(h: Hero, goal: Vector3) -> Vector3:
	if h.area < 0 or h.team != h.area:
		return goal
	var z: Zone = Game.I.zones[h.area]
	var rh := z.region(h.global_position)
	var rg := z.region(goal)
	var gl := z.to_local(goal)
	if rh == "base" and rg == "forest":
		return z.pads[1].pos
	if rh == "base" and gl.y > 34.0:
		return z.pads[0].pos
	return goal


func _go(h: Hero, goal: Vector3, attack := false) -> void:
	var p := _route(h, goal)
	if p != goal:
		_to_pad(h, p)
	elif attack:
		if h.order != "attack_move" or h.target_point.distance_to(p) > 1.5:
			h.issue_attack_move(p)
	elif h.order != "move" or h.target_point.distance_to(p) > 1.0:
		h.issue_move(p)


## Встать на круг телепорта и ждать каста: приказы сбивают каст, поэтому на круге герой стоит.
func _to_pad(h: Hero, pos: Vector3) -> void:
	if h.flat_dist_p(pos) < 1.3:
		if h.order != "hold" and h.order != "idle":
			h.issue_hold()
	elif h.order != "move" or h.target_point.distance_to(pos) > 1.0:
		h.issue_move(pos)


## Путь в другую область: с острова — к вратам мини-леса, из общего леса — к вратам нужной команды.
func _travel(h: Hero, to_area: int) -> void:
	var g := Game.I
	if h.area == to_area or h.area == -1:
		return
	if h.area == Wild.AREA:
		if to_area >= 0:
			_to_pad(h, g.wild.pads[to_area].pos)
		return
	var gate: Dictionary = g.zones[h.area].pads[2]
	var p := _route(h, gate.pos)
	_to_pad(h, p)


func _use_scroll(h: Hero) -> bool:
	if not h.chan.is_empty():
		return h.chan.get("scroll", false)
	var sl := h.items.find("tp_scroll")
	if sl < 0 or h.item_cooldown("tp_scroll") > 0.0 or h.stun > 0.0:
		return false
	if not Game.I.enemies_in_radius(h.global_position, 6.0, h).is_empty():
		return false
	return h.use_item(sl) == ""


## Домой из чужих земель: свитком, а без него — пешком через врата.
func _go_home(h: Hero) -> void:
	if h.area == h.home_zone:
		return
	if _use_scroll(h):
		return
	_travel(h, h.home_zone)


## Работа в общем лесу: хвостатый (если пробудился), иначе — лагеря своей стороны.
func _wild_job(h: Hero, beast: Unit) -> void:
	var g := Game.I
	if h.area != Wild.AREA:
		if h.area != h.home_zone:
			_go_home(h)
		else:
			_travel(h, Wild.AREA)
		return
	var foes := g.enemies_in_radius(h.global_position, 13.0, h)
	# чужой герой рядом важнее лагеря
	for u in foes:
		if u is Hero:
			_fight(h, u, foes)
			return
	if beast != null:
		if h.flat_dist(beast) > 11.0:
			_move_far(h, beast.home_pos)
		else:
			_fight(h, beast, foes)
		return
	var camp := g.wild_camp_for(h)
	if camp.is_empty():
		return
	var tgt: Unit = null
	for u in camp.units:
		if is_instance_valid(u) and u.alive and (tgt == null or h.flat_dist(u) < h.flat_dist(tgt)):
			tgt = u
	if tgt == null:
		return
	if h.flat_dist(tgt) > 10.0:
		_move_far(h, tgt.global_position)
	else:
		_fight(h, tgt, foes)


func _move_far(h: Hero, p: Vector3) -> void:
	if h.order != "move" or h.target_point.distance_to(p) > 2.5:
		h.issue_move(p)


## Атаковать цель; если она по ту сторону телепорта — сначала дойти до него.
func _engage(h: Hero, target: Unit, crowd: Array) -> void:
	var p := _route(h, target.global_position)
	if p != target.global_position:
		_go(h, p)
		return
	_fight(h, target, crowd)


## Битва в лабиринте: видимых врагов атакуем, иначе ищем их вместе с командой.
func _battle(h: Hero) -> void:
	var ps := h.potion_slot()
	if h.hp < h.max_hp * 0.4 and h.heal_time <= 0.0 and ps >= 0:
		h.use_item(ps)
	var foes := Game.I.enemies_in_radius(h.global_position, 80.0, h)
	var best: Unit = null
	var bs := -1e9
	for u in foes:
		var s := -h.flat_dist(u) + (1.0 - u.hp / u.max_hp) * 15.0
		if s > bs:
			bs = s
			best = u
	if best:
		_fight(h, best, foes)
		return
	var p := Game.I.search_point(h.team, h)
	var off := Vector3(slot - 1.0, 0, (slot % 2) * 2.0 - 1.0) * 2.0
	if h.order != "move" or h.target_point.distance_to(p + off) > 2.0:
		h.issue_move(Game.I.arena.nav.clamp(p + off))


func _fight(h: Hero, target: Unit, crowd: Array) -> void:
	if _use_abilities(h, target, crowd):
		return
	if h.order != "attack" or h.target_unit != target:
		h.issue_attack(target)


func _count_near(crowd: Array, p: Vector3, r: float) -> int:
	var n := 0
	for u in crowd:
		if is_instance_valid(u) and u.alive and u.flat_dist_p(p) <= r + u.radius:
			n += 1
	return n


func _heroes_near(h: Hero, r: float) -> int:
	var n := 0
	for u in Game.I.enemies_in_radius(h.global_position, r, h):
		if u is Hero:
			n += 1
	return n


func _use_abilities(h: Hero, target: Unit, crowd: Array) -> bool:
	if not is_instance_valid(target) or not target.alive:
		return false
	var dist := h.flat_dist(target)
	var big := target is Hero or target.kind == Unit.Kind.BOSS
	var tp := target.global_position
	var order: Array = [5, 4, 3, 0, 2, 1]
	for bi in range(6, h.abilities.size()):
		order.push_front(bi)
	for i in order:
		if i >= h.abilities.size() or h.cast_error(i) != "":
			continue
		var a: Dictionary = h.abilities[i].def
		if i == 4 and h.hero_id == "akame" and h.has_buff("akame_d"):
			if dist > 4.0 and dist < 14.0:
				return h.cast(i, tp)
			continue
		match a.type:
			"w3":
				var second := not h.w3_slot(i).is_empty()
				if float(a.cd) < 2.0 and float(a.mana) < 50.0 and not second:
					continue  # переключатели и мгновенные приёмы — по ситуации у триггеров, не спамим
				var ar2: float = maxf(float(a.get("radius", 0.0)), 3.5)
				var rng: float = h.ability_range(i)
				match h.ability_target(i):
					"unit":
						if dist <= rng + 1.0 and (big or second or target.hp > 400.0 or randf() < 0.35):
							return h.cast(i, tp, target)
					"point":
						if dist <= rng + 1.0 and (big or second or _count_near(crowd, tp, ar2) >= 2 or randf() < 0.25):
							return h.cast(i, tp)
					_:
						if dist <= maxf(ar2, 5.0) and (big or second or _count_near(crowd, h.global_position, maxf(ar2, 5.0)) >= 2):
							return h.cast(i, tp)
			"line":
				if dist <= a.range * 0.85 and (big or _count_line(h, crowd, tp, a.width) >= 2 or randf() < 0.3):
					return h.cast(i, tp)
			"leap_strike":
				if dist <= a.range and (big or _count_near(crowd, tp, a.radius) >= 2):
					return h.cast(i, tp)
			"slashes":
				if _count_near(crowd, h.global_position, a.radius * 0.9) >= 2 or (big and dist < a.radius * 0.8):
					return h.cast(i, tp)
			"empower", "transform", "metamorphosis":
				if dist < 6.0 and (big or _count_near(crowd, h.global_position, 6.0) >= 4):
					return h.cast(i, tp)
			"bolt":
				if dist <= a.range and (big or target.hp > 600.0):
					return h.cast(i, tp, target)
			"ice_blocks":
				if dist <= a.range + 2.0 and (big or _count_near(crowd, tp, a.radius) >= 3):
					return h.cast(i, tp)
			"blink":
				if dist > 6.0 and dist < a.range + 4.0 and big:
					return h.cast(i, tp)
			"time_stop":
				if _heroes_near(h, 14.0) >= 2 or (target.kind == Unit.Kind.BOSS and dist < 8.0) or (h.dueling and dist < 6.0):
					return h.cast(i, tp)
			"mugetsu":
				if dist <= a.range * 0.8 and (big or _count_line(h, crowd, tp, a.width) >= 4):
					return h.cast(i, tp)
			"nova":
				var nr: float = a.get("radius", 5.5)
				if _count_near(crowd, h.global_position, nr * 0.9) >= (2 if i < 3 else 3) or (big and dist < nr * 0.8):
					return h.cast(i, tp)
			"aoe_point":
				var ar: float = a.get("radius", 4.5)
				if dist <= a.range + 2.0 and (big or _count_near(crowd, tp, ar) >= (2 if i < 3 else 3)):
					return h.cast(i, tp)
	return false


func _count_line(h: Hero, crowd: Array, tp: Vector3, width: float) -> int:
	var n := 0
	var a := h.global_position
	var dir := (tp - a)
	dir.y = 0
	if dir.length() < 0.1:
		return 0
	var b := a + dir.normalized() * 18.0
	for u in crowd:
		if not is_instance_valid(u) or not u.alive:
			continue
		var p := Geometry3D.get_closest_point_to_segment(u.global_position, a, b)
		if p.distance_to(u.global_position) <= width * 0.5 + u.radius:
			n += 1
	return n


## Активные предметы: лечение, щиты, контроль.
func _use_items(h: Hero) -> void:
	var foes := Game.I.enemies_in_radius(h.global_position, 12.0, h)
	var hero_near := false
	for u in foes:
		if u is Hero:
			hero_near = true
	for s in 6:
		var id: String = h.items[s]
		if id == "":
			continue
		var d: Dictionary = Data.ITEMS[id]
		if d.get("consumable", false):
			if (d.has("heal") and h.hp < h.max_hp * 0.45 and h.heal_time <= 0.0) or \
					(d.has("mana") and h.mp < h.max_mp * 0.25 and h.mana_time <= 0.0) or \
					(d.has("invuln") and h.hp < h.max_hp * 0.2 and foes.size() > 0):
				h.use_item(s)
				return
			continue
		if not d.has("active") or h.item_cooldown(id) > 0.0:
			continue
		var a: Dictionary = d.active
		var want := false
		match a.type:
			"heal", "heal_pct":
				want = h.hp < h.max_hp * 0.45
			"immortal":
				want = h.hp < h.max_hp * 0.25 and foes.size() > 0
			"spell_shield":
				want = hero_near and h.hp < h.max_hp * 0.6
			"freeze_nova", "confuse":
				want = foes.size() >= 3 or (hero_near and h.flat_dist(foes[0]) < 6.0)
			"root", "hex", "snipe":
				want = hero_near
			"invis":
				want = hero_near and h.hp > h.max_hp * 0.4
			"mirror", "attack_buff", "spirit":
				want = hero_near or foes.size() >= 4
		if want:
			h.use_item(s)
			return


## Что купить следующим, чтобы приблизиться к предмету target ("" — уже есть, "!" — нельзя).
static func next_purchase(h: Hero, target: String, need := 1) -> String:
	if h.count_owned(target) >= need:
		return ""
	var d: Dictionary = Data.ITEMS[target]
	if d.cls == "Ex" or not h.can_own(target):
		return "" if h.count_owned(target) >= need else "!"
	var recipe: Array = d.get("recipe", [])
	var counts := {}
	for c in recipe:
		counts[c] = counts.get(c, 0) + 1
	for c in counts:
		var sub := next_purchase(h, c, counts[c])
		if sub == "!":
			return "!"
		if sub != "":
			return sub
	return target


func _shop(h: Hero) -> void:
	# свиток телепорта — чтобы возвращаться из леса не пешком
	if h.items.find("tp_scroll") < 0 and h.gold >= 250 and h.level >= 4 and h.free_slots() >= 2:
		h.buy("tp_scroll")
		return
	if h.potion_slot() < 0 and h.gold >= 400 and h.level >= 3 and not h.has_set() and h.free_slots() >= 2:
		h.buy("potion")
		return
	for goal in Data.BOT_GOALS[h.hero_id]:
		var nxt := next_purchase(h, goal)
		if nxt == "" or nxt == "!":
			continue
		var d: Dictionary = Data.ITEMS[nxt]
		if h.gold >= d.price:
			var err := h.buy(nxt)
			if err.begins_with("Инвентарь"):
				var ps := h.potion_slot()
				if ps >= 0:
					h.sell(ps, false)
		return
	# всё собрано — книги характеристик
	if h.gold >= 600:
		h.buy({"str": "tome_str", "agi": "tome_agi", "int": "tome_int"}[h.def.primary])

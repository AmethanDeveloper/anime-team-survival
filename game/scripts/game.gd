class_name Game
extends Node3D
## Сердце матча: команды, волны, лес с нейтралами и фонтанами, битвы команд в лабиринте с туманом войны,
## остановка времени, урон, управление игроком.

static var I: Game = null

var zones: Array[Zone] = []
var arena: Arena = null
## Общий лес (отдельный остров за вратами)
var wild: Wild = null
var teams: Array = []  # [{id, name, color, crystal, heroes, alive}]
var units: Array[Unit] = []
var heroes: Array[Hero] = []
var camps: Array = []  # [{area, zone (остров-хозяин или −1), pos, kind, units, side}]
## Лагеря нейтралов появляются раз в минуту; если пачку увели из зоны лагеря — появится ещё одна (стаки, до 4)
const CAMP_FIRST := 20.0
const CAMP_PERIOD := 60.0
const CAMP_ZONE_R := 11.0
const CAMP_MAX_PACKS := 4
var next_camps := CAMP_FIRST
## Руны у святилищ общего леса: [{pos, kind, node}]; новая — раз в 2 минуты
const RUNE_PERIOD := 120.0
var runes: Array = []
var next_runes := RUNE_PERIOD
## Хвостатые: одновременно жив один, первый — на 10-й минуте, следующий — через 8 минут после смерти предыдущего
const BEAST_FIRST := 600.0
const BEAST_GAP := 480.0
const BEAST_NAMES := ["Однохвостый Шукаку", "Двухвостая Мататаби", "Трёххвостый Исобу", "Четырёххвостый Сон Гоку",
	"Пятихвостый Кокуо", "Шестихвостый Сайкен", "Семихвостый Чомей", "Восьмихвостый Гьюки", "Девятихвостый Курама"]
var beast_n := 0            # сколько зверей уже появлялось
var beast: Unit = null
var next_beast := BEAST_FIRST
var beast_warned := false
## Рога (мини-боссы) на площадках между вратами: [{name, tid, unit, t (когда появится), spot}]
const HORN_FIRST := 240.0
const HORN_GAP := 300.0
var horns: Array = []
var horn_rot := 0
var horn_at := HORN_FIRST
var _outlaws: Array = []    # модели «преступников» древних лагерей: [id героя ранга B, ранга A]
var towers: Array = []  # [{zone, pos, top, cd}]
var player: Hero = null
var camera: RtsCamera = null
var hud: Hud = null
var audio: Audio = null
var fx_root: Node3D = null

var state := "select"  # select, playing, over
var time := 0.0
var wave := 0
var next_wave := Data.FIRST_WAVE
var next_duel := Data.DUEL_INTERVAL
var duel := {}
var spawn_queue: Array = []
var rng := RandomNumberGenerator.new()
var vision_t := 0.0
var fountain_t := 0.0

# остановка времени (Махападма)
var time_stop_owner: Hero = null
var time_stop_left := 0.0
var env_saved := {}

# ввод
var targeting := -1
var attack_move_mode := false
var quick_cast := false
var range_ring: MeshInstance3D = null
var aoe_ring: MeshInstance3D = null
var hover_ring: MeshInstance3D = null
var hovered: Unit = null
var inspected: Unit = null
var sel_ring: MeshInstance3D

# автотест
var sim := false
var autoplay := false
var uitest := false
var fxtest := false
var test_hero := "akame"
var sim_limit := 1800.0
var shot_path := ""
var shot_time := 0.0
var shot_done := false
var log_t := 0.0
var select_shot := false
var real_t := 0.0
var area_time := {}
var shot_cam := ""
var fx_slot := -1
var abiltest := false
var squadtest := false
var mechtest := false
var _seq: Array = []
var _seq_n := 1
var bosstest := false
var cheattest := false
var casttest := false
## --baltest [--roster=a,b,c,...] [--ballvl=15]: замер героев для баланса (урон атак и способностей по манекенам)
var baltest := false
var roster: Array = []
var bal_lvl := 15
var abil_dmg := {}


func _ready() -> void:
	I = self
	rng.randomize()
	for a in OS.get_cmdline_user_args():
		if a == "--sim":
			sim = true
		elif a == "--autoplay":
			autoplay = true
		elif a == "--uitest":
			uitest = true
		elif a == "--selectshot":
			select_shot = true
		elif a == "--fxtest":
			fxtest = true
		elif a == "--abiltest":
			abiltest = true
			sim = true
		elif a == "--squadtest":
			squadtest = true
			sim = true
		elif a == "--mechtest":
			mechtest = true
			sim = true
		elif a == "--bosstest":
			bosstest = true
			sim = true
		elif a.begins_with("--beastat="):
			next_beast = float(a.split("=")[1])
		elif a.begins_with("--hornat="):
			horn_at = float(a.split("=")[1])
		elif a == "--casttest":
			casttest = true
		elif a == "--baltest":
			baltest = true
			casttest = true
		elif a.begins_with("--roster="):
			roster = Array(a.split("=")[1].split(","))
		elif a.begins_with("--ballvl="):
			bal_lvl = int(a.split("=")[1])
		elif a == "--cheattest":
			cheattest = true
			sim = true
		elif a.begins_with("--hero="):
			test_hero = a.split("=")[1]
		elif a.begins_with("--duelat="):
			next_duel = float(a.split("=")[1])
		elif a.begins_with("--warp="):
			Engine.time_scale = float(a.split("=")[1])
		elif a.begins_with("--simtime="):
			sim_limit = float(a.split("=")[1])
		elif a.begins_with("--shot="):
			shot_path = a.split("=")[1]
		elif a.begins_with("--shottime="):
			shot_time = float(a.split("=")[1])
		elif a.begins_with("--slot="):
			fx_slot = int(a.split("=")[1])
		elif a.begins_with("--cam="):
			shot_cam = a.split("=")[1]
		elif a.begins_with("--seed="):
			rng.seed = int(a.split("=")[1])
			seed(int(a.split("=")[1]))

	if not sim and shot_path == "" and not uitest:
		Input.mouse_mode = Input.MOUSE_MODE_CONFINED
	audio = Audio.new()
	add_child(audio)
	fx_root = Node3D.new()
	fx_root.name = "Fx"
	add_child(fx_root)
	for i in 3:
		zones.append(Zone.new(i))
	arena = Arena.new()
	wild = Wild.new()
	for i in 3:
		# из общего леса врата выводят в мини-лес команды, рядом с её вратами
		var gc := Forest2.clearing("gate")
		wild.pads[i].exit = zones[i].to_world(gc.x - 0.9, gc.y - 1.3)
	World.build(self)
	arena.build(self)
	wild.build(self)
	_setup_teams()
	_make_indicators()
	Gfx.apply(get_tree())

	camera = RtsCamera.new()
	add_child(camera)
	camera.center_on(zones[0].crystal_pos + Vector3(0, 0, -8), true)

	hud = Hud.new()
	add_child(hud)

	if uitest:
		_ui_test()
	elif sim or casttest or (shot_path != "" and not select_shot):
		start_game(test_hero)
		if baltest:
			_bal_test()
		elif casttest:
			_cast_test()
		if fxtest:
			_fx_test()
		elif abiltest:
			_abil_test()
		elif squadtest:
			_squad_test()
		elif mechtest:
			_mech_test()
		elif bosstest:
			_boss_test()
		elif cheattest:
			_cheat_test()
		elif shot_cam != "":
			_shot_setup()
	else:
		hud.show_hero_select()
		Audio.music("menu")


func _exit_tree() -> void:
	if World.props_scene:
		World.props_scene.free()
		World.props_scene = null
	if I == self:
		I = null


## В тестах и автоигре герой игрока вкладывает очки навыков сам, как бот.
func auto_skills() -> bool:
	return sim or autoplay or uitest or mechtest or casttest or shot_path != ""


func nav_of(area: int) -> NavArea:
	if area >= 0:
		return zones[area].nav
	return wild.nav if area == Wild.AREA else arena.nav


## Телепорты области: острова — «1», «2» и врата в общий лес; общий лес — врата трёх команд.
func pads_in(area: int) -> Array:
	if area >= 0:
		return zones[area].pads
	return wild.pads if area == Wild.AREA else []


# ----------------------------------------------------------------- построение
func _setup_teams() -> void:
	for t in 3:
		var z := zones[t]
		var c := Unit.new()
		c.kind = Unit.Kind.CRYSTAL
		c.team = t
		c.area = t
		c.home_zone = t
		c.display_name = "Кристалл выживания"
		c.max_hp = 6000.0
		c.hp = c.max_hp
		c.armor = 3.0
		c.radius = 2.3
		c.move_speed = 0.0
		c.bar_height = 6.5
		add_child(c)
		c.global_position = z.crystal_pos
		var m := World.prop("Crystal")
		m.scale = Vector3.ONE * 1.35
		World.recolor(m, "CrystalGem", Data.TEAM_COLORS[t], 1.1)
		c.add_child(m)
		c.model = m
		var l := OmniLight3D.new()
		l.light_color = Data.TEAM_COLORS[t]
		l.light_energy = 2.5
		l.omni_range = 12.0
		l.position = Vector3(0, 3.5, 0)
		c.add_child(l)
		units.append(c)
		teams.append({"id": t, "name": Data.TEAM_NAMES[t], "color": Data.TEAM_COLORS[t], "crystal": c,
			"heroes": [], "alive": true, "last_hit_sfx": 0.0})
		for p in z.pads:
			_build_pad(p)
		for tp in z.towers:
			towers.append({"zone": t, "pos": tp, "top": tp + Vector3(0, 6.2, 0), "cd": 0.0})
		for k in z.camps.size():
			camps.append({"area": t, "zone": t, "pos": z.camps[k], "kind": Forest2.CAMPS[k], "units": [], "side": t})
	for p in wild.pads:
		_build_pad(p)
	for c in Wild.camp_list():
		camps.append({"area": Wild.AREA, "zone": -1, "pos": c.pos, "kind": "w" + str(c.kind), "units": [], "side": c.team})
	var spots := Wild.points("horn")
	horns = [
		{"name": "Золотой Рог", "tid": "Y00X", "unit": null, "t": horn_at, "spot": 0, "col": Color(1.0, 0.8, 0.25)},
		{"name": "Серебряный Рог", "tid": "Y00Y", "unit": null, "t": horn_at, "spot": 1 % maxi(1, spots.size()), "col": Color(0.8, 0.88, 1.0)},
		{"name": "Кабуто, Мудрец Белого Змея", "tid": "Y00E", "unit": null, "t": horn_at, "spot": 2 % maxi(1, spots.size()), "col": Color(0.75, 0.6, 1.0)},
	]
	for sp in Wild.points("shrine"):
		runes.append({"pos": sp, "kind": "", "node": null})


## Вид телепорта: круг «1»/«2» — малый портал, врата — большая каменная арка.
func _build_pad(p: Dictionary) -> void:
	var col: Color = p.color
	var gate: bool = p.id == "gate"
	var pm := World.prop("SpawnGate" if gate else "Portal")
	pm.position = p.pos
	if gate:
		# арка стоит за кругом и смотрит на подходящую тропу
		var to: Vector3
		if int(p.area) == Wild.AREA:
			to = Wild.CENTER - (p.pos as Vector3)
		else:
			var z: Zone = zones[int(p.area)]
			to = z.to_world(3.6, 87.8) - (p.pos as Vector3)
		to.y = 0.0
		pm.position = (p.pos as Vector3) - to.normalized() * 1.6
		pm.rotation.y = atan2(to.x, to.z)
		pm.scale = Vector3.ONE * 0.9
	else:
		pm.scale = Vector3.ONE * 0.7
		World.recolor(pm, "PortalGlow", col, 0.9)
	add_child(pm)
	var lbl := Label3D.new()
	lbl.text = ("Врата → %s" % p.to_name) if gate else ("%s → %s" % [p.id, p.to_name])
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.font_size = 52
	lbl.outline_size = 10
	lbl.modulate = col.lightened(0.25)
	lbl.position = (p.pos as Vector3) + Vector3(0, 6.4 if gate else 4.2, 0)
	lbl.pixel_size = 0.011
	add_child(lbl)
	var swirl := MeshInstance3D.new()
	swirl.mesh = Fx.flat_ring_mesh(0.9 if gate else 0.6, 1.5 if gate else 1.05, 6)
	swirl.material_override = Fx.glow_mat(col, 1.0, true, 0.5)
	swirl.position = (p.pos as Vector3) + Vector3(0, 0.15, 0)
	add_child(swirl)
	p["swirl"] = swirl


func _make_indicators() -> void:
	range_ring = MeshInstance3D.new()
	range_ring.mesh = Fx.flat_ring_mesh(0.97, 1.0, 96)
	range_ring.material_override = Fx.glow_mat(Color(0.5, 0.9, 1.0), 1.0, true, 0.5)
	range_ring.visible = false
	add_child(range_ring)
	aoe_ring = MeshInstance3D.new()
	aoe_ring.mesh = Fx.flat_ring_mesh(0.9, 1.0, 64)
	aoe_ring.material_override = Fx.glow_mat(Color(1.0, 0.9, 0.5), 1.4, true, 0.8)
	aoe_ring.visible = false
	add_child(aoe_ring)
	hover_ring = MeshInstance3D.new()
	hover_ring.mesh = Fx.flat_ring_mesh(0.85, 1.0, 40)
	hover_ring.material_override = Fx.glow_mat(Color(1, 0.3, 0.3), 1.5, true, 0.8)
	hover_ring.visible = false
	add_child(hover_ring)
	# выделенный юнит (ЛКМ): круг под ногами, его данные — в панели осмотра
	sel_ring = MeshInstance3D.new()
	sel_ring.mesh = Fx.flat_ring_mesh(0.82, 1.0, 48)
	sel_ring.material_override = Fx.glow_mat(Color(1.0, 0.85, 0.3), 2.0, true, 0.9)
	sel_ring.visible = false
	add_child(sel_ring)


func _add_team_ring(u: Unit, col: Color, strong: bool) -> void:
	var r := MeshInstance3D.new()
	r.mesh = Fx.flat_ring_mesh(u.radius + 0.15, u.radius + 0.4 + (0.12 if strong else 0.0), 40)
	r.material_override = Fx.glow_mat(col, 2.2 if strong else 1.4, false, 0.9 if strong else 0.7)
	r.position = Vector3(0, 0.06, 0)
	r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	u.add_child(r)
	u.ring = r


func start_game(hero_id: String) -> void:
	state = "playing"
	# каждой команде — три разных героя, без повторов между командами
	var pool: Array = Data.HERO_ORDER.duplicate()
	pool.erase(hero_id)
	pool.shuffle()
	if roster.size() > 0:
		# заданный состав (тесты): первый — герой игрока
		hero_id = roster[0]
		pool = roster.slice(1)
		pool.reverse()
	for t in 3:
		var ids: Array = []
		if t == 0:
			ids.append(hero_id)
		while ids.size() < 3:
			ids.append(pool.pop_back() if not pool.is_empty() else Data.HERO_ORDER.pick_random())
		for k in 3:
			var h := Hero.new()
			add_child(h)
			var is_player := t == 0 and k == 0
			h.setup(ids[k], t, is_player and not sim)
			h.global_position = zones[t].to_world(-3.0 + k * 3.0, 13.0)
			h.rotation.y = zones[t].facing_inward() + PI
			h.yaw_target = h.rotation.y
			if not h.is_player:
				h.ai = HeroAI.new(k)
			_add_team_ring(h, Color(1.0, 0.86, 0.4) if is_player else Data.TEAM_COLORS[t], is_player)
			units.append(h)
			heroes.append(h)
			teams[t].heroes.append(h)
			if is_player:
				player = h
	if sim:
		player.is_player = false
	else:
		var cr := Courier.new()
		add_child(cr)
		cr.setup(player)
		player.courier = cr
	if autoplay:
		player.ai = HeroAI.new(0)
	_start_w3()
	_preload_models()
	camera.center_on(player.global_position, true)
	hud.on_game_started()
	Audio.music("game")
	if not sim:
		Audio.voice(player.hero_id, "select", 1.0, 0.0)
		hud.announce("Защищайте кристалл выживания! Первая волна через %d сек." % int(Data.FIRST_WAVE), Color(1, 0.9, 0.6), 4.0)
		hud.announce("Круг «2» — в свой мини-лес (каст 3 с), оттуда врата ведут в общий лес. Назад — пешком по лестнице или свитком телепорта",
			Color(0.6, 1.0, 0.6), 6.0)


## Модели эффектов этого матча грузятся в фоновом потоке сразу после старта: способности героев
## (из данных и из триггеров карты), формы и призывы, боссы NCD, их способности и снаряды.
## Без этого каждая модель при первом касте разбиралась из архива прямо в бою — рывки до полсекунды.
func _preload_models() -> void:
	var rt := W3Runtime.I
	if rt == null:
		return
	var paths: Array = []
	var by_hero := {}
	var f := FileAccess.open("res://w3/preload_heroes.json", FileAccess.READ)
	if f:
		var d = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			by_hero = d
	var seen := {}
	var add_unit := func(tid: String, self_ref: Callable) -> void:
		if tid == "" or seen.has("u" + tid):
			return
		seen["u" + tid] = true
		var ud := W3Abil.udata_of(rt, tid)
		for key in ["model", "missile"]:
			if str(ud.get(key, "")) != "":
				paths.append(str(ud[key]))
		for lst in ["abilities", "hero_abilities"]:
			for aid in ud.get(lst, []):
				self_ref.call("a" + str(aid), self_ref)
	var add_abil := func(akey: String, self_ref: Callable) -> void:
		if seen.has(akey):
			return
		seen[akey] = true
		var ad: Dictionary = (rt.data.get("abilities", {}) as Dictionary).get(akey.substr(1), {})
		for v in (ad.get("art", {}) as Dictionary).values():
			if v is String and (v as String).length() > 4:
				paths.append(v)
		for lv in ad.get("levels", []):
			if lv is Dictionary:
				for key in ["unit", "a"]:
					var u2 := str((lv as Dictionary).get(key, ""))
					if u2.length() == 4:
						var ud2 := W3Abil.udata_of(rt, u2)
						if str(ud2.get("model", "")) != "":
							paths.append(str(ud2.model))
	var walk := func(id: String, self_ref: Callable) -> void:
		if id.begins_with("a"):
			add_abil.call(id, self_ref)
		else:
			add_unit.call(id.substr(1), self_ref)
	for h in heroes:
		var hd: Dictionary = by_hero.get(h.hero_id, {})
		paths.append_array(hd.get("models", []))
		for tid in hd.get("units", []):
			walk.call("u" + str(tid), walk)
		walk.call("u" + str(h.def.get("map_unit", "")), walk)
		for ab in h.abilities:
			if ab.def.has("w3"):
				walk.call("a" + str(ab.def.w3), walk)
	paths.append_array(NcdFx.FX_MODELS)
	# лес: волки, Рога и первые хвостатые (остальные догрузятся позже — они появляются раз в 8 минут)
	paths.append("units\\orc\\SpiritWolf\\SpiritWolf.mdl")
	for tid in ["Y00X", "Y00Y", "Y00E"] + (NcdFx.data().get("tailed", []) as Array).slice(0, 3):
		walk.call("u" + str(tid), walk)
	for pair in NcdFx.data().get("boss_waves", []):
		for tid in pair:
			walk.call("u" + str(tid), walk)
	walk.call("u" + str(NcdFx.data().get("creep", "")), walk)
	W3Model.preload_paths(paths)
	print("PRELOAD моделей в очереди: %d" % W3Model.bg_left())


## Триггеры героев из карты Warcraft 3 (переведённый JASS) — способности «как в карте».
func _start_w3() -> void:
	var script: Script = load("res://scripts/w3/w3_map.gd")
	if script == null:
		return
	var w3: W3Runtime = script.new()
	w3.name = "W3"
	add_child(w3)
	w3.setup(self)
	for i in heroes.size():
		w3.bind_hero(heroes[i], i)
	for h in heroes:
		W3Abil.init_hero(w3, h)


# ----------------------------------------------------------------- игровой цикл
func _physics_process(delta: float) -> void:
	if state != "playing":
		return
	if time_stop_left > 0.0:
		time_stop_left -= delta
		if time_stop_left <= 0.0 or not is_instance_valid(time_stop_owner) or not time_stop_owner.alive:
			_end_time_stop()
		_resolve_collisions()
		return
	time += delta
	var battle := not duel.is_empty()
	if battle:
		next_wave += delta
		for s in spawn_queue:
			s.t += delta
	elif time >= next_wave:
		_launch_wave()
	var i := 0
	while i < spawn_queue.size():
		var s: Dictionary = spawn_queue[i]
		if time >= s.t:
			if teams[s.zone].alive:
				_spawn_creep(s.zone, s.boss, s.lane)
			spawn_queue.remove_at(i)
		else:
			i += 1
	_update_camps(delta)
	_update_wild(delta)
	_update_fountains(delta)
	_update_towers(delta)
	_update_duel(delta)
	vision_t -= delta
	if vision_t <= 0.0:
		vision_t = 0.12
		_update_vision()
	_resolve_collisions()
	if sim:
		_sim_tick(delta)


func _process(delta: float) -> void:
	if autoplay and player and player.alive:
		camera.center_on(player.global_position, false)
	if state == "playing":
		_apply_visibility()
		if not sim:
			_update_indicators()
			_update_portals(delta)
			if Engine.get_process_frames() % 20 == 0:
				var sq := player_squad()
				for u: W3Unit in sq:
					if u.ring == null:
						_add_team_ring(u, Color(0.5, 0.95, 1.0), false)
				if not _squad_hint and not sq.is_empty():
					_squad_hint = true
					hud.announce("Клоны и призванные слушаются ваших приказов вместе с героем (ПКМ, A, S, H)", Color(0.6, 0.95, 1.0), 4.0)
	real_t += delta
	var shot_ready := (state == "playing" and time >= shot_time) or (select_shot and real_t >= shot_time)
	# серия кадров: SHOT_SEQ="0.2,0.5,0.9" — ещё снимки через столько секунд после основного (имя_1.png, ...)
	if shot_path != "" and shot_done and not _seq.is_empty() and state == "playing" and time >= shot_time + float(_seq[0]):
		var n_seq := _seq_n
		_seq_n += 1
		_seq.remove_at(0)
		await RenderingServer.frame_post_draw
		var img2 := get_viewport().get_texture().get_image()
		var p2 := shot_path.get_basename() + "_%d.png" % n_seq
		img2.save_png(p2)
		print("SHOT ", p2)
		if _seq.is_empty():
			get_tree().quit()
	if shot_path != "" and not shot_done and shot_ready:
		shot_done = true
		var sq_env := OS.get_environment("SHOT_SEQ")
		if sq_env != "":
			_seq = Array(sq_env.split(","))
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(shot_path)
		print("SHOT ", shot_path)
		if _seq.is_empty():
			get_tree().quit()


func _update_portals(delta: float) -> void:
	for z in zones:
		for p in z.pads:
			(p.swirl as MeshInstance3D).rotate_y(delta * 1.2)
	for p in wild.pads:
		var sw: MeshInstance3D = p.swirl
		sw.rotate_y(delta * 1.2)
		sw.visible = teams[int(p.to_area)].alive
	for r in runes:
		if r.node:
			(r.node as Node3D).rotate_y(delta * 1.6)


## Заморожен ли юнит: остановка времени или все, кроме бойцов, во время битвы команд.
func is_frozen(u: Unit) -> bool:
	if time_stop_left > 0.0 and u != time_stop_owner:
		return true
	if u.team == Data.MONSTER_TEAM and not duel.is_empty() and duel.phase == "fight":
		return true
	return false


func _launch_wave() -> void:
	wave += 1
	next_wave = time + Data.WAVE_INTERVAL
	var boss := wave % Data.BOSS_EVERY == 0
	# каждая тропа получает свою пачку; в волну с боссом — по боссу на тропу
	# монстров в волне больше, чем было (просьба игрока): от 3 до 8 на тропу (было 2–6)
	var count := mini(3 + wave / 4, 8)
	if boss:
		count = maxi(count - 3, 2)
	for t in 3:
		if not teams[t].alive:
			continue
		for lane in 2:
			for k in count:
				spawn_queue.append({"zone": t, "lane": lane, "boss": false, "t": time + k * 0.55 + lane * 0.2})
			if boss:
				spawn_queue.append({"zone": t, "lane": lane, "boss": true, "t": time + count * 0.55 + 0.8})
	if hud:
		var bw := NcdFx.wave_bosses(wave / Data.BOSS_EVERY) if boss else []
		if boss and not bw.is_empty():
			hud.announce("Волна %d — БОССЫ: %s и %s!" % [wave, NcdFx.boss_name(bw[0]), NcdFx.boss_name(bw[1])],
				Color(1.0, 0.35, 0.3), 4.0)
			Audio.sfx("boss_roar", null, 0.8)
		elif boss:
			hud.announce("Волна %d — БОСС: Великий Они!" % wave, Color(1.0, 0.35, 0.3), 3.5)
			Audio.sfx("boss_roar", null, 0.8)
		else:
			hud.announce("Волна %d" % wave, Color(1.0, 0.85, 0.5), 2.0)
			Audio.sfx("wave_horn", null, 0.6)


func _make_creep(z: int, s: Dictionary, boss: bool, name: String) -> Unit:
	var u := Unit.new()
	add_child(u)
	u.kind = Unit.Kind.BOSS if boss else Unit.Kind.CREEP
	u.team = Data.MONSTER_TEAM
	u.area = z
	u.home_zone = z
	u.max_hp = s.hp
	u.hp = s.hp
	u.base_damage = s.damage
	u.armor = s.armor
	u.move_speed = s.speed
	u.attack_cd = s.cd
	u.attack_range = s.range
	u.bounty_gold = s.gold
	u.bounty_xp = s.xp
	u.display_name = name
	units.append(u)
	return u


## Босс — герой карты, которого нет в этой игре: крупная модель, тёмно-красный оттенок, аура.
func _boss_model(u: Unit) -> void:
	var pool: Array = []
	for id in HeroData.HERO_ORDER:
		var used := false
		for h in heroes:
			if h.hero_id == id:
				used = true
		if not used and HeroAssets.has_user_model(id):
			pool.append(id)
	if pool.is_empty():
		u.setup_model("res://models/boss_oni.glb", 1.3)
		return
	var id: String = pool[(wave / maxi(1, Data.BOSS_EVERY) - 1 + pool.size() * 8) % pool.size()]
	var m: Node3D = HeroAssets.model_scene(id).instantiate()
	var info := HeroAssets.fit_model(m, id, 2.7)
	m.scale *= 2.1
	u.attach_model(m, info.anim_map)
	World.recolor(m, "TeamBand", Color(0.7, 0.05, 0.05), 0.35)
	_tint_model(m, Color.WHITE)
	u.display_name = "Босс: %s" % Data.HEROES[id].name
	u.ranged = bool(Data.HEROES[id].ranged)
	if u.ranged:
		u.attack_range = maxf(u.attack_range, 8.0)
		u.proj_color = Color(1.0, 0.3, 0.25)
	u.set_meta("boss_hero", id)
	# тёмная аура под ногами
	var ring := MeshInstance3D.new()
	ring.mesh = Fx.flat_ring_mesh(1.2, 2.6)
	ring.material_override = Fx.glow_mat(Color(0.9, 0.1, 0.15), 2.5, true, 0.55)
	ring.position.y = 0.08
	u.add_child(ring)


static var _boss_overlay: StandardMaterial3D = null


static func _tint_model(n: Node, _c: Color) -> void:
	if _boss_overlay == null:
		_boss_overlay = StandardMaterial3D.new()
		_boss_overlay.albedo_color = Color(0.55, 0.0, 0.05, 0.3)
		_boss_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_boss_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if n is MeshInstance3D:
		(n as MeshInstance3D).material_overlay = _boss_overlay
	for ch in n.get_children():
		_tint_model(ch, _c)


func _spawn_creep(z: int, boss: bool, lane := 0) -> void:
	var s := Data.creep_stats(wave, boss)
	var u := _make_creep(z, s, boss, "Великий Они" if boss else "Бес")
	if boss:
		# боссы NCD по порядку: на каждую тропу свой из пары волны
		var bw := NcdFx.wave_bosses(wave / Data.BOSS_EVERY)
		if bw.is_empty() or not NcdFx.setup_boss(u, bw[lane % bw.size()], wave / Data.BOSS_EVERY):
			_boss_model(u)
			u.radius = 1.5
			u.bar_height = 5.4
	else:
		u.radius = 0.55
		if not NcdFx.setup_creep(u):
			u.setup_model("res://models/creep_imp.glb", 1.45)
			u.bar_height = 2.1
	var zone := zones[z]
	u.lane_id = lane
	u.global_position = zone.nav.clamp(zone.spawns[lane] + Vector3(rng.randf_range(-1.8, 1.8), 0, rng.randf_range(-1.0, 1.0)))
	u.rotation.y = zone.facing_inward()
	u.yaw_target = u.rotation.y
	Fx.burst(fx_root, u.global_position + Vector3(0, 1.0, 0), Color(0.7, 0.3, 0.9), 14, 4.0, 0.3, 0.5)
	if boss:
		Fx.ring_burst(fx_root, u.global_position, 5.0, Color(1.0, 0.3, 0.2), 0.8, 1.0)


# ----------------------------------------------------------------- лес: нейтралы и фонтаны
func _update_camps(_delta: float) -> void:
	if time < next_camps:
		return
	next_camps += CAMP_PERIOD
	for c in camps:
		if int(c.zone) >= 0 and not teams[c.zone].alive:
			continue
		var live: Array = []
		var inside := 0
		for u in c.units:
			if is_instance_valid(u) and u.alive:
				live.append(u)
				if (u as Unit).flat_dist_p(c.pos) < CAMP_ZONE_R:
					inside += 1
		c.units = live
		# в зоне лагеря кто-то остался — новая пачка не появится; увели — появится ещё одна (до 4)
		if inside > 0 or live.size() >= CAMP_MAX_PACKS * _camp_pack(str(c.kind)).size():
			continue
		_spawn_camp(c)


## Состав пачки лагеря: [крупный?, ...]. Мини-лес: слабые лагеря; общий лес: средние (волки) и древние (преступники).
func _camp_pack(kind: String) -> Array:
	match kind:
		"small":
			return [false, false, false]
		"big":
			return [true, false, false, false]
		"wmedium":
			return [true, false, false]
		"wancient":
			return [true, false]
	return [true, false, false]


func _spawn_camp(c: Dictionary) -> void:
	var lvl := maxi(1, wave - 2)
	var kind := str(c.kind)
	var pack := _camp_pack(kind)
	var area := int(c.area)
	for k in pack.size():
		var big: bool = pack[k]
		var s := Data.neutral_stats(lvl, big)
		var u: Unit
		if kind == "wmedium":
			# волчья стая: против лагеря мини-леса выгоднее в полтора раза
			s.hp *= 1.5
			s.damage *= 1.25
			s.gold *= 1.5
			s.xp *= 1.5
			s.speed = 5.2
			u = _make_creep(area, s, false, "Вожак стаи" if big else "Лесной волк")
			u.radius = 0.8 if big else 0.6
			if NcdFx.attach_body(u, "units\\orc\\SpiritWolf\\SpiritWolf.mdl", 1.25 if big else 0.95, 1.5 if big else 1.15,
					1.9 if big else 1.4) == null:
				u.setup_model("res://models/creep_imp.glb", 1.9 if big else 1.4)
				World.recolor(u.model, "ImpSkin", Color(0.5, 0.5, 0.55), 0.05)
				u.bar_height = 2.8 if big else 2.1
		elif kind == "wancient":
			# преступники: B-ранг и A-ранг, втрое выгоднее лагеря мини-леса
			s = Data.neutral_stats(lvl, true)
			var kk := 1.45 if big else 1.0
			s.hp *= 2.1 * kk
			s.damage *= 1.5 * kk
			s.gold *= 2.4 * kk
			s.xp *= 2.4 * kk
			s.speed = 5.0
			u = _make_creep(area, s, false, "Нукэнин A-ранга" if big else "Нукэнин B-ранга")
			u.radius = 0.75
			_outlaw_model(u, big)
		else:
			u = _make_creep(area, s, false, "Лесной вожак" if big else "Лесной бес")
			u.setup_model("res://models/creep_imp.glb", 1.9 if big else 1.35)
			World.recolor(u.model, "ImpSkin", Color(0.22, 0.42, 0.2) if not big else Color(0.35, 0.3, 0.12), 0.05)
			u.radius = 0.85 if big else 0.55
			u.bar_height = 2.8 if big else 2.0
		u.neutral = true
		u.display_name = {"wmedium": "Вожак стаи" if big else "Лесной волк", "wancient": "Нукэнин A-ранга" if big else "Нукэнин B-ранга"}.get(
			kind, "Лесной вожак" if big else "Лесной бес")
		var off := Vector3.ZERO if k == 0 else Vector3(cos(k * 2.1), 0, sin(k * 2.1)) * 1.9
		# следующая пачка стака встаёт чуть в стороне от первой
		off += Vector3(cos(c.units.size() * 1.3), 0, sin(c.units.size() * 1.3)) * (0.0 if c.units.is_empty() else 1.2)
		u.home_pos = nav_of(area).clamp(c.pos + off)
		u.global_position = u.home_pos
		u.rotation.y = randf() * TAU
		u.yaw_target = u.rotation.y
		u.camp = c
		c.units.append(u)
		Fx.burst(fx_root, u.global_position + Vector3(0, 1.0, 0), Color(0.4, 0.9, 0.4), 10, 3.0, 0.25, 0.5)


## Модель «преступника» древнего лагеря — герой карты, которого нет в этой игре (свой для B и для A ранга).
func _outlaw_model(u: Unit, a_rank: bool) -> void:
	if _outlaws.is_empty():
		var pool: Array = []
		for id in HeroData.HERO_ORDER:
			var used := false
			for h in heroes:
				if h.hero_id == id:
					used = true
			if not used and HeroAssets.has_user_model(id):
				pool.append(id)
		_outlaws = [pool[pool.size() / 3] if pool.size() > 0 else "", pool[pool.size() * 2 / 3] if pool.size() > 1 else ""]
	var id: String = _outlaws[1 if a_rank else 0]
	if id == "":
		u.setup_model("res://models/boss_oni.glb", 0.75 if a_rank else 0.6)
		u.bar_height = 3.4 if a_rank else 2.9
		return
	var m: Node3D = HeroAssets.model_scene(id).instantiate()
	var info := HeroAssets.fit_model(m, id, 2.7)
	m.scale *= 1.3 if a_rank else 1.08
	u.attach_model(m, info.anim_map)
	World.recolor(m, "TeamBand", Color(0.25, 0.22, 0.3), 0.1)
	u.bar_height = 3.9 if a_rank else 3.3
	u.ranged = bool(Data.HEROES[id].ranged)
	if u.ranged:
		u.attack_range = 7.5
		u.proj_color = Color(0.8, 0.5, 1.0)
	var ring := MeshInstance3D.new()
	ring.mesh = Fx.flat_ring_mesh(0.8, 1.25)
	ring.material_override = Fx.glow_mat(Color(1.0, 0.45, 0.15) if a_rank else Color(0.75, 0.5, 1.0), 1.6, true, 0.5)
	ring.position.y = 0.08
	u.add_child(ring)


## Башни лагеря: неуязвимы, бьют монстров и чужих героев у входа. Урон не растёт —
## в начале игры башни очень сильны, а к поздним волнам их польза падает.
func _update_towers(delta: float) -> void:
	for tw in towers:
		tw.cd -= delta
		if tw.cd > 0.0 or not teams[tw.zone].alive:
			continue
		var best: Unit = null
		var bd := Data.TOWER_RANGE
		for u in units:
			if not u.alive or u.area != tw.zone or u.team == tw.zone or u.kind == Unit.Kind.CRYSTAL or u.neutral:
				continue
			if not can_see(tw.zone, u):
				continue
			var d := u.flat_dist_p(tw.pos) - u.radius
			if u is Hero:
				d -= 1.5  # чужой герой в лагере — главная цель
			if d < bd:
				bd = d
				best = u
		if best == null:
			continue
		tw.cd = Data.TOWER_CD
		_tower_shot(tw, best)


func _tower_shot(tw: Dictionary, target: Unit) -> void:
	var col: Color = Data.TEAM_COLORS[tw.zone].lightened(0.3)
	var src: Unit = teams[tw.zone].crystal
	var dmg := Data.TOWER_DAMAGE
	if sim:
		deal_damage(src, target, dmg, "tower")
		return
	var start: Vector3 = tw.top
	var n := Fx.spawn(fx_root, start, 1.5, func(node: Fx.FxNode, dt: float) -> bool:
		if not is_instance_valid(target) or not target.alive:
			return false
		var to := target.global_position + Vector3(0, 1.0, 0) - node.global_position
		var step := 34.0 * dt
		if to.length() <= step:
			deal_damage(src, target, dmg, "tower")
			Fx.burst(fx_root, target.global_position + Vector3(0, 1.0, 0), col, 8, 3.0, 0.18, 0.3)
			return false
		node.global_position += to.normalized() * step
		return true)
	var sm := SphereMesh.new()
	sm.radius = 0.25
	sm.height = 0.5
	Fx.add_mesh(n, sm, Fx.glow_mat(col, 3.5))
	Audio.sfx("ice_cast", start, 0.2, 0.2, 0.15)


func _update_fountains(delta: float) -> void:
	fountain_t -= delta
	if fountain_t > 0.0:
		return
	fountain_t = 0.25
	for h in heroes:
		if not h.alive or h.area < 0:
			continue
		var z := zones[h.area]
		var dl := h.flat_dist_p(z.fountain_life)
		var dm := h.flat_dist_p(z.fountain_mana)
		if h.team == h.area:
			# фонтаны лечат только хозяев лагеря
			if dl < 6.0:
				h.hp = minf(h.max_hp, h.hp + (h.max_hp * 0.06 + 15.0) * 0.25)
			if dm < 6.0:
				h.mp = minf(h.max_mp, h.mp + (h.max_mp * 0.06 + 8.0) * 0.25)
		elif teams[h.area].alive and minf(dl, dm) < 7.0 and not h.dueling:
			# а чужого героя рядом бьют
			var from := z.fountain_life if dl < dm else z.fountain_mana
			deal_damage(teams[h.area].crystal, h, (h.max_hp * 0.07 + 40.0) * 0.25, "tower")
			if not sim:
				Fx.burst(fx_root, h.global_position + Vector3(0, 1.0, 0), Color(1.0, 0.4, 0.4) if dl < dm else Color(0.4, 0.6, 1.0),
					6, 3.0, 0.2, 0.3)
				Fx.ring_burst(fx_root, from, 2.2, Color(1.0, 0.5, 0.4), 0.3)


## Расталкивание юнитов. Позиции, радиусы и массы сначала копируются в массивы, пары считаются на них,
## толчки копятся и применяются один раз на юнит (раньше — по два обращения к узлу и к сетке на каждую пару:
## в общей свалке со сотней юнитов это давало 5 мс на кадр).
func _resolve_collisions() -> void:
	var by_area := {}
	for u in units:
		if not u.alive:
			continue
		if not by_area.has(u.area):
			by_area[u.area] = []
		by_area[u.area].append(u)
	const CS := 6.0
	for k in by_area:
		var arr: Array = by_area[k]
		var n := arr.size()
		if n < 2:
			continue
		var px := PackedFloat32Array()
		var pz := PackedFloat32Array()
		var rr := PackedFloat32Array()
		var ms := PackedFloat32Array()
		var ax := PackedFloat32Array()
		var az := PackedFloat32Array()
		px.resize(n)
		pz.resize(n)
		rr.resize(n)
		ms.resize(n)
		ax.resize(n)
		az.resize(n)
		var grid := {}
		for i in n:
			var u: Unit = arr[i]
			var p := u.position
			px[i] = p.x
			pz[i] = p.z
			rr[i] = u.radius
			ms[i] = _mass(u)
			var key := Vector2i(int(floorf(p.x / CS)), int(floorf(p.z / CS)))
			if grid.has(key):
				(grid[key] as Array).append(i)
			else:
				grid[key] = [i]
		for key: Vector2i in grid:
			var cell: Array = grid[key]
			var cn := cell.size()
			for a in cn:
				var i: int = cell[a]
				for b in range(a + 1, cn):
					_pair(i, cell[b], px, pz, rr, ms, ax, az)
			for off: Vector2i in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(-1, 1)]:
				var other = grid.get(key + off)
				if other == null:
					continue
				for i2 in cell:
					for j2 in other:
						_pair(i2, j2, px, pz, rr, ms, ax, az)
		var nav := nav_of(k)
		for i in n:
			var dx := ax[i]
			var dz := az[i]
			if dx == 0.0 and dz == 0.0:
				continue
			var u: Unit = arr[i]
			if u.kind == Unit.Kind.CRYSTAL:
				continue
			# в плотной свалке толчки от многих соседей складываются — за кадр не дальше радиуса
			var lim := maxf(0.25, rr[i])
			var l2 := dx * dx + dz * dz
			if l2 > lim * lim:
				var kk := lim / sqrt(l2)
				dx *= kk
				dz *= kk
			var p0 := u.position
			u.position = nav.slide(p0, Vector3(p0.x + dx, p0.y, p0.z + dz))


static func _pair(i: int, j: int, px: PackedFloat32Array, pz: PackedFloat32Array, rr: PackedFloat32Array,
		ms: PackedFloat32Array, ax: PackedFloat32Array, az: PackedFloat32Array) -> void:
	var dx := px[j] - px[i]
	var dz := pz[j] - pz[i]
	var md := rr[i] + rr[j]
	var d2 := dx * dx + dz * dz
	if d2 >= md * md:
		return
	var d := sqrt(d2)
	if d < 0.001:
		dx = randf_range(-1, 1)
		dz = randf_range(-1, 1)
		d = sqrt(dx * dx + dz * dz)
	var push := md - d
	var nx := dx / d
	var nz := dz / d
	var ma := ms[i]
	var mb := ms[j]
	var ka := mb / (ma + mb) * push
	var kb := ma / (ma + mb) * push
	ax[i] -= nx * ka
	az[i] -= nz * ka
	ax[j] += nx * kb
	az[j] += nz * kb


func _mass(u: Unit) -> float:
	if is_frozen(u):
		return 1000.0
	match u.kind:
		Unit.Kind.CRYSTAL:
			return 1000000.0
		Unit.Kind.BOSS:
			return 6.0
		Unit.Kind.HERO:
			return 2.5
	return 1.0


# ----------------------------------------------------------------- видимость
## Видит ли команда team юнита u (туман войны на арене и невидимость).
func can_see(t: int, u: Unit) -> bool:
	if t < 0 or t > 2 or u.team == t:
		return true
	if u.is_invisible():
		# истинное зрение (камень, глаз) раскрывает невидимых рядом
		for o in heroes:
			if o.team == t and o.alive and o.area == u.area and o.vision_bonus > 0.0 and o.flat_dist(u) < 9.0:
				return true
		return false
	if u.area == -1 and not duel.is_empty() and duel.phase == "fight":
		return u.seen[t]
	# общий лес виден только рядом со своими героями, и чаща перекрывает обзор
	if u.area == Wild.AREA:
		return u.seen[t]
	return true


func _vision_radius(viewer: Hero, target: Unit) -> float:
	var r := Arena.VISION + viewer.vision_bonus
	if target is Hero and (target as Hero).stealth:
		r = minf(r, Arena.STEALTH_VISION + viewer.vision_bonus * 0.5)
	return r


## Кого видит каждая команда в общем лесу: рядом со своим героем и не за чащей.
func _update_wild_vision() -> void:
	var eyes: Array = [[], [], []]
	for h in heroes:
		if h.alive and h.area == Wild.AREA and h.team >= 0 and h.team < 3:
			eyes[h.team].append(h)
	for u in units:
		if u.area != Wild.AREA:
			continue
		for t in 3:
			if u.team == t:
				u.seen[t] = true
				continue
			var ok := false
			for o: Hero in eyes[t]:
				var r := Wild.VISION + o.vision_bonus
				if u is Hero and (u as Hero).stealth:
					r = minf(r, Wild.STEALTH_VISION + o.vision_bonus * 0.5)
				var dd := o.flat_dist(u)
				if dd <= r + u.radius and (dd < 3.5 or wild.nav.los(o.global_position, u.global_position)):
					ok = true
					break
			u.seen[t] = ok
	if sim or player == null:
		return
	var pe: Array = []
	for o: Hero in eyes[player.team]:
		pe.append(Vector4(o.global_position.x, 0, o.global_position.z, Wild.VISION + o.vision_bonus))
	wild.set_fog(pe, 1.0)


func _update_vision() -> void:
	_update_wild_vision()
	if duel.is_empty() or duel.phase != "fight":
		return
	var parts: Array = duel.parts
	for u: Hero in parts:
		if u.area != -1:
			continue
		for t in duel.teams:
			if u.team == t:
				u.seen[t] = true
				continue
			var ok := false
			for o: Hero in parts:
				if o.team != t or not o.alive or o.area != -1:
					continue
				var dd := o.flat_dist(u)
				if dd <= _vision_radius(o, u) and (dd < 3.0 or arena.nav.los(o.global_position, u.global_position)):
					ok = true
					break
			# ударивший раскрывает себя ненадолго
			if not ok and u.last_hit_time > 5.0 and u.last_hit_by and u.last_hit_by.team == t:
				pass
			u.seen[t] = ok
	# туман для игрока
	var eyes: Array = []
	if player and player.dueling:
		for o: Hero in parts:
			if o.team == player.team and o.alive and o.area == -1:
				eyes.append(Vector4(o.global_position.x, 0, o.global_position.z, Arena.VISION + o.vision_bonus))
		arena.set_fog(eyes, 1.0)
	else:
		arena.set_fog([], 0.0)


## Показ/скрытие моделей по туману войны для игрока.
func _apply_visibility() -> void:
	if player == null:
		return
	# далеко от камеры (другие острова) — модель не рисуется и не анимируется: это главная нагрузка
	var f := camera.focus
	var lod_r := camera.dist * 1.9 + 18.0
	var lod2 := lod_r * lod_r
	W3Model.cam_pos = f
	W3Model.cam_r2 = lod2
	for u in units:
		if u.model == null or u.kind == Unit.Kind.CRYSTAL:
			continue
		var vis := can_see(player.team, u)
		if not player.dueling and u.area == -1:
			vis = not u.is_invisible() or u.team == player.team
		var dx := u.position.x - f.x
		var dz := u.position.z - f.z
		if dx * dx + dz * dz > lod2:
			vis = false
		u.model.visible = vis
		var pm := Node.PROCESS_MODE_INHERIT if vis or not u.alive else Node.PROCESS_MODE_DISABLED
		if u.model.process_mode != pm:
			u.model.process_mode = pm
		if u.ring:
			u.ring.visible = vis and u.alive
		# невидимый свой (или раскрытый истинным зрением) — полупрозрачный, как в WC3
		var gh := vis and u.alive and u.is_invisible()
		if gh != u.ghost:
			u.ghost = gh
			W3Unit.set_alpha(u.model, 0.42 if gh else 1.0)


# ----------------------------------------------------------------- запросы
func clamp_to_area(p: Vector3, area: int) -> Vector3:
	return nav_of(area).clamp(p)


func enemies_in_radius(pos: Vector3, r: float, me: Unit, need_sight := true) -> Array[Unit]:
	var out: Array[Unit] = []
	for u in units:
		if not u.alive or u.area != me.area or u.team == me.team or u.kind == Unit.Kind.CRYSTAL or not u.visible:
			continue
		if need_sight and me.team != Data.MONSTER_TEAM and not can_see(me.team, u):
			continue
		var dx := u.position.x - pos.x
		var dz := u.position.z - pos.z
		var rr := r + u.radius
		if dx * dx + dz * dz <= rr * rr:
			out.append(u)
	return out


func nearest_enemy(pos: Vector3, r: float, me: Unit) -> Unit:
	var best: Unit = null
	var bd := 1e9
	for u in units:
		if not u.alive or u.area != me.area or u.team == me.team or u.kind == Unit.Kind.CRYSTAL or not u.visible:
			continue
		if me.team == Data.MONSTER_TEAM:
			if u.is_invisible():
				continue
		elif not can_see(me.team, u):
			continue
		var dx := u.position.x - pos.x
		var dz := u.position.z - pos.z
		var d := sqrt(dx * dx + dz * dz) - u.radius
		if d <= r and d < bd and same_side(me, u):
			bd = d
			best = u
	return best


## Лес отделён от троп стеной деревьев: через неё не дерутся.
func same_side(a: Unit, b: Unit) -> bool:
	if a.area < 0 or a.area != b.area:
		return true
	var z := zones[a.area]
	return z.in_forest(a.global_position) == z.in_forest(b.global_position)


func creeps_near(pos: Vector3, r: float, zone: int) -> int:
	var n := 0
	for u in units:
		if u.alive and u.area == zone and u.team == Data.MONSTER_TEAM and not u.neutral and u.flat_dist_p(pos) <= r:
			n += 1
	return n


func creeps_in_zone(zone: int) -> int:
	var n := 0
	for u in units:
		if u.alive and u.area == zone and u.team == Data.MONSTER_TEAM and not u.neutral:
			n += 1
	return n


func allies_home(h: Hero) -> int:
	var n := 0
	for o: Hero in teams[h.team].heroes:
		if o != h and o.alive and o.area == h.home_zone and not o.dueling:
			n += 1
	return n


func enemy_heroes_near(pos: Vector3, r: float, me: Unit) -> int:
	var n := 0
	for o in heroes:
		if o.alive and o.team != me.team and o.area == me.home_zone and o.flat_dist_p(pos) <= r and can_see(me.team, o):
			n += 1
	return n


## Стоит ли точка под башнями лагеря зоны zone.
func near_tower(pos: Vector3, zone: int, margin := 0.0) -> bool:
	for tw in towers:
		if tw.zone == zone and Vector2(pos.x - tw.pos.x, pos.z - tw.pos.z).length() < Data.TOWER_RANGE + margin:
			return true
	return false


## Ближайший к герою лагерь нейтралов с живыми монстрами на острове zone.
func camp_for_zone(zone: int, h: Hero) -> Dictionary:
	var best := {}
	var bd := 1e9
	for c in camps:
		if c.zone != zone:
			continue
		# слабому герою — лагерь по силам: до лечения теперь идти далеко
		if (str(c.kind) == "medium" and h.level < 3) or (str(c.kind) == "big" and h.level < 5):
			continue
		var alive_n := 0
		for u in c.units:
			if is_instance_valid(u) and u.alive:
				alive_n += 1
		if alive_n == 0:
			continue
		var d := h.flat_dist_p(c.pos)
		if d < bd:
			bd = d
			best = c
	return best


## Лагерь общего леса для бота: на своей стороне, с живыми монстрами; древние — только сильным героям.
func wild_camp_for(h: Hero) -> Dictionary:
	var best := {}
	var bd := 1e9
	for c in camps:
		if int(c.area) != Wild.AREA or int(c.side) != h.team:
			continue
		if str(c.kind) == "wancient" and h.level < 11:
			continue
		var alive_n := 0
		for u in c.units:
			if is_instance_valid(u) and u.alive:
				alive_n += 1
		if alive_n == 0:
			continue
		var d := h.flat_dist_p(c.pos) if h.area == Wild.AREA else (c.pos as Vector3).distance_to(Wild.gate_exit(h.team))
		if d < bd:
			bd = d
			best = c
	return best


func team_alive(t: int) -> bool:
	return t >= 0 and t < 3 and teams[t].alive


func in_battle(h: Hero) -> bool:
	return not duel.is_empty() and duel.phase == "fight" and h.dueling


## Ближайший к герою лагерь нейтралов с живыми монстрами на его острове.
func camp_for(h: Hero) -> Dictionary:
	var best := {}
	var bd := 1e9
	for c in camps:
		if int(c.area) != h.area:
			continue
		var alive_n := 0
		for u in c.units:
			if is_instance_valid(u) and u.alive:
				alive_n += 1
		if alive_n == 0:
			continue
		var d := h.flat_dist_p(c.pos)
		if d < bd:
			bd = d
			best = c
	return best


# ----------------------------------------------------------------- урон и смерть
func deal_damage(src: Unit, dst: Unit, amount: float, kind := "attack", crit := false) -> void:
	if dst == null or not is_instance_valid(dst) or not dst.alive or dst.invulnerable > 0.0:
		return
	if state != "playing" or amount <= 0.0:
		return
	if src != null and not is_instance_valid(src):
		src = null
	var spell := kind == "spell" or kind == "dot"
	if spell and dst.spell_shield > 0.0:
		return
	var hdst: Hero = dst as Hero
	if kind == "attack" and hdst and hdst.evasion > 0.0 and randf() < hdst.evasion:
		if not sim and (dst == player or src == player):
			hud.add_float_text(dst.global_position + Vector3(0, dst.bar_height, 0), "промах", Color(0.8, 0.8, 0.9), false)
		return
	# физический урон (атаки) режет броня, магический (способности) — сопротивление магии
	# балансные множители героя: отдельно для способностей и для атак
	if src is Hero:
		amount *= float((src as Hero).def.get("bal_spell" if spell else "bal_attack", 1.0))
	var mult := 1.0
	if spell:
		mult = 1.0 - clampf(dst.magic_resist, -1.0, 0.9)
	else:
		mult = armor_mult(dst.armor)
	var dmg := amount * mult
	if hdst:
		dmg *= 1.0 - hdst.reduction
		if kind == "attack" and hdst.absorb > 0.0:
			dmg = maxf(dmg * 0.2, dmg - hdst.absorb)
	if dst.kind == Unit.Kind.CRYSTAL:
		dmg *= 0.6
		var tm: Dictionary = teams[dst.team]
		if time - tm.last_hit_sfx > 0.6:
			tm.last_hit_sfx = time
			Audio.sfx("crystal_hit", dst.global_position, 0.5)
	if kind == "attack":
		dmg *= randf_range(0.92, 1.08)
	dst.take_damage(dmg)
	if abiltest and src != null and dst.team != 0:
		var own: bool = src == player or (src is W3Unit and (src as W3Unit).owner_unit == player)
		if own:
			var key := kind + ("" if src == player else "/" + src.display_name.substr(0, 14))
			abil_dmg[key] = float(abil_dmg.get(key, 0.0)) + dmg
	if src is Hero and kind == "attack" and (src as Hero).lifesteal > 0.0:
		src.hp = minf(src.max_hp, src.hp + dmg * (src as Hero).lifesteal)
	if hdst and src and kind == "attack" and hdst.reflect > 0.0 and src.alive and src.kind != Unit.Kind.CRYSTAL:
		src.take_damage(dmg * hdst.reflect)
	if src is Hero and hdst:
		hdst.last_hit_by = src
		hdst.last_hit_time = 6.0
		# удар выдаёт позицию в тумане
		if hdst.area == -1 and not duel.is_empty():
			src.seen[hdst.team] = true
	if not sim and hud and kind != "dot":
		var top := dst.global_position + Vector3(0, dst.bar_height, 0)
		if src == player and player != null:
			var txt := str(int(dmg)) + ("!" if crit else "")
			Fx.number(top, txt, Color(1.0, 0.35, 0.3) if crit else (Color(1.0, 0.85, 0.3) if kind == "spell" else Color(1, 1, 1)),
				crit or kind == "spell")
		elif dst == player:
			Fx.number(top, "-" + str(int(dmg)), Color(1.0, 0.35, 0.3))
	if dst.team == Data.MONSTER_TEAM and src and src.alive and src.area == dst.area:
		if dst.order != "attack" or not dst.valid_target(dst.target_unit):
			if not dst.neutral or src.flat_dist_p(dst.home_pos) < 14.0:
				dst.order = "attack"
				dst.target_unit = src
		if dst.neutral:
			for o in dst.camp.get("units", []):
				if is_instance_valid(o) and o.alive and o != dst and o.order != "attack":
					o.order = "attack"
					o.target_unit = src
	if dst.hp <= 0.0:
		_on_kill(src, dst)


func _on_kill(src: Unit, dst: Unit) -> void:
	if not dst.alive:
		return
	# Reincarnation: встанет снова
	if W3Runtime.I and W3Abil.try_reincarnate(W3Runtime.I, dst):
		return
	W3Abil.note_corpse(dst)
	dst.die()
	units.erase(dst)
	if W3Runtime.I and not (dst is W3Unit):
		W3Runtime.I.on_unit_death(dst, src)
	if dst.kind == Unit.Kind.CRYSTAL:
		_team_destroyed(dst.team)
		return
	var killer: Hero = null
	if src is Hero and is_instance_valid(src):
		killer = src
	elif dst is Hero and (dst as Hero).last_hit_by and (dst as Hero).last_hit_time > 0.0:
		killer = (dst as Hero).last_hit_by
	if dst.kind == Unit.Kind.CREEP or dst.kind == Unit.Kind.BOSS:
		Audio.sfx("creep_die", dst.global_position, 0.45, 0.2, 0.08)
		if killer and killer.team != dst.team:
			killer.gold += int(dst.bounty_gold)
			killer.creep_kills += 1
			if killer == player and hud:
				hud.add_float_text(dst.global_position + Vector3(0, dst.bar_height + 0.6, 0), "+%d" % int(dst.bounty_gold),
					Color(1.0, 0.82, 0.2), false)
				Audio.sfx("coin", null, 0.35, 0.1, 0.05)
		elif src != null and src.kind == Unit.Kind.CRYSTAL:
			# добила башня: золото делится между героями команды на острове
			var mates: Array[Hero] = []
			for o: Hero in teams[src.team].heroes:
				if o.alive and o.area == src.team:
					mates.append(o)
			for o in mates:
				o.gold += int(dst.bounty_gold / mates.size())
			_share_xp(dst.global_position, dst.area, dst.bounty_xp, src.team, 45.0)
			return
		_share_xp(dst.global_position, dst.area, dst.bounty_xp, killer.team if killer else dst.home_zone)
		if dst.kind == Unit.Kind.BOSS and (dst == beast or dst.has_meta("horn")):
			_wild_boss_killed(dst, killer)
		elif dst.kind == Unit.Kind.BOSS:
			if killer:
				killer.add_soul()
			if hud:
				var who := killer.display_name if killer else "Кто-то"
				hud.announce("%s повергает Великого Они!" % who, Color(1.0, 0.8, 0.3), 3.0)
		return
	if dst is Hero:
		var h := dst as Hero
		h.deaths += 1
		var in_duel := h.dueling and not duel.is_empty()
		if in_duel:
			h.respawn_left = 0.0
		else:
			h.respawn_left = minf(5.0 + h.level * 1.2, 35.0) if teams[h.team].alive else 0.0
		Audio.sfx("death", h.global_position, 0.7)
		for o in heroes:
			if o.hero_id == "akame" and o.alive and o != h and o.area == h.area and (o == killer or o.flat_dist(h) < 30.0):
				o.add_soul()
		if killer and killer != h:
			var bounty := 150 + 30 * h.level
			killer.gold += bounty
			killer.kills += 1
			_share_xp(h.global_position, h.area, 100.0 + 45.0 * h.level, killer.team)
			if hud:
				hud.kill_feed(killer, h)
			if killer == player:
				Audio.voice(player.hero_id, "kill", 0.8)
		elif hud:
			hud.kill_feed(null, h)
		if in_duel:
			_check_duel_end()


func _share_xp(pos: Vector3, area: int, amount: float, team: int, radius := 18.0) -> void:
	var got: Array[Hero] = []
	for h in heroes:
		if h.alive and h.team == team and h.area == area and h.flat_dist_p(pos) <= radius:
			got.append(h)
	if got.is_empty():
		return
	var each := amount / got.size() * (1.0 + 0.2 * (got.size() - 1))
	for h in got:
		h.add_xp(each)


func respawn_hero(h: Hero, at: Variant = null) -> void:
	if not teams[h.team].alive:
		return
	var z := zones[h.home_zone]
	h.alive = true
	h.visible = true
	h.area = h.home_zone
	h.dueling = false
	# формы перевоплощения не переживают смерть
	W3Abil.unmorph_all(W3Runtime.I, h)
	h.recalc_stats(true)
	h.stun = 0.0
	h.frozen_ice = 0.0
	h.slow_time = 0.0
	h.dot_time = 0.0
	h.root_time = 0.0
	h.knock = Vector3.ZERO
	h.path.clear()
	h.global_position = (at as Vector3) if at != null else z.hero_spawn + Vector3(rng.randf_range(-2, 2), 0, rng.randf_range(-2, 2))
	h.position.y = 0.0
	h.rotation = Vector3(0, z.facing_inward() + PI, 0)
	h.order = "idle"
	h.target_unit = null
	h.death_time = 0.0
	h.cur_anim = ""
	h.play_anim("Idle")
	if h.ring:
		h.ring.visible = true
	if not units.has(h):
		units.append(h)
	Fx.pillar(fx_root, h.global_position, 1.2, 6.0, Data.TEAM_COLORS[h.team].lightened(0.3), 0.9)
	if h == player:
		camera.center_on(h.global_position, false)
		Audio.voice(h.hero_id, "respawn", 0.8)


func _team_destroyed(t: int) -> void:
	teams[t].alive = false
	teams[t]["dead_t"] = time
	if hud:
		hud.announce("Кристалл выживания команды «%s» разрушен!" % teams[t].name, teams[t].color, 4.0)
	Audio.sfx("crystal_break", null, 1.0)
	Fx.burst(fx_root, zones[t].crystal_pos + Vector3(0, 3, 0), teams[t].color, 80, 16.0, 0.6, 1.5)
	Fx.ring_burst(fx_root, zones[t].crystal_pos, 12.0, teams[t].color, 1.2, 2.0)
	var crystal: Unit = teams[t].crystal
	var tw := crystal.create_tween()
	tw.tween_property(crystal.model, "scale", Vector3(1.6, 0.05, 1.6), 1.2)
	if not duel.is_empty() and t in duel.teams:
		duel.teams.erase(t)
		if duel.teams.size() < 2:
			_end_duel(duel.teams[0] if duel.teams.size() == 1 else -1)
	for h: Hero in teams[t].heroes:
		if h.alive:
			h.die()
			units.erase(h)
		h.respawn_left = 0.0
	for c in camps:
		if c.zone == t:
			for u in c.units:
				if is_instance_valid(u) and u.alive:
					u.die()
					units.erase(u)
	_check_end()


func _check_end() -> void:
	var alive_teams: Array[int] = []
	for t in 3:
		if teams[t].alive:
			alive_teams.append(t)
	if not teams[0].alive:
		_game_over(false)
	elif alive_teams.size() == 1:
		_game_over(true)


func _game_over(win: bool) -> void:
	state = "over"
	targeting = -1
	if time_stop_left > 0.0:
		_end_time_stop()
	arena.set_fog([], 0.0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if hud:
		hud.show_end(win)
	Audio.sfx("victory" if win else "defeat", null, 0.9)
	if sim:
		var order_s := ""
		for t in 3:
			order_s += " T%d:%s" % [t, "alive" if teams[t].alive else ("dead@%.0f" % teams[t].get("dead_t", -1.0))]
		print("SIM END win=%s time=%.0f wave=%d%s" % [win, time, wave, order_s])
		_sim_report()
		get_tree().quit()


# ----------------------------------------------------------------- Махападма
func start_time_stop(h: Hero, dur: float) -> void:
	time_stop_owner = h
	time_stop_left = dur
	var env := World.g_env
	if env:
		env_saved = {"sat": env.adjustment_saturation, "bright": env.adjustment_brightness, "con": env.adjustment_contrast}
		env.adjustment_saturation = 0.12
		env.adjustment_brightness = 0.85
		env.adjustment_contrast = 1.2
	Fx.ring_burst(fx_root, h.global_position, 40.0, Color(0.75, 0.9, 1.0), 1.0, 1.5)
	Fx.burst(fx_root, h.global_position + Vector3(0, 2, 0), Color(0.75, 0.9, 1.0), 60, 14.0, 0.4, 1.0)
	if camera:
		camera.shake(0.4)
	flash_screen(Color(0.8, 0.9, 1.0, 0.5), 0.5)
	if hud:
		hud.announce("МАХАПАДМА — время остановлено (%s)" % h.display_name, Color(0.75, 0.9, 1.0), 3.0)


func _end_time_stop() -> void:
	time_stop_left = 0.0
	var env := World.g_env
	if env and not env_saved.is_empty():
		env.adjustment_saturation = env_saved.sat
		env.adjustment_brightness = env_saved.bright
		env.adjustment_contrast = env_saved.con
	if is_instance_valid(time_stop_owner):
		Audio.sfx("time_resume", null, 0.8)
	time_stop_owner = null


func flash_screen(c: Color, t: float) -> void:
	if hud:
		hud.flash(c, t)


# ----------------------------------------------------------------- битва команд в лабиринте
func _update_duel(delta: float) -> void:
	if duel.is_empty():
		if time >= next_duel:
			_start_duel()
		return
	duel.t += delta
	if duel.phase == "countdown":
		if duel.t >= 4.0:
			_begin_duel_fight()
	elif duel.phase == "fight":
		if duel.t >= Data.DUEL_LIMIT:
			# время вышло: побеждает команда, у которой осталось больше здоровья
			var best := -1
			var bs := -1.0
			var second := -1.0
			for t: int in duel.teams:
				var sc := _team_hp(t)
				if sc > bs:
					second = bs
					bs = sc
					best = t
				elif sc > second:
					second = sc
			if best < 0 or bs - second < 0.05:
				if hud:
					hud.announce("Время битвы вышло — ничья", Color(0.85, 0.85, 0.9), 2.5)
				_end_duel(-1)
			else:
				_end_duel(best)


func _team_hp(t: int) -> float:
	var s := 0.0
	for h: Hero in duel.parts:
		if h.team == t and h.alive:
			s += h.hp / h.max_hp
	return s


## «Лазурные», «Алые» и «Изумрудные»
func _team_list(ts: Array) -> String:
	var names := PackedStringArray()
	for t: int in ts:
		names.append("«%s»" % teams[t].name)
	if names.size() <= 1:
		return "".join(names)
	return ", ".join(names.slice(0, names.size() - 1)) + " и " + names[names.size() - 1]


## Битва команд: на арену выходят все живые команды (две или три), побеждает последняя оставшаяся.
func _start_duel() -> void:
	var cands: Array = []
	for t in 3:
		if teams[t].alive:
			cands.append(t)
	if cands.size() < 2:
		next_duel = time + 60.0
		return
	duel = {"teams": cands, "t": 0.0, "phase": "countdown", "parts": [], "search": {}, "out": []}
	if hud:
		hud.announce("Битва команд через 4 секунды: %s" % _team_list(cands), Color(1.0, 0.8, 0.4), 3.5)
	Audio.sfx("duel_gong", null, 0.9)


func _begin_duel_fight() -> void:
	var ts: Array = []
	for t: int in duel.teams:
		if teams[t].alive:
			ts.append(t)
	if ts.size() < 2:
		duel = {}
		next_duel = time + 30.0
		return
	duel.teams = ts
	duel.phase = "fight"
	duel.t = 0.0
	var parts: Array = []
	for t: int in ts:
		var pts := arena.spawn_points(t)
		var k := 0
		for h: Hero in teams[t].heroes:
			var pos: Vector3 = arena.nav.clamp(pts[k % pts.size()])
			if not h.alive:
				respawn_hero(h, pos)
			Fx.burst(fx_root, h.global_position + Vector3(0, 1, 0), Color(1, 0.85, 0.4), 20, 5.0, 0.3, 0.5)
			h.dueling = true
			h.area = -1
			h.global_position = pos
			h.recalc_stats(true)
			h.issue_stop()
			h.pending = {}
			h.cast_lock = 0.0
			h.stun = 0.0
			h.path.clear()
			h.seen = [false, false, false]
			h.seen[h.team] = true
			h.yaw_target = h.yaw_to(Arena.CENTER)
			h.rotation.y = h.yaw_target
			Fx.pillar(fx_root, h.global_position, 1.2, 6.0, Data.TEAM_COLORS[t].lightened(0.3), 0.8)
			parts.append(h)
			k += 1
	duel.parts = parts
	_update_vision()
	if player in parts:
		camera.center_on(player.global_position, true)
		Audio.voice(player.hero_id, "duel", 1.0, 0.0)
	Audio.music("duel")
	if hud:
		var vs := PackedStringArray()
		for t: int in ts:
			vs.append("«%s»" % teams[t].name)
		vs = PackedStringArray([" против ".join(vs)])
		hud.announce("БИТВА КОМАНД! %s — найдите врагов на арене" % vs[0], Color(1.0, 0.75, 0.3), 3.0)


func _check_duel_end() -> void:
	if duel.is_empty() or duel.phase != "fight":
		return
	var alive: Array = []
	for t: int in duel.teams:
		for h: Hero in duel.parts:
			if h.team == t and h.alive and h.area == -1:
				alive.append(t)
				break
	# команда, у которой не осталось героев на арене, выбывает
	for t: int in duel.teams:
		if not alive.has(t) and not (duel.out as Array).has(t):
			duel.out.append(t)
			if hud and alive.size() >= 2:
				hud.announce("Команда «%s» выбывает из битвы" % teams[t].name, Data.TEAM_COLORS[t], 2.5)
	if alive.is_empty():
		_end_duel(-1)
	elif alive.size() == 1:
		_end_duel(alive[0])


func _end_duel(winner_team: int) -> void:
	if duel.is_empty():
		return
	if sim:
		print("BATTLE t=%.0f teams=%s winner=%d after=%.0fs phase=%s" % [time, str(duel.get("teams", [])), winner_team,
			duel.t, duel.phase])
	var parts: Array = duel.get("parts", [])
	var was_fight: bool = duel.phase == "fight"
	duel = {}
	next_duel = time + Data.DUEL_INTERVAL
	arena.set_fog([], 0.0)
	Audio.music("game")
	if winner_team >= 0 and was_fight:
		for h: Hero in teams[winner_team].heroes:
			h.gold += Data.DUEL_REWARD
			h.add_xp(200.0 + 40.0 * h.level)
		if hud:
			hud.announce("Команда «%s» побеждает в битве! +%d золота каждому" % [teams[winner_team].name, Data.DUEL_REWARD],
				Data.TEAM_COLORS[winner_team], 3.5)
		Audio.sfx("victory", null, 0.6)
	for h: Hero in parts:
		h.dueling = false
		h.seen = [true, true, true]
		if not teams[h.team].alive:
			continue
		if h.alive:
			h.area = h.home_zone
			h.global_position = zones[h.home_zone].hero_spawn + Vector3(rng.randf_range(-2, 2), 0, rng.randf_range(-2, 2))
			h.recalc_stats(true)
			h.issue_stop()
			h.path.clear()
			Fx.pillar(fx_root, h.global_position, 1.2, 6.0, Color(1, 0.85, 0.4), 0.8)
		else:
			respawn_hero(h)
		if h == player:
			camera.center_on(h.global_position, true)


## Общая цель поиска для команды на арене (боты расходятся по арене и ищут врага).
func search_point(t: int, h: Hero) -> Vector3:
	var s: Dictionary = duel.get("search", {})
	var cur: Variant = s.get(t)
	if cur == null or h.flat_dist_p(cur) < 4.0 or duel.t - float(s.get("t%d" % t, 0.0)) > 11.0:
		var p: Vector3
		if cur == null:
			# сначала — к площади со своей стороны, потом — по арене, ближе к центру (там пересекаются пути всех трёх)
			var ax: float = Arena.TEAM_ANGLES[t % 3] + rng.randf_range(-25.0, 25.0)
			p = Arena.world(Arena.dir(ax) * 11.0)
		else:
			var a := rng.randf() * TAU
			p = Arena.world(Vector2(cos(a), sin(a)) * Arena.R * sqrt(rng.randf()) * 0.62)
		cur = arena.nav.clamp(p)
		s[t] = cur
		s["t%d" % t] = duel.t
		duel.search = s
	return cur


# ----------------------------------------------------------------- круги силы
## Может ли герой пользоваться телепортом: «1» и «2» — только хозяева; врата — все, но не к павшей команде.
func pad_usable(h: Hero, p: Dictionary) -> bool:
	if bool(p.own) and h.team != int(p.area):
		return false
	if p.id == "gate" and int(p.to_area) >= 0 and not teams[int(p.to_area)].alive:
		return false
	return true


## Телепорты и врата. Круг «1» срабатывает сразу; «2», врата и свиток — каст: герой должен стоять на месте.
## Оглушение сбивает каст, урон — нет. В точке прибытия на время каста видна метка: все знают, кто прилетает.
func check_portal(h: Hero) -> void:
	if h.dueling or h.area == -1:
		_chan_stop(h)
		return
	var ch: Dictionary = h.chan
	var busy := h.stun > 0.0 or h.silence > 0.0 or h.w3_paused or h.cast_lock > 0.0
	var still := h.order == "idle" or h.order == "hold"
	if not ch.is_empty() and ch.get("scroll", false):
		if busy or not still:
			_chan_stop(h, busy)
		else:
			_chan_tick(h)
		return
	var pad := {}
	if h.portal_cd <= 0.0:
		for p in pads_in(h.area):
			if h.flat_dist_p(p.pos) < Zone.PAD_R + 0.5 and pad_usable(h, p):
				pad = p
				break
	if pad.is_empty():
		_chan_stop(h)
		return
	if float(pad.cast) <= 0.0:
		_teleport(h, pad)
		return
	if busy or not still:
		_chan_stop(h, busy)
		return
	if ch.is_empty() or ch.pad != pad:
		_chan_start(h, pad, float(pad.cast))
	_chan_tick(h)


## Свиток телепорта: откуда угодно — домой, к фонтанам; каст 4 с.
func start_scroll(h: Hero) -> String:
	if h.dueling or h.area == -1:
		return "В битве команд свиток не работает"
	if not teams[h.team].alive:
		return "Лагеря больше нет"
	if not h.chan.is_empty():
		return "Телепорт уже читается"
	var z := zones[h.home_zone]
	h.issue_stop()
	_chan_start(h, {"id": "scroll", "pos": h.global_position, "exit": z.to_world(-3.4, 23.2), "to_name": "Лагерь",
		"cast": Wild.CAST_SCROLL, "area": h.area, "to_area": h.home_zone, "own": true, "color": Data.TEAM_COLORS[h.team]},
		Wild.CAST_SCROLL)
	h.chan["scroll"] = true
	return ""


func _chan_start(h: Hero, pad: Dictionary, dur: float) -> void:
	_chan_stop(h)
	var col: Color = pad.color
	var nodes: Array = []
	if not sim:
		# круг под героем и метка прибытия
		var a := MeshInstance3D.new()
		a.mesh = Fx.flat_ring_mesh(1.25, 1.6, 40)
		a.material_override = Fx.glow_mat(col, 2.2, true, 0.75)
		fx_root.add_child(a)
		a.global_position = h.global_position + Vector3(0, 0.12, 0)
		var b := MeshInstance3D.new()
		b.mesh = Fx.flat_ring_mesh(1.3, 1.75, 40)
		b.material_override = Fx.glow_mat(Data.TEAM_COLORS[h.team], 2.6, true, 0.8)
		fx_root.add_child(b)
		b.global_position = nav_of(int(pad.to_area)).clamp(pad.exit) + Vector3(0, 0.14, 0)
		var beam := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.5
		cm.bottom_radius = 0.9
		cm.height = 7.0
		cm.cap_top = false
		cm.cap_bottom = false
		beam.mesh = cm
		beam.material_override = Fx.glow_mat(Data.TEAM_COLORS[h.team], 1.6, true, 0.28)
		beam.position.y = 3.5
		b.add_child(beam)
		nodes = [a, b]
		Audio.sfx("portal", h.global_position, 0.35, 0.1, 0.1)
	h.chan = {"pad": pad, "t": 0.0, "dur": dur, "nodes": nodes}


func _chan_tick(h: Hero) -> void:
	var ch: Dictionary = h.chan
	ch.t = float(ch.t) + get_physics_process_delta_time()
	var k := clampf(float(ch.t) / float(ch.dur), 0.0, 1.0)
	for n in ch.nodes:
		if is_instance_valid(n):
			(n as Node3D).rotate_y(0.12)
			(n as Node3D).scale = Vector3.ONE * (1.0 + 0.25 * sin(k * 18.0) * (1.0 - k)) * (0.55 + 0.45 * k)
	if h == player and hud:
		hud.set_channel("Телепорт: %s" % ch.pad.to_name, k, float(ch.dur) - float(ch.t))
	if k < 1.0:
		return
	var pad: Dictionary = ch.pad
	var scroll: bool = ch.get("scroll", false)
	_chan_stop(h)
	if scroll and not h.spend_scroll():
		return
	_teleport(h, pad)


## Прервать каст телепорта. broken — сбили оглушением (сообщение игроку).
func _chan_stop(h: Hero, broken := false) -> void:
	if h.chan.is_empty():
		return
	for n in h.chan.nodes:
		if is_instance_valid(n):
			(n as Node).queue_free()
	h.chan = {}
	if h == player and hud:
		hud.set_channel("", 0.0, 0.0)
		if broken:
			hud.announce("Телепорт сбит!", Color(1.0, 0.45, 0.35), 1.5)


func _teleport(h: Hero, pad: Dictionary) -> void:
	var col: Color = pad.color
	var from_area := h.area
	var from := h.global_position
	var to_area := int(pad.to_area)
	var dst := nav_of(to_area).clamp(pad.exit)
	if not sim:
		Fx.burst(fx_root, from + Vector3(0, 1, 0), col, 18, 4.5, 0.28, 0.45)
	# клоны и призванные рядом уходят вместе с героем
	for u in units:
		if u is W3Unit and (u as W3Unit).owner_unit == h and u.alive and u.area == from_area and u.flat_dist_p(from) < 10.0:
			u.area = to_area
			u.global_position = nav_of(to_area).clamp(dst + (u.global_position - from).limit_length(3.0))
			u.issue_stop()
			u.path.clear()
	h.area = to_area
	h.global_position = dst
	h.portal_cd = 1.5
	h.issue_stop()
	h.pending = {}
	h.path.clear()
	h.seen = [true, true, true]
	if not sim:
		Fx.ring_burst(fx_root, dst, 2.6, Data.TEAM_COLORS[h.team], 0.5)
		Fx.pillar(fx_root, dst, 1.1, 6.0, Data.TEAM_COLORS[h.team].lightened(0.3), 0.7)
		Audio.sfx("portal", dst, 0.7)
	if h == player:
		camera.center_on(dst, true)
		if hud and to_area != from_area:
			if to_area == Wild.AREA:
				hud.announce("Вы в общем лесу. Фонтанов здесь нет — лечиться только дома", Color(0.75, 0.6, 1.0), 2.5)
			elif to_area == h.home_zone:
				hud.announce("Вы вернулись домой", Data.TEAM_COLORS[h.team], 1.5)
			else:
				hud.announce("Вы в мини-лесу команды «%s»" % teams[to_area].name, Data.TEAM_COLORS[to_area], 2.0)


# ----------------------------------------------------------------- общий лес: руны, хвостатые, Рога
const RUNES := {
	"damage": {"name": "Руна урона", "col": Color(1.0, 0.35, 0.25), "text": "+50% урона на 30 с"},
	"haste": {"name": "Руна скорости", "col": Color(1.0, 0.9, 0.3), "text": "+40% скорости на 25 с"},
	"regen": {"name": "Руна восстановления", "col": Color(0.4, 1.0, 0.5), "text": "восстанавливает здоровье и ману 15 с"},
	"invis": {"name": "Руна невидимости", "col": Color(0.6, 0.7, 1.0), "text": "невидимость на 30 с"},
}


func _update_wild(_delta: float) -> void:
	# руны
	if time >= next_runes:
		next_runes += RUNE_PERIOD
		var got := false
		for r in runes:
			if str(r.kind) == "":
				_spawn_rune(r)
				got = true
		if got and hud:
			hud.announce("У святилищ общего леса появились руны", Color(0.6, 0.9, 1.0), 2.5)
	for r in runes:
		if str(r.kind) == "":
			continue
		for h in heroes:
			if h.alive and h.area == Wild.AREA and h.flat_dist_p(r.pos) < 2.3:
				_take_rune(h, r)
				break
	# хвостатый
	if beast == null and beast_n < BEAST_NAMES.size():
		if not beast_warned and time >= next_beast - 60.0:
			beast_warned = true
			if hud:
				hud.announce("Через минуту в логове общего леса пробудится %s!" % BEAST_NAMES[beast_n], Color(1.0, 0.55, 0.3), 5.0)
				Audio.sfx("boss_roar", null, 0.5)
		if time >= next_beast:
			_spawn_beast()
	# Рога
	for hn in horns:
		if hn.unit == null and time >= float(hn.t):
			_spawn_horn(hn)


func _spawn_rune(r: Dictionary) -> void:
	var kinds: Array = RUNES.keys()
	r.kind = kinds[rng.randi() % kinds.size()]
	if sim:
		return
	var d: Dictionary = RUNES[r.kind]
	var n := Node3D.new()
	fx_root.add_child(n)
	n.global_position = (r.pos as Vector3) + Vector3(0, 1.75, 0)
	var orb := MeshInstance3D.new()
	var bm := PrismMesh.new()
	bm.size = Vector3(0.75, 0.95, 0.3)
	orb.mesh = bm
	orb.material_override = Forest2._mat(Forest2.GLOW_SHADER, {"col": d.col})
	n.add_child(orb)
	var l := OmniLight3D.new()
	l.light_color = d.col
	l.light_energy = 2.4
	l.omni_range = 8.0
	n.add_child(l)
	r.node = n


func _take_rune(h: Hero, r: Dictionary) -> void:
	var kind := str(r.kind)
	var d: Dictionary = RUNES[kind]
	r.kind = ""
	if r.node:
		(r.node as Node).queue_free()
		r.node = null
	match kind:
		"damage":
			h.add_buff("rune_damage", {"name": d.name, "dmg_mult": 0.5}, 30.0)
		"haste":
			h.bonus_move = maxf(h.bonus_move, 0.4)
			h.buff_time = maxf(h.buff_time, 25.0)
		"regen":
			h.heal_over_time = maxf(h.heal_over_time, h.max_hp * 0.05)
			h.heal_time = 15.0
			h.mana_over_time = maxf(h.mana_over_time, h.max_mp * 0.05)
			h.mana_time = 15.0
		"invis":
			h.invis = maxf(h.invis, 30.0)
	if not sim:
		Fx.pillar(fx_root, h.global_position, 1.0, 5.0, d.col, 0.6)
		Audio.sfx("buff_up", h.global_position, 0.6)
	if hud and (h == player or (player and h.team == player.team)):
		hud.announce("%s: %s — %s" % [h.display_name, d.name, d.text], d.col, 2.5)


func _spawn_beast() -> void:
	beast_n += 1
	beast_warned = false
	var n := beast_n
	var s := Data.creep_stats(maxi(wave, 1), true)
	s.hp *= 3.0 + 0.6 * n
	s.damage *= 1.3 + 0.12 * n
	s.armor += float(n)
	s.gold = 0.0
	s.xp = 0.0
	var u := _make_creep(Wild.AREA, s, true, BEAST_NAMES[n - 1])
	var tids: Array = NcdFx.data().get("tailed", [])
	if n - 1 >= tids.size() or not NcdFx.setup_boss(u, str(tids[n - 1]), 1, true):
		_boss_model(u)
		u.radius = 1.8
		u.bar_height = 6.0
	u.display_name = BEAST_NAMES[n - 1]
	u.neutral = true
	u.n_aggro = 13.0
	u.n_leash = 19.0
	u.home_pos = Wild.lair()
	u.global_position = u.home_pos
	u.set_meta("tails", n)
	beast = u
	Fx.ring_burst(fx_root, u.global_position, 8.0, Color(1.0, 0.4, 0.2), 1.0, 1.2)
	if hud:
		hud.announce("%s пробудился в логове общего леса! Награда — %d золота каждому в команде" % [BEAST_NAMES[n - 1], 400 * n],
			Color(1.0, 0.45, 0.25), 5.0)
		Audio.sfx("boss_roar", null, 0.9)


func _spawn_horn(hn: Dictionary) -> void:
	var spots := Wild.points("horn")
	var pos: Vector3 = spots[int(hn.spot) % spots.size()]
	var s := Data.creep_stats(maxi(wave, 1), true)
	s.hp *= 1.5
	s.damage *= 1.1
	s.gold = 0.0
	s.xp = 0.0
	var u := _make_creep(Wild.AREA, s, true, hn.name)
	if not NcdFx.setup_boss(u, str(hn.tid), 1):
		_boss_model(u)
		u.radius = 1.4
		u.bar_height = 5.0
	u.display_name = hn.name
	u.neutral = true
	u.n_aggro = 9.0
	u.n_leash = 10.0   # стационарные: с площадки не уходят
	u.home_pos = pos
	u.global_position = pos
	u.set_meta("horn", hn)
	hn.unit = u
	if hud:
		hud.announce("%s вышел на площадку в общем лесу" % hn.name, hn.col, 3.0)


## Награда за лесного босса — всей команде, чей герой нанёс последний удар.
func _wild_boss_killed(dst: Unit, killer: Hero) -> void:
	var gold := 0
	var xp := 0.0
	if dst == beast:
		var n := int(dst.get_meta("tails", 1))
		gold = 400 * n
		xp = 260.0 * n
		beast = null
		next_beast = time + BEAST_GAP
	elif dst.has_meta("horn"):
		var hn: Dictionary = dst.get_meta("horn")
		hn.unit = null
		hn.t = time + HORN_GAP
		# следующий раз Рог выйдет на другой площадке — по кругу
		horn_rot += 1
		hn.spot = int(hn.spot) + 1
		gold = 250
		xp = 220.0
	else:
		return
	if killer == null:
		if hud:
			hud.announce("%s пал" % dst.display_name, Color(1.0, 0.8, 0.4), 3.0)
		return
	for o: Hero in teams[killer.team].heroes:
		o.gold += gold
		o.add_xp(xp)
	killer.add_soul()
	if hud:
		hud.announce("%s повержен! Команда «%s» получает по %d золота" % [dst.display_name, teams[killer.team].name, gold],
			Data.TEAM_COLORS[killer.team].lightened(0.3), 4.5)
		Audio.sfx("coin", null, 0.6)


# ----------------------------------------------------------------- ввод игрока
func ground_point(screen: Vector2) -> Variant:
	var o := camera.project_ray_origin(screen)
	var d := camera.project_ray_normal(screen)
	if absf(d.y) < 0.0001:
		return null
	var t := -o.y / d.y
	if t < 0.0:
		return null
	var p := o + d * t
	for z in zones:
		if z.contains(p, 1.0):
			for k in 2:
				var hy := Zone.height_local(z.to_local(p))
				if hy <= 0.0:
					break
				p = o + d * ((hy - o.y) / d.y)
			break
	return p


func pick_unit(screen: Vector2) -> Unit:
	var best: Unit = null
	var bd := 1e9
	for u in units:
		if not u.alive or not u.visible or (u.model and not u.model.visible):
			continue
		if u is W3Unit and ((u as W3Unit).dummy or u.model == null):
			continue  # манекены эффектов и невидимые кастеры карты не выбираются
		var base := u.global_position
		var h := u.bar_height * 0.85
		if camera.is_position_behind(base):
			continue
		var p0 := camera.unproject_position(base)
		var p1 := camera.unproject_position(base + Vector3(0, h, 0))
		var hh := absf(p0.y - p1.y) * 0.5
		var c := (p0 + p1) * 0.5
		var hw := maxf(hh * (0.6 if u.kind == Unit.Kind.CRYSTAL else 0.42), 16.0)
		var dx := absf(screen.x - c.x)
		var dy := absf(screen.y - c.y)
		if dx <= hw and dy <= hh + 6.0:
			var d := dx + dy * 0.5
			if d < bd:
				bd = d
				best = u
	return best


func toggle_fullscreen() -> void:
	var m := DisplayServer.window_get_mode()
	if m == DisplayServer.WINDOW_MODE_FULLSCREEN or m == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		var k := (e as InputEventKey)
		if k.physical_keycode == KEY_F11 or (k.physical_keycode == KEY_ENTER and k.alt_pressed):
			toggle_fullscreen()
			get_viewport().set_input_as_handled()


func _unhandled_input(e: InputEvent) -> void:
	if state != "playing" or player == null or sim:
		return
	if e is InputEventMouseButton and e.pressed:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			if targeting >= 0 or attack_move_mode:
				_cancel_targeting()
				return
			var u := pick_unit(mb.position)
			if u and player.is_enemy(u) and player.valid_target(u):
				player.issue_attack(u)
				_squad_order("attack", u.global_position, u)
				_flash_target(u)
				Audio.voice(player.hero_id, "attack", 0.35, 4.0)
			else:
				var gp: Variant = ground_point(mb.position)
				if gp != null:
					var p := clamp_to_area(gp, player.area)
					player.issue_move(p)
					_squad_order("move", p, null)
					Fx.order_marker(fx_root, p, Color(0.3, 1.0, 0.4))
					Audio.voice(player.hero_id, "move", 0.25, 5.0)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if targeting >= 0:
				_confirm_cast(mb.position)
			elif attack_move_mode:
				var gp2: Variant = ground_point(mb.position)
				if gp2 != null:
					var p2 := clamp_to_area(gp2, player.area)
					player.issue_attack_move(p2)
					_squad_order("attack_move", p2, null)
					Fx.order_marker(fx_root, p2, Color(1.0, 0.4, 0.3))
				attack_move_mode = false
				Input.set_default_cursor_shape(Input.CURSOR_ARROW)
			else:
				# ЛКМ по юниту — осмотр (здоровье, предметы, характеристики); по земле — снять выделение
				inspected = pick_unit(mb.position)
				if inspected == player:
					inspected = null
			get_viewport().set_input_as_handled()
	elif e is InputEventKey and e.pressed and not e.echo:
		var k := (e as InputEventKey).physical_keycode
		# Ctrl+Q/W/E/R — вложить очко навыка, Ctrl+A — очко в атрибуты
		if (e as InputEventKey).ctrl_pressed and player and k in [KEY_Q, KEY_W, KEY_E, KEY_R, KEY_A]:
			if k == KEY_A:
				player.learn_stats()
			else:
				var li := [KEY_Q, KEY_W, KEY_E, KEY_R].find(k)
				var lerr := player.learn_error(li)
				if lerr != "":
					hud.error(lerr)
				else:
					player.learn(li)
			get_viewport().set_input_as_handled()
			return
		match k:
			KEY_Q:
				_begin_targeting(0)
			KEY_W:
				_begin_targeting(1)
			KEY_E:
				_begin_targeting(2)
			KEY_R:
				_begin_targeting(3)
			KEY_D:
				_begin_targeting(4)
			KEY_T:
				_begin_targeting(5)
			KEY_F, KEY_G, KEY_V, KEY_X, KEY_Z:
				# способности книги заклинаний (Shiro, Est)
				var letter := OS.get_keycode_string(k)
				for bi in range(6, player.abilities.size()):
					if str(player.abilities[bi].def.get("hotkey", "")) == letter:
						_begin_targeting(bi)
						break
			KEY_A:
				_cancel_targeting()
				attack_move_mode = true
				Input.set_default_cursor_shape(Input.CURSOR_CROSS)
			KEY_S:
				_cancel_targeting()
				player.issue_stop()
				_squad_order("stop", Vector3.ZERO, null)
			KEY_H:
				_cancel_targeting()
				player.issue_hold()
				_squad_order("hold", Vector3.ZERO, null)
			KEY_SPACE, KEY_F1:
				inspected = null
				camera.center_on(player.global_position if player.alive else zones[player.home_zone].hero_spawn, false)
			KEY_B:
				hud.toggle_shop()
			KEY_C:
				hud.send_courier()
			KEY_TAB:
				hud.toggle_scores(true)
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
				var err := player.use_item(k - KEY_1)
				if err != "":
					hud.error(err)
			KEY_ESCAPE:
				if targeting >= 0 or attack_move_mode:
					_cancel_targeting()
			KEY_F2:
				camera.center_on(Arena.CENTER, false)
			KEY_ENTER, KEY_KP_ENTER:
				hud.open_console()
			_:
				return
		get_viewport().set_input_as_handled()
	elif e is InputEventKey and not e.pressed:
		if (e as InputEventKey).physical_keycode == KEY_TAB:
			hud.toggle_scores(false)


## Множитель физического урона от брони (как в WC3: 6% за единицу, отрицательная броня усиливает урон).
static func armor_mult(a: float) -> float:
	if a >= 0.0:
		return 1.0 - (a * 0.06) / (1.0 + a * 0.06)
	return 2.0 - pow(0.94, -a)


## Тест-режим: команды в строке ввода (Enter). Возвращает текст для игрока.
func run_cheat(cmd: String) -> String:
	var p := cmd.strip_edges().to_lower().split(" ", false)
	if p.is_empty() or player == null:
		return ""
	var c := p[0].trim_prefix("-")
	var n := float(p[1]) if p.size() > 1 and p[1].is_valid_float() else -1.0
	match c:
		"gold", "золото", "g":
			var add := int(n) if n > 0.0 else 100000
			player.gold += add
			return "Золото +%d" % add
		"lvl", "level", "ур", "l":
			var target := clampi(int(n) if n > 0.0 else Data.MAX_LEVEL, 1, Data.MAX_LEVEL)
			var guard := 0
			while player.level < target and guard < 100:
				guard += 1
				player.add_xp(Data.xp_to_next(player.level) - player.xp + 1.0)
			player.recalc_stats(true)
			return "Уровень %d" % player.level
		"wave", "волна", "w":
			var to := maxi(1, int(n) if n > 0.0 else wave + 1)
			wave = to - 1
			next_wave = time
			return "Следующая волна: %d" % to
		"boss", "босс", "b":
			var k := maxi(1, int(n) if n > 0.0 else 1)
			var zi := player.area if player.area >= 0 else player.home_zone
			var keep := wave
			wave = k * Data.BOSS_EVERY
			for lane in 2:
				_spawn_creep(zi, true, lane)
				var bu: Unit = units[units.size() - 1]
				var ang := randf() * TAU
				bu.global_position = clamp_to_area(player.global_position + Vector3(cos(ang), 0, sin(ang)) * 12.0, zi)
			wave = keep
			var bw := NcdFx.wave_bosses(k)
			return "Боссы: %s и %s" % [NcdFx.boss_name(bw[0]), NcdFx.boss_name(bw[1])] if bw.size() == 2 else "Боссы волны %d" % k
		"cd", "refresh", "кд":
			for ab in player.abilities:
				ab.cd = 0.0
			player.w3_cd.clear()
			player.item_cd.clear()
			player.hp = player.max_hp
			player.mp = player.max_mp
			return "Перезарядка сброшена, здоровье и мана полные"
		"god", "бог":
			player.invulnerable = 0.0 if player.invulnerable > 1000.0 else 1e9
			return "Бессмертие " + ("вкл" if player.invulnerable > 1000.0 else "выкл")
		"set", "сет":
			if Data.ITEMS.has("set_" + player.hero_id) and not player.has_item("set_" + player.hero_id):
				player.receive("set_" + player.hero_id, 0)
				player.recalc_stats()
			return "Ультимативный сет выдан — открыт [T]"
		"item", "предмет":
			var id := p[1] if p.size() > 1 else ""
			if not Data.ITEMS.has(id):
				return "Нет такого предмета: " + id
			player.receive(id, int(Data.ITEMS[id].get("charges", 0)))
			player.recalc_stats()
			player.try_auto_combine()
			return "Выдан: " + str(Data.ITEMS[id].name)
		"kill", "убить":
			var nk := 0
			for u in units.duplicate():
				if u.alive and u.team == Data.MONSTER_TEAM and u.area == player.area:
					deal_damage(player, u, 1e12, "spell")
					nk += 1
			return "Убито монстров: %d" % nk
		"help", "помощь", "?":
			return CHEAT_HELP
	return "Неизвестная команда. " + CHEAT_HELP


const CHEAT_HELP := "Команды: -gold [N] · -lvl [N] · -wave N · -boss K (1–10) · -cd · -god · -set · -item id · -kill"


## Клоны и призванные существа героя игрока (как выделенная группа в WC3): получают те же приказы.
func player_squad() -> Array:
	var out: Array = []
	if player == null:
		return out
	for u in get_tree().get_nodes_in_group("w3_tracked"):
		if u is W3Unit and (u as W3Unit).player_squad():
			out.append(u)
	return out


var _squad_hint := false


func _squad_order(kind: String, p: Vector3, t: Unit) -> void:
	var sq := player_squad()
	for k in sq.size():
		var u: W3Unit = sq[k]
		u.manual = true
		var rr := 1.4 * sqrt(float(k + 1))
		var off := Vector3(cos(k * 2.4) * rr, 0.0, sin(k * 2.4) * rr)
		match kind:
			"attack":
				u.issue_attack(t)
			"move":
				u.issue_move(clamp_to_area(p + off, u.area) if u.area != -99 else p + off)
			"attack_move":
				u.issue_attack_move(clamp_to_area(p + off, u.area) if u.area != -99 else p + off)
			"stop":
				u.issue_stop()
			"hold":
				u.issue_hold()


func _flash_target(u: Unit) -> void:
	Fx.ring_burst(fx_root, u.global_position, u.radius + 0.6, Color(1.0, 0.3, 0.25), 0.35, 0.25)


func _begin_targeting(i: int) -> void:
	_cancel_targeting()
	if i >= player.abilities.size():
		return
	var err := player.cast_error(i)
	if err != "":
		hud.error(err)
		Audio.sfx("ui_error", null, 0.5)
		return
	var tgt := player.ability_target(i)
	if tgt == "none":
		player.cast(i, player.global_position)
		return
	targeting = i
	if quick_cast:
		_confirm_cast(get_viewport().get_mouse_position())
		return
	Input.set_default_cursor_shape(Input.CURSOR_CROSS)


func _confirm_cast(screen: Vector2) -> void:
	var i := targeting
	var gp: Variant = ground_point(screen)
	if gp == null:
		_cancel_targeting()
		return
	if player.ability_target(i) == "unit":
		var u := pick_unit(screen)
		if u == null or not player.is_enemy(u) or not player.valid_target(u):
			hud.error("Выберите вражескую цель")
			return
		player.cast(i, u.global_position, u)
	else:
		player.cast(i, gp)
	_cancel_targeting()


func _cancel_targeting() -> void:
	targeting = -1
	attack_move_mode = false
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _update_indicators() -> void:
	var mp := get_viewport().get_mouse_position()
	hovered = pick_unit(mp) if hud and not hud.mouse_over_ui() else null
	if hovered and hovered != player and hovered.kind != Unit.Kind.CRYSTAL:
		hover_ring.visible = true
		hover_ring.global_position = hovered.global_position + Vector3(0, 0.08, 0)
		var s := hovered.radius + 0.55
		hover_ring.scale = Vector3(s, 1, s)
		var enemy := player.is_enemy(hovered)
		(hover_ring.material_override as StandardMaterial3D).albedo_color = Color(1, 0.3, 0.3, 0.8) if enemy else Color(0.4, 1, 0.5, 0.8)
		(hover_ring.material_override as StandardMaterial3D).emission = Color(1, 0.3, 0.3) if enemy else Color(0.4, 1, 0.5)
	else:
		hover_ring.visible = false
	if inspected and (not is_instance_valid(inspected) or not inspected.alive or (inspected.model and not inspected.model.visible)):
		inspected = null
	sel_ring.visible = inspected != null
	if inspected:
		sel_ring.global_position = inspected.global_position + Vector3(0, 0.1, 0)
		var s2 := inspected.radius + 0.7
		sel_ring.scale = Vector3(s2, 1, s2)
		var enemy2 := player.is_enemy(inspected)
		var c2 := Color(1, 0.35, 0.3) if enemy2 else (Color(1.0, 0.85, 0.3) if inspected == player else Color(0.4, 1, 0.5))
		(sel_ring.material_override as StandardMaterial3D).albedo_color = Color(c2, 0.9)
		(sel_ring.material_override as StandardMaterial3D).emission = c2
	if targeting >= 0 and player.alive:
		var a: Dictionary = player.abilities[targeting].def
		var r := player.ability_range(targeting)
		range_ring.visible = r > 0.0
		if r > 0.0:
			range_ring.global_position = player.global_position + Vector3(0, 0.07, 0)
			range_ring.scale = Vector3(r, 1, r)
		var gp: Variant = ground_point(mp)
		var rr: float = a.get("radius", a.get("width", 0.0) * 0.5)
		if gp != null and rr > 0.0:
			aoe_ring.visible = true
			aoe_ring.global_position = (gp as Vector3) + Vector3(0, 0.09, 0)
			aoe_ring.scale = Vector3(rr, 1, rr)
		else:
			aoe_ring.visible = false
	else:
		range_ring.visible = false
		aoe_ring.visible = false


# ----------------------------------------------------------------- автотест
func _sim_tick(delta: float) -> void:
	for h in heroes:
		if not area_time.has(h):
			area_time[h] = {}
		var k := "dead" if not h.alive else ("arena" if h.area < 0 else ("forest" if zones[h.area].in_forest(h.global_position) else ("home" if h.area == h.home_zone else "other")))
		area_time[h][k] = area_time[h].get(k, 0.0) + delta
	if OS.get_environment("ATS_TRACE") != "" and Engine.get_physics_frames() % 120 == 0:
		var th: Hero = heroes[int(OS.get_environment("ATS_TRACE"))]
		var tl := zones[th.area].to_local(th.global_position) if th.area >= 0 else Wild.local(th.global_position)
		print("TRACE t=%.0f a=%d (%.1f,%.1f) %s mode=%s hp=%d%% lvl=%d tgt=%s path=%d chan=%s tp=(%.0f,%.0f)" % [time, th.area, tl.x, tl.y,
			th.order, th.ai.mode if th.ai else "-", int(th.hp / th.max_hp * 100.0), th.level,
			th.target_unit.display_name if is_instance_valid(th.target_unit) else "-", th.path.size(), not th.chan.is_empty(),
			th.target_point.x, th.target_point.z])
	log_t += delta
	if log_t >= (20.0 if OS.get_environment("ATS_FASTLOG") != "" else 60.0):
		log_t = 0.0
		_sim_report()
	_perf_probe()
	if time >= sim_limit:
		print("SIM TIMEOUT time=%.0f wave=%d" % [time, wave])
		_sim_report()
		get_tree().quit()


## Замер нагрузки (PERF_AT=секунда игры): среднее время кадра скриптов и отрисовки за 300 кадров.
var _perf := {}


func _perf_probe() -> void:
	var at := float(OS.get_environment("PERF_AT")) if OS.get_environment("PERF_AT") != "" else -1.0
	if at < 0.0 or time < at or _perf.get("done", false):
		return
	var keys := {"phys": Performance.TIME_PHYSICS_PROCESS, "proc": Performance.TIME_PROCESS,
		"draw": Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME, "prims": Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME,
		"objs": Performance.RENDER_TOTAL_OBJECTS_IN_FRAME, "nodes": Performance.OBJECT_NODE_COUNT}
	for k in keys:
		_perf[k] = float(_perf.get(k, 0.0)) + Performance.get_monitor(keys[k])
	_perf["n"] = int(_perf.get("n", 0)) + 1
	if int(_perf.n) >= (int(OS.get_environment("PERF_N")) if OS.get_environment("PERF_N") != "" else 300):
		_perf["done"] = true
		var n := float(_perf.n)
		if OS.get_environment("PERF_FX") != "":
			var agg := {}
			for wm in get_tree().root.find_children("*", "Node3D", true, false):
				if wm is W3Model:
					var np := 0
					for e in (wm as W3Model).emitters:
						np += (e.parts as Array).size()
					var kk := (wm as W3Model).key.get_file() + (" (выкл)" if not (wm as W3Model).can_process() else "")
					var cur: Array = agg.get(kk, [0, 0])
					agg[kk] = [cur[0] + 1, cur[1] + np]
			var ks2 := agg.keys()
			ks2.sort_custom(func(a, b): return agg[a][1] > agg[b][1])
			for k in ks2.slice(0, 14):
				print("  FX %-40s моделей %d частиц %d" % [k, agg[k][0], agg[k][1]])
		print("PERF t=%.0f wave=%d units=%d | physics %.2f ms | process %.2f ms | draw calls %.0f | prims %.0f | objects %.0f | nodes %.0f" % [
			time, wave, units.size(), _perf.phys / n * 1000.0, _perf.proc / n * 1000.0, _perf.draw / n, _perf.prims / n,
			_perf.objs / n, _perf.nodes / n])


func _sim_report() -> void:
	var dbg := ""
	for h in heroes:
		var at: Dictionary = area_time.get(h, {})
		dbg += " %d%s[h%.0f f%.0f o%.0f a%.0f d%.0f ck%d]" % [h.team, h.hero_id.substr(0, 2), at.get("home", 0.0),
			at.get("forest", 0.0), at.get("other", 0.0), at.get("arena", 0.0), at.get("dead", 0.0), h.creep_kills]
	print("DBG", dbg)
	var cz := ""
	for zi in 3:
		var hist := {}
		for u in units:
			if u.alive and u.area == zi and u.team == Data.MONSTER_TEAM and not u.neutral:
				var l := zones[zi].to_local(u.global_position)
				var key := "%s%d" % [("B" if absf(l.x) < 9.0 and l.y < 29.0 else ("L" if l.x < 0 else "R")), int(floor(l.y / 10.0)) * 10]
				hist[key] = hist.get(key, 0) + 1
		cz += " Z%d%s" % [zi, str(hist)]
	print("CREEPS", cz)
	var ad := ""
	for h: Hero in (heroes if OS.get_environment("ATS_FASTLOG") != "" else teams[0].heroes):
		if h.ai == null or h.area < 0:
			continue
		var l := zones[h.area].to_local(h.global_position)
		var tn: String = h.target_unit.display_name if h.target_unit and is_instance_valid(h.target_unit) else "-"
		ad += " %d%s[%s a%d %s (%.0f,%.0f) %s→%s hp%.0f%%]" % [h.team, h.hero_id.substr(0, 2), h.ai.mode, h.area,
			zones[h.area].region(h.global_position), l.x, l.y, h.order, tn, h.hp / h.max_hp * 100.0]
	print("AI", ad)
	var s := "t=%4.0f wave=%2d units=%3d |" % [time, wave, units.size()]
	for t in 3:
		var c: Unit = teams[t].crystal
		s += " T%d cr=%5.0f" % [t, c.hp if teams[t].alive else 0.0]
		for h: Hero in teams[t].heroes:
			var sets := "S" if h.has_set() else ""
			s += " %s:L%d/%dk/%dd/%dg/%di%s" % [h.hero_id.substr(0, 3), h.level, h.kills, h.deaths, h.gold,
				6 - h.free_slots(), sets]
		s += " |"
	print(s)


# ----------------------------------------------------------------- проверка интерфейса
func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _key(k: Key) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.keycode = k
	e.pressed = true
	Input.parse_input_event(e)
	var e2 := e.duplicate()
	e2.pressed = false
	Input.parse_input_event(e2)


func _click(btn: MouseButton, pos: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = btn
	e.position = pos
	e.global_position = pos
	e.pressed = true
	get_viewport().push_input(e, true)
	var e2 := e.duplicate()
	e2.pressed = false
	get_viewport().push_input(e2, true)


func _screen_of(p: Vector3) -> Vector2:
	return camera.unproject_position(p)


func _ui_test() -> void:
	await _wait(0.3)
	hud._pick_hero(test_hero)
	await _wait(0.5)
	print("UITEST hero=", player.hero_id, " items=", player.items, " hp=%.0f dmg=%.0f" % [player.max_hp, player.damage_value()])
	camera.center_on(player.global_position, true)
	# фонтаны в лагере: лечат хозяев
	var z := zones[0]
	next_wave = maxf(next_wave, time + 200.0)
	player.hp = player.max_hp * 0.4
	player.issue_move(z.fountain_life + (z.crystal_pos - z.fountain_life).normalized() * 3.0)
	await _wait(4.0)
	print("UITEST fountain heal: hp=%.0f/%.0f dist=%.1f" % [player.hp, player.max_hp, player.flat_dist_p(z.fountain_life)])
	# телепорт «2» из лагеря в мини-лес: каст 3 с; оглушение сбивает
	player.issue_move(z.pads[1].pos)
	for _i in 40:
		await _wait(0.25)
		if not player.chan.is_empty():
			break
	await _wait(0.5)
	print("UITEST pad2 cast started: chan=%s in_base=%s" % [not player.chan.is_empty(), z.in_base(player.global_position)])
	player.apply_stun(0.4)
	await _wait(0.2)
	print("UITEST pad2 stun breaks cast: chan=%s" % (not player.chan.is_empty()))
	await _wait(4.2)
	print("UITEST pad2 -> mini-forest: in_forest=%s" % z.in_forest(player.global_position))
	# из мини-леса вниз по лестнице — пешком
	player.issue_move(z.to_world(0.0, 58.0))
	await _wait(7.0)
	print("UITEST stairs down: region=%s local=%s" % [z.region(player.global_position), z.to_local(player.global_position)])
	# и обратно пешком, к вратам; врата — в общий лес
	player.invulnerable = 60.0
	player.issue_move(z.pads[2].pos)
	for _i in 120:
		await _wait(0.25)
		if not player.chan.is_empty():
			break
	print("UITEST walk to gate: dist=%.1f chan=%s local=%s alive=%s order=%s" % [player.flat_dist_p(z.pads[2].pos),
		not player.chan.is_empty(), z.to_local(player.global_position), player.alive, player.order])
	await _wait(3.5)
	print("UITEST gate -> wild: area=%d (ожидается %d) walkable=%s" % [player.area, Wild.AREA, wild.nav.walkable(player.global_position)])
	# общий лес: к логову и к вратам соседней команды
	player.invulnerable = 60.0
	player.issue_move(Wild.world(Wild.sector(0, 12.0, 0.0)))
	await _wait(7.0)
	print("UITEST wild walk to lair: dist to lair=%.1f" % player.flat_dist_p(Wild.lair()))
	player.global_position = wild.nav.clamp(Wild.gate_exit(1))
	player.issue_move(wild.pads[1].pos)
	await _wait(5.5)
	print("UITEST enemy gate -> enemy mini-forest: area=%d in_forest=%s" % [player.area, zones[1].in_forest(player.global_position)])
	# на чужом острове телепорты «1»/«2» не работают, фонтан бьёт
	var ez := zones[1]
	player.global_position = ez.nav.clamp(ez.pads[0].pos + ez.to_world(0, 3) - ez.to_world(0, 0))
	player.issue_move(ez.pads[0].pos)
	await _wait(1.5)
	print("UITEST enemy pad ignored: region=%s area=%d" % [ez.region(player.global_position), player.area])
	player.invulnerable = 0.0
	player.hp = player.max_hp
	player.global_position = ez.nav.clamp(ez.fountain_life + (ez.crystal_pos - ez.fountain_life).normalized() * 3.0)
	player.issue_hold()
	await _wait(1.0)
	print("UITEST enemy fountain hurts: hp=%.0f/%.0f" % [player.hp, player.max_hp])
	# свиток телепорта: домой, каст 4 с
	player.invulnerable = 8.0
	player.global_position = ez.nav.clamp(ez.to_world(0.0, 46.0))
	player.items[5] = "tp_scroll"
	player.item_ch[5] = 1
	var serr := player.use_item(5)
	await _wait(4.6)
	print("UITEST scroll: err='%s' area=%d in_base=%s scroll_left=%s" % [serr, player.area, z.in_base(player.global_position),
		player.items[5]])
	# покупка вне лагеря и доставка курьером
	player.issue_move(z.pads[0].pos)
	await _wait(3.0)
	print("UITEST pad1 -> center: region=%s" % z.region(player.global_position))
	player.gold += 1000
	hud.try_buy("short_sword")
	print("UITEST remote buy: base=%s inv=%s" % [player.base_items, player.items])
	var cerr := player.courier.send()
	await _wait(8.5)
	print("UITEST courier: err='%s' delivered=%s base_left=%d state=%s" % [cerr, player.items.has("short_sword"),
		6 - player.base_items.count(""), player.courier.state])
	player.area = 0
	player.global_position = z.hero_spawn
	player.issue_stop()
	# башни: бьют монстров у входа
	var tw_creep := _make_creep(0, Data.creep_stats(1, false), false, "Бес")
	tw_creep.setup_model("res://models/creep_imp.glb", 1.45)
	tw_creep.global_position = z.to_world(0.0, 3.0)
	tw_creep.lane_index = 12
	var hp0 := tw_creep.hp
	await _wait(2.5)
	print("UITEST tower: creep hp %.0f -> %.0f" % [hp0, tw_creep.hp if tw_creep.alive else 0.0])
	# покупка зелья: заряды
	player.global_position = z.hero_spawn
	player.issue_stop()
	player.gold = 50000
	hud.try_buy("potion")
	hud.try_buy("potion")
	var ps := player.potion_slot()
	print("UITEST potions slot=%d charges=%d" % [ps, player.item_ch[ps] if ps >= 0 else -1])
	# книга
	var s0 := player.s_str
	hud.try_buy("tome_str")
	print("UITEST tome str %.0f -> %.0f" % [s0, player.s_str])
	# сет через рецепты
	var set_id := "set_" + player.hero_id
	var guard := 0
	var plan := HeroAI.next_purchase(player, set_id)
	while plan != "" and plan != "!" and guard < 60:
		var err := player.buy(plan)
		if err != "":
			print("UITEST buy error ", plan, ": ", err)
			break
		plan = HeroAI.next_purchase(player, set_id)
		guard += 1
	print("UITEST set=", player.has_set(), " items=", player.items, " stash=", player.stash, " gold=", player.gold)
	# активный предмет
	var plan2 := HeroAI.next_purchase(player, "antimagic")
	while plan2 != "" and plan2 != "!":
		player.buy(plan2)
		plan2 = HeroAI.next_purchase(player, "antimagic")
	var asl := player.items.find("antimagic")
	if asl < 0:
		player.swap_stash(player.stash.find("antimagic"), true)
		asl = player.items.find("antimagic")
	print("UITEST antimagic slot=", asl, " use=", "'" + player.use_item(asl) + "'", " shield=%.1f" % player.spell_shield)
	# лес: нейтралы
	var camp: Dictionary = camps[0]
	print("UITEST camp units=", camp.units.size(), " alive=", camp.units.filter(func(u): return is_instance_valid(u) and u.alive).size())
	# битва команд в лабиринте
	player.add_xp(3000)
	next_duel = time
	await _wait(4.6)
	print("UITEST battle phase=", duel.get("phase", "none"), " parts=", duel.get("parts", []).size(), " player_in=", player.dueling)
	var foes := 0
	for h: Hero in duel.get("parts", []):
		if h.team != player.team and can_see(player.team, h):
			foes += 1
	print("UITEST visible enemies at start=", foes, " (ожидается 0)")
	var p0 := player.global_position
	player.issue_move(Arena.CENTER)
	await _wait(4.0)
	print("UITEST maze walk moved=%.1f now=%s walkable=%s" % [p0.distance_to(player.global_position), player.global_position,
		arena.nav.walkable(player.global_position)])
	_key(KEY_ESCAPE)
	await _wait(0.1)
	print("UITEST menu visible=", hud.menu_panel.visible, " paused=", get_tree().paused)
	_key(KEY_ESCAPE)
	print("UITEST DONE")
	get_tree().quit()


func _fx_test() -> void:
	next_wave = 9999.0
	next_duel = 9999.0
	var z := zones[0]
	player.global_position = z.to_world(0.0, 52.0)
	player.add_xp(6000)
	player.items[1] = "set_" + player.hero_id
	player.recalc_stats(true)
	for h: Hero in teams[0].heroes:
		if h != player:
			h.global_position = z.to_world(-12.0 if h.hero_id < player.hero_id else 12.0, 45.0)
			h.ai = null
	camera.center_on(z.to_world(0.0, 58.0), true)
	await _wait(0.5)
	for k in 7:
		_spawn_creep(0, k == 3)
		var u: Unit = units[units.size() - 1]
		u.global_position = z.to_world(-4.0 + k * 1.3, 62.0 + (k % 2) * 1.5)
		u.think_timer = 99.0
		u.order = "hold"
	var aim := z.to_world(0.0, 62.0)
	var boss: Unit = units[units.size() - 4]
	await _wait(0.3)
	if fx_slot >= 0:
		camera.target_dist = 19.0
		camera.dist = 19.0
		camera.center_on(z.to_world(0.0, 59.0), true)
		player.mp = player.max_mp
		player.cast(fx_slot, aim, boss)
		return
	for i in range(player.abilities.size()):
		player.mp = player.max_mp
		player.cast(i, aim, boss)
		await _wait(0.35)


## Ракурсы для скриншотов (--cam=base|forest|arena|overview)
func _shot_setup() -> void:
	autoplay = false
	if OS.get_environment("ATS_NOHUD") != "":
		hud.visible = false
	var z := zones[0]
	match shot_cam:
		"base":
			camera.target_dist = 42.0
			camera.dist = 42.0
			camera.center_on(z.to_world(0.0, 14.0), true)
		"forest":
			camera.target_dist = 40.0
			camera.dist = 40.0
			camera.center_on(z.to_world(0.0, 80.0), true)
		"lane":
			camera.target_dist = 52.0
			camera.dist = 52.0
			camera.center_on(z.to_world(0.0, 48.0), true)
		"plateau":
			camera.target_dist = 36.0
			camera.dist = 36.0
			camera.center_on(z.to_world(20.0, 48.0), true)
		"island":
			camera.target_dist = 230.0
			camera.dist = 230.0
			camera.center_on(z.to_world(0.0, 42.0), true)
		"world":
			camera.target_dist = 470.0
			camera.dist = 470.0
			camera.center_on(Vector3(0, 0, -50), true)
		"village":
			camera.target_dist = 46.0
			camera.dist = 46.0
			camera.center_on(z.to_world(-16.0, 20.0), true)
		"gate":
			camera.target_dist = 46.0
			camera.dist = 46.0
			camera.center_on(z.to_world(12.0, 86.0), true)
		"shop":
			camera.center_on(z.to_world(0.0, 14.0), true)
			player.gold = 3000
			hud.toggle_shop()
		"shop2", "hudset":
			# лавка с деревом сборки (часть сета уже есть) или панель с собранным сетом и супер-ультой
			camera.center_on(z.to_world(0.0, 14.0), true)
			player.global_position = z.to_world(0.0, 14.0)
			run_cheat("-lvl 12")
			if shot_cam == "shop2":
				player.receive("orb_fire", 0)
				player.receive("antimagic", 0)
				player.receive("recipe_element", 0)
				player.gold = 900
				player.recalc_stats(true)
				hud.toggle_shop()
				hud.shop_select("set_" + player.hero_id)
			else:
				run_cheat("-set")
				player.gold = 1234
		"inspect":
			# осмотр чужого героя: здоровье, мана, броня, предметы
			camera.center_on(z.to_world(0.0, 14.0), true)
			player.global_position = z.to_world(0.0, 14.0)
			for h: Hero in heroes:
				if h != player and h.team == player.team:
					h.ai = null
					h.global_position = z.to_world(3.0, 16.0)
					h.order = "hold"
					h.add_xp(20000.0)
					for it in ["antimagic", "soul_nature", "orb_fire", "potion"]:
						h.receive(it, 3 if it == "potion" else 0)
					h.recalc_stats(true)
					h.hp = h.max_hp * 0.62
					inspected = h
					break
		"menu", "scores":
			# окна в стиле консоли ATS: меню паузы (без самой паузы) или счёт
			camera.center_on(z.to_world(0.0, 14.0), true)
			if shot_cam == "menu":
				hud.menu_panel.visible = true
			else:
				hud.toggle_scores(true)
		"inspectc":
			# осмотр монстра волны: портрет-буква, «—» вместо атрибутов, пустые способности
			_launch_wave()
			get_tree().create_timer(2.0).timeout.connect(func():
				var best: Unit = null
				for u in units:
					if u.alive and not (u is Hero) and u.kind == Unit.Kind.CREEP and not (u is W3Unit) and (best == null or
							u.global_position.distance_to(player.global_position) < best.global_position.distance_to(player.global_position)):
						best = u
				if best:
					best.stun = 5.0
					best.slow = 0.3
					best.slow_time = 5.0
					inspected = best
					camera.center_on(best.global_position, true))
		"arena":
			next_duel = 1.0
			camera.target_dist = 50.0
			camera.dist = 50.0
			camera.center_on(Arena.CENTER + Vector3(-12, 0, -12), true)
		"overview":
			camera.target_dist = 56.0
			camera.dist = 56.0
			camera.center_on(Vector3(0, 0, -30), true)
	if shot_cam.begins_with("ncd"):
		await _ncd_shot()
	if shot_cam.begins_with("f2") or shot_cam in ["wtop", "wfog", "wgate", "wlair", "wcamp", "wancient", "wshrine", "whorn", "fbase"]:
		await _forest2_shot()
	if shot_cam == "arena":
		await _wait(5.5)
		camera.center_on(player.global_position + Vector3(6, 0, 6), true)
	elif shot_cam == "arenafull":
		next_duel = 1.0
		await _wait(5.5)
		camera.target_dist = 125.0
		camera.dist = 125.0
		camera.center_on(Arena.CENTER + Vector3(0, 0, 6), true)


## Снимки нового леса (--forest2): f2top — весь лес сверху, f2entry — опушка и тропы, f2shrine — развилка
## со святилищем, f2lair — логово хвостатого, f2ancient — древний лагерь. Без --forest2 — тот же ракурс старого леса.
func _forest2_shot() -> void:
	next_wave = 99999.0
	next_duel = 99999.0
	var z := zones[0]
	for h: Hero in heroes:
		h.ai = null
		if h != player:
			h.global_position = z.to_world(-30.0 + heroes.find(h) * 1.5, 8.0)
	# мини-лес: f2top, f2entry, f2gate; общий лес: wtop (весь, без тумана), wfog (как видит игрок), wgate, wlair,
	# wcamp, wancient, wshrine, whorn; база с фонтанами: fbase
	var views := {"f2top": [Vector2(0.0, 80.5), 112.0, 78.0], "f2entry": [Vector2(0.4, 73.0), 40.0, 56.0],
		"f2gate": [Vector2(4.8, 89.0), 26.0, 56.0], "fbase": [Vector2(0.0, 19.0), 44.0, 56.0]}
	var wviews := {"wtop": [Vector2.ZERO, 215.0, 80.0], "wfog": [Vector2.ZERO, 215.0, 80.0],
		"wgate": [Wild.sector(0, 44.0, 0.0), 44.0, 56.0], "wlair": [Vector2(0.0, 2.0), 46.0, 56.0],
		"wcamp": [Wild.sector(0, 40.0, 13.0), 30.0, 56.0], "wancient": [Wild.sector(0, 17.0, 9.0), 30.0, 56.0],
		"wshrine": [Wild.dir(150.0) * 26.0, 30.0, 56.0], "whorn": [Wild.dir(150.0) * 43.0, 36.0, 56.0]}
	if wviews.has(shot_cam):
		var wv: Array = wviews[shot_cam]
		var where: Vector3 = Wild.world(wv[0])
		player.area = Wild.AREA
		player.global_position = wild.nav.clamp(Wild.gate_exit(0) if shot_cam in ["wtop", "wfog", "wgate"] else where + Vector3(2.5, 0, 3.0))
		player.order = "hold"
		camera.far = 900.0
		camera.pitch = wv[2]
		camera.target_dist = wv[1]
		camera.dist = wv[1]
		camera.center_on(where, true)
		next_camps = 0.5
		next_runes = 0.5
		if shot_cam in ["wlair", "wtop"]:
			next_beast = 0.6
		horn_at = 0.6
		for hn in horns:
			hn.t = 0.6
		await _wait(2.5)
		if shot_cam != "wfog":
			# весь лес без тумана войны: монстры видны всем
			wild.fog.visible = false
			wild.fog_mat.set_shader_parameter("strength", 0.0)
			for u in units:
				if u.area == Wild.AREA:
					u.seen = [true, true, true]
			vision_t = 1e9
		await _wait(1.6)
		return
	player.global_position = z.ground(z.to_world(-1.2, 73.0)) if shot_cam != "fbase" else z.to_world(0.0, 15.0)
	player.order = "hold"
	next_camps = 0.5
	var v: Array = views.get(shot_cam, views.f2top)
	camera.pitch = v[2]
	camera.target_dist = v[1]
	camera.dist = v[1]
	var c: Vector2 = v[0]
	camera.center_on(z.to_world(c.x, c.y), true)
	await _wait(4.0)


## Снимки NCD: --cam=ncdboss (--slot=k — пара боссов волны k), --cam=ncdcreeps (волна Белых Зецу),
## --cam=ncdskill (--slot=i — способность героя по толпе Зецу; герой — --hero=madara).
func _ncd_shot() -> void:
	next_wave = 99999.0
	next_duel = 99999.0
	var z := zones[0]
	for h: Hero in heroes:
		h.ai = null
		h.global_position = z.to_world(-30.0 + heroes.find(h) * 1.5, 8.0)
	var c := z.to_world(0.0, 46.0)
	camera.target_dist = 26.0
	camera.dist = 26.0
	camera.center_on(c + Vector3(0, 0, -2), true)
	match shot_cam:
		"ncdboss":
			wave = maxi(1, fx_slot) * Data.BOSS_EVERY
			for lane in 2:
				_spawn_creep(0, true, lane)
				var b: Unit = units[units.size() - 1]
				b.global_position = c + Vector3(-4.5 + lane * 9.0, 0, -2.0)
				b.rotation.y = 0.0
				b.yaw_target = 0.0
				b.think_timer = 9999.0
				b.order = "hold"
			camera.target_dist = 22.0
			camera.dist = 22.0
		"ncdcreeps":
			wave = 9
			for k in 12:
				_spawn_creep(0, false, k % 2)
				var u: Unit = units[units.size() - 1]
				u.global_position = c + Vector3(-6.0 + (k % 6) * 2.4, 0, -3.0 + (k / 6) * 2.6)
				u.think_timer = 9999.0
				u.order = "hold"
		"ncdskill":
			player.add_xp(1e6)
			player.items[1] = "set_" + player.hero_id
			player.recalc_stats(true)
			player.global_position = c + Vector3(0, 0, 6.0)
			player.rotation.y = PI
			wave = 9
			for k in 14:
				_spawn_creep(0, false, k % 2)
				var u: Unit = units[units.size() - 1]
				u.max_hp = 1e7
				u.hp = 1e7
				u.global_position = c + Vector3(-7.0 + (k % 7) * 2.3, 0, -4.0 + (k / 7) * 2.6)
				u.think_timer = 9999.0
				u.order = "hold"
				u.move_speed = 0.0
			camera.target_dist = 30.0
			camera.dist = 30.0
			camera.center_on(c + Vector3(0, 0, 0.5), true)
			await _wait(maxf(0.3, shot_time - float(OS.get_environment("CAST_LEAD") if OS.get_environment("CAST_LEAD") != "" else "1.2")))
			player.mp = player.max_mp
			player.cast(maxi(0, fx_slot), c + Vector3(0, 0, -3.0), units[units.size() - 7])
			# CAST2="ячейка:за сколько секунд до снимка" — вторая способность (например, шаг Акаме в «Козыре»)
			var c2 := OS.get_environment("CAST2")
			if c2 != "":
				var lead := float(OS.get_environment("CAST_LEAD") if OS.get_environment("CAST_LEAD") != "" else "1.2")
				await _wait(lead - float(c2.split(":")[1]))
				player.mp = player.max_mp
				var ok2 := player.cast(int(c2.split(":")[0]), c + Vector3(-5.0, 0, 2.0), units[units.size() - 7])
				print("CAST2 ok=%s err='%s' form=%s slot=%s" % [ok2, player.cast_error(int(c2.split(":")[0])), player.has_buff("akame_form"),
					player.w3_slot(int(c2.split(":")[0]))])


## Проверка урона способностей (--abiltest --hero=X): каждая способность по группе манекенов-целей.
func _abil_test() -> void:
	next_wave = 99999.0
	next_duel = 99999.0
	var z := zones[0]
	for h: Hero in heroes:
		h.ai = null
		if h != player:
			h.global_position = z.to_world(-20.0 + heroes.find(h) * 1.5, 14.0)
	player.global_position = z.to_world(0.0, 52.0)
	player.add_xp(1e7)
	player.items[1] = "set_" + player.hero_id
	player.recalc_stats(true)
	await _wait(0.5)
	var rt := W3Runtime.I
	# цели в 7 м от героя, как до увеличения карты (координаты схемы теперь вдвое крупнее)
	var aim := z.to_world(0.0, 52.0) + Vector3(0.0, 0.0, -7.0)
	for i in player.abilities.size():
		var a: Dictionary = player.abilities[i].def
		var tag := "%s %d %s [%s %s %s]" % [player.hero_id, i, str(a.get("name", "")), str(a.type), str(a.get("w3", "")), str(a.get("code", ""))]
		if fx_slot >= 0 and i != fx_slot:
			continue
		if a.type in ["empty", "book", "passive"] or str(a.get("target", "")) == "passive":
			print("ABIL ", tag, " skip")
			continue
		var tg: Array = []
		for k in 6:
			_spawn_creep(0, false)
			var u: Unit = units[units.size() - 1]
			u.max_hp = 1e7
			u.hp = 1e7
			u.armor = 0.0
			u.bounty_gold = 0.0
			u.bounty_xp = 0.0
			u.global_position = aim + Vector3(cos(k * 1.05) * (0.0 if k == 0 else 2.2), 0, sin(k * 1.05) * (0.0 if k == 0 else 2.2))
			u.think_timer = 9999.0
			u.order = "hold"
			u.move_speed = 0.0
			tg.append(u)
		player.global_position = z.to_world(0.0, 52.0)
		player.stun = 0.0
		player.hp = player.max_hp
		player.max_mp = maxf(player.max_mp, float(a.get("mana", 0.0)) + 10.0)
		player.mp = player.max_mp
		player.order = "hold"
		for ab in player.abilities:
			ab.cd = 0.0
		abil_dmg = {}
		if rt:
			rt.dmg_calls = {}
		var err := player.cast_error(i)
		var ok := player.cast(i, aim, tg[0])
		var stage2 := 0
		for step in 24:
			await _wait(0.5)
			for j in player.abilities.size():
				if not player.w3_slot(j).is_empty() and player.cast_error(j) == "" and player.order != "cast":
					if player.cast(j, aim, tg[0]):
						stage2 += 1
						break
		var total := 0.0
		for u: Unit in tg:
			if is_instance_valid(u):
				total += 1e7 - u.hp
		var parts := []
		for k in abil_dmg:
			parts.append("%s=%.0f" % [k, abil_dmg[k]])
		print("ABIL ", tag, " cast=", ok, " st2=", stage2, " err='", err, "' total=%.0f " % total, " ".join(parts), " calls=", rt.dmg_calls if rt else {})
		for u: Unit in tg:
			if is_instance_valid(u):
				units.erase(u)
				u.queue_free()
		for u in get_tree().get_nodes_in_group("w3_tracked"):
			if u is W3Unit and not (u as W3Unit).dummy and (u as W3Unit).team == 0:
				(u as W3Unit).w3_remove()
		player.recalc_stats()
		await _wait(6.0)
	print("ABILTEST DONE")
	get_tree().quit()


## Замер нагрузки, когда все кастуют разом (--casttest): девять героев на острове 0 бьют способностями толпу,
## каждые 0.7 с — новый залп. Печатает время кадра (среднее и худшее), загрузку и копирование моделей, частицы.
func _cast_test() -> void:
	next_wave = 99999.0
	next_duel = 99999.0
	autoplay = false
	var z := zones[0]
	var c := z.to_world(0.0, 46.0)
	camera.target_dist = 34.0
	camera.dist = 34.0
	camera.center_on(c, true)
	await _wait(0.5)
	var crowd: Array[Unit] = []
	for k in 16:
		_spawn_creep(0, false, k % 2)
		var u: Unit = units[units.size() - 1]
		u.max_hp = 1e7
		u.hp = u.max_hp
		u.base_damage = 0.0
		u.global_position = z.ground(c + Vector3(-5.0 + (k % 4) * 3.0, 0, -9.0 + (k / 4) * 2.5))
		u.think_timer = 9999.0
		u.order = "hold"
		crowd.append(u)
	var hs: Array = heroes.duplicate()
	for i in hs.size():
		var h: Hero = hs[i]
		h.ai = null
		h.area = 0
		h.global_position = z.ground(c + Vector3(-8.0 + (i % 5) * 4.0, 0, 6.0 + (i / 5) * 3.0))
		h.order = "hold"
		var guard := 0
		while h.level < 25 and guard < 60:
			guard += 1
			h.add_xp(Data.xp_to_next(h.level) - h.xp + 1.0)
		if Data.ITEMS.has("set_" + h.hero_id) and not h.has_item("set_" + h.hero_id):
			h.receive("set_" + h.hero_id, 0)
		h.invulnerable = 1e9
		h.recalc_stats(true)
	await _wait(1.0)
	var frames: Array[float] = []
	var vol := 0
	var t_end := 12.0
	var t0 := Time.get_ticks_usec()
	var last := t0
	var next_volley := 0.0
	var tt := 0.0
	var cold_ms := 0.0
	W3Model.stat_load_us = 0
	W3Model.stat_dup_us = 0
	W3Model.stat_proc_us = 0
	W3Model.stat_create_n = 0
	W3Model.stat_load_n = 0
	Prof.acc.clear()
	Prof.cnt.clear()
	var max_parts := 0
	while tt < t_end:
		if tt >= next_volley:
			next_volley += 0.7
			vol += 1
			for h: Hero in hs:
				for i in mini(6, h.abilities.size()):
					h.abilities[i].cd = 0.0
				h.w3_cd.clear()
				h.mp = h.max_mp
				h.stun = 0.0
				var tgt: Unit = crowd[(vol + hs.find(h)) % crowd.size()]
				var idx := (vol + hs.find(h)) % mini(6, h.abilities.size())
				h.cast(idx, tgt.global_position, tgt)
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var ms := (now - last) / 1000.0
		last = now
		frames.append(ms)
		tt += ms / 1000.0
		if vol == 1:
			cold_ms = maxf(cold_ms, ms)
		max_parts = maxi(max_parts, W3Model.live_particles)
	frames.sort()
	var tot := 0.0
	for f in frames:
		tot += f
	var np := 0
	var nm := 0
	for n in get_tree().root.find_children("*", "Node3D", true, false):
		if n is W3Model:
			nm += 1
			for e in (n as W3Model).emitters:
				np += (e.parts as Array).size()
	print("CAST frames=%d avg=%.1f ms p50=%.1f p95=%.1f max=%.1f | first volley worst=%.1f ms" % [frames.size(), tot / frames.size(),
		frames[frames.size() / 2], frames[int(frames.size() * 0.95)], frames[frames.size() - 1], cold_ms])
	print("CAST models created=%d loaded(cold)=%d load=%.0f ms dup=%.0f ms | w3model process=%.0f ms total (%.2f ms/frame) | live models=%d particles=%d" % [
		W3Model.stat_create_n, W3Model.stat_load_n, W3Model.stat_load_us / 1000.0, W3Model.stat_dup_us / 1000.0,
		W3Model.stat_proc_us / 1000.0, W3Model.stat_proc_us / 1000.0 / frames.size(), nm, np])
	print("CAST max live particles=%d budget=%d" % [max_parts, W3Model.particle_budget])
	print("CAST units=%d" % units.size())
	var agg := {}
	for n2 in get_tree().root.find_children("*", "Node3D", true, false):
		if n2 is W3Model:
			var kk: String = (n2 as W3Model).key.get_file()
			agg[kk] = int(agg.get(kk, 0)) + 1
	var ks2 := agg.keys()
	ks2.sort_custom(func(a, b): return agg[a] > agg[b])
	for k2 in ks2.slice(0, 12):
		print("  MODEL %-40s %d" % [k2, agg[k2]])
	var ks := Prof.acc.keys()
	ks.sort_custom(func(a, b): return Prof.acc[a] > Prof.acc[b])
	for k in ks:
		print("  PROF %-16s %.2f ms/кадр" % [k, float(Prof.acc[k]) / 1000.0 / frames.size()])
	get_tree().quit()


## Проверка тест-команд (--cheattest).
func _cheat_test() -> void:
	await get_tree().create_timer(1.0).timeout
	for c in ["-help", "-gold 5000", "-lvl 25", "-cd", "-god", "-god", "-set", "-item boots", "-boss 3", "-wave 10", "-kill", "-lvl"]:
		print("CHEAT ", c, " → ", run_cheat(c), " | lvl=", player.level, " gold=", player.gold, " items=", player.items)
	await get_tree().create_timer(2.0).timeout
	print("CHEAT wave=", wave, " units=", units.size())
	var pl := player
	var st := func(tag: String) -> void:
		print("STATS ", tag, " hp=", int(pl.max_hp), " armor=", snappedf(pl.armor, 0.1), " mres=", snappedf(pl.magic_resist, 0.01),
			" dmg=", int(pl.damage_value()), " range=", snappedf(pl.attack_range, 0.1), " cd=", snappedf(pl.effective_attack_cd(), 0.01),
			" eva=", snappedf(pl.evasion, 0.01), " crit=", snappedf(pl.crit_chance, 0.01), "x", pl.crit_mult, " splash=", pl.morph_mods.get("splash", 0.0))
	st.call("base")
	pl.mp = pl.max_mp
	print("CAST R err='", pl.cast_error(3), "' ok=", pl.cast(3, pl.global_position))
	await get_tree().create_timer(1.0).timeout
	st.call("form")
	# удар по области: поставить двух монстров рядом с целью
	run_cheat("-god")
	var zi := pl.area
	var cr: Array[Unit] = []
	for k in 3:
		_spawn_creep(zi, false, 0)
		var cu: Unit = units[units.size() - 1]
		cu.max_hp = 30000.0
		cu.hp = cu.max_hp
		cu.base_damage = 0.0
		cu.move_speed = 0.0
		cr.append(cu)
	var tp := pl.global_position + Vector3(6.0, 0, 0)
	cr[0].global_position = tp
	cr[1].global_position = tp + Vector3(3.0, 0, 0)
	cr[2].global_position = tp + Vector3(0, 0, 5.2)
	pl.issue_attack(cr[0])
	await get_tree().create_timer(3.0).timeout
	for k in 3:
		print("SPLASH creep", k, " dist=", snappedf(cr[k].global_position.distance_to(tp), 0.1), " lost ", int(cr[k].max_hp - cr[k].hp))
	await get_tree().create_timer(16.0).timeout
	st.call("after")
	get_tree().quit()


## Проверка боссов NCD (--bosstest [--slot=k]): пара боссов каждой волны против героев на острове 0.
func _boss_test() -> void:
	next_wave = 99999.0
	next_duel = 99999.0
	var z := zones[0]
	var rt := W3Runtime.I
	var n := (NcdFx.data().get("boss_waves", []) as Array).size()
	for k in range(1, n + 1):
		if fx_slot > 0 and k != fx_slot:
			continue
		wave = k * Data.BOSS_EVERY
		var made: Array = []
		for lane in 2:
			_spawn_creep(0, true, lane)
			var b: Unit = units[units.size() - 1]
			b.global_position = z.to_world(-3.0 + lane * 6.0, 46.0)
			made.append(b)
		for h: Hero in teams[0].heroes:
			h.respawn_left = 0.0
			if not h.alive:
				respawn_hero(h)
			h.add_xp(maxf(0.0, 2000.0 * k - h.xp))
			h.global_position = z.to_world(randf_range(-4, 4), 40.0)
			h.hp = h.max_hp
		var hp0 := {}
		for h: Hero in teams[0].heroes:
			hp0[h] = h.hp
		await _wait(14.0)
		var parts := []
		for b in made:
			if not is_instance_valid(b):
				parts.append("убит")
				continue
			var d := rt._d(b)
			parts.append("%s hp=%.0f/%.0f h=%.1f casts=%d ranged=%s body=%s" % [b.display_name, b.hp, b.max_hp,
				HeroAssets._aabb(b.model, b.model.transform).size.y if b.model else 0.0, (d.get("cds", {}) as Dictionary).size(),
				b.ranged, (b.model as W3Model).key.get_file() if b.model is W3Model else "-"])
		var lost := 0.0
		for h: Hero in teams[0].heroes:
			lost += maxf(0.0, float(hp0[h]) - h.hp)
		print("BOSS wave=%d " % wave, " | ".join(parts), " heroes_dmg_taken=%.0f" % lost)
		for b in made:
			if is_instance_valid(b):
				units.erase(b)
				b.queue_free()
		for u in units.duplicate():
			if u is W3Unit and u.team == Data.MONSTER_TEAM:
				(u as W3Unit).w3_remove()
	print("BOSSTEST DONE")
	get_tree().quit()


## Проверка механик (--mechtest --hero=X): перевоплощения героя (тип, модель, атака, способности формы,
## возврат), иллюзии предмета, невидимость, Immolation, призыв, перерождение.
func _mech_test() -> void:
	next_wave = 99999.0
	next_duel = 99999.0
	var z := zones[0]
	for h: Hero in heroes:
		h.ai = null
		if h != player:
			h.global_position = z.to_world(-20.0 + heroes.find(h) * 1.5, 14.0)
	player.global_position = z.to_world(0.0, 52.0)
	player.add_xp(1e7)
	player.items[1] = "set_" + player.hero_id
	player.recalc_stats(true)
	await _wait(0.5)
	var rt := W3Runtime.I
	var st := func(tag: String) -> void:
		var mm := player.model
		var d := rt._d(player)
		var slots := []
		for j in player.abilities.size():
			var sid := W3Abil.slot_id(rt, player, j)
			slots.append(W3Runtime.fcc_str(sid) if sid != 0 else "-")
		print("MECH ", tag, " type=", W3Runtime.fcc_str(rt.unit_type_id(player)), " model=", mm.get_class() if mm else "null",
			"/", (mm as W3Model).key if mm is W3Model else str(mm.name) if mm else "", " vis=", mm.visible if mm else false,
			" h=%.2f" % HeroAssets._aabb(mm, mm.transform).size.y if mm else "", " anim=", player.anim_map.get("Run", "?"),
			"/", player.anim.current_animation if player.anim else "-",
			" range=%.1f ranged=%s cd=%.2f spd=%.1f dmg=%.0f hp=%.0f armor=%.1f str=%.0f" % [player.attack_range, player.ranged,
			player.attack_cd, player.move_speed, player.base_damage, player.max_hp, player.armor, player.s_str],
			" missile=", player.missile_art.get_file(), " morphs=", (d.get("morphs", []) as Array).size(), " slots=", slots)
	st.call("base")
	for i in player.abilities.size():
		var a: Dictionary = player.abilities[i].def
		var code := str(a.get("code", ""))
		if not (code in ["ANrg", "AEme", "ANcr"]):
			continue
		player.stun = 0.0
		player.mp = player.max_mp
		player.cast_lock = 0.0
		for ab in player.abilities:
			ab.cd = 0.0
		player.w3_cd.clear()
		print("MECH cast ", a.get("name", ""), " [", a.get("w3", ""), " ", code, "] ok=", player.cast(i, player.global_position + Vector3(0, 0, -3)))
		await _wait(2.0)
		st.call("form")
		# удар формы по цели
		_spawn_creep(0, false)
		var tu: Unit = units[units.size() - 1]
		tu.max_hp = 1e7
		tu.hp = 1e7
		tu.think_timer = 9999.0
		tu.order = "hold"
		tu.move_speed = 0.0
		tu.global_position = player.global_position + Vector3(0, 0, -minf(player.attack_range, 6.0))
		player.issue_attack(tu)
		await _wait(4.0)
		print("MECH attack_in_form dmg=%.0f" % (1e7 - tu.hp), " anim=", player.anim.current_animation if player.anim else "-")
		units.erase(tu)
		tu.queue_free()
		var lvd := W3Abil.lvdata(W3Abil.adata(rt, W3Runtime.fcc(str(a.w3))), 3)
		var hd := float(lvd.get("hdur", 0.0))
		if hd > 0.0:
			await _wait(hd + 1.0)
			st.call("after_time")
		else:
			for ab in player.abilities:
				ab.cd = 0.0
			player.w3_cd.clear()
			player.mp = player.max_mp
			player.order = "idle"
			print("MECH recast ok=", player.cast(i, player.global_position), " err='", player.cast_error(i), "'")
			await _wait(2.0)
			st.call("after_recast")
		W3Abil.unmorph_all(rt, player)
		await _wait(1.5)
	# иллюзии предмета
	player.items[2] = "twins"
	player.item_cd.clear()
	print("MECH twins use='", player.use_item(2), "'")
	await _wait(0.5)
	var ill := []
	for u in units:
		if u.illusion:
			ill.append(u)
	print("MECH illusions n=", ill.size(), " hp=", ill.map(func(u): return int(u.max_hp)), " dmg=", ill.map(func(u): return int(u.base_damage)),
		" taken=", ill.map(func(u): return u.dmg_taken_k), " model=", ill.map(func(u): return u.model.get_class() if u.model else "null"))
	await _wait(11.0)
	var left := 0
	for u in units:
		if u.illusion and u.alive:
			left += 1
	print("MECH illusions_after_time=", left)
	# невидимость: Apiv добавляет и снимает триггер
	rt.UnitAddAbility(player, W3Runtime.fcc("Apiv"))
	await _wait(0.3)
	print("MECH apiv invisible=", player.is_invisible(), " enemy_sees=", can_see(1, player), " ghost=", player.ghost)
	rt.UnitRemoveAbility(player, W3Runtime.fcc("Apiv"))
	await _wait(0.3)
	print("MECH apiv_removed invisible=", player.is_invisible(), " ghost=", player.ghost)
	# Wind Walk (Яя Q)
	W3Abil.cast_base(rt, player, W3Runtime.fcc("A09K"), 1, null, player.global_position)
	print("MECH windwalk invis=%.1f" % player.invis, " move=%.2f" % player.bonus_move, " backstab=", rt._d(player).get("windwalk", 0))
	# Immolation Мисаки
	rt.UnitAddAbility(player, W3Runtime.fcc("AEim"))
	player.mp = player.max_mp
	W3Abil.cast_base(rt, player, W3Runtime.fcc("AEim"), 1, null, player.global_position)
	await _wait(2.1)
	print("MECH immolation on buff=", W3Abil.has_buff(rt, player, W3Runtime.fcc("B00Q")), " mp_used=%.0f" % (player.max_mp - player.mp))
	W3Abil.cast_base(rt, player, W3Runtime.fcc("AEim"), 1, null, player.global_position)
	print("MECH immolation off buff=", W3Abil.has_buff(rt, player, W3Runtime.fcc("B00Q")))
	# призыв (Blessing of Lolis → h060) и Animate Dead
	var before := units.size()
	W3Abil.cast_base(rt, player, W3Runtime.fcc("A0H1"), 1, null, player.global_position + Vector3(2, 0, 0))
	W3Abil.cast_base(rt, player, W3Runtime.fcc("A077"), 1, null, player.global_position)
	await _wait(0.5)
	var sm := []
	for k in range(before, units.size()):
		var u: Unit = units[k]
		sm.append("%s hp=%.0f t=%.0f model=%s" % [u.display_name, u.max_hp, (u as W3Unit).timed_life if u is W3Unit else -1.0,
			u.model.get_class() if u.model else "null"])
	print("MECH summons ", sm)
	# перерождение
	_spawn_creep(0, false)
	var ru: Unit = units[units.size() - 1]
	ru.global_position = player.global_position + Vector3(4, 0, 0)
	rt.UnitAddAbility(ru, W3Runtime.fcc("A0HF"))
	deal_damage(player, ru, 1e9, "spell")
	await _wait(0.2)
	print("MECH reinc alive=", ru.alive, " hp=%.0f" % ru.hp)
	await _wait(8.0)
	print("MECH reinc after hp=%.0f/%.0f" % [ru.hp, ru.max_hp], " paused=", ru.w3_paused)
	print("MECHTEST DONE")
	get_tree().quit()


## Проверка управления клонами (--squadtest --hero=kurumi --slot=2): клоны идут, куда приказал игрок.
func _squad_test() -> void:
	next_wave = 99999.0
	next_duel = 99999.0
	var z := zones[0]
	for h: Hero in heroes:
		h.ai = null
	player.is_player = true
	player.global_position = z.to_world(0.0, 40.0)
	player.add_xp(1e7)
	player.recalc_stats(true)
	await _wait(0.5)
	var slot := maxi(fx_slot, 0)
	player.mp = player.max_mp
	print("SQUAD cast=", player.cast(slot, player.global_position + Vector3(0, 0, 3)))
	await _wait(3.5)
	var sq := player_squad()
	print("SQUAD size=", sq.size(), " lvl=", sq.map(func(u): return u.w3_level), " dmg=", sq.map(func(u): return int(u.base_damage)))
	var goal := z.to_world(8.0, 30.0)
	player.issue_move(goal)
	_squad_order("move", goal, null)
	await _wait(3.0)
	var ds := []
	for u in player_squad():
		ds.append(snappedf(u.flat_dist_p(goal), 0.1))
	print("SQUAD dist_after_move=", ds, " orders=", player_squad().map(func(u): return u.order))
	get_tree().quit()


## Замер героев для баланса. Каждый герой по очереди: 10 с бьёт манекен атаками, потом по разу применяет Q, W, E, R
## по кучке из 8 манекенов и ещё 8 с бьёт атаками. Печатает урон «окна» по всем манекенам и по одному.
func _bal_test() -> void:
	next_wave = 99999.0
	next_duel = 99999.0
	next_camps = 99999.0
	autoplay = false
	var z := zones[0]
	var c := z.to_world(0.0, 46.0)
	await _wait(0.5)
	var hs: Array = heroes.duplicate()
	for i in hs.size():
		var h: Hero = hs[i]
		h.ai = null
		h.area = 1
		h.global_position = zones[1].to_world(-6.0 + i * 1.5, 12.0)
		h.order = "hold"
		h.invulnerable = 1e9
		var guard := 0
		while h.level < bal_lvl and guard < 60:
			guard += 1
			h.add_xp(Data.xp_to_next(h.level) - h.xp + 1.0)
		h.recalc_stats(true)
	var mk := func() -> Unit:
		_spawn_creep(0, false, 0)
		var u: Unit = units[units.size() - 1]
		u.max_hp = 20000.0
		u.hp = u.max_hp
		u.armor = 0.0
		u.magic_resist = 0.0
		u.base_damage = 0.0
		u.think_timer = 1e9
		u.order = "hold"
		u.neutral = true
		return u
	var crowd: Array[Unit] = []
	for k in 8:
		crowd.append(mk.call())
	var place := func() -> void:
		for k in crowd.size():
			if not is_instance_valid(crowd[k]) or not crowd[k].alive:
				crowd[k] = mk.call()   # манекен убит мгновенной смертью — ставим нового
			var u: Unit = crowd[k]
			u.hp = u.max_hp
			u.stun = 0.0
			u.global_position = z.ground(c + Vector3(0, 0, -4.0) + (Vector3.ZERO if k == 0 else Vector3(cos(k * 0.9), 0, sin(k * 0.9)) * 2.2))
			u.order = "hold"
			u.path.clear()
	var total := func() -> Array:
		var sum := 0.0
		var mx := 0.0
		for u in crowd:
			var dd: float = 20000.0 if (not is_instance_valid(u) or not u.alive) else u.max_hp - u.hp
			sum += dd
			mx = maxf(mx, dd)
		return [sum, mx]
	for h: Hero in hs:
		h.area = 0
		h.global_position = z.ground(c)
		h.rotation.y = PI
		place.call()
		await _wait(0.3)
		# атаки
		h.issue_attack(crowd[0])
		await _wait(10.0)
		var auto: Array = total.call()
		var line := "BAL %s lvl=%d hp=%d armor=%.1f dmg=%.0f cd=%.2f rng=%.1f ehp=%d auto_dps=%.0f auto_aoe=%.0f" % [h.hero_id, h.level,
			int(h.max_hp), h.armor, h.base_damage, h.attack_cd, h.attack_range, int(h.max_hp / maxf(armor_mult(h.armor), 0.05)),
			float(auto[1]) / 10.0, float(auto[0]) / 10.0]
		for i in 4:
			var ab: Dictionary = h.abilities[i]
			var def: Dictionary = ab.def
			h.issue_stop()
			await _wait(4.0)   # дать закончиться прежним эффектам и превращениям
			h.global_position = z.ground(c)
			place.call()
			h.mp = h.max_mp
			h.stun = 0.0
			h.silence = 0.0
			for j in h.abilities.size():
				h.abilities[j].cd = 0.0
			h.w3_cd.clear()
			await _wait(0.2)
			var ok := false
			if str(def.type) != "passive" and str(def.type) != "empty":
				ok = h.cast(i, crowd[0].global_position, crowd[0])
			await _wait(0.6)
			if is_instance_valid(crowd[0]) and crowd[0].alive:
				h.issue_attack(crowd[0])
			await _wait(7.4)
			var w: Array = total.call()
			line += " | %s[%s cd=%d mp=%d ok=%s] all=%.0f one=%.0f" % ["qwer"[i], str(def.type).left(3), int(float(def.get("cd", 0.0))),
				int(float(def.get("mana", 0.0))), "1" if ok else "0", float(w[0]), float(w[1])]
		print(line)
		h.issue_stop()
		h.area = 1
		h.global_position = zones[1].to_world(0.0, 12.0)
		await _wait(6.0)
	print("BALTEST DONE")
	get_tree().quit()

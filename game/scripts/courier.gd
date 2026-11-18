class_name Courier
extends Node3D
## Курьер-помощник: снежная сова. Ждёт в лагере; по команде [C] забирает всё, что лежит
## «в лагере» (купленное вне лагеря), летит к герою над стенами и деревьями и отдаёт предметы.
## Летает только над своим островом.

const SPEED := 12.0
const HEIGHT := 3.0

var hero: Hero
var zone: Zone
var state := "home"  # home, go, back
## Груз: [[id, заряды], ...]
var bag: Array = []
var home_pos := Vector3.ZERO
var t := 0.0
var body: Node3D
var wing_r: Node3D
var wing_l: Node3D
var shadow: MeshInstance3D


func setup(h: Hero) -> void:
	hero = h
	zone = Game.I.zones[h.home_zone]
	home_pos = zone.to_world(6.8, 17.0) + Vector3(0, HEIGHT, 0)
	global_position = home_pos
	var col: Color = Data.TEAM_COLORS[h.team]
	body = World.prop("CourierBody")
	World.recolor(body, "TeamCloth", col, 0.4)
	add_child(body)
	wing_r = World.prop("CourierWing")
	wing_r.position = Vector3(0.3, 0.12, 0.02)
	body.add_child(wing_r)
	wing_l = World.prop("CourierWing")
	wing_l.position = Vector3(-0.3, 0.12, 0.02)
	wing_l.scale = Vector3(-1, 1, 1)
	body.add_child(wing_l)
	body.scale = Vector3.ONE * 1.25
	shadow = MeshInstance3D.new()
	shadow.mesh = Fx.disc_mesh(0.55, 16)
	shadow.material_override = Fx.glow_mat(Color(0, 0, 0), 0.0, false, 0.35)
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Game.I.add_child(shadow)
	var ring := MeshInstance3D.new()
	ring.mesh = Fx.flat_ring_mesh(0.62, 0.78, 24)
	ring.material_override = Fx.glow_mat(col, 1.4, true, 0.6)
	shadow.add_child(ring)


func _exit_tree() -> void:
	if is_instance_valid(shadow):
		shadow.queue_free()


func count(id: String) -> int:
	var n := 0
	for e in bag:
		if e[0] == id:
			n += 1
	return n


## Забрать предмет из груза (для рецептов).
func take(id: String) -> bool:
	for i in bag.size():
		if bag[i][0] == id:
			bag.remove_at(i)
			return true
	return false


func can_reach() -> bool:
	return is_instance_valid(hero) and hero.alive and hero.area == hero.home_zone and not hero.dueling


func status_text() -> String:
	var waiting := 6 - hero.base_items.count("")
	match state:
		"go":
			return "Курьер летит к герою (%d)" % bag.size()
		"back":
			return "Курьер возвращается в лагерь"
	if waiting > 0:
		return "В лагере ждёт: %d — нажмите C" % waiting
	return "Курьер в лагере"


## Команда «доставить». Возвращает текст ошибки или "".
func send() -> String:
	if state == "go":
		return "Курьер уже летит к герою"
	if not hero.alive:
		return "Герой мёртв"
	if hero.area != hero.home_zone or hero.dueling:
		return "Курьер летает только над своим островом"
	if state == "home":
		_load()
	if bag.is_empty():
		return "В лагере ничего нет — курьеру нечего везти"
	state = "go"
	Audio.sfx("blink", global_position, 0.35, 0.1)
	return ""


func _load() -> void:
	for i in 6:
		if hero.base_items[i] != "":
			bag.append([hero.base_items[i], hero.base_ch[i]])
			hero.base_items[i] = ""
			hero.base_ch[i] = 0


func _unload_home() -> void:
	var keep: Array = []
	for e in bag:
		var i: int = hero.base_items.find("")
		if i >= 0:
			hero.base_items[i] = e[0]
			hero.base_ch[i] = e[1]
		else:
			keep.append(e)
	bag = keep


func _give() -> void:
	var given := 0
	var keep: Array = []
	for e in bag:
		if hero.receive(e[0], e[1]):
			given += 1
		else:
			keep.append(e)
	bag = keep
	hero.recalc_stats()
	hero.try_auto_combine()
	if given > 0:
		Fx.ring_burst(Game.I.fx_root, hero.global_position, 1.4, Color(1.0, 0.85, 0.4), 0.4)
		Audio.sfx("buy", hero.global_position, 0.6)
	if hero == Game.I.player and Game.I.hud:
		if bag.is_empty():
			Game.I.hud.announce("Курьер доставил предметы: %d" % given, Color(1.0, 0.85, 0.5), 1.8)
		else:
			Game.I.hud.announce("Нет места: %d предм. курьер вернёт в лагерь" % bag.size(), Color(1.0, 0.6, 0.5), 2.2)


func _fly(to: Vector3, delta: float) -> bool:
	var d := to - global_position
	var l := d.length()
	if l < 0.3:
		global_position = to
		return true
	var step := minf(l, SPEED * delta)
	global_position += d / l * step
	var flat := Vector2(d.x, d.z)
	if flat.length() > 0.2:
		rotation.y = lerp_angle(rotation.y, atan2(d.x, d.z), 1.0 - exp(-10.0 * delta))
	return false


func _physics_process(delta: float) -> void:
	if Game.I == null or Game.I.state != "playing" or not is_instance_valid(hero):
		return
	t += delta
	var flap := sin(t * (16.0 if state != "home" else 7.0))
	wing_r.rotation.z = flap * 0.65
	wing_l.rotation.z = -flap * 0.65
	body.position.y = sin(t * 2.6) * 0.12
	match state:
		"go":
			if not can_reach():
				state = "back"
			else:
				var target := hero.global_position + Vector3(0, HEIGHT - 0.4, 0)
				if Vector2(target.x - global_position.x, target.z - global_position.z).length() < 1.6:
					_give()
					state = "back"
				else:
					_fly(target, delta)
		"back":
			if _fly(home_pos, delta):
				state = "home"
				_unload_home()
		_:
			_fly(home_pos, delta)
	var g := global_position
	shadow.global_position = Vector3(g.x, zone.ground(g).y + 0.06, g.z)

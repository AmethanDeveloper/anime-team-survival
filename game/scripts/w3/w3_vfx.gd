class_name W3Vfx
## Замена эффектов карты готовыми эффектами (VfxLib, Binbun CC0).
## Класс эффекта (взрыв, удар, молния, снаряд, волна), цвет и размер посчитаны заранее по самой модели
## (tools/wc3_import/jass/fx_classify.py, поле "vfx" в w3_fx.json). Логика способностей не меняется:
## модель карты остаётся в сцене (её анимации задают время), но прячется, а вместо неё играет новый эффект.

## Естественный размер эффектов библиотеки (поперечник в метрах при scale = 1).
const NATURAL := {"hit": 1.3, "hit2": 1.3, "impact": 2.0, "impact2": 2.0, "big_impact": 3.4, "big_impact2": 3.4,
	"explosion": 4.6, "air_explosion": 4.6, "nuke": 9.0, "zap": 2.6}
## Узнаваемые модели карты (лепестки, ледяные шипы, торнадо…): новый эффект добавляется поверх, модель остаётся.
const AUGMENT := ["cherry_blossom", "judgement", "firetornado", "alice_doll", "hailstorm", "legionstrike", "aquaspike",
	"frost_spike", "icebern", "freezingsplinter", "blizzard", "death_spell", "markofchaos", "lightstrikearray",
	"flamestrike1", "darknova", "earthflare", "iceslam"]
const FIERY := ["fire", "flame", "bomb", "boom", "explo", "nuclear", "mushroom", "meteor", "magma", "burner", "volcano",
	"bijuu", "chaos", "asuma", "ancient", "stkxs", "abomination", "solar", "eruption", "erruption"]

static var off := OS.get_environment("ATS_NOVFX") != ""


static func active() -> bool:
	return not off and not VfxLib.disabled and Game.I != null and not Game.I.sim and Game.I.fx_root != null


## Прятать ли графику модели (решается сразу в W3Model._ready, до первого кадра).
static func wants_hide(m: W3Model) -> bool:
	if not active() or VfxLib.busy():
		return false
	var kind := str((m.info.get("vfx", {}) as Dictionary).get("kind", "keep"))
	match kind:
		"explosion", "impact", "hit", "zap":
			return not _loops(m) and not _augment(m.key)
		"orb", "javelin", "fire":
			return true
		"unknown":
			# своя модель карты без понятного имени: разовая (без зацикленной анимации) — это вспышка/взрыв
			return not _loops(m)
	return false


## Запуск готового эффекта (на следующем кадре, когда у модели уже стоят позиция и масштаб).
static func start_for(m: W3Model, hidden: bool) -> void:
	if not is_instance_valid(m) or not m.is_inside_tree():
		return
	if not on_model_ready(m) and hidden and m.scene_root:
		m.scene_root.visible = true


## Возвращает true, если эффект библиотеки запущен.
static func on_model_ready(m: W3Model) -> bool:
	if not active():
		return false
	var v: Dictionary = m.info.get("vfx", {})
	var kind := str(v.get("kind", "keep"))
	if kind == "keep" or kind == "":
		return false
	var cv: Array = v.get("col", [1.0, 0.9, 0.7])
	var col := Color(float(cv[0]), float(cv[1]), float(cv[2]))
	var gs := absf(m.global_transform.basis.get_scale().x)
	var world := maxf(0.3, float(v.get("size", 2.0)) * gs)
	var key := m.key
	if kind == "unknown":
		if _loops(m):
			return false
		kind = "impact"
		world *= 0.6
	match kind:
		"explosion", "impact", "hit", "zap":
			var lk := _pick(kind, key, world)
			var sc := clampf(world * 0.75 / float(NATURAL.get(lk, 2.0)), 0.45, 1.9)
			var pos := m.global_position
			if lk == "zap":
				pos.y = maxf(pos.y, 0.0)
			if _recent(lk, pos, sc):
				return true   # такой же взрыв только что был рядом — двадцать наложенных дают белое пятно
			var n := VfxLib.spawn(Game.I.fx_root, lk, pos + Vector3(0, 0.05, 0), col, sc)
			if n == null:
				return false
			if "emission" in n:
				n.set("emission", 0.75 if sc < 1.2 else 0.55)
			if kind == "explosion" and Game.I.camera and world > 6.0 and \
					Game.I.camera.focus.distance_to(pos) < 35.0:
				Game.I.camera.shake(clampf(world * 0.02, 0.08, 0.3))
			return true
		"fire":
			# огонь на руке/вокруг героя: живой огонь библиотеки, пока жива модель карты
			var fire := VfxLib.make("fire", col, false)
			if fire == null:
				return false
			var ff := Follow.new()
			ff.fx = fire
			ff.col = col
			ff.no_hit = true
			ff.add_child(fire)
			m.add_child(ff)
			ff.top_level = true
			ff.global_position = m.global_position
			fire.scale = Vector3.ONE * clampf(world / 3.0, 0.4, 1.6)
			return true
		"orb", "javelin", "wave":
			var lk2 := "orb" if kind == "orb" else ("javelin" if kind == "javelin" else "wave")
			var p := VfxLib.make(lk2, col, false)
			if p == null:
				return false
			var f := Follow.new()
			f.fx = p
			f.col = col
			f.hit_scale = clampf(world * 0.35, 0.5, 1.6)
			f.add_child(p)
			m.add_child(f)
			f.top_level = true
			f.global_position = m.global_position
			p.scale = Vector3.ONE * clampf(world / 2.2, 0.7, 1.9)
			VfxLib.start(p)
			return true
	return false


## Манекен триггеров с моделью без класса быстро летит — это снаряд способности: заменяем его готовым снарядом.
static func make_projectile(m: W3Model) -> void:
	if not active() or not is_instance_valid(m) or m.vfx_hidden or VfxLib.busy():
		return
	var v: Dictionary = m.info.get("vfx", {})
	if str(v.get("kind", "")) != "unknown":
		return
	var cv: Array = v.get("col", [1.0, 0.9, 0.7])
	var col := Color(float(cv[0]), float(cv[1]), float(cv[2]))
	var world := maxf(0.3, float(v.get("size", 2.0)) * absf(m.global_transform.basis.get_scale().x))
	var p := VfxLib.make("wave" if world > 7.0 else "orb", col, false)
	if p == null:
		return
	var f := Follow.new()
	f.fx = p
	f.col = col
	f.hit_scale = clampf(world * 0.3, 0.5, 1.6)
	f.add_child(p)
	m.add_child(f)
	f.top_level = true
	f.global_position = m.global_position
	p.scale = Vector3.ONE * clampf(world / 2.6, 0.7, 2.0)
	VfxLib.start(p)
	m.vfx_hidden = true
	for c in m.get_children():
		if c is GeometryInstance3D or c == m.scene_root:
			(c as Node3D).visible = false
	for e in m.emitters:
		e.off = true


static var _bursts: Array = []   # [время, вид, позиция, радиус]


static func _recent(kind: String, pos: Vector3, sc: float) -> bool:
	var now: float = Game.I.time if Game.I else Time.get_ticks_msec() / 1000.0
	var keep: Array = []
	var hit := false
	for b in _bursts:
		if now - float(b[0]) > 0.35:
			continue
		keep.append(b)
		if b[1] == kind and (b[2] as Vector3).distance_to(pos) < float(b[3]):
			hit = true
	if not hit:
		keep.append([now, kind, pos, 1.6 * sc + 0.5])
	_bursts = keep
	return hit


static func _pick(kind: String, key: String, world: float) -> String:
	match kind:
		"hit":
			return "hit" if world < 2.5 else "impact"
		"impact":
			return "impact" if world < 4.0 else "big_impact"
		"zap":
			return "zap"
	var fiery := false
	for w in FIERY:
		if key.contains(w):
			fiery = true
			break
	if fiery:
		if world > 14.0:
			return "nuke"
		return "explosion" if world > 3.0 else "impact2"
	if world < 3.0:
		return "impact"
	return "big_impact" if world < 8.0 else "big_impact2"


static func _augment(key: String) -> bool:
	for w in AUGMENT:
		if key.contains(w):
			return true
	return false


## Модель, которая играет по кругу (аура, висящий над землёй сгусток), не прячем: разовый эффект её не заменит.
static func _loops(m: W3Model) -> bool:
	var anims: Dictionary = m.info.get("anims", {})
	for n in anims:
		var a: Array = anims[n]
		if bool(a[1]) and float(a[0]) > 0.05 and not String(n).to_lower().begins_with("death"):
			return true
	return false


## Снаряд библиотеки, который летит вместе с моделью карты (снаряд способности, манекен-снаряд триггеров),
## смотрит по направлению полёта и при исчезновении даёт вспышку попадания.
class Follow:
	extends Node3D
	var fx: Node3D
	var col := Color.WHITE
	var hit_scale := 1.0
	var prev := Vector3.INF
	var moved := 0.0
	var done := false
	var no_hit := false

	func _process(_d: float) -> void:
		var par := get_parent() as Node3D
		if par == null:
			return
		var p := par.global_position
		if no_hit:
			global_position = p
			if fx:
				fx.visible = par.is_visible_in_tree()
			return
		if prev != Vector3.INF:
			var dv := p - prev
			dv.y = 0.0
			if dv.length() > 0.002:
				moved += dv.length()
				global_rotation = Vector3(0.0, atan2(-dv.z, dv.x), 0.0)
		prev = p
		global_position = p
		var vis := par.is_visible_in_tree()
		if fx:
			fx.visible = vis

	func _exit_tree() -> void:
		# снаряд долетел (манекен удалён) — вспышка попадания
		if done or no_hit:
			return
		done = true
		if moved > 1.5 and prev != Vector3.INF and W3Vfx.active() and fx and fx.visible and \
				Game.I.state == "playing" and Game.I.fx_root.is_inside_tree():
			# родитель сейчас может быть занят удалением детей — вспышку добавляем на следующем кадре
			var root: Node = Game.I.fx_root
			var at := prev
			var c := col
			var hs := hit_scale
			(func() -> void:
				if is_instance_valid(root) and root.is_inside_tree():
					VfxLib.spawn(root, "hit", at, c, hs)).call_deferred()

class_name VfxLib
## Готовые эффекты Binbun (CC0, binbun3d.itch.io): взрывы, удары, вспышки, молнии, огонь, магические снаряды.
## Лежат в res://assets/BinbunVFX*; здесь — запуск по имени, перекраска под способность и удаление после проигрыша.

const V2 := "res://assets/BinbunVFX_Vol2/"
const MP := "res://assets/BinbunVFX/magic_projectiles/effects/"
const KINDS := {
	"hit": V2 + "StylizedHitFX/effects/hit/vfx_hit_01.tscn",
	"hit2": V2 + "StylizedHitFX/effects/hit/vfx_hit_02.tscn",
	"impact": V2 + "StylizedHitFX/effects/impact/vfx_impact_01.tscn",
	"impact2": V2 + "StylizedHitFX/effects/impact/vfx_impact_02.tscn",
	"big_impact": V2 + "StylizedHitFX/effects/big_impact/vfx_big_impact_01.tscn",
	"big_impact2": V2 + "StylizedHitFX/effects/big_impact/vfx_big_impact_02.tscn",
	"explosion": V2 + "ExplosionFX/effects/ground/vfx_ground_explosion_01.tscn",
	"air_explosion": V2 + "ExplosionFX/effects/air/vfx_air_explosion_01.tscn",
	"nuke": V2 + "ExplosionFX/effects/nuke/vfx_nuke_explosion_01.tscn",
	"zap": V2 + "ElectricFX/effects/zap/vfx_zap_lightning_01.tscn",
	"ball_lightning": V2 + "ElectricFX/effects/ball/vfx_ball_lightning_01.tscn",
	"fire": V2 + "FlameFX/effects/fire/vfx_basic_fire_01.tscn",
	"orb": MP + "mprojectile_basic/mprojectile_basic_vfx_01.tscn",
	"orb2": MP + "mprojectile_basic/mprojectile_basic_vfx_02.tscn",
	"orb3": MP + "mprojectile_basic/mprojectile_basic_vfx_03.tscn",
	"orb4": MP + "mprojectile_basic/mprojectile_basic_vfx_04.tscn",
	"javelin": MP + "mprojectile_javelin/mprojectile_javelin_vfx_01.tscn",
	"javelin2": MP + "mprojectile_javelin/mprojectile_javelin_vfx_02.tscn",
	"javelin3": MP + "mprojectile_javelin/mprojectile_javelin_vfx_03.tscn",
	"javelin4": MP + "mprojectile_javelin/mprojectile_javelin_vfx_04.tscn",
	"wave": MP + "mprojectile_wave/mprojectile_wave_vfx_01.tscn",
	"wave2": MP + "mprojectile_wave/mprojectile_wave_vfx_02.tscn",
	"wave3": MP + "mprojectile_wave/mprojectile_wave_vfx_03.tscn",
	"wave4": MP + "mprojectile_wave/mprojectile_wave_vfx_04.tscn",
}
## Сколько живёт разовый эффект, если сам не сообщил об окончании.
const LIFE := {"hit": 1.6, "hit2": 1.6, "impact": 2.0, "impact2": 2.0, "big_impact": 2.6, "big_impact2": 2.6,
	"explosion": 3.2, "air_explosion": 3.2, "nuke": 5.0, "zap": 2.0}
## Ограничение одновременных эффектов (на слабых компьютерах сотни частиц тормозят): зависит от качества графики.
const MAX_LIVE := 60
static var max_live := 32
## Свет внутри эффектов (вспышка освещает землю) — только на высоком качестве: каждый источник света дорог
static var lights := false

static var _cache := {}
static var _live := 0
static var disabled := OS.get_environment("ATS_NOVFX") != ""


## На экране уже много эффектов — новые не запускаем (остаётся графика карты).
static func busy() -> bool:
	return _live >= max_live


static func has(kind: String) -> bool:
	return KINDS.has(kind)


static func scene(kind: String) -> PackedScene:
	if not KINDS.has(kind):
		return null
	if not _cache.has(kind):
		var path: String = KINDS[kind]
		_cache[kind] = load(path) if ResourceLoader.exists(path) else null
	return _cache[kind]


## Разовый эффект в точке. color.a < 0 — оставить родные цвета. dir — куда смотрит (для снарядов и волн).
static func spawn(parent: Node, kind: String, pos: Vector3, color := Color(1, 1, 1, -1), scale := 1.0,
		dir := Vector3.ZERO, life := -1.0) -> Node3D:
	if disabled or parent == null or _live >= max_live or not parent.is_inside_tree():
		return null
	# далеко от камеры — не запускаем: частицы считает видеокарта, даже когда их никто не видит
	var dx := pos.x - W3Model.cam_pos.x
	var dz := pos.z - W3Model.cam_pos.z
	if dx * dx + dz * dz > W3Model.cam_r2:
		return null
	var n := make(kind, color)
	if n == null:
		return null
	parent.add_child(n)
	if not n.is_inside_tree():
		n.free()
		return null
	n.global_position = pos
	_orient(n, dir)
	n.scale = Vector3.ONE * scale
	start(n)
	var t := life if life > 0.0 else float(LIFE.get(kind, 3.0))
	n.get_tree().create_timer(t, false).timeout.connect(func() -> void:
		if is_instance_valid(n):
			n.queue_free())
	return n


## Экземпляр эффекта без запуска таймера удаления (снаряды, ауры — за ними следит вызывающий).
static func make(kind: String, color := Color(1, 1, 1, -1), one_shot := true) -> Node3D:
	var ps := scene(kind)
	if ps == null:
		return null
	var n: Node3D = ps.instantiate()
	_live += 1
	n.tree_exited.connect(func() -> void: _live = maxi(0, _live - 1), CONNECT_ONE_SHOT)
	_unique_materials(n)
	if not lights:
		for l in n.find_children("*", "Light3D", true, false):
			(l as Light3D).visible = false
	for a in n.find_children("*", "AudioStreamPlayer3D", true, false):
		(a as AudioStreamPlayer3D).stream = null
	if one_shot and "one_shot" in n:
		n.set("one_shot", true)
	if color.a >= 0.0:
		colorize(n, color)
	return n


## Запуск, если сцена не запускается сама (у ударов autoplay выключен).
static func start(n: Node) -> void:
	if n.has_method("play") and not bool(n.get("autoplay")):
		n.call("play")


static func colorize(n: Node, c: Color) -> void:
	var main := Color(c.r, c.g, c.b, 1.0)
	var deep := Color.from_hsv(fposmod(main.h + 0.03, 1.0), minf(1.0, main.s * 1.1 + 0.1), main.v * 0.55)
	var hot := main.lerp(Color.WHITE, 0.55)
	for p in [["primary_color", main], ["secondary_color", deep], ["tertiary_color", hot], ["light_color", main]]:
		if p[0] in n:
			n.set(p[0], p[1])


static func _orient(n: Node3D, dir: Vector3) -> void:
	var d := Vector3(dir.x, 0.0, dir.z)
	if d.length() > 0.01:
		n.global_rotation = Vector3(0.0, atan2(d.x, d.z), 0.0)


## У каждого экземпляра свои материалы: иначе перекраска одного меняет все такие же эффекты на экране.
static func _unique_materials(root: Node) -> void:
	for c in root.find_children("*", "GeometryInstance3D", true, false):
		var g := c as GeometryInstance3D
		if g.material_override:
			g.material_override = g.material_override.duplicate()
	var empty: Array[ShaderMaterial] = []
	if "materials" in root:
		root.set("materials", empty)

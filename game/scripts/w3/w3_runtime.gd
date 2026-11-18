class_name W3Runtime
extends W3Consts
## Среда исполнения триггеров Warcraft 3: нативные функции common.j поверх мира игры.
## Код карты (w3_map.gd, переведён из JASS) наследует этот класс и вызывает функции напрямую.
## Координаты JASS — единицы WC3: x -> x игры, y -> -z игры, масштаб U.

const U := 1.0 / 48.0             # 1 единица WC3 -> единицы игры
const DMG_K := 0.75               # урон из формул карты -> баланс игры
const FX_K := 2.08                # масштаб моделей эффектов на земле (U / 0.01)

static var I: W3Runtime = null

var data: Dictionary = {}         # w3_data.json
var _ev: Dictionary = {}          # контекст события текущего «потока»
var _enum_unit = null
var _filter_unit = null
var _enum_player = null
var _enum_item = null
var _enum_dest = null
var players: Array = []
var _unit_events: Dictionary = {}     # событие -> [JTrig]
var _unit_specific: Dictionary = {}   # событие -> [[unit, JTrig]]
var _periodic: Array = []             # [[JTrig, period, acc, periodic]]
var _timers: Array = []
var _in_range: Array = []             # [[JTrig, unit, range, inside{}]]
var _hash: Dictionary = {}
var _order_ids := {"smart": 851971, "stop": 851972, "attack": 851983, "move": 851986, "patrol": 851990,
	"holdposition": 851993}
var _order_names := {}
var _warned := {}
var _sound_cache := {}
var _id_seq := 0
var fx_parent: Node3D = null
var local_player = null


class JPlayer:
	extends RefCounted
	var id := 0
	var team := -1
	var hero = null
	var avail := {}


class JGroup:
	extends RefCounted
	var units: Array = []


class JForce:
	extends RefCounted
	var players: Array = []


class JTrig:
	extends RefCounted
	var enabled := true
	var conds: Array = []
	var actions: Array = []
	var execs := 0
	var name := ""


class JTimer:
	extends RefCounted
	var left := 0.0
	var timeout := 0.0
	var periodic := false
	var cb = null
	var running := false
	var elapsed := 0.0


class JRect:
	extends RefCounted
	var x0 := 0.0
	var y0 := 0.0
	var x1 := 0.0
	var y1 := 0.0


class JSound:
	extends RefCounted
	var path := ""
	var vol := 127
	var unit = null
	var player: AudioStreamPlayer = null


class JItem:
	extends RefCounted
	var type_id := 0
	var x := 0.0
	var y := 0.0
	var visible := true


class JHandle:
	extends RefCounted
	var kind := ""


# ------------------------------------------------------------------ запуск
func _init() -> void:
	I = self
	for k in _order_ids:
		_order_names[_order_ids[k]] = k
	for i in 16:
		var p := JPlayer.new()
		p.id = i
		players.append(p)


var stats := {}


func _exit_tree() -> void:
	if Game.I and Game.I.sim:
		print("[W3] заклинания: ", stats)
	if I == self:
		I = null
		W3Model.clear_cache()


func setup(game: Node) -> void:
	var f := FileAccess.open("res://w3/w3_data.json", FileAccess.READ)
	if f:
		var d = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			data = d
	# боссы, Белый Зецу и Мадара из карты NCD: их способности и юниты (ключи Zxxx / Yxxx)
	var fn := FileAccess.open("res://w3/ncd_data.json", FileAccess.READ)
	if fn and not data.is_empty():
		var n = JSON.parse_string(fn.get_as_text())
		if n is Dictionary:
			(data.abilities as Dictionary).merge(n.get("abilities", {}))
			(data.units as Dictionary).merge(n.get("units", {}))
			data["ncd"] = n
	fx_parent = game.fx_root
	var mon := players[12] as JPlayer
	mon.team = Data.MONSTER_TEAM
	call("_init_globals")
	call("_init_map")
	call("_init_triggers")


## Герой получает игрока WC3 (по порядку в игре: 0..8).
func bind_hero(h: Hero, idx: int) -> void:
	var p: JPlayer = players[idx]
	p.team = h.team
	p.hero = h
	_d(h).player = p
	if h.is_player:
		local_player = p


func _process_order_name(id: int) -> String:
	return _order_names.get(id, "")


# ------------------------------------------------------------------ служебное
func _isnull(v) -> bool:
	if typeof(v) == TYPE_OBJECT:
		return not is_instance_valid(v)
	return v == null


func _idiv(a: int, b: int) -> int:
	if b == 0:
		return 0
	return a / b


## Сравнение вещественных как в JASS: с допуском (сумма шагов 0.1 должна давать ровно 1.1).
func _feq(a: float, b: float) -> bool:
	return absf(a - b) <= 0.001


func _warn(n: String) -> void:
	if not _warned.has(n):
		_warned[n] = true
		print("[W3] нет реализации: ", n)


## Данные WC3 для любого юнита игры (способности, баффы, пауза...).
func _d(u) -> Dictionary:
	if typeof(u) != TYPE_OBJECT or not is_instance_valid(u):
		return {}
	if not u.has_meta("w3"):
		u.set_meta("w3", {"abils": {}, "buffs": {}, "paused": false, "user": 0, "type": 0, "player": null,
			"timed": -1.0, "fly": 0.0, "scale": 1.0})
	return u.get_meta("w3")


func _u(u) -> Unit:
	if typeof(u) != TYPE_OBJECT or not is_instance_valid(u):
		return null
	return u as Unit


static func alive_obj(x) -> bool:
	return typeof(x) == TYPE_OBJECT and is_instance_valid(x)


func pos_of(x: float, y: float) -> Vector3:
	var gx := x * U
	var gz := -y * U
	return Vector3(gx, ground_y(gx, gz), gz)


func ground_y(gx: float, gz: float) -> float:
	var g := Game.I
	if g == null:
		return 0.0
	for z in g.zones:
		var nv: NavArea = g.nav_of(z.index)
		if nv and gx >= nv.x0 - 2.0 and gz >= nv.z0 - 2.0 and gx <= nv.x0 + nv.w + 2.0 and gz <= nv.z0 + nv.h + 2.0:
			return nv._y(gx, gz)
	var an: NavArea = g.nav_of(-1)
	if an:
		return an._y(gx, gz)
	return 0.0


func wx(u: Node3D) -> float:
	return u.global_position.x / U


func wy(u: Node3D) -> float:
	return -u.global_position.z / U


func facing_of(u: Node3D) -> float:
	return fposmod(rad_to_deg(u.rotation.y) - 90.0, 360.0)


func set_facing(u: Node3D, deg: float) -> void:
	var yaw := deg_to_rad(deg + 90.0)
	u.rotation.y = yaw
	if u is Unit:
		(u as Unit).yaw_target = yaw


func player_of(u):
	var uu := _u(u)
	if uu == null:
		return players[15]
	var d := _d(uu)
	if d.get("player") != null:
		return d.player
	if uu.team == Data.MONSTER_TEAM:
		return players[12]
	for p in players:
		if (p as JPlayer).team == uu.team and p.hero != null:
			return p
	return players[12]


func team_of(u) -> int:
	var uu := _u(u)
	return uu.team if uu else -99


## Кому засчитывать урон/убийство: хозяину манекена.
func credit_of(u) -> Unit:
	var uu := _u(u)
	if uu == null:
		return null
	if uu is W3Unit and (uu as W3Unit).owner_unit and is_instance_valid((uu as W3Unit).owner_unit):
		return (uu as W3Unit).owner_unit
	var p = player_of(uu)
	if (uu is W3Unit) and p and p.hero and is_instance_valid(p.hero):
		return p.hero
	return uu


func all_units() -> Array:
	var out: Array = []
	if Game.I:
		for u in Game.I.units:
			if is_instance_valid(u):
				out.append(u)
	return out


func unit_type_id(u) -> int:
	var uu := _u(u)
	if uu == null:
		return 0
	var d := _d(uu)
	if int(d.get("type", 0)) != 0:
		return int(d.type)
	if uu is W3Unit:
		return (uu as W3Unit).type_id
	if uu is Hero:
		var mu: String = (uu as Hero).def.get("map_unit", "")
		if mu != "":
			return fcc(mu)
	return 0


static func fcc(s: String) -> int:
	var v := 0
	for i in s.length():
		v = v * 256 + s.unicode_at(i)
	return v


static func fcc_str(v: int) -> String:
	return "%c%c%c%c" % [(v >> 24) & 255, (v >> 16) & 255, (v >> 8) & 255, v & 255]


# ------------------------------------------------------------------ события
func _ctx(extra: Dictionary) -> Dictionary:
	return extra


func fire(event, ctx: Dictionary, unit = null) -> void:
	var lst: Array = _unit_events.get(event, [])
	var spec: Array = _unit_specific.get(event, [])
	if lst.is_empty() and spec.is_empty():
		return
	var run: Array = lst.duplicate()
	if unit != null:
		for pair in spec:
			if pair[0] == unit:
				run.append(pair[1])
	var saved := _ev
	for t in run:
		var tr: JTrig = t
		if not tr.enabled:
			continue
		_ev = ctx.duplicate()
		_ev["trigger"] = tr
		_ev["event"] = event
		if _eval_conds(tr):
			_run_actions(tr)
	_ev = saved


func _eval_conds(tr: JTrig) -> bool:
	for c in tr.conds:
		if c is Callable and (c as Callable).is_valid():
			if not bool((c as Callable).call()):
				return false
	return true


var _trace := OS.get_environment("W3_TRACE") != ""


func _run_actions(tr: JTrig) -> void:
	tr.execs += 1
	if _trace and tr.execs <= 2 and not tr.actions.is_empty():
		print("[T %.2f] %s" % [Game.I.time if Game.I else 0.0, str((tr.actions[0] as Callable).get_method())])
	for a in tr.actions:
		if a is Callable and (a as Callable).is_valid():
			(a as Callable).call()


func on_unit_death(dead: Unit, killer: Unit) -> void:
	var ctx := {"unit": dead, "dying": dead, "killer": credit_of(killer) if killer else null}
	fire(EVENT_PLAYER_UNIT_DEATH, ctx)
	fire(EVENT_UNIT_DEATH, ctx, dead)


func on_attacked(attacker: Unit, target: Unit) -> void:
	var ctx := {"unit": target, "attacker": attacker}
	fire(EVENT_PLAYER_UNIT_ATTACKED, ctx)
	fire(EVENT_UNIT_ATTACKED, ctx, target)


func on_order(u: Unit, order: String, target_unit: Unit, p: Variant) -> void:
	var oid: int = _order_ids.get(order, 0)
	var ctx := {"unit": u, "order": oid, "order_unit": target_unit}
	if p is Vector3:
		ctx["order_x"] = (p as Vector3).x / U
		ctx["order_y"] = -(p as Vector3).z / U
	if target_unit:
		fire(EVENT_PLAYER_UNIT_ISSUED_TARGET_ORDER, ctx)
		fire(EVENT_UNIT_ISSUED_TARGET_ORDER, ctx, u)
	elif p is Vector3:
		fire(EVENT_PLAYER_UNIT_ISSUED_POINT_ORDER, ctx)
		fire(EVENT_UNIT_ISSUED_POINT_ORDER, ctx, u)
	else:
		fire(EVENT_PLAYER_UNIT_ISSUED_ORDER, ctx)
		fire(EVENT_UNIT_ISSUED_ORDER, ctx, u)


func fire_spell(stage, caster: Unit, abil: int, target_unit: Unit, tx: float, ty: float, has_point: bool) -> void:
	var ctx := {"unit": caster, "spell": abil, "spell_unit": target_unit, "spell_x": tx, "spell_y": ty,
		"spell_point": has_point}
	if stage == EVENT_PLAYER_UNIT_SPELL_EFFECT:
		var k := fcc_str(abil)
		stats[k] = int(stats.get(k, 0)) + 1
	fire(stage, ctx)
	match stage:
		EVENT_PLAYER_UNIT_SPELL_CHANNEL:
			fire(EVENT_UNIT_SPELL_CHANNEL, ctx, caster)
		EVENT_PLAYER_UNIT_SPELL_EFFECT:
			fire(EVENT_UNIT_SPELL_EFFECT, ctx, caster)
		EVENT_PLAYER_UNIT_SPELL_CAST:
			fire(EVENT_UNIT_SPELL_CAST, ctx, caster)


func fire_learn(h: Unit, abil: int) -> void:
	fire(EVENT_PLAYER_HERO_SKILL, {"unit": h, "learned": abil})


# ------------------------------------------------------------------ такт
func _physics_process(delta: float) -> void:
	if Game.I == null or Game.I.state != "playing":
		return
	for e in _periodic.duplicate():
		var tr: JTrig = e[0]
		if not tr.enabled:
			e[2] = 0.0
			continue
		e[2] += delta
		var guard := 0
		while e[2] >= e[1] and guard < 3:
			e[2] -= e[1]
			guard += 1
			var saved := _ev
			_ev = {"trigger": tr}
			if _eval_conds(tr):
				_run_actions(tr)
			_ev = saved
			if not e[3]:
				_periodic.erase(e)
				break
		if guard >= 3:
			e[2] = 0.0
	for t in _timers.duplicate():
		var tm: JTimer = t
		if not tm.running:
			continue
		tm.left -= delta
		tm.elapsed += delta
		if tm.left <= 0.0:
			if tm.periodic:
				tm.left += maxf(tm.timeout, 0.01)
				tm.elapsed = 0.0
			else:
				tm.running = false
				_timers.erase(tm)
			if tm.cb is Callable and (tm.cb as Callable).is_valid():
				var saved2 := _ev
				_ev = {"timer": tm}
				(tm.cb as Callable).call()
				_ev = saved2
	for e in _in_range:
		var tr2: JTrig = e[0]
		var c := _u(e[1])
		if c == null or not tr2.enabled:
			continue
		var r: float = e[2] * U
		var inside: Dictionary = e[3]
		for u in all_units():
			if u == c:
				continue
			# как в WC3: до края юнита (с учётом его размера)
			var near: bool = (u as Unit).flat_dist(c) <= r + (u as Unit).radius
			var id := (u as Object).get_instance_id()
			if near and not inside.has(id):
				inside[id] = true
				var saved3 := _ev
				_ev = {"trigger": tr2, "unit": u}
				if _eval_conds(tr2):
					_run_actions(tr2)
				_ev = saved3
			elif not near and inside.has(id):
				inside.erase(id)
	# баффы и таймеры жизни
	for u in get_tree().get_nodes_in_group("w3_tracked"):
		var d := _d(u)
		var bf: Dictionary = d.get("buffs", {})
		for b in bf.keys():
			bf[b] -= delta
			if bf[b] <= 0.0:
				bf.erase(b)


# ================================================================== НАТИВНЫЕ ФУНКЦИИ
# ---- математика и преобразования
func Sin(a: float) -> float:
	return sin(a)


func Cos(a: float) -> float:
	return cos(a)


func Atan2(y: float, x: float) -> float:
	return atan2(y, x)


func SquareRoot(x: float) -> float:
	return sqrt(maxf(x, 0.0))


func Pow(x: float, p: float) -> float:
	return pow(x, p)


func I2R(i) -> float:
	return float(i)


func R2I(r) -> int:
	return int(r)


func I2S(i) -> String:
	return str(int(i))


func R2S(r) -> String:
	return "%.3f" % float(r)


func GetRandomInt(a: int, b: int) -> int:
	if b < a:
		var t := a
		a = b
		b = t
	return randi_range(a, b)


func GetRandomReal(a: float, b: float) -> float:
	return randf_range(minf(a, b), maxf(a, b))


func StringHash(s: String) -> int:
	return s.hash()


func GetHandleId(h) -> int:
	if alive_obj(h) and h is Object:
		return (h as Object).get_instance_id() & 0x7fffffff
	if h is Vector2:
		return int(hash(h)) & 0x7fffffff
	return 0


func OrderId(s: String) -> int:
	s = s.to_lower()
	if not _order_ids.has(s):
		_order_ids[s] = 852000 + _order_ids.size()
		_order_names[_order_ids[s]] = s
	return _order_ids[s]


func UnitId(s: String) -> int:
	return 0


func Player(i: int):
	return players[clampi(i, 0, 15)]


func GetPlayerId(p) -> int:
	return p.id if p is JPlayer else 0


func GetLocalPlayer():
	return local_player if local_player else players[0]


func GetFloatGameState(_s) -> float:
	return 12.0


# ---- точки и прямоугольники
func Location(x: float, y: float):
	return Vector2(x, y)


func RemoveLocation(_l) -> void:
	pass


func GetLocationX(l) -> float:
	return (l as Vector2).x if l is Vector2 else 0.0


func GetLocationY(l) -> float:
	return (l as Vector2).y if l is Vector2 else 0.0


func GetLocationZ(l) -> float:
	if l is Vector2:
		return ground_y((l as Vector2).x * U, -(l as Vector2).y * U) / U
	return 0.0


func LoadLocationHandle(h, a: int, b: int):
	return (_hash.get(h, {}) as Dictionary).get([a, b], null) if h != null else null


func Rect(x0: float, y0: float, x1: float, y1: float):
	var r := JRect.new()
	r.x0 = x0
	r.y0 = y0
	r.x1 = x1
	r.y1 = y1
	return r


func _rect(r) -> JRect:
	if r is JRect:
		return r
	return Rect(-1e7, -1e7, 1e7, 1e7)


func RemoveRect(_r) -> void:
	pass


func SetRect(r, x0: float, y0: float, x1: float, y1: float) -> void:
	if r is JRect:
		r.x0 = x0
		r.y0 = y0
		r.x1 = x1
		r.y1 = y1


func MoveRectTo(r, x: float, y: float) -> void:
	if r is JRect:
		var hw: float = (r.x1 - r.x0) * 0.5
		var hh: float = (r.y1 - r.y0) * 0.5
		SetRect(r, x - hw, y - hh, x + hw, y + hh)


func MoveRectToLoc(r, l) -> void:
	MoveRectTo(r, GetLocationX(l), GetLocationY(l))


func GetRectCenterX(r) -> float:
	var rr := _rect(r)
	return (rr.x0 + rr.x1) * 0.5 if r is JRect else 0.0


func GetRectCenterY(r) -> float:
	var rr := _rect(r)
	return (rr.y0 + rr.y1) * 0.5 if r is JRect else 0.0


func GetRectMinX(r) -> float:
	return _rect(r).x0


func GetRectMinY(r) -> float:
	return _rect(r).y0


func GetRectMaxX(r) -> float:
	return _rect(r).x1


func GetRectMaxY(r) -> float:
	return _rect(r).y1


func GetWorldBounds():
	return Rect(-1e5, -1e5, 1e5, 1e5)


func IsLocationInRegion(_reg, _l) -> bool:
	return false


func IsTerrainPathable(x: float, y: float, _t) -> bool:
	# true = НЕ проходимо (как в WC3)
	var p := pos_of(x, y)
	if Game.I == null:
		return false
	for z in Game.I.zones:
		var nv: NavArea = Game.I.nav_of(z.index)
		if nv and nv.walkable(p):
			return false
	var an: NavArea = Game.I.nav_of(-1)
	if an and an.walkable(p):
		return false
	return true


func GetTerrainType(_x: float, _y: float) -> int:
	return 0


func SetTerrainType(_x: float, _y: float, _t: int, _v: int, _a: int, _s: int) -> void:
	pass


# ---- триггеры
func CreateTrigger():
	return JTrig.new()


func DestroyTrigger(t) -> void:
	if t is JTrig:
		t.enabled = false
		t.actions.clear()
		t.conds.clear()


func EnableTrigger(t) -> void:
	if t is JTrig:
		t.enabled = true


func DisableTrigger(t) -> void:
	if t is JTrig:
		t.enabled = false


func IsTriggerEnabled(t) -> bool:
	return t is JTrig and t.enabled


func TriggerAddAction(t, f):
	if t is JTrig and f is Callable:
		t.actions.append(f)
	return null


func TriggerAddCondition(t, c):
	if t is JTrig and c is Callable:
		t.conds.append(c)
	return null


func Condition(f):
	return f


func Filter(f):
	return f


func DestroyBoolExpr(_b) -> void:
	pass


func TriggerEvaluate(t) -> bool:
	if not (t is JTrig):
		return false
	return _eval_conds(t)


func TriggerExecute(t) -> void:
	if t is JTrig:
		var saved := _ev
		_ev = _ev.duplicate()
		_ev["trigger"] = t
		_run_actions(t)
		_ev = saved


func GetTriggeringTrigger():
	return _ev.get("trigger")


func ExecuteFunc(name: String) -> void:
	var m := "f_" + name
	if has_method(m):
		call(m)
	elif name == "ProjectileLaunchKill_Child":
		_projectile_kill_child()


## Снаряд системы кастеров карты (Vexorian) — её функции не переведены: без этого кастер с эффектом
## оставался висеть на месте навсегда (у Синон за бой копились сотни таких). Летит к точке и пропадает.
func _projectile_kill_child() -> void:
	var u = get("udg_currentcaster")
	var fx = get("bj_lastCreatedEffect")
	var cv = get("udg_castervars")
	if not (u is Unit) or not (cv is Dictionary):
		if fx != null:
			DestroyEffect(fx)
		return
	var x2 := float(cv.get(0, GetUnitX(u)))
	var y2 := float(cv.get(1, GetUnitY(u)))
	var spd := maxf(float(cv.get(3, 900.0)), 300.0)
	var wu: WeakRef = weakref(u)
	var t := Timer.new()
	t.wait_time = 0.03
	t.process_callback = Timer.TIMER_PROCESS_PHYSICS
	add_child(t)
	var life := [0.0]
	t.timeout.connect(func() -> void:
		var uu = wu.get_ref()
		life[0] += 0.03
		var done: bool = uu == null or not is_instance_valid(uu) or float(life[0]) > 6.0
		if not done:
			var x := GetUnitX(uu)
			var y := GetUnitY(uu)
			var dx := x2 - x
			var dy := y2 - y
			var d := sqrt(dx * dx + dy * dy)
			var step := spd * 0.03
			if d <= step:
				done = true
			else:
				SetUnitX(uu, x + dx / d * step)
				SetUnitY(uu, y + dy / d * step)
		if done:
			if fx != null:
				DestroyEffect(fx)
			if uu != null and is_instance_valid(uu):
				RemoveUnit(uu)
			t.queue_free())
	t.start()


func TriggerSleepAction(t: float) -> void:
	await get_tree().create_timer(maxf(t, 0.05), false, true).timeout


func PolledWait(t: float) -> void:
	if t > 0.0:
		await get_tree().create_timer(t, false, true).timeout


func TriggerRegisterPlayerUnitEvent(t, _p, ev, _f):
	if not (t is JTrig):
		return null
	var lst: Array = _unit_events.get(ev, [])
	if not lst.has(t):
		lst.append(t)
	_unit_events[ev] = lst
	return null


func TriggerRegisterUnitEvent(t, u, ev):
	if t is JTrig and _u(u):
		var lst: Array = _unit_specific.get(ev, [])
		lst.append([u, t])
		_unit_specific[ev] = lst
	return null


func TriggerRegisterTimerEvent(t, timeout: float, periodic: bool):
	if t is JTrig:
		_periodic.append([t, maxf(timeout, 0.01), 0.0, periodic])
	return null


func TriggerRegisterUnitInRange(t, u, r: float, _f):
	if t is JTrig and _u(u):
		_in_range.append([t, u, r, {}])
	return null


func TriggerRegisterPlayerChatEvent(_t, _p, _s, _e):
	return null


# ---- ответы на события
func GetTriggerUnit():
	return _ev.get("unit")


func GetSpellAbilityUnit():
	return _ev.get("unit")


func GetSpellAbilityId() -> int:
	return int(_ev.get("spell", 0))


func GetSpellTargetUnit():
	return _ev.get("spell_unit")


func GetSpellTargetLoc():
	if _ev.get("spell_point", false):
		return Vector2(float(_ev.spell_x), float(_ev.spell_y))
	var su := _u(_ev.get("spell_unit"))
	if su:
		return Vector2(wx(su), wy(su))
	return null


func GetDyingUnit():
	return _ev.get("dying")


func GetKillingUnit():
	return _ev.get("killer")


func GetAttacker():
	return _ev.get("attacker")


func GetLearnedSkill() -> int:
	return int(_ev.get("learned", 0))


func GetTriggerPlayer():
	var u = _ev.get("unit")
	return player_of(u) if u else players[0]


func GetEventPlayerChatString() -> String:
	return ""


func GetIssuedOrderId() -> int:
	return int(_ev.get("order", 0))


func GetOrderPointLoc():
	if _ev.has("order_x"):
		return Vector2(float(_ev.order_x), float(_ev.order_y))
	return null


func GetOrderTargetUnit():
	return _ev.get("order_unit")


func GetEnumUnit():
	return _enum_unit


func GetFilterUnit():
	return _filter_unit


func GetEnumPlayer():
	return _enum_player


func GetEnumItem():
	return _enum_item


func GetEnumDestructable():
	return _enum_dest


func GetFilterDestructable():
	return _enum_dest


# ---- таймеры
func CreateTimer():
	return JTimer.new()


func DestroyTimer(t) -> void:
	if t is JTimer:
		t.running = false
		_timers.erase(t)


func TimerStart(t, timeout: float, periodic: bool, cb) -> void:
	if not (t is JTimer):
		return
	t.timeout = timeout
	t.left = maxf(timeout, 0.0)
	t.periodic = periodic
	t.cb = cb
	t.running = true
	t.elapsed = 0.0
	if not _timers.has(t):
		_timers.append(t)


func PauseTimer(t) -> void:
	if t is JTimer:
		t.running = false


func TimerGetRemaining(t) -> float:
	return t.left if t is JTimer else 0.0


func TimerGetElapsed(t) -> float:
	return t.elapsed if t is JTimer else 0.0


# ---- группы и силы
func CreateGroup():
	return JGroup.new()


func DestroyGroup(_g) -> void:
	pass


func GroupClear(g) -> void:
	if g is JGroup:
		g.units.clear()


func GroupAddUnit(g, u) -> void:
	if g is JGroup and _u(u) and not g.units.has(u):
		g.units.append(u)


func GroupRemoveUnit(g, u) -> void:
	if g is JGroup:
		g.units.erase(u)


func IsUnitInGroup(u, g) -> bool:
	return g is JGroup and g.units.has(u)


func _purge(g: JGroup) -> void:
	var k := 0
	while k < g.units.size():
		if not is_instance_valid(g.units[k]):
			g.units.remove_at(k)
		else:
			k += 1


func FirstOfGroup(g):
	if not (g is JGroup):
		return null
	_purge(g)
	return g.units[0] if not g.units.is_empty() else null


func ForGroup(g, cb) -> void:
	if not (g is JGroup) or not (cb is Callable):
		return
	_purge(g)
	var saved = _enum_unit
	for u in (g.units as Array).duplicate():
		if not is_instance_valid(u):
			continue
		_enum_unit = u
		(cb as Callable).call()
	_enum_unit = saved


func _filter_ok(f, u) -> bool:
	if not (f is Callable):
		return true
	var saved = _filter_unit
	_filter_unit = u
	var ok := bool((f as Callable).call())
	_filter_unit = saved
	return ok


func _enum_add(g, u, f) -> void:
	if _filter_ok(f, u):
		GroupAddUnit(g, u)


func GroupEnumUnitsInRange(g, x: float, y: float, r: float, f) -> void:
	if not (g is JGroup):
		return
	g.units.clear()
	var c := Vector2(x * U, -y * U)
	for u in all_units():
		var uu: Unit = u
		if not uu.visible:
			continue
		var d := Vector2(uu.global_position.x, uu.global_position.z).distance_to(c)
		if d <= r * U + uu.radius * 0.5:
			_enum_add(g, uu, f)


func GroupEnumUnitsInRangeOfLoc(g, l, r: float, f) -> void:
	GroupEnumUnitsInRange(g, GetLocationX(l), GetLocationY(l), r, f)


func GroupEnumUnitsInRect(g, rc, f) -> void:
	if not (g is JGroup):
		return
	g.units.clear()
	var rr := _rect(rc)
	for u in all_units():
		var x := wx(u)
		var y := wy(u)
		if x >= rr.x0 and x <= rr.x1 and y >= rr.y0 and y <= rr.y1 and (u as Unit).visible:
			_enum_add(g, u, f)


func GroupEnumUnitsOfPlayer(g, p, f) -> void:
	if not (g is JGroup):
		return
	g.units.clear()
	for u in all_units():
		if player_of(u) == p:
			_enum_add(g, u, f)
	for u in get_tree().get_nodes_in_group("w3_dummy"):
		if is_instance_valid(u) and player_of(u) == p:
			_enum_add(g, u, f)


func IsUnitInRangeXY(u, x: float, y: float, d: float) -> bool:
	var uu := _u(u)
	if uu == null:
		return false
	return Vector2(wx(uu) - x, wy(uu) - y).length() <= d


func CreateForce():
	return JForce.new()


func ForceAddPlayer(f, p) -> void:
	if f is JForce and not f.players.has(p):
		f.players.append(p)


func IsPlayerInForce(p, f) -> bool:
	if f is JForce:
		return f.players.has(p)
	return true


func ForForce(f, cb) -> void:
	if not (cb is Callable):
		return
	var lst: Array = f.players if f is JForce else players.slice(0, 12)
	var saved = _enum_player
	for p in lst:
		_enum_player = p
		(cb as Callable).call()
	_enum_player = saved


# ---- хэш-таблицы и кэш
func InitHashtable():
	return JHandle.new()


func InitGameCache(_s):
	return JHandle.new()


func FlushGameCache(_c) -> void:
	pass


func SaveInteger(h, a: int, b: int, v: int) -> void:
	if h == null:
		return
	var t: Dictionary = _hash.get(h, {})
	t[[a, b]] = v
	_hash[h] = t


func LoadInteger(h, a: int, b: int) -> int:
	return int((_hash.get(h, {}) as Dictionary).get([a, b], 0)) if h != null else 0


func HaveSavedInteger(h, a: int, b: int) -> bool:
	return h != null and (_hash.get(h, {}) as Dictionary).has([a, b])


func RemoveSavedInteger(h, a: int, b: int) -> void:
	if h != null and _hash.has(h):
		(_hash[h] as Dictionary).erase([a, b])


func FlushChildHashtable(h, a: int) -> void:
	if h == null or not _hash.has(h):
		return
	var t: Dictionary = _hash[h]
	for k in t.keys():
		if k[0] == a:
			t.erase(k)


# ---- юниты: создание и удаление
func CreateUnit(p, type_id: int, x: float, y: float, face: float):
	var u := W3Unit.make(self, type_id, p, pos_of(x, y), face)
	return u


func CreateUnitAtLoc(p, type_id: int, l, face: float):
	return CreateUnit(p, type_id, GetLocationX(l), GetLocationY(l), face)


func KillUnit(u) -> void:
	var uu := _u(u)
	if uu == null or not uu.alive:
		return
	if uu is W3Unit:
		(uu as W3Unit).w3_die(null)
	elif Game.I:
		uu.hp = 0.0
		Game.I._on_kill(null, uu)


func RemoveUnit(u) -> void:
	var uu := _u(u)
	if uu == null or uu is Hero:
		return
	if uu is W3Unit:
		(uu as W3Unit).w3_remove()
		return
	if Game.I:
		Game.I.units.erase(uu)
	uu.alive = false
	uu.queue_free()


func UnitApplyTimedLife(u, _buff: int, t: float) -> void:
	var uu := _u(u)
	if uu is W3Unit:
		(uu as W3Unit).timed_life = maxf(t, 0.01)


func UnitPauseTimedLife(u, flag: bool) -> void:
	var uu := _u(u)
	if uu is W3Unit:
		(uu as W3Unit).timed_paused = flag


# ---- юниты: свойства
## Место «пустого» юнита. В WC3 это центр карты (0, 0), где никто не играет; у нас там острова,
## поэтому эффекты триггеров, включённых до появления героя, уводим далеко за край мира.
const NOWHERE := -60000.0


func GetUnitX(u) -> float:
	var uu := _u(u)
	return wx(uu) if uu else NOWHERE


func GetUnitY(u) -> float:
	var uu := _u(u)
	return wy(uu) if uu else NOWHERE


func GetUnitLoc(u):
	var uu := _u(u)
	return Vector2(wx(uu), wy(uu)) if uu else Vector2(NOWHERE, NOWHERE)


func _place(uu: Unit, p: Vector3, clamp_it: bool) -> void:
	if uu is W3Unit:
		(uu as W3Unit).w3_set_pos(p)
		return
	if clamp_it and Game.I and uu.area != -99:
		p = Game.I.clamp_to_area(p, uu.area)
	uu.global_position = Vector3(p.x, p.y, p.z)
	uu.path.clear()


func SetUnitX(u, x: float) -> void:
	var uu := _u(u)
	if uu:
		_place(uu, pos_of(x, wy(uu)), true)


func SetUnitY(u, y: float) -> void:
	var uu := _u(u)
	if uu:
		_place(uu, pos_of(wx(uu), y), true)


func SetUnitPosition(u, x: float, y: float) -> void:
	var uu := _u(u)
	if uu:
		_place(uu, pos_of(x, y), true)


func SetUnitPositionLoc(u, l) -> void:
	SetUnitPosition(u, GetLocationX(l), GetLocationY(l))


func GetUnitFacing(u) -> float:
	var uu := _u(u)
	return facing_of(uu) if uu else 0.0


func SetUnitFacing(u, a: float) -> void:
	var uu := _u(u)
	if uu:
		set_facing(uu, a)


func SetUnitFacingTimed(u, a: float, _t: float) -> void:
	SetUnitFacing(u, a)


func GetUnitFlyHeight(u) -> float:
	return float(_d(u).get("fly", 0.0))


func SetUnitFlyHeight(u, h: float, _rate: float) -> void:
	var uu := _u(u)
	if uu == null:
		return
	_d(uu).fly = h
	if uu is W3Unit:
		(uu as W3Unit).fly_h = h * U
	elif uu.model:
		uu.model_base_pos.y = h * U
		uu.model.position.y = h * U


func GetUnitState(u, s) -> float:
	var uu := _u(u)
	if uu == null:
		return 0.0
	match s:
		UNIT_STATE_LIFE:
			return uu.hp if uu.alive else 0.0
		UNIT_STATE_MAX_LIFE:
			return uu.max_hp
		UNIT_STATE_MANA:
			return uu.mp
		UNIT_STATE_MAX_MANA:
			return uu.max_mp
	return 0.0


func SetUnitState(u, s, v: float) -> void:
	var uu := _u(u)
	if uu == null or not uu.alive:
		return
	match s:
		UNIT_STATE_LIFE:
			if v <= 0.405:
				KillUnit(uu)
			else:
				uu.hp = clampf(v, 1.0, uu.max_hp)
		UNIT_STATE_MANA:
			uu.mp = clampf(v, 0.0, uu.max_mp)


func GetWidgetLife(u) -> float:
	return GetUnitState(u, UNIT_STATE_LIFE)


func GetUnitTypeId(u) -> int:
	return unit_type_id(u)


func GetUnitLevel(u) -> int:
	var uu := _u(u)
	if uu is Hero:
		return (uu as Hero).level
	if uu is W3Unit:
		return (uu as W3Unit).w3_level
	return 1


func GetUnitUserData(u) -> int:
	return int(_d(u).get("user", 0))


func SetUnitUserData(u, v: int) -> void:
	if _u(u):
		_d(u).user = v


func GetUnitMoveSpeed(u) -> float:
	var uu := _u(u)
	return uu.move_speed / U if uu else 0.0


func GetUnitDefaultMoveSpeed(u) -> float:
	var uu := _u(u)
	if uu is W3Unit:
		return (uu as W3Unit).default_speed / U
	return uu.move_speed / U if uu else 0.0


func SetUnitMoveSpeed(u, v: float) -> void:
	var uu := _u(u)
	if uu is W3Unit:
		uu.move_speed = v * U


func GetOwningPlayer(u):
	return player_of(u)


func SetUnitOwner(u, p, _color: bool) -> void:
	var uu := _u(u)
	if uu and p is JPlayer:
		_d(uu).player = p
		if p.team >= -1:
			uu.team = p.team


func SetUnitColor(_u_, _c) -> void:
	pass


func SetUnitAcquireRange(_u_, _r: float) -> void:
	pass


func SetUnitPathing(_u_, _f: bool) -> void:
	pass


func IsUnitEnemy(u, p) -> bool:
	var uu := _u(u)
	if uu == null or not (p is JPlayer):
		return false
	return uu.team != p.team


func IsUnitAlly(u, p) -> bool:
	var uu := _u(u)
	if uu == null or not (p is JPlayer):
		return false
	return uu.team == p.team


func IsUnitType(u, t) -> bool:
	var uu := _u(u)
	if uu == null:
		return false
	match t:
		UNIT_TYPE_HERO:
			return uu is Hero or (uu is W3Unit and (uu as W3Unit).is_hero_type)
		UNIT_TYPE_STRUCTURE:
			return uu.kind == Unit.Kind.CRYSTAL
		UNIT_TYPE_DEAD:
			return not uu.alive
		UNIT_TYPE_GROUND:
			return float(_d(uu).get("fly", 0.0)) <= 0.0
		UNIT_TYPE_FLYING:
			return float(_d(uu).get("fly", 0.0)) > 0.0
		UNIT_TYPE_SUMMONED:
			return uu is W3Unit
		UNIT_TYPE_MAGIC_IMMUNE:
			return uu.spell_shield > 0.0
		UNIT_TYPE_STUNNED:
			return uu.stun > 0.0
		UNIT_TYPE_MELEE_ATTACKER:
			return not uu.ranged
		UNIT_TYPE_RANGED_ATTACKER:
			return uu.ranged
		UNIT_TYPE_ANCIENT, UNIT_TYPE_MECHANICAL, UNIT_TYPE_UNDEAD, UNIT_TYPE_SAPPER, UNIT_TYPE_PEON, \
				UNIT_TYPE_TOWNHALL, UNIT_TYPE_POISONED, UNIT_TYPE_POLYMORPHED, UNIT_TYPE_SLEEPING, UNIT_TYPE_RESISTANT, \
				UNIT_TYPE_ETHEREAL, UNIT_TYPE_TAUREN, UNIT_TYPE_GIANT:
			return false
	return false


func IsUnitHidden(u) -> bool:
	var uu := _u(u)
	return uu != null and not uu.visible


func ShowUnit(u, show: bool) -> void:
	var uu := _u(u)
	if uu == null:
		return
	uu.visible = show
	_d(uu).hidden = not show


func IsUnitPaused(u) -> bool:
	return bool(_d(u).get("paused", false))


func PauseUnit(u, flag: bool) -> void:
	var uu := _u(u)
	if uu == null:
		return
	_d(uu).paused = flag
	uu.w3_paused = flag
	if flag and not (uu is W3Unit):
		uu.issue_stop()


func SetUnitInvulnerable(u, flag: bool) -> void:
	var uu := _u(u)
	if uu:
		uu.invulnerable = 1e9 if flag else 0.0


func UnitDamageTarget(src, dst, amount: float, _atk: bool, _ranged: bool, _at, _dt, _wt) -> bool:
	var d := _u(dst)
	if d == null or not d.alive or Game.I == null:
		_note_dmg("dead")
		return false
	if d is W3Unit and (d as W3Unit).dummy:
		_note_dmg("dummy")
		return false
	if amount <= 0.0:
		_note_dmg("zero")
	elif d.invulnerable > 0.0:
		_note_dmg("invul")
	elif _u(src) == null:
		_note_dmg("nosrc")
	else:
		_note_dmg("ok")
	Game.I.deal_damage(credit_of(src), d, amount * DMG_K, "spell")
	return true


## Отладка (--abiltest): какие триггеры вызывают урон и с каким результатом.
var dmg_calls := {}


func _note_dmg(reason: String) -> void:
	if Game.I == null or not Game.I.abiltest:
		return
	var tn := "?"
	var tr = _ev.get("trigger")
	if tr is JTrig and not (tr as JTrig).actions.is_empty():
		tn = str(((tr as JTrig).actions[0] as Callable).get_method()).trim_prefix("f_Trig_").trim_suffix("_Actions")
	elif _ev.has("timer"):
		tn = "timer"
	var k := tn + ":" + reason
	dmg_calls[k] = int(dmg_calls.get(k, 0)) + 1


# ---- анимация и вид
func SetUnitAnimation(u, a: String) -> void:
	var uu := _u(u)
	if uu:
		W3Unit.anim_on(uu, a, false)


func SetUnitAnimationWithRarity(u, a: String, _r) -> void:
	SetUnitAnimation(u, a)


func QueueUnitAnimation(u, a: String) -> void:
	var uu := _u(u)
	if uu:
		W3Unit.anim_on(uu, a, true)


func SetUnitTimeScale(u, k: float) -> void:
	var uu := _u(u)
	if uu is W3Unit:
		(uu as W3Unit).w3_time_scale(k)
	elif uu and uu.anim:
		uu.anim.speed_scale = k


func SetUnitScale(u, x: float, _y: float, _z: float) -> void:
	var uu := _u(u)
	if uu is W3Unit:
		(uu as W3Unit).w3_scale(x)


func SetUnitVertexColor(u, _r: int, _g: int, _b: int, a: int) -> void:
	var uu := _u(u)
	if uu:
		W3Unit.set_alpha(uu, clampf(a / 255.0, 0.0, 1.0))


func SelectUnit(_u_, _f: bool) -> void:
	pass


func ClearSelection() -> void:
	pass


# ---- приказы
func IssueImmediateOrder(u, order: String) -> bool:
	var uu := _u(u)
	if uu == null:
		return false
	order = order.to_lower()
	if order == "stop" or order == "holdposition":
		if not (uu is W3Unit):
			uu.issue_stop()
		return true
	return W3Abil.dummy_order(self, uu, order, null, Vector3.INF)


func IssuePointOrderLoc(u, order: String, l) -> bool:
	var uu := _u(u)
	if uu == null or not (l is Vector2):
		return false
	var p := pos_of(l.x, l.y)
	order = order.to_lower()
	if order == "move" or order == "smart" or order == "patrol":
		if uu is W3Unit:
			(uu as W3Unit).w3_move_to(p)
		else:
			uu.issue_move(p)
		return true
	if order == "attack":
		if not (uu is W3Unit and (uu as W3Unit).dummy):
			uu.issue_attack_move(p)
		return true
	return W3Abil.dummy_order(self, uu, order, null, p)


func IssueTargetOrder(u, order: String, t) -> bool:
	var uu := _u(u)
	var tt := _u(t)
	if uu == null or tt == null:
		return false
	order = order.to_lower()
	if order == "attack" or order == "smart":
		if not (uu is W3Unit and (uu as W3Unit).dummy):
			uu.issue_attack(tt)
		return true
	if order == "move":
		uu.issue_move(tt.global_position)
		return true
	return W3Abil.dummy_order(self, uu, order, tt, tt.global_position)


# ---- способности, баффы
func _is_buff(id: int) -> bool:
	return ((id >> 24) & 255) == 66   # 'B'


func GetUnitAbilityLevel(u, id: int) -> int:
	var uu := _u(u)
	if uu == null:
		return 0
	if _is_buff(id):
		return 1 if W3Abil.has_buff(self, uu, id) else 0
	return int((_d(uu).abils as Dictionary).get(id, 0))


func UnitAddAbility(u, id: int) -> bool:
	var uu := _u(u)
	if uu == null:
		return false
	var ab: Dictionary = _d(uu).abils
	if ab.has(id):
		return false
	ab[id] = 1
	W3Abil.on_added(self, uu, id)
	return true


func UnitRemoveAbility(u, id: int) -> bool:
	var uu := _u(u)
	if uu == null:
		return false
	if _is_buff(id):
		W3Abil.remove_buff(self, uu, id)
		return true
	var ab: Dictionary = _d(uu).abils
	if not ab.has(id):
		return false
	ab.erase(id)
	W3Abil.on_removed(self, uu, id)
	return true


func SetUnitAbilityLevel(u, id: int, lvl: int) -> int:
	var uu := _u(u)
	if uu == null:
		return 0
	var ab: Dictionary = _d(uu).abils
	if ab.has(id):
		ab[id] = maxi(1, lvl)
		W3Abil.on_added(self, uu, id)
	return int(ab.get(id, 0))


func IncUnitAbilityLevel(u, id: int) -> int:
	return SetUnitAbilityLevel(u, id, GetUnitAbilityLevel(u, id) + 1)


func SetPlayerAbilityAvailable(p, id: int, flag: bool) -> void:
	if p is JPlayer:
		if flag:
			p.avail.erase(id)
		else:
			p.avail[id] = false


func SelectHeroSkill(_u_, _id: int) -> void:
	pass


func UnitModifySkillPoints(_u_, _n: int) -> bool:
	return true


func GetHeroSkillPoints(_u_) -> int:
	return 0


func UnitStripHeroLevel(_u_, _n: int) -> bool:
	return false


func SuspendHeroXP(_u_, _f: bool) -> void:
	pass


# ---- герой
func GetHeroStr(u, _b: bool) -> int:
	var uu := _hero_or_caster(u)
	if uu is W3Unit:
		return int((uu as W3Unit).stats.str)
	return int((uu as Hero).s_str) if uu is Hero else 0


func GetHeroAgi(u, _b: bool) -> int:
	var uu := _hero_or_caster(u)
	if uu is W3Unit:
		return int((uu as W3Unit).stats.agi)
	return int((uu as Hero).s_agi) if uu is Hero else 0


func GetHeroInt(u, _b: bool) -> int:
	var uu := _hero_or_caster(u)
	if uu is W3Unit:
		return int((uu as W3Unit).stats.int)
	return int((uu as Hero).s_int) if uu is Hero else 0


## В карте встречается характеристика «пустого» героя (переменная не задана, урон выходит 0):
## тогда берём героя, применившего способность.
func _hero_or_caster(u) -> Unit:
	var uu := _u(u)
	if uu == null and _ev.get("unit") is Hero and is_instance_valid(_ev.get("unit")):
		return _ev.get("unit")
	return uu


func _set_stat(u, k: String, v: int) -> void:
	var uu := _u(u)
	if uu is W3Unit:
		(uu as W3Unit).set_stat(k, float(v))
		return
	var h := uu as Hero
	if h == null:
		return
	var cur := 0.0
	match k:
		"str":
			cur = h.s_str
		"agi":
			cur = h.s_agi
		"int":
			cur = h.s_int
	h.tome[k] = float(h.tome.get(k, 0.0)) + (float(v) - cur)
	h.recalc_stats()


func SetHeroStr(u, v: int, _p: bool) -> void:
	_set_stat(u, "str", v)


func SetHeroAgi(u, v: int, _p: bool) -> void:
	_set_stat(u, "agi", v)


func SetHeroInt(u, v: int, _p: bool) -> void:
	_set_stat(u, "int", v)


func GetHeroLevel(u) -> int:
	return GetUnitLevel(u)


func SetHeroLevel(u, l: int, _s: bool) -> void:
	var uu := _u(u)
	if uu is W3Unit:
		(uu as W3Unit).set_level(l)


# ---- предметы (нужны только для проверки проходимости в Knockback)
func CreateItem(t: int, x: float, y: float):
	var it := JItem.new()
	it.type_id = t
	SetItemPosition(it, x, y)
	return it


func SetItemPosition(i, x: float, y: float) -> void:
	if not (i is JItem):
		return
	var p := pos_of(x, y)
	if IsTerrainPathable(x, y, null) and Game.I:
		var best := p
		var bd := INF
		for z in Game.I.zones:
			var c: Vector3 = Game.I.clamp_to_area(p, z.index)
			var dd := c.distance_squared_to(p)
			if dd < bd:
				bd = dd
				best = c
		p = best
	i.x = p.x / U
	i.y = -p.z / U


func GetItemX(i) -> float:
	return i.x if i is JItem else 0.0


func GetItemY(i) -> float:
	return i.y if i is JItem else 0.0


func SetItemVisible(i, f: bool) -> void:
	if i is JItem:
		i.visible = f


func IsItemVisible(i) -> bool:
	return i is JItem and i.visible


func GetItemTypeId(i) -> int:
	return i.type_id if i is JItem else 0


func RemoveItem(_i) -> void:
	pass


func UnitAddItem(_u_, _i) -> bool:
	return false


func UnitItemInSlot(_u_, _s: int):
	return null


func EnumItemsInRect(_r, _f, _cb) -> void:
	pass


# ---- декорации
func CreateDestructable(_t: int, x: float, y: float, _face: float, _sc: float, _v: int):
	return null


func KillDestructable(_d_) -> void:
	pass


func RemoveDestructable(_d_) -> void:
	pass


func SetDestructableInvulnerable(_d_, _f: bool) -> void:
	pass


func EnumDestructablesInRect(_r, _f, _cb) -> void:
	pass


func CreateBlightedGoldmine(_p, _x: float, _y: float, _f: float):
	return null


# ---- эффекты
func AddSpecialEffectLoc(path: String, l):
	if not (l is Vector2):
		return null
	return W3Fx.at(self, path, pos_of(l.x, l.y))


func AddSpecialEffectTarget(path: String, u, attach: String):
	var uu := _u(u)
	if uu == null:
		return null
	return W3Fx.on_unit(self, path, uu, attach)


func DestroyEffect(e) -> void:
	if alive_obj(e) and e is W3Model:
		(e as W3Model).destroy_fx()


func AddLightningEx(code: String, _chk: bool, x1: float, y1: float, z1: float, x2: float, y2: float, z2: float):
	return W3Fx.lightning(self, code, Vector3(x1 * U, ground_y(x1 * U, -y1 * U) + z1 * U, -y1 * U),
		Vector3(x2 * U, ground_y(x2 * U, -y2 * U) + z2 * U, -y2 * U))


func MoveLightningEx(l, _chk: bool, x1: float, y1: float, z1: float, x2: float, y2: float, z2: float) -> bool:
	if alive_obj(l) and l is Node3D:
		W3Fx.move_lightning(l, Vector3(x1 * U, ground_y(x1 * U, -y1 * U) + z1 * U, -y1 * U),
			Vector3(x2 * U, ground_y(x2 * U, -y2 * U) + z2 * U, -y2 * U))
		return true
	return false


func SetLightningColor(l, r: float, g: float, b: float, a: float) -> bool:
	if alive_obj(l) and l is Node3D:
		W3Fx.color_lightning(l, Color(r, g, b, a))
		return true
	return false


func DestroyLightning(l) -> bool:
	if alive_obj(l) and l is Node:
		(l as Node).queue_free()
		return true
	return false


func TerrainDeformRipple(x: float, y: float, r: float, _d_: float, _t: int, _c: int, _sp: float, _ph: float, _w: float, _rel: bool):
	if fx_parent:
		Fx.ring_burst(fx_parent, pos_of(x, y) + Vector3(0, 0.1, 0), r * U, Color(0.75, 0.65, 0.5, 0.6), 0.7, 0.6)
	return null


func TerrainDeformStop(_d_, _t: int) -> void:
	pass


func AddWeatherEffect(_r, _id: int):
	return null


func EnableWeatherEffect(_w, _f: bool) -> void:
	pass


func RemoveWeatherEffect(_w) -> void:
	pass


# ---- текст над головой
func CreateTextTag():
	var l := Label3D.new()
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.outline_size = 8
	l.font_size = 48
	l.pixel_size = 0.01
	if fx_parent:
		fx_parent.add_child(l)
	return l


func SetTextTagText(t, s: String, h: float) -> void:
	if alive_obj(t) and t is Label3D:
		(t as Label3D).text = s.replace("|r", "")
		(t as Label3D).font_size = clampi(int(h * 1500.0), 24, 96)


func SetTextTagPos(t, x: float, y: float, z: float) -> void:
	if alive_obj(t) and t is Label3D:
		(t as Label3D).global_position = pos_of(x, y) + Vector3(0, z * U + 1.0, 0)


func SetTextTagColor(t, r: int, g: int, b: int, a: int) -> void:
	if alive_obj(t) and t is Label3D:
		(t as Label3D).modulate = Color8(r, g, b, maxi(a, 60))


func SetTextTagPermanent(t, f: bool) -> void:
	if alive_obj(t) and t is Label3D and not f:
		get_tree().create_timer(2.5).timeout.connect((t as Node).queue_free)


func DestroyTextTag(t) -> void:
	if alive_obj(t) and t is Node:
		(t as Node).queue_free()


# ---- звук
func CreateSound(path: String, _loop: bool, _3d: bool, _stop: bool, _fin: int, _fout: int, _eax: String):
	var s := JSound.new()
	s.path = path.replace("\\\\", "\\").replace("\\", "/").to_lower()
	return s


func SetSoundParamsFromLabel(_s, _l: String) -> void:
	pass


func SetSoundDuration(_s, _d_: int) -> void:
	pass


func SetSoundChannel(_s, _c: int) -> void:
	pass


func SetSoundPitch(_s, _p: float) -> void:
	pass


func SetSoundVolume(s, v: int) -> void:
	if s is JSound:
		s.vol = clampi(v, 0, 127)


func AttachSoundToUnit(s, u) -> void:
	if s is JSound:
		s.unit = u


func StartSound(s) -> void:
	if not (s is JSound) or Game.I == null or Game.I.sim:
		return
	var res: String = (data.get("sounds", {}) as Dictionary).get(s.path, "")
	if res == "":
		return
	# звук способности слышен рядом с камерой (иначе голоса всех героев звучали бы на всю карту)
	var u := _u(s.unit)
	if u == null:
		u = _u(_ev.get("unit"))
	if u and Game.I.camera and u.global_position.distance_to(Game.I.camera.focus) > 40.0:
		return
	var st: AudioStream = _sound_cache.get(res)
	if st == null:
		st = _load_sound(res)
		if st == null:
			return
		_sound_cache[res] = st
	if s.player == null or not is_instance_valid(s.player):
		s.player = AudioStreamPlayer.new()
		s.player.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
		add_child(s.player)
	s.player.stream = st
	s.player.volume_db = Audio.db(float(s.vol) / 127.0) - 3.0
	s.player.play()


## Звуки карты лежат в w3_sounds_N.pak (места — w3_data.json["sound_files"]).
func _load_sound(res: String) -> AudioStream:
	var fn := res.get_file()
	var e: Array = (data.get("sound_files", {}) as Dictionary).get(fn, [])
	if e.is_empty():
		return load(res) if ResourceLoader.exists(res) else null
	var f := FileAccess.open("res://w3/" + str(e[0]), FileAccess.READ)
	if f == null:
		return null
	f.seek(int(e[1]))
	var b := f.get_buffer(int(e[2]))
	if fn.ends_with(".wav"):
		return AudioStreamWAV.load_from_buffer(b)
	var mp3 := AudioStreamMP3.new()
	mp3.data = b
	return mp3


func StopSound(s, _kill: bool, _fade: bool) -> void:
	if s is JSound and s.player and is_instance_valid(s.player):
		s.player.stop()


func StopMusic(_f: bool) -> void:
	pass


func ResumeMusic() -> void:
	pass


# ---- камера, сообщения
func CameraSetSourceNoise(mag: float, _v: float) -> void:
	if Game.I and Game.I.camera and mag > 0.0:
		Game.I.camera.shake(clampf(mag / 40.0, 0.1, 1.0))


func CameraSetSourceNoiseEx(mag: float, v: float, _b: bool) -> void:
	CameraSetSourceNoise(mag, v)


func CameraSetTargetNoise(mag: float, v: float) -> void:
	CameraSetSourceNoise(mag, v)


func CameraSetTargetNoiseEx(mag: float, v: float, _b: bool) -> void:
	CameraSetSourceNoise(mag, v)


func SetCameraField(_f, _v: float, _d_: float) -> void:
	pass


func PanCameraToTimed(_x: float, _y: float, _d_: float) -> void:
	pass


func DisplayTextToPlayer(p, _x: float, _y: float, s: String) -> void:
	DisplayTimedTextToPlayer(p, 0.0, 0.0, 3.0, s)


## Подсказки способностей из карты («нужно применить ещё 2 заклинания» и т. п.) — игроку на экран.
func DisplayTimedTextToPlayer(p, _x: float, _y: float, d: float, s: String) -> void:
	if p != local_player or Game.I == null or Game.I.sim or Game.I.hud == null:
		return
	if not (_ev.get("unit") == Game.I.player):
		return
	var re := RegEx.create_from_string("\\|c[0-9a-fA-F]{8}|\\|r|\\|n")
	var t := re.sub(s, "", true).strip_edges()
	if t != "":
		Game.I.hud.announce(t, Color(1.0, 0.9, 0.6), clampf(d, 2.0, 6.0))


func FlashQuestDialogButton() -> void:
	pass


func DialogCreate():
	return JHandle.new()

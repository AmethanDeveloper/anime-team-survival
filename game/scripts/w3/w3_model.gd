class_name W3Model
extends Node3D
## Модель Warcraft 3 в игре: меши и анимации из GLB, частицы (PRE2) и ленты (RIBB) из fx.json.
## Анимации выбираются по словам, как в WC3: "spell channel", "attack 2", "birth"...

const W3_DIR := "res://w3/"
const MAX_PARTICLES := 260

static var _index: Dictionary = {}
static var _index_loaded := false
static var _cache: Dictionary = {}   # имя -> [PackedScene|null, Dictionary]
static var _mat_cache: Dictionary = {}
static var _quad: QuadMesh = null

var key := ""
var info: Dictionary = {}
var scene_root: Node3D = null
var ap: AnimationPlayer = null
var cur := ""          # текущая анимация (имя в GLB / fx.json)
var cur_t := 0.0
var cur_len := 1.0
var cur_loop := true
var time_scale := 1.0
var queue: Array[String] = []
var emitters: Array = []   # [{def, mm, parts:[], acc, t_prev}]
var ribbons: Array = []
var dying := false
var die_left := 0.0
var free_when_done := false
var follow: Node3D = null      # юнит, к которому прикреплён эффект
var follow_off := Vector3.ZERO
var fallback := false
var fades: Array = []   # [[GeometryInstance3D, {анимация: [дорожки]}]] — плавная прозрачность частей


## Камера (Game обновляет каждый кадр): эффекты дальше cam_r не считают частицы — их всё равно не видно
static var cam_pos := Vector3.ZERO
static var cam_r2 := 1e12
## Общий бюджет живых частиц всех эффектов (зависит от качества графики): сверх него новые не рождаются
static var particle_budget := 2000
static var live_particles := 0
static var _models: Dictionary = {}   # имя -> данные модели (частицы, ленты, анимации)
static var _files: Dictionary = {}    # имя файла -> [пак, смещение, размер]
static var _paks: Dictionary = {}     # пак -> FileAccess
static var _tex_cache: Dictionary = {}
static var _mutex := Mutex.new()
static var _pak_mutex := Mutex.new()
static var _loading: Dictionary = {}
static var _bg_queue: PackedStringArray = []
static var _bg_task := -1
static var _bg_stop := false
## Сколько копий каждой модели сейчас в сцене (ограничение одинаковых эффектов)
static var live_by_key: Dictionary = {}


## Эффекты лежат пакетами: res://w3/w3_fx*.json + w3_fx*_N.pak (GLB и текстуры читаются прямо из пака).
static func _load_index() -> void:
	if _index_loaded:
		return
	_index_loaded = true
	var dir := DirAccess.open(W3_DIR)
	if dir == null:
		return
	for fn in dir.get_files():
		if fn.begins_with("w3_fx") and fn.ends_with(".json"):
			var f := FileAccess.open(W3_DIR + fn, FileAccess.READ)
			if f == null:
				continue
			var d = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				_index.merge(d.get("index", {}), true)
				_models.merge(d.get("models", {}), true)
				_files.merge(d.get("files", {}), true)


## Освобождение шаблонов моделей и паков (при выходе из игры).
static func clear_cache() -> void:
	_stop_bg()
	for k in _cache:
		var t = _cache[k][0]
		if t is Node and is_instance_valid(t):
			(t as Node).free()
	_cache.clear()
	_paks.clear()
	_tex_cache.clear()


## Байты файла из пака (GLB, PNG).
static func pak_bytes(name: String) -> PackedByteArray:
	_load_index()
	var e: Array = _files.get(name, [])
	if e.is_empty():
		return PackedByteArray()
	var pak: String = e[0]
	_pak_mutex.lock()
	var f: FileAccess = _paks.get(pak)
	if f == null:
		f = FileAccess.open(W3_DIR + pak, FileAccess.READ)
		if f == null:
			_pak_mutex.unlock()
			return PackedByteArray()
		_paks[pak] = f
	f.seek(int(e[1]))
	var out := f.get_buffer(int(e[2]))
	_pak_mutex.unlock()
	return out


static func pak_texture(name: String) -> Texture2D:
	if name == "":
		return null
	_mutex.lock()
	if _tex_cache.has(name):
		var got: Texture2D = _tex_cache[name]
		_mutex.unlock()
		return got
	_mutex.unlock()
	var t: Texture2D = null
	var b := pak_bytes(name)
	if not b.is_empty():
		var img := Image.new()
		if img.load_png_from_buffer(b) == OK:
			img.generate_mipmaps()
			t = ImageTexture.create_from_image(img)
	_mutex.lock()
	_tex_cache[name] = t
	_mutex.unlock()
	return t


## Текстура для сложения (add): почти чёрный фон (1–6 из 255 после JPEG-сжатия BLP) при наложении
## десятков частиц складывается в серый квадрат. Срезаем этот «пол», чтобы фон был ровно чёрным.
static func pak_texture_add(name: String) -> Texture2D:
	if name == "":
		return null
	var key := name + "|add"
	_mutex.lock()
	if _tex_cache.has(key):
		var got: Texture2D = _tex_cache[key]
		_mutex.unlock()
		return got
	_mutex.unlock()
	var t: Texture2D = null
	var b := pak_bytes(name)
	if not b.is_empty():
		var img := Image.new()
		if img.load_png_from_buffer(b) == OK:
			img.convert(Image.FORMAT_RGBA8)
			var d := img.get_data()
			var floor_v := 10
			var k := 255.0 / float(255 - floor_v)
			var lut := PackedByteArray()
			lut.resize(256)
			for v in 256:
				lut[v] = clampi(int(round(maxf(0.0, float(v - floor_v)) * k)), 0, 255)
			var i := 0
			var n := d.size()
			while i < n:
				d[i] = lut[d[i]]
				d[i + 1] = lut[d[i + 1]]
				d[i + 2] = lut[d[i + 2]]
				i += 4
			img = Image.create_from_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, d)
			img.generate_mipmaps()
			t = ImageTexture.create_from_image(img)
	_mutex.lock()
	_tex_cache[key] = t
	_mutex.unlock()
	return t


static func norm_key(path: String) -> String:
	var k := path.replace("\\\\", "\\").replace("\\", "/").strip_edges().to_lower()
	if k.ends_with(".mdl") or k.ends_with(".mdx"):
		k = k.substr(0, k.length() - 4)
	return k


static func has_model(path: String) -> bool:
	_load_index()
	return _index.has(norm_key(path))


## [шаблон сцены или null, данные]; шаблон собирается из GLB один раз, экземпляры — его копии.
## Разбирать модель можно в фоновом потоке (preload_paths): здесь кэш под замком, а если эту модель
## уже разбирает другой поток — ждём его, это быстрее, чем разбирать заново.
static func _load_entry(name: String) -> Array:
	_mutex.lock()
	if _cache.has(name):
		var hit: Array = _cache[name]
		_mutex.unlock()
		return hit
	var busy := _loading.has(name)
	if not busy:
		_loading[name] = true
	_mutex.unlock()
	if busy:
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 4000:
			OS.delay_usec(400)
			_mutex.lock()
			if _cache.has(name):
				var hit2: Array = _cache[name]
				_mutex.unlock()
				return hit2
			_mutex.unlock()
	var res := _parse_entry(name)
	_mutex.lock()
	if _cache.has(name):
		if res[0] is Node:
			(res[0] as Node).free()
		res = _cache[name]
	else:
		_cache[name] = res
	_loading.erase(name)
	_mutex.unlock()
	return res


static func is_cached(path: String) -> bool:
	_load_index()
	var name: String = _index.get(norm_key(path), "")
	if name == "":
		return true
	_mutex.lock()
	var ok := _cache.has(name)
	_mutex.unlock()
	return ok


## Фоновая загрузка: модели разбираются в отдельном потоке заранее, чтобы в бою не было рывков.
static func preload_paths(paths: Array) -> void:
	_load_index()
	_mutex.lock()
	for p in paths:
		var nm: String = _index.get(norm_key(str(p)), "")
		if nm != "" and not _cache.has(nm) and not _loading.has(nm) and not _bg_queue.has(nm):
			_bg_queue.append(nm)
	var start := not _bg_queue.is_empty()
	_mutex.unlock()
	if not start:
		return
	if _bg_task >= 0 and WorkerThreadPool.is_task_completed(_bg_task):
		WorkerThreadPool.wait_for_task_completion(_bg_task)
		_bg_task = -1
	if _bg_task < 0:
		_bg_stop = false
		_bg_task = WorkerThreadPool.add_task(W3Model._bg_run, false, "W3 preload")


static func _bg_run() -> void:
	while not _bg_stop:
		_mutex.lock()
		if _bg_queue.is_empty():
			_mutex.unlock()
			return
		var nm: String = _bg_queue[0]
		_bg_queue.remove_at(0)
		_mutex.unlock()
		_load_entry(nm)


static func bg_left() -> int:
	_mutex.lock()
	var n := _bg_queue.size() + _loading.size()
	_mutex.unlock()
	return n


static func _stop_bg() -> void:
	_bg_stop = true
	if _bg_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_bg_task)
		_bg_task = -1
	_bg_queue.clear()


static func _parse_entry(name: String) -> Array:
	var info: Dictionary = _models.get(name, {})
	_fix_color_order(info)
	var tpl: Node3D = null
	var glb := str(info.get("glb", ""))
	if glb != "":
		var b := pak_bytes(glb)
		if not b.is_empty():
			var doc := GLTFDocument.new()
			var st := GLTFState.new()
			if doc.append_from_buffer(b, "", st) == OK:
				var n := doc.generate_scene(st)
				if n is Node3D:
					tpl = n
					var tap := Unit.find_anim(tpl)
					if tap:
						HeroAssets._fix_tracks(tap)
					_fix_materials(tpl)
				elif n:
					n.free()
	# текстуры частиц и лент — тоже заранее (их чтение и разбор давали рывок при первом показе)
	for e in info.get("emitters", []):
		var tx := str((e as Dictionary).get("tex", ""))
		if tx != "":
			if str((e as Dictionary).get("filter", "")) == "add":
				pak_texture_add(tx)
			else:
				pak_texture(tx)
	for r in info.get("ribbons", []):
		var tx2 := str((r as Dictionary).get("tex", ""))
		if tx2 != "":
			pak_texture(tx2)
	return [tpl, info]


## Цвета частиц и лент в данных лежат в порядке B, G, R (конвертер переставил их лишний раз):
## без этого огонь выходил синим, а лёд — оранжевым.
static func _fix_color_order(info: Dictionary) -> void:
	if info.get("_rgb", false):
		return
	info["_rgb"] = true
	for e in info.get("emitters", []):
		var cs: Array = e.get("colors", [])
		for i in cs.size():
			var c: Array = cs[i]
			if c.size() >= 3:
				cs[i] = [c[2], c[1], c[0]]
	for r in info.get("ribbons", []):
		var c2: Array = r.get("color", [])
		if c2.size() >= 3:
			r["color"] = [c2[2], c2[1], c2[0]]
	# анимированные скорость, размеры области вылета, гравитация частиц и высоты лент конвертер оставил
	# в единицах WC3 (без × 0.01, как у постоянных значений): частицы разлетались на десятки метров
	for e in info.get("emitters", []):
		for seq in (e.get("tracks", {}) as Dictionary).values():
			for k in ["speed", "width", "length", "grav"]:
				_scale_track((seq as Dictionary).get(k), 0.01)
	for r in info.get("ribbons", []):
		for seq in (r.get("tracks", {}) as Dictionary).values():
			for k in ["above", "below"]:
				_scale_track((seq as Dictionary).get(k), 0.01)


static func _scale_track(tr: Variant, k: float) -> void:
	if not (tr is Dictionary):
		return
	for key in (tr as Dictionary).get("keys", []):
		var a: Array = key
		for i in range(1, a.size()):
			if a[i] is float or a[i] is int:
				a[i] = float(a[i]) * k


## Создаёт модель по пути WC3 (например "Abilities\\Spells\\Human\\ThunderClap\\ThunderClapCaster.mdl").
## Счётчики для замеров (--casttest): загрузка моделей, копирование, обработка кадра
static var stat_load_us := 0
static var stat_dup_us := 0
static var stat_proc_us := 0
static var stat_create_n := 0
static var stat_load_n := 0


static func create(path: String, async := false) -> W3Model:
	_load_index()
	stat_create_n += 1
	var m := W3Model.new()
	m.key = norm_key(path)
	if async and not is_cached(path):
		# в бою модель не разбираем: этот раз без картинки, а модель догрузится в фоне
		preload_paths([path])
		m.fallback = true
		m.skipped = true
		return m
	if OS.get_environment("W3_LOG") != "":
		print("[W3FX] ", m.key)
	var name: String = _index.get(m.key, "")
	if name == "":
		m.fallback = true
		return m
	var t0 := Time.get_ticks_usec()
	_mutex.lock()
	var cached := _cache.has(name)
	_mutex.unlock()
	var got := _load_entry(name)
	if not cached:
		stat_load_n += 1
		stat_load_us += Time.get_ticks_usec() - t0
		if OS.get_environment("W3_COLDLOG") != "":
			print("[COLD] %s %.0f ms" % [name, (Time.get_ticks_usec() - t0) / 1000.0])
	m.info = got[1]
	if got[0] and OS.get_environment("W3_NOMESH") == "":
		var t1 := Time.get_ticks_usec()
		m.scene_root = (got[0] as Node3D).duplicate()
		stat_dup_us += Time.get_ticks_usec() - t1
		m.add_child(m.scene_root)
		m.ap = Unit.find_anim(m.scene_root)
		if m.ap:
			m.ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	return m


static func _fix_materials(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mi.mesh:
			for s in mi.mesh.get_surface_count():
				var mat := mi.mesh.surface_get_material(s)
				if mat is BaseMaterial3D:
					var bm := mat as BaseMaterial3D
					var nm := bm.resource_name
					# оттенок частей модели (GeosetAnim) конвертер записал как B, G, R — огонь выходил синим
					var ac := bm.albedo_color
					if not is_equal_approx(ac.r, ac.b):
						bm.albedo_color = Color(ac.b, ac.g, ac.r, ac.a)
					if nm.ends_with("@add"):
						bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
						bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
						bm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
						bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
						bm.cull_mode = BaseMaterial3D.CULL_DISABLED
					elif nm.ends_with("@blend"):
						bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
						bm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
						bm.cull_mode = BaseMaterial3D.CULL_DISABLED
						bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
					elif nm.ends_with("@mod"):
						bm.blend_mode = BaseMaterial3D.BLEND_MODE_MUL
						bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
						bm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
						bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for c in n.get_children():
		_fix_materials(c)


var vfx_hidden := false   # графику модели заменил готовый эффект (W3Vfx)
## Эффект пропущен (далеко от камеры, слишком много одинаковых или модель ещё грузится): пустышка без картинки
var skipped := false


func _enter_tree() -> void:
	if not fallback:
		live_by_key[key] = int(live_by_key.get(key, 0)) + 1


static func live_count(k: String) -> int:
	return int(live_by_key.get(k, 0))


func _ready() -> void:
	if fallback:
		return
	vfx_hidden = W3Vfx.wants_hide(self)
	var hk := OS.get_environment("W3_HIDEK")
	if hk != "":
		for w in hk.split(","):
			if key.contains(w):
				if scene_root:
					scene_root.visible = false
				return
	if OS.get_environment("W3_LOG") != "":
		print("[W3VFX] ", key, " ", (info.get("vfx", {}) as Dictionary).get("kind", "-"), " hide=", vfx_hidden)
	if W3Vfx.active():
		W3Vfx.start_for.call_deferred(self, vfx_hidden)
	if vfx_hidden:
		if scene_root:
			scene_root.visible = false
		if cur == "":
			play("birth" if find_anim("birth") != "" else "stand")
			if find_anim("birth") != "":
				queue.append("stand")
		return
	if scene_root:
		var ga: Dictionary = info.get("geo_alpha", {})
		for gname in ga:
			var gn := scene_root.find_child(gname, true, false)
			if gn is GeometryInstance3D:
				fades.append([gn, ga[gname]])
	for e in info.get("emitters", []):
		var skipk := OS.get_environment("W3_SKIPK")
		if bool(e.get("xy_quad", false)):
			# огромные плоские кольца на земле (до 40 м) в игре заливают экран — их пропускаем
			var bigx := 0.0
			for v in e.scaling:
				bigx = maxf(bigx, float(v))
			if bigx * 2.0 * global_transform.basis.get_scale().x > 10.0:
				continue
		var skipe := OS.get_environment("W3_SKIPE")
		if skipe != "" and skipk != "" and key.contains(skipk) and str(e.name) == skipe:
			continue
		if OS.get_environment("W3_NOPART") == "" and (skipk == "" or not key.contains(skipk) or skipe != ""):
			_add_emitter(e)
	for r in info.get("ribbons", []):
		_add_ribbon(r)
	if cur == "":
		if find_anim("birth") != "":
			play("birth")
			queue.append("stand")
		else:
			play("stand")


# ------------------------------------------------------------------ анимации
func anim_names() -> Array:
	return (info.get("anims", {}) as Dictionary).keys()


## Подбор анимации по словам WC3: все слова запроса должны быть в имени; без лишних слов — лучше.
static func pick_anim(names: Array, q: String) -> String:
	var want := q.to_lower().replace("-", " ").replace("_", " ").split(" ", false)
	var best := ""
	var best_extra := 999
	for n in names:
		var toks := String(n).to_lower().replace("-", " ").replace("_", " ").split(" ", false)
		var ok := true
		for w in want:
			if w.is_valid_int():
				continue
			if not toks.has(w):
				ok = false
				break
		if not ok:
			continue
		var extra := 0
		for t in toks:
			if not t.is_valid_int() and not want.has(t):
				extra += 1
		if extra < best_extra:
			best_extra = extra
			best = n
	return best


func find_anim(q: String) -> String:
	return pick_anim(anim_names(), q)


func play(q: String, loop_override := -1) -> bool:
	var n := find_anim(q) if not (info.get("anims", {}) as Dictionary).has(q) else q
	if n == "":
		return false
	var a: Array = info.anims[n]
	cur = n
	cur_t = 0.0
	cur_len = maxf(0.033, float(a[0]))
	cur_loop = bool(a[1]) if loop_override < 0 else loop_override == 1
	if ap and ap.has_animation(n):
		var anim := ap.get_animation(n)
		anim.loop_mode = Animation.LOOP_LINEAR if cur_loop else Animation.LOOP_NONE
		ap.play(n, 0.0)
		ap.seek(0.0, true)
		ap.speed_scale = time_scale
	for e in emitters:
		e.t_prev = -1.0
	return true


func set_time_scale(k: float) -> void:
	time_scale = k
	if ap:
		ap.speed_scale = k


## Уничтожение эффекта, как DestroyEffect: анимация смерти, потом удаление.
func destroy_fx() -> void:
	if dying:
		return
	dying = true
	if fallback:
		queue_free()
		return
	if find_anim("death") != "" and play("death", 0):
		die_left = cur_len + _max_life()
	elif not cur_loop and cur != "":
		die_left = maxf(0.05, cur_len - cur_t) + _max_life()
	else:
		for e in emitters:
			e.off = true
		die_left = _max_life() + 0.05
		if scene_root:
			scene_root.visible = false


func _max_life() -> float:
	var m := 0.0
	for e in emitters:
		m = maxf(m, float(e.def.lifespan))
	for r in ribbons:
		m = maxf(m, float(r.def.lifespan))
	return minf(m, 4.0)


func _process(delta: float) -> void:
	if fallback:
		return
	var t_in := Time.get_ticks_usec()
	_process_body(delta)
	stat_proc_us += Time.get_ticks_usec() - t_in


func _process_body(delta: float) -> void:
	if follow != null:
		if is_instance_valid(follow) and follow.is_inside_tree():
			global_position = follow.global_position + follow_off
		else:
			follow = null
			destroy_fx()
	var dt := delta * time_scale
	cur_t += dt
	if cur_t >= cur_len:
		if not queue.is_empty() and not dying:
			play(queue.pop_front())
		elif cur_loop:
			cur_t = fmod(cur_t, cur_len)
			for e in emitters:
				e.t_prev = -1.0
		else:
			cur_t = cur_len
	if ap and ap.is_playing() and ap.current_animation == cur:
		cur_t = ap.current_animation_position
	if dying:
		die_left -= delta
		if die_left <= 0.0:
			queue_free()
			return
	var gp := global_position
	if (gp.x - cam_pos.x) * (gp.x - cam_pos.x) + (gp.z - cam_pos.z) * (gp.z - cam_pos.z) > cam_r2:
		return
	for f in fades:
		var per: Dictionary = f[1]
		var trs: Array = per.get(cur, [])
		var a := 1.0
		for tr in trs:
			a *= _track_val(tr, cur_t, 1.0)
		var tv := clampf(1.0 - a, 0.0, 1.0)
		# прозрачность меняем только когда она изменилась (каждая запись — обновление на стороне отрисовки)
		if f.size() < 3 or absf(float(f[2]) - tv) > 0.004:
			if f.size() < 3:
				f.append(tv)
			else:
				f[2] = tv
			(f[0] as GeometryInstance3D).transparency = tv
	for e in emitters:
		# излучатель молчит в этой анимации и частиц не осталось — ничего не считаем
		if (e.parts as Array).is_empty() and not _emitter_live(e):
			continue
		_update_emitter(e, dt)
	for r in ribbons:
		_update_ribbon(r, dt)


# ------------------------------------------------------------------ путь узла
func _node_xf(path: Dictionary) -> Transform3D:
	var p: Dictionary = path.get(cur, {})
	if p.is_empty():
		for k in path:
			p = path[k]
			break
	var pos: Array = p.get("pos", [[0, 0, 0]])
	var rot: Array = p.get("rot", [[0, 0, 0, 1]])
	var n := pos.size()
	var f := 0.0
	if n > 1:
		f = clampf(cur_t / cur_len, 0.0, 1.0) * float(n - 1)
	var i := mini(int(f), n - 1)
	var j := mini(i + 1, n - 1)
	var k := f - float(i)
	var a: Array = pos[i]
	var b: Array = pos[j]
	var o := Vector3(a[0], a[1], a[2]).lerp(Vector3(b[0], b[1], b[2]), k)
	var qa: Array = rot[mini(i, rot.size() - 1)]
	var qb: Array = rot[mini(j, rot.size() - 1)]
	var q := Quaternion(qa[0], qa[1], qa[2], qa[3]).normalized().slerp(Quaternion(qb[0], qb[1], qb[2], qb[3]).normalized(), k)
	return Transform3D(Basis(q), o)


static func _track_val(tr: Variant, t: float, default: float) -> float:
	if tr == null or not (tr is Dictionary):
		return default
	var keys: Array = tr.get("keys", [])
	if keys.is_empty():
		return default
	if tr.has("global"):
		var gd := float(tr.global)
		if gd > 0.0:
			t = fmod(Time.get_ticks_msec() / 1000.0, gd)
	var step: bool = tr.get("step", false)
	var prev: Array = keys[0]
	if t <= float(prev[0]):
		return float(prev[1])
	for kk in keys:
		if float(kk[0]) >= t:
			if step:
				return float(prev[1])
			var span := float(kk[0]) - float(prev[0])
			if span <= 0.0:
				return float(kk[1])
			return lerpf(float(prev[1]), float(kk[1]), (t - float(prev[0])) / span)
		prev = kk
	return float(prev[1])


# ------------------------------------------------------------------ частицы
static func _quad_mesh() -> QuadMesh:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2(1, 1)
	return _quad


static var _flat_shaders := {}


## Плоские частицы (кольца на земле): свой простой шейдер — цвет текстуры × цвет частицы.
static func _flat_mat(tex_path: String, mode: String) -> ShaderMaterial:
	var bm := "blend_add" if mode == "add" else ("blend_mul" if mode.begins_with("mod") else "blend_mix")
	if not _flat_shaders.has(bm):
		var sh := Shader.new()
		sh.code = """shader_type spatial;
render_mode unshaded, %s, depth_draw_never, cull_disabled, shadows_disabled;
uniform sampler2D tex : source_color, filter_linear, repeat_disable;
void fragment() {
	vec4 t = texture(tex, UV);
	ALBEDO = t.rgb * COLOR.rgb;
	ALPHA = t.a * COLOR.a;
	%s
}
""" % [bm, "ALBEDO = mix(vec3(1.0), ALBEDO, ALPHA); ALPHA = 1.0;" if bm == "blend_mul" else ""]
		_flat_shaders[bm] = sh
	var m := ShaderMaterial.new()
	m.shader = _flat_shaders[bm]
	var t := pak_texture(tex_path)
	m.set_shader_parameter("tex", t if t else _soft_dot())
	return m


static func _particle_mat(tex_path: String, mode: String, cols: int, rows: int, flat: bool) -> Material:
	var k := "%s|%s|%d|%d|%s" % [tex_path, mode, cols, rows, flat]
	if _mat_cache.has(k):
		return _mat_cache[k]
	if flat:
		_mat_cache[k] = _flat_mat(tex_path, mode)
		return _mat_cache[k]
	if mode.begins_with("mod"):
		_mat_cache[k] = _mod_mat(tex_path, cols, rows)
		return _mat_cache[k]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	match mode:
		"add":
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		"mod", "mod2x":
			m.blend_mode = BaseMaterial3D.BLEND_MODE_MUL
		"alphakey":
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			m.alpha_scissor_threshold = 0.3
	if not flat:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.billboard_keep_scale = true
	m.particles_anim_h_frames = maxi(1, cols)
	m.particles_anim_v_frames = maxi(1, rows)
	m.particles_anim_loop = false
	var pt := pak_texture_add(tex_path) if mode == "add" else pak_texture(tex_path)
	if pt:
		m.albedo_texture = pt
	else:
		m.albedo_texture = _soft_dot()
	_mat_cache[k] = m
	return m


static var _mod_shader: Shader = null


## Затемняющие частицы (Modulate): прозрачные края текстуры не должны темнить — иначе вокруг дыма
## видны серые квадраты. Прозрачное — белое (умножение на 1).
static func _mod_mat(tex_path: String, cols: int, rows: int) -> ShaderMaterial:
	if _mod_shader == null:
		_mod_shader = Shader.new()
		_mod_shader.code = """shader_type spatial;
render_mode unshaded, blend_mul, depth_draw_never, cull_disabled, shadows_disabled;
uniform sampler2D tex : source_color, filter_linear, repeat_disable;
uniform int hf = 1;
uniform int vf = 1;
void vertex() {
	mat4 bb = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	bb = bb * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * bb;
	float n = float(hf * vf);
	float fr = clamp(floor(INSTANCE_CUSTOM.z * n), 0.0, n - 1.0);
	float fx = mod(fr, float(hf));
	float fy = floor(fr / float(hf));
	UV = (UV + vec2(fx, fy)) / vec2(float(hf), float(vf));
}
void fragment() {
	vec4 t = texture(tex, UV);
	float a = t.a * COLOR.a;
	ALBEDO = mix(vec3(1.0), t.rgb * COLOR.rgb, a);
	ALPHA = 1.0;
}
"""
	var m := ShaderMaterial.new()
	m.shader = _mod_shader
	var t := pak_texture(tex_path)
	m.set_shader_parameter("tex", t if t else _soft_dot())
	m.set_shader_parameter("hf", maxi(1, cols))
	m.set_shader_parameter("vf", maxi(1, rows))
	return m


static var _dot: Texture2D = null


static func _soft_dot() -> Texture2D:
	if _dot:
		return _dot
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var d := Vector2(x - 15.5, y - 15.5).length() / 15.5
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	_dot = ImageTexture.create_from_image(img)
	return _dot


func _add_emitter(d: Dictionary) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = _quad_mesh()
	mm.instance_count = MAX_PARTICLES
	mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tex := str(d.get("tex", ""))
	mi.material_override = _particle_mat(tex, str(d.filter), int(d.cols), int(d.rows), bool(d.get("xy_quad", false)))
	mi.extra_cull_margin = 40.0
	var model_space: bool = d.get("model_space", false)
	if model_space:
		add_child(mi)
	else:
		mi.top_level = true
		add_child(mi)
		mi.global_transform = Transform3D.IDENTITY
	# огромные частицы (кольца ударной волны на 10+ м) в WC3 не копятся десятками — иначе всё заливает белым
	var big := 0.0
	for v in d.scaling:
		big = maxf(big, float(v))
	var size := big * 2.0 * global_transform.basis.get_scale().x if is_inside_tree() else big * 2.0 * scale.x
	var cap := clampi(int(48.0 / maxf(size, 1.0)), 4, MAX_PARTICLES)
	emitters.append({"def": d, "mm": mm, "mi": mi, "parts": [], "acc": 0.0, "t_prev": -1.0, "off": false,
		"model_space": model_space, "cap": cap})


func _exit_tree() -> void:
	if not fallback:
		var lc := int(live_by_key.get(key, 0)) - 1
		if lc <= 0:
			live_by_key.erase(key)
		else:
			live_by_key[key] = lc
	for e in emitters:
		live_particles -= (e.parts as Array).size()
		(e.parts as Array).clear()
	live_particles = maxi(live_particles, 0)


## Излучатель может что-то выпустить в текущей анимации (видимость и частота не нулевые хоть где-то).
func _emitter_live(e: Dictionary) -> bool:
	if e.off:
		return false
	var lk := "live:" + cur
	if e.has(lk):
		return e[lk]
	var d: Dictionary = e.def
	var trs: Dictionary = (d.get("tracks", {}) as Dictionary).get(cur, {})
	var live := true
	var vt = trs.get("vis")
	if vt is Dictionary and not (vt.get("keys", []) as Array).is_empty():
		live = false
		for k in vt.keys:
			if float(k[1]) > 0.0:
				live = true
				break
	var rt = trs.get("rate")
	if live:
		if rt is Dictionary and not (rt.get("keys", []) as Array).is_empty():
			var any := false
			for k in rt.keys:
				if float(k[1]) > 0.0:
					any = true
					break
			live = any
		elif float(d.rate) <= 0.0:
			live = false
	e[lk] = live
	if not live:
		(e.mm as MultiMesh).visible_instance_count = 0
	return live


## Сколько частиц может жить в каждом излучателе (большие частицы по умолчанию ограничены, чтобы не заливать
## экран; облако пламени Гока Мэккяку должно быть плотным).
func set_particle_cap(n: int) -> void:
	for e in emitters:
		e.cap = clampi(n, 1, MAX_PARTICLES)


func _update_emitter(e: Dictionary, dt: float) -> void:
	var d: Dictionary = e.def
	var trs: Dictionary = (d.get("tracks", {}) as Dictionary).get(cur, {})
	var nx := _node_xf(d.path)
	var xf := global_transform * nx
	var vis := _track_val(trs.get("vis"), cur_t, 1.0)
	var rate := _track_val(trs.get("rate"), cur_t, float(d.rate))
	var parts: Array = e.parts
	if not e.off and vis > 0.0 and rate > 0.0:
		var n := 0
		if int(d.get("squirt", 0)) == 1:
			var tr = trs.get("rate")
			if tr is Dictionary:
				for kk in tr.get("keys", []):
					var kt := float(kk[0])
					if kt > float(e.t_prev) and kt <= cur_t and float(kk[1]) > 0.0:
						n += int(kk[1])
		else:
			e.acc += rate * dt
			n = int(e.acc)
			e.acc -= n
		n = mini(n, int(e.cap) - parts.size())
		if live_particles >= particle_budget:
			n = 0
		elif live_particles > particle_budget * 0.6:
			n = int(ceilf(n * 0.5))
		live_particles += maxi(n, 0)
		for i in n:
			parts.append(_spawn_particle(d, trs, xf, e.model_space, nx))
	e.t_prev = cur_t
	# движение
	var life := maxf(0.05, float(d.lifespan))
	var grav := float(d.gravity)
	var sc := global_transform.basis.get_scale().x if not e.model_space else 1.0
	var k := 0
	while k < parts.size():
		var p: Array = parts[k]
		p[2] += dt
		if p[2] >= life:
			parts.remove_at(k)
			live_particles -= 1
			continue
		p[1].y -= grav * sc * dt
		p[0] += p[1] * dt
		k += 1
	var mm: MultiMesh = e.mm
	mm.visible_instance_count = parts.size()
	var cols: Array = d.colors
	var alphas: Array = d.alphas
	var scal: Array = d.scaling
	var mid := clampf(float(d.time), 0.01, 0.99)
	var frames := maxi(1, int(d.cols) * int(d.rows))
	var head: Array = d.head
	var decay: Array = d.head_decay
	var flat: bool = d.get("xy_quad", false)
	for i in parts.size():
		var p: Array = parts[i]
		var t: float = p[2] / life
		var c0: int
		var c1: int
		var kk: float
		if t < mid:
			c0 = 0
			c1 = 1
			kk = t / mid
		else:
			c0 = 1
			c1 = 2
			kk = (t - mid) / (1.0 - mid)
		var ca: Array = cols[c0]
		var cb: Array = cols[c1]
		var col := Color(lerpf(ca[0], cb[0], kk), lerpf(ca[1], cb[1], kk), lerpf(ca[2], cb[2], kk),
			lerpf(float(alphas[c0]), float(alphas[c1]), kk) / 255.0)
		var s: float = lerpf(float(scal[c0]), float(scal[c1]), kk) * 2.0 * float(p[3])
		var fr := 0.0
		var iv: Array = head if t < mid else decay
		var f0 := float(iv[0])
		var f1 := float(iv[1])
		var rep := maxf(1.0, float(iv[2]))
		fr = f0 + (f1 - f0) * fmod(kk * rep, 1.0)
		var b := Basis.IDENTITY.scaled(Vector3(s, s, s))
		if flat:
			b = Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(s, s, s))
		var pos: Vector3 = p[0]
		mm.set_instance_transform(i, Transform3D(b, pos))
		mm.set_instance_color(i, col)
		mm.set_instance_custom_data(i, Color(0.0, 0.0, clampf(fr / float(frames), 0.0, 0.999), 0.0))


func _spawn_particle(d: Dictionary, trs: Dictionary, xf: Transform3D, model_space: bool, nx: Transform3D) -> Array:
	var w := _track_val(trs.get("width"), cur_t, float(d.width))
	var l := _track_val(trs.get("length"), cur_t, float(d.length))
	var sp := _track_val(trs.get("speed"), cur_t, float(d.speed))
	var lat := deg_to_rad(_track_val(trs.get("lat"), cur_t, float(d.latitude)))
	var var_k := _track_val(trs.get("var"), cur_t, float(d.variation))
	var base := nx if model_space else xf
	# точка вылета: прямоугольник width x length в плоскости эмиттера (WC3 XY -> glTF ZX)
	var off := Vector3(randf_range(-l, l) * 0.5, 0.0, randf_range(-w, w) * 0.5)
	var pos := base * off
	# направление: вверх узла, разброс по широте
	var dir := Vector3.UP
	if lat > 0.0001:
		var th := randf() * lat
		var ph := randf() * TAU
		dir = Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
	dir = (base.basis * dir).normalized()
	var speed := sp * (1.0 + randf_range(-var_k, var_k))
	var sc := 1.0 if model_space else global_transform.basis.get_scale().x
	return [pos, dir * speed * sc, 0.0, sc]


# ------------------------------------------------------------------ ленты
func _add_ribbon(d: Dictionary) -> void:
	var mi := MeshInstance3D.new()
	mi.top_level = true
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var im := ImmediateMesh.new()
	mi.mesh = im
	var tex := str(d.get("tex", ""))
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	if str(d.filter) == "add":
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var rtex := pak_texture(tex)
	if rtex:
		m.albedo_texture = rtex
	mi.material_override = m
	mi.extra_cull_margin = 40.0
	add_child(mi)
	mi.global_transform = Transform3D.IDENTITY
	ribbons.append({"def": d, "mi": mi, "im": im, "segs": [], "acc": 0.0})


func _update_ribbon(r: Dictionary, dt: float) -> void:
	var d: Dictionary = r.def
	var trs: Dictionary = (d.get("tracks", {}) as Dictionary).get(cur, {})
	var xf := global_transform * _node_xf(d.path)
	var vis := _track_val(trs.get("vis"), cur_t, 1.0)
	var above := _track_val(trs.get("above"), cur_t, float(d.above)) * global_transform.basis.get_scale().x
	var below := _track_val(trs.get("below"), cur_t, float(d.below)) * global_transform.basis.get_scale().x
	var alpha := _track_val(trs.get("alpha"), cur_t, float(d.alpha))
	var segs: Array = r.segs
	var life := maxf(0.05, float(d.lifespan))
	for s in segs:
		s[2] += dt
	while not segs.is_empty() and segs[0][2] >= life:
		segs.pop_front()
	if vis > 0.0 and not dying:
		r.acc += float(d.rate) * dt
		if r.acc >= 1.0 or segs.is_empty():
			r.acc = fmod(r.acc, 1.0)
			var up := (xf.basis * Vector3.UP).normalized()
			segs.append([xf.origin + up * above, xf.origin - up * below, 0.0, alpha])
	var im: ImmediateMesh = r.im
	im.clear_surfaces()
	if segs.size() < 2:
		return
	var c: Array = d.color
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var n := segs.size()
	for i in n:
		var s: Array = segs[i]
		var a: float = float(s[3]) * (1.0 - float(s[2]) / life)
		var u := float(i) / float(n - 1)
		im.surface_set_color(Color(c[0], c[1], c[2], a))
		im.surface_set_uv(Vector2(u, 0.0))
		im.surface_add_vertex(s[0])
		im.surface_set_color(Color(c[0], c[1], c[2], a))
		im.surface_set_uv(Vector2(u, 1.0))
		im.surface_add_vertex(s[1])
	im.surface_end()

class_name HeroAssets
## Подхватывает файлы героя из папки res://heroes/<id>/, которые кладёт сам пользователь:
##   model.glb | model.gltf | model.fbx   — 3D-модель (анимации находятся по ключевым словам)
##   portrait.png | .jpg | .jpeg | .webp — портрет
##   icons/q.png … d.png                 — иконки способностей
##   voice/<событие>[_N].ogg|mp3|wav      — фразы: select move attack q w e r d death kill level respawn duel
##   hero.json                            — необязательные настройки (масштаб, поворот, имена анимаций,
##                                          model_height — рост модели, ground — модель уже стоит на земле)
## Если файла нет, используется временная модель и иконки, нарисованные кодом.

const MODEL_EXT := ["glb", "gltf", "fbx"]
const IMAGE_EXT := ["png", "jpg", "jpeg", "webp"]
const AUDIO_EXT := ["ogg", "mp3", "wav"]

const ANIM_KEYS := {
	"Idle": ["idle", "stand", "wait", "breath"],
	"Run": ["run", "walk", "move", "sprint"],
	"Attack": ["attack", "slash", "hit", "strike", "combo"],
	"Cast": ["cast", "spell", "skill", "magic", "channel"],
	"Death": ["death", "die", "dead", "dying"],
}

static var _cache := {}


static func dir(id: String) -> String:
	return "res://heroes/%s/" % id


static func _list(path: String) -> PackedStringArray:
	var out := PackedStringArray()
	if not DirAccess.dir_exists_absolute(path):
		return out
	for f in DirAccess.get_files_at(path):
		var n := f
		if n.ends_with(".import"):
			n = n.trim_suffix(".import")
		elif n.ends_with(".remap"):
			n = n.trim_suffix(".remap")
		if not out.has(n):
			out.append(n)
	return out


static func _find(path: String, base: String, exts: Array) -> String:
	for f in _list(path):
		var e := f.get_extension().to_lower()
		if f.get_basename().to_lower() == base and e in exts:
			return path + f
	return ""


static func model_path(id: String) -> String:
	var p := _find(dir(id), "model", MODEL_EXT)
	return p


static func has_user_model(id: String) -> bool:
	return model_path(id) != "" and ResourceLoader.exists(model_path(id))


static func model_scene(id: String) -> PackedScene:
	var key := "model:" + id
	if _cache.has(key):
		return _cache[key]
	var ps: PackedScene = null
	var p := model_path(id)
	if p != "" and ResourceLoader.exists(p):
		ps = load(p) as PackedScene
	if ps == null:
		ps = load(Data.HEROES[id].fallback_model)
	_cache[key] = ps
	return ps


static func config(id: String) -> Dictionary:
	var key := "cfg:" + id
	if _cache.has(key):
		return _cache[key]
	var cfg := {}
	var p := dir(id) + "hero.json"
	if FileAccess.file_exists(p):
		var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
		if j is Dictionary:
			cfg = j
	_cache[key] = cfg
	return cfg


static func texture(path_no_ext: String) -> Texture2D:
	var key := "tex:" + path_no_ext
	if _cache.has(key):
		return _cache[key]
	var folder := path_no_ext.get_base_dir() + "/"
	var base := path_no_ext.get_file().to_lower()
	var p := _find(folder, base, IMAGE_EXT)
	var t: Texture2D = null
	if p != "" and ResourceLoader.exists(p):
		t = load(p) as Texture2D
	_cache[key] = t
	return t


static func portrait(id: String) -> Texture2D:
	return texture(dir(id) + "portrait")


static func icon(id: String, key: String) -> Texture2D:
	return texture(dir(id) + "icons/" + key)


static func voices(id: String, event: String) -> Array:
	var key := "voice:%s:%s" % [id, event]
	if _cache.has(key):
		return _cache[key]
	var out: Array = []
	var folder := dir(id) + "voice/"
	for f in _list(folder):
		var b := f.get_basename().to_lower()
		var e := f.get_extension().to_lower()
		if not e in AUDIO_EXT:
			continue
		if b == event or b.begins_with(event + "_") or (b.begins_with(event) and b.substr(event.length()).is_valid_int()):
			var s: Variant = load(folder + f) if ResourceLoader.exists(folder + f) else null
			if s is AudioStream:
				out.append(s)
	_cache[key] = out
	return out


static func audio_folder(path: String) -> Array:
	var key := "folder:" + path
	if _cache.has(key):
		return _cache[key]
	var out: Array = []
	for f in _list(path):
		if f.get_extension().to_lower() in AUDIO_EXT and ResourceLoader.exists(path + f):
			var s: Variant = load(path + f)
			if s is AudioStream:
				out.append(s)
	_cache[key] = out
	return out


## Подгоняет модель под нужную высоту и подбирает имена анимаций.
static func fit_model(model: Node3D, id: String, target_height: float) -> Dictionary:
	var cfg := config(id)
	var user := has_user_model(id)
	var info := {"anim_map": {}, "user": user}
	var ap := Unit.find_anim(model)
	if ap and user:
		_fix_tracks(ap)
	if ap:
		var names := ap.get_animation_list()
		var custom: Dictionary = cfg.get("animations", {})
		for k in ANIM_KEYS:
			if custom.has(k) and ap.has_animation(custom[k]):
				info.anim_map[k] = custom[k]
				continue
			if ap.has_animation(k):
				info.anim_map[k] = k
				continue
			for n in names:
				var low := String(n).to_lower()
				for kw in ANIM_KEYS[k]:
					if low.contains(kw):
						info.anim_map[k] = n
						break
				if info.anim_map.has(k):
					break
	if user:
		var aabb := _aabb(model, Transform3D.IDENTITY)
		var h := maxf(aabb.size.y, 0.01)
		# model_height — рост героя в позе стойки (модели из карты: оружие и крылья не в счёт)
		if cfg.has("model_height"):
			h = maxf(float(cfg.model_height), 0.01)
		var k := target_height / h * float(cfg.get("scale", 1.0))
		model.scale = Vector3.ONE * k
		# ground: начало координат модели уже стоит на земле (как в Warcraft 3)
		model.position.y = 0.0 if cfg.get("ground", false) else -aabb.position.y * k
		model.rotation_degrees.y = float(cfg.get("rotate_y", 0.0))
	else:
		model.scale = Vector3.ONE * (target_height / 1.95)
	return info


## Импорт glTF кладёт меши со скелетом внутрь Skeleton3D, а дорожки видимости частей
## (показать оружие или эффект только в нужной анимации) остаются с путём от корня — чиним пути.
static func _fix_tracks(ap: AnimationPlayer) -> void:
	var rn := ap.get_node_or_null(ap.root_node)
	if rn == null:
		return
	for an in ap.get_animation_list():
		var a := ap.get_animation(an)
		for t in a.get_track_count():
			if a.track_get_type(t) != Animation.TYPE_VALUE:
				continue
			var p := str(a.track_get_path(t))
			var node_part := p.get_slice(":", 0)
			if rn.get_node_or_null(NodePath(node_part)) != null:
				continue
			var found := rn.find_child(node_part.get_file(), true, false)
			if found:
				a.track_set_path(t, NodePath(str(rn.get_path_to(found)) + ":" + p.get_slice(":", 1)))


static func _aabb(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is VisualInstance3D:
		var a := t * (n as VisualInstance3D).get_aabb()
		out = a
		first = false
	for c in n.get_children():
		var ca := _aabb(c, t)
		if ca.size != Vector3.ZERO:
			if first:
				out = ca
				first = false
			else:
				out = out.merge(ca)
	return out

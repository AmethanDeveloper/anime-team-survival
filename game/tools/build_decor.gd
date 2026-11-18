extends SceneTree
## Сборка декораций Quaternius (CC0) для карты: модели природы и дома из модульного набора деревни
## склеиваются в готовые сетки (по одной поверхности на материал, с LOD) и сохраняются в assets/quaternius/mesh.
## Исходники (glTF) в проект не входят — нужны только для пересборки:
##   godot --headless --path game --script res://tools/build_decor.gd -- --nat=<Stylized Nature MegaKit/glTF> --vil=<Medieval Village MegaKit/glTF>

const OUT := "res://assets/quaternius/"
const TEX := OUT + "textures/"

## Модели природы: имя → [материалы-листва (alpha), масштаб]
const NATURE := [
	"CommonTree_1", "CommonTree_2", "CommonTree_3", "CommonTree_4", "CommonTree_5",
	"Pine_1", "Pine_2", "Pine_3", "Pine_4", "Pine_5",
	"TwistedTree_1", "TwistedTree_2", "TwistedTree_3", "TwistedTree_4", "TwistedTree_5",
	"DeadTree_1", "DeadTree_2", "DeadTree_3", "DeadTree_4", "DeadTree_5",
	"Bush_Common", "Bush_Common_Flowers",
	"Grass_Common_Short", "Grass_Common_Tall", "Grass_Wispy_Short", "Grass_Wispy_Tall",
	"Flower_3_Group", "Flower_4_Group", "Flower_3_Single", "Flower_4_Single",
	"Clover_1", "Clover_2", "Fern_1", "Plant_1", "Plant_1_Big", "Plant_7", "Plant_7_Big",
	"Mushroom_Common", "Mushroom_Laetiporus",
	"Rock_Medium_1", "Rock_Medium_2", "Rock_Medium_3",
	"Pebble_Round_1", "Pebble_Round_2", "Pebble_Round_3", "Pebble_Square_1", "Pebble_Square_2",
	"RockPath_Round_Small_1", "RockPath_Round_Small_2", "RockPath_Round_Small_3", "RockPath_Round_Wide",
	"RockPath_Square_Wide", "RockPath_Square_Small_1",
]
## Пропсы деревни, которые идут как есть
const VILLAGE_PROPS := ["Prop_Crate", "Prop_Wagon", "Prop_WoodenFence_Single", "Prop_WoodenFence_Extension1",
	"Prop_MetalFence_Ornament", "Prop_Chimney", "Prop_Vine5", "Prop_Vine6", "Prop_Brick1", "Prop_Brick2",
	"Wall_UnevenBrick_Straight", "Wall_UnevenBrick_Window_Wide_Round", "Wall_Arch", "Stairs_Exterior_Straight"]

## Материалы glTF → [шейдер, текстура цвета, нормали, шероховатость, AO из цвета вершин, ветер, оттенок]
const MATS := {
	"Bark_NormalTree": ["solid", "Bark_NormalTree", "Bark_NormalTree_Normal", 0.9, 0.7, 0.0],
	"Bark_DeadTree": ["solid", "Bark_DeadTree", "Bark_DeadTree_Normal", 0.9, 0.7, 0.0],
	"Bark_TwistedTree": ["solid", "Bark_TwistedTree", "Bark_TwistedTree_Normal", 0.9, 0.7, 0.0],
	"Leaves_NormalTree": ["foliage", "Leaves_NormalTree_C", "", 0.8, 0.0, 0.02],
	"Leaves_TwistedTree": ["foliage", "Leaves_TwistedTree_C", "", 0.8, 0.0, 0.012],
	"Leaves_Pine": ["foliage", "Leaf_Pine_C", "", 0.8, 0.0, 0.015],
	"Leaves": ["foliage", "Leaves", "", 0.8, 0.0, 0.25],
	"Flowers": ["foliage", "Flowers", "", 0.7, 0.0, 0.3],
	"Grass": ["foliage", "Grass", "", 0.8, 0.55, 0.9],
	"Mushrooms": ["solid", "Mushrooms", "", 0.6, 0.0, 0.0],
	"PathRocks": ["solid", "PathRocks_Diffuse", "", 0.85, 0.0, 0.0],
	"Rocks": ["solid", "Rocks_Diffuse", "", 0.9, 0.0, 0.0],
	"MI_WoodTrim": ["solid", "T_WoodTrim_BaseColor", "T_WoodTrim_Normal", 0.8, 0.0, 0.0],
	"MI_WoodTrim_Wear": ["solid", "T_WoodTrim_BaseColor", "T_WoodTrim_Normal", 0.85, 0.0, 0.0],
	"MI_RockTrim": ["solid", "T_RockTrim_BaseColor", "T_RockTrim_Normal", 0.9, 0.0, 0.0],
	"MI_Brick": ["solid", "T_Brick_BaseColor", "T_Brick_Normal", 0.9, 0.0, 0.0],
	"MI_RedBrick": ["solid", "T_RedBrick_BaseColor", "T_Brick_Normal", 0.9, 0.0, 0.0],
	"MI_UnevenBrick": ["solid", "T_UnevenBrick_BaseColor", "T_UnevenBrick_Normal", 0.9, 0.0, 0.0],
	"MI_Plaster": ["solid", "T_Plaster_BaseColor", "T_Plaster_Normal", 0.9, 0.0, 0.0],
	"MI_RoundTiles": ["solid", "T_RoundTiles_BaseColor", "T_RoundTiles_Normal", 0.75, 0.0, 0.0],
	"MI_Vine": ["foliage", "T_VineLeaf", "", 0.8, 0.0, 0.1],
	"MI_MetalOrnaments": ["solid", "", "", 0.45, 0.0, 0.0],
	"MI_WindowGlass": ["solid", "", "", 0.15, 0.0, 0.0],
}
## Цвет материалов без текстуры
const FLAT := {"MI_MetalOrnaments": Color(0.16, 0.16, 0.18), "MI_WindowGlass": Color(0.95, 0.72, 0.38)}

var nat_dir := ""
var vil_dir := ""
var only := ""
var mats := {}
var scenes := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--nat="):
			nat_dir = a.substr(6)
		elif a.begins_with("--vil="):
			vil_dir = a.substr(6)
		elif a.begins_with("--only="):
			only = a.substr(7)
	_build.call_deferred()


func _build() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "mesh"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "mat"))
	var n := 0
	if nat_dir != "":
		for name: String in NATURE:
			if only != "" and not name.contains(only):
				continue
			var parts := _parts(nat_dir.path_join(name + ".gltf"), Transform3D.IDENTITY)
			_save(name, parts)
			n += 1
	if vil_dir != "":
		for name: String in VILLAGE_PROPS:
			if only != "" and not name.contains(only):
				continue
			_save(name, _parts(vil_dir.path_join(name + ".gltf"), Transform3D.IDENTITY))
			n += 1
		for hv in _houses():
			if only != "" and not String(hv[0]).contains(only):
				continue
			var parts: Array = []
			for p in hv[1]:
				parts.append_array(_parts(vil_dir.path_join(String(p[0]) + ".gltf"), p[1]))
			_save(hv[0], parts)
			n += 1
	print("DECOR built ", n)
	quit()


## Сетки glTF с их трансформами: [[Mesh, Transform3D]]
func _parts(path: String, xf: Transform3D) -> Array:
	var root: Node = scenes.get(path)
	if root == null:
		var doc := GLTFDocument.new()
		var st := GLTFState.new()
		var err := doc.append_from_file(path, st)
		if err != OK:
			push_error("Не загрузился " + path)
			return []
		root = doc.generate_scene(st)
		scenes[path] = root
	var out: Array = []
	_collect(root, xf, out, true)
	return out


func _collect(n: Node, xf: Transform3D, out: Array, is_root := false) -> void:
	var t := xf
	if n is Node3D and not is_root:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		out.append([(n as MeshInstance3D).mesh, t])
	for c in n.get_children():
		_collect(c, t, out)


func _mat(name: String) -> Material:
	if mats.has(name):
		return mats[name]
	var d: Array = MATS.get(name, ["solid", "", "", 0.85, 0.0, 0.0])
	if not MATS.has(name):
		push_warning("Нет описания материала " + name)
	var m := ShaderMaterial.new()
	m.shader = load(OUT + "decor_%s.gdshader" % d[0])
	if d[1] != "":
		m.set_shader_parameter("albedo_tex", load(TEX + d[1] + ".png"))
	else:
		var img := Image.create(4, 4, false, Image.FORMAT_RGB8)
		img.fill(Color.WHITE)
		m.set_shader_parameter("albedo_tex", ImageTexture.create_from_image(img))
		m.set_shader_parameter("tint", FLAT.get(name, Color.WHITE))
	if d[2] != "":
		m.set_shader_parameter("normal_tex", load(TEX + d[2] + ".png"))
		m.set_shader_parameter("use_normal", true)
	m.set_shader_parameter("roughness", d[3])
	m.set_shader_parameter("ao_amount", d[4])
	m.set_shader_parameter("wind", d[5])
	if name == "Leaves_Pine":
		m.set_shader_parameter("snow_bias", -0.05)
	var path := OUT + "mat/" + name + ".tres"
	ResourceSaver.save(m, path)
	m.take_over_path(path)
	mats[name] = m
	return m


## Склейка частей: поверхности с одним материалом объединяются, касательные и LOD строятся заново.
func _save(name: String, parts: Array) -> void:
	var groups := {}   # материал → {v, n, uv, c, idx}
	var order: Array = []
	for pr in parts:
		var mesh: Mesh = pr[0]
		var xf: Transform3D = pr[1]
		var flip := xf.basis.determinant() < 0.0
		for s in mesh.get_surface_count():
			var mat := mesh.surface_get_material(s)
			var key := mat.resource_name if mat else "default"
			if key == "":
				key = "default"
			if not groups.has(key):
				groups[key] = {"v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array(),
					"c": PackedColorArray(), "i": PackedInt32Array()}
				order.append(key)
			var g: Dictionary = groups[key]
			var arr := mesh.surface_get_arrays(s)
			var vv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var nn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL] if arr[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
			var uu: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV] if arr[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
			var cc: PackedColorArray = arr[Mesh.ARRAY_COLOR] if arr[Mesh.ARRAY_COLOR] != null else PackedColorArray()
			var ii: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var base: int = (g.v as PackedVector3Array).size()
			var nb := xf.basis.inverse().transposed()
			for k in vv.size():
				g.v.append(xf * vv[k])
				g.n.append((nb * (nn[k] if k < nn.size() else Vector3.UP)).normalized())
				g.uv.append(uu[k] if k < uu.size() else Vector2.ZERO)
				g.c.append(cc[k] if k < cc.size() else Color.WHITE)
			if ii.is_empty():
				for k in vv.size():
					ii.append(k)
			for k in range(0, ii.size(), 3):
				if flip:
					g.i.append(base + ii[k])
					g.i.append(base + ii[k + 2])
					g.i.append(base + ii[k + 1])
				else:
					g.i.append(base + ii[k])
					g.i.append(base + ii[k + 1])
					g.i.append(base + ii[k + 2])
	var im := ImporterMesh.new()
	for key in order:
		var g: Dictionary = groups[key]
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = g.v
		a[Mesh.ARRAY_NORMAL] = g.n
		a[Mesh.ARRAY_TEX_UV] = g.uv
		a[Mesh.ARRAY_COLOR] = g.c
		a[Mesh.ARRAY_INDEX] = g.i
		var st := SurfaceTool.new()
		st.create_from_arrays(a)
		st.generate_tangents()
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays(), [], {}, _mat(key), key)
	im.generate_lods(25.0, 60.0, [])
	var am := im.get_mesh()
	am.resource_name = name
	var err := ResourceSaver.save(am, OUT + "mesh/" + name + ".res", ResourceSaver.FLAG_COMPRESS)
	var aabb := am.get_aabb()
	print("DECOR %s surf=%d size=%s err=%d" % [name, am.get_surface_count(), aabb.size, err])


# ----------------------------------------------------------------- дома из модулей
const STORY := 3.0


static func _xf(x: float, y: float, z: float, rot_deg := 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, deg_to_rad(rot_deg)), Vector3(x, y, z))


## Стены одного этажа: w модулей по x, l по z (модуль 2 м); двери на фронте (+z) первого этажа.
func _story(out: Array, w: int, l: int, y: float, style: String, door: bool, win_every := 2) -> void:
	var hw := float(w)
	var hl := float(l)
	# стороны: [центр стороны, поворот, число модулей, ось вдоль]
	var sides := [
		[Vector3(0, 0, hl), 0.0, w, Vector3.RIGHT],
		[Vector3(0, 0, -hl), 180.0, w, Vector3.LEFT],
		[Vector3(hw, 0, 0), 90.0, l, Vector3.BACK],
		[Vector3(-hw, 0, 0), -90.0, l, Vector3.FORWARD],
	]
	for si in sides.size():
		var sd: Array = sides[si]
		var cnt: int = sd[2]
		for i in cnt:
			var off := -float(cnt) + 1.0 + 2.0 * i
			var p: Vector3 = sd[0] + (sd[3] as Vector3) * off
			var piece := "Wall_%s_Straight" % style
			var win := (i + si) % win_every == 1 or (cnt == 1)
			if door and si == 0 and i == cnt / 2:
				piece = "Wall_%s_Door_Round" % style
				out.append(["Door_1_Round", _xf(p.x, y, p.z, sd[1]) * _xf(-0.53, 0.0, -0.05)])
			elif win:
				piece = "Wall_%s_Window_Wide_Round" % style
				out.append(["Window_Wide_Round1", _xf(p.x, y, p.z, sd[1])])
				out.append(["WindowShutters_Wide_Round_Open", _xf(p.x, y, p.z, sd[1])])
			out.append([piece, _xf(p.x, y, p.z, sd[1])])
	for cx in [-hw, hw]:
		for cz in [-hl, hl]:
			out.append(["Corner_Exterior_Wood", _xf(cx, y, cz)])


func _house(w: int, l: int, styles: Array, roof: String, gable: String, chimney: bool) -> Array:
	var out: Array = []
	for k in styles.size():
		_story(out, w, l, k * STORY, styles[k], k == 0)
	var top := styles.size() * STORY
	out.append([roof, _xf(0, top, 0)])
	out.append([gable, _xf(0, top, float(l))])
	out.append([gable, _xf(0, top, -float(l), 180.0)])
	if chimney:
		out.append(["Prop_Chimney", _xf(float(w) - 1.0, top + 0.6, float(l) * 0.35)])
	return out


func _houses() -> Array:
	return [
		["House_A", _house(3, 4, ["UnevenBrick", "Plaster"], "Roof_RoundTiles_6x8", "Roof_Front_Brick6", true)],
		["House_B", _house(2, 3, ["Plaster"], "Roof_RoundTiles_4x6", "Roof_Front_Brick4", false)],
		["House_C", _house(3, 3, ["UnevenBrick", "UnevenBrick"], "Roof_RoundTiles_6x6", "Roof_Front_Brick6", true)],
		["Watchtower", _tower()],
	]


func _tower() -> Array:
	var out: Array = []
	for k in 3:
		_story(out, 2, 2, k * STORY, "UnevenBrick", k == 0, 3)
	out.append(["Roof_Tower_RoundTiles", _xf(0, 3 * STORY, 0)])
	return out

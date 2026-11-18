extends SceneTree
## Снимок собранных декораций: godot --path game --script res://tools/decor_preview.gd -- --names=A,B --shot=out.png [--snow=0.8] [--cam=x,y,z]

var names: Array = []
var shot := "/tmp/decor.png"
var snow := 0.0
var cam_pos := Vector3.INF
var look := Vector3.INF
var frames := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--names="):
			names = a.substr(8).split(",")
		elif a.begins_with("--shot="):
			shot = a.substr(7)
		elif a.begins_with("--snow="):
			snow = float(a.substr(7))
		elif a.begins_with("--cam="):
			var p := a.substr(6).split(",")
			cam_pos = Vector3(float(p[0]), float(p[1]), float(p[2]))
		elif a.begins_with("--look="):
			var p := a.substr(7).split(",")
			look = Vector3(float(p[0]), float(p[1]), float(p[2]))
	_build.call_deferred()


func _build() -> void:
	var root := Node3D.new()
	get_root().add_child(root)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.65, 0.8)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.65, 0.75)
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
	sun.shadow_enabled = true
	root.add_child(sun)
	var gr := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	gr.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.75, 0.8, 0.85)
	gr.material_override = gm
	root.add_child(gr)
	var x := 0.0
	var maxh := 0.0
	for n: String in names:
		var m: Mesh = load("res://assets/quaternius/mesh/%s.res" % n)
		if m == null:
			continue
		var ab := m.get_aabb()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = m
		mm.instance_count = 1
		x += ab.size.x * 0.5 + 0.5
		mm.set_instance_transform(0, Transform3D(Basis.IDENTITY, Vector3(x - ab.get_center().x, 0, 0)))
		mm.set_instance_custom_data(0, Color(snow, 0.0, 0.3, 0.0))
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		root.add_child(mi)
		x += ab.size.x * 0.5 + 0.5
		maxh = maxf(maxh, ab.size.y)
	var cam := Camera3D.new()
	cam.fov = 40.0
	root.add_child(cam)
	var c := Vector3(x * 0.5, maxh * 0.45, 0)
	cam.position = cam_pos if cam_pos != Vector3.INF else c + Vector3(0, maxh * 0.5 + x * 0.25, maxf(x, maxh) * 1.25 + 2.0)
	cam.look_at(look if look != Vector3.INF else c)
	cam.current = true


func _process(_d: float) -> bool:
	frames += 1
	if frames == 8:
		var img := get_root().get_texture().get_image()
		img.save_png(shot)
		print("SHOT ", shot)
		quit()
	return false

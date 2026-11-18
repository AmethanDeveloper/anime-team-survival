extends SceneTree
## Предпросмотр эффектов: godot --path . -s res://tools/vfx_preview.gd -- --shot=out.png --t=0.4 [--only=имя]
## Сетка эффектов на земле, камера как в игре, снимок через t секунд после запуска.

var shot := "/tmp/vfx.png"
var t_shot := 0.5
var only := ""
var color := Color(-1, 0, 0)


func _initialize() -> void:
	_build.call_deferred()


func _build() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			shot = a.split("=")[1]
		elif a.begins_with("--t="):
			t_shot = float(a.split("=")[1])
		elif a.begins_with("--only="):
			only = a.split("=")[1]
		elif a.begins_with("--color="):
			color = Color(a.split("=")[1])
	var root3 := Node3D.new()
	get_root().add_child(root3)
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.15, 0.2)
	env.ambient_light_color = Color(0.6, 0.65, 0.75)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env_node.environment = env
	root3.add_child(env_node)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	root3.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	ground.mesh = pm
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.25, 0.33, 0.22)
	ground.material_override = gmat
	root3.add_child(ground)
	var cam := Camera3D.new()
	root3.add_child(cam)
	var list: Array = VfxLib.KINDS.keys()
	if only != "":
		list = only.split(",")
	var cols := mini(4, list.size())
	var rows := ceili(list.size() / float(cols))
	var step := 5.0
	for i in list.size():
		var x := (i % cols - (cols - 1) * 0.5) * step
		var z := (int(i / cols) - (rows - 1) * 0.5) * step
		var c: Color = color if color.r >= 0.0 else Color.from_hsv(float(i) / list.size(), 0.75, 1.0)
		var p := Vector3(x, 0, z)
		VfxLib.spawn(root3, str(list[i]), p, c, 1.0, Vector3(1, 0, 0))
		var lbl := Label3D.new()
		lbl.text = str(list[i])
		lbl.font_size = 64
		lbl.pixel_size = 0.01
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.position = p + Vector3(0, 0.2, 2.6)
		root3.add_child(lbl)
	var span := maxf(cols, rows) * step
	cam.position = Vector3(0, span * 0.62, span * 0.5)
	cam.look_at(Vector3.ZERO)
	cam.fov = 55.0
	await create_timer(t_shot).timeout
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(shot)
	print("SHOT ", shot)
	quit()

extends SceneTree
## Снимок моделей карты (W3Model) в ряд: godot --path game --script res://tools/model_preview.gd -- --keys=a|b|c --shot=out.png [--anim=stand] [--t=1.0]
## Рост каждой модели приводится к 3 м (--fit=0 — родной размер), подписи — номера по порядку.

var keys: Array = []
var shot := "/tmp/models.png"
var anim := "stand"
var t_wait := 1.0
var fit := true
var frames := 0
var cam: Camera3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--keys="):
			keys = a.substr(7).split("|")
		elif a.begins_with("--shot="):
			shot = a.substr(7)
		elif a.begins_with("--anim="):
			anim = a.substr(7)
		elif a.begins_with("--t="):
			t_wait = float(a.substr(4))
		elif a == "--fit=0":
			fit = false
	_build.call_deferred()


func _build() -> void:
	var root := Node3D.new()
	get_root().add_child(root)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.32, 0.38, 0.48)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.7, 0.78)
	e.ambient_light_energy = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	root.add_child(sun)
	var gr := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	gr.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.45, 0.5, 0.45)
	gr.material_override = gm
	root.add_child(gr)
	var x := 0.0
	var step := 4.0
	var maxh := 3.0
	for k: String in keys:
		var m := W3Model.create(k)
		if m.fallback or m.scene_root == null:
			print("MISSING ", k)
			x += step
			continue
		var bb := HeroAssets._aabb(m.scene_root, Transform3D.IDENTITY)
		var s := 3.0 / maxf(bb.size.y, 0.01) if fit else W3Runtime.FX_K
		m.scale = Vector3.ONE * s
		root.add_child(m)
		m.position = Vector3(x, 0, 0)
		m.rotation.y = deg_to_rad(-30.0)
		m.play(anim)
		maxh = maxf(maxh, bb.size.y * s)
		print("MODEL %d %s h=%.2f w=%.2f anims=%s" % [keys.find(k), k, bb.size.y, bb.size.x, str(m.anim_names().slice(0, 6))])
		x += step if fit else maxf(step, bb.size.x * s + 1.0)
	cam = Camera3D.new()
	root.add_child(cam)
	var cx := (x - step) * 0.5
	var w := maxf(x, 6.0)
	cam.fov = 40.0
	cam.position = Vector3(cx, maxh * 0.8 + w * 0.08, w * 0.62 + maxh * 0.8)
	cam.look_at(Vector3(cx, maxh * 0.45, 0))


func _process(_d: float) -> bool:
	frames += 1
	if frames == int(t_wait * 30.0) + 5:
		var img := get_root().get_texture().get_image()
		img.save_png(shot)
		print("SHOT ", shot)
		quit()
	return false

extends SceneTree
## Снимок одной модели с прозрачным фоном (для портретов и иконок):
## godot --path game --script res://tools/still_render.gd -- --hero=madara | --w3=<путь модели> --out=a.png
##   [--size=640x480] [--anim=stand] [--t=0.5] [--frame=upper|full|face] [--yaw=-20] [--k=1.0]

var out := "/tmp/still.png"
var hero := ""
var w3 := ""
var size := Vector2i(640, 480)
var anim := ""
var t_at := 0.4
var frame := "upper"
var yaw := -20.0
var k := 1.0
var frames := 0
var model: Node3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		match kv[0]:
			"--out":
				out = kv[1]
			"--hero":
				hero = kv[1]
			"--w3":
				w3 = kv[1]
			"--size":
				var p := kv[1].split("x")
				size = Vector2i(int(p[0]), int(p[1]))
			"--anim":
				anim = kv[1]
			"--t":
				t_at = float(kv[1])
			"--frame":
				frame = kv[1]
			"--yaw":
				yaw = float(kv[1])
			"--k":
				k = float(kv[1])
	get_root().transparent_bg = true
	get_root().size = size
	_build.call_deferred()


func _build() -> void:
	var root := Node3D.new()
	get_root().add_child(root)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.72, 0.78)
	e.ambient_light_energy = 0.75
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35.0, -35.0, 0.0)
	sun.light_energy = 1.2
	root.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-10.0, 150.0, 0.0)
	fill.light_energy = 0.45
	fill.light_color = Color(1.0, 0.55, 0.45)
	root.add_child(fill)
	var h := 2.7
	if hero != "":
		model = HeroAssets.model_scene(hero).instantiate()
		var info := HeroAssets.fit_model(model, hero, 2.7)
		root.add_child(model)
		var ap := Unit.find_anim(model)
		if ap:
			var n: String = info.anim_map.get(anim if anim != "" else "Idle", "")
			if n == "" and anim != "":
				n = W3Model.pick_anim(Array(ap.get_animation_list()), anim)
			if n != "":
				ap.play(n)
				ap.seek(t_at, true)
				ap.pause()
	else:
		var wm := W3Model.create(w3)
		root.add_child(wm)
		var hh := maxf(NcdFx.stand_height(wm), 0.05)
		wm.scale = Vector3.ONE * (2.7 * k / hh)
		h = 2.7 * k
		if anim != "":
			wm.play(anim)
		model = wm
	model.rotation_degrees.y = yaw
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.fov = 32.0
	match frame:
		"face":
			cam.position = Vector3(0, h * 0.86, h * 0.42)
			cam.look_at(Vector3(0, h * 0.86, 0))
		"full":
			cam.position = Vector3(0, h * 0.55, h * 2.1)
			cam.look_at(Vector3(0, h * 0.48, 0))
		_:
			cam.position = Vector3(0, h * 0.78, h * 0.95)
			cam.look_at(Vector3(0, h * 0.7, 0))


func _process(_d: float) -> bool:
	frames += 1
	if frames == int(t_at * 30.0) + 8:
		var img := get_root().get_texture().get_image()
		img.save_png(out)
		print("SHOT ", out)
		quit()
	return false

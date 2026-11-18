class_name Gfx
## Качество графики (меню паузы): Низкое / Среднее / Высокое и счётчик кадров. Хранится в user://settings.cfg.
## Низкое — без теней, SSAO и сглаживания, картинка рисуется в 75% разрешения, меньше частиц и мелкого декора.

const NAMES := ["Низкое", "Среднее", "Высокое"]
const PATH := "user://settings.cfg"

static var quality := 1
static var show_fps := true
static var _loaded := false


static func load_cfg() -> void:
	if _loaded:
		return
	_loaded = true
	var c := ConfigFile.new()
	if c.load(PATH) == OK:
		quality = clampi(int(c.get_value("gfx", "quality", 1)), 0, 2)
		show_fps = bool(c.get_value("gfx", "show_fps", true))


static func save_cfg() -> void:
	var c := ConfigFile.new()
	c.load(PATH)
	c.set_value("gfx", "quality", quality)
	c.set_value("gfx", "show_fps", show_fps)
	c.save(PATH)


## Применить к текущей сцене: окружение, солнце, окно, частицы, декор.
static func apply(tree: SceneTree) -> void:
	load_cfg()
	var vp := tree.root.get_viewport()
	var env := World.g_env
	if env:
		env.ssao_enabled = quality >= 2
		env.glow_enabled = quality >= 1
		env.fog_enabled = quality >= 1
	vp.msaa_3d = Viewport.MSAA_2X if quality >= 2 else Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if quality == 1 else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = 0.75 if quality == 0 else 1.0
	vp.mesh_lod_threshold = [4.0, 2.0, 1.0][quality]
	RenderingServer.directional_soft_shadow_filter_set_quality([RenderingServer.SHADOW_QUALITY_HARD,
		RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_HIGH][quality])
	RenderingServer.directional_shadow_atlas_set_size([1024, 2048, 4096][quality], true)
	for n in tree.root.find_children("*", "DirectionalLight3D", true, false):
		var sun := n as DirectionalLight3D
		sun.shadow_enabled = quality >= 1
		sun.directional_shadow_max_distance = [40.0, 80.0, 140.0][quality]
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL if quality == 1 \
			else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	W3Model.particle_budget = [500, 1300, 2600][quality]
	VfxLib.max_live = [16, 32, 60][quality]
	VfxLib.lights = quality >= 2
	# мелкий декор (трава, цветы, мелкие камни) — видно ближе на низком качестве
	for n in tree.root.find_children("*", "MultiMeshInstance3D", true, false):
		var mi := n as MultiMeshInstance3D
		if mi.has_meta("decor_small"):
			mi.visible = quality >= 1
			mi.visibility_range_end = [0.0, 90.0, 140.0][quality]
		elif mi.has_meta("decor"):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if quality >= 2 \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

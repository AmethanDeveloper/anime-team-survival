class_name Hud
extends CanvasLayer
## Интерфейс: выбор героя, панель героя, миникарта, лавка с крафтом и складом, счёт, меню, сообщения.

const BG := Color(0.04, 0.05, 0.1, 0.9)
const BORDER := Color(1.0, 1.0, 1.0, 0.22)
## Цвета консоли ATS (фиолетовый мрамор с розовым свечением)
const ACC := Color(1.0, 0.82, 0.48)
const ACC_HI := Color(1.0, 0.9, 0.65)
const NAME_COL := Color(1.0, 1.0, 1.0)
const TEXT := Color(0.95, 0.93, 0.88)
const DIM := Color(0.66, 0.69, 0.78)
const GOLD := Color(1.0, 0.8, 0.3)
const HP_COL := Color(0.3, 0.86, 0.36)
const MP_COL := Color(0.3, 0.55, 1.0)
const XP_COL := Color(0.75, 0.55, 1.0)
const KEYS := ["Q", "W", "E", "R", "D", "T"]
const CLS_COLORS := {"D": Color(0.7, 0.7, 0.72), "D+": Color(0.75, 0.8, 0.75), "C": Color(0.5, 0.85, 0.55),
	"C+": Color(0.45, 0.95, 0.6), "B": Color(0.45, 0.65, 1.0), "B+": Color(0.5, 0.75, 1.0), "A": Color(0.8, 0.5, 1.0),
	"A+": Color(0.9, 0.55, 1.0), "S": Color(1.0, 0.75, 0.3), "S+": Color(1.0, 0.45, 0.3), "Ex": Color(1.0, 0.3, 0.4)}

var theme_res: Theme
## Шрифты интерфейса: Exo 2 — цифры и подписи, Philosopher — имена, заголовки, кнопки (оба — OFL, с кириллицей)
static var font_ui: Font
static var font_title: Font
var root: Control
var overlay: Overlay
var minimap: Minimap
var game_ui: Control
var flash_rect: ColorRect

var lbl_wave: Label
var lbl_time: Label
var lbl_duel: Label
var lbl_forest: Label
var chan_box: Control
var chan_bar: ColorRect
var chan_lbl: Label
## Прокачка: строка над панелью героя — очки навыков, «+ атрибуты», выбор таланта
var lvl_row: HBoxContainer
var lvl_lbl: Label
var lvl_stat_btn: Button
var lvl_tal_btns: Array[Button] = []
var lbl_fps: Label
var lbl_kills: Label
var _fps_t := 0.0
var team_rows: Array = []

var portrait_holder: Control
var lbl_name: Label
var lbl_level: Label
var hp_bar: Bar
var mp_bar: Bar
var xp_bar: Bar
var lbl_stats: Label
var lbl_buffs: RichTextLabel
var lbl_gold: Label
var lbl_respawn: Label
var ability_buttons: Array = []
var item_slots: Array = []
var info_label: Label
var info_panel: PanelContainer
## Осмотр (как в Warcraft 3 и Dota): выбранный чужой юнит показывается на нижней панели вместо своего героя
var insp_face: TextureRect
var insp_badge: Label
var _view_last: Unit = null
var console_edit: LineEdit

var announce_box: VBoxContainer
var feed_box: VBoxContainer
var error_label: Label
var error_tween: Tween

var shop_panel: PanelContainer
var shop_status: Label
var courier_status: Label
var shop_tabs: TabContainer
var shop_cards: Array = []
var shop_inv: Array = []
var scores_panel: PanelContainer
var scores_grid: GridContainer
var menu_panel: PanelContainer
var select_layer: Control
var end_layer: Control
var float_texts: Array = []
## Подсветка только что собранных предметов: id -> оставшееся время
var craft_flash := {}
var select_viewports: Array = []
var refresh_t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	_setup_fonts()
	_build_theme()
	root = Control.new()
	root.theme = theme_res
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	overlay = Overlay.new()
	overlay.hud = self
	root.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

	game_ui = Control.new()
	game_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(game_ui)
	game_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game_ui.visible = false

	_build_top()
	_build_teams()
	_build_bottom()
	_build_minimap()
	_build_info()
	_build_messages()
	_build_shop()
	_build_scores()
	_build_menu()

	flash_rect = ColorRect.new()
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash_rect.color = Color(0, 0, 0, 0)
	root.add_child(flash_rect)
	flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


# ----------------------------------------------------------------- тема
func _sb(bg: Color, border := BORDER, radius := 6, bw := 1, pad := 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad
	s.content_margin_bottom = pad
	s.anti_aliasing = true
	return s


static func _setup_fonts() -> void:
	if font_ui != null:
		return
	var exo: Font = load("res://ui/fonts/Exo2.ttf")
	var fv := FontVariation.new()
	fv.base_font = exo
	fv.variation_opentype = {"wght": 600}
	font_ui = fv
	# заголовки и имена — жирный Exo 2 с наклоном (как в интерфейсах аниме-игр)
	var ft := FontVariation.new()
	ft.base_font = exo
	ft.variation_opentype = {"wght": 800}
	ft.variation_transform = Transform2D(Vector2(1, 0), Vector2(-0.18, 1), Vector2.ZERO)
	font_title = ft
	ThemeDB.fallback_font = font_ui


## Тёмное «стекло» с тонкой светлой линией; skew — скос панели (параллелограмм).
static func glass(pad := 10.0, skew := 0.0, border := BORDER, bg := BG) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 8
	sb.skew = Vector2(skew, 0)
	sb.anti_aliasing = true
	sb.content_margin_left = pad + 2 + absf(skew) * 20.0
	sb.content_margin_right = pad + 2 + absf(skew) * 20.0
	sb.content_margin_top = pad
	sb.content_margin_bottom = pad
	return sb


## Стили окон и кнопок (имя осталось от прежних рамок): frame — стекло, button* — кнопки с золотым акцентом.
static func ats_box(file := "frame", pad := 10.0) -> StyleBox:
	match file:
		"button":
			return glass(pad, 0.0, Color(ACC, 0.75), Color(0.16, 0.13, 0.08, 0.95))
		"button_hover":
			return glass(pad, 0.0, ACC_HI, Color(0.3, 0.23, 0.1, 0.97))
		"button_pressed":
			return glass(pad, 0.0, ACC, Color(0.4, 0.3, 0.12, 0.97))
		"button_disabled":
			return glass(pad, 0.0, Color(1, 1, 1, 0.15), Color(0.08, 0.09, 0.13, 0.9))
	return glass(pad)


func _build_theme() -> void:
	theme_res = Theme.new()
	theme_res.default_font = font_ui
	theme_res.default_font_size = 16
	theme_res.set_stylebox("panel", "PanelContainer", ats_box())
	theme_res.set_stylebox("panel", "Panel", ats_box())
	theme_res.set_color("font_color", "Label", TEXT)
	theme_res.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.85))
	theme_res.set_font_size("font_size", "Button", 16)
	theme_res.set_stylebox("normal", "Button", ats_box("button", 7))
	theme_res.set_stylebox("hover", "Button", ats_box("button_hover", 7))
	theme_res.set_stylebox("pressed", "Button", ats_box("button_pressed", 7))
	theme_res.set_stylebox("disabled", "Button", ats_box("button_disabled", 7))
	theme_res.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	theme_res.set_color("font_color", "Button", Color(0.98, 0.92, 1.0))
	theme_res.set_color("font_hover_color", "Button", Color(1, 1, 1))
	theme_res.set_color("font_pressed_color", "Button", ACC_HI)
	theme_res.set_color("font_disabled_color", "Button", Color(0.6, 0.55, 0.65))
	theme_res.set_color("font_outline_color", "Button", Color(0, 0, 0, 0.9))
	theme_res.set_constant("outline_size", "Button", 3)
	theme_res.set_stylebox("panel", "TooltipPanel", ats_box("frame", 9))
	theme_res.set_color("font_color", "TooltipLabel", TEXT)
	theme_res.set_font_size("font_size", "TooltipLabel", 15)
	theme_res.set_color("default_color", "RichTextLabel", TEXT)
	theme_res.set_stylebox("panel", "TabContainer", ats_box("frame", 8))
	theme_res.set_stylebox("tab_selected", "TabContainer", ats_box("button_hover", 7))
	theme_res.set_stylebox("tab_unselected", "TabContainer", ats_box("button_disabled", 7))
	theme_res.set_stylebox("tab_hovered", "TabContainer", ats_box("button", 7))
	theme_res.set_color("font_selected_color", "TabContainer", Color(1, 0.9, 1.0))
	theme_res.set_color("font_unselected_color", "TabContainer", DIM)
	theme_res.set_color("font_hovered_color", "TabContainer", Color(1, 1, 1))


func _title(text: String, size := 20, color := NAME_COL, outline := 4) -> Label:
	var l := _label(text, size, color, outline)
	l.add_theme_font_override("font", font_title)
	return l


func _label(text: String, size := 16, color := TEXT, outline := 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func():
		Audio.sfx("ui_click", null, 0.5)
		cb.call())
	return b


# ----------------------------------------------------------------- верх
## Верх: своя команда · часы с отсчётом волны и битвы · две чужие команды. У героев — портрет, уровень,
## таймер возрождения; под ними прочность кристалла. Слева кнопки меню, справа счёт игрока.
const TOPBAR_H := 64.0
var top_row: HBoxContainer
var team_boxes: Array = []


func _build_top() -> void:
	top_row = HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 6)
	top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game_ui.add_child(top_row)
	top_row.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	top_row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var clock := PanelContainer.new()
	clock.add_theme_stylebox_override("panel", glass(5))
	clock.custom_minimum_size = Vector2(210, 0)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", -4)
	clock.add_child(cv)
	lbl_time = _label("00:00", 26, Color.WHITE, 4)
	lbl_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(lbl_time)
	lbl_wave = _label("", 12, ACC, 3)
	lbl_wave.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(lbl_wave)
	lbl_duel = _label("", 12, ACC, 3)
	lbl_duel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(lbl_duel)
	# лес: до появления лагерей (стаки) и до хвостатого
	lbl_forest = _label("", 11, Color(0.62, 0.95, 0.62), 3)
	lbl_forest.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_forest.tooltip_text = "Лагеря нейтралов появляются раз в минуту. Уведите пачку из лагеря к этому моменту — появится ещё одна (до 4)."
	lbl_forest.mouse_filter = Control.MOUSE_FILTER_PASS
	cv.add_child(lbl_forest)
	for t in 3:
		var box := PanelContainer.new()
		box.add_theme_stylebox_override("panel", glass(4, -0.18))
		box.mouse_filter = Control.MOUSE_FILTER_PASS
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 3)
		box.add_child(v)
		var faces := HBoxContainer.new()
		faces.add_theme_constant_override("separation", 3)
		faces.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_child(faces)
		var bar := Bar.new()
		bar.color = Data.TEAM_COLORS[t]
		bar.custom_minimum_size = Vector2(120, 12)
		bar.font_size = 9
		bar.skew = -0.18
		bar.tooltip_text = "Кристалл команды «%s»" % Data.TEAM_NAMES[t]
		v.add_child(bar)
		team_boxes.append(box)
		team_rows.append({"bar": bar, "faces": faces, "box": box})
	top_row.add_child(team_boxes[0])
	top_row.add_child(clock)
	top_row.add_child(team_boxes[1])
	top_row.add_child(team_boxes[2])
	# меню и счёт — слева
	var mb := HBoxContainer.new()
	mb.add_theme_constant_override("separation", 6)
	game_ui.add_child(mb)
	mb.position = Vector2(10, 8)
	for d in [["Меню", "Esc", toggle_menu], ["Счёт", "Tab", func(): toggle_scores(not scores_panel.visible)]]:
		var b := _button(d[0], d[2])
		b.add_theme_font_size_override("font_size", 13)
		b.add_theme_stylebox_override("normal", glass(5, -0.18))
		b.add_theme_stylebox_override("hover", glass(5, -0.18, ACC_HI, Color(0.3, 0.23, 0.1, 0.97)))
		b.add_theme_stylebox_override("pressed", glass(5, -0.18, ACC, Color(0.4, 0.3, 0.12, 0.97)))
		b.tooltip_text = "%s [%s]" % [d[0], d[1]]
		mb.add_child(b)
	# убийства и кадры — справа
	var kp := PanelContainer.new()
	kp.add_theme_stylebox_override("panel", glass(5, -0.18))
	kp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game_ui.add_child(kp)
	kp.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	kp.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	kp.offset_top = 8
	kp.offset_right = -12
	lbl_kills = _label("", 14, TEXT, 3)
	kp.add_child(lbl_kills)
	lbl_fps = _label("", 12, DIM, 3)
	lbl_fps.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game_ui.add_child(lbl_fps)
	lbl_fps.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	lbl_fps.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	lbl_fps.offset_top = 46
	lbl_fps.offset_right = -14


## Портреты героев в верхней полосе: своя команда встаёт слева от часов.
func _fill_teams() -> void:
	var g := Game.I
	var mine: int = g.player.team
	if mine != 0:
		top_row.move_child(team_boxes[mine], 0)
		top_row.move_child(team_boxes[0], 2 if mine == 1 else 3)
	for t in 3:
		var faces: HBoxContainer = team_rows[t].faces
		for c in faces.get_children():
			c.queue_free()
		for h: Hero in g.teams[t].heroes:
			var f := TeamFace.new()
			f.hero = h
			f.custom_minimum_size = Vector2(44, 44)
			faces.add_child(f)


## Ставит элемент в прямоугольник текстуры (x0..x1, y0..y1 в пикселях текстуры шириной 1600 и высотой th):
## при растяжении консоли на широкий экран элемент едет вместе с ней.
func _at(parent: Control, c: Control, x0: float, y0: float, x1: float, y1: float, th: float) -> Control:
	parent.add_child(c)
	c.anchor_left = x0 / 1600.0
	c.anchor_right = x1 / 1600.0
	c.anchor_top = y0 / th
	c.anchor_bottom = y1 / th
	c.offset_left = 0
	c.offset_right = 0
	c.offset_top = 0
	c.offset_bottom = 0
	return c


## Квадратная ячейка внутри прямоугольника текстуры (кнопки способностей, предметы).
func _cell(parent: Control, c: Control, x0: float, y0: float, x1: float, y1: float, th: float, ratio := 1.0) -> AspectRatioContainer:
	var a := AspectRatioContainer.new()
	a.ratio = ratio
	a.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_at(parent, a, x0, y0, x1, y1, th)
	a.add_child(c)
	c.custom_minimum_size = Vector2.ZERO
	return a


func _build_teams() -> void:
	pass  # команды теперь в верхней полосе (_build_top)


# ----------------------------------------------------------------- низ
## Нижняя консоль ATS — текстура из файлов карты (как в оригинале): миникарта · портрет под аркой с полосами
## здоровья и маны · сведения о герое · инвентарь 2×3 · сетка команд 4×3 (Q W E R / D T / лавка и курьер).
## Координаты ниже — в пикселях текстуры консоли (1600×337), элементы растягиваются вместе с ней.
var console_root: Control
var book_row: Control
var book_buttons: Array = []
var stats_view: StatsView
var buff_bar: BuffBar
var lbl_title: Label
var super_slot: SuperSlot
var shop_sel := ""
var recipe_view: RecipeView
var recipe_desc: Label
var recipe_buy: Button
## Высота нижних блоков (по ней ставятся подсказки и сообщения над ними)
const CONSOLE_H := 196.0
var stats_panel: PanelContainer
var mini_stats: Label
var hero_block: HBoxContainer


func _build_bottom() -> void:
	console_root = Control.new()
	console_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game_ui.add_child(console_root)
	console_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# ---- миникарта: слева внизу
	var mp := PanelContainer.new()
	mp.add_theme_stylebox_override("panel", glass(4))
	mp.mouse_filter = Control.MOUSE_FILTER_STOP
	console_root.add_child(mp)
	mp.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	mp.grow_vertical = Control.GROW_DIRECTION_BEGIN
	mp.offset_left = 10
	mp.offset_bottom = -10
	minimap = Minimap.new()
	minimap.custom_minimum_size = Vector2(180, 180)
	mp.add_child(minimap)

	# ---- герой: по центру — портрет, способности в ряд, под ними здоровье и мана
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 4)
	hv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	console_root.add_child(hv)
	hv.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hv.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hv.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hv.offset_bottom = -10
	# над блоком: эффекты слева, способности из книги справа
	var over := HBoxContainer.new()
	over.add_theme_constant_override("separation", 8)
	over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hv.add_child(over)
	buff_bar = BuffBar.new()
	buff_bar.custom_minimum_size = Vector2(300, 26)
	buff_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buff_bar.size_flags_vertical = Control.SIZE_SHRINK_END
	over.add_child(buff_bar)
	book_row = HBoxContainer.new()
	book_row.add_theme_constant_override("separation", 5)
	book_row.visible = false
	over.add_child(book_row)
	for k in 4:
		var bb := AbilityButton.new()
		bb.idx = 6 + k
		bb.custom_minimum_size = Vector2(48, 48)
		book_row.add_child(bb)
		book_buttons.append(bb)
	hero_block = HBoxContainer.new()
	hero_block.add_theme_constant_override("separation", 0)
	hero_block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hv.add_child(hero_block)
	# портрет с уровнем в кружке
	var pwrap := Control.new()
	pwrap.custom_minimum_size = Vector2(132, 152)
	hero_block.add_child(pwrap)
	portrait_holder = PanelContainer.new()
	var psb := glass(0.0, 0.0, ACC, Color(0.02, 0.02, 0.05))
	psb.set_border_width_all(2)
	psb.shadow_size = 10
	portrait_holder.add_theme_stylebox_override("panel", psb)
	portrait_holder.clip_contents = true
	pwrap.add_child(portrait_holder)
	portrait_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	insp_face = TextureRect.new()
	insp_face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	insp_face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	insp_face.visible = false
	portrait_holder.add_child(insp_face)
	insp_badge = _title("", 72, TEXT, 6)
	insp_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	insp_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	insp_badge.visible = false
	portrait_holder.add_child(insp_badge)
	lbl_respawn = _title("", 22, Color(1, 0.5, 0.45), 4)
	lbl_respawn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_respawn.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	portrait_holder.add_child(lbl_respawn)
	var lvp := PanelContainer.new()
	var lsb := glass(2.0, 0.0, ACC, Color(0.05, 0.06, 0.1))
	lsb.set_border_width_all(2)
	lsb.set_corner_radius_all(20)
	lsb.content_margin_left = 8
	lsb.content_margin_right = 8
	lvp.add_theme_stylebox_override("panel", lsb)
	lvp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pwrap.add_child(lvp)
	lvp.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	lvp.grow_vertical = Control.GROW_DIRECTION_BEGIN
	lvp.offset_left = -8
	lvp.offset_bottom = 6
	lbl_level = _label("", 15, Color.WHITE, 3)
	lbl_level.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lvp.add_child(lbl_level)
	# основная панель
	var main := PanelContainer.new()
	main.add_theme_stylebox_override("panel", glass(8))
	main.mouse_filter = Control.MOUSE_FILTER_STOP
	hero_block.add_child(main)
	var iv := VBoxContainer.new()
	iv.add_theme_constant_override("separation", 4)
	main.add_child(iv)
	var nrow := HBoxContainer.new()
	nrow.add_theme_constant_override("separation", 10)
	iv.add_child(nrow)
	lbl_name = _title("", 20, NAME_COL, 4)
	nrow.add_child(lbl_name)
	lbl_title = _label("", 12, DIM, 3)
	lbl_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_title.clip_text = true
	lbl_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	lbl_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nrow.add_child(lbl_title)
	mini_stats = _label("", 13, Color(0.88, 0.9, 0.95), 3)
	mini_stats.mouse_filter = Control.MOUSE_FILTER_STOP
	mini_stats.mouse_default_cursor_shape = Control.CURSOR_HELP
	nrow.add_child(mini_stats)
	var arow := HBoxContainer.new()
	arow.add_theme_constant_override("separation", 7)
	iv.add_child(arow)
	for i in 6:
		var b := AbilityButton.new()
		b.idx = i
		ability_buttons.append(b)
	for i in 4:
		(ability_buttons[i] as Control).custom_minimum_size = Vector2(66, 66)
		arow.add_child(ability_buttons[i])
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(4, 0)
	arow.add_child(gap)
	super_slot = SuperSlot.new()
	super_slot.btn = ability_buttons[5]
	super_slot.custom_minimum_size = Vector2(66, 66)
	arow.add_child(super_slot)
	var dbtn: Control = ability_buttons[4]
	dbtn.custom_minimum_size = Vector2(52, 52)
	dbtn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	arow.add_child(dbtn)
	var fill := Control.new()
	fill.custom_minimum_size = Vector2(0, 0)
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	arow.add_child(fill)
	hp_bar = Bar.new()
	hp_bar.color = HP_COL
	hp_bar.font_size = 14
	hp_bar.trail = true
	hp_bar.skew = -0.18
	hp_bar.custom_minimum_size = Vector2(470, 22)
	iv.add_child(hp_bar)
	mp_bar = Bar.new()
	mp_bar.color = MP_COL
	mp_bar.font_size = 12
	mp_bar.trail = true
	mp_bar.skew = -0.18
	mp_bar.custom_minimum_size = Vector2(470, 16)
	iv.add_child(mp_bar)
	xp_bar = Bar.new()
	xp_bar.color = ACC
	xp_bar.custom_minimum_size = Vector2(470, 5)
	xp_bar.plain = true
	xp_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	iv.add_child(xp_bar)
	lbl_stats = _label("", 1, DIM)
	lbl_stats.visible = false
	console_root.add_child(lbl_stats)
	lbl_buffs = RichTextLabel.new()
	lbl_buffs.visible = false
	console_root.add_child(lbl_buffs)
	# полная таблица атрибутов — по Alt или при наведении на краткие цифры
	stats_panel = PanelContainer.new()
	stats_panel.add_theme_stylebox_override("panel", glass(8))
	stats_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats_panel.visible = false
	console_root.add_child(stats_panel)
	stats_view = StatsView.new()
	stats_view.custom_minimum_size = Vector2(440, 52)
	stats_panel.add_child(stats_view)

	# ---- предметы, золото, лавка и курьер: справа внизу
	var ip := PanelContainer.new()
	ip.add_theme_stylebox_override("panel", glass(8))
	ip.mouse_filter = Control.MOUSE_FILTER_STOP
	console_root.add_child(ip)
	ip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	ip.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ip.offset_right = -10
	ip.offset_bottom = -10
	var ih := HBoxContainer.new()
	ih.add_theme_constant_override("separation", 10)
	ip.add_child(ih)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 5)
	grid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ih.add_child(grid)
	for i in 6:
		var sl := ItemSlot.new()
		sl.slot = i
		sl.custom_minimum_size = Vector2(54, 48)
		grid.add_child(sl)
		item_slots.append(sl)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 6)
	ih.add_child(side)
	var grow := HBoxContainer.new()
	grow.alignment = BoxContainer.ALIGNMENT_END
	grow.add_theme_constant_override("separation", 6)
	side.add_child(grow)
	var coin := Coin.new()
	coin.custom_minimum_size = Vector2(18, 18)
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	grow.add_child(coin)
	lbl_gold = _label("0", 20, GOLD, 3)
	grow.add_child(lbl_gold)
	var cb := HBoxContainer.new()
	cb.add_theme_constant_override("separation", 6)
	side.add_child(cb)
	var shop_b := CmdButton.new()
	shop_b.kind = "shop"
	shop_b.hud = self
	cb.add_child(shop_b)
	shop_b.custom_minimum_size = Vector2(60, 60)
	var cour_b := CmdButton.new()
	cour_b.kind = "courier"
	cour_b.hud = self
	cb.add_child(cour_b)
	cour_b.custom_minimum_size = Vector2(60, 60)


## Вдавленная панель внутри консоли.
func _inset() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := _sb(Color(0.035, 0.04, 0.07, 0.92), Color(1.0, 1.0, 1.0, 0.35), 6, 1, 8)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 4
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	return p


func _build_minimap() -> void:
	pass  # миникарта — часть нижней консоли


## Панель осмотра выделенного юнита (ЛКМ по герою, монстру, боссу): здоровье, мана, характеристики, предметы.
## Кого показывает нижняя панель: осматриваемый юнит (щелчок по чужому герою или монстру) или свой герой.
func view_unit() -> Unit:
	var g := Game.I
	if g == null:
		return null
	var u: Unit = g.inspected
	if u != null and is_instance_valid(u) and u.alive and u != g.player:
		return u
	return g.player


func view_hero() -> Hero:
	return view_unit() as Hero


func inspecting() -> bool:
	return Game.I != null and view_unit() != Game.I.player


## Имя, подпись, портрет и уровень на панели — для того, кого она сейчас показывает.
func _update_view(pl: Hero) -> void:
	var vu := view_unit()
	var insp := vu != pl
	if vu != _view_last:
		_view_last = vu
		for c in portrait_holder.get_children():
			if c != lbl_respawn and c != insp_face and c != insp_badge and c is Control:
				(c as Control).visible = not insp
		insp_face.visible = false
		insp_badge.visible = false
		if insp:
			var tex: Texture2D = null
			if vu is Hero:
				tex = HeroAssets.portrait((vu as Hero).hero_id)
				if tex == null:
					tex = HeroAssets.icon((vu as Hero).hero_id, "")
			if tex:
				insp_face.texture = tex
				insp_face.visible = true
			else:
				insp_badge.text = vu.display_name.substr(0, 1).to_upper()
				insp_badge.visible = true
		if insp:
			var enemy := pl.is_enemy(vu)
			var col := Color(1.0, 0.55, 0.5) if enemy else Color(0.6, 1.0, 0.65)
			lbl_name.text = vu.display_name
			lbl_name.add_theme_color_override("font_color", col)
			insp_badge.add_theme_color_override("font_color", col)
			if vu is Hero:
				var h := vu as Hero
				lbl_title.text = "%s · %s · %s" % [Data.TEAM_NAMES[h.team], h.def.title, "враг" if enemy else "союзник"]
			elif vu.kind == Unit.Kind.BOSS:
				lbl_title.text = "Босс · осмотр (Esc — к своему герою)"
			else:
				lbl_title.text = ("Лесной монстр" if vu.neutral else "Монстр") + " · осмотр (Esc — к своему герою)"
		else:
			lbl_name.text = pl.def.name
			lbl_name.add_theme_color_override("font_color", Color(pl.def.color).lightened(0.35))
			lbl_title.text = "%s · %s" % [pl.def.title, pl.def.series]
	if vu is Hero:
		lbl_level.text = "%d" % (vu as Hero).level
	elif vu.kind == Unit.Kind.BOSS:
		lbl_level.text = "Босс"
	else:
		lbl_level.text = "Монстр"
	super_slot.modulate.a = 0.0 if insp else 1.0
	book_row.modulate.a = 0.0 if insp else 1.0


## Строка команд тест-режима (Enter).
func open_console() -> void:
	if console_edit == null:
		console_edit = LineEdit.new()
		console_edit.placeholder_text = "Команда (Enter — выполнить, Esc — закрыть): -gold, -lvl 25, -wave 20, -boss 5, -cd, -god, -set, -kill"
		console_edit.add_theme_font_size_override("font_size", 15)
		game_ui.add_child(console_edit)
		console_edit.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
		console_edit.offset_left = 16
		console_edit.offset_right = 760
		console_edit.offset_top = -CONSOLE_H - 52
		console_edit.offset_bottom = -CONSOLE_H - 16
		console_edit.text_submitted.connect(func(t: String) -> void:
			var msg := Game.I.run_cheat(t)
			if msg != "":
				announce(msg, Color(0.6, 1.0, 0.7), 3.0)
			console_edit.text = ""
			console_edit.visible = false
			console_edit.release_focus())
		console_edit.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventKey and e.pressed and (e as InputEventKey).physical_keycode == KEY_ESCAPE:
				console_edit.visible = false
				console_edit.release_focus()
				console_edit.accept_event())
	console_edit.visible = true
	console_edit.grab_focus()


func _build_info() -> void:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	game_ui.add_child(p)
	p.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	p.offset_right = -10
	p.offset_bottom = -CONSOLE_H - 4
	p.offset_left = -250
	p.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	p.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var v := VBoxContainer.new()
	p.add_child(v)
	info_label = _label("", 14, TEXT)
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_label.custom_minimum_size = Vector2(220, 0)
	v.add_child(info_label)
	info_panel = p


func _build_messages() -> void:
	announce_box = VBoxContainer.new()
	announce_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(announce_box)
	announce_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	announce_box.offset_top = 104
	announce_box.offset_left = -560
	announce_box.offset_right = 560
	announce_box.grow_horizontal = Control.GROW_DIRECTION_BOTH

	feed_box = VBoxContainer.new()
	feed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game_ui.add_child(feed_box)
	feed_box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	feed_box.offset_top = 210
	feed_box.offset_right = -26
	feed_box.offset_left = -350
	feed_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN

	# полоса каста телепорта (круг «2», врата, свиток)
	chan_box = Control.new()
	chan_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game_ui.add_child(chan_box)
	chan_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	chan_box.offset_bottom = -CONSOLE_H - 58
	chan_box.offset_top = -CONSOLE_H - 92
	chan_box.offset_left = -170
	chan_box.offset_right = 170
	var chan_bg := Panel.new()
	chan_bg.add_theme_stylebox_override("panel", glass(2))
	chan_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chan_box.add_child(chan_bg)
	chan_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	chan_bar = ColorRect.new()
	chan_bar.color = Color(0.55, 0.8, 1.0, 0.75)
	chan_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chan_bar.position = Vector2(4, 4)
	chan_bar.size = Vector2(0, 26)
	chan_box.add_child(chan_bar)
	chan_lbl = _label("", 15, Color.WHITE, 4)
	chan_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chan_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chan_box.add_child(chan_lbl)
	chan_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	chan_box.visible = false

	lvl_row = HBoxContainer.new()
	lvl_row.alignment = BoxContainer.ALIGNMENT_CENTER
	lvl_row.add_theme_constant_override("separation", 8)
	game_ui.add_child(lvl_row)
	lvl_row.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	lvl_row.offset_bottom = -CONSOLE_H - 96
	lvl_row.offset_top = -CONSOLE_H - 132
	lvl_row.offset_left = -420
	lvl_row.offset_right = 420
	lvl_lbl = _label("", 14, Color(1.0, 0.85, 0.4), 4)
	lvl_row.add_child(lvl_lbl)
	lvl_stat_btn = Button.new()
	lvl_stat_btn.text = "+%d ко всем атрибутам" % int(Data.STAT_POINT)
	lvl_stat_btn.tooltip_text = "Вложить очко навыка в атрибуты (Ctrl+A)"
	lvl_stat_btn.focus_mode = Control.FOCUS_NONE
	lvl_stat_btn.pressed.connect(func() -> void:
		if Game.I.player:
			Game.I.player.learn_stats())
	lvl_row.add_child(lvl_stat_btn)
	for o in 2:
		var tb := Button.new()
		tb.focus_mode = Control.FOCUS_NONE
		tb.pressed.connect(func() -> void:
			var me: Hero = Game.I.player
			if me and me.talent_pending() >= 0:
				me.pick_talent(me.talent_pending(), o))
		lvl_row.add_child(tb)
		lvl_tal_btns.append(tb)
	lvl_row.visible = false

	error_label = _label("", 18, Color(1.0, 0.45, 0.4), 4)
	error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_ui.add_child(error_label)
	error_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	error_label.offset_bottom = -CONSOLE_H - 14
	error_label.offset_top = -CONSOLE_H - 42
	error_label.offset_left = -320
	error_label.offset_right = 320
	error_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	error_label.modulate.a = 0.0


func _center_panel(w: float, h: float) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", ats_box("frame", 16))
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(p)
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	p.offset_left = -w / 2
	p.offset_right = w / 2
	p.offset_top = -h / 2
	p.offset_bottom = h / 2
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	p.visible = false
	return p


# ----------------------------------------------------------------- лавка
func _build_shop() -> void:
	shop_panel = _center_panel(1420, 700)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	shop_panel.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	var t := _label("Лавка выживания", 26, GOLD, 4)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(t)
	top.add_child(_button("Закрыть [B]", toggle_shop))
	shop_status = _label("", 14, DIM)
	v.add_child(shop_status)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	shop_tabs = TabContainer.new()
	shop_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shop_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(shop_tabs)
	for tab: Dictionary in Data.SHOP_TABS:
		var sc := ScrollContainer.new()
		sc.name = tab.title
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		shop_tabs.add_child(sc)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 6)
		sc.add_child(col)
		for sec: Dictionary in tab.sections:
			col.add_child(_label(sec.title, 15, GOLD, 3))
			var grid := GridContainer.new()
			grid.columns = 3
			grid.add_theme_constant_override("h_separation", 8)
			grid.add_theme_constant_override("v_separation", 8)
			col.add_child(grid)
			for id in sec.items:
				var card := ShopCard.new()
				card.item_id = id
				card.hud = self
				grid.add_child(card)
				shop_cards.append(card)
	_build_recipe_panel(body)
	# инвентарь и склад
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 190
	side.add_theme_constant_override("separation", 6)
	body.add_child(side)
	side.add_child(_label("Инвентарь", 16, GOLD, 3))
	var g1 := GridContainer.new()
	g1.columns = 3
	g1.add_theme_constant_override("h_separation", 6)
	g1.add_theme_constant_override("v_separation", 6)
	side.add_child(g1)
	for i in 6:
		var s := ShopSlot.new()
		s.slot = i
		s.stash = false
		s.hud = self
		g1.add_child(s)
		shop_inv.append(s)
	side.add_child(_label("Рюкзак", 16, GOLD, 3))
	var g2 := GridContainer.new()
	g2.columns = 3
	g2.add_theme_constant_override("h_separation", 6)
	g2.add_theme_constant_override("v_separation", 6)
	side.add_child(g2)
	for i in 6:
		var s2 := ShopSlot.new()
		s2.slot = i
		s2.stash = true
		s2.hud = self
		g2.add_child(s2)
		shop_inv.append(s2)
	side.add_child(_label("В лагере", 16, GOLD, 3))
	var g3 := GridContainer.new()
	g3.columns = 3
	g3.add_theme_constant_override("h_separation", 6)
	g3.add_theme_constant_override("v_separation", 6)
	side.add_child(g3)
	for i in 6:
		var s3 := ShopSlot.new()
		s3.slot = i
		s3.base = true
		s3.hud = self
		g3.add_child(s3)
		shop_inv.append(s3)
	var cb := _button("Отправить курьера [C]", send_courier)
	cb.add_theme_font_size_override("font_size", 13)
	side.add_child(cb)
	courier_status = _label("", 12, DIM)
	courier_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	courier_status.custom_minimum_size.x = 180
	side.add_child(courier_status)
	var hint := _label("ЛКМ по ячейке — переложить между инвентарём и рюкзаком.\nПКМ по ячейке — продать (в лагере).\nВне лагеря покупки ложатся «в лагерь» — их привезёт курьер.\nРюкзак и лагерь учитываются в рецептах.", 12, DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = 180
	side.add_child(hint)


## Колонка «Сборка» (как в Dota): выбранный предмет, из чего собирается и куда входит. ПКМ — купить всё недостающее.
func _build_recipe_panel(body: HBoxContainer) -> void:
	var pan := PanelContainer.new()
	pan.add_theme_stylebox_override("panel", _sb(Color(0.035, 0.04, 0.07, 0.95), Color(1.0, 1.0, 1.0, 0.35), 8, 1, 10))
	pan.custom_minimum_size.x = 330
	body.add_child(pan)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	pan.add_child(v)
	v.add_child(_label("Сборка", 16, GOLD, 3))
	recipe_view = RecipeView.new()
	recipe_view.hud = self
	recipe_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	recipe_view.custom_minimum_size = Vector2(310, 380)
	v.add_child(recipe_view)
	recipe_desc = _label("", 12, DIM)
	recipe_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	recipe_desc.custom_minimum_size = Vector2(310, 0)
	v.add_child(recipe_desc)
	recipe_buy = _button("Купить", func() -> void:
		if shop_sel != "":
			try_buy(shop_sel, true))
	recipe_buy.add_theme_font_size_override("font_size", 14)
	v.add_child(recipe_buy)
	var hint := _label("ЛКМ по предмету — показать сборку · ПКМ — купить сразу всё недостающее и собрать (если хватает золота)", 11, DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(310, 0)
	v.add_child(hint)


## Выбрать предмет в лавке: показать его дерево сборки.
func shop_select(id: String) -> void:
	if id == "" or not Data.ITEMS.has(id):
		return
	var old := shop_sel
	shop_sel = id
	for c in shop_cards:
		if c.item_id == id or c.item_id == old:
			c._style()
	recipe_desc.text = "%s · класс %s\n%s" % [Data.ITEMS[id].name, Data.ITEMS[id].cls, Data.item_desc(id)]
	recipe_view.queue_redraw()


func _refresh_recipe_buy() -> void:
	var pl := Game.I.player if Game.I else null
	if pl == null or shop_sel == "":
		recipe_buy.text = "Выберите предмет"
		recipe_buy.disabled = true
		return
	var plan := pl.recipe_plan(shop_sel)
	var cost := int(plan.cost)
	recipe_buy.disabled = false
	if str(plan.err) != "":
		recipe_buy.text = plan.err
		recipe_buy.disabled = true
	elif (Data.ITEMS[shop_sel].get("recipe", []) as Array).is_empty():
		recipe_buy.text = "Купить — %d золота" % cost if pl.gold >= cost else "Не хватает %d золота" % (cost - pl.gold)
	elif pl.gold >= cost:
		recipe_buy.text = "Докупить всё и собрать — %d золота [ПКМ]" % cost
	else:
		recipe_buy.text = "Не хватает %d золота (нужно %d)" % [cost - pl.gold, cost]


func _build_scores() -> void:
	scores_panel = _center_panel(760, 460)
	var v := VBoxContainer.new()
	scores_panel.add_child(v)
	v.add_child(_label("Счёт", 24, GOLD, 4))
	scores_grid = GridContainer.new()
	scores_grid.columns = 7
	scores_grid.add_theme_constant_override("h_separation", 20)
	scores_grid.add_theme_constant_override("v_separation", 6)
	v.add_child(scores_grid)


func _slider(v: VBoxContainer, title: String, value: float, cb: Callable) -> void:
	var row := HBoxContainer.new()
	v.add_child(row)
	var l := _label(title, 15, TEXT)
	l.custom_minimum_size.x = 200
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = value
	s.focus_mode = Control.FOCUS_NONE
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.value_changed.connect(cb)
	row.add_child(s)


func _build_menu() -> void:
	menu_panel = _center_panel(600, 780)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 9)
	menu_panel.add_child(v)
	v.add_child(_title("Пауза", 30, NAME_COL, 5))
	v.add_child(_button("Продолжить", toggle_menu))
	_slider(v, "Общая громкость", Audio.vol_master, func(x: float):
		Audio.vol_master = x
		Audio.apply_volumes())
	_slider(v, "Эффекты", Audio.vol_sfx, func(x: float): Audio.vol_sfx = x)
	_slider(v, "Голоса героев", Audio.vol_voice, func(x: float):
		Audio.vol_voice = x
		Audio.apply_volumes())
	_slider(v, "Музыка", Audio.vol_music, func(x: float):
		Audio.vol_music = x
		Audio.apply_volumes())
	var qc := Button.new()
	qc.focus_mode = Control.FOCUS_NONE
	qc.text = "Быстрое применение способностей: выкл"
	qc.pressed.connect(func():
		Game.I.quick_cast = not Game.I.quick_cast
		qc.text = "Быстрое применение способностей: " + ("вкл" if Game.I.quick_cast else "выкл"))
	v.add_child(qc)
	var ep := Button.new()
	ep.focus_mode = Control.FOCUS_NONE
	ep.text = "Прокрутка у края экрана: вкл"
	ep.pressed.connect(func():
		Game.I.camera.edge_pan = not Game.I.camera.edge_pan
		ep.text = "Прокрутка у края экрана: " + ("вкл" if Game.I.camera.edge_pan else "выкл"))
	v.add_child(ep)
	var gq := Button.new()
	gq.focus_mode = Control.FOCUS_NONE
	Gfx.load_cfg()
	gq.text = "Качество графики: " + Gfx.NAMES[Gfx.quality]
	gq.tooltip_text = "Низкое — без теней и сглаживания, меньше частиц: если игра тормозит"
	gq.pressed.connect(func():
		Gfx.quality = (Gfx.quality + 2) % 3
		Gfx.save_cfg()
		Gfx.apply(get_tree())
		gq.text = "Качество графики: " + Gfx.NAMES[Gfx.quality])
	v.add_child(gq)
	var fp := Button.new()
	fp.focus_mode = Control.FOCUS_NONE
	fp.text = "Счётчик кадров: " + ("вкл" if Gfx.show_fps else "выкл")
	fp.pressed.connect(func():
		Gfx.show_fps = not Gfx.show_fps
		Gfx.save_cfg()
		fp.text = "Счётчик кадров: " + ("вкл" if Gfx.show_fps else "выкл"))
	v.add_child(fp)
	v.add_child(_button("Полный экран / окно  [F11]", func(): Game.I.toggle_fullscreen()))
	var help := _label("", 13, DIM)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.text = "ПКМ — идти / атаковать · Q W E R D — способности, затем ЛКМ по цели\n" \
		+ "A + ЛКМ — атака с передвижением · S — стоп · H — стоять · 1–6 — предмет\n" \
		+ "B — лавка · C — курьер · Tab — счёт · Пробел — камера к герою · F2 — арена\n" \
		+ "ЛКМ по герою или монстру — осмотр (здоровье, предметы) · Enter — тест-команды (-gold, -lvl, -boss...)\n" \
		+ "Камера: курсор к краю экрана, стрелки, средняя кнопка мыши · колесо — зум\n\n" \
		+ "Соберите Ультимативный сет (вкладка «Сет героя» в лавке) — он откроет способность [D]."
	v.add_child(help)
	v.add_child(_button("Начать заново", func():
		get_tree().paused = false
		get_tree().reload_current_scene()))
	v.add_child(_button("Выйти из игры", func(): get_tree().quit()))


# ----------------------------------------------------------------- выбор героя
var select_detail: Control = null
var select_tiles := {}


func show_hero_select() -> void:
	select_layer = Control.new()
	root.add_child(select_layer)
	select_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.07, 0.8)
	select_layer.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	select_layer.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(v)
	var title := _title("Anime Team Survival", 52, Color(1.0, 0.8, 1.0), 10)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var sub := _label("Три команды. У каждой свой кристалл выживания. Продержитесь дольше всех.", 17, DIM, 4)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(body)
	# сетка героев
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	body.add_child(left)
	left.add_child(_label("Выберите героя — %d из карты. Двойной щелчок — сразу в бой." % Data.HERO_ORDER.size(), 14, DIM))
	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	left.add_child(grid)
	select_tiles.clear()
	for id in Data.HERO_ORDER:
		grid.add_child(_hero_tile(id))
	var rnd := _button("Случайный герой", func(): _pick_hero(Data.HERO_ORDER.pick_random()))
	rnd.custom_minimum_size = Vector2(220, 36)
	rnd.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	left.add_child(rnd)
	# карточка выбранного героя
	select_detail = VBoxContainer.new()
	select_detail.custom_minimum_size = Vector2(340, 0)
	body.add_child(select_detail)
	_show_select_detail(Data.HERO_ORDER[0])
	var rules := _label("Монстры идут волнами к кристаллу, каждая 5-я волна — босс. Через круги силы можно напасть на врагов. " \
		+ "Каждые 5 минут две команды целиком сражаются на арене.", 14, DIM, 3)
	rules.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rules.custom_minimum_size.x = 1100
	v.add_child(rules)


func _hero_tile(id: String) -> Control:
	var d: Dictionary = Data.HEROES[id]
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(108, 128)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	p.tooltip_text = "%s — %s\n%s" % [d.name, d.title, d.role]
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(vb)
	var tex := HeroAssets.portrait(id)
	var pr: Control
	if tex:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		pr = tr
	else:
		var cr := ColorRect.new()
		cr.color = Color(d.color).darkened(0.5)
		pr = cr
	pr.custom_minimum_size = Vector2(100, 100)
	pr.clip_contents = true
	pr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(pr)
	var n := _label(d.name, 13 if str(d.name).length() <= 11 else 11, Color(d.color).lightened(0.35), 3)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.clip_text = true
	n.custom_minimum_size.x = 100
	vb.add_child(n)
	p.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.double_click:
				_pick_hero(id)
			else:
				_show_select_detail(id))
	select_tiles[id] = p
	_style_tile(id, false)
	return p


func _style_tile(id: String, on: bool) -> void:
	var c: Color = Data.HEROES[id].color
	var bg := Color(0.12, 0.13, 0.2, 0.98) if on else Color(0.07, 0.08, 0.13, 0.95)
	select_tiles[id].add_theme_stylebox_override("panel", _sb(bg, c.lightened(0.2) if on else c.darkened(0.45), 8, 3 if on else 2, 4))


func _show_select_detail(id: String) -> void:
	if select_detail == null:
		return
	for k in select_tiles:
		_style_tile(k, k == id)
	for c in select_detail.get_children():
		c.queue_free()
	select_detail.add_child(_hero_card(id))
	Audio.sfx("ui_click", null, 0.4)


func _hero_card(id: String) -> Control:
	var d: Dictionary = Data.HEROES[id]
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _sb(Color(0.07, 0.08, 0.13, 0.95), d.color.darkened(0.1), 10, 2, 12))
	p.custom_minimum_size = Vector2(340, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	p.add_child(v)
	var tex := HeroAssets.portrait(id)
	var pr: TextureRect
	if tex:
		pr = TextureRect.new()
		pr.texture = tex
		pr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	else:
		pr = make_portrait(id, Vector2i(296, 250), true)
		select_viewports.append(pr.get_meta("viewport"))
	pr.custom_minimum_size = Vector2(316, 230)
	pr.clip_contents = true
	v.add_child(pr)
	var n := _label(d.name, 26, d.color.lightened(0.25), 4)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(n)
	var t := _label("%s · %s" % [d.title, d.series], 13, DIM)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var r := _label(d.role, 13, TEXT)
	r.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(r)
	var attr: String = {"str": "Сила", "agi": "Ловкость", "int": "Интеллект"}[d.primary]
	var nums := _label("%s · здоровье %d · урон %d · %s" % [attr, int(d.hp + d.str * Data.STR_HP), int(d.damage + d[d.primary]),
		"дальний бой" if d.ranged else "ближний бой"], 12, DIM)
	nums.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(nums)
	if str(d.get("passive", "")) != "":
		var ps := _label(d.passive, 12, Color(0.8, 0.85, 1.0))
		ps.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ps.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ps.custom_minimum_size.x = 300
		v.add_child(ps)
	for i in mini(6, d.abilities.size()):
		var a: Dictionary = Data.ABILITIES[d.abilities[i]]
		if a.type == "empty":
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.tooltip_text = a.desc
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		v.add_child(row)
		var ic := AbilityIcon.new()
		ic.ability_id = d.abilities[i]
		ic.hero_id = id
		ic.key = KEYS[i].to_lower()
		ic.custom_minimum_size = Vector2(28, 28)
		row.add_child(ic)
		var suffix := " (сет)" if a.get("set", false) else (" (пассивная)" if a.type == "passive" else (" (врождённая)" if i == 4 else ""))
		var l := _label("%s  %s%s" % [KEYS[i], a.name, suffix], 13, GOLD if a.get("set", false) else TEXT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 270
		row.add_child(l)
	var b := _button("Играть за %s" % d.name, func(): _pick_hero(id))
	b.custom_minimum_size.y = 40
	v.add_child(b)
	return p


func _pick_hero(id: String) -> void:
	if select_layer:
		select_layer.queue_free()
		select_layer = null
	for vp in select_viewports:
		(vp as Node).queue_free()
	select_viewports.clear()
	Game.I.start_game(id)


func on_game_started() -> void:
	game_ui.visible = true
	var pl := Game.I.player
	for card in shop_cards:
		var owner_id: String = Data.ITEMS[card.item_id].get("hero", "")
		card.visible = owner_id == "" or owner_id == pl.hero_id
	for c in portrait_holder.get_children():
		if c != lbl_respawn and c != insp_face and c != insp_badge:
			c.queue_free()
	_view_last = null
	_fill_teams()
	# живой портрет: модель героя крупным планом, как в Warcraft
	var pr := make_portrait(pl.hero_id, Vector2i(180, 180), false, pl.team)
	pr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait_holder.add_child(pr)
	portrait_holder.move_child(pr, 0)
	lbl_name.text = pl.def.name
	lbl_name.add_theme_color_override("font_color", Color(pl.def.color).lightened(0.35))
	lbl_title.text = "%s · %s" % [pl.def.title, pl.def.series]
	shop_select("set_" + pl.hero_id if Data.ITEMS.has("set_" + pl.hero_id) else "")
	var nb := pl.abilities.size() - KEYS.size()
	book_row.visible = nb > 0
	for k in book_buttons.size():
		(book_buttons[k] as Control).visible = k < nb


## 3D-портрет временной модели (если у героя нет картинки portrait.png).
func make_portrait(id: String, size: Vector2i, full: bool, team := -1) -> TextureRect:
	var vp := SubViewport.new()
	vp.size = size
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_4X
	add_child(vp)
	var m: Node3D = HeroAssets.model_scene(id).instantiate()
	vp.add_child(m)
	var info := HeroAssets.fit_model(m, id, 1.95)
	World.recolor(m, "TeamBand", Data.TEAM_COLORS[team] if team >= 0 else Color(0.85, 0.7, 0.4), 0.35)
	var ap := Unit.find_anim(m)
	var idle: String = info.anim_map.get("Idle", "")
	if ap and not full:
		for pn in ["Portrait", "portrait"]:
			if ap.has_animation(pn):
				idle = pn
				break
	if ap and idle != "":
		ap.get_animation(idle).loop_mode = Animation.LOOP_LINEAR
		ap.play(idle)
	var cam := Camera3D.new()
	vp.add_child(cam)
	var cfg := HeroAssets.config(id)
	if not full and cfg.has("head"):
		# голова модели (hero.json → head) в координатах модели
		var hd: Array = cfg.head
		m.rotation.y += 0.25
		var head := m.global_transform * Vector3(float(hd[0]), float(hd[1]), float(hd[2]))
		var dist := 1.15
		cam.fov = 30
		cam.position = head + Vector3(dist * 0.25, dist * 0.05, dist)
		cam.look_at(head + Vector3(0, -0.08, 0))
	elif full:
		cam.fov = 32
		cam.position = Vector3(0.0, 1.2, 3.6)
		cam.look_at(Vector3(0, 1.05, 0))
		m.rotation.y += 0.35
	else:
		cam.fov = 30
		cam.position = Vector3(0.25, 1.8, 1.55)
		cam.look_at(Vector3(0, 1.66, 0))
		m.rotation.y += 0.2
	var l := DirectionalLight3D.new()
	l.rotation_degrees = Vector3(-30, 35, 0)
	l.light_energy = 1.3
	vp.add_child(l)
	var l2 := DirectionalLight3D.new()
	l2.rotation_degrees = Vector3(-10, -140, 0)
	l2.light_energy = 0.7
	l2.light_color = Color(0.6, 0.75, 1.0)
	vp.add_child(l2)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.7)
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	vp.add_child(we)
	var tr := TextureRect.new()
	tr.texture = vp.get_texture()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.set_meta("viewport", vp)
	return tr


# ----------------------------------------------------------------- обновление
func _process(delta: float) -> void:
	var g := Game.I
	if g == null:
		return
	_update_floats(delta)
	for k in craft_flash.keys():
		craft_flash[k] -= delta
		if craft_flash[k] <= 0.0:
			craft_flash.erase(k)
	if g.state == "select" or g.player == null:
		return
	var pl := g.player
	_fps_t -= delta
	if _fps_t <= 0.0:
		_fps_t = 0.5
		lbl_fps.text = "%d к/с · %s" % [Engine.get_frames_per_second(), Gfx.NAMES[Gfx.quality].to_lower()] if Gfx.show_fps else ""
		lbl_kills.text = "Убийства %d · смерти %d" % [pl.kills, pl.deaths]
	lbl_time.text = _fmt_time(g.time)
	var to_wave := maxf(0.0, g.next_wave - g.time)
	if g.wave == 0:
		lbl_wave.text = "волна 1 через %d" % ceili(to_wave)
	else:
		var nb := Data.BOSS_EVERY - (g.wave % Data.BOSS_EVERY)
		lbl_wave.text = "%s %d через %d" % ["БОСС" if nb == 1 else "волна", g.wave + 1, ceili(to_wave)]
	if g.time_stop_left > 0.0:
		lbl_duel.text = "время стоит: %d" % ceili(g.time_stop_left)
		lbl_duel.add_theme_color_override("font_color", Color(0.75, 0.9, 1.0))
	elif g.duel.is_empty():
		lbl_duel.text = "битва через %s" % _fmt_time(maxf(0.0, g.next_duel - g.time))
		lbl_duel.add_theme_color_override("font_color", TEXT)
	else:
		var names := PackedStringArray()
		for t: int in g.duel.teams:
			names.append(Data.TEAM_NAMES[t])
		var vs := " × ".join(names)
		if g.duel.phase == "fight":
			lbl_duel.text = "Битва: %s · %d" % [vs, ceili(Data.DUEL_LIMIT - g.duel.t)]
		else:
			lbl_duel.text = "Битва: %s" % vs
		lbl_duel.add_theme_color_override("font_color", GOLD)
	var me0: Hero = g.player
	if me0 and lvl_row:
		var tp := me0.talent_pending()
		lvl_row.visible = me0.alive and not inspecting() and (me0.skill_points > 0 or tp >= 0)
		lvl_lbl.text = ("Талант %d уровня:" % Data.TALENT_LEVELS[tp]) if tp >= 0 else ("Очки навыков: %d" % me0.skill_points)
		lvl_stat_btn.visible = tp < 0 and me0.skill_points > 0
		for o in 2:
			lvl_tal_btns[o].visible = tp >= 0
			if tp >= 0:
				lvl_tal_btns[o].text = str(Data.TALENTS[tp][o].name)
	var ft := "лагеря через %s" % _fmt_time(maxf(0.0, g.next_camps - g.time))
	if g.beast != null and is_instance_valid(g.beast):
		ft += " · %s в логове!" % g.beast.display_name.split(" ")[0]
	elif g.beast_n < g.BEAST_NAMES.size():
		ft += " · хвостатый через %s" % _fmt_time(maxf(0.0, g.next_beast - g.time))
	lbl_forest.text = ft
	refresh_t -= delta
	if refresh_t <= 0.0:
		refresh_t = 0.25
		_refresh_teams()
		if scores_panel.visible:
			_refresh_scores()
		if shop_panel.visible:
			_refresh_shop_status()
			_refresh_recipe_buy()
			if courier_status and pl.courier:
				courier_status.text = pl.courier.status_text()
	var vu := view_unit()
	var vh := vu as Hero
	mini_stats.text = "урон %d · броня %s · бег %.1f" % [int(vu.damage_value()), String.num(vu.armor, 1), vu.move_speed * (1.0 + vu.bonus_move)]
	var show_stats := Input.is_key_pressed(KEY_ALT) or mini_stats.get_global_rect().has_point(get_viewport().get_mouse_position())
	if show_stats != stats_panel.visible:
		stats_panel.visible = show_stats
	if show_stats:
		var hr := hero_block.get_global_rect()
		stats_panel.position = Vector2(hr.end.x - stats_panel.size.x, hr.position.y - stats_panel.size.y - 34)
	hp_bar.value = vu.hp
	hp_bar.max_value = maxf(1.0, vu.max_hp)
	hp_bar.text = "%d / %d" % [int(vu.hp), int(vu.max_hp)]
	mp_bar.value = vu.mp
	mp_bar.max_value = maxf(1.0, vu.max_mp)
	mp_bar.text = "%d / %d" % [int(vu.mp), int(vu.max_mp)] if vu.max_mp > 0.0 else "нет маны"
	if vh == null:
		xp_bar.value = 0.0
		xp_bar.max_value = 1.0
		xp_bar.text = "награда: %d зол. · %d опыта" % [int(vu.bounty_gold), int(vu.bounty_xp)] if vu.bounty_gold > 0.0 or vu.bounty_xp > 0.0 else ""
	elif vh.level >= Data.MAX_LEVEL:
		xp_bar.value = 1.0
		xp_bar.max_value = 1.0
		xp_bar.text = "макс."
	else:
		xp_bar.value = vh.xp
		xp_bar.max_value = Data.xp_to_next(vh.level)
		xp_bar.text = "опыт %d / %d" % [int(vh.xp), int(xp_bar.max_value)]
	xp_bar.tooltip_text = xp_bar.text
	lbl_gold.text = str(pl.gold) if vu == pl else "—"
	if vu != pl:
		portrait_holder.modulate = Color.WHITE
		lbl_respawn.text = ""
	elif not pl.alive:
		if g.teams[pl.team].alive:
			lbl_respawn.text = "Воскрешение\n%d" % ceili(pl.respawn_left) if pl.respawn_left > 0.0 else "Ждёт конца\nбитвы"
		else:
			lbl_respawn.text = "Выбыл"
		portrait_holder.modulate = Color(0.6, 0.6, 0.65)
	else:
		lbl_respawn.text = ""
		portrait_holder.modulate = Color.WHITE
	_update_view(pl)
	# угловая подсказка — только юнит под курсором (выбранный показан на нижней панели)
	var u: Unit = g.hovered
	if u and is_instance_valid(u) and u.alive and u != view_unit():
		var who := u.display_name
		if u is Hero:
			who += " (%s), ур. %d" % [Data.TEAM_NAMES[u.team], (u as Hero).level]
		elif u.kind == Unit.Kind.CRYSTAL:
			who += " команды «%s»" % Data.TEAM_NAMES[u.team]
		var s := "%s\nЗдоровье %d / %d" % [who, int(u.hp), int(u.max_hp)]
		if u.kind != Unit.Kind.CRYSTAL:
			s += "\nУрон %d · Броня %.1f" % [int(u.damage_value()), u.armor]
		info_label.text = s
	else:
		var zt: int = pl.area
		info_label.text = ("Остров: «%s»" % Data.TEAM_NAMES[zt]) if zt >= 0 else "Арена битвы команд"


func _refresh_teams() -> void:
	var g := Game.I
	for t in 3:
		var row: Dictionary = team_rows[t]
		var c: Unit = g.teams[t].crystal
		var bar: Bar = row.bar
		bar.max_value = c.max_hp
		bar.value = c.hp if g.teams[t].alive else 0.0
		bar.text = "%d" % int(bar.value) if g.teams[t].alive else "разрушен"
		(row.box as Control).modulate = Color.WHITE if g.teams[t].alive else Color(0.55, 0.55, 0.6)


func _fmt_time(t: float) -> String:
	var s := int(t)
	return "%02d:%02d" % [s / 60, s % 60]


# ----------------------------------------------------------------- сообщения
## Предмет собран: вспышка ячейки и сообщение.
func on_item_crafted(id: String) -> void:
	craft_flash[id] = 1.8
	var d: Dictionary = Data.ITEMS[id]
	announce("✦ Собрано: %s ✦" % d.name, Color(d.get("color", GOLD)).lightened(0.25), 2.4)


## Рисует сияние вокруг ячейки с только что собранным предметом.
static func draw_craft_flash(ci: Control, id: String) -> void:
	if id == "" or Game.I == null or Game.I.hud == null:
		return
	var t: float = Game.I.hud.craft_flash.get(id, 0.0)
	if t <= 0.0:
		return
	var k := clampf(t / 1.8, 0.0, 1.0)
	var col: Color = Color(Data.ITEMS[id].get("color", Color(1, 0.8, 0.3))).lightened(0.4)
	var r := Rect2(Vector2.ZERO, ci.size)
	for i in 3:
		ci.draw_rect(r.grow(1.0 + i * 2.0), Color(col, 0.5 * k / (i + 1)), false, 2.0)
	var x := ci.size.x * (1.0 - k) * 1.6 - ci.size.x * 0.3
	var pts := PackedVector2Array([Vector2(x, 0), Vector2(x + ci.size.x * 0.25, 0), Vector2(x + ci.size.x * 0.05, ci.size.y), Vector2(x - ci.size.x * 0.2, ci.size.y)])
	ci.draw_colored_polygon(pts, Color(1, 1, 1, 0.35 * k))


## Полоса каста телепорта: k — доля от 0 до 1; пустой текст — убрать.
func set_channel(text: String, k: float, left: float) -> void:
	if chan_box == null:
		return
	chan_box.visible = text != ""
	if text == "":
		return
	chan_bar.size.x = 332.0 * clampf(k, 0.0, 1.0)
	chan_lbl.text = "%s · %.1f" % [text, maxf(left, 0.0)]


func announce(text: String, color: Color, dur := 2.5) -> void:
	if announce_box == null:
		return
	var l := _label(text, 26, color, 6)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	announce_box.add_child(l)
	while announce_box.get_child_count() > 3:
		var c := announce_box.get_child(0)
		announce_box.remove_child(c)
		c.queue_free()
	l.modulate.a = 0.0
	var tw := l.create_tween()
	tw.tween_property(l, "modulate:a", 1.0, 0.2)
	tw.tween_interval(dur)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(l.queue_free)


func error(text: String) -> void:
	error_label.text = text
	error_label.modulate.a = 1.0
	if error_tween:
		error_tween.kill()
	error_tween = error_label.create_tween()
	error_tween.tween_interval(1.4)
	error_tween.tween_property(error_label, "modulate:a", 0.0, 0.5)


func flash(c: Color, t: float) -> void:
	flash_rect.color = c
	var tw := flash_rect.create_tween()
	tw.tween_property(flash_rect, "color:a", 0.0, t)


func kill_feed(killer: Hero, victim: Hero) -> void:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_theme_font_size_override("normal_font_size", 15)
	r.add_theme_constant_override("outline_size", 4)
	r.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	var vc := Data.TEAM_COLORS[victim.team].lightened(0.3).to_html(false)
	if killer:
		var kc := Data.TEAM_COLORS[killer.team].lightened(0.3).to_html(false)
		r.text = "[right][color=#%s]%s[/color] убивает [color=#%s]%s[/color][/right]" % [kc, killer.display_name, vc, victim.display_name]
	else:
		r.text = "[right][color=#%s]%s[/color] погибает[/right]" % [vc, victim.display_name]
	feed_box.add_child(r)
	while feed_box.get_child_count() > 5:
		var c := feed_box.get_child(0)
		feed_box.remove_child(c)
		c.queue_free()
	var tw := r.create_tween()
	tw.tween_interval(7.0)
	tw.tween_property(r, "modulate:a", 0.0, 0.8)
	tw.tween_callback(r.queue_free)


func add_float_text(pos: Vector3, text: String, color: Color, big := false) -> void:
	float_texts.append({"pos": pos, "text": text, "color": color, "t": 0.0, "big": big, "dx": randf_range(-26.0, 26.0)})
	if float_texts.size() > 60:
		float_texts.pop_front()


func _update_floats(delta: float) -> void:
	var i := 0
	while i < float_texts.size():
		float_texts[i].t += delta
		if float_texts[i].t > 1.0:
			float_texts.remove_at(i)
		else:
			i += 1


# ----------------------------------------------------------------- окна
func mouse_over_ui() -> bool:
	return get_viewport().gui_get_hovered_control() != null


func toggle_shop() -> void:
	if Game.I.state != "playing":
		return
	shop_panel.visible = not shop_panel.visible
	if shop_panel.visible:
		_refresh_shop_status()
		Audio.sfx("ui_click", null, 0.5)


## Герой в своём лагере: покупки сразу в инвентарь, можно продавать.
func can_shop() -> bool:
	var pl := Game.I.player
	if pl == null or not pl.alive:
		return false
	var z: Zone = Game.I.zones[pl.home_zone]
	return pl.area == pl.home_zone and (z.in_base(pl.global_position) or pl.flat_dist_p(z.shop_pos) < 10.0)


func _refresh_shop_status() -> void:
	if can_shop():
		shop_status.text = "ЛКМ по предмету — сборка справа, ПКМ — купить (сборные: докупить все части сразу). Когда части лежат в инвентаре или рюкзаке, предмет собирается сам."
		shop_status.add_theme_color_override("font_color", DIM)
	else:
		shop_status.text = "Вы не в лагере: купленное ляжет «в лагерь», курьер привезёт его — кнопка C. Продавать можно только в лагере."
		shop_status.add_theme_color_override("font_color", Color(1.0, 0.8, 0.5))


func send_courier() -> void:
	var pl := Game.I.player
	if pl == null or pl.courier == null:
		return
	var err := pl.courier.send()
	if err != "":
		error(err)
		Audio.sfx("ui_error", null, 0.5)
	else:
		announce("Курьер вылетел", Color(1.0, 0.85, 0.5), 1.2)


func try_buy(id: String, quick := false) -> void:
	var pl := Game.I.player
	if pl == null or not pl.alive:
		error("Герой мёртв — дождитесь воскрешения")
		Audio.sfx("ui_error", null, 0.5)
		return
	var remote := not can_shop()
	if remote and pl.courier == null:
		error("Подойдите к лавке у своего кристалла")
		Audio.sfx("ui_error", null, 0.5)
		return
	var err := pl.quick_buy(id, remote) if quick else pl.buy(id, remote)
	if err != "":
		error(err)
		Audio.sfx("ui_error", null, 0.5)
	elif remote:
		Audio.sfx("buy", null, 0.6)
		announce("Куплено: %s — лежит в лагере, курьер привезёт (C)" % Data.ITEMS[id].name, Color(1.0, 0.85, 0.5), 2.0)
	else:
		Fx.ring_burst(Game.I.fx_root, Game.I.player.global_position, 1.6, GOLD, 0.4)
		Audio.sfx("buy", null, 0.7)
		if id.begins_with("set_"):
			Audio.sfx("transform", null, 0.8)


func toggle_scores(show: bool) -> void:
	scores_panel.visible = show and Game.I.state == "playing"
	if scores_panel.visible:
		_refresh_scores()


func _refresh_scores() -> void:
	for c in scores_grid.get_children():
		c.queue_free()
	for h in ["Команда", "Герой", "Ур.", "Убийства", "Смерти", "Золото", "Сет"]:
		scores_grid.add_child(_label(h, 14, DIM))
	for t in 3:
		for h: Hero in Game.I.teams[t].heroes:
			var col: Color = Data.TEAM_COLORS[t].lightened(0.3)
			scores_grid.add_child(_label(Data.TEAM_NAMES[t], 15, col))
			scores_grid.add_child(_label(h.display_name + (" (вы)" if h == Game.I.player else ""), 15, TEXT))
			scores_grid.add_child(_label(str(h.level), 15, TEXT))
			scores_grid.add_child(_label(str(h.kills), 15, TEXT))
			scores_grid.add_child(_label(str(h.deaths), 15, TEXT))
			scores_grid.add_child(_label(str(h.gold), 15, GOLD))
			scores_grid.add_child(_label("★" if h.has_set() else "—", 15, GOLD if h.has_set() else DIM))


func toggle_menu() -> void:
	if Game.I.state == "select":
		return
	menu_panel.visible = not menu_panel.visible
	get_tree().paused = menu_panel.visible and Game.I.state == "playing"
	if menu_panel.visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif not Game.I.sim:
		Input.mouse_mode = Input.MOUSE_MODE_CONFINED


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and (e as InputEventKey).physical_keycode == KEY_ESCAPE:
		var g := Game.I
		if g and g.state != "select" and g.targeting < 0 and not g.attack_move_mode:
			if shop_panel.visible:
				shop_panel.visible = false
			elif inspecting():
				g.inspected = null
			else:
				toggle_menu()
			get_viewport().set_input_as_handled()


func show_end(win: bool) -> void:
	shop_panel.visible = false
	scores_panel.visible = false
	end_layer = Control.new()
	root.add_child(end_layer)
	end_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.6)
	end_layer.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	end_layer.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _sb(Color(0.05, 0.06, 0.1, 0.96), BORDER, 12, 1, 28))
	center.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	p.add_child(v)
	var t := _label("ПОБЕДА" if win else "ПОРАЖЕНИЕ", 56, GOLD if win else Color(1, 0.4, 0.35), 10)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var g := Game.I
	var l := _label("Ваша команда выстояла дольше всех." if win else "Кристалл выживания вашей команды разрушен.", 18, TEXT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	var pl := g.player
	var st := _label("Время %s · Волна %d · Уровень %d · Убийства %d · Монстров %d · Смерти %d" % [
		_fmt_time(g.time), g.wave, pl.level, pl.kills, pl.creep_kills, pl.deaths], 16, DIM)
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(st)
	var b := _button("Играть снова", func():
		get_tree().paused = false
		get_tree().reload_current_scene())
	b.custom_minimum_size = Vector2(220, 44)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_child(b)
	v.add_child(hb)


# ================================================================= элементы
class Bar extends Control:
	var value := 1.0
	var max_value := 1.0
	var color := Color.GREEN
	var text := ""
	var font_size := 13
	## След урона: светлая полоска, которая догоняет значение после потери (как в Dota)
	var trail := false
	## Скос полосы (параллелограмм) и простой вид для тонких полос
	var skew := 0.0
	var plain := false
	var _trail_k := 1.0
	var _hold := 0.0
	var _last_k := 1.0

	var _sb_bg := StyleBoxFlat.new()
	var _sb_tr := StyleBoxFlat.new()
	var _sb_base := StyleBoxFlat.new()
	var _sb_mid := StyleBoxFlat.new()
	var _sb_shine := StyleBoxFlat.new()
	var _sb_edge := StyleBoxFlat.new()

	func _ready() -> void:
		if not plain:
			mouse_filter = Control.MOUSE_FILTER_IGNORE
		_sb_bg.bg_color = Color(0.03, 0.0, 0.05, 0.92)
		_sb_bg.border_color = Color(0, 0, 0, 0.9)
		_sb_bg.set_border_width_all(1)
		_sb_tr.bg_color = Color(1.0, 0.95, 0.8, 0.75)
		_sb_shine.bg_color = Color(1, 1, 1, 0.32)
		_sb_edge.draw_center = false
		_sb_edge.border_color = Color(Hud.ACC, 0.55)
		_sb_edge.set_border_width_all(1)
		_sb_edge.border_color = Color(1, 1, 1, 0.28)
		for sb in [_sb_bg, _sb_tr, _sb_base, _sb_mid, _sb_shine, _sb_edge]:
			(sb as StyleBoxFlat).anti_aliasing = true
			(sb as StyleBoxFlat).skew = Vector2(skew, 0)

	func _process(d: float) -> void:
		var k := clampf(value / maxf(max_value, 0.001), 0.0, 1.0)
		if k < _last_k - 0.0001:
			_hold = 0.45
		_last_k = k
		if _trail_k < k:
			_trail_k = k
		elif _hold > 0.0:
			_hold -= d
		else:
			_trail_k = move_toward(_trail_k, k, d * 0.6)
		queue_redraw()

	func _draw() -> void:
		var h := size.y
		if plain:
			draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.06, 0.9))
			draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * clampf(value / maxf(max_value, 0.001), 0.0, 1.0), h)), color)
			return
		var rad := 2 if skew != 0.0 else int(minf(h * 0.5, 10.0))
		var r := Rect2(Vector2.ZERO, size)
		_sb_bg.set_corner_radius_all(rad)
		draw_style_box(_sb_bg, r)
		var k := clampf(value / maxf(max_value, 0.001), 0.0, 1.0)
		var inner := r.grow(-2.0)
		var irad := maxi(1, rad - 2)
		if trail and _trail_k > k + 0.002:
			_sb_tr.set_corner_radius_all(irad)
			draw_style_box(_sb_tr, Rect2(inner.position, Vector2(inner.size.x * _trail_k, inner.size.y)))
		if k > 0.0:
			var w := maxf(inner.size.x * k, float(irad) * 2.0)
			var fr := Rect2(inner.position, Vector2(w, inner.size.y))
			_sb_base.bg_color = color.darkened(0.25)
			_sb_base.set_corner_radius_all(irad)
			draw_style_box(_sb_base, fr)
			_sb_mid.bg_color = color
			_sb_mid.set_corner_radius_all(irad)
			draw_style_box(_sb_mid, Rect2(fr.position, Vector2(fr.size.x, fr.size.y * 0.7)))
			_sb_shine.set_corner_radius_all(irad)
			draw_style_box(_sb_shine, Rect2(fr.position + Vector2(2, 1), Vector2(maxf(0.0, fr.size.x - 4), fr.size.y * 0.32)))
			# тонкие деления, как у полос в Dota: каждые 10%
			if inner.size.x > 100 and h >= 12:
				for i in range(1, 10):
					var x := inner.position.x + inner.size.x * i / 10.0
					if x < fr.end.x - 1:
						draw_line(Vector2(x, inner.position.y + inner.size.y * 0.55), Vector2(x, inner.end.y), Color(0, 0, 0, 0.28), 1.0)
		_sb_edge.set_corner_radius_all(rad)
		draw_style_box(_sb_edge, r)
		if text != "":
			var f := ThemeDB.fallback_font
			var ts := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
			var p := Vector2((size.x - ts.x) / 2.0, (size.y + ts.y) / 2.0 - f.get_descent(font_size))
			draw_string_outline(f, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, Color(0, 0, 0, 0.9))
			draw_string(f, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)


## Портрет героя в верхней полосе: рамка цвета команды (у своего героя — золотая), уровень,
## у погибшего — серый портрет и секунды до возрождения. Щелчок — осмотреть героя.
class TeamFace extends Control:
	var hero: Hero
	var _tex: Texture2D

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		_tex = HeroAssets.icon(hero.hero_id, "")
		if _tex == null:
			_tex = HeroAssets.portrait(hero.hero_id)

	func _process(_d: float) -> void:
		queue_redraw()

	func _get_tooltip(_p: Vector2) -> String:
		if hero == null or not is_instance_valid(hero):
			return ""
		return "%s · %s · уровень %d\nУбийства %d · смерти %d%s" % [hero.display_name, Data.TEAM_NAMES[hero.team], hero.level,
			hero.kills, hero.deaths, "\nУльтимативный сет собран" if hero.has_set() else ""]

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			var g := Game.I
			g.inspected = hero if hero != g.player and hero.alive else null
			accept_event()

	func _draw() -> void:
		if hero == null or not is_instance_valid(hero):
			return
		var r := Rect2(Vector2.ZERO, size)
		var f := ThemeDB.fallback_font
		var dead := not hero.alive
		draw_rect(r, Color(0.02, 0.03, 0.06))
		if _tex:
			draw_texture_rect(_tex, r.grow(-2), false, Color(0.35, 0.35, 0.4) if dead else Color.WHITE)
		else:
			draw_string(f, Vector2(12, 30), hero.display_name.substr(0, 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)
		var me := hero == Game.I.player
		draw_rect(r.grow(-1), Hud.ACC if me else Data.TEAM_COLORS[hero.team], false, 2.0)
		if Game.I.inspected == hero:
			draw_rect(r.grow(1), Color.WHITE, false, 1.0)
		if dead and hero.respawn_left > 0.0:
			var t := str(ceili(hero.respawn_left))
			var ts := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
			var p := Vector2((size.x - ts.x) / 2.0, size.y / 2.0 + 7)
			draw_string_outline(f, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, 5, Color(0, 0, 0, 0.9))
			draw_string(f, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1.0, 0.85, 0.8))
		else:
			var lv := str(hero.level) + ("★" if hero.has_set() else "")
			var lw := f.get_string_size(lv, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			draw_rect(Rect2(size.x - lw - 6, size.y - 15, lw + 5, 14), Color(0, 0, 0, 0.75))
			draw_string(f, Vector2(size.x - lw - 3, size.y - 4), lv, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Hud.ACC if hero.has_set() else Color.WHITE)


## Картинка консоли ATS: растягивается на свой прямоугольник, клики ловит только непрозрачными местами.
class AtsArt extends Control:
	var tex: Texture2D
	var discs: Array = []   # [центр, радиус] в пикселях текстуры — тёмные круги под прозрачными окнами
	var _img: Image

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		if tex:
			_img = tex.get_image()
			if _img and _img.is_compressed():
				_img.decompress()
		resized.connect(queue_redraw)

	func _draw() -> void:
		if tex == null:
			return
		var k := Vector2(size.x / tex.get_width(), size.y / tex.get_height())
		for d in discs:
			var c: Vector2 = d[0]
			draw_circle(c * k, float(d[1]) * k.y, Color(0.03, 0.0, 0.06, 0.95))
		draw_texture_rect(tex, Rect2(Vector2.ZERO, size), false)

	func _has_point(p: Vector2) -> bool:
		if _img == null or size.x <= 0.0 or size.y <= 0.0:
			return false
		var x := int(p.x / size.x * _img.get_width())
		var y := int(p.y / size.y * _img.get_height())
		if x < 0 or y < 0 or x >= _img.get_width() or y >= _img.get_height():
			return false
		return _img.get_pixel(x, y).a > 0.35


## Кнопка в ячейке верхней полосы: сама ячейка — рамка, кнопка только подсвечивается.
class TopButton extends Control:
	var text := ""
	var key := ""
	var cb: Callable

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		tooltip_text = "%s [%s]" % [text, key]
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			Audio.sfx("ui_click", null, 0.5)
			cb.call()
			accept_event()

	func _draw() -> void:
		var hov := get_global_rect().has_point(get_global_mouse_position())
		var r := Rect2(Vector2.ZERO, size).grow(-1.0)
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(5)
		sb.anti_aliasing = true
		sb.bg_color = Color(0.55, 0.15, 0.85, 0.32) if hov else Color(0.25, 0.05, 0.4, 0.18)
		draw_style_box(sb, r)
		var f: Font = Hud.font_title
		var fs := 17
		var ks := 12
		var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var kw := Hud.font_ui.get_string_size(" " + key, HORIZONTAL_ALIGNMENT_LEFT, -1, ks).x
		var x := (size.x - tw - kw) / 2.0
		var y := size.y / 2.0 + fs * 0.34
		draw_string_outline(f, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.9))
		draw_string(f, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1) if hov else Color(0.97, 0.88, 1.0))
		draw_string_outline(Hud.font_ui, Vector2(x + tw, y), " " + key, HORIZONTAL_ALIGNMENT_LEFT, -1, ks, 3, Color(0, 0, 0, 0.9))
		draw_string(Hud.font_ui, Vector2(x + tw, y), " " + key, HORIZONTAL_ALIGNMENT_LEFT, -1, ks, Hud.ACC_HI)


class Coin extends Control:
	func _draw() -> void:
		var c := size / 2.0
		draw_circle(c, 8.0, Color(0.85, 0.6, 0.15))
		draw_circle(c, 6.5, Color(1.0, 0.82, 0.3))
		draw_circle(c + Vector2(-2, -2), 2.0, Color(1, 0.95, 0.7))


## Иконка способности: своя картинка из папки героя или нарисованная кодом.
class AbilityIcon extends Control:
	var ability_id := ""
	var hero_id := ""
	var key := ""

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var tex := HeroAssets.icon(hero_id, key) if hero_id != "" else null
		if tex:
			draw_texture_rect(tex, r, false)
		else:
			Icons.ability(self, ability_id, r)


class AbilityButton extends Control:
	var idx := 0

	func _ready() -> void:
		custom_minimum_size = Vector2(64, 64)
		mouse_filter = Control.MOUSE_FILTER_STOP
		tooltip_text = " "

	func _process(_d: float) -> void:
		queue_redraw()

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			if Game.I and Game.I.player and not Game.I.hud.inspecting() and idx < Game.I.player.abilities.size():
				var me: Hero = Game.I.player
				var plus: bool = idx < 4 and me.learn_error(idx) == ""
				# щелчок по «+» (верх кнопки), Ctrl+щелчок или щелчок по неизученной — вложить очко
				if plus and ((e as InputEventMouseButton).position.y < 20.0 or (e as InputEventMouseButton).ctrl_pressed
						or me.skill_level(idx) <= 0):
					me.learn(idx)
				else:
					Game.I._begin_targeting(idx)
			accept_event()

	func _get_tooltip(_p: Vector2) -> String:
		var pl: Hero = Game.I.hud.view_hero() if Game.I and Game.I.hud else null
		if pl == null or idx >= pl.abilities.size():
			return ""
		var a: Dictionary = pl.abilities[idx].def
		var ov := pl.w3_slot(idx)
		if not ov.is_empty():
			return "%s — следующий этап  [%s]\nМана: %d · Перезарядка: %d с" % [a.name, Hud.key_of(pl, idx), int(ov.mana), int(ov.cd)]
		var s := "%s  [%s]\n%s\n" % [a.name, Hud.key_of(pl, idx), a.desc]
		if a.type == "book":
			return s + "\nКнига заклинаний: её способности — на кнопках над панелью"
		if a.type == "empty":
			return ""
		if a.type == "passive":
			s += "\nПассивная способность"
		else:
			var p := pl.ability_power(idx)
			if p > 0.0:
				s += "\nСила удара сейчас: %d" % int(p)
			s += "\nМана: %d · Перезарядка: %d с" % [int(a.mana), int(a.cd)]
		if a.get("set", false) and not pl.has_set():
			s += "\nНужен Ультимативный сет героя (лавка → «Сет героя»)"
		elif idx < 4:
			s += "\nУровень: %d / %d" % [pl.skill_level(idx), Data.SKILL_MAX[idx]]
			if pl == Game.I.player and pl.skill_points > 0:
				var le := pl.learn_error(idx)
				s += "\n" + ("Щёлкните «+» или Ctrl+%s, чтобы улучшить" % "QWER"[idx] if le == "" else le)
		return s

	func _draw() -> void:
		var pl: Hero = Game.I.hud.view_hero() if Game.I and Game.I.hud else null
		if pl == null or idx >= pl.abilities.size():
			Hud.draw_empty_cell(self)
			return
		var ab: Dictionary = pl.abilities[idx]
		var a: Dictionary = ab.def
		var r := Rect2(Vector2.ZERO, size)
		if a.type == "empty":
			Hud.draw_empty_cell(self)
			return
		var ov := pl.w3_slot(idx)
		var tex: Texture2D = null
		if not ov.is_empty():
			tex = HeroAssets.icon(pl.hero_id, str(ov.key))
		if tex == null:
			tex = HeroAssets.icon(pl.hero_id, Hud.icon_key(pl, idx))
		if tex:
			draw_texture_rect(tex, r, false)
		else:
			Icons.ability(self, ab.id, r)
		if not ov.is_empty():
			# второй этап способности: подсветка рамки
			var pulse := 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.008)
			draw_rect(r.grow(-1), Color(0.5, 0.95, 1.0, pulse), false, 3.0)
			var ocd := float(pl.w3_cd.get(ov.id, 0.0))
			var ff := ThemeDB.fallback_font
			if ocd > 0.0:
				draw_rect(Rect2(0, 0, size.x, size.y * clampf(ocd / maxf(float(ov.cd), 0.01), 0.0, 1.0)), Color(0, 0, 0, 0.65))
				var ot := str(ceili(ocd))
				draw_string_outline(ff, Vector2(0, size.y / 2 + 9), ot, HORIZONTAL_ALIGNMENT_CENTER, size.x, 24, 4, Color(0, 0, 0))
				draw_string(ff, Vector2(0, size.y / 2 + 9), ot, HORIZONTAL_ALIGNMENT_CENTER, size.x, 24, Color.WHITE)
			elif pl.mp < float(ov.mana):
				draw_rect(r, Color(0.1, 0.2, 0.7, 0.45))
			draw_rect(Rect2(2, 2, 18, 18), Color(0, 0, 0, 0.7))
			draw_string(ff, Vector2(2, 16), Hud.key_of(pl, idx), HORIZONTAL_ALIGNMENT_CENTER, 18, 14, Color(0.6, 1, 1))
			return
		var is_set: bool = a.get("set", false)
		var locked: bool = (is_set and not pl.has_set()) or (not is_set and pl.skill_level(idx) <= 0)
		var f := ThemeDB.fallback_font
		if locked:
			draw_rect(r, Color(0, 0, 0, 0.72))
			var tx := "сет" if is_set else ("ульт: %d ур." % Data.ULT_LEVELS[0] if idx == 3 and pl.level < Data.ULT_LEVELS[0] else "не изучено")
			draw_string(f, Vector2(0, size.y / 2 + 6), tx, HORIZONTAL_ALIGNMENT_CENTER, size.x, 14, Color(0.85, 0.85, 0.9))
		elif a.type == "passive":
			draw_rect(Rect2(0, size.y - 16, size.x, 16), Color(0, 0, 0, 0.6))
			draw_string(f, Vector2(0, size.y - 4), "пассив", HORIZONTAL_ALIGNMENT_CENTER, size.x, 11, Color(0.8, 0.8, 0.9))
		elif ab.cd > 0.0 and not (idx == 4 and pl.hero_id == "akame" and pl.has_buff("akame_d")):
			var k: float = ab.cd / maxf(a.cd, 0.01)
			draw_rect(Rect2(0, 0, size.x, size.y * clampf(k, 0.0, 1.0)), Color(0, 0, 0, 0.65))
			var t := str(ceili(ab.cd))
			draw_string_outline(f, Vector2(0, size.y / 2 + 9), t, HORIZONTAL_ALIGNMENT_CENTER, size.x, 24, 4, Color(0, 0, 0))
			draw_string(f, Vector2(0, size.y / 2 + 9), t, HORIZONTAL_ALIGNMENT_CENTER, size.x, 24, Color.WHITE)
		elif pl.mp < a.mana:
			draw_rect(r, Color(0.1, 0.2, 0.7, 0.45))
		var active := Game.I.targeting == idx and pl == Game.I.player
		var frame := Color(1.0, 0.45, 0.3) if is_set and not locked else Color(0.92, 0.94, 1.0, 0.8)
		draw_rect(r, Color(1.0, 0.85, 0.4) if active else frame, false, 2.0 if active or is_set else 1.0)
		draw_rect(Rect2(2, 2, 18, 18), Color(0, 0, 0, 0.7))
		draw_string(f, Vector2(2, 16), Hud.key_of(pl, idx), HORIZONTAL_ALIGNMENT_CENTER, 18, 14, Color(1, 0.9, 0.6))
		if a.type != "passive" and not locked:
			var mt := str(int(a.mana))
			draw_string_outline(f, Vector2(0, size.y - 4), mt, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 4, 12, 3, Color(0, 0, 0))
			draw_string(f, Vector2(0, size.y - 4), mt, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 4, 12, Color(0.6, 0.75, 1.0))
		if idx < 4 and not is_set:
			# уровень способности — точки слева внизу; «+» — есть очко и можно улучшить
			for k in Data.SKILL_MAX[idx]:
				draw_rect(Rect2(4 + k * 8, size.y - 9, 6, 5), Color(1.0, 0.85, 0.35) if k < pl.skill_level(idx) else Color(0.25, 0.25, 0.3, 0.9))
			if pl == Game.I.player and pl.learn_error(idx) == "":
				var pr := Rect2(size.x - 22, 0, 22, 20)
				draw_rect(pr, Color(1.0, 0.8, 0.2, 0.95 if int(Time.get_ticks_msec() / 400.0) % 2 == 0 else 0.7))
				draw_string(f, Vector2(size.x - 22, 16), "+", HORIZONTAL_ALIGNMENT_CENTER, 22, 18, Color(0.1, 0.08, 0.0))


class ItemSlot extends Control:
	var slot := 0

	func _ready() -> void:
		custom_minimum_size = Vector2(46, 40)
		mouse_filter = Control.MOUSE_FILTER_STOP
		tooltip_text = " "

	func _process(_d: float) -> void:
		queue_redraw()

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			if Game.I and Game.I.player and not Game.I.hud.inspecting():
				var err := Game.I.player.use_item(slot)
				if err != "":
					Game.I.hud.error(err)
			accept_event()

	func _get_tooltip(_p: Vector2) -> String:
		var vu: Unit = Game.I.hud.view_unit() if Game.I and Game.I.hud else null
		var pl := vu as Hero
		if vu != null and pl == null:
			return ""
		if pl == null or pl.items[slot] == "":
			return "Пустой слот [%d]" % (slot + 1)
		var d: Dictionary = Data.ITEMS[pl.items[slot]]
		return "%s  [%d] · класс %s\n%s" % [d.name, slot + 1, d.cls, Data.item_desc(pl.items[slot])]

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0.03, 0.04, 0.07, 0.95))
		var pl: Hero = Game.I.hud.view_hero() if Game.I and Game.I.hud else null
		var f := ThemeDB.fallback_font
		if pl and pl.items[slot] != "":
			var id: String = pl.items[slot]
			Icons.item(self, id, r.grow(-3))
			var d: Dictionary = Data.ITEMS[id]
			if d.has("active"):
				var cd := pl.item_cooldown(id)
				if cd > 0.0:
					draw_rect(Rect2(0, 0, size.x, size.y * clampf(cd / float(d.active.cd), 0.0, 1.0)), Color(0, 0, 0, 0.65))
					draw_string_outline(f, Vector2(0, size.y / 2 + 6), str(ceili(cd)), HORIZONTAL_ALIGNMENT_CENTER, size.x, 16, 3, Color.BLACK)
					draw_string(f, Vector2(0, size.y / 2 + 6), str(ceili(cd)), HORIZONTAL_ALIGNMENT_CENTER, size.x, 16, Color.WHITE)
				else:
					draw_rect(r.grow(-1), Color(0.5, 1.0, 0.6, 0.7), false, 1.5)
			if d.get("consumable", false) and pl.item_ch[slot] > 1:
				var t := str(pl.item_ch[slot])
				draw_string_outline(f, Vector2(0, size.y - 3), t, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 3, 12, 3, Color.BLACK)
				draw_string(f, Vector2(0, size.y - 3), t, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 3, 12, Color.WHITE)
		draw_rect(r, Color(0.92, 0.94, 1.0, 0.5), false, 1.0)
		draw_string(f, Vector2(3, 12), str(slot + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.55))
		if pl and pl == Game.I.player:
			Hud.draw_craft_flash(self, pl.items[slot])


class ShopSlot extends Control:
	var slot := 0
	var stash := false
	## Ячейка «в лагере» (ждёт курьера)
	var base := false
	var hud: Hud

	func _ready() -> void:
		custom_minimum_size = Vector2(54, 48)
		mouse_filter = Control.MOUSE_FILTER_STOP
		tooltip_text = " "

	func _process(_d: float) -> void:
		queue_redraw()

	func _id() -> String:
		var pl := Game.I.player if Game.I else null
		if pl == null:
			return ""
		if base:
			return pl.base_items[slot]
		return pl.stash[slot] if stash else pl.items[slot]

	func _gui_input(e: InputEvent) -> void:
		if not (e is InputEventMouseButton and e.pressed):
			return
		var pl := Game.I.player
		if pl == null:
			return
		var mb := e as InputEventMouseButton
		var err := ""
		if base:
			if mb.button_index == MOUSE_BUTTON_LEFT:
				if hud.can_shop():
					pl.collect_base()
				else:
					err = "Это лежит в лагере — нажмите C, курьер привезёт"
			elif mb.button_index == MOUSE_BUTTON_RIGHT:
				if not hud.can_shop():
					err = "Продавать можно только в лагере"
				else:
					err = pl.sell_base(slot)
					if err == "":
						Audio.sfx("coin", null, 0.6)
			if err != "":
				hud.error(err)
			accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			err = pl.swap_stash(slot, stash)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			if not hud.can_shop():
				err = "Продавать можно только в лагере"
			else:
				err = pl.sell(slot, stash)
				if err == "":
					Audio.sfx("coin", null, 0.6)
		if err != "":
			hud.error(err)
		accept_event()

	func _get_tooltip(_p: Vector2) -> String:
		var id := _id()
		if id == "":
			return "Пусто"
		var d: Dictionary = Data.ITEMS[id]
		return "%s · класс %s\n%s" % [d.name, d.cls, Data.item_desc(id)]

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0.03, 0.04, 0.07, 0.95))
		var id := _id()
		if id != "":
			Icons.item(self, id, r.grow(-3))
		draw_rect(r, Color(0.92, 0.94, 1.0, 0.5), false, 1.0)
		Hud.draw_craft_flash(self, id)


class ShopCard extends PanelContainer:
	var item_id := ""
	var hud: Hud
	var hover := false
	var comp_label: RichTextLabel

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		custom_minimum_size = Vector2(262, 118)
		_style()
		mouse_entered.connect(func():
			hover = true
			_style())
		mouse_exited.connect(func():
			hover = false
			_style())
		var d: Dictionary = Data.ITEMS[item_id]
		if str(d.get("shop", "")) != "":
			tooltip_text = "В карте продаётся в лавке «%s» (%s)" % [d.shop, d.map]
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(h)
		var ic := ItemIcon.new()
		ic.item_id = item_id
		ic.custom_minimum_size = Vector2(46, 46)
		ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		h.add_child(ic)
		var v := VBoxContainer.new()
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_theme_constant_override("separation", 1)
		h.add_child(v)
		var top := HBoxContainer.new()
		top.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(top)
		var n := hud._label(d.name, 14, Hud.TEXT)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		top.add_child(n)
		top.add_child(hud._label(d.cls, 13, Hud.CLS_COLORS.get(d.cls, Hud.TEXT), 2))
		var recipe: Array = d.get("recipe", [])
		var price := "%d золота" % d.price if recipe.is_empty() else "рецепт +%d · всего %d" % [d.price, Data.recipe_total(item_id)]
		if recipe.size() > 0:
			tooltip_text = (tooltip_text + "\n" if tooltip_text != "" else "") + "ЛКМ — показать сборку · ПКМ — докупить всё и собрать"
		v.add_child(hud._label(price, 13, Hud.GOLD))
		var ds := hud._label(Data.item_desc(item_id), 12, Hud.DIM)
		ds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ds.custom_minimum_size.x = 180
		v.add_child(ds)
		if recipe.size() > 0:
			comp_label = RichTextLabel.new()
			comp_label.bbcode_enabled = true
			comp_label.fit_content = true
			comp_label.scroll_active = false
			comp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			comp_label.add_theme_font_size_override("normal_font_size", 11)
			comp_label.custom_minimum_size.x = 180
			v.add_child(comp_label)

	func _process(_d: float) -> void:
		var pl := Game.I.player if Game.I else null
		if pl == null:
			return
		visible = pl.can_own(item_id)
		if comp_label and hud.shop_panel.visible:
			var need := {}
			for c in Data.ITEMS[item_id].recipe:
				need[c] = need.get(c, 0) + 1
			var parts: PackedStringArray = []
			for c in need:
				var have := pl.count_owned(c)
				var col := "#7fe08a" if have >= need[c] else "#c8c8d0"
				var nm: String = Data.ITEMS[c].name
				if need[c] > 1:
					nm += " ×%d" % need[c]
				parts.append("[color=%s]%s%s[/color]" % [col, "✓ " if have >= need[c] else "", nm])
			comp_label.text = " + ".join(parts)

	func _style() -> void:
		var sel := hud.shop_sel == item_id
		var c := Color(1.0, 0.82, 0.45, 0.95) if hover or sel else Color(0.92, 0.94, 1.0, 0.3)
		var bg := Color(0.17, 0.16, 0.12) if sel else (Color(0.14, 0.15, 0.24) if hover else Color(0.09, 0.1, 0.16))
		add_theme_stylebox_override("panel", hud._sb(bg, c, 8, 2 if sel else 1, 8))

	func _gui_input(e: InputEvent) -> void:
		if not (e is InputEventMouseButton and e.pressed):
			return
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			hud.shop_select(item_id)
			if mb.double_click:
				hud.try_buy(item_id, true)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			hud.shop_select(item_id)
			hud.try_buy(item_id, true)
			accept_event()


class ItemIcon extends Control:
	var item_id := ""

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.04, 0.07))
		Icons.item(self, item_id, Rect2(Vector2.ZERO, size).grow(-3))


# ----------------------------------------------------------------- полоски над юнитами
class Overlay extends Control:
	var hud: Hud

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var g := Game.I
		if g == null or g.camera == null:
			return
		var cam := g.camera
		var f := ThemeDB.fallback_font
		var vs := get_viewport_rect().size
		for u in g.units:
			if not u.alive or not u.visible or (u.model and not u.model.visible):
				continue
			var wp := u.global_position + Vector3(0, u.bar_height, 0)
			if cam.is_position_behind(wp):
				continue
			var sp := cam.unproject_position(wp)
			if sp.x < -100 or sp.y < -100 or sp.x > vs.x + 100 or sp.y > vs.y + 100:
				continue
			var w := 46.0
			var h := 6.0
			var col := Color(0.92, 0.28, 0.22)
			var is_hero := u is Hero
			if is_hero:
				w = 76.0
				h = 8.0
				col = Data.TEAM_COLORS[u.team].lightened(0.1)
			elif u.kind == Unit.Kind.BOSS:
				w = 130.0
				h = 9.0
				col = Color(1.0, 0.35, 0.15)
			elif u.kind == Unit.Kind.CRYSTAL:
				w = 150.0
				h = 10.0
				col = Data.TEAM_COLORS[u.team]
			var zoom_k := clampf(34.0 / cam.dist, 0.7, 1.4)
			w *= zoom_k
			var x := sp.x - w / 2.0
			var y := sp.y
			var k := clampf(u.hp / u.max_hp, 0.0, 1.0)
			if u == g.player:
				draw_rect(Rect2(x - 3, y - 3, w + 6, h + 6), Color(1.0, 0.86, 0.4, 0.9))
			draw_rect(Rect2(x - 1, y - 1, w + 2, h + 2), Color(0, 0, 0, 0.75))
			draw_rect(Rect2(x, y, w * k, h), col)
			draw_rect(Rect2(x, y, w * k, h * 0.4), col.lightened(0.3))
			if u.dot_time > 0.0:
				draw_rect(Rect2(x, y + h - 2, w * k, 2), Color(0.5, 1.0, 0.2))
			if is_hero:
				var hero := u as Hero
				var mk := clampf(hero.mp / maxf(hero.max_mp, 1.0), 0.0, 1.0)
				draw_rect(Rect2(x - 1, y + h + 1, w + 2, 5), Color(0, 0, 0, 0.75))
				draw_rect(Rect2(x, y + h + 2, w * mk, 3), Color(0.35, 0.6, 1.0))
				draw_rect(Rect2(x - 22, y - 2, 20, 16), Color(0, 0, 0, 0.8))
				draw_string(f, Vector2(x - 22, y + 11), str(hero.level), HORIZONTAL_ALIGNMENT_CENTER, 20, 12, Color(1, 0.85, 0.4))
				var name_col: Color = Color(1.0, 0.9, 0.55) if u == g.player else Data.TEAM_COLORS[u.team].lightened(0.35)
				var nm := hero.display_name + (" ★" if hero.has_set() else "")
				draw_string_outline(f, Vector2(x - 30, y - 5), nm, HORIZONTAL_ALIGNMENT_CENTER, w + 60, 13, 3, Color(0, 0, 0, 0.9))
				draw_string(f, Vector2(x - 30, y - 5), nm, HORIZONTAL_ALIGNMENT_CENTER, w + 60, 13, name_col)
				if hero.stun > 0.0:
					draw_string(f, Vector2(x, y + 24), "заморожен" if hero.frozen_ice > 0.0 else "оглушён", HORIZONTAL_ALIGNMENT_CENTER, w, 11, Color(0.7, 0.9, 1.0))
			elif u.kind == Unit.Kind.BOSS:
				draw_string_outline(f, Vector2(x, y - 5), u.display_name, HORIZONTAL_ALIGNMENT_CENTER, w, 14, 3, Color(0, 0, 0, 0.9))
				draw_string(f, Vector2(x, y - 5), u.display_name, HORIZONTAL_ALIGNMENT_CENTER, w, 14, Color(1, 0.6, 0.4))
		for ft in hud.float_texts:
			var wp2: Vector3 = ft.pos
			if cam.is_position_behind(wp2):
				continue
			var sp2 := cam.unproject_position(wp2) + Vector2(ft.dx, -ft.t * 46.0)
			var a := clampf(1.4 - ft.t * 1.4, 0.0, 1.0)
			var fs := 22 if ft.big else 16
			var c: Color = ft.color
			c.a = a
			draw_string_outline(f, sp2 - Vector2(50, 0), ft.text, HORIZONTAL_ALIGNMENT_CENTER, 100, fs, 4, Color(0, 0, 0, a * 0.9))
			draw_string(f, sp2 - Vector2(50, 0), ft.text, HORIZONTAL_ALIGNMENT_CENTER, 100, fs, c)


# ----------------------------------------------------------------- миникарта
class Minimap extends Control:
	const W := 244.0
	## Центр миникарты в мире (острова вверху, арена внизу)
	const C := Vector2(0.0, -108.0)
	var dragging := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		clip_contents = true

	func _process(_d: float) -> void:
		queue_redraw()

	func w2m(p: Vector3) -> Vector2:
		return size / 2.0 + (Vector2(p.x, p.z) - C) * (size.x / (2.0 * W))

	func _zone_rect(z: Zone, r: Rect2) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for c in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
			pts.append(w2m(z.to_world(c.x, c.y)))
		return pts

	func m2w(v: Vector2) -> Vector3:
		var k := (2.0 * W) / size.x
		var d := (v - size / 2.0) * k + C
		return Vector3(d.x, 0, d.y)

	func _gui_input(e: InputEvent) -> void:
		var g := Game.I
		if g == null or g.state != "playing":
			return
		if e is InputEventMouseButton:
			var mb := e as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT:
				dragging = mb.pressed
				if mb.pressed:
					g.camera.center_on(m2w(mb.position), true)
			elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and g.player and g.player.alive:
				var p := m2w(mb.position)
				var pl := g.player
				if (pl.area >= 0 and g.zones[pl.area].contains(p, 0.0)) or (pl.area == Wild.AREA and g.wild.nav.walkable(p)):
					pl.issue_move(p)
					Fx.order_marker(g.fx_root, p, Color(0.3, 1.0, 0.4))
			accept_event()
		elif e is InputEventMouseMotion and dragging:
			g.camera.center_on(m2w((e as InputEventMouseMotion).position), true)
			accept_event()

	func _draw() -> void:
		var g := Game.I
		if g == null:
			return
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.18, 0.28))
		for z: Zone in g.zones:
			var alive: bool = g.teams[z.index].alive
			var ground := Color(0.55, 0.66, 0.76) if alive else Color(0.25, 0.25, 0.25)
			draw_colored_polygon(_zone_rect(z, Decor.LAND), Color(0.17, 0.25, 0.28) if alive else Color(0.15, 0.15, 0.15))
			for r: Rect2 in Zone.WALK:
				draw_colored_polygon(_zone_rect(z, r), ground)
			draw_colored_polygon(_zone_rect(z, Zone.FOREST_GROUND), Color(0.12, 0.3, 0.12) if alive else Color(0.2, 0.2, 0.2))
			for side in [-1.0, 1.0]:
				var pr := Rect2(Zone.RAMP_X1 if side > 0 else -31.0, Zone.PLAT_Z0, 31.0 - Zone.RAMP_X1, Zone.PLAT_Z1 - Zone.PLAT_Z0)
				draw_colored_polygon(_zone_rect(z, pr), ground.lightened(0.18))
			for o in z.obstacles:
				if o.kind == "cliff":
					draw_colored_polygon(_zone_rect(z, o.r), Color(0.25, 0.27, 0.32))
			var outline := _zone_rect(z, Zone.BASE)
			outline.append(outline[0])
			draw_polyline(outline, Data.TEAM_COLORS[z.index].darkened(0.1), 1.5)
			for li in 2:
				var lane := PackedVector2Array()
				for p in z.lanes[li]:
					lane.append(w2m(p))
				draw_polyline(lane, Color(0.08, 0.1, 0.14), 2.0)
			draw_circle(w2m(z.fountain_life), 2.2, Color(1.0, 0.3, 0.3))
			draw_circle(w2m(z.fountain_mana), 2.2, Color(0.3, 0.5, 1.0))
			for p in z.pads:
				draw_circle(w2m(p.pos), 3.0 if p.id == "gate" else 2.0, p.color)
			for sp in z.spawns:
				draw_circle(w2m(sp), 2.6, Color(0.6, 0.2, 0.6))
			for tp in z.towers:
				var q := w2m(tp)
				draw_rect(Rect2(q - Vector2(1.8, 1.8), Vector2(3.6, 3.6)), Data.TEAM_COLORS[z.index].lightened(0.4))
		# общий лес: чаща, тропы и поляны, врата команд, логово, святилища и площадки Рогов
		var k_m := size.x / (2.0 * W)
		draw_circle(w2m(Wild.CENTER), Wild.R * k_m, Color(0.07, 0.17, 0.09))
		for pl2 in Wild.paths:
			var line := PackedVector2Array()
			for v: Vector2 in pl2.pts:
				line.append(w2m(Wild.world(v)))
			draw_polyline(line, Color(0.36, 0.42, 0.26), maxf(1.5, float(pl2.w) * 2.0 * k_m))
		for c in Wild.clearings:
			var cc := w2m(Wild.world(c.c))
			var col := Color(0.36, 0.46, 0.27)
			match str(c.kind):
				"lair":
					col = Color(0.62, 0.42, 0.24)
				"horn":
					col = Color(0.6, 0.52, 0.28)
				"shrine":
					col = Color(0.35, 0.6, 0.7)
				"gate":
					col = (Data.TEAM_COLORS[int(c.team)] as Color).darkened(0.25)
			draw_circle(cc, maxf(1.6, float(c.r) * k_m), col)
		for r in g.runes:
			if str(r.kind) != "":
				draw_circle(w2m(r.pos), 2.2, (g.RUNES[r.kind].col as Color))
		var hexp := PackedVector2Array()
		for v: Vector2 in g.arena.hex:
			hexp.append(w2m(Arena.world(v)))
		draw_colored_polygon(hexp, Color(0.16, 0.15, 0.2))
		for t in 3:
			draw_circle(w2m(Arena.world(Arena.dir(Arena.TEAM_ANGLES[t]) * Arena.SPAWN_DIST)), 2.2,
				Data.TEAM_COLORS[t].darkened(0.2))
		for poly: PackedVector2Array in g.arena.wall_polys:
			var wp := PackedVector2Array()
			for v: Vector2 in poly:
				wp.append(w2m(Arena.world(v)))
			wp.append(wp[0])
			draw_polyline(wp, Color(0.55, 0.4, 0.8), 1.2)
		for u in g.units:
			if not u.alive or not u.visible or (u.model and not u.model.visible):
				continue
			var p2 := w2m(u.global_position)
			if u.kind == Unit.Kind.CRYSTAL:
				var c: Color = Data.TEAM_COLORS[u.team]
				draw_colored_polygon(PackedVector2Array([p2 + Vector2(0, -7), p2 + Vector2(6, 0), p2 + Vector2(0, 7), p2 + Vector2(-6, 0)]), c)
			elif u is Hero:
				if u == g.player:
					draw_circle(p2, 5.0, Color.WHITE)
				draw_circle(p2, 3.8, Data.TEAM_COLORS[u.team])
			elif u.kind == Unit.Kind.BOSS:
				draw_circle(p2, 4.0, Color(1.0, 0.35, 0.1))
			else:
				draw_rect(Rect2(p2 - Vector2(1.5, 1.5), Vector2(3, 3)), Color(0.95, 0.3, 0.25))
		if g.player and g.player.courier:
			var cp := w2m(g.player.courier.global_position)
			draw_circle(cp, 3.2, Color(1.0, 0.85, 0.45))
			draw_circle(cp, 1.8, Color.WHITE)
		if g.camera:
			var cs := g.camera.ground_corners()
			var poly := PackedVector2Array()
			for c in cs:
				poly.append(w2m(c))
			poly.append(poly[0])
			draw_polyline(poly, Color(1, 1, 1, 0.8), 1.2)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.92, 0.94, 1.0, 0.4), false, 1.0)


## Клавиша способности: Q W E R D T, у книги заклинаний — своя (F, G, V...).
static func key_of(pl: Hero, idx: int) -> String:
	if idx < KEYS.size():
		return KEYS[idx]
	return str(pl.abilities[idx].def.get("hotkey", "")) if idx < pl.abilities.size() else ""


## Имя файла иконки: q w e r d t, у книги — b1, b2...
static func icon_key(pl: Hero, idx: int) -> String:
	if idx < KEYS.size():
		return KEYS[idx].to_lower()
	return "b%d" % (idx - KEYS.size() + 1)


static func draw_empty_cell(ci: Control) -> void:
	var r := Rect2(Vector2.ZERO, ci.size)
	ci.draw_rect(r, Color(0.02, 0.025, 0.045, 0.9))
	ci.draw_rect(r.grow(-3), Color(1, 1, 1, 0.03), false, 1.0)
	ci.draw_rect(r, Color(1.0, 1.0, 1.0, 0.22), false, 1.0)


## Фон консоли: тёмный металл, золотая кромка с орнаментом.
class ConsoleFrame extends Control:
	var row: Control

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var top := 8.0
		var bg := PackedVector2Array([Vector2(0, top), Vector2(w, top), Vector2(w, h), Vector2(0, h)])
		var c1 := Color(0.09, 0.1, 0.16, 0.97)
		var c2 := Color(0.025, 0.03, 0.055, 0.98)
		draw_polygon(bg, PackedColorArray([c1, c1, c2, c2]))
		var y := top + 6.0
		while y < h:
			draw_line(Vector2(0, y), Vector2(w, y), Color(1, 1, 1, 0.012), 1.0)
			y += 4.0
		var gold := Color(0.92, 0.94, 1.0)
		draw_line(Vector2(0, top), Vector2(w, top), gold, 2.0)
		draw_line(Vector2(0, top + 4), Vector2(w, top + 4), Color(gold, 0.35), 1.0)
		if row:
			var kids := row.get_children()
			for i in range(1, kids.size()):
				var c: Control = kids[i]
				var x: float = row.position.x + c.position.x - 7.0
				_diamond(Vector2(x, top + 2), 6.0, gold)
				draw_line(Vector2(x, top + 14), Vector2(x, h - 12), Color(gold, 0.16), 1.0)
		_diamond(Vector2(w / 2.0, top + 2), 9.0, gold)

	func _diamond(c: Vector2, r: float, col: Color) -> void:
		var pts := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
		draw_colored_polygon(pts, Color(0.12, 0.1, 0.07))
		pts.append(pts[0])
		draw_polyline(pts, col, 1.5, true)
		draw_circle(c, r * 0.3, col)


## Характеристики героя с иконками: атрибуты и боевые числа.
class StatsView extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		tooltip_text = " "

	func _process(_d: float) -> void:
		queue_redraw()

	func _get_tooltip(_p: Vector2) -> String:
		var vu: Unit = Game.I.hud.view_unit() if Game.I and Game.I.hud else null
		if vu == null:
			return ""
		var who := "вас" if vu == Game.I.player else "него"
		if not (vu is Hero):
			return "Броня снижает физический урон, сопротивление магии — урон способностей.\nФиз. урон по %s: −%d%% · Маг. урон по %s: −%d%%" % [
				who, int(round((1.0 - Game.armor_mult(vu.armor)) * 100.0)), who, int(round(clampf(vu.magic_resist, -1.0, 0.9) * 100.0))]
		var pl := vu as Hero
		var s := "Сила: здоровье и его восстановление\nЛовкость: броня и скорость атаки\n"
		s += "Интеллект: мана и её восстановление\nОсновной атрибут (★) добавляет урон атаки.\n\n"
		s += "Броня снижает физический урон (атаки), сопротивление магии — урон способностей.\n"
		s += "Физ. урон по %s: −%d%% · Маг. урон по %s: −%d%%\n" % [who, int(round((1.0 - Game.armor_mult(pl.armor)) * 100.0)),
			who, int(round(clampf(pl.magic_resist, -1.0, 0.9) * 100.0))]
		s += "Вампиризм %d%% · Уклонение %d%% · Крит %d%% ×%s" % [int(pl.lifesteal * 100), int(pl.evasion * 100),
			int(pl.crit_chance * 100), str(snappedf(pl.crit_mult, 0.1))]
		return s

	func _draw() -> void:
		var pl: Unit = Game.I.hud.view_unit() if Game.I and Game.I.hud else null
		if pl == null:
			return
		var f := ThemeDB.fallback_font
		var h := pl as Hero
		var prim: String = h.def.primary if h else ""
		var attrs := [["str", "Сила", h.s_str if h else -1.0, Color(1.0, 0.45, 0.35)], ["agi", "Ловкость", h.s_agi if h else -1.0, Color(0.45, 1.0, 0.5)],
			["int", "Интеллект", h.s_int if h else -1.0, Color(0.45, 0.7, 1.0)]]
		var cw := size.x / 3.0
		for i in 3:
			var a: Array = attrs[i]
			var x := cw * i
			var main: bool = a[0] == prim
			_gem(Vector2(x + 9, 12), 8.0, a[3] if h else Color(0.4, 0.4, 0.45), main)
			var t := "%s %d" % [a[1], int(a[2])] if h else "%s —" % a[1]
			if main:
				t += " ★"
			draw_string(f, Vector2(x + 22, 17), t, HORIZONTAL_ALIGNMENT_LEFT, cw - 24, 14, Hud.GOLD if main else (Color(0.9, 0.9, 0.92) if h else Hud.DIM))
		var aps := 1.0 / maxf(pl.effective_attack_cd(), 0.05)
		var spd: float = pl.move_speed * (1.0 + pl.bonus_move)
		var stats := [["sword", "%d" % int(pl.damage_value()), "урон"], ["shield", "%.1f" % pl.armor, "броня"],
			["mshield", "%d%%" % int(round(pl.magic_resist * 100.0)), "маг."],
			["bolt", "%.2f" % aps, "атк/с"], ["boot", "%.1f" % spd, "бег"]]
		# ширины по содержимому: если подписи не влезают, остаются только числа (подписи — в подсказке)
		var ws: Array = []
		var total := 0.0
		var total_u := 0.0
		for st: Array in stats:
			var vw := f.get_string_size(st[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			var uw := f.get_string_size(st[2], HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
			ws.append([vw, uw])
			total += 19.0 + vw
			total_u += 19.0 + vw + 3.0 + uw
		var units := total_u + 6.0 * stats.size() <= size.x
		var gap := (size.x - (total_u if units else total)) / maxf(1.0, stats.size() - 1.0)
		var x := 0.0
		for i in stats.size():
			var st: Array = stats[i]
			_icon(st[0], Vector2(x + 8, 38))
			draw_string(f, Vector2(x + 18, 43), st[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
			x += 19.0 + ws[i][0]
			if units:
				draw_string(f, Vector2(x + 2, 43), st[2], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Hud.DIM)
				x += 3.0 + ws[i][1]
			x += gap

	func _gem(c: Vector2, r: float, col: Color, main: bool) -> void:
		var pts := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.85, 0), c + Vector2(0, r), c + Vector2(-r * 0.85, 0)])
		draw_colored_polygon(pts, col.darkened(0.25))
		draw_colored_polygon(PackedVector2Array([pts[0], pts[1], c, pts[3]]), col.lightened(0.15))
		pts.append(pts[0])
		draw_polyline(pts, Hud.GOLD if main else Color(1, 1, 1, 0.5), 1.5 if main else 1.0, true)

	func _icon(kind: String, c: Vector2) -> void:
		var g := Color(0.85, 0.82, 0.75)
		match kind:
			"sword":
				draw_line(c + Vector2(-7, 7), c + Vector2(7, -7), g, 2.5, true)
				draw_line(c + Vector2(-7, 1), c + Vector2(-1, 7), Hud.GOLD, 2.5, true)
			"shield", "mshield":
				var p := PackedVector2Array([c + Vector2(-7, -7), c + Vector2(7, -7), c + Vector2(6, 2), c + Vector2(0, 8), c + Vector2(-6, 2)])
				draw_colored_polygon(p, Color(0.62, 0.38, 0.85) if kind == "mshield" else Color(0.35, 0.45, 0.65))
				p.append(p[0])
				draw_polyline(p, g, 1.5, true)
			"bolt":
				draw_polyline(PackedVector2Array([c + Vector2(2, -8), c + Vector2(-4, 1), c + Vector2(1, 1), c + Vector2(-2, 8)]), Hud.GOLD, 2.0, true)
			"boot":
				draw_polyline(PackedVector2Array([c + Vector2(-3, -7), c + Vector2(-3, 5), c + Vector2(7, 5), c + Vector2(7, 2),
					c + Vector2(2, 0), c + Vector2(2, -7)]), g, 2.0, true)


## Усиления героя — цветные плашки с таймером.
class BuffBar extends Control:
	var _rects: Array = []

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		tooltip_text = " "

	func _process(_d: float) -> void:
		queue_redraw()

	func _items() -> Array:
		var vu: Unit = Game.I.hud.view_unit() if Game.I and Game.I.hud else null
		var out: Array = []
		if vu == null:
			return out
		if vu.stun > 0.0:
			out.append(["Оглушение %d" % ceili(vu.stun), Color(1.0, 0.85, 0.3), "Не может двигаться, атаковать и колдовать"])
		if vu.root_time > 0.0:
			out.append(["Корни %d" % ceili(vu.root_time), Color(0.45, 0.8, 0.35), "Не может двигаться"])
		if vu.slow > 0.0 and vu.slow_time > 0.0:
			out.append(["Замедление %d" % ceili(vu.slow_time), Color(0.45, 0.65, 1.0), "Скорость бега снижена на %d%%" % int(vu.slow * 100.0)])
		var pl := vu as Hero
		if pl == null:
			if vu.invis > 0.0 or vu.perm_invis:
				out.append(["Невидимость", Color(0.7, 0.7, 0.9), "Невидим для врагов"])
			return out
		if pl.hero_id == "akame" and pl.skill_level(1) > 0:
			out.append(["Души: %d" % pl.souls, Color(1.0, 0.3, 0.38), "Души Мурасамэ: каждая усиливает урон"])
		for id in pl.buffs:
			var b: Dictionary = pl.buffs[id]
			var nm: String = b.def.get("name", id)
			var col := Color(0.55, 0.55, 0.6) if id == "weak" else Color(b.def.get("color", Color(0.75, 0.6, 1.0)))
			out.append(["%s %d" % [nm, ceili(b.t)], col, str(b.def.get("desc", nm))])
		return out

	func _get_tooltip(p: Vector2) -> String:
		var it := _items()
		for i in mini(_rects.size(), it.size()):
			if (_rects[i] as Rect2).has_point(p):
				return it[i][2]
		return ""

	func _draw() -> void:
		var f := ThemeDB.fallback_font
		var x := 0.0
		_rects.clear()
		for it in _items():
			var t: String = it[0]
			if t.length() > 22:
				t = t.substr(0, 21) + "…"
			var tw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			var r := Rect2(x, 3, tw + 16, size.y - 6)
			if r.end.x > size.x:
				break
			var col: Color = it[1]
			draw_rect(r, Color(col.darkened(0.6), 0.85))
			draw_rect(Rect2(r.position, Vector2(4, r.size.y)), col)
			draw_rect(r, Color(col, 0.7), false, 1.0)
			draw_string(f, Vector2(x + 9, r.position.y + r.size.y / 2 + 4), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.95))
			_rects.append(r)
			x = r.end.x + 5


## Кнопки лавки и курьера в сетке команд.
class CmdButton extends Control:
	var kind := "shop"
	var hud: Hud

	func _ready() -> void:
		custom_minimum_size = Vector2(64, 64)
		mouse_filter = Control.MOUSE_FILTER_STOP
		tooltip_text = "Лавка [B]" if kind == "shop" else "Курьер [C] — привезёт покупки из лагеря"

	func _process(_d: float) -> void:
		queue_redraw()

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			if kind == "shop":
				hud.toggle_shop()
			else:
				hud.send_courier()
			accept_event()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var hov := get_global_rect().has_point(get_global_mouse_position())
		draw_rect(r, Color(0.2, 0.17, 0.1) if hov else Color(0.06, 0.07, 0.12))
		var c := size / 2.0 + Vector2(0, -3)
		var gold := Hud.GOLD
		if kind == "shop":
			var bag := PackedVector2Array([c + Vector2(-13, -4), c + Vector2(13, -4), c + Vector2(16, 14), c + Vector2(-16, 14)])
			draw_colored_polygon(bag, Color(0.55, 0.38, 0.2))
			draw_arc(c + Vector2(0, -5), 7, PI, TAU, 12, gold, 2.5, true)
			draw_circle(c + Vector2(0, 5), 4.5, gold)
		else:
			draw_colored_polygon(PackedVector2Array([c + Vector2(-17, 2), c + Vector2(0, -9), c + Vector2(17, 2), c + Vector2(0, 5)]), Color(0.92, 0.94, 1.0))
			draw_circle(c + Vector2(0, -3), 5.5, Color(0.95, 0.96, 1.0))
			draw_circle(c + Vector2(2, -4), 1.5, Color(0.1, 0.1, 0.1))
			draw_colored_polygon(PackedVector2Array([c + Vector2(5, -3), c + Vector2(9, -2), c + Vector2(5, -1)]), gold)
		draw_rect(r, Color(0.92, 0.94, 1.0, 0.9 if hov else 0.55), false, 1.5)
		var f := ThemeDB.fallback_font
		draw_rect(Rect2(2, 2, 18, 18), Color(0, 0, 0, 0.7))
		draw_string(f, Vector2(2, 16), "B" if kind == "shop" else "C", HORIZONTAL_ALIGNMENT_CENTER, 18, 14, Color(1, 0.9, 0.6))
		var cap := "Лавка" if kind == "shop" else "Курьер"
		draw_string_outline(f, Vector2(0, size.y - 4), cap, HORIZONTAL_ALIGNMENT_CENTER, size.x, 11, 3, Color.BLACK)
		draw_string(f, Vector2(0, size.y - 4), cap, HORIZONTAL_ALIGNMENT_CENTER, size.x, 11, Color(0.95, 0.9, 0.8))


# ----------------------------------------------------------------- супер-ульта сета: кат-ин
## Кат-ин при способности сета [T]: затемнение, полоса цвета героя, портрет, название, замедление времени.
func super_ult_cutin(h: Hero, a: Dictionary) -> void:
	if Game.I == null or Game.I.sim:
		return
	var layer := CutIn.new()
	layer.hero = h
	layer.title = str(a.get("name", ""))
	layer.color = Color(h.def.color)
	add_child(layer)
	if h.is_player:
		Engine.time_scale = 0.3
		get_tree().create_timer(0.75, true, false, true).timeout.connect(func() -> void: Engine.time_scale = 1.0)
	if Game.I.camera:
		Game.I.camera.shake(0.8)
		var cam := Game.I.camera
		var d0 := cam.target_dist
		cam.target_dist = d0 * 0.82
		get_tree().create_timer(1.3, true, false, true).timeout.connect(func() -> void:
			if is_instance_valid(cam):
				cam.target_dist = d0)
	Audio.sfx("transform", null, 1.0)


class CutIn:
	extends Control
	var hero: Hero
	var title := ""
	var color := Color.RED
	var t := 0.0
	var portrait: TextureRect
	const DUR := 1.6

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tex := HeroAssets.portrait(hero.hero_id)
		portrait = TextureRect.new()
		portrait.texture = tex
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(portrait)
		if tex == null:
			var h := Game.I.hud
			var lp := h.make_portrait(hero.hero_id, Vector2i(420, 420), false, hero.team)
			lp.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			portrait.queue_free()
			portrait = lp
			add_child(portrait)

	func _process(delta: float) -> void:
		# время кат-ина не зависит от замедления
		t += delta / maxf(Engine.time_scale, 0.05)
		if t >= DUR:
			queue_free()
			return
		var vp := size
		var band_h := vp.y * 0.34
		var cy := vp.y * 0.42
		var k_in := clampf(t / 0.18, 0.0, 1.0)
		var k_out := clampf((DUR - t) / 0.25, 0.0, 1.0)
		var vis := minf(k_in, k_out)
		var ps := Vector2(band_h * 1.25, band_h * 1.25)
		var slide := ease(clampf(t / 0.3, 0.0, 1.0), 0.3)
		portrait.size = ps
		portrait.position = Vector2(lerpf(-ps.x, vp.x * 0.1, slide) + t * 30.0, cy - ps.y * 0.55)
		portrait.modulate = Color(1, 1, 1, vis)
		queue_redraw()

	func _draw() -> void:
		var vp := size
		var k_in := clampf(t / 0.18, 0.0, 1.0)
		var k_out := clampf((DUR - t) / 0.25, 0.0, 1.0)
		var vis := minf(k_in, k_out)
		draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.5 * vis))
		var band_h := vp.y * 0.34
		var cy := vp.y * 0.42
		var sk := band_h * 0.35
		var w := vp.x * ease(k_in, 0.4)
		var c1 := Color(color.darkened(0.35), 0.85 * vis)
		var band := PackedVector2Array([Vector2(-sk, cy - band_h * 0.5), Vector2(w + sk, cy - band_h * 0.5 - sk * 0.3),
			Vector2(w, cy + band_h * 0.5 - sk * 0.3), Vector2(-sk * 2.0, cy + band_h * 0.5)])
		draw_colored_polygon(band, c1)
		# скоростные линии
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		for i in 26:
			var y := cy - band_h * 0.5 + rng.randf() * band_h
			var len := rng.randf_range(80.0, 340.0)
			var x := fposmod(rng.randf() * vp.x - t * rng.randf_range(900.0, 1700.0), vp.x + len) - len
			draw_line(Vector2(x, y), Vector2(x + len, y - len * 0.08), Color(1, 1, 1, 0.35 * vis), rng.randf_range(1.0, 3.0))
		draw_line(Vector2(0, cy - band_h * 0.5), Vector2(w, cy - band_h * 0.5 - sk * 0.3), Color(Hud.GOLD, vis), 3.0)
		draw_line(Vector2(0, cy + band_h * 0.5), Vector2(w, cy + band_h * 0.5 - sk * 0.3), Color(Hud.GOLD, vis), 3.0)
		var f := ThemeDB.fallback_font
		var tx := vp.x * 0.38 + (1.0 - ease(clampf((t - 0.08) / 0.3, 0.0, 1.0), 0.3)) * 400.0
		var tsize := int(clampf(vp.y * 0.06, 30.0, 64.0))
		draw_string_outline(f, Vector2(tx, cy - 6), title, HORIZONTAL_ALIGNMENT_LEFT, vp.x * 0.6, tsize, 10, Color(0, 0, 0, vis))
		draw_string(f, Vector2(tx, cy - 6), title, HORIZONTAL_ALIGNMENT_LEFT, vp.x * 0.6, tsize, Color(1.0, 0.95, 0.85, vis))
		var sub := "%s — СУПЕР-УЛЬТИМЕЙТ" % hero.def.name
		draw_string_outline(f, Vector2(tx + 4, cy + tsize * 0.75), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, int(tsize * 0.45), 6, Color(0, 0, 0, vis))
		draw_string(f, Vector2(tx + 4, cy + tsize * 0.75), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, int(tsize * 0.45), Color(Hud.GOLD, vis))


# ----------------------------------------------------------------- супер-ульта сета [T]
## Отдельная ячейка над панелью способностей: появляется, только когда Ультимативный сет собран.
class SuperSlot extends Control:
	var btn: AbilityButton
	var shown := false
	var t_show := 9.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		visible = false
		add_child(btn)
		btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		resized.connect(func(): pivot_offset = size / 2.0)

	func _process(d: float) -> void:
		var pl := Game.I.player if Game.I else null
		var want := pl != null and pl.abilities.size() > 5 and bool(pl.abilities[5].def.get("set", false)) and pl.has_set()
		if want != shown:
			shown = want
			visible = want
			if want and Game.I.state == "playing":
				t_show = 0.0
				scale = Vector2.ONE * 0.25
				create_tween().tween_property(self, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				Game.I.hud.announce("Ультимативный сет собран! Супер-способность [T] открыта", Color(1.0, 0.75, 0.3), 3.5)
				Audio.sfx("buff_up", null, 0.8)
		if shown:
			t_show += d
			queue_redraw()

	func _draw() -> void:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.004)
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r.grow(2), Color(1.0, 0.75, 0.3, 0.4 + 0.4 * pulse), false, 3.0)
		if t_show < 1.0:
			var k2 := t_show
			var c := size / 2.0
			draw_arc(c, 30.0 + k2 * 90.0, 0.0, TAU, 48, Color(1.0, 0.75, 1.0, 1.0 - k2), 4.0 * (1.0 - k2) + 1.0, true)
			draw_rect(r, Color(1.0, 0.9, 1.0, (1.0 - k2) * 0.6))


# ----------------------------------------------------------------- лавка: дерево сборки
## Дерево сборки выбранного предмета: сверху предмет, под ним части, под частями — их части.
## Зелёная рамка — уже есть (инвентарь, рюкзак, лагерь, курьер), цена — сколько стоит докупить ветку.
## ЛКМ — перейти к предмету, ПКМ — купить его (со всеми недостающими частями).
class RecipeView extends Control:
	var hud: Hud
	var hits: Array = []
	var hover_id := ""
	static var _used_in := {}

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		tooltip_text = " "
		clip_contents = true

	func _process(_d: float) -> void:
		if is_visible_in_tree():
			queue_redraw()

	static func used_in(id: String) -> Array:
		if _used_in.is_empty():
			for k in Data.ITEMS:
				for c in Data.ITEMS[k].get("recipe", []):
					if not _used_in.has(c):
						_used_in[c] = []
					if not (_used_in[c] as Array).has(k):
						(_used_in[c] as Array).append(k)
		return _used_in.get(id, [])

	func _hit(p: Vector2) -> String:
		for h in hits:
			if (h[0] as Rect2).has_point(p):
				return h[1]
		return ""

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseMotion:
			hover_id = _hit((e as InputEventMouseMotion).position)
			return
		if not (e is InputEventMouseButton and e.pressed):
			return
		var mb := e as InputEventMouseButton
		var id := _hit(mb.position)
		if id == "":
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			hud.shop_select(id)
			if mb.double_click:
				hud.try_buy(id, true)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			hud.try_buy(id, true)
		accept_event()

	func _get_tooltip(p: Vector2) -> String:
		var id := _hit(p)
		if id == "":
			return ""
		var d: Dictionary = Data.ITEMS[id]
		return "%s · класс %s · всего %d золота\n%s\nЛКМ — открыть сборку · ПКМ — купить" % [d.name, d.cls,
			Data.recipe_total(id), Data.item_desc(id)]

	func _node(n: Dictionary, r: Rect2, pl: Hero, font_px: int, price_below := true) -> void:
		var id: String = n.id
		hits.append([r, id])
		draw_rect(r, Color(0.03, 0.04, 0.07))
		Icons.item(self, id, r.grow(-2))
		var f := ThemeDB.fallback_font
		var hov := hover_id == id
		if n.have:
			draw_rect(r, Color(0.45, 1.0, 0.5, 0.95), false, 2.0)
			var cc := r.position + Vector2(r.size.x - 6, 6)
			draw_circle(cc, 6.5, Color(0.12, 0.55, 0.2))
			draw_polyline(PackedVector2Array([cc + Vector2(-3, 0), cc + Vector2(-1, 2.5), cc + Vector2(3.5, -2.5)]), Color.WHITE, 1.6, true)
		else:
			draw_rect(r, Color(1.0, 0.85, 0.45, 0.95) if hov else Color(0.92, 0.94, 1.0, 0.55), false, 2.0 if hov else 1.0)
		var txt := "есть" if n.have else str(int(n.cost))
		var col := Color(0.55, 1.0, 0.6) if n.have else (Hud.GOLD if pl.gold >= int(n.cost) else Color(1.0, 0.5, 0.45))
		if str(n.err) != "" and not n.have:
			txt = "Ex"
			col = Color(1.0, 0.4, 0.45)
		if price_below:
			draw_string_outline(f, Vector2(r.position.x - 10, r.end.y + font_px + 1), txt, HORIZONTAL_ALIGNMENT_CENTER, r.size.x + 20, font_px, 3, Color.BLACK)
			draw_string(f, Vector2(r.position.x - 10, r.end.y + font_px + 1), txt, HORIZONTAL_ALIGNMENT_CENTER, r.size.x + 20, font_px, col)
		else:
			draw_string_outline(f, Vector2(r.end.x + 4, r.position.y + r.size.y * 0.5 + font_px * 0.4), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px, 3, Color.BLACK)
			draw_string(f, Vector2(r.end.x + 4, r.position.y + r.size.y * 0.5 + font_px * 0.4), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px, col)
		if not n.have and (Data.ITEMS[id].get("recipe", []) as Array).size() > 0 and (n.kids as Array).is_empty():
			draw_string(f, r.position + Vector2(2, r.size.y - 3), "+", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Hud.GOLD)

	func _draw() -> void:
		hits.clear()
		var pl := Game.I.player if Game.I else null
		var w := size.x
		var f := ThemeDB.fallback_font
		if pl == null or hud.shop_sel == "":
			draw_string(f, Vector2(0, 30), "Выберите предмет слева", HORIZONTAL_ALIGNMENT_CENTER, w, 14, Hud.DIM)
			return
		var id := hud.shop_sel
		var d: Dictionary = Data.ITEMS[id]
		var plan := pl.recipe_plan(id)
		var line := Color(0.92, 0.94, 1.0, 0.55)
		# предмет
		var rr := Rect2(w / 2.0 - 30.0, 4.0, 60.0, 60.0)
		hits.append([rr, id])
		draw_rect(rr, Color(0.03, 0.04, 0.07))
		Icons.item(self, id, rr.grow(-3))
		var own := pl.count_owned(id)
		draw_rect(rr, Color(0.45, 1.0, 0.5) if own > 0 else Color(1.0, 0.82, 0.45), false, 2.0)
		draw_string_outline(f, Vector2(0, 84), d.name, HORIZONTAL_ALIGNMENT_CENTER, w, 15, 3, Color.BLACK)
		draw_string(f, Vector2(0, 84), d.name, HORIZONTAL_ALIGNMENT_CENTER, w, 15, Hud.CLS_COLORS.get(d.cls, Hud.TEXT))
		var sub := "всего %d золота" % Data.recipe_total(id)
		if own > 0:
			sub += " · у вас: %d" % own
		draw_string(f, Vector2(0, 102), sub, HORIZONTAL_ALIGNMENT_CENTER, w, 12, Hud.DIM)
		var kids: Array = plan.kids
		var y := 112.0
		if kids.size() > 0:
			var n := kids.size()
			var s1 := minf(44.0, (w - 8.0 - (n - 1) * 8.0) / n)
			var gap := minf(8.0 + (w - 8.0 - n * s1 - (n - 1) * 8.0) / maxf(1.0, n - 1), 40.0)
			var tot := n * s1 + (n - 1) * gap
			var x0 := (w - tot) / 2.0
			var ky := y + 22.0
			draw_line(Vector2(w / 2.0, rr.end.y + 42.0), Vector2(w / 2.0, y + 10.0), line, 1.5)
			if n > 1:
				draw_line(Vector2(x0 + s1 / 2.0, y + 10.0), Vector2(x0 + tot - s1 / 2.0, y + 10.0), line, 1.5)
			var bottom := ky + s1 + 16.0
			for i in n:
				var k: Dictionary = kids[i]
				var kx := x0 + i * (s1 + gap)
				draw_line(Vector2(kx + s1 / 2.0, y + 10.0), Vector2(kx + s1 / 2.0, ky), line, 1.5)
				_node(k, Rect2(kx, ky, s1, s1), pl, 11)
				# части части — столбиком
				var gk: Array = k.kids
				var gy := ky + s1 + 18.0
				var gs := minf(28.0, s1 - 10.0)
				if gk.size() > 0:
					draw_line(Vector2(kx + s1 / 2.0, ky + s1 + 14.0), Vector2(kx + s1 / 2.0, gy + (gk.size() - 1) * (gs + 18.0) + gs / 2.0), Color(line, 0.35), 1.0)
				for j in gk.size():
					var g: Dictionary = gk[j]
					var gr := Rect2(kx + (s1 - gs) / 2.0, gy + j * (gs + 18.0), gs, gs)
					_node(g, gr, pl, 10)
					bottom = maxf(bottom, gr.end.y + 14.0)
			y = bottom + 10.0
		else:
			draw_string(f, Vector2(0, y + 16), "Простой предмет — покупается целиком", HORIZONTAL_ALIGNMENT_CENTER, w, 12, Hud.DIM)
			y += 34.0
		# куда входит
		var ups: Array = used_in(id).filter(func(x): return pl.can_own(x))
		if ups.size() > 0:
			draw_line(Vector2(8, y), Vector2(w - 8, y), Color(line, 0.3), 1.0)
			draw_string(f, Vector2(4, y + 18), "Входит в:", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Hud.GOLD)
			var us := 36.0
			var per := maxi(1, int((w + 6.0) / (us + 6.0)))
			for i in ups.size():
				var r2 := Rect2(4.0 + (i % per) * (us + 6.0), y + 26.0 + (i / per) * (us + 6.0), us, us)
				if r2.end.y > size.y:
					break
				hits.append([r2, ups[i]])
				draw_rect(r2, Color(0.03, 0.04, 0.07))
				Icons.item(self, ups[i], r2.grow(-2))
				var hv: bool = hover_id == ups[i]
				draw_rect(r2, Color(1.0, 0.85, 0.45) if hv else Color(0.92, 0.94, 1.0, 0.45), false, 2.0 if hv else 1.0)

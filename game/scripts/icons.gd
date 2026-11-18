class_name Icons
## Иконки способностей и предметов, нарисованные кодом (временные, пока нет своих картинок).


static func _bg(ci: CanvasItem, r: Rect2, col: Color) -> void:
	ci.draw_rect(r, col.darkened(0.82))
	for i in 6:
		var k := float(i) / 6.0
		ci.draw_rect(r.grow(-r.size.x * 0.5 * k), Color(col.r, col.g, col.b, 0.06 + 0.04 * k))


static func _slash(ci: CanvasItem, c: Vector2, s: float, ang: float, col: Color, w: float) -> void:
	var d := Vector2(cos(ang), sin(ang)) * s
	ci.draw_line(c - d, c + d, col, w, true)


static func ability(ci: CanvasItem, id: String, r: Rect2) -> void:
	if not Data.ABILITIES.has(id):
		return
	var a: Dictionary = Data.ABILITIES[id]
	var col: Color = a.color
	if col.v < 0.2:
		col = Color(0.8, 0.1, 0.15)
	_bg(ci, r, col)
	var c := r.get_center()
	var s := r.size.x
	var lw := maxf(2.0, s * 0.06)
	match a.type:
		"line":
			if a.get("shape", "") == "shards":
				for k in 3:
					var y := c.y + (k - 1) * s * 0.18
					ci.draw_colored_polygon(PackedVector2Array([Vector2(c.x + s * 0.32, y), Vector2(c.x - s * 0.1, y - s * 0.06),
						Vector2(c.x - s * 0.1, y + s * 0.06)]), col.lightened(0.3))
					ci.draw_line(Vector2(r.position.x + s * 0.1, y), Vector2(c.x - s * 0.1, y), Color(col, 0.6), lw * 0.4, true)
			else:
				ci.draw_arc(c + Vector2(-s * 0.1, 0), s * 0.32, -1.1, 1.1, 18, col, lw * 1.6, true)
				ci.draw_arc(c + Vector2(-s * 0.1, 0), s * 0.32, -0.7, 0.7, 12, Color.WHITE, lw * 0.6, true)
		"leap_strike":
			_slash(ci, c, s * 0.34, 0.8, col.lightened(0.2), lw * 1.3)
			_slash(ci, c, s * 0.34, -0.8, col.lightened(0.2), lw * 1.3)
			ci.draw_arc(c, s * 0.38, 0, TAU, 24, Color(col, 0.6), lw * 0.5, true)
		"passive":
			ci.draw_arc(c, s * 0.3, 0, TAU, 24, col.lightened(0.3), lw, true)
			ci.draw_circle(c, s * 0.12, col.lightened(0.2))
		"slashes":
			for k in 6:
				_slash(ci, c + Vector2(cos(k * 1.1), sin(k * 1.1)) * s * 0.15, s * 0.22, k * 0.9, Color.WHITE if k % 2 == 0 else col, lw * 0.7)
		"empower", "transform", "metamorphosis":
			for k in 3:
				var y := c.y + s * 0.2 - k * s * 0.17
				ci.draw_polyline(PackedVector2Array([Vector2(c.x - s * 0.24, y + s * 0.1), Vector2(c.x, y - s * 0.07),
					Vector2(c.x + s * 0.24, y + s * 0.1)]), Color.WHITE if k == 2 else col.lightened(0.2), lw, true)
		"nova":
			ci.draw_arc(c, s * 0.34, 0, TAU, 28, col.lightened(0.3), lw, true)
			ci.draw_arc(c, s * 0.2, 0, TAU, 20, Color.WHITE, lw * 0.6, true)
			for k in 8:
				var ang := TAU * k / 8.0
				ci.draw_line(c + Vector2(cos(ang), sin(ang)) * s * 0.08, c + Vector2(cos(ang), sin(ang)) * s * 0.3, col.lightened(0.4), lw * 0.4, true)
		"aoe_point":
			ci.draw_arc(c + Vector2(0, s * 0.12), s * 0.3, 0, TAU, 28, col.lightened(0.2), lw * 0.8, true)
			ci.draw_circle(c + Vector2(0, -s * 0.14), s * 0.11, Color.WHITE)
			ci.draw_line(c + Vector2(0, -s * 0.14), c + Vector2(0, s * 0.12), col.lightened(0.4), lw * 0.7, true)
		"bolt":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.2, -s * 0.2), c + Vector2(s * 0.2, -s * 0.2),
				c + Vector2(s * 0.2, s * 0.2), c + Vector2(-s * 0.2, s * 0.2)]), col.lightened(0.3))
			ci.draw_line(c + Vector2(-s * 0.2, -s * 0.2), c + Vector2(s * 0.2, s * 0.2), Color.WHITE, lw * 0.5, true)
		"ice_blocks":
			for k in 3:
				var p := c + Vector2((k - 1) * s * 0.22, (k % 2) * s * 0.16 - s * 0.05)
				ci.draw_rect(Rect2(p - Vector2(s * 0.09, s * 0.09), Vector2(s * 0.18, s * 0.18)), col.lightened(0.3))
				ci.draw_line(p + Vector2(0, -s * 0.11), p + Vector2(-s * 0.08, -s * 0.32), Color(col, 0.6), lw * 0.5, true)
		"blink":
			ci.draw_circle(c + Vector2(-s * 0.2, s * 0.1), s * 0.11, Color(col, 0.35))
			ci.draw_circle(c + Vector2(s * 0.2, -s * 0.1), s * 0.13, col)
			for k in 4:
				var t := float(k) / 4.0
				ci.draw_circle(c + Vector2(lerpf(-s * 0.08, s * 0.08, t), lerpf(s * 0.05, -s * 0.05, t)), s * 0.025, Color.WHITE)
		"time_stop":
			ci.draw_arc(c, s * 0.32, 0, TAU, 32, col.lightened(0.3), lw, true)
			ci.draw_line(c, c + Vector2(0, -s * 0.24), Color.WHITE, lw, true)
			ci.draw_line(c, c + Vector2(s * 0.16, 0), Color.WHITE, lw, true)
			for k in 12:
				var ang := TAU * k / 12.0
				ci.draw_circle(c + Vector2(cos(ang), sin(ang)) * s * 0.32, s * 0.025, Color.WHITE)
		"mugetsu":
			ci.draw_rect(Rect2(c - Vector2(s * 0.12, s * 0.38), Vector2(s * 0.24, s * 0.76)), Color(0.02, 0.0, 0.02))
			ci.draw_line(c + Vector2(-s * 0.12, -s * 0.38), c + Vector2(-s * 0.12, s * 0.38), Color(0.9, 0.1, 0.1), lw * 0.6, true)
			ci.draw_line(c + Vector2(s * 0.12, -s * 0.38), c + Vector2(s * 0.12, s * 0.38), Color(0.9, 0.1, 0.1), lw * 0.6, true)
	if a.get("set", false):
		ci.draw_rect(r.grow(-1), Color(1.0, 0.45, 0.3, 0.9), false, 2.0)


## Иконка предмета из карты ATS / Warcraft 3 (items/icons/<id>.png), если есть; иначе нарисованная кодом.
## Иконки из установленного Warcraft 3 установщик кладёт без импорта Godot — тогда картинка читается с диска.
static var _item_tex := {}


static func item_texture(id: String) -> Texture2D:
	if _item_tex.has(id):
		return _item_tex[id]
	var t: Texture2D = null
	var p := "res://items/icons/%s.png" % id
	if ResourceLoader.exists(p):
		t = load(p) as Texture2D
	elif FileAccess.file_exists(p):
		var img := Image.load_from_file(ProjectSettings.globalize_path(p))
		if img and not img.is_empty():
			t = ImageTexture.create_from_image(img)
	_item_tex[id] = t
	return t


static func item(ci: CanvasItem, id: String, r: Rect2) -> void:
	if not Data.ITEMS.has(id):
		return
	var tex := item_texture(id)
	if tex:
		ci.draw_texture_rect(tex, r, false)
		return
	var d: Dictionary = Data.ITEMS[id]
	var col: Color = d.color
	_bg(ci, r, col)
	var c := r.get_center()
	var s := minf(r.size.x, r.size.y)
	var lw := maxf(2.0, s * 0.07)
	match d.get("icon", ""):
		"sword":
			var a := c + Vector2(-s * 0.3, s * 0.3)
			var b := c + Vector2(s * 0.32, -s * 0.32)
			ci.draw_line(a, b, col.lightened(0.4), lw * 1.2, true)
			ci.draw_line(c + Vector2(-s * 0.3, s * 0.08), c + Vector2(-s * 0.08, s * 0.3), Color(0.85, 0.65, 0.25), lw, true)
		"shield":
			var pts := PackedVector2Array([c + Vector2(-s * 0.3, -s * 0.32), c + Vector2(s * 0.3, -s * 0.32),
				c + Vector2(s * 0.28, s * 0.05), c + Vector2(0, s * 0.36), c + Vector2(-s * 0.28, s * 0.05)])
			ci.draw_colored_polygon(pts, col.darkened(0.15))
			pts.append(pts[0])
			ci.draw_polyline(pts, col.lightened(0.4), lw * 0.6, true)
		"armor":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.32, -s * 0.22), c + Vector2(-s * 0.12, -s * 0.32),
				c + Vector2(s * 0.12, -s * 0.32), c + Vector2(s * 0.32, -s * 0.22), c + Vector2(s * 0.22, s * 0.32),
				c + Vector2(-s * 0.22, s * 0.32)]), col.darkened(0.1))
			ci.draw_line(c + Vector2(0, -s * 0.3), c + Vector2(0, s * 0.3), col.lightened(0.4), lw * 0.4)
		"ring":
			ci.draw_arc(c + Vector2(0, s * 0.08), s * 0.22, 0, TAU, 24, Color(0.85, 0.7, 0.3), lw, true)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s * 0.36), c + Vector2(s * 0.12, -s * 0.18),
				c + Vector2(0, -s * 0.06), c + Vector2(-s * 0.12, -s * 0.18)]), col)
		"orb":
			ci.draw_circle(c, s * 0.3, col.darkened(0.2))
			ci.draw_circle(c, s * 0.22, col)
			ci.draw_circle(c + Vector2(-s * 0.09, -s * 0.09), s * 0.07, Color(1, 1, 1, 0.7))
		"gem":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s * 0.34), c + Vector2(s * 0.26, -s * 0.06),
				c + Vector2(0, s * 0.34), c + Vector2(-s * 0.26, -s * 0.06)]), col)
			ci.draw_line(c + Vector2(-s * 0.26, -s * 0.06), c + Vector2(s * 0.26, -s * 0.06), Color(1, 1, 1, 0.5), lw * 0.4)
		"glove":
			ci.draw_rect(Rect2(c + Vector2(-s * 0.22, -s * 0.12), Vector2(s * 0.44, s * 0.36)), col)
			for k in 4:
				ci.draw_rect(Rect2(c + Vector2(-s * 0.22 + k * s * 0.11, -s * 0.3), Vector2(s * 0.09, s * 0.2)), col.lightened(0.15))
		"potion":
			ci.draw_circle(c + Vector2(0, s * 0.1), s * 0.24, col)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.08, -s * 0.34), Vector2(s * 0.16, s * 0.24)), Color(0.8, 0.85, 0.9, 0.8))
		"staff":
			ci.draw_line(c + Vector2(-s * 0.25, s * 0.35), c + Vector2(s * 0.2, -s * 0.25), Color(0.6, 0.45, 0.3), lw, true)
			ci.draw_circle(c + Vector2(s * 0.22, -s * 0.27), s * 0.11, col)
		"claw":
			for k in 3:
				ci.draw_line(c + Vector2(-s * 0.25 + k * s * 0.18, -s * 0.3), c + Vector2(-s * 0.15 + k * s * 0.18, s * 0.3), col.lightened(0.3), lw * 0.8, true)
		"scroll":
			ci.draw_rect(Rect2(c - Vector2(s * 0.24, s * 0.28), Vector2(s * 0.48, s * 0.56)), Color(0.9, 0.85, 0.7))
			for k in 3:
				ci.draw_line(c + Vector2(-s * 0.16, -s * 0.14 + k * s * 0.12), c + Vector2(s * 0.16, -s * 0.14 + k * s * 0.12), col.darkened(0.3), lw * 0.4)
		"key":
			ci.draw_arc(c + Vector2(-s * 0.15, -s * 0.12), s * 0.13, 0, TAU, 16, col, lw, true)
			ci.draw_line(c + Vector2(-s * 0.06, -s * 0.03), c + Vector2(s * 0.3, s * 0.3), col, lw, true)
			ci.draw_line(c + Vector2(s * 0.18, s * 0.18), c + Vector2(s * 0.28, s * 0.08), col, lw, true)
		"heart":
			ci.draw_circle(c + Vector2(-s * 0.1, -s * 0.04), s * 0.14, col)
			ci.draw_circle(c + Vector2(s * 0.1, -s * 0.04), s * 0.14, col)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.23, s * 0.02), c + Vector2(s * 0.23, s * 0.02), c + Vector2(0, s * 0.32)]), col)
		"star":
			var pts2 := PackedVector2Array()
			for k in 10:
				var ang := TAU * k / 10.0 - PI / 2.0
				pts2.append(c + Vector2(cos(ang), sin(ang)) * s * (0.34 if k % 2 == 0 else 0.14))
			ci.draw_colored_polygon(pts2, col)
		"ex":
			ci.draw_rect(Rect2(c - Vector2(s * 0.3, s * 0.3), Vector2(s * 0.6, s * 0.6)), col.darkened(0.3))
			ci.draw_string(ThemeDB.fallback_font, Vector2(r.position.x, c.y + s * 0.12), "Ex", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, int(s * 0.36), Color.WHITE)
		"skull":
			ci.draw_circle(c + Vector2(0, -s * 0.05), s * 0.25, Color(0.9, 0.88, 0.8))
			ci.draw_rect(Rect2(c + Vector2(-s * 0.13, s * 0.12), Vector2(s * 0.26, s * 0.16)), Color(0.9, 0.88, 0.8))
			ci.draw_circle(c + Vector2(-s * 0.1, -s * 0.06), s * 0.06, col.darkened(0.6))
			ci.draw_circle(c + Vector2(s * 0.1, -s * 0.06), s * 0.06, col.darkened(0.6))
		"key_blade":
			ci.draw_line(c + Vector2(-s * 0.3, s * 0.3), c + Vector2(s * 0.28, -s * 0.28), col.lightened(0.3), lw * 1.2, true)
			ci.draw_line(c + Vector2(s * 0.12, -s * 0.28), c + Vector2(s * 0.28, -s * 0.12), col.lightened(0.3), lw, true)
			ci.draw_arc(c + Vector2(-s * 0.26, s * 0.26), s * 0.1, 0, TAU, 12, Color(0.85, 0.7, 0.3), lw * 0.6, true)
		"feather":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.25, s * 0.32), c + Vector2(s * 0.05, -s * 0.05),
				c + Vector2(s * 0.3, -s * 0.34), c + Vector2(s * 0.08, s * 0.08)]), col)
			ci.draw_line(c + Vector2(-s * 0.28, s * 0.34), c + Vector2(s * 0.28, -s * 0.32), Color(1, 1, 0.8), lw * 0.4, true)
		"eye":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.36, 0), c + Vector2(0, -s * 0.2), c + Vector2(s * 0.36, 0), c + Vector2(0, s * 0.2)]), Color(0.95, 0.95, 0.9))
			ci.draw_circle(c, s * 0.14, col)
			ci.draw_circle(c, s * 0.06, Color.BLACK)
		"amulet":
			ci.draw_arc(c + Vector2(0, -s * 0.2), s * 0.2, PI * 0.15, PI * 0.85, 12, Color(0.85, 0.7, 0.3), lw * 0.5, true)
			ci.draw_circle(c + Vector2(0, s * 0.08), s * 0.18, col)
			ci.draw_circle(c + Vector2(0, s * 0.08), s * 0.09, col.lightened(0.5))
		"cloak":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.12, -s * 0.34), c + Vector2(s * 0.12, -s * 0.34),
				c + Vector2(s * 0.34, s * 0.34), c + Vector2(-s * 0.34, s * 0.34)]), col)
			ci.draw_circle(c + Vector2(0, -s * 0.26), s * 0.1, col.darkened(0.4))
		"bone":
			ci.draw_line(c + Vector2(-s * 0.25, s * 0.25), c + Vector2(s * 0.25, -s * 0.25), Color(0.92, 0.9, 0.82), lw * 1.3, true)
			for e in [Vector2(-s * 0.27, s * 0.27), Vector2(s * 0.27, -s * 0.27)]:
				ci.draw_circle(c + e + Vector2(s * 0.06, s * 0.06), s * 0.07, Color(0.92, 0.9, 0.82))
				ci.draw_circle(c + e - Vector2(s * 0.06, s * 0.06), s * 0.07, Color(0.92, 0.9, 0.82))
		"spear":
			ci.draw_line(c + Vector2(-s * 0.32, s * 0.32), c + Vector2(s * 0.2, -s * 0.2), Color(0.6, 0.45, 0.3), lw, true)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(s * 0.34, -s * 0.34), c + Vector2(s * 0.12, -s * 0.24), c + Vector2(s * 0.24, -s * 0.12)]), col)
		"leaf":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s * 0.36), c + Vector2(s * 0.24, 0), c + Vector2(0, s * 0.34), c + Vector2(-s * 0.24, 0)]), col)
			ci.draw_line(c + Vector2(0, -s * 0.3), c + Vector2(0, s * 0.3), col.darkened(0.4), lw * 0.4)
		"seal":
			ci.draw_arc(c, s * 0.3, 0, TAU, 24, col.lightened(0.3), lw, true)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s * 0.2), c + Vector2(s * 0.17, s * 0.12), c + Vector2(-s * 0.17, s * 0.12)]), col.lightened(0.2))
		"scope":
			ci.draw_arc(c, s * 0.28, 0, TAU, 24, col, lw, true)
			ci.draw_line(c + Vector2(-s * 0.36, 0), c + Vector2(s * 0.36, 0), col, lw * 0.5)
			ci.draw_line(c + Vector2(0, -s * 0.36), c + Vector2(0, s * 0.36), col, lw * 0.5)
			ci.draw_circle(c, s * 0.05, Color(1, 0.3, 0.3))
		"halo":
			ci.draw_arc(c + Vector2(0, -s * 0.18), s * 0.24, 0, TAU, 24, col, lw, true)
			ci.draw_circle(c + Vector2(0, s * 0.12), s * 0.16, col.lightened(0.3))
		"mirror":
			ci.draw_circle(c + Vector2(-s * 0.12, 0), s * 0.18, Color(col, 0.5))
			ci.draw_circle(c + Vector2(s * 0.12, 0), s * 0.18, col)
		"fang":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.2, -s * 0.3), c + Vector2(s * 0.2, -s * 0.3), c + Vector2(0, s * 0.36)]), Color(0.95, 0.92, 0.85))
			ci.draw_circle(c + Vector2(0, s * 0.3), s * 0.06, col)
		"box":
			ci.draw_rect(Rect2(c - Vector2(s * 0.28, s * 0.2), Vector2(s * 0.56, s * 0.48)), col.darkened(0.2))
			ci.draw_rect(Rect2(c - Vector2(s * 0.32, s * 0.3), Vector2(s * 0.64, s * 0.14)), col.lightened(0.2))
			ci.draw_rect(Rect2(c - Vector2(s * 0.05, s * 0.3), Vector2(s * 0.1, s * 0.58)), Color(0.95, 0.8, 0.3))
		"flame":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s * 0.38), c + Vector2(s * 0.22, s * 0.05), c + Vector2(s * 0.14, s * 0.32), c + Vector2(-s * 0.14, s * 0.32), c + Vector2(-s * 0.22, s * 0.05)]), col)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s * 0.1), c + Vector2(s * 0.1, s * 0.14), c + Vector2(0, s * 0.3), c + Vector2(-s * 0.1, s * 0.14)]), Color(1, 0.95, 0.6))
		"snowflake":
			for k in 3:
				var ang := PI * k / 3.0
				var dd := Vector2(cos(ang), sin(ang)) * s * 0.34
				ci.draw_line(c - dd, c + dd, col.lightened(0.4), lw * 0.7, true)
		"yinyang":
			ci.draw_circle(c, s * 0.32, Color(0.95, 0.95, 0.95))
			ci.draw_arc(c, s * 0.32, -PI / 2, PI / 2, 16, Color(0.1, 0.1, 0.1), s * 0.32, true)
			ci.draw_circle(c + Vector2(0, -s * 0.16), s * 0.16, Color(0.95, 0.95, 0.95))
			ci.draw_circle(c + Vector2(0, s * 0.16), s * 0.16, Color(0.1, 0.1, 0.1))
		"book":
			ci.draw_rect(Rect2(c - Vector2(s * 0.26, s * 0.3), Vector2(s * 0.52, s * 0.6)), col.darkened(0.25))
			ci.draw_rect(Rect2(c - Vector2(s * 0.2, s * 0.24), Vector2(s * 0.4, s * 0.48)), Color(0.92, 0.88, 0.78))
			ci.draw_rect(Rect2(c - Vector2(s * 0.26, s * 0.3), Vector2(s * 0.08, s * 0.6)), col)
		"set":
			var pts3 := PackedVector2Array()
			for k in 10:
				var ang := TAU * k / 10.0 - PI / 2.0
				pts3.append(c + Vector2(cos(ang), sin(ang)) * s * (0.38 if k % 2 == 0 else 0.18))
			ci.draw_colored_polygon(pts3, col)
			ci.draw_circle(c, s * 0.1, Color(1, 0.95, 0.7))

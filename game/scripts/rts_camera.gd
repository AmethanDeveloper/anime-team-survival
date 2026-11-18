class_name RtsCamera
extends Camera3D
## Камера как в Warcraft 3: фиксированный наклон, прокрутка краем экрана, стрелками и средней кнопкой.

const PITCH := 56.0
const MIN_DIST := 16.0
const MAX_DIST := 56.0
## Границы прокрутки: три острова в ряд (±160 м), арена под ними и общий лес над ними
const BOUND_X := 250.0
const BOUND_Z0 := -352.0
const BOUND_Z1 := 140.0
const EDGE := 14.0

var focus := Vector3.ZERO
var target_focus := Vector3.ZERO
var dist := 30.0
var target_dist := 30.0
var dragging := false
var drag_last := Vector2.ZERO
var edge_pan := true
var shake_amount := 0.0
## Наклон камеры (градусы); меняется только для снимков
var pitch := PITCH


func _ready() -> void:
	fov = 42.0
	far = 650.0
	near = 0.5
	current = true
	_apply()


func center_on(p: Vector3, instant: bool) -> void:
	target_focus = Vector3(p.x, 0.0, p.z)
	if instant:
		focus = target_focus
		_apply()


func shake(k: float) -> void:
	shake_amount = maxf(shake_amount, k)


func _process(delta: float) -> void:
	var move := Vector2.ZERO
	if Input.is_key_pressed(KEY_LEFT):
		move.x -= 1
	if Input.is_key_pressed(KEY_RIGHT):
		move.x += 1
	if Input.is_key_pressed(KEY_UP):
		move.y -= 1
	if Input.is_key_pressed(KEY_DOWN):
		move.y += 1
	var vp := get_viewport()
	if edge_pan and not dragging and DisplayServer.window_is_focused() and not get_tree().paused:
		var m := vp.get_mouse_position()
		var size := vp.get_visible_rect().size
		if m.x <= EDGE:
			move.x -= 1
		elif m.x >= size.x - EDGE:
			move.x += 1
		if m.y <= EDGE:
			move.y -= 1
		elif m.y >= size.y - EDGE:
			move.y += 1
	if move != Vector2.ZERO:
		var spd := dist * 1.6
		target_focus += Vector3(move.x, 0, move.y).normalized() * spd * delta
	target_focus.x = clampf(target_focus.x, -BOUND_X, BOUND_X)
	target_focus.z = clampf(target_focus.z, BOUND_Z0, BOUND_Z1)
	focus = focus.lerp(target_focus, 1.0 - exp(-12.0 * delta))
	dist = lerpf(dist, target_dist, 1.0 - exp(-10.0 * delta))
	shake_amount = maxf(0.0, shake_amount - delta * 1.5)
	_apply()


func _apply() -> void:
	var p := deg_to_rad(pitch)
	position = focus + Vector3(0, sin(p) * dist, cos(p) * dist)
	if shake_amount > 0.0:
		position += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * shake_amount
	rotation = Vector3(-p, 0, 0)


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			target_dist = clampf(target_dist - 2.5, MIN_DIST, MAX_DIST)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			target_dist = clampf(target_dist + 2.5, MIN_DIST, MAX_DIST)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			dragging = mb.pressed
			drag_last = mb.position
	elif e is InputEventMouseMotion and dragging:
		var mm := e as InputEventMouseMotion
		var d := mm.position - drag_last
		drag_last = mm.position
		var k := dist * 0.0022
		target_focus -= Vector3(d.x, 0, d.y) * k
		focus = target_focus


## Точки пересечения углов экрана с землёй — для рамки на миникарте.
func ground_corners() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var size := get_viewport().get_visible_rect().size
	for c in [Vector2(0, 0), Vector2(size.x, 0), Vector2(size.x, size.y), Vector2(0, size.y)]:
		var o := project_ray_origin(c)
		var d := project_ray_normal(c)
		if d.y > -0.01:
			d.y = -0.01
		out.append(o + d * (-o.y / d.y))
	return out

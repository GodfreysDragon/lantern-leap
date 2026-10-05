class_name PlayerVisual
extends Node2D
## Procedurally drawn lantern sprite. The origin sits at the feet, so scaling
## this node squashes and stretches the character against the ground.
##
## Body color doubles as UI: warm amber means a dash is available, cool blue
## means it's spent. Players read it without ever looking at a HUD.

const BODY := Vector2(10, 13)
const COLOR_READY := Color(1.0, 0.7, 0.28)
const COLOR_SPENT := Color(0.5, 0.7, 1.0)
const COLOR_DASHING := Color(1.0, 1.0, 0.95)
const EYE_COLOR := Color(0.12, 0.07, 0.05)

var squash := Vector2.ONE
var facing := 1
var has_dash := true
var dashing := false
var wall_sliding := false

var _color := COLOR_READY
var _time := 0.0
var _blink := 2.5
var _body_style := StyleBoxFlat.new()


func _ready() -> void:
	# Unshaded: the lantern is a light source, so it shouldn't be lit by its own glow.
	var mat := CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = mat
	_body_style.set_corner_radius_all(3)
	_body_style.anti_aliasing = false


func _process(delta: float) -> void:
	_time += delta
	squash = squash.lerp(Vector2.ONE, 1.0 - exp(-14.0 * delta))
	scale = squash

	var target := COLOR_DASHING if dashing else (COLOR_READY if has_dash else COLOR_SPENT)
	_color = _color.lerp(target, 1.0 - exp(-18.0 * delta))

	_blink -= delta
	if _blink < -0.12:
		_blink = randf_range(2.0, 4.5)
	queue_redraw()


func _draw() -> void:
	var w := BODY.x
	var h := BODY.y

	# Flame: flickers with two out-of-phase sines and leans away from travel.
	var flicker := sin(_time * 17.0) * 1.2 + sin(_time * 29.0) * 0.6
	var tip := Vector2(-facing * 1.5 + flicker * 0.4, -h - 6.0 - flicker)
	var flame := _color.lightened(0.45)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-3.5, -h + 1), tip, Vector2(3.5, -h + 1)]), flame)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-1.5, -h + 1), tip.lerp(Vector2(0, -h), 0.35), Vector2(1.5, -h + 1)]),
		Color(1, 1, 0.92))

	# Body.
	_body_style.bg_color = _color
	draw_style_box(_body_style, Rect2(-w * 0.5, -h, w, h))
	draw_rect(Rect2(-w * 0.5 + 1.5, -h + 2.5, 1.5, h - 6.0), Color(1, 1, 1, 0.3))
	draw_rect(Rect2(-w * 0.5, -2.5, w, 2.5), _color.darkened(0.3))

	# Eyes look in the facing direction; during a wall slide they look away from the wall.
	var look := float(-facing if wall_sliding else facing)
	var eye_h := 1.0 if _blink < 0.0 else 3.0
	var eye_y := -h + 4.0 + (3.0 - eye_h) * 0.5
	draw_rect(Rect2(look * 1.5 - 2.6, eye_y, 1.6, eye_h), EYE_COLOR)
	draw_rect(Rect2(look * 1.5 + 1.0, eye_y, 1.6, eye_h), EYE_COLOR)

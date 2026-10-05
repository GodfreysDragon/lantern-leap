class_name ExitDoor
extends Area2D
## The glowing archway that ends the level.

signal reached

const GLOW := Color(1.0, 0.86, 0.55)
const STONE := Color(0.36, 0.32, 0.48)

var _done := false
var _time := 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(8, 20)
	shape.shape = rect
	shape.position = Vector2(0, -10)
	add_child(shape)

	var light := Fx.make_light(GLOW, 1.5, 1.1)
	light.position = Vector2(0, -14)
	add_child(light)

	var motes := CPUParticles2D.new()
	motes.amount = 10
	motes.lifetime = 1.4
	motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	motes.emission_rect_extents = Vector2(6, 2)
	motes.position = Vector2(0, -2)
	motes.direction = Vector2.UP
	motes.spread = 10.0
	motes.gravity = Vector2.ZERO
	motes.initial_velocity_min = 8.0
	motes.initial_velocity_max = 18.0
	motes.scale_amount_min = 1.0
	motes.scale_amount_max = 2.0
	var ramp := Gradient.new()
	ramp.set_color(0, GLOW)
	ramp.set_color(1, Color(GLOW, 0.0))
	motes.color_ramp = ramp
	add_child(motes)

	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if _done or not body is Player:
		return
	_done = true
	reached.emit()


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var pulse := 0.85 + 0.15 * sin(_time * 3.0)
	# Arch-shaped opening: a rect plus a half-disc on top.
	draw_rect(Rect2(-6, -18, 12, 18), Color(GLOW, 0.8 * pulse))
	draw_circle(Vector2(0, -18), 6.0, Color(GLOW, 0.8 * pulse))
	draw_rect(Rect2(-3, -16, 6, 16), Color(1, 1, 0.95, pulse))
	# Stone frame.
	draw_rect(Rect2(-9, -18, 3, 18), STONE)
	draw_rect(Rect2(6, -18, 3, 18), STONE)
	draw_arc(Vector2(0, -18), 7.5, PI, TAU, 12, STONE, 3.0)

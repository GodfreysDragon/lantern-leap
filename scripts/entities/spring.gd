class_name Spring
extends Area2D
## Launches the player upward and refills their dash.

const METAL := Color(0.6, 0.6, 0.72)
const PAD := Color(1.0, 0.5, 0.45)

var _compress := 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(14, 8)
	shape.shape = rect
	shape.position = Vector2(0, 4)
	add_child(shape)
	var glow := Fx.make_light(PAD, 0.35, 0.6)
	glow.position = Vector2(0, 2)
	add_child(glow)
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	# Ignore a player already rising past it (e.g. jumping up through it).
	if not body is Player or body.velocity.y < -60.0:
		return
	body.bounce()
	_compress = 1.0
	Sfx.play("spring", 0.02)
	Juice.shake(0.15)
	Fx.burst(get_parent(), position + Vector2(0, 2), Color(1, 0.9, 0.7), 8, 80.0,
		Vector2.UP, 60.0, 0.35, 200.0)


func _process(delta: float) -> void:
	if _compress <= 0.0:
		return
	_compress = move_toward(_compress, 0.0, delta * 4.0)
	queue_redraw()


func _draw() -> void:
	# Overshoot: the pad springs past rest before settling.
	var extend := sin(_compress * PI) * 5.0 if _compress > 0.0 else 0.0
	var pad_y := 1.0 - extend
	draw_rect(Rect2(-7, 6, 14, 2), METAL.darkened(0.3))
	var coil := PackedVector2Array()
	for i in 5:
		coil.append(Vector2(-4 if i % 2 == 0 else 4, lerpf(6.0, pad_y + 2.0, i / 4.0)))
	draw_polyline(coil, METAL, 1.5)
	draw_rect(Rect2(-7, pad_y, 14, 3), PAD)
	draw_rect(Rect2(-7, pad_y, 14, 1), PAD.lightened(0.4))

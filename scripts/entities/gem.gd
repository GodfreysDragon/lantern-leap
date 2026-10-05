class_name Gem
extends Area2D
## Optional collectible. Bobs, glows, and pops with a little fanfare.

signal collected

const COLOR := Color(0.45, 1.0, 0.78)

var _time := randf() * TAU
var _taken := false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 7.0
	shape.shape = circle
	add_child(shape)
	add_child(Fx.make_light(COLOR, 0.4, 0.7))
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _on_body_entered(body: Node2D) -> void:
	if _taken or not body is Player:
		return
	_taken = true
	set_deferred("monitoring", false)
	Fx.burst(get_parent(), position, COLOR, 14, 90.0, Vector2.UP, 180.0, 0.5, 60.0)
	Sfx.play("gem", 0.0)
	collected.emit()
	var tween := create_tween().set_parallel()
	tween.tween_property(self, "scale", Vector2(1.8, 1.8), 0.18).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.0, 0.18)
	tween.chain().tween_callback(queue_free)


func _draw() -> void:
	var bob := sin(_time * 3.0) * 1.5
	var squeeze := 0.75 + 0.25 * absf(cos(_time * 1.6))  # fake a slow 3D spin
	var pts := PackedVector2Array([
		Vector2(0, -6 + bob), Vector2(5 * squeeze, bob),
		Vector2(0, 6 + bob), Vector2(-5 * squeeze, bob)])
	draw_colored_polygon(pts, COLOR.darkened(0.25))
	draw_colored_polygon(PackedVector2Array([pts[0], pts[1], Vector2(0, bob), pts[3]]), COLOR)
	draw_rect(Rect2(-1 * squeeze - 1, -3 + bob, 1.5, 1.5), Color.WHITE)

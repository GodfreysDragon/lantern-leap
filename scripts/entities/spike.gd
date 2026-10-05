class_name Spike
extends Area2D
## Hazard. Drawn pointing up and rotated to face away from its anchor.
## The hitbox is smaller than the art: near misses should feel like skill,
## not like the game cheating.

const LIGHT := Color(0.86, 0.84, 0.95)
const DARK := Color(0.52, 0.48, 0.66)


func setup(direction: Vector2) -> void:
	rotation = Vector2.UP.angle_to(direction)


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(12, 5)
	shape.shape = rect
	shape.position = Vector2(0, 5)
	add_child(shape)
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		body.die()


func _draw() -> void:
	for i in 2:
		var x0 := -8.0 + i * 8.0
		var tip := Vector2(x0 + 4, -1)
		draw_colored_polygon(PackedVector2Array([Vector2(x0, 8), tip, Vector2(x0 + 4, 8)]), LIGHT)
		draw_colored_polygon(PackedVector2Array([Vector2(x0 + 4, 8), tip, Vector2(x0 + 8, 8)]), DARK)

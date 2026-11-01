class_name Spike
extends Area2D
## Hazard. Pointing up, rotated to face away from its anchor.
## The hitbox is smaller than the art: near misses should feel like skill,
## not like the game cheating. TileArt draws the art (see draw_art), so a level
## full of spikes doesn't cost one draw call each.

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


## Draws a spike centred on `center`, pointing in `direction`. Uses rotated
## draw_primitive triangles: unlike polygons or draw_set_transform, they batch.
static func draw_art(ci: CanvasItem, center: Vector2, direction: Vector2) -> void:
	var xf := Transform2D(Vector2.UP.angle_to(direction), center)
	for i in 2:
		var x0 := -8.0 + i * 8.0
		var tip := Vector2(x0 + 4, -1)
		ci.draw_primitive(xf * PackedVector2Array([Vector2(x0, 8), tip, Vector2(x0 + 4, 8)]),
			PackedColorArray([LIGHT]), PackedVector2Array())
		ci.draw_primitive(xf * PackedVector2Array([Vector2(x0 + 4, 8), tip, Vector2(x0 + 8, 8)]),
			PackedColorArray([DARK]), PackedVector2Array())

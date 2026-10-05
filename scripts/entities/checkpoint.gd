class_name Checkpoint
extends Area2D
## A lamp post the player lights by touching it; it becomes the respawn point.

signal reached(spawn: Vector2)

const POST := Color(0.45, 0.42, 0.55)
const FLAME := Color(1.0, 0.72, 0.3)

var lit := false
var _time := 0.0
var _light: PointLight2D


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(14, 26)
	shape.shape = rect
	shape.position = Vector2(0, -13)
	add_child(shape)
	_light = Fx.make_light(FLAME, 1.2, 0.0)
	_light.position = Vector2(0, -22)
	add_child(_light)
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if lit or not body is Player:
		return
	lit = true
	create_tween().tween_property(_light, "energy", 1.0, 0.4).from(3.0)
	Fx.burst(get_parent(), position + Vector2(0, -22), FLAME, 16, 80.0, Vector2.UP, 120.0, 0.6, 80.0)
	Sfx.play("checkpoint", 0.0)
	reached.emit(position)


func _process(delta: float) -> void:
	_time += delta
	if lit:
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(-1, -18, 2, 18), POST)
	draw_rect(Rect2(-4, -1, 8, 1), POST.darkened(0.3))
	draw_rect(Rect2(-4, -20, 8, 2), POST)
	draw_rect(Rect2(-4, -28, 8, 1), POST)
	draw_rect(Rect2(-4, -28, 1, 8), POST)
	draw_rect(Rect2(3, -28, 1, 8), POST)
	if lit:
		var f := sin(_time * 14.0) * 0.8
		draw_colored_polygon(PackedVector2Array([
			Vector2(-2.5, -20), Vector2(f * 0.5, -26 - f), Vector2(2.5, -20)]), FLAME)
		draw_rect(Rect2(-1, -22, 2, 2), Color(1, 1, 0.85))
	else:
		draw_rect(Rect2(-1, -21, 2, 1), Color(0.3, 0.28, 0.35))

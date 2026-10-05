class_name CrumbleBlock
extends StaticBody2D
## Solid block that shakes when touched, breaks, then reforms, but never
## inside the player.

enum State { SOLID, SHAKING, GONE }

const TILE := 16
const SHAKE_TIME := 0.45
const RESPAWN_TIME := 2.2
const COLOR := Color(0.52, 0.42, 0.36)
const CRACK := Color(0.3, 0.22, 0.2)

var _state := State.SOLID
var _timer := 0.0
var _appear := 1.0
var _shape: CollisionShape2D


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	_shape = CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(TILE, TILE)
	_shape.shape = rect
	_shape.position = Vector2(TILE, TILE) * 0.5
	add_child(_shape)


func touch() -> void:
	if _state != State.SOLID:
		return
	_state = State.SHAKING
	_timer = SHAKE_TIME
	Sfx.play("crumble", 0.1, -8.0)


func reset_state() -> void:
	_state = State.SOLID
	_appear = 1.0
	_shape.set_deferred("disabled", false)
	queue_redraw()


func _physics_process(delta: float) -> void:
	match _state:
		State.SHAKING:
			_timer -= delta
			if _timer <= 0.0:
				_break()
		State.GONE:
			_timer -= delta
			if _timer <= 0.0:
				if _player_inside():
					_timer = 0.1
				else:
					_state = State.SOLID
					_appear = 0.0
					_shape.set_deferred("disabled", false)


func _process(delta: float) -> void:
	if _state == State.SHAKING or _appear < 1.0:
		_appear = move_toward(_appear, 1.0, delta * 6.0)
		queue_redraw()


func _break() -> void:
	_state = State.GONE
	_timer = RESPAWN_TIME
	_shape.set_deferred("disabled", true)
	Fx.burst(get_parent(), position + Vector2(TILE, TILE) * 0.5, COLOR, 10, 50.0,
		Vector2.DOWN, 70.0, 0.5, 300.0, 3.0)
	Sfx.play("crumble", 0.1)
	queue_redraw()


func _player_inside() -> bool:
	var player := get_tree().get_first_node_in_group("player") as Player
	if player == null:
		return false
	return Rect2(global_position, Vector2(TILE, TILE)).grow(-1).intersects(player.global_rect())


func _draw() -> void:
	if _state == State.GONE:
		draw_rect(Rect2(2, 2, TILE - 4, TILE - 4), Color(COLOR, 0.15), false, 1.0)
		return
	var jitter := Vector2(randf_range(-1, 1), randf_range(-1, 1)) if _state == State.SHAKING else Vector2.ZERO
	var s := _appear
	var size := Vector2(TILE, TILE) * s
	var origin := (Vector2(TILE, TILE) - size) * 0.5 + jitter
	draw_rect(Rect2(origin, size), COLOR)
	draw_rect(Rect2(origin, Vector2(size.x, 2 * s)), COLOR.lightened(0.25))
	draw_polyline(PackedVector2Array([
		origin + Vector2(3, 4) * s, origin + Vector2(7, 8) * s,
		origin + Vector2(6, 12) * s, origin + Vector2(11, 14) * s]), CRACK, 1.0)
	draw_line(origin + Vector2(7, 8) * s, origin + Vector2(12, 6) * s, CRACK, 1.0)

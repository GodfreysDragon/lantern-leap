class_name DashCrystal
extends Area2D
## Refills the player's dash mid-air, then regrows after a short delay.
## Only consumed if the player actually needs it.

const COLOR := Color(0.55, 0.85, 1.0)
const RESPAWN_TIME := 2.5

var _active := true
var _respawn := 0.0
var _time := randf() * TAU
var _pop := 1.0
var _light: PointLight2D


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 8.0
	shape.shape = circle
	add_child(shape)
	_light = Fx.make_light(COLOR, 0.5, 0.9)
	add_child(_light)


func _physics_process(delta: float) -> void:
	if not _active:
		_respawn -= delta
		if _respawn <= 0.0:
			_set_active(true)
			Fx.burst(get_parent(), position, COLOR, 6, 30.0, Vector2.UP, 180.0, 0.3, 0.0)
		return
	# Polling overlaps (rather than body_entered) catches a player who was
	# already inside the crystal when they spent their dash.
	for body in get_overlapping_bodies():
		if body is Player and body.refill_dash():
			_set_active(false)
			_respawn = RESPAWN_TIME
			Fx.burst(get_parent(), position, COLOR, 12, 100.0, Vector2.UP, 180.0, 0.4, 0.0)
			Sfx.play("crystal", 0.02)
			Juice.hitstop(0.03)


func reset_state() -> void:
	_set_active(true)


func _set_active(value: bool) -> void:
	_active = value
	_light.enabled = value
	_pop = 0.0 if value else 1.0


func _process(delta: float) -> void:
	_time += delta
	_pop = move_toward(_pop, 1.0, delta * 5.0)
	queue_redraw()


func _draw() -> void:
	var bob := sin(_time * 2.4) * 1.5
	if not _active:
		var ghost := PackedVector2Array([
			Vector2(0, -7), Vector2(4, 0), Vector2(0, 7), Vector2(-4, 0), Vector2(0, -7)])
		draw_polyline(ghost, Color(COLOR, 0.25), 1.0)
		return
	var s := ease(_pop, -2.0) * (1.0 + 0.08 * sin(_time * 6.0))
	var pts := PackedVector2Array([
		Vector2(0, -8 * s + bob), Vector2(5 * s, bob), Vector2(0, 8 * s + bob), Vector2(-5 * s, bob)])
	draw_colored_polygon(pts, COLOR)
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, -4 * s + bob), Vector2(2 * s, bob), Vector2(0, 4 * s + bob), Vector2(-2 * s, bob)]),
		Color(1, 1, 1, 0.9))

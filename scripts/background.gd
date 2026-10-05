extends Node2D
## Parallax cave backdrop, drawn procedurally in screen space on a
## CanvasLayer. Each layer scrolls at a fraction of the camera's speed and
## wraps horizontally, so it works for levels of any size.

const SCREEN := Vector2(480, 270)
const PERIOD := 480.0

## [scroll factor, colour, stalactite depth, seed]
const LAYERS := [
	[0.15, Color(0.07, 0.06, 0.12), 70.0, 11],
	[0.35, Color(0.1, 0.08, 0.16), 50.0, 23],
	[0.6, Color(0.13, 0.1, 0.2), 32.0, 37],
]
const MOTES := 40

var _camera_pos := Vector2.ZERO
var _time := 0.0
var _shapes: Array[PackedVector2Array] = []  # two per layer: ceiling, floor
var _motes: Array[Vector3] = []  # x, y, phase


func _ready() -> void:
	for layer in LAYERS:
		_shapes.append_array(_profiles(layer[2], layer[3]))
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in MOTES:
		_motes.append(Vector3(rng.randf() * SCREEN.x, rng.randf() * SCREEN.y, rng.randf() * TAU))


func _process(delta: float) -> void:
	_time += delta
	var camera := get_viewport().get_camera_2d()
	if camera:
		_camera_pos = camera.get_screen_center_position()
	queue_redraw()


func _draw() -> void:
	# Vertical gradient wash.
	var top := Color(0.035, 0.025, 0.06)
	var bottom := Color(0.07, 0.045, 0.11)
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(SCREEN.x, 0), SCREEN, Vector2(0, SCREEN.y)]),
		PackedColorArray([top, top, bottom, bottom]))

	for i in LAYERS.size():
		var factor: float = LAYERS[i][0]
		var color: Color = LAYERS[i][1]
		var scroll := fposmod(_camera_pos.x * factor, PERIOD)
		var lift := clampf(-_camera_pos.y * factor * 0.15, -20.0, 20.0)
		for tile in 2:
			var offset := Vector2(tile * PERIOD - scroll, lift)
			var t := Transform2D(0.0, offset)
			draw_set_transform_matrix(t)
			draw_colored_polygon(_shapes[i * 2], color)
			draw_colored_polygon(_shapes[i * 2 + 1], color)
	draw_set_transform_matrix(Transform2D.IDENTITY)

	# Drifting dust motes, closer ones parallax more.
	for m in _motes:
		var depth := 0.3 + fmod(m.z, 1.0) * 0.5
		var x := fposmod(m.x - _camera_pos.x * depth * 0.5 + sin(_time * 0.4 + m.z) * 8.0, SCREEN.x)
		var y := fposmod(m.y - _camera_pos.y * depth * 0.5 - _time * 4.0 * depth, SCREEN.y)
		var a := 0.15 + 0.25 * (0.5 + 0.5 * sin(_time * 1.3 + m.z * 3.0))
		draw_rect(Rect2(x, y, 1.5, 1.5), Color(1.0, 0.85, 0.6, a * depth))


## Builds two polygons per layer: a jagged ceiling of stalactites and a floor
## of stalagmites. Both start and end at the same height so the PERIOD-wide
## strip tiles seamlessly.
func _profiles(depth: float, seed_value: int) -> Array[PackedVector2Array]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var top := PackedVector2Array([Vector2(0, 8)])
	var bottom := PackedVector2Array([Vector2(0, SCREEN.y - 8)])
	var x := 0.0
	while x < PERIOD - 40.0:
		var w := rng.randf_range(14.0, 34.0)
		top.append(Vector2(x + w * 0.5, rng.randf_range(depth * 0.4, depth)))
		top.append(Vector2(x + w, rng.randf_range(4.0, 14.0)))
		bottom.append(Vector2(x + w * 0.5, SCREEN.y - rng.randf_range(depth * 0.3, depth * 0.8)))
		bottom.append(Vector2(x + w, SCREEN.y - rng.randf_range(4.0, 12.0)))
		x += w
	top.append(Vector2((x + PERIOD) * 0.5, depth * 0.6))
	top.append(Vector2(PERIOD, 8))
	bottom.append(Vector2((x + PERIOD) * 0.5, SCREEN.y - depth * 0.5))
	bottom.append(Vector2(PERIOD, SCREEN.y - 8))

	var ceiling := PackedVector2Array([Vector2(PERIOD, -40), Vector2(0, -40)])
	ceiling.append_array(top)
	var ground := PackedVector2Array([Vector2(0, SCREEN.y + 40), Vector2(PERIOD, SCREEN.y + 40)])
	bottom.reverse()
	ground.append_array(bottom)
	return [ceiling, ground]

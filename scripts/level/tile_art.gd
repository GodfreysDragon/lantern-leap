class_name TileArt
extends Node2D
## Draws all static tiles once (Godot caches the draw commands, so this costs
## nothing per frame). Tiles "auto-tile" by looking at their neighbours:
## exposed tops get a mossy lip, exposed sides get a rim, buried tiles go dark.

const TILE := 16
const ROCK := Color(0.2, 0.17, 0.3)
const ROCK_DEEP := Color(0.11, 0.09, 0.17)
const ROCK_RIM := Color(0.3, 0.26, 0.42)
const MOSS := Color(0.42, 0.62, 0.5)
const MOSS_DARK := Color(0.26, 0.42, 0.36)
const SPECK := Color(0.14, 0.12, 0.22)
const WOOD := Color(0.55, 0.38, 0.24)
const WOOD_DARK := Color(0.35, 0.23, 0.15)

var data: LevelData


func _draw() -> void:
	for y in data.height:
		for x in data.width:
			match data.cell(x, y):
				LevelData.SOLID:
					_draw_rock(x, y)
				LevelData.ONE_WAY:
					_draw_plank(x, y)


func _draw_rock(x: int, y: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(x, y))
	var origin := Vector2(x, y) * TILE
	var open_up := not data.is_solid(x, y - 1)
	var open_down := not data.is_solid(x, y + 1)
	var open_left := not data.is_solid(x - 1, y)
	var open_right := not data.is_solid(x + 1, y)
	var buried := not (open_up or open_down or open_left or open_right) \
		and data.is_solid(x - 1, y - 1) and data.is_solid(x + 1, y - 1) \
		and data.is_solid(x - 1, y + 1) and data.is_solid(x + 1, y + 1)

	var base := ROCK_DEEP if buried else ROCK
	base = base.lightened(rng.randf_range(-0.012, 0.018))
	draw_rect(Rect2(origin, Vector2(TILE, TILE)), base)

	for i in rng.randi_range(2, 4):
		var p := origin + Vector2(rng.randi_range(2, 12), rng.randi_range(4, 12))
		draw_rect(Rect2(p, Vector2(rng.randi_range(1, 3), 1)), SPECK)

	if open_left:
		draw_rect(Rect2(origin, Vector2(1, TILE)), ROCK_RIM)
	if open_right:
		draw_rect(Rect2(origin + Vector2(TILE - 1, 0), Vector2(1, TILE)), ROCK_RIM)
	if open_down:
		draw_rect(Rect2(origin + Vector2(0, TILE - 2), Vector2(TILE, 2)), ROCK_DEEP)
	if open_up:
		draw_rect(Rect2(origin, Vector2(TILE, 3)), MOSS)
		draw_rect(Rect2(origin + Vector2(0, 3), Vector2(TILE, 1)), MOSS_DARK)
		# A few blades of grass poking above the surface.
		for i in rng.randi_range(0, 3):
			var bx := origin.x + rng.randi_range(1, TILE - 2)
			draw_rect(Rect2(bx, origin.y - rng.randi_range(1, 3), 1, 3), MOSS)


func _draw_plank(x: int, y: int) -> void:
	var origin := Vector2(x, y) * TILE
	draw_rect(Rect2(origin, Vector2(TILE, 4)), WOOD)
	draw_rect(Rect2(origin + Vector2(0, 3), Vector2(TILE, 1)), WOOD_DARK)
	draw_rect(Rect2(origin + Vector2(TILE - 1, 0), Vector2(1, 4)), WOOD_DARK)
	# Diagonal brace on the ends of a platform run.
	if data.cell(x - 1, y) != LevelData.ONE_WAY:
		draw_line(origin + Vector2(2, 4), origin + Vector2(6, 9), WOOD_DARK, 1.0)
	if data.cell(x + 1, y) != LevelData.ONE_WAY:
		draw_line(origin + Vector2(TILE - 2, 4), origin + Vector2(TILE - 6, 9), WOOD_DARK, 1.0)

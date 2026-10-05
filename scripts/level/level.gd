class_name Level
extends Node2D
## Builds a playable level from LevelData: merged collision, tile art and
## entities. Re-emits entity signals so the game loop only talks to the level.

signal gem_collected
signal checkpoint_reached(spawn: Vector2)
signal exit_reached

const TILE := 16
const AMBIENT := Color(0.5, 0.46, 0.66)

var data: LevelData
var spawn_point := Vector2.ZERO
var bounds := Rect2()
var gem_total := 0


func build(level_data: LevelData) -> void:
	data = level_data
	bounds = Rect2(0, 0, data.width * TILE, data.height * TILE)

	var ambient := CanvasModulate.new()
	ambient.color = AMBIENT
	add_child(ambient)

	var art := TileArt.new()
	art.data = data
	add_child(art)

	_build_solids()
	_build_side_walls()
	_build_entities()


## Called on player death: crumbled blocks and used crystals come back.
func reset_transients() -> void:
	for child in get_children():
		if child.has_method("reset_state"):
			child.reset_state()


func _build_entities() -> void:
	for y in data.height:
		for x in data.width:
			var top_left := Vector2(x, y) * TILE
			var center := top_left + Vector2(TILE, TILE) * 0.5
			var bottom := top_left + Vector2(TILE * 0.5, TILE)
			match data.cell(x, y):
				LevelData.START:
					spawn_point = bottom
				LevelData.ONE_WAY:
					_add_one_way(top_left)
				LevelData.SPIKE:
					var spike := Spike.new()
					spike.position = center
					spike.setup(_spike_direction(x, y))
					add_child(spike)
				LevelData.GEM:
					var gem := Gem.new()
					gem.position = center
					gem.collected.connect(gem_collected.emit)
					add_child(gem)
					gem_total += 1
				LevelData.SPRING:
					var spring := Spring.new()
					spring.position = center
					add_child(spring)
				LevelData.CRYSTAL:
					var crystal := DashCrystal.new()
					crystal.position = center
					add_child(crystal)
				LevelData.CRUMBLE:
					var block := CrumbleBlock.new()
					block.position = top_left
					add_child(block)
				LevelData.CHECKPOINT:
					var checkpoint := Checkpoint.new()
					checkpoint.position = bottom
					checkpoint.reached.connect(checkpoint_reached.emit)
					add_child(checkpoint)
				LevelData.EXIT:
					var door := ExitDoor.new()
					door.position = bottom
					door.reached.connect(exit_reached.emit)
					add_child(door)


## Spikes point away from whatever they're attached to, so the level text
## only needs a single spike character.
func _spike_direction(x: int, y: int) -> Vector2:
	if data.is_solid(x, y + 1):
		return Vector2.UP
	if data.is_solid(x, y - 1):
		return Vector2.DOWN
	if data.is_solid(x - 1, y):
		return Vector2.RIGHT
	if data.is_solid(x + 1, y):
		return Vector2.LEFT
	return Vector2.UP


## Greedy-merges solid tiles into as few rectangles as possible. Fewer, larger
## shapes are cheaper and avoid the "catching on internal tile seams" bug.
func _build_solids() -> void:
	var body := StaticBody2D.new()
	body.name = "Solids"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)

	var used := {}
	for y in data.height:
		for x in data.width:
			if data.cell(x, y) != LevelData.SOLID or used.has(Vector2i(x, y)):
				continue
			var w := 1
			while data.cell(x + w, y) == LevelData.SOLID and not used.has(Vector2i(x + w, y)):
				w += 1
			var h := 1
			while _row_free(x, y + h, w, used):
				h += 1
			for yy in range(y, y + h):
				for xx in range(x, x + w):
					used[Vector2i(xx, yy)] = true
			_add_rect(body, Rect2(x * TILE, y * TILE, w * TILE, h * TILE))


func _row_free(x: int, y: int, w: int, used: Dictionary) -> bool:
	for xx in range(x, x + w):
		if data.cell(xx, y) != LevelData.SOLID or used.has(Vector2i(xx, y)):
			return false
	return true


## Invisible walls on the left/right edges (tall, so you can't hop over them).
func _build_side_walls() -> void:
	var body := StaticBody2D.new()
	body.name = "Bounds"
	body.collision_mask = 0
	add_child(body)
	var top := -TILE * 20.0
	var height := bounds.size.y - top
	_add_rect(body, Rect2(-TILE, top, TILE, height))
	_add_rect(body, Rect2(bounds.size.x, top, TILE, height))


func _add_one_way(top_left: Vector2) -> void:
	var body := StaticBody2D.new()
	body.collision_mask = 0
	body.position = top_left
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(TILE, 4)
	shape.shape = rect
	shape.position = Vector2(TILE * 0.5, 2)
	shape.one_way_collision = true
	body.add_child(shape)
	add_child(body)


static func _add_rect(body: StaticBody2D, rect: Rect2) -> void:
	var shape := CollisionShape2D.new()
	var rect_shape := RectangleShape2D.new()
	rect_shape.size = rect.size
	shape.shape = rect_shape
	shape.position = rect.get_center()
	body.add_child(shape)

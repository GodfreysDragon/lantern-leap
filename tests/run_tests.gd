extends Node
## Headless test suite. Run with:
##   godot --headless --path . --fixed-fps 120 res://tests/run_tests.tscn
##
## (Run as a scene rather than with -s so autoloads are registered.)
##
## 1. Lints every level file.
## 2. Checks movement "feel contracts" by simulating the real Player scene
##    with synthetic input, so retuning can't silently break level design.
## 3. Drives the real main scene end-to-end through every level.

const MainScript := preload("res://scripts/main.gd")
const PLAYER_SCENE := preload("res://scenes/player.tscn")
const TILE := 16.0
const VALID_TILES := " #-^xS*oCEP"

var _failures := 0
var _checks := 0


func _ready() -> void:
	Save.persist = false
	Save.best_times.clear()
	Save.best_gems.clear()
	_run.call_deferred()


func _run() -> void:
	print("\n== Level lint")
	for path in MainScript.LEVELS:
		_lint_level(path)

	print("\n== Movement contracts")
	await _test_run_speed()
	await _test_jump_heights()
	await _test_coyote_time()
	await _test_jump_buffer()
	await _test_dash_distance()
	await _test_corner_correction()
	await _test_wall_slide_and_jump()

	print("\n== End-to-end")
	await _test_full_run()

	print("\n%d checks, %d failed" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("  ok    ", label)
	else:
		_failures += 1
		printerr("  FAIL  ", label)


# --- level lint --------------------------------------------------------------

func _lint_level(path: String) -> void:
	var data := LevelData.load_file(path)
	_check(data != null, "%s loads" % path)
	if data == null:
		return
	var starts := data.find(LevelData.START)
	var exits := data.find(LevelData.EXIT)
	_check(starts.size() == 1, "%s has exactly one start" % data.id)
	_check(exits.size() == 1, "%s has exactly one exit" % data.id)
	_check(data.width * TILE >= 480 and data.height * TILE >= 270,
		"%s is at least one screen in size" % data.id)

	var unknown := ""
	for row in data.rows:
		for c in row:
			if not c in VALID_TILES and not c in unknown:
				unknown += c
	_check(unknown.is_empty(), "%s uses only known tiles %s" % [data.id, unknown])

	for e in exits:
		_check(not data.is_solid(e.x, e.y - 1), "%s exit has headroom" % data.id)
	for s in starts:
		_check(data.is_solid(s.x, s.y + 1), "%s start is on solid ground" % data.id)
	for c in data.find(LevelData.CHECKPOINT) + data.find(LevelData.SPRING):
		_check(data.is_solid(c.x, c.y + 1), "%s %s at %s is grounded" % [data.id, data.cell(c.x, c.y), c])


# --- movement contracts ------------------------------------------------------

## Builds a flat floor (optionally with extra rects) and drops a player on it.
func _make_arena(extra_rects: Array[Rect2] = []) -> Player:
	var arena := Node2D.new()
	get_tree().root.add_child(arena)
	var body := StaticBody2D.new()
	arena.add_child(body)
	for rect in [Rect2(-800, 0, 1600, 32)] + extra_rects:
		var shape := CollisionShape2D.new()
		var rs := RectangleShape2D.new()
		rs.size = rect.size
		shape.shape = rs
		shape.position = rect.get_center()
		body.add_child(shape)
	var player: Player = PLAYER_SCENE.instantiate()
	arena.add_child(player)
	player.global_position = Vector2(0, 0)
	await _frames(10)
	return player


func _teardown(player: Player) -> void:
	_release_all()
	player.get_parent().queue_free()
	await _frames(2)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _release_all() -> void:
	for action in ["move_left", "move_right", "move_up", "move_down", "jump", "dash"]:
		Input.action_release(action)


func _test_run_speed() -> void:
	var p := await _make_arena()
	Input.action_press("move_right")
	await _frames(30)  # 0.25s
	_check(is_equal_approx(p.velocity.x, p.max_speed), "reaches top speed within 0.25s (%.0f)" % p.velocity.x)
	Input.action_release("move_right")
	await _frames(12)  # 0.1s
	_check(is_zero_approx(p.velocity.x), "stops within 0.1s of releasing")
	await _teardown(p)


## Returns the peak height reached, in pixels.
func _jump_height(p: Player, hold_frames: int) -> float:
	var start_y := p.global_position.y
	var peak := start_y
	Input.action_press("jump")
	for i in 120:
		if i == hold_frames:
			Input.action_release("jump")
		await get_tree().physics_frame
		peak = minf(peak, p.global_position.y)
	Input.action_release("jump")
	return start_y - peak


func _test_jump_heights() -> void:
	var p := await _make_arena()
	var full := await _jump_height(p, 9999)
	_check(full > 3 * TILE and full < 4 * TILE, "full jump clears 3 tiles but not 4 (%.1fpx)" % full)
	await _frames(30)
	var hop := await _jump_height(p, 2)
	_check(hop < full * 0.45, "tapping jump gives a short hop (%.1fpx)" % hop)
	await _teardown(p)


func _test_coyote_time() -> void:
	# Floor ends at x = 0; start just left of the edge and run off.
	var p := await _make_arena()
	p.get_parent().get_child(0).get_child(0).position.x = -800  # shift floor so it ends at x=0
	p.global_position = Vector2(-20, 0)
	await _frames(5)
	Input.action_press("move_right")
	while p.is_on_floor():
		await get_tree().physics_frame
	await _frames(6)  # 50ms after leaving the ledge
	_check(not p.is_on_floor(), "player has left the ledge")
	Input.action_press("jump")
	await _frames(2)
	_check(p.velocity.y < 0.0, "jump still works 50ms after running off a ledge")
	await _teardown(p)


func _test_jump_buffer() -> void:
	var p := await _make_arena()
	Input.action_press("jump")
	await _frames(3)
	Input.action_release("jump")
	# Wait until falling and almost on the ground again.
	while p.velocity.y < 0.0 or p.global_position.y < -10.0:
		await get_tree().physics_frame
	Input.action_press("jump")  # pressed ~10px before landing
	await _frames(1)
	Input.action_release("jump")
	var jumped := false
	for i in 30:
		await get_tree().physics_frame
		if p.velocity.y < -100.0:
			jumped = true
			break
	_check(jumped, "jump pressed just before landing is buffered")
	await _teardown(p)


func _test_dash_distance() -> void:
	var p := await _make_arena()
	var start_x := p.global_position.x
	Input.action_press("dash")
	await _frames(2)  # physics_frame fires before nodes process, so wait one extra
	Input.action_release("dash")
	_check(p.state == Player.State.DASH, "dash starts on press")
	_check(not p.has_dash, "dash is spent")
	while p.state == Player.State.DASH:
		await get_tree().physics_frame
	var dist := p.global_position.x - start_x
	_check(dist > 2.5 * TILE and dist < 4.0 * TILE, "ground dash covers ~3 tiles (%.1fpx)" % dist)
	await _frames(2)
	_check(p.has_dash, "dash recharges on the ground")
	await _teardown(p)


func _test_corner_correction() -> void:
	# A ceiling block whose edge overlaps the player's head by 3px.
	var ceiling := Rect2(-5 + 3 - 32, -40, 32, 8)
	var p := await _make_arena([ceiling])
	var height := await _jump_height(p, 9999)
	_check(height > 40.0, "jump slides past a ceiling corner (%.1fpx)" % height)
	await _teardown(p)



func _test_wall_slide_and_jump() -> void:
	# A tall wall whose face is 3px to the right of the player.
	var p := await _make_arena([Rect2(8, -300, 16, 300)])
	Input.action_press("move_right")
	Input.action_press("jump")
	await _frames(40)  # rise along the wall, then start falling
	Input.action_release("jump")
	while p.velocity.y <= 0.0:
		await get_tree().physics_frame
	await _frames(30)
	_check(p.velocity.y <= p.wall_slide_speed + 1.0,
		"holding into a wall caps fall speed (%.0f)" % p.velocity.y)
	var y_before := p.global_position.y
	Input.action_press("jump")
	await _frames(2)
	Input.action_release("jump")
	_check(p.velocity.x < 0.0 and p.velocity.y < 0.0, "jumping on a wall kicks up and away")
	await _frames(8)
	_check(p.global_position.y < y_before, "wall jump gains height")
	await _teardown(p)


# --- end-to-end --------------------------------------------------------------

func _test_full_run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	await _frames(10)
	_press("jump")
	await _wait_for(func() -> bool: return main.mode == main.Mode.PLAYING, 240)
	_check(main.mode == main.Mode.PLAYING, "title -> playing")

	for i in MainScript.LEVELS.size():
		var level: Level = main.level
		_check(level != null and main.player != null, "level %d built" % (i + 1))
		_check(level.gem_total > 0, "level %d has gems (%d)" % [i + 1, level.gem_total])
		var player: Player = main.player

		if i == 0:
			# Dying respawns the player at the start and resets transients.
			player.die()
			_check(main.level_deaths == 1, "death is counted")
			await _wait_for(func() -> bool: return player.state == Player.State.NORMAL, 240)
			_check(player.global_position.distance_to(level.spawn_point) < 1.0, "respawned at spawn")

		# Teleport onto the exit; the door should end the level.
		var exit_cell: Vector2i = level.data.find(LevelData.EXIT)[0]
		player.global_position = (Vector2(exit_cell) + Vector2(0.5, 1.0)) * TILE
		var target_mode = main.Mode.FINISHED if i == MainScript.LEVELS.size() - 1 else main.Mode.CLEAR
		await _wait_for(func() -> bool: return main.mode == target_mode, 240)
		_check(main.mode == target_mode, "level %d exit completes the level" % (i + 1))
		_press("jump")
		await _wait_for(func() -> bool: return main.mode != target_mode, 60)
		if i < MainScript.LEVELS.size() - 1:
			await _wait_for(func() -> bool: return main.mode == main.Mode.PLAYING, 240)

	await _wait_for(func() -> bool: return main.mode == main.Mode.TITLE, 240)
	_check(main.mode == main.Mode.TITLE, "finale returns to title")
	main.queue_free()
	await _frames(2)


func _press(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event.call_deferred(up)


func _wait_for(condition: Callable, max_frames: int) -> void:
	for i in max_frames:
		if condition.call():
			return
		await get_tree().process_frame

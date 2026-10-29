extends Node
## Game loop: title -> levels -> finale. Owns the run state (timer, deaths,
## gems), level loading, respawning, pausing and persistence of best times.

enum Mode { TITLE, PLAYING, PAUSED, TRANSITION, CLEAR, FINISHED }

const LEVELS := [
	"res://levels/01_first_light.txt",
	"res://levels/02_the_well.txt",
	"res://levels/03_glass_air.txt",
	"res://levels/04_crumbling_way.txt",
]
const PLAYER_SCENE := preload("res://scenes/player.tscn")
const RESPAWN_DELAY := 0.5
const RUN_ID := "full_run"

var mode := Mode.TITLE
var level: Level
var player: Player
var level_index := 0
var respawn_point := Vector2.ZERO

var level_time := 0.0
var level_deaths := 0
var level_gems := 0

var run_time := 0.0
var run_deaths := 0
var run_gems := 0
var run_gem_total := 0

@onready var world: Node2D = $World
@onready var camera: GameCamera = $Camera
@onready var hud: Hud = $Hud
@onready var screens: Screens = $Screens


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	camera.process_mode = Node.PROCESS_MODE_PAUSABLE
	hud.visible = false
	screens.show_title(Save.best_times.get(RUN_ID, 0.0))
	screens.fade(0.0, 0.8)


func _physics_process(delta: float) -> void:
	if mode != Mode.PLAYING or not is_instance_valid(player):
		return
	level_time += delta
	hud.set_time(level_time)
	# Falling out of the bottom of the map is a death.
	if player.state != Player.State.DEAD and player.global_position.y > level.bounds.end.y + 24.0:
		player.die()


func _notification(what: int) -> void:
	# Auto-pause when the browser tab / window loses focus.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and mode == Mode.PLAYING:
		_set_paused(true)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("mute"):
		Sfx.toggle_mute()
		return

	match mode:
		Mode.TITLE:
			var clicked: bool = event is InputEventMouseButton and event.pressed
			if event.is_action_pressed("jump") or clicked:
				Sfx.play("ui", 0.0)
				_start_run()
		Mode.PLAYING:
			if event.is_action_pressed("pause"):
				_set_paused(true)
			elif event.is_action_pressed("restart"):
				player.die()
		Mode.PAUSED:
			if event.is_action_pressed("pause") or event.is_action_pressed("jump"):
				_set_paused(false)
			elif event.is_action_pressed("restart"):
				_set_paused(false)
				player.die()
			elif event.is_action_pressed("dash"):
				_set_paused(false)
				_quit_to_title()
		Mode.CLEAR:
			if event.is_action_pressed("jump"):
				Sfx.play("ui", 0.0)
				level_index += 1
				_go_to_level(level_index)
		Mode.FINISHED:
			if event.is_action_pressed("jump"):
				Sfx.play("ui", 0.0)
				_quit_to_title()


# --- flow --------------------------------------------------------------------

func _start_run() -> void:
	run_time = 0.0
	run_deaths = 0
	run_gems = 0
	run_gem_total = 0
	level_index = 0
	_go_to_level(0)


func _go_to_level(index: int) -> void:
	mode = Mode.TRANSITION
	await screens.fade(1.0, 0.3).finished
	screens.hide_screen()
	_build_level(index)
	hud.visible = true
	mode = Mode.PLAYING
	screens.fade(0.0, 0.35)
	hud.show_hints(level.data.hints)


func _build_level(index: int) -> void:
	_clear_level()
	var data := LevelData.load_file(LEVELS[index])
	level = Level.new()
	level.build(data)
	world.add_child(level)
	level.gem_collected.connect(_on_gem_collected)
	level.checkpoint_reached.connect(func(spawn: Vector2) -> void: respawn_point = spawn)
	level.exit_reached.connect(_on_exit_reached)

	player = PLAYER_SCENE.instantiate()
	level.add_child(player)
	player.global_position = level.spawn_point
	player.died.connect(_on_player_died)
	respawn_point = level.spawn_point

	camera.target = player
	camera.set_bounds(level.bounds)
	camera.snap_to_target()

	level_time = 0.0
	level_deaths = 0
	level_gems = 0
	hud.set_level("%d. %s" % [index + 1, data.name], level.gem_total)


func _clear_level() -> void:
	Juice.reset()
	if is_instance_valid(level):
		level.queue_free()
	level = null
	player = null
	camera.target = null


func _quit_to_title() -> void:
	mode = Mode.TRANSITION
	await screens.fade(1.0, 0.3).finished
	_clear_level()
	hud.visible = false
	screens.show_title(Save.best_times.get(RUN_ID, 0.0))
	mode = Mode.TITLE
	screens.fade(0.0, 0.4)


func _set_paused(paused: bool) -> void:
	get_tree().paused = paused
	if paused:
		mode = Mode.PAUSED
		screens.show_pause()
		Sfx.play("ui_back", 0.0)
	else:
		mode = Mode.PLAYING
		screens.hide_screen()
		Sfx.play("ui", 0.0)


# --- events ------------------------------------------------------------------

func _on_gem_collected() -> void:
	level_gems += 1
	hud.set_gems(level_gems, level.gem_total)


func _on_player_died() -> void:
	level_deaths += 1
	hud.set_deaths(level_deaths)
	var dead := player
	# Timer pauses with the tree, so pausing mid-death doesn't skip the respawn.
	await get_tree().create_timer(RESPAWN_DELAY, false).timeout
	if dead != player or not is_instance_valid(dead):
		return  # level was left or reloaded meanwhile
	await screens.fade(1.0, 0.1).finished
	if dead != player or not is_instance_valid(dead):
		return
	level.reset_transients()
	player.respawn(respawn_point)
	camera.snap_to_target()
	screens.fade(0.0, 0.2)


func _on_exit_reached() -> void:
	mode = Mode.TRANSITION
	player.freeze()
	Sfx.play("exit", 0.0)
	Juice.shake(0.2)
	var tween := player.create_tween().set_parallel()
	tween.tween_property(player, "global_position:y", player.global_position.y - 8.0, 0.5)
	tween.tween_property(player, "modulate:a", 0.0, 0.5)

	var new_best := Save.record(level.data.id, level_time, level_gems)
	run_time += level_time
	run_deaths += level_deaths
	run_gems += level_gems
	run_gem_total += level.gem_total

	await get_tree().create_timer(0.7, false).timeout
	if level_index >= LEVELS.size() - 1:
		var run_best := Save.record(RUN_ID, run_time, run_gems)
		mode = Mode.FINISHED
		screens.show_finale(run_time, run_best, run_gems, run_gem_total, run_deaths)
	else:
		mode = Mode.CLEAR
		screens.show_level_clear(level.data.name, level_time, new_best, level_gems,
			level.gem_total, level_deaths)

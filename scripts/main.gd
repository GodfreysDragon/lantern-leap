extends Node
## Game loop: title -> levels -> finale, plus a level select for replaying
## single levels. Owns the run state (timer, deaths, gems), level loading,
## respawning, pausing and persistence of best times.

enum Mode { TITLE, SELECT, PLAYING, PAUSED, TRANSITION, CLEAR, FINISHED }

const LEVELS := [
	"res://levels/01_first_light.txt",
	"res://levels/02_the_well.txt",
	"res://levels/03_thorn_pass.txt",
	"res://levels/04_glass_air.txt",
	"res://levels/05_crumbling_way.txt",
]
const PLAYER_SCENE := preload("res://scenes/player.tscn")
const RESPAWN_DELAY := 0.5
## How close (in tiles) the player must come to a tip's cell to see it.
const TIP_RANGE := Vector2i(3, 4)
## A death within this many tiles of a shown tip shows it again next time.
const TIP_REPEAT_RANGE := 12
const RUN_ID := "full_run"

var mode := Mode.TITLE
var level: Level
var player: Player
var level_index := 0
## Playing one level from the level select rather than a full run.
var practice := false
var select_index := 0
var respawn_point := Vector2.ZERO
## A bot playing the level for the player to watch (-1: none), see BotDriver.
var bot_kind := -1
var _bot: BotDriver
var _tips_shown := {}  # tip index -> true once shown this attempt

var level_time := 0.0
var level_deaths := 0
var level_gems := 0
## Gems held when the last checkpoint was lit: what a death drops back to.
var banked_gems := 0

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
	_show_title()
	screens.fade(0.0, 0.8)


func _physics_process(delta: float) -> void:
	if mode != Mode.PLAYING or not is_instance_valid(player):
		return
	level_time += delta
	hud.set_time(level_time)
	# Falling out of the bottom of the map is a death.
	if player.state != Player.State.DEAD and player.global_position.y > level.bounds.end.y + 24.0:
		player.die()
	_check_tips()


## Shows a level's place-tied hints as the player reaches them, so a hint
## arrives with the challenge it explains rather than at the level start.
func _check_tips() -> void:
	var at := Vector2i((player.global_position / Level.TILE).floor())
	for i in level.data.tips.size():
		if _tips_shown.has(i):
			continue
		var c: Vector2i = level.data.tips[i].cell
		if absi(at.x - c.x) <= TIP_RANGE.x and absi(at.y - c.y) <= TIP_RANGE.y:
			_tips_shown[i] = true
			hud.show_hints(PackedStringArray([level.data.tips[i].text]))


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
			elif event.is_action_pressed("dash"):
				Sfx.play("ui", 0.0)
				mode = Mode.SELECT
				_show_level_select()
		Mode.SELECT:
			var step := 0
			if event.is_action_pressed("move_up") or event.is_action_pressed("move_left"):
				step = -1
			elif event.is_action_pressed("move_down") or event.is_action_pressed("move_right"):
				step = 1
			if step != 0:
				var index := clampi(select_index + step, 0, unlocked_count() - 1)
				if index != select_index:
					select_index = index
					Sfx.play("ui_back", 0.0)
					_show_level_select()
			elif event.is_action_pressed("jump"):
				Sfx.play("ui", 0.0)
				_start_practice(select_index)
			elif event.is_action_pressed("bot_speedrun") or event.is_action_pressed("bot_normal"):
				if BotDriver.has_data(_level_id(select_index)):
					Sfx.play("ui", 0.0)
					var speedrun := event.is_action_pressed("bot_speedrun")
					_start_practice(select_index, BotDriver.Kind.SPEEDRUN if speedrun else BotDriver.Kind.NORMAL)
			elif event.is_action_pressed("dash") or event.is_action_pressed("pause"):
				Sfx.play("ui_back", 0.0)
				mode = Mode.TITLE
				_show_title()
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
				if practice:
					_quit_to_select()
				else:
					level_index += 1
					_go_to_level(level_index)
		Mode.FINISHED:
			if event.is_action_pressed("jump"):
				Sfx.play("ui", 0.0)
				_quit_to_title()


# --- flow --------------------------------------------------------------------

## Levels unlock in order: the first is always open, each later one once the
## level before it has been cleared.
func unlocked_count() -> int:
	var count := 1
	while count < LEVELS.size() and Save.best_times.has(_level_id(count - 1)):
		count += 1
	return count


static func _level_id(index: int) -> String:
	return String(LEVELS[index]).get_file().get_basename()


func _show_title() -> void:
	screens.show_title(Save.best_times.get(RUN_ID, 0.0))


func _show_level_select() -> void:
	var entries: Array[Dictionary] = []
	var unlocked := unlocked_count()
	for i in LEVELS.size():
		var data := LevelData.load_file(LEVELS[i])
		entries.append({
			"name": data.name,
			"unlocked": i < unlocked,
			"best_time": Save.best_times.get(data.id, 0.0),
			"gems": Save.best_gems.get(data.id, 0),
			"gem_total": data.find(LevelData.GEM).size(),
		})
	screens.show_level_select(entries, select_index)


func _start_practice(index: int, bot := -1) -> void:
	practice = true
	bot_kind = bot
	level_index = index
	_go_to_level(index)


func _start_run() -> void:
	practice = false
	bot_kind = -1
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
	if bot_kind >= 0:
		_bot = BotDriver.new(self, bot_kind)
		add_child(_bot)
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
	level.checkpoint_reached.connect(_on_checkpoint_reached)
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
	_tips_shown.clear()
	level_gems = 0
	banked_gems = 0
	var title := "%d. %s" % [index + 1, data.name]
	if bot_kind >= 0:
		title += "   -   " + BotDriver.label(bot_kind)
	hud.set_level(title, level.gem_total)


func _clear_level() -> void:
	if is_instance_valid(_bot):
		_bot.queue_free()
	_bot = null
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
	_show_title()
	mode = Mode.TITLE
	screens.fade(0.0, 0.4)


func _quit_to_select() -> void:
	mode = Mode.TRANSITION
	await screens.fade(1.0, 0.3).finished
	_clear_level()
	hud.visible = false
	select_index = mini(level_index + 1, unlocked_count() - 1)
	_show_level_select()
	mode = Mode.SELECT
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


func _on_checkpoint_reached(spawn: Vector2) -> void:
	respawn_point = spawn
	banked_gems = level_gems


func _on_player_died() -> void:
	level_deaths += 1
	hud.set_deaths(level_deaths)
	# Struggling near a tip: show it again on the way back.
	var at := player.global_position / Level.TILE
	for i in _tips_shown.keys():
		if at.distance_to(Vector2(level.data.tips[i].cell)) <= TIP_REPEAT_RANGE:
			_tips_shown.erase(i)
	var dead := player
	# Timer pauses with the tree, so pausing mid-death doesn't skip the respawn.
	await get_tree().create_timer(RESPAWN_DELAY, false).timeout
	if dead != player or not is_instance_valid(dead):
		return  # level was left or reloaded meanwhile
	await screens.fade(1.0, 0.1).finished
	if dead != player or not is_instance_valid(dead):
		return
	level.reset_transients()  # also puts unbanked gems back
	if level_gems != banked_gems:
		level_gems = banked_gems
		hud.set_gems(level_gems, level.gem_total)
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

	# A bot's run is for watching, not for the records.
	var new_best := Save.record(level.data.id, level_time, level_gems) if bot_kind < 0 else false
	if practice:
		await get_tree().create_timer(0.7, false).timeout
		mode = Mode.CLEAR
		screens.show_level_clear(level.data.name, level_time, new_best, level_gems,
			level.gem_total, level_deaths, "press  JUMP  for level select")
		return
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

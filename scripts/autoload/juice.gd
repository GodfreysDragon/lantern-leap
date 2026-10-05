extends Node
## Global game-feel helpers: screen shake and hit-stop. Anything in the game
## can call `Juice.shake(0.3)` without needing a reference to the camera.

var camera: GameCamera

var _hitstop_end_ms := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	# Hit-stop is timed against the wall clock: with time_scale at 0 the
	# scaled delta (and scaled timers) would never advance.
	if _hitstop_end_ms > 0 and Time.get_ticks_msec() >= _hitstop_end_ms:
		reset()


func shake(trauma: float) -> void:
	if is_instance_valid(camera):
		camera.add_trauma(trauma)


## Freezes the simulation for a few frames to sell an impact. Overlapping
## calls extend the freeze rather than cutting each other short.
func hitstop(duration: float) -> void:
	_hitstop_end_ms = maxi(_hitstop_end_ms, Time.get_ticks_msec() + int(duration * 1000.0))
	Engine.time_scale = 0.0


func reset() -> void:
	_hitstop_end_ms = 0
	Engine.time_scale = 1.0

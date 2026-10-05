class_name GameCamera
extends Camera2D
## Follows the player with velocity-based look-ahead and trauma-based shake
## (shake strength = trauma², decaying over time, driven by smooth noise so it
## rolls rather than jitters).

const LOOK_AHEAD := 36.0
const VERTICAL_BIAS := -18.0
const MAX_SHAKE := 7.0
const TRAUMA_DECAY := 1.7

var target: Player

var _trauma := 0.0
var _look := 0.0
var _noise := FastNoiseLite.new()
var _noise_t := 0.0


func _ready() -> void:
	process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	position_smoothing_enabled = true
	position_smoothing_speed = 8.0
	_noise.frequency = 0.9
	Juice.camera = self


func _physics_process(delta: float) -> void:
	if not is_instance_valid(target):
		return
	var look_goal := 0.0
	if target.state != Player.State.DEAD:
		look_goal = clampf(target.velocity.x / target.max_speed, -1.0, 1.0) * LOOK_AHEAD
	_look = lerpf(_look, look_goal, 1.0 - exp(-2.5 * delta))
	global_position = target.global_position + Vector2(_look, VERTICAL_BIAS)


func _process(delta: float) -> void:
	_trauma = maxf(_trauma - TRAUMA_DECAY * delta, 0.0)
	_noise_t += delta * 60.0
	var amount := _trauma * _trauma * MAX_SHAKE
	offset = Vector2(_noise.get_noise_2d(_noise_t, 0.0), _noise.get_noise_2d(0.0, _noise_t)) * amount


func add_trauma(amount: float) -> void:
	_trauma = minf(_trauma + amount, 1.0)


func set_bounds(bounds: Rect2) -> void:
	limit_left = int(bounds.position.x)
	limit_top = int(bounds.position.y)
	limit_right = int(bounds.end.x)
	limit_bottom = int(bounds.end.y)


## Jump straight to the target (level start), skipping smoothing.
func snap_to_target() -> void:
	_look = 0.0
	if is_instance_valid(target):
		global_position = target.global_position + Vector2(0, VERTICAL_BIAS)
	reset_smoothing()

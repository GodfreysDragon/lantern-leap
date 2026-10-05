class_name Player
extends CharacterBody2D
## Platformer controller tuned for game feel rather than physical accuracy.
##
## Forgiveness: coyote time, jump buffering, corner correction, wall coyote.
## Expressiveness: variable jump height, apex hang, fast-fall, 8-way dash with
## dash-jump momentum. Every tunable is exported so it can be tweaked live
## from the inspector while the game is running.

signal died
signal dashed

enum State { NORMAL, DASH, DEAD, FROZEN }

const SIZE := Vector2(10, 13)

@export_group("Run")
@export var max_speed := 125.0
@export var ground_accel := 1400.0
@export var ground_decel := 1700.0
@export var air_accel := 950.0
@export var air_decel := 520.0
## Acceleration multiplier while reversing direction, for snappy turnarounds.
@export var turn_multiplier := 1.8

@export_group("Jump")
@export var jump_velocity := 312.0
@export var gravity := 920.0
@export var fall_gravity_multiplier := 1.3
## Below this vertical speed (while holding jump) gravity is reduced, giving
## a brief hang at the top of the arc that makes jumps easier to aim.
@export var apex_threshold := 45.0
@export var apex_gravity_multiplier := 0.5
@export var jump_cut_multiplier := 0.42
@export var max_fall_speed := 290.0
@export var fast_fall_speed := 400.0
@export var coyote_time := 0.1
@export var jump_buffer_time := 0.12
## How many pixels the player is nudged sideways to slip past a ceiling corner.
@export var corner_correction := 5

@export_group("Wall")
@export var wall_slide_speed := 55.0
@export var wall_jump_velocity := Vector2(150.0, 290.0)
## Horizontal input is ignored this long after a wall jump so the push-off reads.
@export var wall_jump_lock := 0.13
@export var wall_coyote_time := 0.08

@export_group("Dash")
@export var dash_speed := 330.0
@export var dash_time := 0.15
@export var dash_buffer_time := 0.1
@export var spring_velocity := 470.0

var state := State.NORMAL
var facing := 1
var has_dash := true

var _coyote := 0.0
var _jump_buffer := 0.0
var _dash_buffer := 0.0
var _wall_coyote := 0.0
var _wall_lock := 0.0
var _last_wall_dir := 0
var _is_jumping := false  # true only for player-initiated jumps (cuttable)
var _dash_timer := 0.0
var _dash_dir := Vector2.ZERO
var _ghost_timer := 0.0
var _dust_timer := 0.0
var _was_on_floor := true
var _prev_velocity := Vector2.ZERO
var _input := Vector2.ZERO
var _light_energy := 1.0

@onready var visual: PlayerVisual = $Visual
@onready var light: PointLight2D = $Light


func _ready() -> void:
	add_to_group("player")
	light.texture = Fx.light_texture()
	_light_energy = light.energy


func _physics_process(delta: float) -> void:
	if state == State.DEAD or state == State.FROZEN:
		return

	_read_input(delta)
	_prev_velocity = velocity

	match state:
		State.NORMAL:
			_normal_step(delta)
		State.DASH:
			_dash_step(delta)

	_corner_correct(delta)
	move_and_slide()
	_after_move(delta)


# --- input -------------------------------------------------------------------

func _read_input(delta: float) -> void:
	var raw := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down"))
	# Digitize analog input so a half-tilted stick doesn't produce a half-speed run.
	_input = Vector2(_digital(raw.x), _digital(raw.y))

	_jump_buffer = jump_buffer_time if Input.is_action_just_pressed("jump") else _jump_buffer - delta
	_dash_buffer = dash_buffer_time if Input.is_action_just_pressed("dash") else _dash_buffer - delta


static func _digital(v: float) -> float:
	return signf(v) if absf(v) > 0.3 else 0.0


# --- states ------------------------------------------------------------------

func _normal_step(delta: float) -> void:
	var on_floor := is_on_floor()
	if on_floor:
		_coyote = coyote_time
		has_dash = true
	else:
		_coyote -= delta

	var wall_dir := _wall_dir()
	if wall_dir != 0 and not on_floor:
		_wall_coyote = wall_coyote_time
		_last_wall_dir = wall_dir
	else:
		_wall_coyote -= delta

	# Horizontal movement.
	_wall_lock -= delta
	if _wall_lock <= 0.0:
		if _input.x != 0.0:
			facing = int(_input.x)
		var target := _input.x * max_speed
		var accel: float
		if _input.x == 0.0:
			accel = ground_decel if on_floor else air_decel
		else:
			accel = ground_accel if on_floor else air_accel
			if signf(velocity.x) != _input.x and velocity.x != 0.0:
				accel *= turn_multiplier
			elif absf(velocity.x) > max_speed:
				# Carrying dash momentum: bleed it off gently instead of clamping.
				accel = air_decel
		velocity.x = move_toward(velocity.x, target, accel * delta)

	# Gravity, with a lighter apex and heavier fall.
	var g := gravity
	if velocity.y > 0.0:
		g *= fall_gravity_multiplier
	if absf(velocity.y) < apex_threshold and Input.is_action_pressed("jump") and not on_floor:
		g *= apex_gravity_multiplier
	velocity.y += g * delta

	var fall_cap := fast_fall_speed if _input.y > 0.0 else max_fall_speed
	var sliding := not on_floor and wall_dir != 0 and _input.x == wall_dir and velocity.y > 0.0
	if sliding:
		fall_cap = wall_slide_speed
		_dust_timer -= delta
		if _dust_timer <= 0.0:
			_dust_timer = 0.08
			Fx.burst(get_parent(), global_position + Vector2(wall_dir * SIZE.x * 0.5, -10),
				Color(0.85, 0.8, 1.0, 0.7), 2, 20.0, Vector2(-wall_dir, -1), 30.0, 0.3, 120.0)
		# Ease into the slide speed so grabbing a wall mid-fall isn't a hard stop.
		velocity.y = move_toward(velocity.y, minf(velocity.y, fall_cap), 1600.0 * delta)
	else:
		velocity.y = minf(velocity.y, fall_cap)
	visual.wall_sliding = sliding

	# Jumping. Ground jump wins over wall jump when both are possible.
	if _jump_buffer > 0.0:
		if _coyote > 0.0:
			_jump()
		elif _wall_coyote > 0.0:
			_wall_jump(_last_wall_dir)

	# Variable jump height: releasing early cuts the rise. Checking "not pressed"
	# instead of "just released" also handles a buffered tap that ended mid-air.
	if _is_jumping and velocity.y < 0.0 and not Input.is_action_pressed("jump"):
		velocity.y *= jump_cut_multiplier
		_is_jumping = false
	if velocity.y >= 0.0:
		_is_jumping = false

	if _dash_buffer > 0.0 and has_dash:
		_start_dash()


func _dash_step(delta: float) -> void:
	_dash_timer -= delta
	velocity = _dash_dir * dash_speed

	_ghost_timer -= delta
	if _ghost_timer <= 0.0:
		_ghost_timer = 0.025
		Fx.ghost(get_parent(), global_position, SIZE, visual.scale, Color(0.55, 0.85, 1.0))

	# Dash-jump: jumping out of a grounded dash keeps the horizontal speed.
	if _jump_buffer > 0.0 and (is_on_floor() or _coyote > 0.0) and _dash_dir.y >= 0.0:
		state = State.NORMAL
		velocity.x = _dash_dir.x * dash_speed * 0.85
		_jump()
		return

	if _dash_timer <= 0.0:
		state = State.NORMAL
		visual.dashing = false
		if velocity.y < 0.0:
			velocity.y *= 0.45
		velocity.x *= 0.7


func _start_dash() -> void:
	has_dash = false
	_dash_buffer = 0.0
	_jump_buffer = 0.0
	_is_jumping = false
	var dir := _input
	if dir == Vector2.ZERO:
		dir = Vector2(facing, 0)
	_dash_dir = dir.normalized()
	if _dash_dir.x != 0.0:
		facing = int(signf(_dash_dir.x))
	_dash_timer = dash_time
	_ghost_timer = 0.0
	velocity = _dash_dir * dash_speed
	state = State.DASH
	visual.dashing = true
	visual.squash = Vector2(1.3, 0.75) if _dash_dir.y == 0.0 else Vector2(0.75, 1.3)
	Fx.burst(get_parent(), global_position + Vector2(0, -6), Color(0.7, 0.9, 1.0), 8, 90.0,
		-_dash_dir, 50.0, 0.35, 0.0)
	Sfx.play("dash")
	Juice.hitstop(0.045)
	Juice.shake(0.25)
	dashed.emit()


# --- actions -----------------------------------------------------------------

func _jump() -> void:
	velocity.y = -jump_velocity
	_jump_buffer = 0.0
	_coyote = 0.0
	_is_jumping = true
	visual.squash = Vector2(0.7, 1.35)
	Fx.burst(get_parent(), global_position, Color(0.8, 0.75, 0.95, 0.8), 6, 45.0,
		Vector2.UP, 70.0, 0.3, 150.0)
	Sfx.play("jump")


func _wall_jump(wall_dir: int) -> void:
	velocity = Vector2(-wall_dir * wall_jump_velocity.x, -wall_jump_velocity.y)
	facing = -wall_dir
	_jump_buffer = 0.0
	_wall_coyote = 0.0
	_wall_lock = wall_jump_lock
	_is_jumping = true
	visual.squash = Vector2(0.75, 1.3)
	Fx.burst(get_parent(), global_position + Vector2(wall_dir * SIZE.x * 0.5, -6),
		Color(0.8, 0.75, 0.95, 0.8), 6, 50.0, Vector2(-wall_dir, -0.5), 50.0, 0.3, 150.0)
	Sfx.play("wall_jump")


## Called by springs.
func bounce(strength := -1.0) -> void:
	if state == State.DEAD:
		return
	if state == State.DASH:
		state = State.NORMAL
		visual.dashing = false
	velocity.y = -(spring_velocity if strength < 0.0 else strength)
	_is_jumping = false
	_coyote = 0.0
	has_dash = true
	visual.squash = Vector2(0.6, 1.45)


## Called by dash crystals. Returns false if the dash was already available,
## so the crystal isn't wasted.
func refill_dash() -> bool:
	if has_dash or state == State.DEAD:
		return false
	has_dash = true
	return true


func die() -> void:
	if state == State.DEAD:
		return
	state = State.DEAD
	velocity = Vector2.ZERO
	visual.visible = false
	light.energy = 0.0
	var center := global_position + Vector2(0, -6)
	Fx.burst(get_parent(), center, Color(1.0, 0.75, 0.35), 24, 170.0, Vector2.UP, 180.0, 0.7, 200.0, 3.0)
	Fx.burst(get_parent(), center, Color(1.0, 1.0, 0.9), 10, 110.0, Vector2.UP, 180.0, 0.4, 0.0, 2.0)
	Sfx.play("death", 0.0)
	Juice.hitstop(0.09)
	Juice.shake(0.55)
	died.emit()


func respawn(at: Vector2) -> void:
	global_position = at
	velocity = Vector2.ZERO
	state = State.NORMAL
	has_dash = true
	_is_jumping = false
	_jump_buffer = 0.0
	_dash_buffer = 0.0
	_wall_lock = 0.0
	visual.visible = true
	visual.dashing = false
	visual.squash = Vector2(1.5, 0.5)
	var tween := create_tween()
	tween.tween_property(light, "energy", _light_energy, 0.3).from(_light_energy * 2.0)
	Fx.burst(get_parent(), at + Vector2(0, -6), Color(1.0, 0.85, 0.5), 12, 60.0, Vector2.UP, 180.0, 0.4, -40.0)
	Sfx.play("respawn")


## Stops all control, e.g. while walking into the exit.
func freeze() -> void:
	state = State.FROZEN
	velocity = Vector2.ZERO


func global_rect() -> Rect2:
	return Rect2(global_position - Vector2(SIZE.x * 0.5, SIZE.y), SIZE)


# --- helpers -----------------------------------------------------------------

func _after_move(delta: float) -> void:
	var on_floor := is_on_floor()

	if on_floor and not _was_on_floor:
		var impact := clampf(_prev_velocity.y / max_fall_speed, 0.0, 1.0)
		visual.squash = Vector2(1.0 + 0.45 * impact, 1.0 - 0.4 * impact)
		if impact > 0.25:
			Fx.burst(get_parent(), global_position, Color(0.8, 0.75, 0.95, 0.8),
				int(4 + 8 * impact), 60.0 * impact + 20.0, Vector2.UP, 80.0, 0.35, 160.0)
			Sfx.play("land", 0.08, linear_to_db(impact))
		if impact > 0.9:
			Juice.shake(0.12)
	_was_on_floor = on_floor

	# Run dust and skid puffs.
	if on_floor and state == State.NORMAL:
		_dust_timer -= delta
		var skidding := _input.x != 0.0 and signf(velocity.x) != _input.x and absf(velocity.x) > 60.0
		if (absf(velocity.x) > 90.0 or skidding) and _dust_timer <= 0.0:
			_dust_timer = 0.06 if skidding else 0.14
			Fx.burst(get_parent(), global_position, Color(0.75, 0.7, 0.9, 0.6), 2, 25.0,
				Vector2(-signf(velocity.x), -1.0), 30.0, 0.3, 60.0)

	# Let crumbling blocks know they've been stood on or clung to.
	for i in get_slide_collision_count():
		var collider := get_slide_collision(i).get_collider()
		if collider != null and collider.has_method("touch"):
			collider.touch()

	visual.facing = facing
	visual.has_dash = has_dash
	light.color = Color(1.0, 0.78, 0.45) if has_dash else Color(0.55, 0.75, 1.0)


func _wall_dir() -> int:
	if test_move(global_transform, Vector2(2, 0)):
		return 1
	if test_move(global_transform, Vector2(-2, 0)):
		return -1
	return 0


## When rising into a ceiling edge by a few pixels, slide around it instead of
## bonking. One of the cheapest, most noticeable game-feel wins.
func _corner_correct(delta: float) -> void:
	if velocity.y >= 0.0:
		return
	var motion := Vector2(0, velocity.y * delta)
	if not test_move(global_transform, motion):
		return
	for nudge in range(1, corner_correction + 1):
		for side: int in [1, -1]:
			var offset := Vector2(nudge * side, 0)
			if test_move(global_transform, offset):
				continue
			if not test_move(global_transform.translated(offset), motion):
				global_position += offset
				return

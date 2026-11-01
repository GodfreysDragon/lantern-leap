class_name BotPolicy
extends RefCounted
## A scripted player for debugging and playtesting. It drives the real input
## actions, so the player controller can't tell it from a person.
##
## An attempt is one try at one challenge: a "segment" from the safe spot
## before it ({from: [x0, x1, row]} standing cells) to the safe spot after it
## ({to: ...}), optionally steering through {aim: [[x, row], ...]} first. A
## random seed picks the plan (when to jump, how long to hold, which way to
## dash), and the plan reacts to landings, walls and dash refills like a
## person would. An optional `noise` generator adds human-sized timing errors.
##
## Used by the in-game bot watcher (bot_driver.gd) and by tools/bots.gd, which
## searches for the plans and the speedrun stored in res://debug/bots/.

const T := 16.0
const ACTIONS := ["move_left", "move_right", "move_up", "move_down", "jump", "dash"]
## Human timing error, in 120 Hz frames (about 33 ms).
const TIMING_ERROR := 4.0
const DIRS := [Vector2(1, 0), Vector2(1, -1), Vector2(0, -1), Vector2(1, 1), Vector2(-1, -1),
	Vector2(-1, 0), Vector2(0, 1)]

var player: Player
var level: Level
var _tree: SceneTree
var _pressed := {}


func _init(p: Player, l: Level) -> void:
	player = p
	level = l
	_tree = p.get_tree()


## Where a plan starts: the x (in pixels) to stand on before attempting.
static func start_x(seg: Dictionary, seed_value: int) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var from: Array = seg.from
	return rng.randf_range(from[0] * T + 6.0, (from[1] + 1) * T - 6.0)


## One attempt at `seg` from where the player stands. Returns
## {ok, frames, timeline}; the timeline holds one input mask per frame.
func attempt(seg: Dictionary, skills: Array, seed_value: int, frames: int,
		noise: RandomNumberGenerator = null) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	rng.randf()  # the start x (see start_x), already used by the caller
	var timeline := PackedInt32Array()
	var still: bool = seg.get("still", false)  # stand and wait: no jumps or kicks
	var can_wall := skills.has("wall") and not still
	var can_dash := skills.has("dash")
	var to: Array = seg.to
	var tx: float = (to[0] + to[1] + 1) * 0.5 * T
	release_all()

	# The plan.
	var hop_delay: Array[int] = []
	var hop_hold: Array[int] = []
	for k in 8:
		hop_delay.append(rng.randi_range(0, 45) if k == 0 else rng.randi_range(0, 14))
		hop_hold.append(rng.randi_range(1, 40) if rng.randf() < 0.75 else 40)
	var dashes: Array[Dictionary] = []
	if can_dash:
		for k in rng.randi_range(0, 3):
			var d: Vector2 = DIRS[rng.randi_range(0, 4)] if rng.randf() < 0.85 \
				else DIRS[rng.randi_range(0, DIRS.size() - 1)]
			dashes.append({"after": rng.randi_range(0, 30), "dir": d, "ground": k == 0 and rng.randf() < 0.2})
	var p_single := rng.randf()
	var single_wall := rng.randf() < p_single
	var kick_delay := rng.randi_range(0, 10)
	var back_delay := rng.randi_range(6, 18)
	var kick_hold := rng.randi_range(6, 40)
	var wobble_start := rng.randi_range(0, frames)
	var wobble_len := rng.randi_range(0, 20) if rng.randf() < 0.5 else 0
	var wobble_x := rng.randi_range(-1, 1)
	var refill_delay := rng.randi_range(0, 12)
	var refill_up := rng.randf()
	if noise:
		for k in 8:
			hop_delay[k] = maxi(0, hop_delay[k] + _jitter(noise))
			hop_hold[k] = clampi(roundi(hop_hold[k] * noise.randfn(1.0, 0.25)), 1, 40)
		for d in dashes:
			d.after = maxi(0, d.after + _jitter(noise))
			if noise.randf() < 0.1:
				d.dir = _misdirect(d.dir, noise)
		refill_delay = maxi(2, refill_delay + absi(_jitter(noise)))
	var kick_delay_now := kick_delay
	var back_delay_now := back_delay

	var hop := 8 if still else 0
	var ground_frames := 0
	var jump_left := 0
	var since_action := 0
	var dash_i := 0
	var dash_left := 0
	var dash_dir := Vector2.ZERO
	var wall_frames := 0
	var kick_dir := 0
	var kick_age := 999
	var fresh := false
	var had_dash := true
	var refill_at := -1
	var aims: Array = seg.get("aim", [])
	var aim_i := 0

	for f in frames:
		if player.state == Player.State.DEAD or player.global_position.y > level.bounds.end.y + 24.0:
			release_all()
			return {"ok": false, "frames": f, "timeline": timeline}
		var pos := player.global_position
		var on_floor := player.is_on_floor()
		if f > 2 and on_floor and absf(pos.y - (to[2] + 1) * T) < 1.0 \
				and pos.x >= to[0] * T and pos.x <= (to[1] + 1) * T:
			release_all()
			return {"ok": true, "frames": f, "timeline": timeline}

		# Steer toward the next waypoint, then the landing.
		var gx := tx
		while aim_i < aims.size() and pos.y <= (aims[aim_i][1] + 1) * T + 0.5:
			aim_i += 1
		if aim_i < aims.size():
			gx = (aims[aim_i][0] + 0.5) * T
		var dir := signf(gx - pos.x) if absf(gx - pos.x) > 3.0 else 0.0
		var hx := dir
		var vy := 0.0
		var jump := false
		var dash := false
		since_action += 1
		kick_age += 1

		# Jumps: one per landing, after the plan's delay.
		if on_floor:
			ground_frames += 1
			wall_frames = 0
			kick_age = 999
			if jump_left <= 0 and ground_frames > hop_delay[mini(hop, 7)] and hop < 8:
				jump_left = hop_hold[mini(hop, 7)]
				hop += 1
				since_action = 0
				fresh = true
		else:
			ground_frames = 0

		# Wall kicks: hold into the wall, kick, then come back to the same wall
		# (single-wall climb) or carry on to the other one.
		var wd := player._wall_dir()
		if can_wall and not on_floor and wd != 0 and kick_age > 4:
			wall_frames += 1
			hx = wd
			if wall_frames > kick_delay_now and jump_left <= 0:
				jump_left = kick_hold
				if noise:
					kick_delay_now = maxi(1, kick_delay + _jitter(noise))
					back_delay_now = maxi(2, back_delay + _jitter(noise))
					jump_left = clampi(roundi(kick_hold * noise.randfn(1.0, 0.25)), 2, 40)
				kick_dir = -wd
				single_wall = rng.randf() < p_single and not _spikes_above(pos, wd)
				kick_age = 0
				fresh = true
				wall_frames = 0
				since_action = 0
		elif wd == 0:
			wall_frames = 0
		if kick_age < 60 and can_wall:
			hx = -kick_dir if (single_wall and kick_age > back_delay_now) else kick_dir

		# Dashes: the planned ones, plus another whenever a crystal or wall
		# refills the dash in mid-air.
		if can_dash and not on_floor and player.has_dash and not had_dash and dash_i > 0:
			refill_at = f + refill_delay
		had_dash = player.has_dash
		if refill_at >= 0 and f >= refill_at and dash_left <= 0 and player.has_dash and not on_floor:
			refill_at = -1
			var side := dir if dir != 0.0 else 1.0
			dash_dir = Vector2(side, -1.0) if rng.randf() < refill_up else Vector2(side, 0.0)
			if rng.randf() < 0.25:
				dash_dir = Vector2(0, -1)
			if noise and noise.randf() < 0.1:
				dash_dir = _misdirect(dash_dir, noise)
			dash = true
			dash_left = 18
			since_action = 0
		elif dash_left > 0:
			dash_left -= 1
			dash = false
			hx = dash_dir.x
			vy = dash_dir.y
		elif dash_i < dashes.size() and player.has_dash:
			var dsh: Dictionary = dashes[dash_i]
			var ready: bool = (on_floor and dsh.ground and ground_frames > 2) \
				or (not on_floor and not dsh.ground and since_action >= dsh.after)
			if ready:
				dash_dir = dsh.dir
				dash_dir.x *= dir if dir != 0.0 else 1.0
				dash = true
				dash_left = 18
				dash_i += 1
				since_action = 0
				if dsh.ground:
					jump_left = 0
					hop_delay[mini(hop, 7)] = 0
		if dash:
			hx = dash_dir.x
			vy = dash_dir.y

		if f >= wobble_start and f < wobble_start + wobble_len:
			hx = wobble_x

		if jump_left > 0:
			jump = true
			jump_left -= 1
			if fresh and _pressed.get("jump", false):
				jump = false  # a fresh press needs a released frame first
				jump_left += 1
			fresh = false
		# Only press jump where it does something intended: never buffered in
		# mid-air toward a wall unless wall jumps are allowed.
		if jump and not _pressed.get("jump", false):
			if not (on_floor or player._coyote > 0.0 or player.state == Player.State.DASH \
					or (can_wall and wd != 0)):
				jump = false
				jump_left = 0
		_set_inputs(hx, vy, jump, dash)
		timeline.append(mask())
		await step()
	release_all()
	return {"ok": false, "frames": frames, "timeline": timeline}


## Plays back a recorded timeline, one input mask per frame.
func replay(timeline: PackedInt32Array) -> void:
	for m in timeline:
		for i in ACTIONS.size():
			press(ACTIONS[i], (m >> i) & 1 == 1)
		await step()
	release_all()


## Walks to `x` on the current floor and stops there, like a person lining up.
func walk_to(x: float, max_frames := 600) -> void:
	for f in max_frames:
		if player.state == Player.State.DEAD:
			break
		var dx := x - player.global_position.x
		if absf(dx) < 3.0 and absf(player.velocity.x) < 1.0 and player.is_on_floor():
			break
		# Run while far, then tap toward the spot so the stop doesn't overshoot.
		var hx := 0.0
		if absf(dx) >= 12.0 or (absf(dx) >= 3.0 and f % 4 == 0):
			hx = signf(dx)
		_set_inputs(hx, 0.0, false, false)
		await step()
	release_all()


## Waits one physics frame, and stays put while the game is paused.
func step() -> void:
	await _tree.physics_frame
	while _tree.paused:
		await _tree.physics_frame


func mask() -> int:
	var m := 0
	for i in ACTIONS.size():
		if _pressed.get(ACTIONS[i], false):
			m |= 1 << i
	return m


func press(action: String, on: bool) -> void:
	if _pressed.get(action, false) == on:
		return
	_pressed[action] = on
	if on:
		Input.action_press(action)
	else:
		Input.action_release(action)


func release_all() -> void:
	for a in ACTIONS:
		press(a, false)


## Run-length encoding for timelines: [mask, count, mask, count, ...].
static func encode(timeline: PackedInt32Array) -> Array[int]:
	var out: Array[int] = []
	for m in timeline:
		if out.size() >= 2 and out[-2] == m:
			out[-1] += 1
		else:
			out.append_array([m, 1])
	return out


static func decode(runs: Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in range(0, runs.size(), 2):
		for k in int(runs[i + 1]):
			out.append(int(runs[i]))
	return out


func _set_inputs(hx: float, vy: float, jump: bool, dash: bool) -> void:
	press("move_left", hx < 0.0)
	press("move_right", hx > 0.0)
	press("move_up", vy < 0.0)
	press("move_down", vy > 0.0)
	press("jump", jump)
	press("dash", dash)


## True if the wall face the player is touching has spikes in the next few rows up.
func _spikes_above(pos: Vector2, wd: int) -> bool:
	var cx := int(floor(pos.x / T))
	var cy := int(floor((pos.y - 1.0) / T))
	for dy in range(0, 5):
		for dx in [0, wd]:
			if level.data.cell(cx + dx, cy - dy) == LevelData.SPIKE:
				return true
	return false


static func _jitter(noise: RandomNumberGenerator) -> int:
	return roundi(noise.randfn(0.0, TIMING_ERROR))


## A dash 45° off from the intended direction.
static func _misdirect(d: Vector2, noise: RandomNumberGenerator) -> Vector2:
	return d.rotated(PI / 4.0 * (1 if noise.randf() < 0.5 else -1)).round()

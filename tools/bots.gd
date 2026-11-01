extends Node
## Fills in res://debug/bots/<level>.json for the bot watcher (BotDriver).
## Each file lists the level's challenges as segments between safe spots
## (written by the level generator; edit them by hand if a level changes) and
## the skills allowed. This tool adds:
##   normal:   per challenge, the routes (plan seeds) a normal player succeeds
##             with most often under human-sized timing errors;
##   speedrun: the fastest unbroken run it can find, as run-length encoded
##             inputs, proved by replaying it from the spawn.
## Run headless; it takes a few minutes per level:
##   godot --headless --path . --fixed-fps 120 res://tools/bots.tscn
## Set LEVEL_ONLY=02 to redo one level. Set RESUME=1 to keep the routes and
## speedrun already in the file and do only what is missing; progress is
## saved after each challenge, so an interrupted run can pick up from there.
## Set REDO=5,19 after changing those challenges: their routes are found again,
## and the speedrun is kept up to the first of them and searched on from there.

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const MAIN := preload("res://scripts/main.gd")
const T := BotPolicy.T
const FRAMES := 900
const SEARCH := 400  # plans tried per challenge
const ROUTES := 10  # successful plans kept for scoring
const NOISY_TRIES := 12  # noisy attempts per plan when scoring it
const KEEP := 3  # best plans stored for the normal player

var level: Level
var player: Player
var policy: BotPolicy
var _exited := false


func _ready() -> void:
	Save.persist = false
	Juice.hitstop_enabled = false
	_run.call_deferred()


func _run() -> void:
	for path in MAIN.LEVELS:
		var id := String(path).get_file().get_basename()
		if OS.get_environment("LEVEL_ONLY") != "" and not id.begins_with(OS.get_environment("LEVEL_ONLY")):
			continue
		var data_path := BotDriver.data_path(id)
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(data_path))
		print("== ", id)
		var redo: Array = Array(OS.get_environment("REDO").split(",", false)).map(
			func(n: String) -> int: return n.to_int() - 1)
		if not redo.is_empty():
			var normal: Array = data.get("normal", [])
			for k: int in redo:
				if k < normal.size():
					normal[k] = null
			if data.has("speedrun"):
				data.speedrun_partial = (await _split(path, data)).slice(0, redo.min())
				data.erase("speedrun")
			_save(data_path, data)
		elif OS.get_environment("RESUME") != "1":
			data.erase("normal")
			data.erase("speedrun")
			data.erase("speedrun_partial")
		await _normal_routes(path, data, data_path)
		if data.has("speedrun"):
			continue
		var run := await _speedrun(path, data, data_path)
		if run.is_empty():
			printerr("  no speedrun found for ", id)
		else:
			data.speedrun = BotPolicy.encode(run)
			data.erase("speedrun_partial")
			print("  speedrun %.2f s" % (run.size() / 120.0))
			_save(data_path, data)
	print("DONE")
	get_tree().quit()


func _build(path: String) -> void:
	if is_instance_valid(level):
		level.queue_free()
		await get_tree().physics_frame
	level = Level.new()
	level.build(LevelData.load_file(path))
	add_child(level)
	level.exit_reached.connect(func() -> void: _exited = true)
	player = PLAYER_SCENE.instantiate()
	level.add_child(player)
	player.global_position = level.spawn_point
	policy = BotPolicy.new(player, level)
	_exited = false
	for i in 3:
		await get_tree().physics_frame


# --- normal player -------------------------------------------------------------

## Standing on the safe spot, tries plans until ROUTES succeed, then scores
## each with noisy attempts and keeps the most reliable. Fills data.normal,
## saving after each challenge and skipping those already there (not null).
func _normal_routes(path: String, data: Dictionary, data_path: String) -> void:
	var out: Array = data.get("normal", [])
	out.resize(data.segments.size())
	if not out.has(null):
		return
	await _build(path)
	for idx in out.size():
		if out[idx] != null:
			continue
		var seg: Dictionary = data.segments[idx]
		var found: Array[int] = []
		for i in SEARCH:
			var r: Dictionary = await _from_spot(seg, data.skills, 1000 + i, null)
			if r.ok:
				found.append(1000 + i)
				if found.size() >= ROUTES:
					break
		var scored: Array = []
		for s in found:
			var wins := 0
			for k in NOISY_TRIES:
				var noise := RandomNumberGenerator.new()
				noise.seed = s * 97 + k
				if (await _from_spot(seg, data.skills, s, noise)).ok:
					wins += 1
			scored.append([wins, s])
		scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
		var keep: Array = scored.slice(0, KEEP).map(func(e: Array) -> int: return e[1])
		var best: float = scored[0][0] / float(NOISY_TRIES) if not scored.is_empty() else 0.0
		print("  %-28s routes %2d  best %3.0f%%" % [seg.name, found.size(), best * 100.0])
		out[idx] = keep
		data.normal = out
		_save(data_path, data)


func _save(data_path: String, data: Dictionary) -> void:
	var f := FileAccess.open(data_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data) + "\n")


func _from_spot(seg: Dictionary, skills: Array, plan: int, noise: RandomNumberGenerator) -> Dictionary:
	var from: Array = seg.from
	var sx := BotPolicy.start_x(seg, plan)
	if noise:
		sx = clampf(sx + noise.randfn(0.0, 4.0), from[0] * T + 5.0, (from[1] + 1) * T - 5.0)
	policy.release_all()
	level.reset_transients()
	player.respawn(Vector2(sx, (from[2] + 1) * T))
	await get_tree().physics_frame
	await get_tree().physics_frame
	return await policy.attempt(seg, skills, plan, FRAMES, noise)


# --- speedrun ----------------------------------------------------------------

## The fastest route through each challenge, carrying momentum from the last.
## A dead end backs up and takes the next-fastest route through the previous
## challenge. Every choice is checked by a real replay from the spawn. The
## challenges settled so far are saved as speedrun_partial; a resumed run
## replays those once and never backs up into them.
func _speedrun(path: String, data: Dictionary, data_path: String) -> PackedInt32Array:
	var segs: Array = data.segments
	var n := segs.size()
	var done: Array = data.get("speedrun_partial", [])
	var cands: Array = []
	var choice: Array[int] = []
	cands.resize(n)
	choice.resize(n)
	await _build(path)
	var snaps: Array = []
	for k in done.size():
		cands[k] = [{"timeline": BotPolicy.decode(done[k])}]
		choice[k] = 0
		snaps.append(null)
		await policy.replay(cands[k][0].timeline)
	snaps.append(_capture())
	var first := done.size()
	if first > 0:
		print("  speedrun resumes at challenge %d" % (first + 1))
	var backtracks := 0
	var i := first
	while i < n:
		var seg: Dictionary = segs[i]
		if cands[i] == null:
			var found: Array = []
			# Arriving at speed can rule out most plans: keep looking (up to
			# three times as long) until at least one works.
			for k in SEARCH * 3:
				if k >= SEARCH and not found.is_empty():
					break
				policy.release_all()
				level.reset_transients()
				_restore(snaps[i])
				var r: Dictionary = await policy.attempt(seg, data.skills, 5000 + k, FRAMES)
				if r.ok:
					found.append(r)
					if found.size() >= 25:
						break
			found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.frames < b.frames)
			cands[i] = found
			choice[i] = 0
		if choice[i] >= cands[i].size():
			if i == first or backtracks >= 40:
				return PackedInt32Array()
			cands[i] = null
			i -= 1
			choice[i] += 1
			backtracks += 1
			continue
		await _build(path)
		for k in i:
			await policy.replay(cands[k][choice[k]].timeline)
		await policy.replay(cands[i][choice[i]].timeline)
		var to: Array = seg.to
		var p := player.global_position
		if player.state == Player.State.DEAD or not player.is_on_floor() \
				or p.x < to[0] * T or p.x > (to[1] + 1) * T:
			choice[i] += 1
			continue
		snaps.resize(i + 1)
		snaps.append(_capture())
		if i + 1 < n:
			cands[i + 1] = null
		i += 1
		data.speedrun_partial = range(i).map(func(k: int) -> Array: return BotPolicy.encode(cands[k][choice[k]].timeline))
		_save(data_path, data)
		print("  speedrun through challenge %d" % i)
	var run := PackedInt32Array()
	for k in n:
		run.append_array(cands[k][choice[k]].timeline)
	# Into the door.
	var door: Vector2i = level.data.find(LevelData.EXIT)[0]
	for f in 600:
		if _exited:
			break
		var dx := (door.x + 0.5) * T - player.global_position.x
		policy.press("move_right", dx > 2.0)
		policy.press("move_left", dx < -2.0)
		run.append(policy.mask())
		await get_tree().physics_frame
	policy.release_all()
	# Proof: the whole run, replayed from the spawn on a fresh level.
	await _build(path)
	await policy.replay(run)
	for f in 30:
		await get_tree().physics_frame
	return run if _exited else PackedInt32Array()


## Cuts the stored speedrun into one timeline per challenge, each ending where
## the run lands on that challenge's safe spot (as BotPolicy.attempt ends).
func _split(path: String, data: Dictionary) -> Array:
	var run := BotPolicy.decode(data.speedrun)
	await _build(path)
	var pieces: Array = []
	var start := 0
	for f in run.size():
		if pieces.size() >= data.segments.size():
			break
		var to: Array = data.segments[pieces.size()].to
		var p := player.global_position
		if f - start > 2 and player.is_on_floor() and absf(p.y - (to[2] + 1) * T) < 1.0 				and p.x >= to[0] * T and p.x <= (to[1] + 1) * T:
			pieces.append(BotPolicy.encode(run.slice(start, f)))
			start = f
		for i in BotPolicy.ACTIONS.size():
			policy.press(BotPolicy.ACTIONS[i], (run[f] >> i) & 1 == 1)
		await policy.step()
	policy.release_all()
	return pieces


func _capture() -> Dictionary:
	var snap := {"pos": player.global_position, "vel": player.velocity, "vars": {}}
	for p in player.get_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and not p.name in ["visual", "light"]:
			snap.vars[p.name] = player.get(p.name)
	return snap


func _restore(snap: Dictionary) -> void:
	player.global_position = snap.pos
	for k in snap.vars:
		player.set(k, snap.vars[k])
	player.visual.visible = true
	# Settle floor contact without moving, then restore the real velocity.
	player.velocity = Vector2(0, 1)
	player.move_and_slide()
	player.global_position = snap.pos
	player.velocity = snap.vel

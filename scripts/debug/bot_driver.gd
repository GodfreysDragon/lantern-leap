class_name BotDriver
extends Node
## Plays the current level with a bot so it can be watched (debugging and
## playtesting). Started from the level select: 1 watches the speedrun, 2 the
## normal player. Data comes from res://debug/bots/<level id>.json, written by
## tools/bots.tscn.
##
## SPEEDRUN replays the recorded fastest run input for input. Hit-stop is off
## while it plays, as it was when the run was recorded.
## NORMAL plays live: it stops on the safe spot before each challenge, lines
## up, hesitates, and tries one of the challenge's known routes with
## human-sized timing errors. After a death it carries on from the checkpoint.

enum Kind { SPEEDRUN, NORMAL }

const FRAMES_PER_ATTEMPT := 900

var kind := Kind.SPEEDRUN
var _main: Node
var _data: Dictionary
var _policy: BotPolicy
var _stopped := false
var _hitstop_was := true


static func data_path(level_id: String) -> String:
	return "res://debug/bots/%s.json" % level_id


static func has_data(level_id: String) -> bool:
	return FileAccess.file_exists(data_path(level_id))


static func label(k: Kind) -> String:
	return "speedrun bot" if k == Kind.SPEEDRUN else "normal-player bot"


func _init(main: Node, k: Kind) -> void:
	_main = main
	kind = k
	name = "BotDriver"


func _ready() -> void:
	var text := FileAccess.get_file_as_string(data_path(_main.level.data.id))
	_data = JSON.parse_string(text) if not text.is_empty() else {}
	if _data.is_empty():
		push_error("No bot data for %s" % _main.level.data.id)
		return
	_policy = BotPolicy.new(_main.player, _main.level)
	_hitstop_was = Juice.hitstop_enabled
	if kind == Kind.SPEEDRUN:
		Juice.hitstop_enabled = false
	_run.call_deferred()


func _exit_tree() -> void:
	_stopped = true
	Juice.hitstop_enabled = _hitstop_was
	if _policy:
		_policy.release_all()


func _playing() -> bool:
	return not _stopped and is_instance_valid(_main.player) and _main.player == _policy.player


func _run() -> void:
	# Let the level settle under the fade-in, as the recording did.
	while _playing() and _main.mode != _main.Mode.PLAYING:
		await _policy.step()
	for i in 3:
		await _policy.step()
	if not _playing():
		return
	if kind == Kind.SPEEDRUN:
		await _policy.replay(BotPolicy.decode(_data.speedrun))
	else:
		await _play_normal()


func _play_normal() -> void:
	var segs: Array = _data.segments
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var i := 0
	while _playing() and i < segs.size():
		if _main.player.state == Player.State.DEAD or _main.mode != _main.Mode.PLAYING:
			await _policy.step()
			continue
		if not _main.player.is_on_floor():
			await _policy.step()
			continue
		var seg: Dictionary = segs[i]
		var plans: Array = _data.normal[i]
		if plans.is_empty():
			push_error("No route for %s" % seg.name)
			return
		var plan: int = plans[rng.randi_range(0, plans.size() - 1)]
		await _policy.walk_to(BotPolicy.start_x(seg, plan))
		for k in rng.randi_range(15, 45):  # a moment to size it up
			await _policy.step()
		if not _playing():
			return
		var noise := RandomNumberGenerator.new()
		noise.seed = rng.randi()
		var result: Dictionary = await _policy.attempt(seg, _data.skills, plan, FRAMES_PER_ATTEMPT, noise)
		if result.ok:
			i += 1
			continue
		# Died or fell short: wait for the respawn, then find where we are.
		var died: bool = _main.player.state == Player.State.DEAD
		while _playing() and (_main.player.state == Player.State.DEAD or _main.mode != _main.Mode.PLAYING \
				or not _main.player.is_on_floor()):
			await _policy.step()
		if not died:
			# A fall that wasn't a death leaves used crystals and crumbled
			# blocks behind; give them time to come back, as a person would.
			for k in 120 * 3:
				await _policy.step()
		i = _segment_at(segs, i)
	# Into the door.
	var door: Vector2i = _main.level.data.find(LevelData.EXIT)[0]
	await _policy.walk_to((door.x + 0.5) * BotPolicy.T)


## The challenge whose safe spot the player is standing on: the latest one at
## or before `upto` (a respawn only ever sends the player back).
func _segment_at(segs: Array, upto: int) -> int:
	var at: Vector2 = _main.player.global_position / BotPolicy.T
	for k in range(upto, -1, -1):
		var from: Array = segs[k].from
		if absf(at.y - (from[2] + 1)) < 0.2 and at.x >= from[0] - 0.5 and at.x <= from[1] + 1.5:
			return k
	# Fell somewhere between safe spots: walk back to the latest challenge
	# that starts on this floor.
	for k in range(upto, -1, -1):
		if absf(at.y - (segs[k].from[2] + 1)) < 0.2:
			return k
	return 0 if upto == 0 else _segment_nearest(segs, upto, at)


func _segment_nearest(segs: Array, upto: int, at: Vector2) -> int:
	var best := 0
	var best_d := INF
	for k in upto + 1:
		var from: Array = segs[k].from
		var d := Vector2((from[0] + from[1] + 1) * 0.5, from[2] + 1).distance_to(at)
		if d < best_d:
			best_d = d
			best = k
	return best

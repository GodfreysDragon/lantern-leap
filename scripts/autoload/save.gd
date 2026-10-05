extends Node
## Persists settings and personal bests. user:// maps to IndexedDB on the web
## export, so best times survive page reloads there too.

const PATH := "user://save.cfg"

## Tests turn this off so simulated runs never touch the real save file.
var persist := true
var muted := false
var best_times: Dictionary[String, float] = {}
var best_gems: Dictionary[String, int] = {}


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	muted = cfg.get_value("settings", "muted", false)
	for key in cfg.get_section_keys("best_times") if cfg.has_section("best_times") else PackedStringArray():
		best_times[key] = cfg.get_value("best_times", key)
	for key in cfg.get_section_keys("best_gems") if cfg.has_section("best_gems") else PackedStringArray():
		best_gems[key] = cfg.get_value("best_gems", key)


## Records a finished run of a level. Returns true if it set a new best time.
func record(level_id: String, time: float, gems: int) -> bool:
	var is_best := not best_times.has(level_id) or time < best_times[level_id]
	if is_best:
		best_times[level_id] = time
	best_gems[level_id] = maxi(best_gems.get(level_id, 0), gems)
	write()
	return is_best


func write() -> void:
	if not persist:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("settings", "muted", muted)
	for key in best_times:
		cfg.set_value("best_times", key, best_times[key])
	for key in best_gems:
		cfg.set_value("best_gems", key, best_gems[key])
	cfg.save(PATH)

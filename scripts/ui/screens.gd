class_name Screens
extends CanvasLayer
## Full-screen menus (title, pause, level clear, finale) and the fade curtain.
## Purely presentational; the game loop in main.gd decides when to show what.

var _current: Control
var _fade: ColorRect
var _blink_label: Label
var _mascot: PlayerVisual
var _was_airborne := false
var _time := 0.0


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_fade = ColorRect.new()
	_fade.color = Color(0.02, 0.01, 0.05, 1.0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)


func _process(delta: float) -> void:
	_time += delta
	if is_instance_valid(_blink_label):
		_blink_label.modulate.a = 0.55 + 0.45 * sin(_time * 4.0)
	if is_instance_valid(_mascot):
		_animate_mascot()


func fade(to_alpha: float, duration: float) -> Tween:
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", to_alpha, duration)
	return tween


func hide_screen() -> void:
	if is_instance_valid(_current):
		_current.queue_free()
	_current = null
	_blink_label = null


func show_title(best_total: float) -> void:
	var col := _open(0.0)
	# The real player sprite, scaled up, as the title mascot.
	var mascot_slot := UiKit.spacer(52)
	var holder := Node2D.new()
	holder.position = Vector2(240, 50)
	holder.scale = Vector2(2.5, 2.5)
	var mascot := PlayerVisual.new()
	holder.add_child(mascot)
	mascot_slot.add_child(holder)
	col.add_child(mascot_slot)
	_mascot = mascot
	col.add_child(UiKit.label("LANTERN LEAP", 34, UiKit.ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(UiKit.label("a tiny lantern, a long way up", 10, UiKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(UiKit.spacer(14))
	_blink_label = UiKit.label("press  JUMP  to begin", 12, UiKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(_blink_label)
	if best_total > 0.0:
		col.add_child(UiKit.label("best run  %s" % UiKit.format_time(best_total), 9,
			UiKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(UiKit.spacer(18))
	for line in [
		"move  arrows / WASD / stick      jump  space / Z / C / (A)",
		"dash  X / shift / (X)      restart  R      pause  esc      mute  M",
	]:
		col.add_child(UiKit.label(line, 8, UiKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER))


func show_pause() -> void:
	var col := _open(0.7)
	col.add_child(UiKit.label("PAUSED", 24, UiKit.ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(UiKit.spacer(10))
	col.add_child(UiKit.label("jump   resume", 10, UiKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(UiKit.label("R   restart level", 10, UiKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(UiKit.label("dash   quit to title", 10, UiKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER))


func show_level_clear(title: String, time: float, new_best: bool, gems: int,
		gem_total: int, deaths: int) -> void:
	var col := _open(0.6)
	col.add_child(UiKit.label("LEVEL CLEAR", 24, UiKit.ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(UiKit.label(title, 10, UiKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(UiKit.spacer(10))
	var time_text := "time   %s" % UiKit.format_time(time)
	if new_best:
		time_text += "   new best!"
	col.add_child(UiKit.label(time_text, 12, UiKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	if gem_total > 0:
		col.add_child(UiKit.label("gems   %d / %d" % [gems, gem_total], 12,
			Color(0.55, 1.0, 0.8), HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(UiKit.label("deaths   %d" % deaths, 12, UiKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(UiKit.spacer(16))
	_blink_label = UiKit.label("press  JUMP  to continue", 10, UiKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(_blink_label)


func show_finale(time: float, new_best: bool, gems: int, gem_total: int, deaths: int) -> void:
	var col := _open(0.75)
	col.add_child(UiKit.label("YOU REACHED THE SURFACE", 22, UiKit.ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(UiKit.label("thanks for playing", 10, UiKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(UiKit.spacer(12))
	var time_text := "total time   %s" % UiKit.format_time(time)
	if new_best:
		time_text += "   new best!"
	col.add_child(UiKit.label(time_text, 12, UiKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(UiKit.label("gems   %d / %d" % [gems, gem_total], 12,
		Color(0.55, 1.0, 0.8), HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(UiKit.label("deaths   %d" % deaths, 12, UiKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(UiKit.spacer(16))
	_blink_label = UiKit.label("press  JUMP  to return to title", 10, UiKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(_blink_label)


func _open(dim: float) -> VBoxContainer:
	hide_screen()
	_current = UiKit.screen(dim)
	add_child(_current)
	move_child(_current, 0)  # keep the fade curtain on top
	var col: VBoxContainer = _current.get_node("Column")
	col.modulate.a = 0.0
	create_tween().tween_property(col, "modulate:a", 1.0, 0.25)
	return col


## Little idle hop loop for the title mascot, reusing the in-game squash.
func _animate_mascot() -> void:
	var hop := maxf(sin(_time * 3.0), 0.0)
	_mascot.position.y = -hop * 6.0
	var airborne := hop > 0.0
	if airborne and not _was_airborne:
		_mascot.squash = Vector2(0.75, 1.3)
	elif not airborne and _was_airborne:
		_mascot.squash = Vector2(1.3, 0.75)
	_was_airborne = airborne

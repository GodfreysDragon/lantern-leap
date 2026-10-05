class_name Hud
extends CanvasLayer
## In-game overlay: level title, timer, gem and death counters, tutorial hint.

var _title: Label
var _timer: Label
var _gems: Label
var _deaths: Label
var _hint: Label
var _hint_tween: Tween


func _ready() -> void:
	layer = 10
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_title = UiKit.label("", 10, UiKit.ACCENT)
	_title.position = Vector2(8, 4)
	root.add_child(_title)

	_gems = UiKit.label("", 9, Color(0.55, 1.0, 0.8))
	_gems.position = Vector2(8, 18)
	root.add_child(_gems)

	_deaths = UiKit.label("", 9, UiKit.MUTED)
	_deaths.position = Vector2(8, 30)
	root.add_child(_deaths)

	_timer = UiKit.label("0:00.00", 10, UiKit.TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	_timer.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_timer.position = Vector2(480 - 108, 4)
	_timer.size = Vector2(100, 14)
	root.add_child(_timer)

	_hint = UiKit.label("", 10, UiKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_hint.position = Vector2(0, 238)
	_hint.size = Vector2(480, 16)
	_hint.modulate.a = 0.0
	root.add_child(_hint)


func set_level(title: String, gem_total: int) -> void:
	_title.text = title
	set_gems(0, gem_total)
	set_deaths(0)
	set_time(0.0)


func set_gems(count: int, total: int) -> void:
	_gems.visible = total > 0
	_gems.text = "gems  %d / %d" % [count, total]
	if count > 0:
		_pulse(_gems)


func set_deaths(count: int) -> void:
	_deaths.text = "deaths  %d" % count


func set_time(seconds: float) -> void:
	_timer.text = UiKit.format_time(seconds)


func show_hint(text: String) -> void:
	if text.is_empty():
		return
	_hint.text = text
	if _hint_tween:
		_hint_tween.kill()
	_hint_tween = create_tween()
	_hint_tween.tween_property(_hint, "modulate:a", 1.0, 0.4).set_delay(0.6)
	_hint_tween.tween_interval(5.0)
	_hint_tween.tween_property(_hint, "modulate:a", 0.0, 0.8)


func _pulse(label: Label) -> void:
	label.pivot_offset = Vector2(0, label.size.y * 0.5)
	var tween := create_tween()
	tween.tween_property(label, "scale", Vector2.ONE, 0.25).from(Vector2(1.4, 1.4)) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

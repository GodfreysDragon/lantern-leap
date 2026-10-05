class_name UiKit
extends RefCounted
## Small helpers for building the code-driven UI with a consistent look.

const TEXT := Color(1.0, 0.95, 0.85)
const ACCENT := Color(1.0, 0.72, 0.3)
const MUTED := Color(0.7, 0.66, 0.82)
const OUTLINE := Color(0.05, 0.03, 0.09)


static func label(text: String, size := 10, color := TEXT,
		align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	var settings := LabelSettings.new()
	settings.font_size = size
	settings.font_color = color
	settings.outline_size = maxi(2, size / 4)
	settings.outline_color = OUTLINE
	l.label_settings = settings
	return l


## A full-screen centered column, for menu-style screens.
static func screen(dim := 0.0) -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if dim > 0.0:
		var bg := ColorRect.new()
		bg.color = Color(0.02, 0.01, 0.05, dim)
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(bg)
	var column := VBoxContainer.new()
	column.name = "Column"
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 4)
	root.add_child(column)
	return root


static func spacer(height: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c


static func format_time(seconds: float) -> String:
	var minutes := int(seconds) / 60
	return "%d:%05.2f" % [minutes, seconds - minutes * 60]

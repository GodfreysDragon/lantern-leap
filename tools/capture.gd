extends Node
## Dev tool: renders the title screen and a few spots in every level to
## docs/screenshots/. Needs a window (not --headless):
##   godot --path . res://tools/capture.tscn

const OUT := "res://docs/screenshots"
const TILE := 16.0

var main: Node


func _ready() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	_capture_all.call_deferred()


func _capture_all() -> void:
	await _settle(60)
	await _shot("title")

	var levels: Array = main.LEVELS
	for i in levels.size():
		main.mode = main.Mode.PLAYING
		main.screens.hide_screen()
		main.screens.fade(0.0, 0.0)
		main._build_level(i)
		main.hud.visible = true
		var level: Level = main.level
		var spots: Array[Vector2i] = [level.data.find(LevelData.START)[0]]
		spots.append_array(level.data.find(LevelData.CHECKPOINT))
		spots.append(level.data.find(LevelData.EXIT)[0] + Vector2i(-3, 0))
		for j in spots.size():
			main.player.global_position = (Vector2(spots[j]) + Vector2(0.5, 1.0)) * TILE
			main.camera.snap_to_target()
			await _settle(40)
			await _shot("level%d_%d" % [i + 1, j + 1])
	get_tree().quit()


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("%s/%s.png" % [OUT, shot_name]))
	print("saved ", shot_name)

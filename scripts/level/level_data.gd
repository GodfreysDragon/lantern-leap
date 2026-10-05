class_name LevelData
extends RefCounted
## A level parsed from a plain-text file in res://levels/.
##
## Format: `key: value` header lines, a `---` separator, then the ASCII map.
## Keeping levels as text makes them diffable, reviewable and editable
## without the editor; see levels/README.md for the tile legend.

const SOLID := "#"
const CRUMBLE := "x"
const ONE_WAY := "-"
const SPIKE := "^"
const GEM := "o"
const SPRING := "S"
const CRYSTAL := "*"
const CHECKPOINT := "C"
const EXIT := "E"
const START := "P"

var id := ""
var name := "Untitled"
var hint := ""
var rows := PackedStringArray()
var width := 0
var height := 0


static func load_file(path: String) -> LevelData:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("Could not read level %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return null
	return parse(text, path.get_file().get_basename())


static func parse(text: String, level_id: String) -> LevelData:
	var data := LevelData.new()
	data.id = level_id
	var in_map := false
	for raw_line in text.split("\n"):
		var line := raw_line.trim_suffix("\r")
		if in_map:
			data.rows.append(line)
		elif line.strip_edges() == "---":
			in_map = true
		elif ":" in line:
			var key := line.get_slice(":", 0).strip_edges()
			var value := line.substr(line.find(":") + 1).strip_edges()
			match key:
				"name": data.name = value
				"hint": data.hint = value

	while not data.rows.is_empty() and data.rows[-1].strip_edges().is_empty():
		data.rows.remove_at(data.rows.size() - 1)

	data.height = data.rows.size()
	for row in data.rows:
		data.width = maxi(data.width, row.length())
	for i in data.rows.size():
		data.rows[i] = data.rows[i].rpad(data.width)
	return data


func cell(x: int, y: int) -> String:
	if x < 0 or y < 0 or x >= width or y >= height:
		return " "
	return rows[y][x]


## Solid for collision and auto-orientation purposes.
func is_solid(x: int, y: int) -> bool:
	var c := cell(x, y)
	return c == SOLID or c == CRUMBLE


func find(tile: String) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for y in height:
		for x in width:
			if rows[y][x] == tile:
				found.append(Vector2i(x, y))
	return found

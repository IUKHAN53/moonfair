extends Node
## Autoload: SaveData — persistent progress, currency, settings.

const PATH := "user://moonfair_save.json"

var stars: int = 0          # ★ currency
var sparks: int = 0         # ✦ currency
var best: Dictionary = {}   # game_id -> best score
var game_stars: Dictionary = {}  # game_id -> 0..3 rating
var music_on: bool = true
var sfx_on: bool = true
var last_gift: String = ""  # date of last claimed evening gift

func _ready() -> void:
	load_save()

func record_result(game_id: String, score: int, rating: int) -> void:
	if score > int(best.get(game_id, 0)):
		best[game_id] = score
	if rating > int(game_stars.get(game_id, 0)):
		game_stars[game_id] = rating
	save()

func add_currency(st: int, sp: int) -> void:
	stars += st
	sparks += sp
	save()

func gift_available() -> bool:
	return last_gift != Time.get_date_string_from_system()

func claim_gift(st: int, sp: int) -> void:
	last_gift = Time.get_date_string_from_system()
	add_currency(st, sp)

func save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"stars": stars, "sparks": sparks,
		"best": best, "game_stars": game_stars,
		"music_on": music_on, "sfx_on": sfx_on,
		"last_gift": last_gift,
	}))

func load_save() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(data) != TYPE_DICTIONARY:
		return
	stars = int(data.get("stars", 0))
	sparks = int(data.get("sparks", 0))
	best = data.get("best", {})
	game_stars = data.get("game_stars", {})
	music_on = bool(data.get("music_on", true))
	sfx_on = bool(data.get("sfx_on", true))
	last_gift = str(data.get("last_gift", ""))

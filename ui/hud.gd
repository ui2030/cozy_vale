extends CanvasLayer
# 시각/요일/계절 + 소지금 + 선택 씨앗 (GameClock·Player 구독).

@onready var _label: Label = $Label

# 기본 폰트가 한글 미지원 → 지금은 영문 표기 (한글 폰트 번들은 폴리시 단계)
const SEASON_EN := ["Spring", "Summer", "Autumn", "Winter"]
const WD_EN := ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

var _player: Node

func _ready() -> void:
	GameClock.tick.connect(func(_a, _m): _refresh())
	GameClock.day_changed.connect(func(_p, _a): _refresh())
	_player = get_tree().get_first_node_in_group("player")
	if _player != null:
		_player.stats_changed.connect(_refresh)
	_refresh()

func _refresh() -> void:
	var c := GameClock
	var line := "Y%d  %s D%d (%s)   %02d:%02d" % [
		c.year(), SEASON_EN[c.season()], c.day_of_season(),
		WD_EN[c.weekday()], c.hour(), c.minute(),
	]
	if _player != null:
		var seed_name := GameData.display_name(GameData.crop_from_seed(_player.selected_seed))
		line += "    Gold: %d    Seed: %s" % [_player.gold, seed_name]
	_label.text = line

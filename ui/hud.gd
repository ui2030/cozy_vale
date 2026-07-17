extends CanvasLayer
# 시각/요일/계절 표시 — GameClock 구독만 (DESIGN 11.2).

@onready var _label: Label = $Label

# 기본 폰트가 한글 미지원 → 지금은 영문 표기 (한글 폰트 번들은 폴리시 단계)
const SEASON_EN := ["Spring", "Summer", "Autumn", "Winter"]
const WD_EN := ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

func _ready() -> void:
	GameClock.tick.connect(_on_tick)
	GameClock.day_changed.connect(_on_day)
	_refresh()

func _on_tick(_abs_day: int, _game_min: int) -> void:
	_refresh()

func _on_day(_prev: int, _abs_day: int) -> void:
	_refresh()

func _refresh() -> void:
	var c := GameClock
	_label.text = "Y%d  %s D%d (%s)   %02d:%02d" % [
		c.year(), SEASON_EN[c.season()], c.day_of_season(),
		WD_EN[c.weekday()], c.hour(), c.minute(),
	]

extends CanvasLayer
# 시각/요일/계절 + 소지금 + 선택 씨앗 + 대화/선물 토스트.

@onready var _label: Label = $Label
@onready var _msg: Label = $MsgLabel
@onready var _msg_timer: Timer = $MsgTimer

const SEASON_EN := ["Spring", "Summer", "Autumn", "Winter"]
const WD_EN := ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

var _player: Node

func _ready() -> void:
	GameClock.tick.connect(func(_a, _m): _refresh())
	GameClock.day_changed.connect(func(_p, _a): _refresh(); _event_toast())
	_player = get_tree().get_first_node_in_group("player")
	if _player != null:
		_player.stats_changed.connect(_refresh)
		_player.message.connect(_on_message)
	_msg_timer.timeout.connect(func(): _msg.text = "")
	_msg.text = ""
	_refresh()

func _on_message(text: String) -> void:
	_msg.text = text
	_msg_timer.start(2.5)

# 기상 시 오늘 이벤트 토스트 (축제 우선, 생일 병기)
func _event_toast() -> void:
	var sid := GameData.season_id(GameClock.season())
	var day := GameClock.day_of_season()
	var parts := []
	var f := GameData.festival_on(sid, day)
	if not f.is_empty():
		parts.append(str(f["name"]) + "!")
	for nm in GameData.birthdays_on(sid, day):
		parts.append(str(nm) + " 생일")
	if not parts.is_empty():
		_on_message("오늘: " + " · ".join(parts))

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

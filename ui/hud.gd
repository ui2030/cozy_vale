extends CanvasLayer
# 시각/요일/계절 + 소지금 + 선택 씨앗 + 대화/선물 토스트.

@onready var _label: Label = $Label
@onready var _msg: Label = $MsgLabel
@onready var _msg_timer: Timer = $MsgTimer
@onready var _prompt: Label = $PromptLabel

const SEASON_EN := ["Spring", "Summer", "Autumn", "Winter"]
const WD_EN := ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

var _player: Node

# 흰 글자 + 검은 외곽선. 겨울 눈 지면(화면 ~248)·크림 하늘 위에서 순백 글자는 사라진다(실측).
# world.tscn Label3D 마을 라벨과 같은 방식·같은 비율(font 36 / outline 9 = 0.25).
const OUTLINE_PX := 6  # 폰트 22~24px 기준

# 패널 공통 배경. 기본 테마의 PanelContainer는 안쪽 여백 0 + 알파 ~0.6이라
# ① 제목이 상단 경계에 붙고 목록이 좌측 경계에서 시작하며(버튼 행만 안으로 들어가 목록이
#    패널 밖으로 삐져나온 것처럼 읽힌다) ② 배경 꽃·풀이 글자를 뚫고 올라온다(실측 audit2_0809).
# 값만 잡아 주는 헬퍼 하나로 다섯 패널이 같은 여백·같은 불투명도를 쓴다(ToonChar.make_solid 전례).
static func panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.17, 0.15, 0.19, 0.95)   # 파스텔 톤을 유지하되 글자 대비를 확보
	sb.border_color = Color(1.0, 0.94, 0.86, 0.30)  # 크림 테두리 = 밝은 지면 위에서도 패널 경계가 선다
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(18)
	return sb

func _ready() -> void:
	add_to_group("hud")  # sleep_screen 등이 토스트 호출
	for l in [_label, _msg, _prompt]:
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", OUTLINE_PX)
	GameClock.tick.connect(func(_a, _m): _refresh())
	GameClock.day_changed.connect(func(_p, _a): _refresh(); _event_toast())
	_player = get_tree().get_first_node_in_group("player")
	if _player != null:
		_player.stats_changed.connect(_refresh)
		_player.message.connect(_on_message)
	_msg_timer.timeout.connect(func(): _msg.text = "")
	_msg.text = ""
	_prompt.text = ""
	_refresh()

func _process(_delta: float) -> void:
	if _player != null:
		_prompt.text = _player.interact_prompt()

func toast(text: String) -> void:  # 공용 토스트 진입점
	_on_message(text)

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
		var sid: String = _player.active_seed()  # 계절 밖 선택은 스냅된 값으로 표시
		var seed_txt := "-" if sid == "" else "%s x%d" % [
			GameData.display_name(GameData.crop_from_seed(sid)), _player.count(sid),
		]
		line += "    Gold: %d    Seed: %s" % [_player.gold, seed_txt]
	_label.text = line

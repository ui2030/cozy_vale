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
static func panel_style() -> StyleBox:
	var tex := ui_texture()
	if tex == null:
		return _flat_style()
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.region_rect = UI_PANEL_RECT
	# 9슬라이스 여백. 좌우상은 모서리 라운딩(6px)에 여유 2px, 아래만 10 — 타일 아래쪽 4px가
	# 두께를 내는 짙은 립이라 여기를 늘리면 립이 통째로 늘어나 패널이 기울어 보인다.
	sb.texture_margin_left = 8
	sb.texture_margin_right = 8
	sb.texture_margin_top = 8
	sb.texture_margin_bottom = 10
	sb.set_content_margin_all(18)
	return sb

# 에셋 없을 때의 폴백 = 옛 판 그대로. vendor는 gitignore(재배포 금지 + 비상업 전용)라
# 클론에는 파일이 없다 — UI가 통째로 안 보이는 대신 옛 어두운 패널로 조용히 돌아간다.
static func _flat_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.17, 0.15, 0.19, 0.95)   # 파스텔 톤을 유지하되 글자 대비를 확보
	sb.border_color = Color(1.0, 0.94, 0.86, 0.30)  # 크림 테두리 = 밝은 지면 위에서도 패널 경계가 선다
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(18)
	return sb

# 패널 하나를 통째로 꾸민다 = 배경 + 글자색 + 픽셀 필터. 셋을 갈라 놓으면 배경만 크림으로
# 바꾸고 글자색을 잊는 순간 **흰 글자가 크림 위에서 사라진다** — 한 함수로 묶어 그걸 막는다.
static func style_panel(p: Control) -> void:
	p.add_theme_stylebox_override("panel", panel_style())
	if ui_texture() == null:
		return
	# 픽셀아트는 선형 보간하면 뭉개진다. 자식까지 상속된다(CanvasItem 규약).
	p.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# 배경이 크림이 됐으니 글자는 어두워야 한다. Theme로 걸어 자식 라벨·버튼이 전부 상속받는다
	# = 패널마다 라벨을 찾아다니며 색을 칠하지 않는다.
	var th := Theme.new()
	for cls in ["Label", "Button", "RichTextLabel"]:
		th.set_color("font_color", cls, PANEL_FG)
	for st in ["font_hover_color", "font_pressed_color", "font_focus_color"]:
		th.set_color(st, "Button", PANEL_FG)
	th.set_color("font_disabled_color", "Button", PANEL_FG_HI)
	th.set_color("default_color", "RichTextLabel", PANEL_FG)
	# 버튼도 같이 갈아야 한다 — 배경만 크림으로 바꾸면 기본 테마의 **어두운 회색 버튼**이
	# 그대로 남아 목록 행이 크림 패널 위에 검은 띠로 박힌다(실측 ui2b/ui_inventory 1차).
	# 상태별 색은 만들지 않고 시트의 다른 타일을 쓴다 = 팔레트를 발명하지 않는다.
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		th.set_stylebox(st, "Button", _btn_style(st))
	p.theme = th

# 버튼 상태별 타일. 밝을수록 위(hover), 어두울수록 눌림 — 시트 안에서 같은 계열 3단이 있다.
static func _btn_style(state: String) -> StyleBox:
	var rect := UI_BTN_RECT                       # (220,185,138) 탄 — 크림 패널보다 한 단 아래
	if state == "hover" or state == "focus":
		rect = UI_PANEL_RECT                      # (232,207,166) 밝아짐
	elif state == "pressed":
		rect = UI_BTN_DOWN_RECT                   # (196,154,108) 눌림
	var sb := StyleBoxTexture.new()
	sb.texture = ui_texture()
	sb.region_rect = rect
	sb.texture_margin_left = 8
	sb.texture_margin_right = 8
	sb.texture_margin_top = 8
	sb.texture_margin_bottom = 10
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 4
	sb.content_margin_bottom = 6
	if state == "disabled":
		sb.modulate_color = Color(1, 1, 1, 0.55)  # 표시 전용 행 = 같은 타일을 옅게
	return sb

# 킷 UI 시트(비상업 평가용, gitignore). 원본 픽셀 좌표는 알파 경계 실측이다 —
# 크림 패널 타일 (11,57) 26×30. 같은 시트에 버튼·아이콘도 있어 나중에 여기서 잘라 쓴다.
const UI_SHEET := "res://assets/vendor/Sprout Lands - UI Pack - Basic pack/Sprite sheets/Sprite sheet for Basic Pack.png"
const UI_PANEL_RECT := Rect2(11, 57, 26, 30)
const UI_BTN_RECT := Rect2(11, 105, 26, 30)       # 한 단 진한 탄 = 목록 행
const UI_BTN_DOWN_RECT := Rect2(107, 105, 26, 30) # 더 진한 탄 = 눌린 상태
# 크림 패널(232,207,166) 위 글자. 마을 목재 진갈색 계열이라 UI가 세계와 같은 팔레트를 쓴다.
const PANEL_FG := Color(0.286, 0.204, 0.157)
const PANEL_FG_HI := Color(0.478, 0.325, 0.220)

# 강조색·달력 칸 배경은 **어느 패널이 켜졌는지에 따라 갈린다**. 옛 금색(1.0,0.85,0.35)은
# 어두운 패널 전제였다 — 크림 위에 얹으면 대비가 사라져 "선택됨"이 안 읽힌다(실측).
# 폴백 경로에선 옛 값을 글자 그대로 돌려준다 = 에셋 없는 클론의 화면은 무변경.
static func accent_color() -> Color:
	return Color(0.62, 0.26, 0.15) if ui_texture() != null else Color(1.0, 0.85, 0.35)

static func cell_bg(is_today: bool) -> Color:
	if ui_texture() == null:
		return Color(1.0, 0.85, 0.35, 0.55) if is_today else Color(1.0, 1.0, 1.0, 0.06)
	return Color(0.62, 0.26, 0.15, 0.45) if is_today else Color(0.29, 0.20, 0.16, 0.10)

static var _ui_tex: Texture2D = null
static var _ui_tried := false

# 임포트 리소스가 아니라 런타임 로드다(vendor는 *.import도 gitignore). 실패는 조용히 null —
# 호출부가 폴백을 갖고 있으므로 에셋이 없다고 게임이 멈추면 안 된다.
static func ui_texture() -> Texture2D:
	if not _ui_tried:
		_ui_tried = true
		if FileAccess.file_exists(UI_SHEET):
			var img := Image.new()
			if img.load_png_from_buffer(FileAccess.get_file_as_bytes(UI_SHEET)) == OK:
				_ui_tex = ImageTexture.create_from_image(img)
	return _ui_tex

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

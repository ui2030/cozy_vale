extends Control
# 달력 패널 (C키 토글). 현재 계절 그리드 + 생일·축제·오늘 표시.
# 이벤트 데이터는 GameData(생일=npcs.json, 축제=calendar.json) 단일 출처 조회.

const Hud := preload("res://ui/hud.gd")  # 패널 배경 단일 출처(여백·불투명도)

# 칸 크기. 높이는 **3줄이 들어가야 한다** — 축제와 생일이 같은 날 겹치는 날이 실제로 있고
# (겨울 D10 = 등불 축제 + 생일), 그 칸의 글자가 62px라 옛 52로는 담기지 않았다. Label은
# 자동 줄바꿈도 잘라내기도 꺼져 있어서 넘쳐도 안 잘린다 — PanelContainer가 그냥 커지고
# 그 주 한 줄만 키가 달라졌다(실측 collection/cal_w). 66 = 62 + 여유 4.
# 폭 78은 그대로다(가장 긴 칸 글자가 69px). test_core가 네 계절 전수로 두 값을 다 문다.
const CELL := Vector2(78, 66)

# 오늘 강조·빈 칸 배경도, 계절·요일 표기도 hud.gd 단일 출처.

var _title: Label
var _grid: GridContainer

func _ready() -> void:
	add_to_group("calendar_panel")  # 일시정지 메뉴가 열릴 때 닫도록
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(340, 90)
	Hud.style_panel(panel)
	add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 22)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_title)
	# 요일 헤더
	var header := GridContainer.new()
	header.columns = 7
	header.add_theme_constant_override("h_separation", 4)
	for wd in Hud.WD_KO:
		var l := Label.new()
		l.text = wd
		l.custom_minimum_size = Vector2(CELL.x, 0)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		header.add_child(l)
	vb.add_child(header)
	_grid = GridContainer.new()
	_grid.columns = 7
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 4)
	vb.add_child(_grid)
	# 계절/일이 바뀌면 열려 있을 때만 갱신
	GameClock.day_changed.connect(func(_p, _a): if visible: _rebuild())
	GameClock.season_changed.connect(func(_p, _s): if visible: _rebuild())

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("calendar"):
		visible = not visible
		Sfx.play("ui_open" if visible else "ui_close")
		if visible:
			_rebuild()
		get_viewport().set_input_as_handled()

func _rebuild() -> void:
	var sidx := GameClock.season()
	var sid := GameData.season_id(sidx)
	var today := GameClock.day_of_season()
	_title.text = Hud.date_ko(GameClock.year(), sidx, 0)
	for c in _grid.get_children():
		c.queue_free()
	# 계절 길이가 7의 배수가 아니면 계절마다 1일의 요일이 달라진다 → 앞쪽 빈칸으로 요일 열을 맞춘다.
	# 1일차의 abs_day = 오늘 abs_day - (오늘 일차 - 1), 요일 = 그 값 % 7 (0=월).
	for _i in (GameClock.abs_day - today + 1) % 7:
		var blank := Control.new()
		blank.custom_minimum_size = CELL
		_grid.add_child(blank)
	for day in range(1, GameClock.DAYS_PER_SEASON + 1):
		_grid.add_child(_make_cell(sid, day, day == today))

func _make_cell(sid: String, day: int, is_today: bool) -> Control:
	var box := PanelContainer.new()
	box.custom_minimum_size = CELL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Hud.cell_bg(is_today)
	box.add_theme_stylebox_override("panel", sb)
	var lbl := Label.new()
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var txt := str(day)
	var f := GameData.festival_on(sid, day)
	if not f.is_empty():
		txt += "\n* " + str(f["name"])
	for nm in GameData.birthdays_on(sid, day):
		txt += "\n" + str(nm) + " 생일"
	lbl.text = txt
	box.add_child(lbl)
	return box

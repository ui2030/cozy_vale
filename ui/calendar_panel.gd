extends Control
# 달력 패널 (C키 토글). 현재 계절 그리드 + 생일·축제·오늘 표시.
# 이벤트 데이터는 GameData(생일=npcs.json, 축제=calendar.json) 단일 출처 조회.

const Hud := preload("res://ui/hud.gd")  # 패널 배경 단일 출처(여백·불투명도)

const WD_EN := ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
const SEASON_EN := ["Spring", "Summer", "Autumn", "Winter"]
# 오늘 강조·빈 칸 배경은 패널 배경에 따라 갈린다 — hud.gd 단일 출처.

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
	for wd in WD_EN:
		var l := Label.new()
		l.text = wd
		l.custom_minimum_size = Vector2(78, 0)
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
	_title.text = "%s  (Y%d)" % [SEASON_EN[sidx], GameClock.year()]
	for c in _grid.get_children():
		c.queue_free()
	# 계절 길이가 7의 배수가 아니면 계절마다 1일의 요일이 달라진다 → 앞쪽 빈칸으로 요일 열을 맞춘다.
	# 1일차의 abs_day = 오늘 abs_day - (오늘 일차 - 1), 요일 = 그 값 % 7 (0=월).
	for _i in (GameClock.abs_day - today + 1) % 7:
		var blank := Control.new()
		blank.custom_minimum_size = Vector2(78, 52)
		_grid.add_child(blank)
	for day in range(1, GameClock.DAYS_PER_SEASON + 1):
		_grid.add_child(_make_cell(sid, day, day == today))

func _make_cell(sid: String, day: int, is_today: bool) -> Control:
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(78, 52)
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

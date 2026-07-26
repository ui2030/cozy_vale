extends Control
# 달력 패널 (C키 토글). 현재 계절 28일 그리드 + 생일·축제·오늘 표시.
# 이벤트 데이터는 GameData(생일=npcs.json, 축제=calendar.json) 단일 출처 조회.

const WD_EN := ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
const SEASON_EN := ["Spring", "Summer", "Autumn", "Winter"]
const TODAY_BG := Color(1.0, 0.85, 0.35, 0.55)
const CELL_BG := Color(1.0, 1.0, 1.0, 0.06)

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
	for day in range(1, GameClock.DAYS_PER_SEASON + 1):
		_grid.add_child(_make_cell(sid, day, day == today))

func _make_cell(sid: String, day: int, is_today: bool) -> Control:
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(78, 52)
	var sb := StyleBoxFlat.new()
	sb.bg_color = TODAY_BG if is_today else CELL_BG
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

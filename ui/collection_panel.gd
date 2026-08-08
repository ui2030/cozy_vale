extends Control
# 도감 패널 (B키 토글). 카테고리별(작물/물고기/채집물) 전체 슬롯 — 발견=이름, 미발견="???".
# 발견 현황은 player.collection 단일 출처 조회. 낚시 중엔 열지 않음.

const Hud := preload("res://ui/hud.gd")  # 패널 배경 단일 출처(여백·불투명도)

var _list: VBoxContainer

func _ready() -> void:
	add_to_group("collection_panel")
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(360, 100)
	panel.add_theme_stylebox_override("panel", Hud.panel_style())
	add_child(panel)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	_list.custom_minimum_size = Vector2(360, 0)
	panel.add_child(_list)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("collection"):
		var fg := get_tree().get_first_node_in_group("fishing")
		if fg != null and fg.is_active():  # 낚시 중엔 무시
			return
		visible = not visible
		Sfx.play("ui_open" if visible else "ui_close")
		if visible:
			_rebuild()
		get_viewport().set_input_as_handled()

func _rebuild() -> void:
	for c in _list.get_children():
		c.queue_free()
	var p := get_tree().get_first_node_in_group("player")
	var col: Array = p.collection if p != null else []
	var title := Label.new()
	title.text = "도감"
	title.add_theme_font_size_override("font_size", 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_list.add_child(title)
	_section("작물", GameData.crops, col)
	_section("물고기", GameData.fish, col)
	_section("채집물", GameData.forage, col)

func _section(title: String, source: Dictionary, col: Array) -> void:
	var found := 0
	for id in source:
		if id in col:
			found += 1
	var head := Label.new()
	head.add_theme_font_size_override("font_size", 18)
	head.text = "%s  (%d/%d)" % [title, found, source.size()]
	_list.add_child(head)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 4)
	for id in source:
		var cell := Label.new()
		cell.add_theme_font_size_override("font_size", 15)
		cell.custom_minimum_size = Vector2(110, 26)
		cell.text = GameData.display_name(id) if id in col else "???"
		grid.add_child(cell)
	_list.add_child(grid)

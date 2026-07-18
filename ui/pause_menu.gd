extends Control
# 일시정지 메뉴 (ESC 토글). 열림=GameClock PAUSED, 닫힘=이전 상태 복원.
# 조작키 화면은 InputMap을 실제로 읽어 표시 (하드코딩 금지, 리바인딩 넣어도 무변경).
# 버튼 focus 네이티브 네비게이션으로 마우스+키보드(위아래/Enter) 둘 다 동작.

enum View { MAIN, CONTROLS, CONFIRM }

var _views := {}
var _prev_state := GameClock.State.NORMAL

func _ready() -> void:
	add_to_group("pause_menu")
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cc)
	_views[View.MAIN] = _build_main()
	_views[View.CONTROLS] = _build_controls()
	_views[View.CONFIRM] = _build_confirm()
	for v in _views.values():
		cc.add_child(v)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_menu"):
		if visible:
			close_menu()
		else:
			open_menu()
		get_viewport().set_input_as_handled()

func open_menu() -> void:
	_prev_state = GameClock.state
	GameClock.state = GameClock.State.PAUSED
	var cal := get_tree().get_first_node_in_group("calendar_panel")
	if cal != null:
		cal.visible = false
	visible = true
	_show(View.MAIN)

func close_menu() -> void:
	GameClock.state = _prev_state
	visible = false

func _show(view: int) -> void:
	for v in _views:
		_views[v].visible = (v == view)
	var btns: Array = _views[view].find_children("", "Button", true, false)  # owned=false: 코드 생성 노드
	if not btns.is_empty():
		btns[0].grab_focus()

# ── 뷰 빌드 ────────────────────────────────────────────────────
func _panel(title: String) -> Array:  # [PanelContainer, VBoxContainer]
	var p := PanelContainer.new()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	vb.custom_minimum_size = Vector2(320, 0)
	p.add_child(vb)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 24)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	return [p, vb]

func _btn(vb: VBoxContainer, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	vb.add_child(b)

func _build_main() -> Control:
	var r := _panel("일시정지")
	_btn(r[1], "계속하기", close_menu)
	_btn(r[1], "조작키", func(): _show(View.CONTROLS))
	_btn(r[1], "게임 종료", func(): _show(View.CONFIRM))
	return r[0]

func _build_controls() -> Control:
	var r := _panel("조작키")
	for action in InputSetup.ACTION_LABELS:
		if not InputMap.has_action(action):
			continue
		var row := Label.new()
		row.add_theme_font_size_override("font_size", 16)
		row.text = "%s   —   %s" % [InputSetup.ACTION_LABELS[action], _keys_for(action)]
		r[1].add_child(row)
	_btn(r[1], "뒤로", func(): _show(View.MAIN))
	return r[0]

func _build_confirm() -> Control:
	var r := _panel("게임 종료")
	var msg := Label.new()
	msg.text = "저장은 취침 시에만 됩니다.\n종료할까요?"
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	r[1].add_child(msg)
	_btn(r[1], "예", func(): get_tree().quit())
	_btn(r[1], "아니오", func(): _show(View.MAIN))
	return r[0]

func _keys_for(action: String) -> String:
	var parts := []
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			var kc: int = e.physical_keycode if e.physical_keycode != 0 else e.keycode
			parts.append(OS.get_keycode_string(kc))
	return ", ".join(parts)

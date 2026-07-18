extends Control
# 취침 확인 + 페이드 연출. 침대 E → 확인 다이얼로그 → 페이드아웃 → sleep+저장 → 페이드인 → 토스트.
# 확인창 열린 동안 GameClock PAUSED (pause_menu와 동일 _prev_state 패턴).

const SEASON_EN := ["Spring", "Summer", "Autumn", "Winter"]

var _fade: ColorRect
var _confirm: Control
var _prev_state := GameClock.State.NORMAL
var _busy := false

func _ready() -> void:
	add_to_group("sleep_screen")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)
	_confirm = _build_confirm()
	_confirm.visible = false
	add_child(_confirm)

func is_active() -> bool:  # 확인창 열림 or 페이드 진행 중 (pause_menu 상호배제용)
	return _busy or _confirm.visible

func request_sleep() -> void:
	if is_active():
		return
	_prev_state = GameClock.state
	GameClock.state = GameClock.State.PAUSED
	_confirm.visible = true
	var btns: Array = _confirm.find_children("", "Button", true, false)
	if not btns.is_empty():
		btns[0].grab_focus()

func _on_no() -> void:
	_confirm.visible = false
	GameClock.state = _prev_state

func _on_yes() -> void:
	_confirm.visible = false
	_busy = true
	var t1 := create_tween()
	t1.tween_property(_fade, "color:a", 1.0, 0.5)
	await t1.finished
	GameClock.sleep_to_morning()       # day_changed 구독자(농사) 정산
	SaveManager.request_save("sleep")  # 큐잉 저장
	var t2 := create_tween()
	t2.tween_property(_fade, "color:a", 0.0, 0.5)
	await t2.finished
	GameClock.state = _prev_state
	_busy = false
	_toast("%s D%d 아침이 밝았어요" % [SEASON_EN[GameClock.season()], GameClock.day_of_season()])

func _toast(text: String) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("toast"):
		hud.toast(text)

func _build_confirm() -> Control:
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var p := PanelContainer.new()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	vb.custom_minimum_size = Vector2(300, 0)
	p.add_child(vb)
	var msg := Label.new()
	msg.text = "오늘 하루를 마칠까요?"
	msg.add_theme_font_size_override("font_size", 22)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(msg)
	_btn(vb, "예", _on_yes)
	_btn(vb, "아니오", _on_no)
	cc.add_child(p)
	return cc

func _btn(vb: VBoxContainer, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	vb.add_child(b)

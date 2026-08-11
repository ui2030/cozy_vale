extends Control
# 요리 패널 (부엌 스토브 E로 열림, E/ESC로 닫힘). 레시피 8종 전부 나열 —
# 만들 수 있는 것은 활성 + 강조, 재료가 모자란 것은 비활성 행에 "재료 보유/필요"를 그대로 보여준다
# (무엇이 모자란지 패널을 나가지 않고 알 수 있게). 가방 패널 관례를 그대로 따른다.

const Hud := preload("res://ui/hud.gd")  # 패널 배경 단일 출처(여백·불투명도)

# "지금 할 수 있는 것" 강조 = 가방 패널과 같은 색(hud.gd 단일 출처).

var _list: VBoxContainer

func _ready() -> void:
	add_to_group("cooking_panel")
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(300, 100)
	Hud.style_panel(panel)
	add_child(panel)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	_list.custom_minimum_size = Vector2(560, 0)
	panel.add_child(_list)
	var p := get_tree().get_first_node_in_group("player")
	if p != null:  # 요리 직후 재료 수량·가능 여부가 그 자리에서 갱신된다
		p.stats_changed.connect(func(): if visible: _rebuild())

func open() -> void:
	visible = true
	Sfx.play("ui_open")
	_rebuild()

# 열려 있을 때만 입력을 먹는다 — 닫힌 패널이 ESC(일시정지)나 E(상호작용)를 가로채면 안 된다.
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("pause_menu"):
		visible = false
		Sfx.play("ui_close")
		get_viewport().set_input_as_handled()

func _rebuild() -> void:
	for c in _list.get_children():  # 가방 패널과 같은 이유: 먼저 떼고 지운다(옛 행 겹침 방지)
		_list.remove_child(c)
		c.queue_free()
	var p := get_tree().get_first_node_in_group("player")
	if p == null:
		return
	var title := Label.new()
	title.text = "요리"
	title.add_theme_font_size_override("font_size", 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_list.add_child(title)
	var head := Label.new()
	head.add_theme_font_size_override("font_size", 18)
	head.text = "클릭 = 요리 (E/ESC = 닫기)"
	_list.add_child(head)
	for rid in GameData.recipes:
		_list.add_child(_recipe_btn(p, rid))

func _recipe_btn(p: Node, rid: String) -> Button:
	var r: Dictionary = GameData.recipes[rid]
	var parts := []
	for iid in r["ingredients"]:
		parts.append("%s %d/%d" % [GameData.display_name(iid), p.count(iid), int(r["ingredients"][iid])])
	var b := Button.new()
	b.text = "%s   %dG   %s" % [GameData.display_name(rid), int(r["sell_price"]), " · ".join(parts)]
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 16)
	var ok: bool = p.can_cook(rid)
	b.disabled = not ok
	if ok:
		b.add_theme_color_override("font_color", Hud.accent_color())
	b.pressed.connect(func(): p.cook(rid))  # stats_changed → 이 패널 재빌드
	return b

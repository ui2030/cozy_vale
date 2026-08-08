extends Control
# 가방 패널 (I키 토글). 소지금 + 보유 아이템 + 씨앗 선택(클릭). 낚시 중엔 열지 않음.
# player.gold/inventory/selected_seed 단일 출처 조회 — 표시만 하고 세이브 표면 무변경.
# 씨앗 목록은 all_seed_ids 전부(보유 0 포함): Q 순환과 같은 집합이라 상점 구매 대상도 고를 수 있다.

const Hud := preload("res://ui/hud.gd")  # 패널 배경 단일 출처(여백·불투명도)

const SEL_COLOR := Color(1.0, 0.85, 0.35)

var _list: VBoxContainer

func _ready() -> void:
	add_to_group("inventory_panel")
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(360, 100)
	panel.add_theme_stylebox_override("panel", Hud.panel_style())
	add_child(panel)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	_list.custom_minimum_size = Vector2(340, 0)
	panel.add_child(_list)
	var p := get_tree().get_first_node_in_group("player")
	if p != null:  # 열려 있는 동안 수확·판매·씨앗변경 반영 (닫혀 있으면 열 때 어차피 다시 그림)
		p.stats_changed.connect(func(): if visible: _rebuild())
	# 계절이 바뀌면 씨앗 목록(= 이번 계절 재고 ∪ 보유)이 통째로 달라진다
	GameClock.day_changed.connect(func(_p, _a): if visible: _rebuild())

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory"):
		var fg := get_tree().get_first_node_in_group("fishing")
		if fg != null and fg.is_active():  # 낚시 중엔 무시
			return
		visible = not visible
		Sfx.play("ui_open" if visible else "ui_close")
		if visible:
			_rebuild()
		get_viewport().set_input_as_handled()

func _rebuild() -> void:
	# 한 프레임에 stats_changed가 여러 번 올 수 있다(판매상자 일괄 정산 = 아이템당 1회) —
	# queue_free만 하면 아직 자식으로 남아 옛 행과 새 행이 겹친다. 먼저 떼어내고 지운다.
	# (free가 아니라 queue_free인 이유: 클릭한 버튼이 자기 pressed 디스패치 중에 사라지면 안 됨)
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var p := get_tree().get_first_node_in_group("player")
	if p == null:
		return
	var title := Label.new()
	title.text = "가방"
	title.add_theme_font_size_override("font_size", 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_list.add_child(title)
	var gold := Label.new()
	gold.add_theme_font_size_override("font_size", 18)
	gold.text = "Gold: %d" % p.gold
	_list.add_child(gold)
	_head("씨앗 (클릭 = 선택, Q = 순환)")
	var seeds: Array = p.cycle_seeds()
	if seeds.is_empty():  # 겨울 + 보유 0 = 고를 씨앗 없음 (빈 목록을 그대로 두지 않는다)
		var none := Label.new()
		none.add_theme_font_size_override("font_size", 16)
		none.text = "  (이번 계절엔 씨앗이 없어요)"
		_list.add_child(none)
	for sid in seeds:
		_list.add_child(_seed_btn(p, sid))
	_head("특별")  # 반지가 씨앗 목록 마지막 줄로 읽히던 것(실측 audit2_0809/inventory)을 제 섹션으로
	_list.add_child(_ring_btn(p))
	_head("소지품")
	var any := false
	for e in p.inventory:
		if not GameData.is_produce(e["id"]):  # 씨앗은 위 섹션에서 이미 표시
			continue
		any = true
		var row := Label.new()
		row.add_theme_font_size_override("font_size", 16)
		row.text = "%s   x%d" % [GameData.display_name(e["id"]), int(e["qty"])]
		_list.add_child(row)
	if not any:
		var empty := Label.new()
		empty.add_theme_font_size_override("font_size", 16)
		empty.text = "(비어 있음)"
		_list.add_child(empty)

# 프러포즈 아이템 행. 미보유면 구매 버튼(상점 앞에서만 성사 — player.buy_ring이 판정),
# 보유면 소지 표시. 씨앗 목록과 분리해 Q 순환 집합을 오염시키지 않는다.
func _ring_btn(p: Node) -> Button:
	var b := Button.new()
	var owned: bool = p.count(GameData.RING_ID) > 0
	b.text = "  %s   %s" % [
		GameData.RING_NAME,
		"x1 (후보에게 G = 청혼)" if owned else "%dG — 상점에서 구매" % GameData.RING_COST,
	]
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 16)
	b.disabled = owned  # 보유 중 = 표시 전용 행
	b.pressed.connect(func(): p.buy_ring())
	return b

func _head(text: String) -> void:
	var h := Label.new()
	h.add_theme_font_size_override("font_size", 18)
	h.text = text
	_list.add_child(h)

# 씨앗 ID는 display_name 소스(작물·물고기·채집물)에 없다 — 작물 이름으로 되짚어 표기.
func _seed_btn(p: Node, sid: String) -> Button:
	var b := Button.new()
	var sel: bool = sid == p.active_seed()
	b.text = "%s %s Seed   x%d" % [
		"▶" if sel else "  ", GameData.display_name(GameData.crop_from_seed(sid)), p.count(sid),
	]
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 16)
	if sel:
		b.add_theme_color_override("font_color", SEL_COLOR)
	b.pressed.connect(func(): p.select_seed(sid))  # stats_changed → 이 패널 재빌드
	return b

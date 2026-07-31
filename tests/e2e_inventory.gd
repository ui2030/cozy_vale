extends Node
# E2E: I키 가방 패널 토글 + 씨앗 클릭 선택 (world 인스턴스 + 입력 시뮬).
# 헤드리스: godot --headless res://tests/e2e_inventory.tscn
# 주의: parse_input_event는 다음 프레임 flush라 await 여유를 둔다. 유저 세이브는 셸에서 백업/복원.

func _ready() -> void:
	add_child(preload("res://world/world.tscn").instantiate())
	_run.call_deferred()

func _run() -> void:
	await get_tree().process_frame
	var panel: Node = get_tree().get_first_node_in_group("inventory_panel")
	assert(panel != null, "가방 패널 존재")
	assert(not panel.visible, "초기 닫힘")
	_press(KEY_I)
	await get_tree().process_frame
	await get_tree().process_frame
	assert(panel.visible, "I → 열림")
	# 씨앗 버튼 클릭 = selected_seed 교체 (Q 순환과 같은 집합)
	var player: Node = get_tree().get_first_node_in_group("player")
	var seeds: Array = player.cycle_seeds()  # 패널 목록 = Q 순환 집합(이번 계절 재고 ∪ 보유)
	assert(seeds.size() >= 2, "봄 시작 = 고를 씨앗 2종 이상 (실제 %d)" % seeds.size())
	var other: String = seeds[1] if seeds[0] == player.active_seed() else seeds[0]
	var btns: Array = panel.find_children("", "Button", true, false)  # owned=false: 코드 생성 노드
	assert(btns.size() == seeds.size() + 1, "씨앗 %d + 반지 1 버튼 (실제 %d)" % [seeds.size(), btns.size()])
	btns[seeds.find(other)].pressed.emit()  # 반지 행은 씨앗 뒤에 붙어 인덱스 불변
	await get_tree().process_frame
	assert(player.selected_seed == other, "클릭 → 씨앗 교체: %s" % player.selected_seed)
	_press(KEY_I)
	await get_tree().process_frame
	await get_tree().process_frame
	assert(not panel.visible, "I 재입력 → 닫힘")
	print("E2E INVENTORY PASS")
	get_tree().quit()

func _press(kc: int) -> void:
	var down := InputEventKey.new()
	down.physical_keycode = kc
	down.pressed = true
	Input.parse_input_event(down)
	var up := InputEventKey.new()
	up.physical_keycode = kc
	up.pressed = false
	Input.parse_input_event(up)

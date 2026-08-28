extends Node
# E2E: I키 가방 패널 토글 + 씨앗 클릭 선택 + 목록 패널이 화면 안에 드는지 (world 인스턴스 + 입력 시뮬).
# 헤드리스: godot --headless res://tests/e2e_inventory.tscn
# 주의: parse_input_event는 다음 프레임 flush라 await 여유를 둔다.

func _ready() -> void:
	# 소지품을 채워 재는 구간이 있다 — 유저 세이브 쓰기를 아예 막는다(모든 쓰기의 공통 관문).
	SaveManager.suspended = true
	# 헤드리스 더미 디스플레이는 창을 64px로 연다. 패널 위치는 중앙 앵커 기준이라 **패널이 만들어지기
	# 전에** 릴리즈 화면(1280×720)으로 되돌려야 배치가 실제 게임과 같아진다.
	get_window().size = Vector2i(1280, 720)
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

	# ── 목록 패널이 화면 밖으로 자라던 것 ────────────────────────────
	# 도감은 채집물 6행 중 4행만, 요리는 14종 중 13종만 보이고 나머지가 화면 아래로 잘려 나갔다
	# (실측 lookdev/shots/ui/before_collection·before_cooking). 항목은 앞으로도 느니 스크롤이
	# 빠지는 순간 재발한다. 720은 project.godot 뷰포트 높이 = 릴리즈 화면 값을 그대로 박은 것이다.
	# 프로덕션 상수에서 파생시키지 않는다 — 파생 문턱은 상수가 되돌아가면 같이 움직여 안 문다(e1c0540).
	var view_h: float = get_viewport().get_visible_rect().size.y
	assert(view_h == 720.0, "뷰포트 높이 720 전제가 깨짐(%.0f) — 아래 문턱이 무의미해진다" % view_h)
	_press(KEY_B)  # 도감 = 프로덕션 진입점(키 입력 → _unhandled_input → _rebuild)
	await get_tree().process_frame
	await get_tree().process_frame
	var col: Node = get_tree().get_first_node_in_group("collection_panel")
	assert(col.visible, "B → 도감 열림")
	_assert_fits(col, "도감")
	var cook: Node = get_tree().get_first_node_in_group("cooking_panel")
	cook.open()  # 스토브 상호작용이 부르는 그 함수
	await get_tree().process_frame
	await get_tree().process_frame
	_assert_fits(cook, "요리")
	# 가방은 지금 담긴 양으론 안 넘치지만, 산출물을 두루 들고 다니면 넘친다 — 채워서 잰다.
	for iid in GameData.forage:
		player._add_item(iid, 1)
	for iid in GameData.fish:
		player._add_item(iid, 1)
	panel.visible = true
	panel._rebuild()
	await get_tree().process_frame
	await get_tree().process_frame
	_assert_fits(panel, "가방")

	print("E2E INVENTORY PASS")
	get_tree().quit()

# 패널 상자를 **실측**한다. 목록 원래 높이가 화면 몫(뷰포트 720 − 상단 100 − 여백)보다 길어야
# 이 핀이 무언가를 재는 것이고, 그 상태에서 ① 패널 바닥이 화면 안 ② 패널이 목록보다 짧다
# (= 스크롤이 실제로 눌러 주고 있다) 둘 다여야 통과.
func _assert_fits(panel: Node, label: String) -> void:
	var box: Control = panel.find_children("", "PanelContainer", true, false)[0]
	var content: float = panel._list.get_combined_minimum_size().y
	assert(content > 560.0, "%s 목록이 560보다 짧다(%.0f) — 이 핀이 아무것도 안 잰다" % [label, content])
	var bottom: float = box.position.y + box.size.y
	assert(bottom <= 720.0, "%s 패널이 화면 밖으로 자람: 바닥 %.0f (목록 %.0f)" % [label, bottom, content])
	assert(box.size.y < content, "%s 목록이 안 눌렸다 — 스크롤이 빠졌다 (패널 %.0f, 목록 %.0f)" % [label, box.size.y, content])
	# 위 두 줄만으론 "높이를 아예 안 잡아 패널이 0으로 접힌" 경우도 통과한다(실측: fit_scroll 호출을
	# 빼도 안 물었다). 목록이 화면보다 길면 패널은 화면을 거의 다 써야 한다 — 하한도 박는다.
	assert(box.size.y >= 500.0, "%s 목록이 긴데 패널이 %.0f뿐 — 스크롤 높이가 안 잡혔다" % [label, box.size.y])

func _press(kc: int) -> void:
	var down := InputEventKey.new()
	down.physical_keycode = kc
	down.pressed = true
	Input.parse_input_event(down)
	var up := InputEventKey.new()
	up.physical_keycode = kc
	up.pressed = false
	Input.parse_input_event(up)

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
	await _assert_icons(col, player)
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

	# ── 창 크기를 바꿔도 배치가 안 무너지던가 ────────────────────────
	# 패널 넷은 1280×720 절대좌표다(중앙 앵커 + 고정 offset). 스트레치가 빠지면 2D 좌표계가
	# 창 크기를 그대로 따라가 배치가 통째로 어긋난다 — 헤드리스 64px 창에서 패널 상단이
	# 100이 아니라 428로 잡히던 그 증상. 문턱은 전부 절대 숫자다(프로덕션 상수에서 파생시키면
	# 그 상수가 0이 될 때 문턱도 0이 되어 조용히 통과한다).
	for w in [Vector2i(1920, 1080), Vector2i(1024, 768), Vector2i(800, 600)]:
		get_window().size = w
		await get_tree().process_frame
		await get_tree().process_frame
		var vr: Vector2 = get_viewport().get_visible_rect().size
		assert(vr == Vector2(1280.0, 720.0),
			"창 %dx%d에서 2D 좌표계가 1280x720이 아님(%.0fx%.0f) — UI 절대좌표가 통째로 어긋난다"
				% [w.x, w.y, vr.x, vr.y])
		for row in [[col, "도감"], [cook, "요리"], [panel, "가방"]]:
			var pn: Node = row[0]
			pn.visible = true
			pn._rebuild()  # 창을 줄인 뒤 패널을 여는 경로 = 프로덕션이 매번 부르는 그 함수
			await get_tree().process_frame
			_assert_fits(pn, "%s @%dx%d" % [row[1], w.x, w.y])
	get_window().size = Vector2i(1280, 720)

	print("E2E INVENTORY PASS")
	get_tree().quit()

# ── 도감 아이콘 ────────────────────────────────────────────────────
# 도감이 글자만 나열하던 것을 고쳤다 — 밭·풀숲에 서 있는 **그 실물 메시**를 작은 SubViewport에
# 그려 아이콘으로 쓴다. 아이콘이 조용히 빠져도 패널은 멀쩡해 보이므로 **개수를 세서** 문다.
# 문턱은 전부 절대 숫자다: 프로덕션 상수(ICON_PX·항목 수)에서 유도하면 그쪽이 0이 되는 순간
# 문턱도 같이 0이 되어 조용히 통과한다(e1c0540에서 겪은 그 구멍).
func _assert_icons(col: Node, player: Node) -> void:
	# 세이브가 실려 있어도 여기서 상태를 확정한다 — 진도의 단일 출처가 이 배열이다.
	player.collection = []
	col._rebuild()
	await get_tree().process_frame
	var cells: int = col._list.find_children("", "HBoxContainer", true, false).size()
	# 목록 안에서만 센다 — ScrollContainer 자체가 내부용 TextureRect 둘을 달고 있다(실측).
	var icons: Array = col._list.find_children("", "TextureRect", true, false)
	assert(cells == 47, "도감 슬롯 47칸(작물 12 + 물고기 19 + 채집물 16) — 실제 %d칸" % cells)
	assert(icons.size() == 28,
		"아이콘 28장(작물 12 + 채집물 16)이어야 한다 — 실제 %d장. 나머지 19칸(물고기)은 실물 메시가 없어 글자만 둔다"
			% icons.size())
	for ic in icons:
		assert(ic.texture != null, "아이콘 자리는 만들었는데 텍스처가 비었다")
		assert(ic.custom_minimum_size == Vector2(44.0, 44.0),
			"아이콘이 행 높이(44)와 안 맞는다: %s" % str(ic.custom_minimum_size))
	# 렌더는 항목당 한 번. 패널을 다시 열 때마다 SubViewport를 새로 돌리면 여기서 걸린다.
	var vps: int = col.find_children("", "SubViewport", true, false).size()
	assert(vps == 28, "아이콘 렌더 28개 — 실제 %d개" % vps)
	col._rebuild()
	col._rebuild()
	assert(col.find_children("", "SubViewport", true, false).size() == 28,
		"패널을 다시 열 때마다 아이콘을 새로 렌더한다 — 캐시가 안 걸렸다 (%d개로 늘었다)"
			% col.find_children("", "SubViewport", true, false).size())
	var fid: String = GameData.forage.keys()[0]
	assert(is_same(col._icon(fid), col._icon(fid)), "%s — 같은 항목의 아이콘을 두 번 만든다" % fid)
	# 미발견은 실루엣, 발견은 제 색. modulate 값을 실제로 세서 갈리는지 본다.
	assert(_icon_tone(col) == [0, 28],
		"아무것도 안 모은 도감은 28장 전부 실루엣이어야 한다 — 실제 [제 색, 실루엣] = %s"
			% str(_icon_tone(col)))
	for iid in GameData.forage:  # 채집물 16종만 모은 상태 = 화면에서 반은 색, 반은 실루엣
		player._add_item(iid, 1)
	col._rebuild()
	await get_tree().process_frame
	assert(_icon_tone(col) == [16, 12],
		"채집물 16종만 모았으면 제 색 16 · 실루엣 12여야 한다 — 실제 %s" % str(_icon_tone(col)))

# 아이콘 [제 색 수, 실루엣 수]. 둘 중 어느 쪽도 아니면 합이 안 맞아 위 단언이 문다.
func _icon_tone(col: Node) -> Array:
	var lit := 0
	var dark := 0
	for ic in col._list.find_children("", "TextureRect", true, false):
		var m: Color = ic.modulate
		if m.r > 0.9 and m.g > 0.9 and m.b > 0.9 and m.a > 0.9:
			lit += 1
		elif m.r < 0.15 and m.g < 0.15 and m.b < 0.15 and m.a > 0.4:
			dark += 1
	return [lit, dark]

# 패널 상자를 **실측**한다. 목록 원래 높이가 화면 몫(뷰포트 720 − 상단 100 − 여백)보다 길어야
# 이 핀이 무언가를 재는 것이고, 그 상태에서 ① 패널 바닥이 화면 안 ② 패널이 목록보다 짧다
# (= 스크롤이 실제로 눌러 주고 있다) 둘 다여야 통과.
func _assert_fits(panel: Node, label: String) -> void:
	var box: Control = panel.find_children("", "PanelContainer", true, false)[0]
	var content: float = panel._list.get_combined_minimum_size().y
	assert(content > 560.0, "%s 목록이 560보다 짧다(%.0f) — 이 핀이 아무것도 안 잰다" % [label, content])
	var bottom: float = box.position.y + box.size.y
	assert(bottom <= 720.0, "%s 패널이 화면 밖으로 자람: 바닥 %.0f (목록 %.0f)" % [label, bottom, content])
	# 세로만 재면 창을 좁혔을 때 좌우로 삐져나가는 것을 못 잡는다(요리 패널 폭 596, x=300).
	var right: float = box.position.x + box.size.x
	assert(box.position.x >= 0.0 and right <= 1280.0 and box.position.y >= 0.0,
		"%s 패널이 화면 밖: 좌 %.0f 우 %.0f 상 %.0f" % [label, box.position.x, right, box.position.y])
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

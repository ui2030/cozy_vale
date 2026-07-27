extends Node
# E2E: 연못 물가 → E → 낚시 미니게임 열림 검증 (world 인스턴스 + 입력 시뮬).
# 헤드리스: godot --headless res://tests/e2e_fishing.tscn
# 유저 세이브는 셸에서 백업/복원.

func _ready() -> void:
	add_child(preload("res://world/world.tscn").instantiate())
	_run.call_deferred()

func _run() -> void:
	await get_tree().process_frame
	var player: Node = get_tree().get_first_node_in_group("player")
	assert(player != null, "player 존재")
	player.global_position = Vector3(10, 1.0, 3.8)  # 연못(10,0,0) 물가
	for i in 12:  # Area 겹침 등록 대기
		await get_tree().physics_frame
	assert(player.interact_prompt() == "E: 낚시", "낚시 프롬프트: '%s'" % player.interact_prompt())
	_press(KEY_E)
	await get_tree().process_frame
	await get_tree().process_frame
	var fg: Node = get_tree().get_first_node_in_group("fishing")
	assert(fg != null, "fishing 노드 존재")
	assert(fg.is_active(), "E → 낚시 미니게임 열림")
	# 연못 트리거엔 spot 메타가 없다 = pond 기본값 → 바다 어종이 섞이지 않는다(H단계 회귀)
	var area: Area3D = player.interact_target()["area"]
	assert(not area.has_meta("spot"), "연못은 spot 메타 없음(기본 pond)")
	assert(String(GameData.fish[fg._fish_id].get("spot", GameData.SPOT_POND)) == GameData.SPOT_POND,
		"연못에서 바다 어종 나옴: %s" % fg._fish_id)
	print("E2E FISHING PASS")
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

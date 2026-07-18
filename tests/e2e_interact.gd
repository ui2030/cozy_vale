extends Node
# E2E: 침대 상호작용 → 확인 '예' → 취침 경로 실동작 검증 (world 인스턴스 + 입력 시뮬).
# 헤드리스: godot --headless res://tests/e2e_interact.tscn
# 주의: parse_input_event는 다음 프레임 flush라 await 여유를 둔다. 유저 세이브는 셸에서 백업/복원.

func _ready() -> void:
	add_child(preload("res://world/world.tscn").instantiate())  # world._ready: 세이브 로드
	_run.call_deferred()

func _run() -> void:
	await get_tree().process_frame
	var player: Node = get_tree().get_first_node_in_group("player")
	assert(player != null, "player 존재")
	player.global_position = Vector3(3.6, 1.0, 0)  # 침대 옆으로 텔레포트
	for i in 12:  # Area 겹침 등록 대기
		await get_tree().physics_frame
	var before: int = GameClock.abs_day
	assert(player.interact_prompt() == "E: 취침", "취침 프롬프트: '%s'" % player.interact_prompt())
	# E 입력 시뮬 → 확인 다이얼로그
	_press(KEY_E)
	await get_tree().process_frame
	await get_tree().process_frame
	assert(GameClock.state == GameClock.State.PAUSED, "확인창 열림 = PAUSED")
	# 확인창 '예' 경로 (포커스된 첫 버튼) → 페이드 + 취침 + 저장
	var ss: Node = get_tree().get_first_node_in_group("sleep_screen")
	var btns: Array = ss.find_children("", "Button", true, false)
	assert(not btns.is_empty(), "확인 버튼 존재")
	btns[0].pressed.emit()  # '예'
	await get_tree().create_timer(1.6).timeout  # 페이드 0.5+0.5 + 여유
	assert(GameClock.abs_day == before + 1, "취침 → abs_day +1 (before=%d now=%d)" % [before, GameClock.abs_day])
	assert(GameClock.state == GameClock.State.NORMAL, "취침 후 상태 복원")
	print("E2E INTERACT PASS")
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

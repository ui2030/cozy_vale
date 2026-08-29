extends Node
# E2E: 침대 상호작용 → 확인 '예' → 취침 경로 실동작 검증 (world 인스턴스 + 입력 시뮬).
# 헤드리스: godot --headless res://tests/e2e_interact.tscn
# 주의: parse_input_event는 다음 프레임 flush라 await 여유를 둔다. 유저 세이브는 셸에서 백업/복원.

func _ready() -> void:
	SaveManager.suspended = true  # 취침 경로를 태우므로 유저 세이브 쓰기를 원천 차단
	add_child(preload("res://world/world.tscn").instantiate())  # world._ready: 세이브 로드
	_run.call_deferred()

func _run() -> void:
	await get_tree().process_frame
	var player: Node = get_tree().get_first_node_in_group("player")
	assert(player != null, "player 존재")
	await _check_deck_lift(player)
	_check_wild_seed_pickup(player)
	player.global_position = Vector3(119.4, 1.0, 118.2)  # 실내 침대 옆 (G단계: 침대가 실내로 이전)
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

# 늦가을 야생 씨앗 줍기 = **실플레이어 경로**. test_core는 stub_player라 _pick_forage를 못 태운다
# — 씨앗이 화면에 돋아도 주울 수 없으면 첫해 겨울 밭은 여전히 성립하지 않으므로 여기서 문다.
# 값을 직접 센다: 소지 수량, 도감에 안 들어감, 그 자리 노드가 실제로 사라짐.
func _check_wild_seed_pickup(player: Node) -> void:
	var fs: Node = get_tree().get_first_node_in_group("forage_system")
	assert(fs != null, "forage_system 존재")
	var wild: Array = GameData.wild_seed_ids()
	assert(wild.size() == 4, "야생 씨앗 4종 (실제 %d)" % wild.size())
	GameClock.abs_day = 3 * GameClock.DAYS_PER_SEASON - 6  # Y1 가을 D25 = 늦가을 창 첫날
	assert(GameClock.year() == 1 and GameClock.day_of_season() == 25, "전제: Y1 가을 D25")
	fs._respawn()
	var picked := 0
	var last := ""
	var roots_before: int = fs._roots.size()
	for r in fs._roots.duplicate():
		for c in (r as Node).get_children():
			if c is Area3D and c.is_in_group("forage"):
				var fid := String(c.get_meta("forage_id", ""))
				if fid in wild:
					var had: int = player.count(fid)
					player._pick_forage(c)  # 프롬프트 E가 부르는 그 함수
					assert(player.count(fid) == had + 1, "%s 줍기가 소지품에 안 들어감" % fid)
					assert(not fid in player.collection, "%s 씨앗이 도감에 등록됐다" % fid)
					picked += 1
					last = fid
	assert(picked == 2, "늦가을 D25에 주울 수 있는 씨앗이 %d개 — 자리 2곳은 반드시 돋는다" % picked)
	assert(fs._roots.size() == roots_before - picked, "주운 씨앗 노드가 안 사라졌다")
	assert(last in player.cycle_seeds(), "주운 씨앗 %s가 Q 순환에 안 뜬다 = 심을 수가 없다" % last)

# 다리 위 플레이어 시각 리프트 = world.gd deck_top 곡선과 동일해야 한다.
# (test_core는 stub_player라 실제 플레이어 노드가 없다 — 실물 검증은 여기서만 가능)
func _check_deck_lift(player: Node) -> void:
	const W := preload("res://world/world.gd")
	var br: Vector2 = W.BRIDGES[0]
	var ang: float = W._river_dir_at(br)
	var axis := Vector2(cos(ang), -sin(ang))  # 다리 로컬 +X(강 횡단)의 월드 방향
	assert(player._visual != null, "플레이어 비주얼(GLB) 로드됨")
	for dx in [0.0, 1.5, 3.0, 8.0]:
		var q: Vector2 = br + axis * dx
		player.global_position = Vector3(q.x, 1.0, q.y)
		for _i in 2:  # physics_frame은 _physics_process **앞**에서 발신된다 — 한 프레임 여유
			await get_tree().physics_frame
		var lift: float = player._visual.position.y - player.visual_y
		assert(absf(lift - W.deck_top(dx)) < 0.001,
			"다리 x=%.1f 플레이어 리프트 %.3f ≠ 데크 상면 %.3f" % [dx, lift, W.deck_top(dx)])
	# 몸통은 물리가 잡고 있다 = 리프트가 몸통 y를 건드리지 않는다(카메라 튐·중력 싸움 방지)
	player.global_position = Vector3(br.x, 1.0, br.y)
	for _i in 2:
		await get_tree().physics_frame
	assert(player.global_position.y < W.DECK_CROWN, "리프트는 비주얼만 — 몸통은 지면 높이 유지")

func _press(kc: int) -> void:
	var down := InputEventKey.new()
	down.physical_keycode = kc
	down.pressed = true
	Input.parse_input_event(down)
	var up := InputEventKey.new()
	up.physical_keycode = kc
	up.pressed = false
	Input.parse_input_event(up)

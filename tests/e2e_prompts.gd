extends Node
# E2E: 마을 P1 재배치 후 침대/상점/판매상자/연못/NPC 상호작용 프롬프트가 실거리에서 발생하는지.
# 헤드리스: godot --headless res://tests/e2e_prompts.tscn  (유저 세이브는 셸에서 백업/복원)

func _ready() -> void:
	add_child(preload("res://world/world.tscn").instantiate())
	_run.call_deferred()

func _run() -> void:
	await get_tree().process_frame
	var player: Node = get_tree().get_first_node_in_group("player")
	assert(player != null, "player 존재")
	GameClock.game_min = 1320  # 밤 = NPC 집에서 정지 (배회 흔들림 제거)
	var cases := [
		[Vector3(119.4, 1.0, 118.2), "E: 취침"],  # 실내 침대(ORIGIN-3,-3.43) 남동 — G단계에서 실내 이전
		[Vector3(-5, 1.0, -3.4), "E: 상점"],      # 상점 트리거(-5,-5) 전면 (불변)
		[Vector3(5.0, 1.0, 4.3), "E: 판매 상자"], # 밭 옆 판매상자(5.0,5.8) (불변)
		[Vector3(10, 1.0, 3.8), "E: 낚시"],       # 연못(10,0) 물가 (불변)
	]
	for c in cases:
		player.global_position = c[0]
		for i in 12:
			await get_tree().physics_frame
		var got: String = player.interact_prompt()
		assert(got == c[1], "%s 기대 '%s' 실제 '%s'" % [str(c[0]), c[1], got])
		print("  OK ", c[1])
	# NPC 대화: mira 집(-20,-9) 옆 (다른 프롬프트 간섭 없는 곳).
	# G단계부터 밤엔 집에 있는 주민이 숨는다(귀가 연출) → 낮으로 옮기되 PAUSED로 배회를 얼리고
	# 위치를 명시 배치해 결정성을 유지한다(기존 "밤=정지" 트릭의 대체).
	GameClock.game_min = 12 * 60
	GameClock.state = GameClock.State.PAUSED
	var npcsys: Node = get_tree().get_first_node_in_group("npc_system")
	npcsys.npc_nodes["npc.mira"].position = Vector3(-20, 0, -9)
	player.global_position = Vector3(-20, 1.0, -7.8)
	for i in 12:
		await get_tree().physics_frame
	var p: String = player.interact_prompt()
	assert(p.begins_with("E: 대화"), "NPC 대화 프롬프트 실제 '%s'" % p)
	print("  OK ", p)
	# 통행 계약(S자 곡류): 다리 없는 세그먼트는 막고, 다리 3곳은 가로지르는 레이가 통과.
	var ss: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	# 차단: z=-3 세그먼트(강선 x≈19, 근처 다리 없음) 동→서 레이
	var q_wall := PhysicsRayQueryParameters3D.create(Vector3(30, 1, -3), Vector3(8, 1, -3))
	assert(not ss.intersect_ray(q_wall).is_empty(), "강 벽이 통행 차단(z=-3, 다리 밖)")
	print("  OK 강 통행 차단(다리 밖)")
	# 통과: 다리 3곳(북동/동/남서) 중심을 가로지르는 짧은 레이는 비어야 함(벽 gap)
	var bridges := [
		["북동 다리", Vector3(18.25, 1, -17.58), Vector3(27.75, 1, -14.42)],
		["동 다리",   Vector3(12.1, 1, 6.02),    Vector3(21.9, 1, 7.98)],
		["남서 다리", Vector3(-5.53, 1, 25.63),  Vector3(-1.47, 1, 34.77)],
	]
	for b in bridges:
		var q := PhysicsRayQueryParameters3D.create(b[1], b[2])
		assert(ss.intersect_ray(q).is_empty(), "%s 통과(벽 gap)" % b[0])
		print("  OK %s 통과" % b[0])
	# 풍차 언덕 램프 도보 등반: 램프 아래에서 북(-z)으로 밀어 대지(top=2.5)에 오르는지.
	player.set_physics_process(false)  # Input 덮어쓰기 차단, 직접 구동
	player.global_position = Vector3(29, 1.0, -14.5)  # 램프 남단(29,-24 대지 남쪽)
	player.velocity = Vector3.ZERO
	for i in 120:
		player.velocity.y -= player.gravity * (1.0 / 60.0)
		player.velocity.x = 0.0
		player.velocity.z = -4.0  # 북쪽(대지 방향)
		player.move_and_slide()
		await get_tree().physics_frame
	assert(player.global_position.y > 1.5, "램프 등반 → 대지 위(y=%.2f)" % player.global_position.y)
	print("  OK 풍차 언덕 등반 (y=%.2f)" % player.global_position.y)
	print("E2E PROMPTS PASS")
	get_tree().quit()

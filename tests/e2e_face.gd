extends Node
# E2E: 대화 시 NPC가 말 건 플레이어 쪽으로 도는지 검증 (전 주민 공통).
# 헤드리스: godot --headless res://tests/e2e_face.tscn
# 배회를 얼려(_shot_frozen) NPC·플레이어를 개방 위치에 놓고 talk 경로(E키)를 태운 뒤
# NPC 루트의 전방(-Z, look_at 규약)이 플레이어 방향을 향하는지 확인.

func _ready() -> void:
	add_child(preload("res://world/world.tscn").instantiate())
	_run.call_deferred()

func _run() -> void:
	await get_tree().process_frame
	var npcsys: Node = get_tree().get_first_node_in_group("npc_system")
	var player: Node3D = get_tree().get_first_node_in_group("player")
	assert(npcsys != null and player != null, "npc_system + player 존재")
	npcsys._shot_frozen = true  # 배회 정지 (yaw 덮어쓰기 차단)

	var id: String = npcsys.npc_nodes.keys()[0]
	var npc: Node3D = npcsys.npc_nodes[id]
	npc.position = Vector3(0, 0, -5)
	npc.rotation.y = 0.0                       # 초기: 플레이어를 안 봄
	player.global_position = Vector3(1.2, 1.0, -5)  # NPC 기준 +X
	var dir := (player.global_position - npc.global_position)
	dir.y = 0.0; dir = dir.normalized()        # 기대 방향 ≈ (1,0,0)

	# talk() 은 E키 상호작용이 최종적으로 부르는 함수 — 직접 호출해 _face_player 검증.
	var fwd_before := (npc.global_transform.basis * Vector3(0, 0, -1))
	assert(fwd_before.normalized().dot(dir) < 0.9, "초기엔 플레이어를 안 봄")
	npcsys.talk(id)                            # → _face_player() 트윈 시작
	for _j in 30:                              # 트윈 0.25s 완료 대기 (~0.5s)
		await get_tree().process_frame
	var fwd_after := (npc.global_transform.basis * Vector3(0, 0, -1))
	fwd_after.y = 0.0; fwd_after = fwd_after.normalized()
	var d := fwd_after.dot(dir)
	assert(d > 0.9, "NPC 전방이 플레이어를 향함 (dot=%.3f, fwd=%s dir=%s)" % [d, fwd_after, dir])

	# give() 도 같은 경로인지 확인: 다른 방향에서 접근 → 그쪽으로 돎
	player.global_position = Vector3(0.0, 1.0, -1.5)  # NPC 기준 +Z
	var dir2 := (player.global_position - npc.global_position); dir2.y = 0.0; dir2 = dir2.normalized()
	npcsys.give(id, "crop.turnip")
	for _k in 30:
		await get_tree().process_frame
	var fwd2 := (npc.global_transform.basis * Vector3(0, 0, -1)); fwd2.y = 0.0; fwd2 = fwd2.normalized()
	assert(fwd2.dot(dir2) > 0.9, "give 후에도 플레이어를 향함 (dot=%.3f)" % fwd2.dot(dir2))
	print("E2E FACE PASS  talk_dot=%.3f give_dot=%.3f" % [d, fwd2.dot(dir2)])
	get_tree().quit()

func _press(kc: int) -> void:
	var down := InputEventKey.new(); down.physical_keycode = kc; down.pressed = true
	Input.parse_input_event(down)
	var up := InputEventKey.new(); up.physical_keycode = kc; up.pressed = false
	Input.parse_input_event(up)

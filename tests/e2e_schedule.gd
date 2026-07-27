extends Node
# E2E: NPC 하루 스케줄 이동 — 실제 _wander_step 루프로 걸어가서 도착하는지,
# 도중에 건물 keep-out·강물(다리 밖)을 관통하지 않는지 검증.
# 헤드리스: godot --headless res://tests/e2e_schedule.tscn
# 클록은 PAUSED로 얼려 npc_system._process 자동 스텝을 막고 수동 스텝만 돌린다.

const N := preload("res://npc/npc_system.gd")

func _ready() -> void:
	add_child(preload("res://world/world.tscn").instantiate())
	_run.call_deferred()

func _run() -> void:
	await get_tree().process_frame
	var npcsys: Node = get_tree().get_first_node_in_group("npc_system")
	assert(npcsys != null, "npc_system 존재")
	GameClock.state = GameClock.State.PAUSED

	# 같은 편 이동: mira 집(9시) → 광장(10시)
	var s1 := _walk(npcsys, "npc.mira", 9, 10, N.ANCHORS["plaza"])
	# 강 건너 이동: milo 광장(11시) → 풍차(14시) — 다리 데크 경유 강제
	var s2 := _walk(npcsys, "npc.milo", 11, 14, N.ANCHORS["windmill"])
	assert(s2["deck_lift"], "강 건너는 동안 다리 데크 높이로 들림")
	print("E2E SCHEDULE PASS  mira->plaza %d스텝, milo->windmill %d스텝(deck)" % [s1["steps"], s2["steps"]])
	get_tree().quit()

# from_h에 스냅 후 to_h로 점프, 도착까지 수동 스텝. 매 스텝 관통 불변식 검사.
func _walk(npcsys: Node, id: String, from_h: int, to_h: int, goal: Vector2) -> Dictionary:
	GameClock.game_min = from_h * 60
	npcsys.snap_to_schedule()
	GameClock.game_min = to_h * 60
	var node: Node3D = npcsys.npc_nodes[id]
	var deck_lift := false
	for i in 6000:
		npcsys._wander_step(id, 0.1)
		npcsys._wander[id]["wait"] = 0.0  # 대기 생략 (도착 판정만 관심)
		var p := Vector2(node.position.x, node.position.z)
		assert(not N._inside_block(p) or node.position.y > 0.3,
			"%s 건물/장애물 관통 (%s)" % [id, p])
		if N._river_dist(p) < 1.4:  # 물폭3 안 = 다리 위여야 함
			assert(N._near_bridge(p, N.DECK_HALF + 0.6), "%s 다리 밖 도하 (%s)" % [id, p])
			assert(node.position.y > 0.3, "%s 발이 물에 잠김 (%s)" % [id, p])
			deck_lift = true
		if p.distance_to(goal) <= N.ANCHOR_R_MAX + 0.1:
			return {"steps": i, "deck_lift": deck_lift}
	assert(false, "%s 6000스텝 안에 %s 미도착 (현재 %s)" % [id, goal, node.position])
	return {}

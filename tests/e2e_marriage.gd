extends Node
# E2E: 데이트 2회 → 청혼 → 3일 뒤 결혼식 → 익일 아침 부부 일상 (DESIGN 6.5 F단계).
# 헤드리스: godot --headless res://tests/e2e_marriage.tscn
# 클록은 PAUSED로 얼려 자동 tick을 막고, NPC 이동만 _wander_step 수동 루프로 돈다
# (e2e_schedule과 같은 기법). _wed()·_finish_date()가 큐잉하는 저장은 즉시 취소해
# 유저 세이브를 건드리지 않는다.

const N := preload("res://npc/npc_system.gd")
const ID := "npc.mira"

var _npcsys: Node
var _player: Node

func _ready() -> void:
	add_child(preload("res://world/world.tscn").instantiate())  # world._ready: 세이브 로드
	_run.call_deferred()

func _run() -> void:
	await get_tree().process_frame
	_npcsys = get_tree().get_first_node_in_group("npc_system")
	_player = get_tree().get_first_node_in_group("player")
	assert(_npcsys != null and _player != null, "world 로드")
	GameClock.state = GameClock.State.PAUSED
	GameClock.abs_day = 0     # spring D1 = 축제 아님
	GameClock.game_min = 12 * 60
	_npcsys.spouse = ""
	_npcsys.engaged = {}
	_npcsys._date = {}
	_npcsys.state[ID]["dates_seen"] = 0

	# ── 1. 데이트 1 (♥9 → 연못)
	_npcsys.state[ID]["affection_points"] = 9 * N.HEART
	_player.global_position = Vector3(0, 1.0, 20)  # 데이트 장소에서 멀리 = 아직 성사 안 됨
	_npcsys.state[ID]["talked_today"] = false
	var invite := String(_npcsys.talk(ID)["msg"])
	assert("연못" in invite, "데이트 1 제안(연못): %s" % invite)
	assert(_npcsys._date.get("place", "") == "pond", "데이트 상태 = 연못")
	var d1 := _walk_until(N.ANCHORS["pond"], 4000)
	assert(int(d1["steps"]) >= 0, "배우자 후보가 연못 미도착")
	assert(int(_npcsys.state[ID]["dates_seen"]) == 0, "플레이어가 안 왔으면 미성사(앵커에서 대기)")
	_arrive(N.ANCHORS["pond"])
	assert(int(_npcsys.state[ID]["dates_seen"]) == 1, "플레이어 도착 → 데이트 1 완주")
	assert(_npcsys._date.is_empty(), "완주 후 스케줄 오버라이드 해제")

	# ── 2. 데이트 2 (♥10 → 풍차 언덕, 강 건너 = 다리 경유)
	_npcsys.state[ID]["affection_points"] = N.MAX_AFF
	_npcsys.state[ID]["talked_today"] = false
	_player.global_position = Vector3(0, 1.0, 20)
	var invite2 := String(_npcsys.talk(ID)["msg"])
	assert("풍차" in invite2, "데이트 2 제안(풍차 언덕): %s" % invite2)
	var d2 := _walk_until(N.ANCHORS["windmill"], 6000)
	assert(int(d2["steps"]) >= 0, "후보가 풍차 언덕 미도착")
	assert(bool(d2["deck"]), "강 건너 데이트 = 다리 데크 경유")
	_arrive(N.ANCHORS["windmill"])
	assert(int(_npcsys.state[ID]["dates_seen"]) == 2, "데이트 2 완주")

	# ── 3. 청혼: 반지 소지 + 후보 옆에서 실제 선물키 경로(_give)
	_player._add_item(GameData.RING_ID, 1)
	_player.global_position = _npcsys.npc_nodes[ID].global_position + Vector3(1.0, 1.0, 0)
	for _i in 12:  # Area3D 겹침 등록 대기
		await get_tree().physics_frame
	_player._give()
	assert(_player.count(GameData.RING_ID) == 0, "청혼 수락 → 반지 소모")
	assert(_npcsys.engaged.get("id", "") == ID, "약혼 성립: %s" % str(_npcsys.engaged))
	assert(_npcsys.spouse == "", "약혼 단계에선 아직 미혼")
	var wd := int(_npcsys.engaged["wedding_abs_day"])
	assert(wd == N.ENGAGE_DAYS, "결혼식 = 청혼 %d일 뒤 (wd=%d)" % [N.ENGAGE_DAYS, wd])

	# ── 4. 3일 스킵 → 결혼식 아침 09시: 주민 광장 집합 + 배우자 마주보기
	GameClock.abs_day = wd
	GameClock.game_min = N.WEDDING_HOUR * 60
	_player.global_position = Vector3(0, 1.0, -1.5)  # 광장 집합 지점(0,-6) 남쪽
	_player._face_dir(Vector3(0, 0, -1))             # 광장을 향해 섬
	_npcsys._check_wedding()
	SaveManager.set_process(false)  # _wed()가 큐잉한 저장 취소 (유저 세이브 보호)
	assert(_npcsys.spouse == ID, "결혼 성립")
	assert(_npcsys.engaged.is_empty(), "약혼 상태 해제")
	assert(_npcsys._festival_active, "결혼식 = 주민 광장 집합")
	var gathered := 0
	for nid in _npcsys.npc_nodes:
		var p3: Vector3 = _npcsys.npc_nodes[nid].position
		if Vector2(p3.x, p3.z).distance_to(_npcsys.WEDDING_PLAZA) < N.FEST_RING + 0.5:
			gathered += 1
	assert(gathered >= GameData.npcs.size() - 1, "주민 광장 링 집합 (%d명)" % gathered)
	var node: Node3D = _npcsys.npc_nodes[ID]
	var ppos: Vector3 = _player.global_position
	var dist := Vector2(node.position.x, node.position.z).distance_to(Vector2(ppos.x, ppos.z))
	assert(dist < 2.2, "배우자가 플레이어 앞에 섬 (거리 %.2f)" % dist)
	await get_tree().create_timer(0.4).timeout  # _face_player 트윈(0.25s) 완료 대기
	var to_p := ppos - node.global_position
	to_p.y = 0.0
	var fwd: Vector3 = -node.global_transform.basis.z
	fwd.y = 0.0
	var dot := fwd.normalized().dot(to_p.normalized())
	assert(dot > 0.9, "배우자가 플레이어를 마주봄 (dot %.2f)" % dot)

	# ── 5. 익일 아침 06시: 집합 해제 + 배우자 = 플레이어 집 앞
	GameClock.abs_day = wd + 1
	GameClock.game_min = GameClock.WAKE_MIN
	_npcsys._check_wedding()  # 절대분 판정 → 자정 넘겨도 집합 해제 + snap_to_schedule
	assert(not _npcsys._festival_active, "결혼식 집합 종료")
	var goal: Vector2 = N.ANCHORS["player_home"]
	var snap := Vector2(node.position.x, node.position.z)
	assert(snap.distance_to(goal) <= N.ANCHOR_R_MAX + 0.01, "아침 로드 배치 = 플레이어 집 앞 (%s)" % snap)
	# 걸어서 가는 경로도 검증: 자기 집에서 출발 (관통·도하 불변식 유지)
	var home: Array = GameData.npcs[ID]["home"]
	node.position = Vector3(home[0], 0, home[1])
	_npcsys._wander[ID]["place"] = "home"
	_npcsys._wander[ID]["path"] = []
	_npcsys._wander[ID]["target"] = node.position
	GameClock.game_min = 8 * 60  # 배회 시간창(DAY_START) 안에서 걷게
	var w := _walk_until(goal, 6000)
	assert(int(w["steps"]) >= 0, "배우자가 플레이어 집 앞 미도착 (현재 %s)" % node.position)

	# ── 6. 하루 첫 대화 = 부부 아침 인사 + 하트 표기
	_npcsys.state[ID]["talked_today"] = false
	var msg := String(_npcsys.talk(ID)["msg"])
	var married := false
	for line in GameData.dialogues[String(GameData.npcs[ID]["archetype"])]["married"]:
		if String(line) in msg:
			married = true
	assert(married, "부부 아침 인사 대사: %s" % msg)
	assert("♥" in msg, "토스트 하트 표기: %s" % msg)

	# ── 7. 낮은 원래 자기 스케줄 유지 (mira 13시 = 상점)
	GameClock.game_min = 13 * 60
	_npcsys.snap_to_schedule()
	var mp: Vector3 = node.position
	assert(Vector2(mp.x, mp.z).distance_to(N.ANCHORS["shop"]) <= N.ANCHOR_R_MAX + 0.01,
		"낮 13시 = 원래 스케줄(상점) (%s)" % mp)

	SaveManager.set_process(false)  # 종료 전 저장 큐 재확인
	print("E2E MARRIAGE PASS  데이트1 %d스텝 / 데이트2 %d스텝(다리) / 집합 %d명 / 집앞 %d스텝" % [
		int(d1["steps"]), int(d2["steps"]), gathered, int(w["steps"])])
	get_tree().quit()

# 목표 앵커 반경까지 수동 스텝. 매 스텝 관통·도하 불변식 + 데이트 판정을 함께 돌린다.
func _walk_until(goal: Vector2, max_steps: int) -> Dictionary:
	var node: Node3D = _npcsys.npc_nodes[ID]
	var deck := false
	for i in max_steps:
		_npcsys._wander_step(ID, 0.1)
		_npcsys._wander[ID]["wait"] = 0.0  # 대기 생략(도착 판정만 관심)
		_npcsys._check_date()
		var p := Vector2(node.position.x, node.position.z)
		assert(not N._inside_block(p) or node.position.y > 0.3, "%s 건물/장애물 관통 (%s)" % [ID, p])
		if N._river_dist(p) < 1.4:  # 물폭3 안 = 다리 위여야 함
			assert(N._near_bridge(p, N.DECK_HALF + 0.6), "%s 다리 밖 도하 (%s)" % [ID, p])
			assert(node.position.y > 0.3, "%s 발이 물에 잠김 (%s)" % [ID, p])
			deck = true
		if p.distance_to(goal) <= N.ANCHOR_R_MAX + 0.1:
			return {"steps": i, "deck": deck}
	return {"steps": -1, "deck": deck}

# 플레이어가 데이트 장소에 도착 → 성사 판정
func _arrive(anchor: Vector2) -> void:
	_player.global_position = Vector3(anchor.x, 1.0, anchor.y)
	_npcsys._check_date()
	SaveManager.set_process(false)  # _finish_date가 큐잉한 저장 취소

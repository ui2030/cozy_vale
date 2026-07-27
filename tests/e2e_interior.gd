extends Node
# E2E: 플레이어 집 실내 (G단계) — 문 왕복 + 실내 취침 + 배우자 실내 배치 + NPC 밤 귀가.
# 헤드리스: godot --headless res://tests/e2e_interior.tscn
# 유저 세이브 보호: SaveManager.suspended (set_process(false)만으로는 취침이 다시 켠다).

const N := preload("res://npc/npc_system.gd")
const I := preload("res://world/interior.gd")
const ID := "npc.mira"

var _player: Node3D
var _npcsys: Node

func _ready() -> void:
	SaveManager.suspended = true  # world._ready(로드) 전에 — 이 테스트는 취침까지 태운다
	add_child(preload("res://world/world.tscn").instantiate())
	_run.call_deferred()

func _run() -> void:
	await get_tree().process_frame
	_player = get_tree().get_first_node_in_group("player") as Node3D
	_npcsys = get_tree().get_first_node_in_group("npc_system")
	assert(_player != null and _npcsys != null, "world 로드")
	GameClock.state = GameClock.State.PAUSED
	GameClock.abs_day = 0        # spring D1 = 축제 아님
	GameClock.game_min = 12 * 60
	_npcsys.spouse = ""          # 유저 세이브의 결혼 상태와 무관하게 시작
	_npcsys.engaged = {}
	_npcsys.snap_to_schedule()

	# ── 1. 집 앞 → 실내
	await _stand(I.OUT_DOOR + Vector3(0, 0, 1.1))  # 문 트리거 남쪽(집 정면 쪽)
	assert(_player.interact_prompt() == "E: 들어가기", "집 앞 문 프롬프트: '%s'" % _player.interact_prompt())
	_player._try_interact()
	await _settle()
	assert(I.inside(_player.global_position), "실내 진입 (%s)" % _player.global_position)
	assert(_player.global_position.distance_to(I.IN_SPAWN) < 1.5, "실내 스폰 지점 근처")
	# 도착 직후 문 트리거 밖 = E 연타로 튕겨 나가지 않는다
	var t0: Dictionary = _player.interact_target()
	assert(t0.is_empty() or t0["kind"] != "door", "실내 스폰이 문 트리거 밖 (현재 %s)" % str(t0.get("kind", "")))

	# ── 2. 실내 침대 취침 → 다음날 아침
	await _stand(Vector3(119.4, 1.0, 118.2))  # 실내 침대 남동 (실측)
	assert(_player.interact_prompt() == "E: 취침", "실내 침대 프롬프트: '%s'" % _player.interact_prompt())
	var before := GameClock.abs_day
	_player._try_interact()                    # → sleep_screen 확인창
	await get_tree().process_frame
	var ss: Node = get_tree().get_first_node_in_group("sleep_screen")
	var btns: Array = ss.find_children("", "Button", true, false)
	assert(not btns.is_empty(), "취침 확인창 열림")
	btns[0].pressed.emit()                     # '예'
	await get_tree().create_timer(1.6).timeout # 페이드 0.5+0.5 + 여유
	assert(GameClock.abs_day == before + 1, "실내 취침 → 다음날 (%d→%d)" % [before, GameClock.abs_day])
	assert(GameClock.game_min == GameClock.WAKE_MIN, "아침 06시 기상")
	assert(I.inside(_player.global_position), "기상 후에도 실내 (침대에서 깬다)")

	# ── 3. 기혼 아침: 배우자가 실내에 배치되고 대화가 걸린다
	GameClock.state = GameClock.State.PAUSED
	GameClock.game_min = 7 * 60
	_npcsys.spouse = ID
	await _stand(I.IN_SPAWN)
	_npcsys._process(0.1)
	var sp: Vector3 = _npcsys.npc_nodes[ID].position
	assert(sp.distance_to(I.SPOUSE_SPOT) < 0.01, "배우자 실내 정위치 (%s)" % sp)
	assert(_npcsys._spouse_indoor, "실내 동거 플래그")
	await _settle()
	assert(_player.interact_prompt().begins_with("E: 대화"), "실내 배우자 대화 프롬프트: '%s'" % _player.interact_prompt())
	# 배회 스텝이 실내 노드를 실외로 끌고 가지 않는다
	for _i in 20:
		_npcsys._process(0.1)
	assert(_npcsys.npc_nodes[ID].position.distance_to(I.SPOUSE_SPOT) < 0.01, "실내 배치 유지(배회 미개입)")

	# ── 4. 실내 → 집 앞, 배우자는 실외 앵커로 복귀
	await _stand(I.IN_DOOR + Vector3(0, 0, 1.0))
	assert(_player.interact_prompt() == "E: 나가기", "실내 문 프롬프트: '%s'" % _player.interact_prompt())
	_player._try_interact()
	await _settle()
	assert(not I.inside(_player.global_position), "실외 복귀 (%s)" % _player.global_position)
	assert(_player.global_position.distance_to(I.OUT_SPAWN) < 1.5, "집 앞 복귀 지점")
	_npcsys._process(0.1)
	assert(not _npcsys._spouse_indoor, "플레이어가 나가면 실내 동거 해제")
	var out: Vector3 = _npcsys.npc_nodes[ID].position
	assert(Vector2(out.x, out.z).distance_to(N.ANCHORS["player_home"]) <= N.ANCHOR_R_MAX + 0.01,
		"배우자 실외 앵커(집 앞) 복귀 (%s)" % out)

	# ── 5. NPC 밤 귀가: 자기 집 앞 주민은 숨김 + 상호작용 비활성, 아침에 복귀
	_npcsys.spouse = ""   # 배우자 예외를 빼고 순수 귀가 연출만 본다
	GameClock.game_min = 22 * 60
	_npcsys.snap_to_schedule()
	_npcsys._process(0.1)
	var hidden := 0
	for id in _npcsys.npc_nodes:
		if bool(_npcsys._wander[id]["hidden"]):
			hidden += 1
			assert(not (_npcsys._wander[id]["area"] as Area3D).is_in_group("npc"), "%s 숨김 중 상호작용 비활성" % id)
	assert(hidden == GameData.npcs.size(), "밤 = 전원 귀가 숨김 (%d/%d)" % [hidden, GameData.npcs.size()])
	GameClock.game_min = 9 * 60
	_npcsys.snap_to_schedule()
	_npcsys._process(0.1)
	for id in _npcsys.npc_nodes:
		assert(not bool(_npcsys._wander[id]["hidden"]), "%s 아침 복귀" % id)
		assert((_npcsys._wander[id]["area"] as Area3D).is_in_group("npc"), "%s 아침 상호작용 복구" % id)

	assert(SaveManager.suspended, "테스트 내내 세이브 쓰기 차단 유지")
	print("E2E INTERIOR PASS  문 왕복 / 실내 취침 D%d / 배우자 실내 / 밤 귀가 %d명" % [
		GameClock.abs_day, hidden])
	get_tree().quit()

# 텔레포트 후 Area3D 겹침이 물리 프레임에 등록될 때까지 대기
func _stand(at: Vector3) -> void:
	_player.global_position = at
	_player.velocity = Vector3.ZERO
	await _settle()

func _settle() -> void:
	for _i in 12:
		await get_tree().physics_frame

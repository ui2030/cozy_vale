extends Node
# E2E: 바닷가 존 (H단계) — 마을 게이트 왕복 + 해변 낚시(바다 어종만) + 귀가 오두막 순환.
# 헤드리스: godot --headless res://tests/e2e_beach.tscn
# 유저 세이브 보호: SaveManager.suspended (set_process(false)만으로는 게임 코드가 다시 켠다).

const B := preload("res://world/beach.gd")
const I := preload("res://world/interior.gd")

var _player: Node3D

func _ready() -> void:
	SaveManager.suspended = true  # world._ready(로드) 전에
	add_child(preload("res://world/world.tscn").instantiate())
	_run.call_deferred()

func _run() -> void:
	await get_tree().process_frame
	_player = get_tree().get_first_node_in_group("player") as Node3D
	assert(_player != null, "world 로드")
	GameClock.state = GameClock.State.PAUSED
	GameClock.abs_day = 0        # spring D1
	GameClock.game_min = 12 * 60  # 정오 (바다 야간종 배제 = 시간창 필터도 함께 걸림)

	# ── 1. 마을 남동 게이트 → 해변
	await _stand(B.V_GATE + Vector3(0, 0, -1.2))  # 흙길에서 게이트로 내려온 자리
	assert(_player.interact_prompt() == "E: 바닷가로", "마을 게이트 프롬프트: '%s'" % _player.interact_prompt())
	_player._try_interact()
	await _settle()
	assert(B.inside(_player.global_position), "해변 진입 (%s)" % _player.global_position)
	assert(_player.global_position.distance_to(B.B_SPAWN) < 1.5, "해변 스폰 지점 근처")
	var t0: Dictionary = _player.interact_target()
	assert(t0.is_empty() or t0["kind"] != "door", "해변 스폰이 문 트리거 밖 (현재 %s)" % str(t0.get("kind", "")))

	# ── 2. 모래사장 지면이 있다 (허공 낙하 없음) + 바다로는 못 들어간다
	_player.set_physics_process(false)  # Input 덮어쓰기 차단, 직접 구동
	_player.velocity = Vector3.ZERO
	for _i in 220:  # 북(바다 쪽)으로 밀어붙인다 — 스폰(z_rel 8.6)에서 물가선까지 12.9 + 여유
		_player.velocity.y = 0.0 if _player.is_on_floor() else _player.velocity.y - _player.gravity * (1.0 / 60.0)
		_player.velocity.x = 0.0
		_player.velocity.z = -5.0
		_player.move_and_slide()
		await get_tree().physics_frame
	var stop := _player.global_position
	assert(stop.y > -0.5, "모래사장 위에 서 있다 (y=%.2f)" % stop.y)
	assert(stop.z - B.ORIGIN.z > B.SHORE_Z - 0.5, "바다 진입 차단 (z_rel=%.2f)" % (stop.z - B.ORIGIN.z))
	# 나머지 세 벽도 실제로 막는지 (존 밖 허공으로 걸어 나가는 회귀 방지)
	for dir in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1)]:
		_player.global_position = B.B_SPAWN
		_player.velocity = Vector3.ZERO
		await _settle()
		for _i in 260:
			_player.velocity.y = 0.0 if _player.is_on_floor() else _player.velocity.y - _player.gravity * (1.0 / 60.0)
			_player.velocity.x = dir.x * 5.0
			_player.velocity.z = dir.z * 5.0
			_player.move_and_slide()
			await get_tree().physics_frame
		var p := _player.global_position
		assert(p.y > -0.5, "%s 방향: 허공 낙하 없음 (y=%.2f)" % [dir, p.y])
		assert(absf(p.x - B.ORIGIN.x) < B.WALK_HALF_X and p.z - B.ORIGIN.z < B.WALK_Z1,
			"%s 방향: 둘레 벽이 막는다 (rel %.1f, %.1f)" % [dir, p.x - B.ORIGIN.x, p.z - B.ORIGIN.z])
	_player.set_physics_process(true)
	await _stand(B.ORIGIN + Vector3(-2.0, 1.2, B.SHORE_Z + 1.2))  # 물가로 복귀(다음 단계 = 낚시)

	# ── 3. 물가 낚시: 프롬프트 + 바다 어종만 (연못 어종 교차 오염 0)
	await _settle()
	assert(_player.interact_prompt() == "E: 낚시", "물가 낚시 프롬프트: '%s'" % _player.interact_prompt())
	var water: Area3D = _player.interact_target()["area"]
	assert(String(water.get_meta("spot", "")) == GameData.SPOT_SEA, "물가 트리거 spot=sea")
	var fg: Node = get_tree().get_first_node_in_group("fishing")
	assert(fg != null, "fishing 노드 존재")
	_player._try_interact()
	await get_tree().process_frame
	assert(fg.is_active(), "E → 해변 낚시 미니게임 열림")
	var caught := {}
	for _i in 40:  # 실제 게임 경로(_start_fishing)로 반복 추첨
		fg._active = false
		_player._start_fishing(water)
		var fid: String = fg._fish_id
		assert(String(GameData.fish[fid].get("spot", GameData.SPOT_POND)) == GameData.SPOT_SEA,
			"해변에서 연못 어종 나옴: %s" % fid)
		caught[fid] = true
	assert(caught.size() >= 2, "바다 어종이 여러 종 나온다 (%d종)" % caught.size())
	fg._active = false
	fg.visible = false

	# ── 4. 연못은 그대로 연못 어종만 (spot 필터 회귀)
	var pond: Area3D = null
	for a in get_tree().get_nodes_in_group("water"):
		if not a.has_meta("spot"):
			pond = a
	assert(pond != null, "연못 트리거(spot 메타 없음 = pond 기본값) 존재")
	for _i in 40:
		_player._start_fishing(pond)
		var fid: String = fg._fish_id
		assert(String(GameData.fish[fid].get("spot", GameData.SPOT_POND)) == GameData.SPOT_POND,
			"연못에서 바다 어종 나옴: %s" % fid)
		fg._active = false
	fg.visible = false

	# ── 5. 귀가 오두막 → 집 실내
	await _stand(B.H_DOOR + Vector3(0, 0, 1.2))
	assert(_player.interact_prompt() == "E: 집으로", "오두막 문 프롬프트: '%s'" % _player.interact_prompt())
	_player._try_interact()
	await _settle()
	assert(I.inside(_player.global_position), "집 실내 진입 (%s)" % _player.global_position)
	assert(_player.global_position.distance_to(I.IN_SPAWN) < 1.5, "실내 스폰 지점 근처")

	# ── 6. 실내 문 → 마을 집 앞 (순환 닫힘)
	await _stand(I.IN_DOOR + Vector3(0, 0, 1.0))
	assert(_player.interact_prompt() == "E: 나가기", "실내 문 프롬프트: '%s'" % _player.interact_prompt())
	_player._try_interact()
	await _settle()
	assert(not I.inside(_player.global_position) and not B.inside(_player.global_position), "마을 복귀")
	assert(_player.global_position.distance_to(I.OUT_SPAWN) < 1.5, "집 앞 복귀 지점")

	# ── 7. 해변 게이트 → 마을 (되돌아오는 길)
	await _stand(B.B_GATE + Vector3(0, 0, -1.2))
	assert(_player.interact_prompt() == "E: 마을로", "해변 게이트 프롬프트: '%s'" % _player.interact_prompt())
	_player._try_interact()
	await _settle()
	assert(not B.inside(_player.global_position), "마을 복귀 (%s)" % _player.global_position)
	assert(_player.global_position.distance_to(B.V_SPAWN) < 1.5, "마을 도착 지점")
	var t1: Dictionary = _player.interact_target()
	assert(t1.is_empty() or t1["kind"] != "door", "마을 도착점이 게이트 트리거 밖 (현재 %s)" % str(t1.get("kind", "")))

	assert(SaveManager.suspended, "테스트 내내 세이브 쓰기 차단 유지")
	print("E2E BEACH PASS  게이트 왕복 / 바다 어종 %d종 / 오두막→실내→마을 순환" % caught.size())
	get_tree().quit()

# 텔레포트 후 Area3D 겹침이 물리 프레임에 등록될 때까지 대기
func _stand(at: Vector3) -> void:
	_player.global_position = at
	_player.velocity = Vector3.ZERO
	await _settle()

func _settle() -> void:
	for _i in 12:
		await get_tree().physics_frame

extends Node
# 헤드리스 코어 검증: godot --headless res://tests/test_core.tscn
# 시계 수식 + 취침 전환 + 세이브 원자적쓰기/복구 (DESIGN 11.1/11.2 경로).
# 일반 런타임으로 실행해야 autoload(GameClock/SaveManager) 전역이 살아있음.

var _farm: Node
var _npcsys: Node
var _stub: Node

func _ready() -> void:
	GameClock.state = GameClock.State.PAUSED  # 자동 tick 정지 (결정적 테스트)
	_stub = preload("res://tests/stub_player.gd").new()
	_stub.add_to_group("player")
	add_child(_stub)
	_farm = preload("res://farm/farm_system.gd").new()
	add_child(_farm)  # _ready: group farm 등록 + day_changed 연결
	_npcsys = preload("res://npc/npc_system.gd").new()
	add_child(_npcsys)  # _ready: npcs.json 스폰 + day_changed 연결

	_test_clock_math()
	_test_sleep()
	_test_save_roundtrip()
	_test_bak_fallback()
	_test_migration_v1_v2()
	_test_farm_loop()
	_test_crops_h1()
	_test_npc()
	_test_npc_roster()
	_test_wander()
	_test_npc_schedule()
	_test_save_v2_v3()
	_test_save_v3_v4()
	_test_save_v4_v5()
	_test_v1_save_compat()
	_test_calendar()
	_test_festival()
	_test_ring_item()
	_test_spouse_schedule()
	_test_dates()
	_test_marriage()
	_test_pause_menu()
	_test_fishing_judge()
	_test_pick_fish()
	_test_forage_rare()
	_test_collection_roundtrip()
	_test_daynight()
	_test_ambience_curve()
	_test_weather()
	_test_interior()
	_test_beach()
	print("ALL CORE TESTS PASS")
	get_tree().quit()

func _test_clock_math() -> void:
	GameClock.abs_day = 30  # 30 = 두번째 계절 3일차
	GameClock.game_min = 725
	assert(GameClock.season() == 1, "season")           # 30/28 % 4 = 1
	assert(GameClock.day_of_season() == 3, "day_of_season")  # 30%28+1
	assert(GameClock.year() == 1, "year")
	assert(GameClock.weekday() == 30 % 7, "weekday")
	assert(GameClock.hour() == 12, "hour")              # 725/60
	assert(GameClock.minute() == 5, "minute")           # 725%60

func _test_sleep() -> void:
	GameClock.abs_day = 5
	GameClock.game_min = 1300
	GameClock.sleep_to_morning()
	assert(GameClock.abs_day == 6, "sleep abs_day+1")
	assert(GameClock.game_min == GameClock.WAKE_MIN, "sleep wakes at morning")

func _test_save_roundtrip() -> void:
	GameClock.abs_day = 42
	GameClock.game_min = 700
	SaveManager._write(SaveManager._gather())
	GameClock.abs_day = 0
	GameClock.game_min = 0
	assert(SaveManager.load_game(), "load returns true")
	assert(GameClock.abs_day == 42, "restore abs_day")
	assert(GameClock.game_min == 700, "restore game_min")

func _test_bak_fallback() -> void:
	# bak = 직전 저장. json 손상시 직전 상태로 복구되어야 함.
	GameClock.abs_day = 77
	SaveManager._write(SaveManager._gather())   # json=77
	GameClock.abs_day = 88
	SaveManager._write(SaveManager._gather())   # json=88, bak=77
	var f := FileAccess.open("user://save.json", FileAccess.WRITE)
	f.store_string("{ broken json")             # json 손상
	f.close()
	GameClock.abs_day = 0
	assert(SaveManager.load_game(), "bak fallback loads")
	assert(GameClock.abs_day == 77, "json 손상 → bak(직전 저장 77) 복구")

func _test_migration_v1_v2() -> void:
	var v1 := {"save_version": 1, "clock": {"abs_day": 3, "game_min": 400}, "player": {"pos": [1, 2, 3]}}
	var m := SaveManager._migrate(v1)
	assert(int(m["save_version"]) == SaveManager.VERSION, "최신 버전까지 마이그레이션")
	assert(m["systems"]["farming"].has("tiles"), "farming.tiles 생성(1→2)")
	assert(m["systems"].has("npc"), "npc 생성(2→3)")
	assert(m["player"].has("gold"), "gold 기본값 채움")
	assert(m["player"]["pos"] == [1, 2, 3], "기존 pos 보존(전방호환)")
	# 무버전(save_version 없음) 세이브 = v1로 간주해 최신까지 마이그레이션
	var nover := SaveManager._migrate({"clock": {"abs_day": 1}})
	assert(int(nover["save_version"]) == SaveManager.VERSION, "무버전 → 최신")
	assert(nover["systems"]["farming"].has("tiles"), "무버전 → farming 생성")

# 취침 n회 동안 계속 맑고 계절도 안 넘어가는 봄 시작일 (없으면 -1). 날씨가 결정적이라
# 수동 물주기를 검증하는 테스트가 우연히 비 오는 날에 걸리면 깨진다 — 맑은 구간에 고정한다.
# 상한이 DAYS_PER_SEASON - n인 이유: 마지막 취침(s+n)까지 봄이어야 봄 작물이 고사하지 않음.
func _clear_run(n: int) -> int:
	for s in range(0, GameClock.DAYS_PER_SEASON - n):
		var ok := true
		for k in n + 1:  # 시작일 포함 s..s+n 전부 맑음
			if GameData.is_rainy(s + k):
				ok = false
				break
		if ok:
			return s
	return -1

func _test_farm_loop() -> void:
	GameClock.abs_day = _clear_run(6)  # 이 테스트는 수동 물주기 경로 — 맑은 구간에서만 유효
	assert(GameClock.abs_day >= 0, "봄에 맑은 6일 연속 구간이 없음 (RAIN_PCT 재조정 필요)")
	assert(GameData.season_id(GameClock.season()) == "spring", "전제: 봄(계절 밖 씨앗은 심기가 거부됨)")
	GameClock.game_min = 360
	var cell := Vector2i(1, 3)
	assert(_farm.till(cell), "괭이질")
	assert(_farm.plant(cell, "seed.turnip"), "씨앗 심기")
	for i in 4:  # turnip grow_days=4: 매일 물주고 취침
		assert(_farm.water(cell), "물주기 %d일" % i)
		GameClock.sleep_to_morning()
	assert(_farm.is_mature_at(cell), "4일 물주면 성숙")
	assert(_farm.harvest(cell) == "crop.turnip", "수확")
	# 판매상자 → 아침 정산
	_stub.gold = 0
	_farm.deposit("crop.turnip", 2)
	GameClock.sleep_to_morning()
	assert(_stub.gold == 120, "판매정산 60*2=120")
	assert(_farm.shipping_bin.is_empty(), "정산 후 상자 비움")
	# 물 안 준 날은 성장 정지 (watered_growth_days 저장 방식 검증)
	var c2 := Vector2i(2, 3)
	_farm.till(c2)
	_farm.plant(c2, "seed.turnip")
	var before := int(_farm.get_tile(c2)["watered_growth_days"])
	GameClock.sleep_to_morning()  # 물 안 줌
	assert(int(_farm.get_tile(c2)["watered_growth_days"]) == before, "물 안 주면 성장 정지")

# ── H-1: 작물 12종 (봄4·여름4·가을4·겨울0) ──────────────────────
# 28일 계절에 밭 한 칸이 내는 gold/day. 단발 작물은 즉시 재파종, 재수확 작물은 regrow 주기로 계산.
# 밸런스 대역이 데이터로만 유지되도록 게임 코드가 아니라 테스트에 둔다(런타임은 이 값을 안 쓴다).
func _gold_per_day(d: Dictionary) -> float:
	var season := GameClock.DAYS_PER_SEASON
	var grow := int(d["grow_days"])
	var regrow := int(d.get("regrow_days", 0))
	var sell := int(d["sell_price"])
	var cost := int(d["seed_cost"])
	if regrow > 0:
		var harvests := 1 + maxi(0, (season - grow) / regrow)
		return float(harvests * sell - cost) / float(season)
	var cycles := season / grow
	return float(cycles * (sell - cost)) / float(season)

func _test_crops_h1() -> void:
	# ── 데이터 정합: 종수·계절 분포·겨울 공백(설계)·색 구분
	assert(GameData.crops.size() == 12, "작물 12종 (실제 %d)" % GameData.crops.size())
	assert(GameData.season_seed_ids("spring").size() == 4, "봄 씨앗 4종")
	assert(GameData.season_seed_ids("summer").size() == 4, "여름 씨앗 4종")
	assert(GameData.season_seed_ids("autumn").size() == 5, "가을 씨앗 5종(가을 전용 4 + 두 계절 corn)")
	assert(GameData.season_seed_ids("winter").is_empty(), "겨울 = 씨앗 없음(설계: 낚시·채집의 계절)")
	assert(GameData.crop_in_season("crop.corn", "summer") and GameData.crop_in_season("crop.corn", "autumn"),
		"corn = 여름·가을 두 계절 작물")
	var colors := {}
	for cid in GameData.crops:
		var c: Array = GameData.crops[cid].get("color", [])
		assert(c.size() == 3, "%s color 없음(밭에서 구분 불가)" % cid)
		var key := "%.2f,%.2f,%.2f" % [c[0], c[1], c[2]]
		assert(not colors.has(key), "성장 단계 색 중복: %s ↔ %s" % [cid, str(colors.get(key))])
		colors[key] = cid
		# 씨앗 ↔ 작물 왕복 (참조 무결성은 GameData._validate가 보지만 신규 8종 매핑을 명시 확인)
		assert(GameData.crop_from_seed(GameData.crops[cid]["seed_id"]) == cid, "%s 씨앗 매핑" % cid)
	# 밭 시각화가 실제로 데이터 색을 쓴다(하드코딩 회귀 방지)
	assert(_farm.crop_color("crop.pumpkin") != _farm.crop_color("crop.eggplant"), "작물별 색 반영")
	assert(_farm.crop_color("crop.unknown") == _farm.RIPE_FALLBACK, "color 없는 id = 기본 열매색")

	# ── 밸런스 대역: 계절 안에서 한 작물이 압도하지 않는다
	var per_season := {}
	for cid in GameData.crops:
		var gpd := _gold_per_day(GameData.crops[cid])
		assert(gpd >= 8.0 and gpd <= 26.0, "%s gold/day 대역(8~26) 밖: %.2f" % [cid, gpd])
		for s in GameData.crops[cid]["seasons"]:
			if not per_season.has(s):
				per_season[s] = []
			per_season[s].append(gpd)
	for s in per_season:
		var lo: float = per_season[s].min()
		var hi: float = per_season[s].max()
		assert(hi / lo <= 3.0, "%s 계절 내 수익 격차 %.2f배 (상한 3배)" % [s, hi / lo])

	# ── 여름 재배 루프 (재수확 작물 tomato: 7일 성숙 → 수확 → 3일 재성숙)
	GameClock.abs_day = 28  # 여름 D1
	GameClock.game_min = 360
	assert(GameData.season_id(GameClock.season()) == "summer" and GameClock.day_of_season() == 1, "전제: 여름 D1")
	var cell := Vector2i(6, 3)
	assert(_farm.till(cell), "여름 괭이질")
	assert(not _farm.plant(cell, "seed.turnip"), "철 지난 봄 씨앗은 심기 거부(다음 아침 증발 방지)")
	assert(_farm.plant(cell, "seed.tomato"), "여름 씨앗 심기")
	for _i in 7:
		_farm.water(cell)  # 비 오는 날은 이미 젖어 false — 결과는 보지 않는다
		GameClock.sleep_to_morning()
	assert(_farm.is_mature_at(cell), "tomato 7일 = 성숙")
	assert(_farm.harvest(cell) == "crop.tomato", "여름 수확")
	assert(_farm.get_tile(cell)["crop_id"] == "crop.tomato" and not _farm.is_mature_at(cell), "재수확 작물 = 그루 유지")
	for _j in 3:
		_farm.water(cell)
		GameClock.sleep_to_morning()
	assert(_farm.is_mature_at(cell), "regrow 3일 = 재성숙")
	assert(_farm.harvest(cell) == "crop.tomato", "재수확")

	# ── 계절 경계 고사: 여름 막날 심은 여름 작물은 죽고, 두 계절 작물(corn)은 산다
	GameClock.abs_day = 55  # 여름 D28
	assert(GameClock.day_of_season() == 28, "전제: 여름 마지막 날")
	var c_die := Vector2i(6, 4)
	var c_live := Vector2i(7, 4)
	assert(_farm.till(c_die) and _farm.till(c_live), "막날 괭이질")
	assert(_farm.plant(c_die, "seed.tomato") and _farm.plant(c_live, "seed.corn"), "막날 심기")
	GameClock.sleep_to_morning()  # → 가을 D1
	assert(GameData.season_id(GameClock.season()) == "autumn", "가을 진입")
	assert(_farm.get_tile(c_die)["crop_id"] == "", "철 지난 작물 고사")
	assert(_farm.get_tile(c_live)["crop_id"] == "crop.corn", "여름·가을 작물은 계절 경계 생존")
	GameClock.abs_day = 83  # 가을 D28
	GameClock.sleep_to_morning()  # → 겨울 D1
	assert(GameData.season_id(GameClock.season()) == "winter", "겨울 진입")
	assert(_farm.get_tile(c_live)["crop_id"] == "", "겨울엔 corn도 고사")
	var c_win := Vector2i(5, 5)
	assert(_farm.till(c_win) and not _farm.plant(c_win, "seed.carrot"), "겨울엔 어떤 씨앗도 못 심음")

	# ── 상점 계절 재고 + 씨앗 순환 집합 (씬 트리 없이 순수 로직)
	var p: Node = preload("res://player/player.gd").new()
	p.gold = 1000
	GameClock.abs_day = 28  # 여름 D1 (월요일 = 영업일)
	assert(GameClock.weekday() != 6, "전제: 상점 영업일")
	p.selected_seed = "seed.turnip"  # 봄 씨앗을 든 채 여름 상점 앞
	assert(p.cycle_seeds() == GameData.season_seed_ids("summer"), "무보유 = 순환 집합이 이번 계절 재고와 동일")
	assert(p.active_seed() == "seed.pepper", "계절 밖 선택 → 첫 후보로 스냅: %s" % p.active_seed())
	assert(p.selected_seed == "seed.turnip", "스냅은 표시용 — 저장 표면(selected_seed)은 불변")
	p._buy_seed()
	assert(p.count("seed.pepper") == 1 and p.gold == 960, "여름 상점 = 여름 씨앗 구매 (gold %d)" % p.gold)
	# 보유한 철 지난 씨앗: 순환·패널엔 남지만 상점은 거부
	p._add_item("seed.turnip", 1)
	assert("seed.turnip" in p.cycle_seeds(), "보유 중인 철 지난 씨앗도 순환 집합에 보임")
	assert(p.active_seed() == "seed.turnip", "보유하면 그 선택이 다시 유효")
	var g0: int = p.gold
	p._buy_seed()
	assert(p.gold == g0 and p.count("seed.turnip") == 1, "철 지난 씨앗은 상점이 거부(골드·수량 무변경)")
	# Q 순환은 집합 안에서만 돌고, 스냅 자리에서 제자리걸음하지 않는다
	var set0: Array = p.cycle_seeds()
	p._cycle_seed()
	assert(p.selected_seed in set0 and p.selected_seed != "seed.turnip", "Q = 집합 내 다음 항목: %s" % p.selected_seed)
	# 겨울: 재고 0 → 구매 불가, 순환은 보유분만
	GameClock.abs_day = 84  # 겨울 D1
	assert(GameData.season_id(GameClock.season()) == "winter" and GameClock.weekday() != 6, "전제: 겨울 영업일")
	var gw: int = p.gold
	p._buy_seed()
	assert(p.gold == gw, "겨울엔 씨앗 구매 불가(재고 0)")
	assert(p.cycle_seeds() == ["seed.turnip", "seed.pepper"], "겨울 순환 = 보유분만: %s" % str(p.cycle_seeds()))
	p._remove_item("seed.turnip", 1)
	p._remove_item("seed.pepper", 1)
	assert(p.cycle_seeds().is_empty() and p.active_seed() == "", "겨울 무보유 = 고를 씨앗 없음(HUD '-')")
	p._cycle_seed()  # 빈 집합에서도 크래시 없이 무동작
	assert(p.active_seed() == "", "빈 집합 Q 무동작")
	p.free()

	# ── 세이브 표면: 작물 id 추가는 포맷 무변경 (무심코 범프하는 것을 잡는 트립와이어)
	assert(SaveManager.VERSION == 5, "작물 추가 = 세이브 포맷 무변경 (VERSION 5 유지)")
	GameClock.abs_day = 0  # 뒤 테스트를 위해 봄으로 원복
	GameClock.game_min = 360

func _test_npc() -> void:
	GameClock.abs_day = 0  # spring D1, 생일 아님
	GameClock.game_min = 360
	var id := "npc.mira"
	# 대화 +5, 하루 1회
	var r: Dictionary = _npcsys.talk(id)
	assert(r["ok"] and int(_npcsys.state[id]["affection_points"]) == 5, "대화 +5")
	assert(not _npcsys.talk(id)["ok"], "하루 1회 대화")
	assert(_npcsys.hearts(id) == 0, "5pt = 0하트")
	# 선물 취향: Mira loved=strawberry(+40)
	assert(_npcsys.give(id, "crop.strawberry")["ok"], "선물 성공")
	assert(int(_npcsys.state[id]["affection_points"]) == 45, "loved +40")
	assert(not _npcsys.give(id, "crop.turnip")["ok"], "하루 1회 선물")
	# 싫어함 -20, 0 하한 clamp (Tom disliked=strawberry)
	_npcsys.give("npc.tom", "crop.strawberry")
	assert(int(_npcsys.state["npc.tom"]["affection_points"]) == 0, "disliked -20 → 0 clamp")
	# 일변경 플래그 리셋
	GameClock.sleep_to_morning()
	assert(not _npcsys.state[id]["talked_today"] and not _npcsys.state[id]["gifted_today"], "일변경 리셋")
	# 생일 ×8 + 250 상한 clamp (Mira 생일 = spring D12 = abs_day 11)
	GameClock.abs_day = 11
	_npcsys.state[id]["gifted_today"] = false
	_npcsys.state[id]["affection_points"] = 0
	assert(_npcsys._is_birthday(id), "Mira 생일 판정")
	_npcsys.give(id, "crop.strawberry")  # 40*8=320 → 250 clamp
	assert(int(_npcsys.state[id]["affection_points"]) == 250, "생일 loved ×8 → 250 clamp")

func _test_npc_roster() -> void:
	# 주민 데이터 + 스폰 (기존 8 + 수녀님)
	assert(GameData.npcs.size() == 9, "주민 9명")
	for id in ["npc.rosa", "npc.milo", "npc.momo", "npc.pip"]:
		assert(GameData.npcs.has(id), "신규 주민 %s" % id)
		assert(_npcsys.npc_nodes.has(id), "%s 스폰됨" % id)
		assert(_npcsys.state.has(id), "%s 상태 초기화" % id)
	# 신규 아키타입 대사 풀 (GameData 참조 무결성이 커버하지만 개수 명시)
	for arche in ["easygoing", "tsundere", "playful", "curious"]:
		assert(GameData.dialogues.has(arche), "%s 대사 풀" % arche)
		assert(GameData.dialogues[arche]["normal"].size() == 3, "%s normal 3줄" % arche)
		assert(GameData.dialogues[arche]["festival"].size() == 2, "%s festival 2줄" % arche)
	assert(_npcsys._dialogue_line("npc.rosa") != "", "신규 아키타입 대사 반환")
	# candidate 필드 = mira/luna/finn/milo만 (F단계 소비, 지금은 검증만)
	for id in ["npc.mira", "npc.luna", "npc.finn", "npc.milo"]:
		assert(GameData.npcs[id].get("candidate", false), "%s 결혼후보" % id)
	for id in ["npc.tom", "npc.rosa", "npc.momo", "npc.pip"]:
		assert(not GameData.npcs[id].get("candidate", false), "%s 후보 아님" % id)

func _test_wander() -> void:
	# 낮엔 배회(위치 변화), 축제·밤엔 정지. 순수 보간 이동.
	GameClock.state = GameClock.State.NORMAL
	GameClock.game_min = 720  # 정오 = 배회 시간창
	var id := "npc.mira"
	var node: Node3D = _npcsys.npc_nodes[id]
	node.position = Vector3(-9, 0, -3)  # 집으로 리셋
	var start: Vector3 = node.position
	_npcsys._wander[id]["wait"] = 0.0
	_npcsys._wander[id]["target"] = start + Vector3(5, 0, 0)  # 밭·연못 밖
	for _i in 20:
		_npcsys._process(0.5)
	assert(node.position.distance_to(start) > 0.5, "낮에 배회 이동")
	# 축제 중 배회 정지
	var held: Vector3 = node.position
	_npcsys._festival_active = true
	_npcsys._wander[id]["wait"] = 0.0
	_npcsys._wander[id]["target"] = held + Vector3(5, 0, 0)
	for _j in 10:
		_npcsys._process(0.5)
	assert(node.position.distance_to(held) < 0.01, "축제 중 배회 정지")
	_npcsys._festival_active = false
	# 밤엔 배회 정지 (시간창 밖)
	GameClock.game_min = 1320  # 22:00
	var night: Vector3 = node.position
	_npcsys._wander[id]["wait"] = 0.0
	_npcsys._wander[id]["target"] = night + Vector3(5, 0, 0)
	for _k in 10:
		_npcsys._process(0.5)
	assert(node.position.distance_to(night) < 0.01, "밤엔 배회 정지")
	GameClock.state = GameClock.State.PAUSED  # 결정성 복원

# NPC 하루 스케줄: 시각→장소 파생(순수) + 다리 경유 + 전 구간 통행 가능 + 로드/취침 배치.
func _test_npc_schedule() -> void:
	var N := preload("res://npc/npc_system.gd")
	var BR: Array = preload("res://world/world.gd").BRIDGES
	# ── 시각 → 장소 (순수 함수)
	var sc := [{"h": 8, "place": "home"}, {"h": 10, "place": "plaza"}, {"h": 19, "place": "home"}]
	assert(N.place_at(sc, 6) == "home", "첫 항목 전 = 집")
	assert(N.place_at(sc, 10) == "plaza", "경계 시각 = 그 장소")
	assert(N.place_at(sc, 12) == "plaza", "다음 항목 전까지 유지")
	assert(N.place_at(sc, 23) == "home", "마지막 항목 유지")
	assert(N.place_at([], 12) == "home", "스케줄 없으면 집")
	# ── 데이터 검증 (game_data 참조 무결성 확장: 장소 id·시각 정렬)
	for id in GameData.npcs:
		var s: Array = GameData.npcs[id].get("schedule", [])
		assert(not s.is_empty(), "%s schedule 없음" % id)
		var prev := -1
		for e in s:
			var h := int(e["h"])
			assert(h > prev and h >= 0 and h < 24, "%s schedule 시각 오름차순·범위" % id)
			prev = h
			assert(e["place"] == "home" or N.ANCHORS.has(e["place"]), "%s 알 수 없는 장소 %s" % [id, str(e["place"])])
		assert(String(s[s.size() - 1]["place"]) == "home", "%s 하루 끝 = 집(밤 정지 정합)" % id)
	# ── 강 건너 목적지 = 다리 데크 양끝 경유 (직선 도하 금지)
	var wm: Vector2 = N.ANCHORS["windmill"]
	var pz: Vector2 = N.ANCHORS["plaza"]
	assert(N.needs_bridge(wm, pz), "풍차(강 건너)→광장 = 강 횡단")
	var path: Array = N.route(wm, pz)
	var on_deck := 0
	for w in path:
		for br in BR:
			if (w as Vector2).distance_to(br) < N.DECK_HALF + 0.01:
				on_deck += 1
	assert(on_deck == 2, "다리 데크 양끝 2점 경유 (실제 %d, wp %d)" % [on_deck, path.size()])
	assert(not N.needs_bridge(pz, N.ANCHORS["shop"]), "같은 편 = 다리 불필요")
	assert(N.route(pz, N.ANCHORS["shop"]).size() == 1, "장애물 없으면 직선 1점")
	# ── 전 주민 전 구간: 건물·물 관통 0 (앵커 좌표가 world.gd 배치와 어긋나면 여기서 터짐)
	for id in GameData.npcs:
		var s: Array = GameData.npcs[id]["schedule"]
		var hm: Array = GameData.npcs[id]["home"]
		var home := Vector2(hm[0], hm[1])
		for i in s.size():
			var a_place := String(s[i - 1]["place"]) if i > 0 else String(s[s.size() - 1]["place"])
			var b_place := String(s[i]["place"])
			if a_place == b_place:
				continue
			var a: Vector2 = home if a_place == "home" else N.ANCHORS[a_place]
			var b: Vector2 = home if b_place == "home" else N.ANCHORS[b_place]
			assert(not N._inside_block(a) and not N._inside_block(b), "%s 앵커가 장애물 안 (%s→%s)" % [id, a_place, b_place])
			var cur := a
			for w in N.route(a, b):
				var seg: Vector2 = w
				assert(N._block_hit(cur, seg).is_empty(), "%s %s→%s 구간이 건물/물 관통" % [id, a_place, b_place])
				assert(not N.needs_bridge(cur, seg), "%s %s→%s 구간이 다리 밖 도하" % [id, a_place, b_place])
				cur = seg
	# ── 데크 높이 리프트 (다리 위에서만 들림 = 발이 물에 안 잠김)
	assert(absf(N._deck_y(BR[0]) - N.DECK_Y) < 0.001, "다리 중심 = 데크 높이")
	assert(N._deck_y(BR[0] + Vector2(10, 0)) == 0.0, "다리 밖 = 지면")
	# ── 로드/취침 점프: 그 시각 장소에 이미 배치 (단체 행군 방지)
	GameClock.game_min = 13 * 60
	_npcsys.snap_to_schedule()
	var mp: Vector3 = _npcsys.npc_nodes["npc.mira"].position
	var shop: Vector2 = N.ANCHORS["shop"]  # mira 13시 = 상점
	assert(Vector2(mp.x, mp.z).distance_to(shop) <= N.ANCHOR_R_MAX + 0.01, "13시 로드 = 상점 앞 배치")
	GameClock.game_min = 1320  # 22시 = 집
	_npcsys.snap_to_schedule()
	var mh: Array = GameData.npcs["npc.mira"]["home"]
	mp = _npcsys.npc_nodes["npc.mira"].position
	assert(Vector2(mp.x, mp.z).distance_to(Vector2(mh[0], mh[1])) < 0.01, "밤 = 집 배치")

func _test_save_v2_v3() -> void:
	var v2 := {"save_version": 2, "systems": {"farming": {"tiles": {}, "shipping_bin": []}}, "player": {"gold": 100}}
	var m := SaveManager._migrate(v2)
	assert(int(m["save_version"]) == SaveManager.VERSION, "v2 → 최신")
	assert(m["systems"].has("npc"), "systems.npc 생성(v3)")
	assert(m["player"].has("collection"), "collection 생성(v4)")

func _test_save_v3_v4() -> void:
	# v3 → v4: 도감 기본 빈 배열
	var v3 := {"save_version": 3, "player": {"gold": 100}, "systems": {"npc": {}}}
	var m := SaveManager._migrate(v3)
	assert(int(m["save_version"]) == SaveManager.VERSION, "v3 → 최신")
	assert(m["player"]["collection"] == [], "collection 기본 []")
	# player 키 없는 구조도 방어 (무버전/손상 세이브)
	var nop := SaveManager._migrate({"save_version": 3})
	assert(nop["player"]["collection"] == [], "player 없어도 collection 생성")

func _test_save_v4_v5() -> void:
	# v4 → v5: 결혼 상태 키 생성, 기존 호감도 보존
	var v4 := {"save_version": 4, "player": {"gold": 100, "collection": []},
		"systems": {"npc": {"npc.mira": {"affection_points": 40}}}}
	var m := SaveManager._migrate(v4)
	assert(int(m["save_version"]) == 5, "v4 → v5")
	assert(m["systems"]["npc"]["spouse"] == null, "spouse 기본 null")
	assert(m["systems"]["npc"]["engaged"] == null, "engaged 기본 null")
	assert(int(m["systems"]["npc"]["npc.mira"]["affection_points"]) == 40, "기존 호감도 보존")
	assert(int(m["systems"]["npc"]["npc.mira"]["dates_seen"]) == 0, "주민별 dates_seen 생성")
	# systems 없는 구조도 방어 (손상 세이브)
	var nop := SaveManager._migrate({"save_version": 4})
	assert(nop["systems"]["npc"]["spouse"] == null, "systems 없어도 생성")
	# 최초 포맷(v1)에서 한 번에 최신까지
	var v1 := SaveManager._migrate({"save_version": 1})
	assert(v1["systems"]["npc"].has("spouse") and v1["systems"]["npc"].has("engaged"), "v1 → v5 결혼 키")

func _test_calendar() -> void:
	# 달력 데이터 로드 + 조회 (생일=npcs, 축제=calendar 단일 출처)
	assert(GameData.calendar.has("festival.flower"), "축제 로드")
	assert(not GameData.festival_on("spring", 15).is_empty(), "spring D15 = 축제")
	assert(GameData.festival_on("spring", 14).is_empty(), "축제 없는 날")
	assert("Mira" in GameData.birthdays_on("spring", 12), "Mira 생일 조회")
	assert(GameData.season_id(GameClock.season()) is String, "season_id 반환")

func _test_festival() -> void:
	var fest := preload("res://festival/festival_system.gd").new()
	add_child(fest)  # _ready: 축제 아님 상태로 evaluate
	var id := "npc.mira"
	var home: Array = GameData.npcs[id]["home"]
	var home_pos := Vector3(home[0], 0, home[1])
	# 축제 시간창 진입: spring D15(abs_day 14), 12:00
	GameClock.abs_day = 14
	GameClock.game_min = 720
	fest.evaluate()
	assert(_npcsys._festival_active, "축제 활성")
	assert(_npcsys.npc_nodes[id].position.distance_to(home_pos) > 1.0, "광장으로 이동")
	# 축제 중 대화 ×2 (5→10)
	_npcsys.state[id]["talked_today"] = false
	_npcsys.state[id]["affection_points"] = 0
	_npcsys.talk(id)
	assert(int(_npcsys.state[id]["affection_points"]) == 10, "축제 대화 5×2=10")
	# 시간창 종료 → 상태 해제 + 집 복귀
	GameClock.game_min = 1320  # end_min = 창 밖
	fest.evaluate()
	assert(not _npcsys._festival_active, "축제 종료")
	assert(_npcsys.npc_nodes[id].position.distance_to(home_pos) < 0.01, "집 복귀")

# ── F단계: 연애·결혼 (DESIGN 6.5) ───────────────────────────────
func _test_ring_item() -> void:
	# 프러포즈 아이템이 씨앗·산출물 집합에 섞이면 Q순환 오염·판매상자 증발·선물 오소모가 난다.
	assert(GameData.has_item_id(GameData.RING_ID), "반지 = 유효 아이템 ID")
	assert(not GameData.is_produce(GameData.RING_ID), "반지는 산출물 아님(판매·도감·선물취향 제외)")
	assert(not (GameData.RING_ID in GameData.all_seed_ids()), "반지는 씨앗 순환 집합 밖")
	assert(GameData.display_name(GameData.RING_ID) == GameData.RING_NAME, "반지 표시 이름")
	assert(GameData.RING_COST > 500, "시작 골드 500으로 1일차 즉시 구매 불가 = 저축 필요")
	assert(_farm.deposit(GameData.RING_ID, 1) == 0, "반지는 판매상자가 거부")

func _test_spouse_schedule() -> void:
	# 배우자 스케줄 오버라이드: 순수 함수 + npcs.json 원본 불변 + 앵커 통행 가능
	var N := preload("res://npc/npc_system.gd")
	var raw := JSON.stringify(GameData.npcs["npc.mira"]["schedule"])
	var sp: Array = N.spouse_schedule(GameData.npcs["npc.mira"]["schedule"])
	assert(JSON.stringify(GameData.npcs["npc.mira"]["schedule"]) == raw, "npcs.json 원본 불변")
	assert(N.place_at(sp, 6) == "player_home", "기상 시각(06시) = 플레이어 집 앞")
	assert(N.place_at(sp, 7) == "player_home", "아침 유지")
	assert(N.place_at(sp, 13) == "shop", "낮은 원래 자기 스케줄 유지 (mira 13시 상점)")
	assert(N.place_at(sp, 19) == "player_home", "저녁 = 플레이어 집 앞")
	assert(N.place_at(sp, 23) == "player_home", "밤에도 그 자리(집 대신 플레이어 집 앞)")
	var prev := -1
	for e in sp:
		assert(int(e["h"]) > prev, "오버라이드 스케줄 시각 오름차순")
		prev = int(e["h"])
		assert(N.ANCHORS.has(e["place"]), "알 수 없는 장소 %s" % str(e["place"]))
	# player_home 앵커 정합 (건물 keepout·밭·강 밖)
	var ph: Vector2 = N.ANCHORS["player_home"]
	assert(not N._inside_block(ph), "player_home 앵커가 건물 keepout 안")
	assert(not _farm.in_region(Vector2i(floori(ph.x), floori(ph.y))), "player_home 앵커가 밭 위")
	assert(N._river_dist(ph) > N.RIVER_AVOID, "player_home 앵커가 강 근처")
	# 후보 4명 배우자 스케줄 전 구간: 건물·물 관통 0 (기존 스케줄 불변식과 같은 검사)
	for id in ["npc.mira", "npc.luna", "npc.finn", "npc.milo"]:
		var s: Array = N.spouse_schedule(GameData.npcs[id]["schedule"])
		for i in s.size():
			var a: Vector2 = N.ANCHORS[String(s[i - 1]["place"])] if i > 0 else N.ANCHORS[String(s[s.size() - 1]["place"])]
			var b: Vector2 = N.ANCHORS[String(s[i]["place"])]
			var cur := a
			for w in N.route(a, b):
				assert(N._block_hit(cur, w).is_empty(), "%s 배우자 구간이 건물/물 관통" % id)
				assert(not N.needs_bridge(cur, w), "%s 배우자 구간이 다리 밖 도하" % id)
				cur = w

func _test_dates() -> void:
	# 데이트 이벤트: 하트가 열고(9·10칸), 대화가 방아쇠, 도착 앵커는 스케줄 인프라 재활용.
	var N := preload("res://npc/npc_system.gd")
	var id := "npc.luna"  # mira는 결혼 테스트가 쓰므로 분리
	GameClock.abs_day = 0  # spring D1 = 축제 아님
	GameClock.game_min = 12 * 60
	_npcsys.spouse = ""
	_npcsys.engaged = {}
	_npcsys._date = {}
	_npcsys.state[id]["dates_seen"] = 0
	# ── ♥8에선 안 열림
	_npcsys.state[id]["affection_points"] = 8 * _npcsys.HEART
	assert(_npcsys.date_index(id) == -1, "♥8 = 데이트 아직 안 열림")
	# ── ♥9 → 데이트 1(연못), 대화가 방아쇠
	_npcsys.state[id]["affection_points"] = 9 * _npcsys.HEART
	assert(_npcsys.date_index(id) == 0, "♥9 = 데이트 1 열림")
	_npcsys.state[id]["talked_today"] = false
	var t: Dictionary = _npcsys.talk(id)
	assert(t["ok"] and "연못" in String(t["msg"]), "대화 = 데이트 제안(연못): %s" % t["msg"])
	assert(_npcsys._date["id"] == id and _npcsys._date["place"] == "pond", "데이트 상태: %s" % str(_npcsys._date))
	assert(not _npcsys.talk(id)["ok"], "같은 날 재대화 불가 = 데이트 하루 1회")
	# 스케줄 오버라이드(데이트 > 배우자 > npcs.json)
	assert(N.place_at(_npcsys._schedule(id), 12) == "pond", "데이트 중 스케줄 = 연못")
	assert(N.place_at(_npcsys._schedule(id), 19) == "pond", "데이트는 저녁 스케줄도 덮음")
	assert(N.place_at(_npcsys._schedule("npc.finn"), 15) == "bridge", "데이트 무관 주민은 원래 스케줄(finn 15시 다리)")
	# ── 동시 데이트 금지
	_npcsys.state["npc.finn"]["dates_seen"] = 0
	_npcsys.state["npc.finn"]["affection_points"] = 9 * _npcsys.HEART
	assert(_npcsys.date_index("npc.finn") == -1, "데이트 진행 중 다른 데이트 금지")
	# ── 밤 = 중단(미소진, 다시 발생 가능)
	GameClock.game_min = 21 * 60
	_npcsys._check_date()
	assert(_npcsys._date.is_empty(), "밤엔 데이트 중단")
	assert(int(_npcsys.state[id]["dates_seen"]) == 0, "중단은 소진 아님")
	GameClock.game_min = 12 * 60
	assert(_npcsys.date_index(id) == 0, "중단 후 다시 열림")
	# ── 완주: 진행도 +1 + 호감 보너스 + 오버라이드 해제
	_npcsys._start_date(id, 0)
	var before := int(_npcsys.state[id]["affection_points"])
	_npcsys._finish_date(id, 0)
	assert(int(_npcsys.state[id]["dates_seen"]) == 1, "데이트 1 완주")
	assert(int(_npcsys.state[id]["affection_points"]) == before + _npcsys.DATE_BONUS, "완주 호감 보너스 +%d" % _npcsys.DATE_BONUS)
	assert(_npcsys._date.is_empty(), "완주 후 오버라이드 해제")
	assert(N.place_at(_npcsys._schedule(id), 12) == "plaza", "원래 스케줄 복귀(luna 12시 광장)")
	# ── 순서 보장: 데이트 2는 ♥10부터
	assert(_npcsys.date_index(id) == -1, "♥9 + 1회 완주 → 데이트 2는 아직")
	_npcsys.state[id]["affection_points"] = _npcsys.MAX_AFF
	assert(_npcsys.date_index(id) == 1, "♥10 = 데이트 2 열림")
	assert(String(_npcsys.DATE_PLACES[1]) == "windmill", "데이트 2 = 풍차 언덕(강 건너 = 다리 경유)")
	_npcsys._start_date(id, 1)
	_npcsys._finish_date(id, 1)
	assert(int(_npcsys.state[id]["dates_seen"]) == 2, "데이트 2 완주")
	assert(_npcsys.date_index(id) == -1, "2회 완주 후 더 안 열림")
	# ── 축제일엔 시작 금지
	GameClock.abs_day = 14  # spring D15 = 꽃축제
	assert(_npcsys.date_index("npc.finn") == -1, "축제일 데이트 금지")
	GameClock.abs_day = 0
	assert(_npcsys.date_index("npc.finn") == 0, "축제 아닌 날 열림")
	# ── 비후보는 데이트 없음
	_npcsys.state["npc.tom"]["affection_points"] = _npcsys.MAX_AFF
	assert(_npcsys.date_index("npc.tom") == -1, "비후보는 데이트 없음")
	# ── 세이브 라운드트립 (dates_seen)
	var sd: Dictionary = _npcsys.save_data()
	assert(int(sd[id]["dates_seen"]) == 2, "세이브에 데이트 진행도")
	_npcsys.load_data({id: {"affection_points": 250, "dates_seen": 1.0}})
	assert(int(_npcsys.state[id]["dates_seen"]) == 1, "로드 float → int 정규화")
	_npcsys.load_data({id: {"affection_points": 250}})  # 데이트 이전 세이브 = 필드 없음
	assert(int(_npcsys.state[id]["dates_seen"]) == 0, "구세이브(필드 없음) → 0")
	# 원복
	_npcsys._date = {}
	for nid in _npcsys.state:
		_npcsys.state[nid]["dates_seen"] = 0
	SaveManager.set_process(false)  # _finish_date가 큐잉한 저장 취소

func _test_marriage() -> void:
	var id := "npc.mira"
	GameClock.abs_day = 0
	GameClock.game_min = 8 * 60
	_npcsys.spouse = ""
	_npcsys.engaged = {}
	_npcsys._date = {}
	for nid in _npcsys.state:
		_npcsys.state[nid]["dates_seen"] = 0
	# ── 청혼 게이트 ①: 하트 부족 (만렙 ♥10 필요)
	_npcsys.state[id]["affection_points"] = 0
	assert(not _npcsys.propose(id)["ok"], "♥0 청혼 거절")
	_npcsys.state[id]["affection_points"] = 9 * _npcsys.HEART + 24  # ♥9 (경계 바로 아래)
	assert(_npcsys.hearts(id) == 9, "전제: ♥9")
	assert(not _npcsys.propose(id)["ok"], "♥9 = 만렙 미달 → 거절")
	# ── 청혼 게이트 ②: ♥10이어도 데이트 2회 전엔 거절 (힌트가 다름)
	_npcsys.state[id]["affection_points"] = _npcsys.MAX_AFF
	assert(_npcsys.hearts(id) == _npcsys.PROPOSE_HEARTS, "전제: ♥10 만렙")
	var r0: Dictionary = _npcsys.propose(id)
	assert(not r0["ok"], "♥10 + 데이트 0회 → 거절")
	assert("데이트 0/2" in String(r0["msg"]), "거절 힌트에 데이트 진행도: %s" % r0["msg"])
	_npcsys.state[id]["dates_seen"] = 1
	assert(not _npcsys.propose(id)["ok"], "데이트 1회만 봐도 거절")
	_npcsys.state[id]["dates_seen"] = 2
	# ── 후보 판정 (비후보는 player 쪽에서 반지 분기 자체를 안 탄다)
	for c in ["npc.mira", "npc.luna", "npc.finn", "npc.milo"]:
		assert(_npcsys.is_candidate(c), "%s 결혼 후보" % c)
	for c in ["npc.tom", "npc.rosa", "npc.momo", "npc.pip", "npc.nun"]:
		assert(not _npcsys.is_candidate(c), "%s 후보 아님" % c)
	# ── 거절이면 반지 무소모 (실제 player 소모 경로)
	var p: Node = preload("res://player/player.gd").new()
	p._npcsys = _npcsys
	p._add_item(GameData.RING_ID, 1)
	_npcsys.state[id]["dates_seen"] = 0  # 데이트 미완주 = 거절 조건
	assert(not p.propose_with_ring(id)["ok"], "조건 미달 청혼 실패")
	assert(p.count(GameData.RING_ID) == 1, "거절 = 반지 무소모")
	# ── ♥10 + 데이트 2회 → 수락(약혼), 반지 소모
	_npcsys.state[id]["dates_seen"] = 2
	assert(p.propose_with_ring(id)["ok"], "♥10 + 데이트 2회 청혼 수락")
	assert(p.count(GameData.RING_ID) == 0, "수락 = 반지 소모")
	assert(_npcsys.engaged["id"] == id and _npcsys.spouse == "", "약혼 상태(아직 미혼)")
	assert(int(_npcsys.engaged["wedding_abs_day"]) == _npcsys.ENGAGE_DAYS, "결혼식 = 청혼 3일 뒤")
	# ── 약혼 중 이중 청혼 거절 + 무소모
	p._add_item(GameData.RING_ID, 1)
	assert(not p.propose_with_ring("npc.luna")["ok"], "약혼 중 이중 청혼 거절")
	assert(p.count(GameData.RING_ID) == 1, "이중 청혼도 반지 무소모")
	# ── 결혼식 발동 시점: 전날·당일 09시 전엔 대기
	GameClock.abs_day = _npcsys.ENGAGE_DAYS - 1
	GameClock.game_min = 12 * 60
	_npcsys._check_wedding()
	assert(_npcsys.spouse == "", "결혼식 전날엔 미혼 유지")
	GameClock.abs_day = _npcsys.ENGAGE_DAYS
	GameClock.game_min = 8 * 60
	_npcsys._check_wedding()
	assert(_npcsys.spouse == "", "당일 09시 전엔 대기")
	# ── 당일 09시 → 결혼 성립 + 주민 광장 집합
	GameClock.game_min = _npcsys.WEDDING_HOUR * 60
	_npcsys._check_wedding()
	assert(_npcsys.spouse == id and _npcsys.engaged.is_empty(), "09시 결혼 성립")
	assert(_npcsys._festival_active, "결혼식 = 주민 광장 집합(축제 API 재활용)")
	var at_plaza := 0
	for nid in _npcsys.npc_nodes:
		var np: Vector3 = _npcsys.npc_nodes[nid].position
		if Vector2(np.x, np.z).distance_to(_npcsys.WEDDING_PLAZA) < _npcsys.FEST_RING + 0.5:
			at_plaza += 1
	assert(at_plaza >= GameData.npcs.size() - 1, "주민 광장 링 집합 (%d명)" % at_plaza)
	# ── 집합 종료: 절대분 판정이라 식 중 자정을 넘겨도 풀린다
	GameClock.abs_day += 1
	GameClock.game_min = 6 * 60
	_npcsys._check_wedding()
	assert(not _npcsys._festival_active, "자정 넘겨도 집합 해제(절대분 판정)")
	# ── 기혼자 재청혼 거절 + 무소모
	assert(not p.propose_with_ring("npc.luna")["ok"], "기혼 재청혼 거절")
	assert(p.count(GameData.RING_ID) == 1, "기혼 재청혼도 무소모")
	# ── 배우자 = married 아침 인사 + 하트 표기
	_npcsys.state[id]["talked_today"] = false
	var t: Dictionary = _npcsys.talk(id)
	assert(t["ok"] and "♥" in String(t["msg"]), "대화 토스트 하트 표기: %s" % t["msg"])
	var found := false
	for line in GameData.dialogues["cheerful"]["married"]:
		if String(line) in String(t["msg"]):
			found = true
	assert(found, "배우자는 married 대사: %s" % t["msg"])
	# ── 시간창을 지나침(취침·로드) → 연출 없이 즉시 완혼 폴백
	_npcsys.spouse = ""
	_npcsys.engaged = {"id": "npc.luna", "wedding_abs_day": GameClock.abs_day + 1}
	GameClock.abs_day += 5
	GameClock.game_min = 20 * 60
	_npcsys._check_wedding()
	assert(_npcsys.spouse == "npc.luna", "지나친 결혼식 = 즉시 완혼")
	assert(not _npcsys._festival_active, "폴백은 광장 집합 없음")
	# ── 결혼식이 축제날과 겹치면 하루 미룸 (봄 D15 = abs_day 14)
	assert(_npcsys.wedding_day_for(14) == 15, "축제날 결혼식 → 하루 미룸")
	assert(_npcsys.wedding_day_for(13) == 13, "축제 아닌 날 그대로")
	# ── 세이브 라운드트립 + 방어
	var sd: Dictionary = _npcsys.save_data()
	assert(sd["spouse"] == "npc.luna" and sd["engaged"] == null, "세이브에 배우자/약혼")
	assert(sd.has(id) and int(sd[id]["affection_points"]) > 0, "호감도와 같은 딕셔너리 공존")
	_npcsys.load_data({"spouse": "npc.luna", "engaged": {"id": id, "wedding_abs_day": 7.0}})
	assert(_npcsys.spouse == "npc.luna", "로드 배우자 복원")
	assert(int(_npcsys.engaged["wedding_abs_day"]) == 7, "JSON float → int 정규화")
	_npcsys.load_data({"spouse": "npc.ghost", "engaged": {"id": "npc.ghost"}})
	assert(_npcsys.spouse == "" and _npcsys.engaged.is_empty(), "없는 npc_id → 미혼 폴백(유령 배우자 방지)")
	# 상태 원복 — 뒤 테스트가 배우자 스케줄 오버라이드에 영향받지 않게
	_npcsys.spouse = ""
	_npcsys.engaged = {}
	_npcsys._wedding_end = -1
	_npcsys.exit_festival()
	SaveManager.set_process(false)  # _wed()가 큐잉한 저장 취소 (유저 세이브 미변경)
	p.free()

func _test_pause_menu() -> void:
	var menu := preload("res://ui/pause_menu.gd").new()
	add_child(menu)  # _ready: 뷰 빌드
	GameClock.state = GameClock.State.NORMAL
	menu.open_menu()
	assert(GameClock.state == GameClock.State.PAUSED, "메뉴 열림 → PAUSED")
	assert(menu.visible, "메뉴 표시")
	menu.close_menu()
	assert(GameClock.state == GameClock.State.NORMAL, "메뉴 닫힘 → 이전 상태 복원")

func _test_fishing_judge() -> void:
	var FG := preload("res://ui/fishing_game.gd")
	# 난이도↑ → 존 폭↓
	assert(FG.zone_half_width(0.0) > FG.zone_half_width(1.0), "쉬운 어종 존이 더 넓음")
	assert(FG.zone_half_width(0.5) >= 0.0 and FG.zone_half_width(1.0) >= 0.0, "존 폭 음수 아님")
	# 중앙(0.5) 명중, 가장자리 실패
	assert(FG.in_zone(0.5, FG.zone_half_width(0.5)), "중앙 명중")
	assert(not FG.in_zone(0.95, FG.zone_half_width(1.0)), "가장자리 + 어려움 실패")
	assert(FG.in_zone(0.5 + FG.zone_half_width(0.0) - 0.001, FG.zone_half_width(0.0)), "존 경계 안 명중")

func _test_pick_fish() -> void:
	# 가중치 선택 + 야간 시간대 필터 (순수 함수)
	var defs := {
		"fish.a": {"weight": 50, "difficulty": 0.1},
		"fish.b": {"weight": 30, "difficulty": 0.4},
		"fish.night": {"weight": 10, "difficulty": 0.8, "hours": [18, 26]},
	}
	var pool := ["fish.a", "fish.b", "fish.night"]
	# 낮 12시: 밤물고기 제외 → a(50)+b(30)=80
	assert(GameData.pick_fish(defs, pool, 0.0, 12) == "fish.a", "rng0 → 첫 후보 a")
	assert(GameData.pick_fish(defs, pool, 0.6, 12) == "fish.a", "48<50 → a")     # 0.6*80=48
	assert(GameData.pick_fish(defs, pool, 0.63, 12) == "fish.b", "50.4>50 → b")  # 0.63*80=50.4
	assert(GameData.pick_fish(defs, pool, 0.99, 12) == "fish.b", "낮엔 밤물고기 안 나옴")
	# 밤 20시: 밤물고기 후보. 0.99*90=89.1 > a+b(80) → night
	assert(GameData.pick_fish(defs, pool, 0.99, 20) == "fish.night", "밤엔 밤물고기 후보")
	# 새벽 1시(+24=25 ∈ [18,26)) 포함, 2시(26)은 배제
	assert(GameData.pick_fish(defs, ["fish.night"], 0.5, 1) == "fish.night", "새벽1시 밤물고기 가능")
	assert(GameData.pick_fish(defs, ["fish.night"], 0.5, 2) == "", "새벽2시(end 배타) 없음")
	assert(GameData.pick_fish(defs, ["fish.night"], 0.5, 12) == "", "낮 밤전용만 → 후보없음")
	# 실데이터: catfish는 야간, weight 필드 존재
	assert(GameData.fish["fish.catfish"].get("hours", []).size() == 2, "catfish 야간 창")
	assert(GameData.pick_fish(GameData.fish, ["fish.catfish"], 0.5, 12) == "", "낮엔 catfish 안 나옴")

func _test_forage_rare() -> void:
	var FS := preload("res://forage/forage_system.gd")
	assert(FS.pick_rare(false, 12345, ["forage.morel"]) == "", "근거리는 희귀 없음")
	assert(FS.pick_rare(true, 12345, []) == "", "희귀풀 없으면 없음")
	# 원거리 + 밴드 안: (1500/100)%100=15 < 20 → morel
	assert(FS.pick_rare(true, 1500, ["forage.morel"]) == "forage.morel", "원거리 희귀밴드 → morel")
	# 원거리지만 밴드 밖: (9500/100)%100=95 → 일반
	assert(FS.pick_rare(true, 9500, ["forage.morel"]) == "", "원거리라도 밴드밖 → 일반")
	assert(GameData.forage["forage.morel"].get("rare", false), "morel = 희귀 플래그")

func _test_collection_roundtrip() -> void:
	# 실제 player 스크립트로 도감 발견 → 저장 → 로드 유지 (스텁엔 도감 없음).
	# add_child 안 함: 검증 대상(_discover/save_data/load_data)은 _ready·씬트리 불필요.
	var p: Node = preload("res://player/player.gd").new()
	p._discover("fish.carp")
	p._discover("fish.carp")  # 중복 무시
	p._discover("seed.turnip")  # 씨앗은 산출물 아님 → 미등록
	assert(p.collection == ["fish.carp"], "발견 1회, 씨앗 제외: %s" % str(p.collection))
	var d: Dictionary = p.save_data()
	var p2: Node = preload("res://player/player.gd").new()
	p2.load_data(d)
	assert("fish.carp" in p2.collection, "저장→로드 도감 유지")
	p.free()
	p2.free()

func _test_daynight() -> void:
	# 시각→조명 순수 보간(day_night.sample). 낮 룩 불변 + 밤 감광 + 자정 랩 연속 검증.
	var DN := preload("res://world/day_night.gd")
	# 낮(9~16) = 승인값 상수 (9/12/16 동일)
	assert(DN.sample(12.0)["amb_e"] == 0.55, "정오 ambient energy = 승인값 0.55")
	assert(DN.sample(12.0)["sun_e"] == 1.0, "정오 sun energy = 1.0")
	assert(DN.sample(9.0)["amb_e"] == 0.55 and DN.sample(16.0)["amb_e"] == 0.55, "9·16시 낮 상수")
	assert(DN.sample(12.0)["sun_rot"] == Vector3(-52, -125, 0), "낮 태양각 승인값 유지")
	# 밤(자정) = 감광하되 암흑 아님(판독 가능)
	var n0: Dictionary = DN.sample(0.0)
	assert(n0["amb_e"] < 0.5 and n0["amb_e"] > 0.3, "밤 ambient 감광하되 암흑 아님")
	assert(n0["amb_e"] < 0.55, "밤이 낮보다 어두움")
	assert(n0["sun_e"] < 0.3, "밤 태양 에너지 급감")
	# 자정 넘김 연속(0시 == 24시, 그리고 랩 경계 근처 pop 없음)
	assert(n0["amb_e"] == DN.sample(24.0)["amb_e"] and n0["sun_e"] == DN.sample(24.0)["sun_e"], "자정 랩 연속")
	assert(absf(DN.sample(23.9)["amb_e"] - DN.sample(0.1)["amb_e"]) < 0.01, "23.9시≈0.1시(자정 pop 없음)")
	# 노을(18시) = 따뜻(R>B) + 태양 낮은 고도
	var s18: Dictionary = DN.sample(18.0)
	assert(s18["amb_col"].r > s18["amb_col"].b, "노을 환경광 따뜻(R>B)")
	assert(s18["sun_rot"].x > -30.0, "노을 태양 지평선 근처(낮은 고도)")
	# 6시 전환점 = 밤<x<낮 (연속 보간, 스냅 없음)
	var d6: Dictionary = DN.sample(6.0)
	assert(d6["amb_e"] > n0["amb_e"] and d6["amb_e"] < 0.55, "새벽6시 밤<x<낮")

func _test_ambience_curve() -> void:
	# 낮=새 / 밤=귀뚜라미 크로스페이드 곡선 (autoload/sfx.gd 순수 함수)
	assert(Sfx.day_weight(12.0) == 1.0, "정오 = 낮 앰비언스 최대")
	assert(Sfx.day_weight(2.0) == 0.0 and Sfx.day_weight(23.0) == 0.0, "심야 = 낮 앰비언스 0")
	assert(Sfx.day_weight(6.0) > 0.0 and Sfx.day_weight(6.0) < 1.0, "새벽 = 전환 중")
	assert(Sfx.day_weight(19.0) > 0.0 and Sfx.day_weight(19.0) < 1.0, "해질녘 = 전환 중")
	assert(Sfx.day_weight(6.0) < Sfx.day_weight(6.5), "새벽엔 낮 비중 증가")
	assert(Sfx.day_weight(19.0) > Sfx.day_weight(19.5), "해질녘엔 낮 비중 감소")
	# 등파워: 두 트랙 선형에너지 합이 어디서나 1 (중간점 음량 꺼짐 없음)
	for h in [0.0, 6.0, 12.0, 19.0, 23.9]:
		var w: float = Sfx.day_weight(h)
		var e := db_to_linear(Sfx.fade_db(w)) ** 2 + db_to_linear(Sfx.fade_db(1.0 - w)) ** 2
		assert(absf(e - 1.0) < 0.001, "등파워 크로스페이드 h=%s" % h)
	assert(Sfx.fade_db(0.0) <= -80.0, "가중치 0 = 무음 바닥")
	# 버스 조회 폴백 (레이아웃 없거나 오타여도 Master로 흘러 로그 도배 안 함)
	assert(Sfx.bus_or_master("존재하지않는버스") == "Master", "없는 버스 → Master 폴백")
	assert(Sfx.bus_or_master("SFX") == "SFX", "SFX 버스 존재")
	assert(Sfx.bus_or_master("Ambience") == "Ambience", "Ambience 버스 존재")

func _test_weather() -> void:
	# ── 결정성: abs_day만의 함수 (세이브 안 하므로 재로드해도 같아야 함)
	var days := []
	for d in 200:
		days.append(GameData.is_rainy(d))
	for d in 200:
		assert(GameData.is_rainy(d) == days[d], "abs_day %d 날씨 비결정적" % d)
	# ── 확률대: 목표 25%, 200일 표본 산포 감안해 넉넉히
	var rainy := days.count(true)
	assert(rainy > 25 and rainy < 75, "200일 중 비 %d일 — 25%% 대역 밖" % rainy)
	# ── 축제날(봄 D15 = abs_day 14) 강제 맑음
	assert(not GameData.festival_on("spring", 15).is_empty(), "전제: 봄 D15 = 꽃축제")
	assert(not GameData.is_rainy(14), "축제날은 강제 맑음")
	# ── 채집 해시와 무상관: 비 여부와 채집 스폰이 같은 날 늘 붙어 다니면 안 됨
	var agree := 0
	for d in 200:
		var spawn: bool = absi(hash([d, 0])) % 100 < 55  # forage_system SPAWN_PCT 재현
		if spawn == days[d]:
			agree += 1
	assert(agree > 60 and agree < 140, "비-채집 해시 상관 의심 (일치 %d/200)" % agree)

	# ── 비 오는 날 자동 물주기 (farm day_changed 4단계 정합)
	var rd := -1   # 봄의 첫 비 오는 날
	var cd := -1   # 그 뒤 첫 맑은 날
	for d in range(1, 28):
		if rd < 0 and days[d]:
			rd = d
		elif rd >= 0 and cd < 0 and not days[d]:
			cd = d
	assert(rd > 0 and cd > rd, "봄에 비/맑음 검증일 확보 (rd=%d cd=%d)" % [rd, cd])
	GameClock.abs_day = rd - 1
	GameClock.game_min = 1300
	assert(GameData.season_id(GameClock.season()) == "spring", "전제: 봄(계절 밖 씨앗은 심기가 거부됨)")
	var cell := Vector2i(4, 4)
	assert(_farm.till(cell) and _farm.plant(cell, "seed.turnip"), "검증용 심기")
	GameClock.sleep_to_morning()   # → rd (비)
	assert(_farm.get_tile(cell)["watered"], "비 오는 날 아침 = 자동 물주기")
	assert(not _farm.water(cell), "이미 젖음 → 수동 물주기 조용히 무시")
	var g0 := int(_farm.get_tile(cell)["watered_growth_days"])
	# 비 온 날 하루 = 성장 +1 (물 준 날과 동일 수식)
	GameClock.abs_day = cd - 1     # 다음 취침이 맑은 날이 되게 이동
	GameClock.sleep_to_morning()   # → cd (맑음)
	assert(int(_farm.get_tile(cell)["watered_growth_days"]) == g0 + 1, "비 온 날 성장 +1")
	assert(not _farm.get_tile(cell)["watered"], "맑은 날 아침엔 마름")
	# 비 오는 날에 새로 심어도 즉시 젖음 (아침 일괄 처리를 놓치지 않게)
	GameClock.abs_day = rd
	var c3 := Vector2i(5, 4)
	assert(_farm.till(c3) and _farm.plant(c3, "seed.turnip"), "비 오는 날 심기")
	assert(_farm.get_tile(c3)["watered"], "비 오는 날 심은 작물도 젖음")

func _test_v1_save_compat() -> void:
	# A단계(v1) 세이브를 그대로 로드 → 마이그레이션되어 복원 (호환)
	var dir := DirAccess.open("user://")
	if dir.file_exists("save.bak"):
		dir.remove("save.bak")
	var f := FileAccess.open("user://save.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"save_version": 1, "clock": {"abs_day": 9, "game_min": 100}, "player": {"pos": [0, 2, 0]}}))
	f.close()
	GameClock.abs_day = 0
	assert(SaveManager.load_game(), "v1 세이브 로드")
	assert(GameClock.abs_day == 9, "v1 → clock 복원")

# 실내(G단계) 순수 로직: 격리 좌표 판정 + 문 왕복 좌표 계약 + 배우자 실내/밤 귀가 조건.
func _test_interior() -> void:
	var I := preload("res://world/interior.gd")
	var N := preload("res://npc/npc_system.gd")
	const PLAYER_R := 1.3  # player.tscn InteractArea 반경 (프롬프트 사거리 = 이것 + 대상 반경)
	# ── 정적 배치가 바뀌었으므로 구세이브 위치는 광장 폴백돼야 한다
	assert(SaveManager.WORLD_VERSION == 3, "침대 실내 이전 = WORLD_VERSION 3")
	# ── 실내/실외 판정
	assert(I.inside(I.ORIGIN), "원점 = 실내")
	assert(I.inside(I.IN_SPAWN) and I.inside(I.IN_DOOR), "실내 스폰·문 = 실내")
	assert(I.inside(I.SPOUSE_SPOT) and I.inside(I.BED_CENTER), "배우자 자리·침대 = 실내")
	assert(not I.inside(I.OUT_SPAWN) and not I.inside(I.OUT_DOOR), "집 앞 = 실외")
	assert(not I.inside(Vector3(0, 2, -3.5)), "광장 = 실외")
	assert(not I.inside(Vector3(3, 2, 15)), "플레이어 집(마을 쪽) = 실외")
	# ── 마을과 물리적으로 겹치지 않는다 (Ground 80×80 = |x|,|z| ≤ 40 밖)
	assert(absf(I.ORIGIN.x) - I.HALF > 40.0 and absf(I.ORIGIN.z) - I.HALF > 40.0, "실내가 마을 지면 밖")
	for ko in N.BUILDING_KEEPOUT:
		assert(Vector2(I.ORIGIN.x, I.ORIGIN.z).distance_to(ko[0]) > 40.0, "실내가 마을 건물에서 충분히 멈")
	# ── 문 왕복: 도착점이 반대편 트리거 사거리 밖이어야 E 연타로 튕기지 않는다
	assert(I.IN_SPAWN.distance_to(I.IN_DOOR) > I.DOOR_R + PLAYER_R, "실내 스폰이 실내 문 밖")
	assert(I.OUT_SPAWN.distance_to(I.OUT_DOOR) > I.DOOR_R + PLAYER_R, "실외 스폰이 실외 문 밖")
	# 왕복이 닫혀 있다: 실외 문으로 들어가면 실내, 실내 문으로 나가면 실외
	assert(I.inside(I.IN_SPAWN) and not I.inside(I.OUT_SPAWN), "문 왕복 목적지 짝이 맞음")
	# 침대는 실내 문과 프롬프트가 겹치지 않을 만큼 떨어져 있다(단일판정이 문을 먹지 않게)
	assert(I.BED_CENTER.distance_to(I.IN_DOOR) > I.DOOR_R + PLAYER_R, "침대와 실내 문 이격")
	# ── 배우자 실내 배치 조건 (기혼 && 스케줄=player_home && 플레이어가 실내)
	assert(N.spouse_indoors("npc.mira", "player_home", true), "기혼+집앞시각+플레이어 실내 = 실내 배치")
	assert(not N.spouse_indoors("", "player_home", true), "미혼이면 안 함")
	assert(not N.spouse_indoors("npc.mira", "plaza", true), "낮 스케줄(광장)엔 안 함")
	assert(not N.spouse_indoors("npc.mira", "player_home", false), "플레이어가 밖이면 안 함")
	# 배우자 스케줄이 실제로 아침·저녁에 player_home을 준다(위 조건이 발화하는지 = 데이터 정합)
	var ss: Array = N.spouse_schedule(GameData.npcs["npc.mira"]["schedule"])
	assert(N.place_at(ss, N.SPOUSE_MORNING_H) == "player_home", "배우자 아침 = 집 앞")
	assert(N.place_at(ss, N.SPOUSE_EVENING_H) == "player_home", "배우자 저녁 = 집 앞")
	# ── 밤 귀가 페이드 조건
	assert(N.night_hidden(22, true, false, false), "밤 + 자기 집 = 숨김")
	assert(N.night_hidden(7, true, false, false), "활동 시작(8시) 전도 숨김")
	assert(not N.night_hidden(12, true, false, false), "낮엔 안 숨김")
	assert(not N.night_hidden(22, false, false, false), "집에서 멀면 안 숨김(길에 서 있는 그림 유지)")
	assert(not N.night_hidden(22, true, true, false), "축제 중엔 강제 가시")
	assert(not N.night_hidden(22, true, false, true), "실내 배치된 배우자는 예외")

# 바닷가 존(H단계) 순수 로직: 낚시터 spot 필터 + 게이트 왕복 좌표 계약 + 존 격리 + 마을 간섭.
func _test_beach() -> void:
	var B := preload("res://world/beach.gd")
	var I := preload("res://world/interior.gd")
	var W := preload("res://world/world.gd")
	var N := preload("res://npc/npc_system.gd")
	var F := preload("res://farm/farm_system.gd")
	const REACH := 2.0  # 프롬프트 사거리 = 문 DOOR_R(0.7) + player.tscn InteractArea(1.3)

	# ── 1. spot 필터 (순수 함수). 기본값 미지정 = pond → 기존 호출부 무변경 호환.
	var defs := {
		"fish.p": {"weight": 10, "difficulty": 0.2},                     # spot 없음 = pond
		"fish.s": {"weight": 10, "difficulty": 0.3, "spot": "sea"},
		"fish.s2": {"weight": 10, "difficulty": 0.4, "spot": "sea", "hours": [18, 26]},
	}
	var all := ["fish.p", "fish.s", "fish.s2"]
	assert(GameData.pick_fish(defs, all, 0.5, 12) == "fish.p", "spot 생략 = pond 기본값")
	assert(GameData.pick_fish(defs, all, 0.99, 12, "pond") == "fish.p", "연못엔 바다 어종 안 나옴")
	assert(GameData.pick_fish(defs, all, 0.5, 12, "sea") == "fish.s", "바다엔 바다 어종만(낮)")
	assert(GameData.pick_fish(defs, ["fish.s"], 0.5, 12, "pond") == "", "바다 전용만 있는 연못 = 후보없음")
	assert(GameData.pick_fish(defs, ["fish.p"], 0.5, 12, "sea") == "", "연못 전용만 있는 바다 = 후보없음")
	# spot과 hours가 함께 걸린다(둘 다 통과해야 후보)
	assert(GameData.pick_fish(defs, ["fish.s2"], 0.5, 12, "sea") == "", "바다 야간종은 낮에 안 나옴")
	assert(GameData.pick_fish(defs, ["fish.s2"], 0.5, 20, "sea") == "fish.s2", "바다 야간종은 밤에 후보")

	# ── 2. 실데이터: 낚시터별 풀이 서로 배타 + 양쪽 다 봄에 잡을 게 있다
	var pool := GameData.season_filter(GameData.fish, "spring")
	var sea_ids := []
	var pond_ids := []
	for fid in pool:
		var sp := String(GameData.fish[fid].get("spot", GameData.SPOT_POND))
		assert(sp in GameData.SPOT_IDS, "%s spot 잘못됨: %s" % [fid, sp])
		if sp == GameData.SPOT_SEA:
			sea_ids.append(fid)
		else:
			pond_ids.append(fid)
	assert(sea_ids.size() == 3, "바다 어종 3종 (실제 %d)" % sea_ids.size())
	assert(pond_ids.size() == 5, "기존 연못 어종 5종 유지 (실제 %d)" % pond_ids.size())
	# 200회 뽑아 교차 오염이 없는지 (가중치 경로 전체를 훑는다)
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	for _i in 200:
		var h := rng.randi_range(0, 23)
		var sea_pick := GameData.pick_fish(GameData.fish, pool, rng.randf(), h, GameData.SPOT_SEA)
		var pond_pick := GameData.pick_fish(GameData.fish, pool, rng.randf(), h, GameData.SPOT_POND)
		assert(sea_pick == "" or sea_pick in sea_ids, "바다에서 연못 어종: %s" % sea_pick)
		assert(pond_pick == "" or pond_pick in pond_ids, "연못에서 바다 어종: %s" % pond_pick)
	# 바다는 하루 어느 시각이든 물릴 게 있다(시간창 없는 종이 남아 있어야 빈손 낚시가 안 생긴다)
	for h in 24:
		assert(GameData.pick_fish(GameData.fish, pool, 0.5, h, GameData.SPOT_SEA) != "", "바다 %d시 후보 0" % h)
	# 판매가: 바다 최고가가 연못 최고가를 넘되 반지(1200) 경제를 깨지 않는다
	assert(GameData.sell_price("fish.seabream") > GameData.sell_price("fish.catfish"), "바다 최고가 > 연못 최고가")
	assert(GameData.RING_COST >= GameData.sell_price("fish.seabream") * 7, "반지값이 최고가 7배 이상 유지")
	# 도감·판매·선물은 데이터 파생 — 신규 어종이 자동으로 산출물로 잡힌다
	for fid in sea_ids:
		assert(GameData.is_produce(fid), "%s 산출물(도감·판매 대상)" % fid)
		assert(GameData.display_name(fid) != fid, "%s 표시 이름 있음" % fid)

	# ── 3. 존 격리: 마을(|x|,|z|≤40)·실내(120,120)와 물리적으로 안 겹친다
	assert(B.inside(B.B_SPAWN) and B.inside(B.B_GATE) and B.inside(B.H_DOOR), "해변 지점 = 해변 안")
	assert(not B.inside(Vector3(0, 2, -3.5)) and not B.inside(B.V_GATE), "광장·마을 게이트 = 해변 밖")
	assert(not B.inside(I.IN_SPAWN) and not I.inside(B.B_SPAWN), "해변과 실내는 서로 밖")
	assert(absf(B.ORIGIN.x) - B.SEA_W * 0.5 > 40.0, "해변이 마을 지면(80×80) 밖")
	assert(Vector2(B.ORIGIN.x, B.ORIGIN.z).distance_to(Vector2(I.ORIGIN.x, I.ORIGIN.z)) > 100.0, "해변↔실내 이격")

	# ── 4. 문 왕복 계약: 도착점이 반대편 트리거 사거리 밖(E 연타 왕복 차단)
	assert(B.B_SPAWN.distance_to(B.B_GATE) > REACH, "해변 도착점이 해변 게이트 밖")
	assert(B.V_SPAWN.distance_to(B.V_GATE) > REACH, "마을 도착점이 마을 게이트 밖")
	assert(B.B_SPAWN.distance_to(B.H_DOOR) > REACH, "해변 도착점이 오두막 문 밖")
	assert(B.B_GATE.distance_to(B.H_DOOR) > REACH, "해변 게이트와 오두막 문 프롬프트 미간섭")
	# 오두막 문 → 집 실내: 도착점은 실내이고 실내 문 트리거 밖(기존 실내 계약 재사용)
	assert(I.inside(I.IN_SPAWN) and I.IN_SPAWN.distance_to(I.IN_DOOR) > REACH, "오두막→실내 도착점 계약")
	# 순환이 닫힌다: 마을→해변→(오두막)→실내→(실내문)→마을 집 앞
	assert(B.inside(B.B_SPAWN) and not I.inside(B.V_SPAWN), "마을 도착점은 실내가 아니다")
	assert(not I.inside(I.OUT_SPAWN) and not B.inside(I.OUT_SPAWN), "실내 문 출구 = 마을")
	# 걷는 판 안에 도착·게이트가 들어있다(허공 스폰 방지)
	for p in [B.B_SPAWN, B.B_GATE, B.H_DOOR]:
		assert(absf(p.x - B.ORIGIN.x) < B.WALK_HALF_X, "%s 모래사장 폭 안" % p)
		assert(p.z - B.ORIGIN.z > B.SHORE_Z and p.z - B.ORIGIN.z < B.WALK_Z1, "%s 물가선~남단 사이" % p)
	# 가시 판이 걷는 영역보다 넉넉히 넓다(프레임 구석에 존 밖 허공이 뚫리지 않게)
	assert(B.SAND_W * 0.5 > B.WALK_HALF_X + 6.0, "모래 판이 걷는 폭보다 여유 있음")
	assert(B.SAND_REL.z + B.SAND_D * 0.5 > B.WALK_Z1 + 6.0, "모래 판이 남단보다 여유 있음")

	# ── 5. 마을 쪽 게이트가 기존 지형과 간섭하지 않는다 (남쪽 길 실측 계약)
	var g2 := Vector2(B.V_GATE.x, B.V_GATE.z)
	assert(absf(g2.x) < 40.0 and absf(g2.y) < 40.0, "마을 게이트가 Ground(80×80) 안")
	for ko in N.BUILDING_KEEPOUT:
		assert(g2.distance_to(ko[0]) > float(ko[1]), "마을 게이트가 건물 keepout 밖: %s" % str(ko[0]))
	assert(not F.REGION.has_point(Vector2i(floori(g2.x), floori(g2.y))), "마을 게이트가 밭 밖")
	# 강에서 충분히 떨어져 있다(강 폭3 + 양안 강둑 + 분절 충돌벽)
	var near := INF
	for i in W.RIVER_PTS.size() - 1:
		var a: Vector2 = W.RIVER_PTS[i]
		var b: Vector2 = W.RIVER_PTS[i + 1]
		var ab := b - a
		var t := clampf((g2 - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		near = minf(near, g2.distance_to(a + ab * t))
	assert(near > N.RIVER_AVOID, "마을 게이트가 강에서 이격 (%.2f)" % near)
	# 마을 도착점도 같은 조건(강·건물 밖) — 게이트 바로 북쪽이라 짧게 확인
	assert(Vector2(B.V_SPAWN.x, B.V_SPAWN.z).distance_to(Vector2(24, 20)) > 3.0, "마을 도착점이 집4 밖")
	# 마을 쪽 신규물은 전부 무충돌(장식 길·표지판 + Area3D 게이트)이라 구세이브가 박힐 수 없다
	# → WORLD_VERSION 유지. 이 단언이 무심코 범프하는 것을 잡는 트립와이어.
	assert(SaveManager.WORLD_VERSION == 3, "해변 추가는 마을 충돌체 무변경 = WORLD_VERSION 유지")

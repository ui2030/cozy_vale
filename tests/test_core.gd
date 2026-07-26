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
	_test_npc()
	_test_npc_roster()
	_test_wander()
	_test_save_v2_v3()
	_test_save_v3_v4()
	_test_v1_save_compat()
	_test_calendar()
	_test_festival()
	_test_pause_menu()
	_test_fishing_judge()
	_test_pick_fish()
	_test_forage_rare()
	_test_collection_roundtrip()
	_test_daynight()
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

func _test_farm_loop() -> void:
	GameClock.abs_day = 0
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
	assert(int(m["save_version"]) == 4, "v3 → v4")
	assert(m["player"]["collection"] == [], "collection 기본 []")
	# player 키 없는 구조도 방어 (무버전/손상 세이브)
	var nop := SaveManager._migrate({"save_version": 3})
	assert(nop["player"]["collection"] == [], "player 없어도 collection 생성")

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

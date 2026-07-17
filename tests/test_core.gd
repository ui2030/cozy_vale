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
	_test_save_v2_v3()
	_test_v1_save_compat()
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

func _test_save_v2_v3() -> void:
	var v2 := {"save_version": 2, "systems": {"farming": {"tiles": {}, "shipping_bin": []}}, "player": {"gold": 100}}
	var m := SaveManager._migrate(v2)
	assert(int(m["save_version"]) == 3, "v2 → v3")
	assert(m["systems"].has("npc"), "systems.npc 생성")

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

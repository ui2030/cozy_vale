extends Node
# 헤드리스 코어 검증: godot --headless res://tests/test_core.tscn
# 시계 수식 + 취침 전환 + 세이브 원자적쓰기/복구 (DESIGN 11.1/11.2 경로).
# 일반 런타임으로 실행해야 autoload(GameClock/SaveManager) 전역이 살아있음.

var _farm: Node
var _npcsys: Node
var _stub: Node

func _ready() -> void:
	# 이 테스트는 일부러 세이브를 쓴다(라운드트립·bak 폴백) — suspended로는 못 막으므로
	# 파일명을 갈아끼워 유저 세이브(save.json)를 아예 건드리지 않는다.
	SaveManager.basename = "save_test"
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
	_test_farm_off_plaza()
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
	_test_calendar_cell_fit()
	_test_festival()
	_test_ring_item()
	_test_spouse_schedule()
	_test_dates()
	_test_marriage()
	_test_pause_menu()
	_test_fishing_judge()
	_test_pick_fish()
	_test_forage_rare()
	_test_forage_look()
	_test_wood_grain()
	_test_ui_panel_skin()
	_test_winter_pass()
	_test_winter_veg_look()
	_test_autumn_veg_look()
	_test_wall_face_look()
	_test_collection_roundtrip()
	_test_daynight()
	_test_ambience_curve()
	_test_weather()
	_test_interior()
	_test_beach()
	_test_water_look()
	_test_cooking()
	_test_korean_names()
	_test_currency_korean()
	_test_dialogue_context()
	_test_npc_personality()
	_test_crop_look()
	_test_dormant_look()
	_test_forage_crops()  # 날짜를 여러 해 돌리므로 맨 뒤 (앞 테스트의 시계·주민 상태를 안 흔들게)
	_test_winter_seeds()  # 같은 이유로 맨 뒤 — Y1 가을 30일 + 겨울까지 실제로 돌린다
	print("ALL CORE TESTS PASS")
	get_tree().quit()

func _test_clock_math() -> void:
	var d2 := GameClock.DAYS_PER_SEASON + 2  # 두번째 계절 3일차
	GameClock.abs_day = d2
	GameClock.game_min = 725
	assert(GameClock.season() == 1, "season")
	assert(GameClock.day_of_season() == 3, "day_of_season")
	assert(GameClock.year() == 1, "year")
	assert(GameClock.weekday() == d2 % 7, "weekday")
	assert(GameClock.hour() == 12, "hour")              # 725/60
	assert(GameClock.minute() == 5, "minute")           # 725%60
	# 계절/연차 경계: 마지막 날 취침 → 다음 계절 D1, 겨울 막날 → 다음 해 봄 D1
	GameClock.abs_day = GameClock.DAYS_PER_SEASON - 1
	assert(GameClock.day_of_season() == GameClock.DAYS_PER_SEASON, "봄 마지막 날")
	GameClock.sleep_to_morning()
	assert(GameClock.season() == 1 and GameClock.day_of_season() == 1, "계절 넘김 = 다음 계절 D1")
	GameClock.abs_day = 4 * GameClock.DAYS_PER_SEASON - 1
	assert(GameClock.season() == 3 and GameClock.day_of_season() == GameClock.DAYS_PER_SEASON and GameClock.year() == 1, "겨울 마지막 날")
	GameClock.sleep_to_morning()
	assert(GameClock.season() == 0 and GameClock.day_of_season() == 1 and GameClock.year() == 2, "연차 넘김 = Y2 봄 D1")

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
	var f := FileAccess.open(SaveManager.path("json"), FileAccess.WRITE)
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

# 밭 칸을 REGION 기준 오프셋으로 잡는다 — 밭이 옮겨져도 테스트가 절대좌표를 따라다니지 않게.
func _fcell(dx: int, dz: int) -> Vector2i:
	return _farm.REGION.position + Vector2i(dx, dz)

# ── 밭 흙 타일이 광장 판석과 건물 밖에 있다 (좌표 실측) ────────────────
# 두 축을 둘 다 물어야 한다 — 겹침만 보면 그림이 깔끔한지 모른다.
#  (1) 판석: 옛 REGION Rect2i(0,2,8,4)가 원점 반경 6의 판석을 파고들어 32칸 중 21칸이 포장
#      위였다(13칸은 통째로 안, 가장 깊은 (0,2)는 흙 모서리가 림에서 3.96 안쪽).
#      판석 상면 0.14 > 흙 상면 0.11이라 흙이 통째로 가려 "포장도로에 심은 작물"이 됐다.
#  (2) 건물 벽면: 판석만 피해 Rect2i(4,8,8,4)로 옮겼더니 밭 남단과 플레이어 집 북벽이
#      0.5밖에 안 떨어졌다 — 겹침은 0이지만 사람이 못 지나가고 밭이 벽에 처박힌 그림이다.
# 임계 6.5 / 6.4 / 1.5는 전부 **박은 절대값**이다: PLAZA_R이나 건물 폭에서 유도하면
# 그 값을 0으로 만든 순간 임계값도 따라 0이 돼 핀이 조용히 통과한다.
# 반면 **재는 대상은 전부 실제로 만들어진 노드**다: 판석은 셰이더 discard 반경,
# 흙은 BoxMesh 크기, 건물은 world.HOUSES를 그대로 세워 벽체/모델 AABB를 잰다.
# 처마(박스 폴백 w+0.5)는 일부러 안 잰다 — y5.2라 밑으로 걸어 지나간다. 기준은 벽면.
# 단언은 **재고 치운 뒤** 몰아서 한다 — assert 실패는 그 함수를 거기서 끝내므로, 중간에서
# 물면 갈아 둔 32칸이 남아 뒤따르는 밭 테스트의 괭이질까지 줄줄이 깨진다(핀 하나가 세 건으로).
func _test_farm_off_plaza() -> void:
	var W3 := preload("res://world/world.gd")
	var probe: Node3D = W3.new()
	var root := Node3D.new()
	probe._plaza(root)
	var mi := root.get_child(0) as MeshInstance3D
	var paved_r := float((mi.material_override as ShaderMaterial).get_shader_parameter("radius"))
	var paved_top := mi.position.y
	root.free()
	# 건물 벽면 = 세운 집의 몸체 노드(child 0) AABB. GLB가 있으면 모델, 없으면 벽 박스 —
	# 어느 쪽이든 벽면이고, 뒤에 붙는 처마·창·문·충돌체는 안 섞인다.
	var walls: Array[Rect2] = []
	for hs in W3.HOUSES:
		var hroot := Node3D.new()
		probe._house(hroot, hs[0], hs[1], hs[2], hs[3], hs[4], hs[5])
		var bb: AABB = ToonCharacter.aabb_of(hroot.get_child(0))
		walls.append(Rect2(bb.position.x, bb.position.z, bb.size.x, bb.size.z))
		hroot.free()
	probe.free()
	var made: Array[Vector2i] = []
	var near_plaza := INF
	var worst_plaza := Vector2i.ZERO
	var near_wall := INF
	var worst_wall := Vector2i.ZERO
	var worst_house := Rect2()
	for dx in _farm.REGION.size.x:
		for dz in _farm.REGION.size.y:
			var cell := _fcell(dx, dz)
			if not _farm.till(cell):
				continue
			made.append(cell)
			var soil: MeshInstance3D = _farm._nodes[cell]["soil"]
			var half: Vector3 = (soil.mesh as BoxMesh).size * 0.5
			var tile := Rect2(soil.position.x - half.x, soil.position.z - half.z, half.x * 2.0, half.z * 2.0)
			# 흙 상자에서 원점(광장 중심)에 가장 가까운 점까지 — 모서리까지 재야 한다.
			var np := Vector2(maxf(absf(soil.position.x) - half.x, 0.0),
				maxf(absf(soil.position.z) - half.z, 0.0)).length()
			if np < near_plaza:
				near_plaza = np
				worst_plaza = cell
			for w in walls:
				var nw := _rect_gap(tile, w)
				if nw < near_wall:
					near_wall = nw
					worst_wall = cell
					worst_house = w
	for cell in made:  # 뒤 테스트가 쓰는 밭을 맨땅으로 되돌린다
		_farm.tiles.erase(cell)
		_farm._refresh(cell)
	assert(paved_top > 0.11, "판석 상면 %.3f — 흙 상면 0.11보다 낮으면 이 핀의 전제가 깨진다" % paved_top)
	assert(paved_r <= 6.4, "판석 포장 반경 %.2f — 밭 여유선 6.5를 침범한다" % paved_r)
	assert(made.size() == 32, "밭 %d칸 — 32칸에서 줄었다(금지존을 피하려고 밭을 깎지 말 것)" % made.size())
	assert(walls.size() == 7, "건물 %d채 — world.HOUSES가 바뀌었다(밭 이격을 다시 재라)" % walls.size())
	assert(near_plaza >= 6.5, "밭 %s 흙 모서리가 광장 중심에서 %.2f — 판석(포장 반경 %.2f) 위에 앉는다"
		% [worst_plaza, near_plaza, paved_r])
	assert(near_wall >= 1.5, "밭 %s 흙과 건물 벽면(%s) 사이가 %.2f — 사람이 지나갈 1.5가 안 된다"
		% [worst_wall, worst_house, near_wall])

# 축정렬 사각형 둘 사이 최단거리(겹치면 0).
static func _rect_gap(a: Rect2, b: Rect2) -> float:
	return Vector2(maxf(maxf(b.position.x - a.end.x, a.position.x - b.end.x), 0.0),
		maxf(maxf(b.position.y - a.end.y, a.position.y - b.end.y), 0.0)).length()

func _test_farm_loop() -> void:
	GameClock.abs_day = _clear_run(6)  # 이 테스트는 수동 물주기 경로 — 맑은 구간에서만 유효
	assert(GameClock.abs_day >= 0, "봄에 맑은 6일 연속 구간이 없음 (RAIN_PCT 재조정 필요)")
	assert(GameData.season_id(GameClock.season()) == "spring", "전제: 봄(계절 밖 씨앗은 심기가 거부됨)")
	GameClock.game_min = 360
	var cell := _fcell(1, 1)
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
	var c2 := _fcell(2, 1)
	_farm.till(c2)
	_farm.plant(c2, "seed.turnip")
	var before := int(_farm.get_tile(c2)["watered_growth_days"])
	GameClock.sleep_to_morning()  # 물 안 줌
	assert(int(_farm.get_tile(c2)["watered_growth_days"]) == before, "물 안 주면 성장 정지")

# ── H-1: 작물 12종 (봄4·여름4·가을4·겨울0) ──────────────────────
# 한 계절(DAYS_PER_SEASON일)에 밭 한 칸이 내는 gold/day. 단발 작물은 즉시 재파종, 재수확 작물은 regrow 주기로 계산.
# 밸런스 대역이 데이터로만 유지되도록 게임 코드가 아니라 테스트에 둔다(런타임은 이 값을 안 쓴다).
#
# 씨앗값 규약 3종 (다년생·채집물 재배가 들어오며 갈렸다):
#  - 씨앗 전용 아이템(상점 구매) → seed_cost 그대로
#  - 주운 채집물을 그대로 심는 **한해살이** → 씨앗값 = 그 아이템 판매가.
#    한 개를 안 팔고 묻는 기회비용이 진짜 원가다(그래서 첫 수확은 본전이고 재수확부터 이득).
#  - **다년생** → 0. 한 번 심으면 해마다 다시 열려 파종 비용이 무한히 분할상환된다.
#    (되돌린 시도: 다년생에도 매 계절 씨앗값을 물려 봤더니 첫해만 재는 셈이라 정상 상태를
#     과소평가했다 — 대역 상한이 독주를 못 잡는다. 정상 상태로 재는 쪽을 택했다.)
func _gold_per_day(cid: String) -> float:
	var d: Dictionary = GameData.crops[cid]
	var season := GameClock.DAYS_PER_SEASON
	var grow := int(d["grow_days"])
	var regrow := int(d.get("regrow_days", 0))
	var sell := GameData.sell_price(cid)  # 프로덕션 해석 — 채집물 재배는 그 채집물 값을 본다
	var cost := 0
	if not GameData.crop_perennial(cid):
		cost = sell if GameData.crop_yield(cid) != cid else int(d["seed_cost"])
	if regrow > 0:
		var harvests := 1 + maxi(0, (season - grow) / regrow)
		return float(harvests * sell - cost) / float(season)
	var cycles := season / grow
	return float(cycles * (sell - cost)) / float(season)

func _test_crops_h1() -> void:
	# ── 데이터 정합: 종수·계절 분포·겨울 공백(설계)·색 구분
	# 기존 작물 12 + 재배 가능 채집물 13(버섯 3종 제외 — 동굴 해금 후 포자 재배, DESIGN 6.2)
	assert(GameData.crops.size() == 25, "재배 항목 25종 (실제 %d)" % GameData.crops.size())
	# 상점 재고는 **씨앗 전용 아이템**만 — 주운 채집물을 그대로 심는 항목은 상점에 없다(채집이 공급원).
	# 이 셋은 승인된 12종의 고정 집합이라 정확히 센다.
	assert(GameData.season_seed_ids("spring").size() == 4, "봄 상점 씨앗 4종")
	assert(GameData.season_seed_ids("summer").size() == 4, "여름 상점 씨앗 4종")
	assert(GameData.season_seed_ids("autumn").size() == 5, "가을 상점 씨앗 5종(가을 전용 4 + 두 계절 corn)")
	# ⚠ 옛 핀은 "겨울 = 씨앗 없음" 하나였다. 다년생이 들어오며 둘로 갈린다:
	#   겨울에 **심을 수 있는** 것은 없고(파종 금지 유지), 겨울에 **열리는** 것은 있다(가을에 심어둔 다년생).
	#   계약은 "겨울 파종 불가"지 "겨울 작물 없음"이 아니다.
	assert(GameData.season_seed_ids("winter").is_empty(), "겨울 상점 재고 0(설계: 파종 없는 계절)")
	var plantable := {}
	for s in GameData.SEASON_IDS:
		plantable[s] = []
		for cid2 in GameData.crops:
			if GameData.crop_plantable(cid2, s):
				plantable[s].append(cid2)
	# 심을 수 있는 종은 **하한**으로 잡는다 — 종이 늘 때마다 숫자를 고치게 되면 그게 부패다.
	for s in ["spring", "summer", "autumn"]:
		assert(plantable[s].size() >= 7, "%s 심을 수 있는 종 %d개 — 하한 7" % [s, plantable[s].size()])
	assert(plantable["winter"].is_empty(), "겨울엔 어떤 종도 못 심는다(파종 금지)")
	assert(GameData.season_filter(GameData.crops, "winter").size() >= 4,
		"겨울에 열리는 재배 종 하한 4 (실제 %d)" % GameData.season_filter(GameData.crops, "winter").size())
	assert(GameData.crop_in_season("crop.corn", "summer") and GameData.crop_in_season("crop.corn", "autumn"),
		"corn = 여름·가을 두 계절 작물")
	var colors := {}
	for cid in GameData.crops:
		# 밭이 실제로 칠하는 색(프로덕션 경로)을 잰다 — 채집물 재배는 색을 다시 안 적고
		# 그 채집물 hex를 해석해 쓰므로, json 배열만 보면 배선이 끊겨도 통과한다.
		var c: Color = _farm.crop_color(cid)
		assert(c != _farm.RIPE_FALLBACK, "%s 색 미해석 — 밭에서 구분 불가(폴백으로 떨어짐)" % cid)
		var key := "%.2f,%.2f,%.2f" % [c.r, c.g, c.b]
		assert(not colors.has(key), "성장 단계 색 중복: %s ↔ %s" % [cid, str(colors.get(key))])
		colors[key] = cid
		# 씨앗 ↔ 작물 왕복 (참조 무결성은 GameData._validate가 보지만 신규 종 매핑을 명시 확인)
		assert(GameData.crop_from_seed(GameData.crops[cid]["seed_id"]) == cid, "%s 씨앗 매핑" % cid)
	# 밭 시각화가 실제로 데이터 색을 쓴다(하드코딩 회귀 방지)
	assert(_farm.crop_color("crop.pumpkin") != _farm.crop_color("crop.eggplant"), "작물별 색 반영")
	assert(_farm.crop_color("crop.unknown") == _farm.RIPE_FALLBACK, "color 없는 id = 기본 열매색")

	# ── 밸런스 대역: 계절 안에서 한 작물이 압도하지 않는다
	var per_season := {}
	for cid in GameData.crops:
		var gpd := _gold_per_day(cid)
		# 계절 30일화 때 cranberry가 재수확 임계(30-9=21, 21/5 → 4→5회)로 26.67 독주 →
		# 기획 판정: sell 180→160(수확 5회×160=23.33, 재수확 프리미엄 1위 유지·독주 해소). 상한 26 복원.
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
	GameClock.abs_day = GameClock.DAYS_PER_SEASON  # 여름 D1
	GameClock.game_min = 360
	assert(GameData.season_id(GameClock.season()) == "summer" and GameClock.day_of_season() == 1, "전제: 여름 D1")
	var cell := _fcell(6, 1)
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
	GameClock.abs_day = 2 * GameClock.DAYS_PER_SEASON - 1  # 여름 마지막 날
	assert(GameClock.day_of_season() == GameClock.DAYS_PER_SEASON, "전제: 여름 마지막 날")
	var c_die := _fcell(6, 2)
	var c_live := _fcell(7, 2)
	assert(_farm.till(c_die) and _farm.till(c_live), "막날 괭이질")
	assert(_farm.plant(c_die, "seed.tomato") and _farm.plant(c_live, "seed.corn"), "막날 심기")
	GameClock.sleep_to_morning()  # → 가을 D1
	assert(GameData.season_id(GameClock.season()) == "autumn", "가을 진입")
	assert(_farm.get_tile(c_die)["crop_id"] == "", "철 지난 작물 고사")
	assert(_farm.get_tile(c_live)["crop_id"] == "crop.corn", "여름·가을 작물은 계절 경계 생존")
	GameClock.abs_day = 3 * GameClock.DAYS_PER_SEASON - 1  # 가을 마지막 날
	GameClock.sleep_to_morning()  # → 겨울 D1
	assert(GameData.season_id(GameClock.season()) == "winter", "겨울 진입")
	assert(_farm.get_tile(c_live)["crop_id"] == "", "겨울엔 corn도 고사")
	var c_win := _fcell(5, 3)
	assert(_farm.till(c_win) and not _farm.plant(c_win, "seed.carrot"), "겨울엔 어떤 씨앗도 못 심음")

	# ── 상점 계절 재고 + 씨앗 순환 집합 (씬 트리 없이 순수 로직)
	var p: Node = preload("res://player/player.gd").new()
	p.gold = 1000
	GameClock.abs_day = GameClock.DAYS_PER_SEASON  # 여름 D1
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
	# 겨울 D2 — D1(abs_day 90)은 일요일 휴무라 "재고 0" 대신 요일로 막혀 검증이 무뎌진다
	GameClock.abs_day = 3 * GameClock.DAYS_PER_SEASON + 1
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
	# ── 풀 아치 데크 = NPC 발높이 곡선과 동일식 (어긋나면 건너는 동안 발이 돌에 파묻히거나 뜬다)
	# NPC는 이제 world.gd deck_lift를 직접 호출하므로 이 루프는 "식 복제 재발" 방지 트립와이어다.
	# 표본은 다리 로컬 X축(강 횡단 = 데크 축) 위에서 뜬다 — 데크는 축 밖에선 리프트가 죽는다.
	var W2 := preload("res://world/world.gd")
	var b_ang: float = W2._river_dir_at(BR[0])
	var b_axis := Vector2(cos(b_ang), -sin(b_ang))  # 다리 로컬 +X의 월드 방향
	for i in 13:
		var dx := -3.0 + i * 0.5
		assert(absf(W2.deck_top(dx) - N._deck_y(BR[0] + b_axis * dx)) < 0.001,
			"데크 상면 x=%.1f (%.3f) ≠ NPC 발높이 (%.3f)" % [dx, W2.deck_top(dx), N._deck_y(BR[0] + b_axis * dx)])
	assert(W2.deck_top(0.0) == N.DECK_Y, "관정 = DECK_Y")
	assert(absf(W2.deck_top(3.0) - 0.1) < 0.05, "데크 끝이 지면 상면(0.1)과 턱 없이 물림")
	# 연속 원호: 관정에 평탄 구간이 없다(혹등 v2 회귀 방지 — 스무스스텝은 0에서 기울기가 0).
	assert(W2.deck_top(0.0) - W2.deck_top(0.4) > 0.015, "관정이 평평함 = 원호가 아님")
	# 원호 위 아무 점이나 원 방정식을 만족 (반지름 파생값이 어긋나면 여기서 터짐)
	for i in 7:
		var ax := i * 0.5
		var cy: float = W2.DECK_CROWN - W2.DECK_ARC_R
		assert(absf(Vector2(ax, W2.deck_top(ax) - cy).length() - W2.DECK_ARC_R) < 0.001, "x=%.1f 원호 이탈" % ax)
	# 데크 축 밖(흐름 방향)은 리프트 0 — 다리 옆 강물 위에 떠 있지 않게
	var b_flow := Vector2(sin(b_ang), cos(b_ang))
	assert(W2.deck_lift(BR[0] + b_flow * 2.0) == 0.0, "데크 폭 밖 = 리프트 0")
	assert(absf(W2.deck_lift(BR[0] + b_flow * 1.5) - W2.DECK_CROWN) < 0.001, "난간 선까지는 온전한 데크 높이")
	# ── 강둑이 "떠 있는 물"을 가리는 계약 (슬림화하다 illusion을 깨는 회귀 방지)
	# 물 상자: 중심 y0.16 · 높이 0.14 → 상면 0.23 (초지 상면 0.10보다 높다) · 반폭 1.5.
	assert(W2.BANK_H - 0.23 >= 0.10, "강둑 상면이 물 위 턱 0.10 미만 (%.2f)" % (W2.BANK_H - 0.23))
	assert(W2.BANK_OFF - W2.BANK_W * 0.5 <= 1.6, "강둑 안쪽 모서리가 물(반폭1.5)에서 떨어짐 (%.2f)" % (W2.BANK_OFF - W2.BANK_W * 0.5))
	assert(W2.BANK_H < 0.55, "강둑이 아치 발치(데크 끝 ~0.55)보다 높다 = 다리가 흙에 먹힘")
	# ── 물 박스가 곡률 셰이더에 잠기지 않는 계약 (강 안에 "물 아닌 잔디" 패치 회귀 방지)
	# 툰 셰이더는 정점마다 v.y -= 0.006·z² — 세분할 없는 긴 박스는 조각이 현으로 근사돼
	# 최대 0.006·조각²/4 만큼 처진다. 물 상면 0.23 − 잔디 상면 0.10 = 여유 0.13.
	# 굽이 쐐기: 박스 끝 여유가 1.5·tan(Δ/2)보다 작으면 바깥 모서리에 잔디가 남고,
	# 크면 그만큼 강둑 밖으로 물이 삐져나온다 — 파생식이라 항상 정확히 맞는다.
	for i in W2.RIVER_PTS.size() - 1:
		var pa: Vector2 = W2.RIVER_PTS[i]
		var pb: Vector2 = W2.RIVER_PTS[i + 1]
		var pad_a: float = absf(W2._joint_ext(i, false, 1.5))
		var pad_b: float = absf(W2._joint_ext(i, true, 1.5))
		var lz: float = (pb - pa).length() + pad_a + pad_b
		var piece := lz / float(W2._subdiv_z(lz) + 1)
		assert(0.006 * piece * piece * 0.25 < 0.13,
			"강 세그먼트 %d 물면 처짐 %.3f ≥ 여유 0.13 (조각 %.2f)" % [i, 0.006 * piece * piece * 0.25, piece])
		# 수식만이 아니라 _box()가 실제로 그 값을 메시에 물리는지도 본다(우회 삭제 회귀 방지).
		var probe := W2.new()
		var pm: BoxMesh = probe._box(probe, Vector3.ZERO, Vector3(3.0, 0.14, lz), Color.WHITE, 0.0).mesh
		assert(pm.subdivide_depth == W2._subdiv_z(lz), "_box가 장축 세분할을 안 걸었다 (z=%.1f)" % lz)
		probe.free()
		if i > 0:
			var p0: Vector2 = W2.RIVER_PTS[i - 1]
			var half := absf((pa - p0).angle_to(pb - pa)) * 0.5
			assert(absf(pad_a - 1.5 * tan(half)) < 0.001,
				"관절 %d 굽이 %.1f° 물 박스 패딩 어긋남 (필요 %.3f, 현재 %.3f)"
					% [i, rad_to_deg(half) * 2.0, 1.5 * tan(half), pad_a])
		else:
			assert(pad_a == 0.0, "강 북단은 관절이 아니다 — 여유를 주면 둑 밖으로 물이 삐져나온다")
	# 강 남단도 같은 계약(마지막 세그먼트의 b끝). 여기가 실제로 새던 자리다.
	assert(W2._joint_ext(W2.RIVER_PTS.size() - 2, true, 1.5) == 0.0, "강 남단 여유 0")
	# 강둑 마이터는 부호가 있어야 한다: 굽이 바깥은 늘리고 안쪽은 같은 양만큼 줄인다(호출부가 s를 곱한다).
	# 옛 absf 식은 안쪽에서 두 런이 겹쳐 둑이 두꺼워지는 계단 혹을 만들었다.
	# S자 곡류라 관절 1(북, 서로 꺾임)과 관절 5(남, 반대로 꺾임)의 부호가 반대여야 한다.
	assert(W2._joint_ext(1, false, W2.BANK_OFF) < 0.0 and W2._joint_ext(5, false, W2.BANK_OFF) > 0.0,
		"굽이 방향 부호가 살아 있지 않다(absf 회귀) — 안쪽 둑이 겹쳐 혹이 된다")
	# ── 광장 판석도 같은 곡률 함정에 걸렸었다(실측 assets1/probe_nofount): 원기둥 뚜껑은
	# 중심-림 삼각형 팬이라 스포크가 r6 = 처짐 0.006·6²/4 = 0.054 > 여유 0.04라 광장 한복판에
	# 잔디가 뚫고 올라왔다. 판 + 세분할로 고쳤으니 그 계약(칸 대각 처짐 < 지면 여유)을 잡는다.
	var probe_p := W2.new()
	var plaza_root := Node3D.new()
	probe_p._plaza(plaza_root)
	var plaza_mi := plaza_root.get_child(0) as MeshInstance3D
	var plaza_pm := plaza_mi.mesh as PlaneMesh
	var pdiag: float = W2.PLAZA_R * 2.0 / float(plaza_pm.subdivide_width + 1) * sqrt(2.0)
	assert(0.006 * pdiag * pdiag * 0.25 < plaza_mi.position.y - 0.10,
		"판석 칸 처짐 %.3f ≥ 지면 여유 %.2f" % [0.006 * pdiag * pdiag * 0.25, plaza_mi.position.y - 0.10])
	assert(absf(plaza_mi.position.y - 0.14) < 0.001, "판석 상면 0.14 계약(길 0.185 아래 · 접지 그림자판 0.20 아래)")
	plaza_root.free()
	probe_p.free()
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

# ── 달력 칸이 내용에 밀리지 않는가 ──────────────────────────────────
# 칸 글자는 날짜 + 그날 축제 + 그날 생일들이라 **데이터가 늘면 칸이 넘친다**. Label은 자동
# 줄바꿈도 잘라내기도 꺼져 있어서 넘쳐도 안 잘린다 — PanelContainer가 그냥 커지고 그 주 한 줄만
# 키가 달라진다. 조용히 밀리는 종류라 핀이 없으면 아무도 모른다(실측 collection/cal_w: 겨울 D10이
# 축제+생일로 3줄 62px인데 칸이 52px였다 = 도입 당시 이미 넘쳐 있었다. 칸 높이를 66으로 올려 담았다).
#
# 재는 것은 **프로덕션 _make_cell이 만든 그 Label의 최소 크기**다. get_string_size로 한 줄씩
# 재지 않고 Label에 물어보는 이유: 줄 수·줄간격·폰트 폴백까지 레이아웃 엔진이 실제로 쓰는 값을
# 그대로 받기 때문이다(글자 수 어림은 못 쓴다 — 한글·로마자·기호가 폭이 다르다). 트리에 붙여야
# 테마에서 폰트가 산다. 칸 규칙은 두 곳에 안 적는다 — _make_cell을 그대로 부른다.
func _test_calendar_cell_fit() -> void:
	var cp: Control = preload("res://ui/calendar_panel.gd").new()
	add_child(cp)
	var measured := 0
	var w_max := 0.0
	var h_max := 0.0
	var w_worst := ""
	var h_worst := ""
	for sidx in GameData.SEASON_IDS.size():
		var sid := GameData.season_id(sidx)
		for day in range(1, GameClock.DAYS_PER_SEASON + 1):
			var cell: Control = cp._make_cell(sid, day, false)
			add_child(cell)
			var lbl: Label = cell.get_child(0)
			var ms := lbl.get_combined_minimum_size()
			var tag := "%s D%d [%s]" % [sid, day, lbl.text.replace("\n", " / ")]
			if ms.x > w_max:
				w_max = ms.x
				w_worst = tag
			if ms.y > h_max:
				h_max = ms.y
				h_worst = tag
			remove_child(cell)
			cell.free()
			measured += 1
	cp.free()
	assert(measured == 4 * GameClock.DAYS_PER_SEASON,
		"달력 칸을 %d개만 쟀다 — 네 계절 × %d일 전수를 안 돌았다" % [measured, GameClock.DAYS_PER_SEASON])
	# 문턱 78·66은 핀 안에 박은 숫자다. CELL에서 끌어오면 칸을 줄이는 순간 문턱도 같이 줄어
	# 조용히 통과한다. 실측(2026-08-31): 최대 폭 69.0 · 최대 높이 62.0 = **여유 폭 9px·높이 4px**.
	# 축제 이름을 한 글자 늘리거나 같은 날에 생일을 하나 더 두면 여기가 운다.
	assert(w_max <= 78.0, "달력 칸 글자 폭 %.1f — 칸(78)을 넘어 그 주 줄이 옆으로 밀린다: %s" % [w_max, w_worst])
	assert(h_max <= 66.0, "달력 칸 글자 높이 %.1f — 칸(66)을 넘어 그 주 줄만 키가 달라진다: %s" % [h_max, h_worst])

func _test_calendar() -> void:
	# 달력 데이터 로드 + 조회 (생일=npcs, 축제=calendar 단일 출처)
	assert(GameData.calendar.has("festival.flower"), "축제 로드")
	assert(not GameData.festival_on("spring", 15).is_empty(), "spring D15 = 축제")
	assert(GameData.festival_on("spring", 14).is_empty(), "축제 없는 날")
	assert("미라" in GameData.birthdays_on("spring", 12), "npc.mira 생일 조회")
	assert(GameData.season_id(GameClock.season()) is String, "season_id 반환")
	# H-2: 4계절 전부 축제 1개씩 (달력 패널·기상 토스트가 자동으로 4개를 집는 근거)
	assert(GameData.calendar.size() == 4, "축제 4종")
	var by_season := {}
	for fid in GameData.calendar:
		var f: Dictionary = GameData.calendar[fid]
		assert(not by_season.has(f["season"]), "계절당 축제 1개: %s 중복" % str(f["season"]))
		by_season[f["season"]] = fid
		# 시간창은 하루(0~1440) 안에 닫힌다 — 자정 넘김은 _festival_now()의 단순 비교가 못 다룬다
		assert(int(f["start_min"]) >= 0 and int(f["end_min"]) <= GameClock.MINUTES_PER_DAY, "%s 시간창 하루 안" % fid)
	for s in GameData.SEASON_IDS:
		assert(by_season.has(s), "%s 축제 있음" % s)
	assert(by_season["spring"] == "festival.flower" and int(GameData.calendar["festival.flower"]["day"]) == 15, "봄 D15 꽃축제")
	assert(by_season["summer"] == "festival.star" and int(GameData.calendar["festival.star"]["day"]) == 15, "여름 D15 별빛축제")
	assert(by_season["autumn"] == "festival.harvest" and int(GameData.calendar["festival.harvest"]["day"]) == 15, "가을 D15 수확제")
	assert(by_season["winter"] == "festival.lantern" and int(GameData.calendar["festival.lantern"]["day"]) == 10, "겨울 D10 등불축제")
	# 축제일 파생 + 강제 맑음 (축제는 abs_day 파생이라 세이브에 아무것도 안 남는다)
	for d in GameClock.DAYS_PER_SEASON * 4:
		var sid: String = GameData.SEASON_IDS[GameClock.season_at(d)]
		var is_fest := not GameData.festival_on(sid, GameClock.day_of_season_at(d)).is_empty()
		if is_fest:
			assert(not GameData.is_rainy(d), "축제일 abs_day %d 강제 맑음" % d)
	assert(not GameData.festival_on("summer", 15).is_empty(), "여름 D15 파생")
	assert(not GameData.festival_on("autumn", 15).is_empty(), "가을 D15 파생")
	assert(not GameData.festival_on("winter", 10).is_empty(), "겨울 D10 파생")
	assert(GameData.festival_on("winter", 15).is_empty(), "겨울 D15는 축제 아님")
	# 축제별 대사: 아키타입 × 축제 전부 2줄 (개수는 데이터에서 세고, 하드코딩하지 않는다)
	for arche in GameData.dialogues:
		for fid in GameData.calendar:
			var pool: Array = GameData.dialogues[arche].get(fid, [])
			assert(pool.size() == 2, "%s / %s 축제 대사 2줄 (지금 %d)" % [arche, fid, pool.size()])
		assert(GameData.dialogues[arche].get("festival", []).size() == 2, "%s 축제 공용 대사 2줄(결혼식 폴백)" % arche)

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
	assert(fest._decor == null, "축제 종료 = 장식 해제")

	# ── H-2: 저녁 축제(여름 별빛제 20:00~23:00). DAY_END=20 이후 집합이므로
	# "축제 > 밤" 우선순위가 실제로 성립하는지가 핵심 위험이었다.
	GameClock.abs_day = GameClock.DAYS_PER_SEASON + 14     # summer D15
	GameClock.game_min = 1230  # 20:30 = DAY_END(20시) 넘긴 시각
	fest.evaluate()
	assert(_npcsys._festival_active, "저녁 축제 활성(DAY_END 이후)")
	assert(_npcsys._festival_id == "festival.star", "축제 id 전달")
	assert(_npcsys.npc_nodes[id].position.distance_to(home_pos) > 1.0, "밤에도 광장 집합")
	assert(fest._decor == null, "별빛제는 장식 없음(하늘·상시 가로등이 그림)")
	# 밤 귀가 숨김이 축제에 양보하는지 — 매 프레임 도는 판정을 직접 돌려 확인
	_npcsys._update_home_hide()
	for nid in _npcsys.npc_nodes:
		assert(not bool(_npcsys._wander[nid]["hidden"]), "%s 밤 축제 중 가시" % nid)
	# 순수 판정으로도 고정 (h=20,21,22 전부 축제면 안 숨김)
	for h in [20, 21, 22]:
		assert(not _npcsys.night_hidden(h, true, true, false), "h=%d 축제면 미숨김" % h)
		assert(_npcsys.night_hidden(h, true, false, false), "h=%d 축제 아니면 숨김" % h)
	# 축제 중엔 축제별 대사 풀을 쓴다 (공용 festival 풀이 아니라)
	var star_pool: Array = GameData.dialogues[String(GameData.npcs[id]["archetype"])]["festival.star"]
	assert(_npcsys._dialogue_line(id) in star_pool, "별빛제 전용 대사")
	# 23:00 종료 → 집 복귀 + 그제서야 숨김(숨김은 exit가 아니라 다음 _update_home_hide가 한다)
	GameClock.game_min = 1380  # 23:00 = end_min
	fest.evaluate()
	assert(not _npcsys._festival_active, "23시 축제 종료")
	assert(_npcsys._festival_id == "", "종료 시 축제 id 해제")
	assert(_npcsys.npc_nodes[id].position.distance_to(home_pos) < 0.01, "종료 후 집 복귀(한밤 행군 없음)")
	_npcsys._update_home_hide()
	assert(bool(_npcsys._wander[id]["hidden"]), "종료 후 밤 숨김 재개")
	# 축제가 끝나면 축제 풀을 안 쓴다. **"normal 안에 있다"로는 더 못 박는다** — 이제 계절·날씨
	# 풀이 평상보다 먼저 걸리기 때문. 우선순위 목록에서 축제 key가 빠졌는지로 본다.
	var keys_off: Array = _npcsys._event_keys(id)
	assert(not ("festival" in keys_off) and not ("festival.star" in keys_off), "축제 밖인데 축제 풀이 후보에 남음: %s" % str(keys_off))
	assert(_npcsys._dialogue_line(id) in _union_pool(id, _npcsys._ambient_keys(id)), "축제 밖 = 상시 풀에서 나온다")

	# ── H-2: 겨울 등불 축제(D10 19:00~22:00) + 장식 생성
	GameClock.abs_day = 3 * GameClock.DAYS_PER_SEASON + 9     # winter D10
	GameClock.game_min = 1170  # 19:30
	fest.evaluate()
	assert(_npcsys._festival_active and _npcsys._festival_id == "festival.lantern", "등불 축제 활성")
	assert(fest._decor != null and fest._decor.get_child_count() == 8, "등불 장식 8기둥")
	GameClock.game_min = 1320  # 22:00 = end_min
	fest.evaluate()
	assert(not _npcsys._festival_active, "등불 축제 종료")

	# ── 가을 수확제(D15 낮) + 수확 장식
	GameClock.abs_day = 2 * GameClock.DAYS_PER_SEASON + 14     # autumn D15
	GameClock.game_min = 720
	fest.evaluate()
	assert(_npcsys._festival_active and _npcsys._festival_id == "festival.harvest", "수확제 활성")
	assert(fest._decor != null and fest._decor.get_child_count() == 8, "수확 장식 8궤짝")

	# ── 시간창 경계 (start_min 직전=밖, start_min=안, end_min 직전=안, end_min=밖)
	for fid in GameData.calendar:
		var f: Dictionary = GameData.calendar[fid]
		GameClock.abs_day = GameData.SEASON_IDS.find(String(f["season"])) * GameClock.DAYS_PER_SEASON + int(f["day"]) - 1
		GameClock.game_min = int(f["start_min"]) - 1
		assert(fest._festival_now() == "", "%s 시작 1분 전 = 창 밖" % fid)
		GameClock.game_min = int(f["start_min"])
		assert(fest._festival_now() == fid, "%s 시작 시각 = 창 안" % fid)
		GameClock.game_min = int(f["end_min"]) - 1
		assert(fest._festival_now() == fid, "%s 종료 1분 전 = 창 안" % fid)
		GameClock.game_min = int(f["end_min"])
		assert(fest._festival_now() == "", "%s 종료 시각 = 창 밖" % fid)
		# 하루 전날은 같은 시각이어도 축제 아님 (날짜 파생 확인)
		GameClock.abs_day -= 1
		GameClock.game_min = int(f["start_min"])
		assert(fest._festival_now() == "", "%s 전날은 축제 아님" % fid)

	# ── 결혼식 회피: 4개 축제일 전부에서 하루 미룸 (광장 이중 예약 방지)
	for fid in GameData.calendar:
		var f: Dictionary = GameData.calendar[fid]
		var fd := GameData.SEASON_IDS.find(String(f["season"])) * GameClock.DAYS_PER_SEASON + int(f["day"]) - 1
		var moved: int = _npcsys.wedding_day_for(fd)
		assert(moved != fd, "%s 축제일 결혼식 회피" % fid)
		assert(GameData.festival_on(GameData.SEASON_IDS[GameClock.season_at(moved)], GameClock.day_of_season_at(moved)).is_empty(), "%s 회피한 날도 축제 아님" % fid)
		assert(_npcsys.wedding_day_for(fd - 1) == fd - 1, "%s 전날은 그대로" % fid)
	# 계절 말일 예약: 축제가 없는 날이므로 계절 경계를 넘겨 밀지 않는다
	for s in 4:
		var last := (s + 1) * GameClock.DAYS_PER_SEASON - 1
		assert(_npcsys.wedding_day_for(last) == last, "계절 %d 마지막 날 결혼식은 그대로" % s)

	# 후속 테스트를 위해 시계를 원래 종료 상태(봄 D15 22:00)로 되돌린다
	GameClock.abs_day = 14
	GameClock.game_min = 1320
	fest.evaluate()
	_npcsys.snap_to_schedule()

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
	# ── 하객 2열 배치(순수 함수): 서로 안 겹치고 전원 집합 반경 안
	var cn := GameData.npcs.size()
	var slots := []
	for i in cn:
		slots.append(_npcsys.fest_slot(i, cn, _npcsys.WEDDING_PLAZA, _npcsys.WEDDING_PLAZA + Vector2(0, 5)))
	for i in cn:
		var si: Vector2 = slots[i]
		assert(_npcsys.WEDDING_PLAZA.distance_to(si) < _npcsys.FEST_RING + 0.5, "하객이 집합 반경 밖 (%s)" % si)
		for j in range(i + 1, cn):
			assert(si.distance_to(slots[j]) > 1.0, "하객 관통 (%d-%d, %.2f)" % [i, j, si.distance_to(slots[j])])
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
	# married* 전체를 인정한다 — 부부 인사도 계절 변형이 있다(두 줄에 갇히지 않게).
	# 계약은 "배우자는 부부 대사를 한다"이지 "그 두 줄만 한다"가 아니다.
	var found := false
	for key in GameData.dialogues["cheerful"]:
		if not String(key).begins_with("married"):
			continue
		for line in GameData.dialogues["cheerful"][key]:
			if String(line) in String(t["msg"]):
				found = true
	assert(found, "배우자는 부부 대사: %s" % t["msg"])
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

# ── UI 스킨: 밝은 패널로 바꿀 때 글자색을 같이 안 바꾸면 글자가 사라진다 ──
# 킷 UI는 vendor(재배포 금지·비상업)라 gitignore다 → 클론엔 파일이 없다. 두 경로를 모두 핀한다.
func _test_ui_panel_skin() -> void:
	var H := preload("res://ui/hud.gd")
	var p := PanelContainer.new()
	H.style_panel(p)
	var sb := p.get_theme_stylebox("panel")
	if H.ui_texture() == null:
		assert(sb is StyleBoxFlat, "에셋 없는 클론에서 폴백이 옛 패널이 아니다")
		p.free()
		return
	assert(sb is StyleBoxTexture, "킷 시트가 있는데 패널이 옛 단색이다")
	assert((sb as StyleBoxTexture).region_rect == H.UI_PANEL_RECT, "패널 타일 좌표가 어긋남")
	assert(p.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "픽셀아트가 선형 보간으로 뭉개진다")
	assert(p.theme != null, "밝은 패널인데 글자색 테마가 없다")
	# 규약의 **전제**부터 확인한다: 그 타일이 실제로 밝은가. 시트에서 어두운 타일을 집어오면
	# "글자는 어두워야 한다"는 규칙 자체가 뒤집히므로, 상수만 비교하는 핀은 그걸 못 잡는다.
	var img := H.ui_texture().get_image()
	var bg := img.get_pixel(int(H.UI_PANEL_RECT.position.x + 9), int(H.UI_PANEL_RECT.position.y + 14))
	assert(bg.a > 0.9 and bg.get_luminance() > 0.6, "패널 타일이 밝은 크림이 아니다 — 글자색 규칙의 전제가 깨졌다 (%s)" % str(bg))
	var fg: Color = p.theme.get_color("font_color", "Label")
	assert(bg.get_luminance() - fg.get_luminance() > 0.4,
		"패널과 글자의 명도차 부족 — 크림 위 흰 글자로 사라진다 (%.2f vs %.2f)" % [bg.get_luminance(), fg.get_luminance()])
	# 버튼까지 같이 갈려야 한다. 배경만 크림으로 바꾸면 기본 테마의 어두운 회색 버튼이 남아
	# 목록 행이 검은 띠로 박힌다(실측 ui2b/ui_inventory 1차).
	assert(p.theme.get_stylebox("normal", "Button") is StyleBoxTexture, "버튼이 기본 테마 회색 그대로다")
	assert(H.accent_color().get_luminance() < bg.get_luminance() - 0.2,
		"선택 강조색이 크림 패널 위에서 안 읽힌다 (%.2f)" % H.accent_color().get_luminance())
	p.free()

# ── 나뭇결: "색이 곧 재질" 규약이 실제로 세 파일 전부에 걸려 있는가 ──
# 유저 지시: "나무 의자면 나무의 결대로 자른 나무의자니까 나이테가 있어야겠지".
# 재질 선택을 호출부에 맡기지 않고 **색으로** 거는 이유가 여기 있다 — 목재 조각은 world/decor/
# beach 세 파일에 흩어져 있어서, 새로 만드는 조각이 조용히 민 갈색으로 빠지는 게 진짜 위험이다.
func _test_wood_grain() -> void:
	var W := preload("res://world/world.gd")
	var D := preload("res://world/decor.gd")
	var B := preload("res://world/beach.gd")
	# 팔레트 복제본이 갈리면 목재가 통째로 단색으로 빠진다(조용히, 에러 없이)
	assert(ToonCharacter.WOOD_C == W.C_WOOD and ToonCharacter.WOOD_D == D.C_WOOD_D,
		"ToonCharacter 목재 팔레트가 world/decor와 어긋남")
	# 결 축 = 최장변 (실제 제재목이 켜지는 방향)
	var dirs := {
		Vector3(0.9, 1.8, 0.12): Vector3.UP,     # 문
		Vector3(2.4, 0.09, 0.06): Vector3.RIGHT, # 울타리 레일
		Vector3(0.1, 0.1, 3.0): Vector3.BACK,    # 부두 널
	}
	for sz in dirs:
		var m := ToonCharacter.solid_or_wood(W.C_WOOD, sz, 0.004)
		assert(m.shader == ToonCharacter.WOOD, "목재 색인데 나뭇결 셰이더가 아님 (%s)" % str(sz))
		assert(m.get_shader_parameter("grain_dir") == dirs[sz], "결 축이 최장변이 아님 %s → %s" % [str(sz), str(m.get_shader_parameter("grain_dir"))])
	# 목재가 아닌 색은 옛 경로 그대로 (전역 회귀 방지)
	assert(ToonCharacter.solid_or_wood(W.C_STONE, Vector3.ONE, 0.0).shader == ToonCharacter.TOON,
		"목재가 아닌 색까지 나뭇결을 받는다")

	# ── 실경로: 세 파일의 _box가 실제로 그 재질을 칠하는가 (상수만 보는 핀은 _box가
	# make_solid로 되돌아가도 통과한다 — D9 교훈)
	var wn: Node3D = W.new()
	var hw := Node3D.new()
	wn.add_child(hw)
	assert((wn._box(hw, Vector3.ZERO, Vector3(0.9, 1.8, 0.12), W.C_WOOD, 0.004).material_override as ShaderMaterial).shader == ToonCharacter.WOOD, "world.gd _box가 목재에 단색을 칠한다")
	assert((wn._cyl(hw, Vector3.ZERO, 0.15, 2.0, W.C_WOOD, 0.0).material_override as ShaderMaterial).shader == ToonCharacter.WOOD, "world.gd _cyl이 목재에 단색을 칠한다")
	# 납작한 원통(수레바퀴 r0.36×h0.1)도 결은 로컬 Y여야 마구리에 나이테가 뜬다 — 최장변
	# 규칙을 원통에 그대로 쓰면 여기서 가로축이 골라진다(그럼 바퀴 옆면에만 줄이 간다).
	var wheel := (wn._cyl(hw, Vector3.ZERO, 0.36, 0.1, W.C_WOOD, 0.0).material_override as ShaderMaterial)
	assert(wheel.get_shader_parameter("grain_dir") == Vector3.UP, "납작한 목재 원통의 결 축이 Y가 아니다 (%s)" % str(wheel.get_shader_parameter("grain_dir")))
	wn.free()
	var dn: Node3D = D.new()
	var hd := Node3D.new()
	dn.add_child(hd)
	assert((dn._box(hd, Vector3.ZERO, Vector3(1.5, 0.44, 0.9), D.C_WOOD, 0.004).material_override as ShaderMaterial).shader == ToonCharacter.WOOD, "decor.gd _box가 목재에 단색을 칠한다")
	dn.free()
	var bn: Node3D = B.new()
	assert((bn._box_at(Vector3.ZERO, Vector3(0.9, 1.8, 0.12), D.C_WOOD, 0.004).material_override as ShaderMaterial).shader == ToonCharacter.WOOD, "beach.gd _box_at이 목재에 단색을 칠한다")
	bn.free()

func _test_forage_rare() -> void:
	var FS := preload("res://forage/forage_system.gd")
	assert(FS.pick_rare(false, 12345, ["forage.morel"]) == "", "근거리는 희귀 없음")
	assert(FS.pick_rare(true, 12345, []) == "", "희귀풀 없으면 없음")
	# 원거리 + 밴드 안: (1500/100)%100=15 < 20 → morel
	assert(FS.pick_rare(true, 1500, ["forage.morel"]) == "forage.morel", "원거리 희귀밴드 → morel")
	# 원거리지만 밴드 밖: (9500/100)%100=95 → 일반
	assert(FS.pick_rare(true, 9500, ["forage.morel"]) == "", "원거리라도 밴드밖 → 일반")
	assert(GameData.forage["forage.morel"].get("rare", false), "morel = 희귀 플래그")

# ── 채집물 겉모습: 종 구분 + 겨울 가독 (forage.json이 단일 출처) ────
# 옛 판은 전 종이 같은 초록 구체라 6종이 화면에서 하나로 보였고, 그 초록이 설원 위에서 형광
# 점으로 떴다. 값 자체가 아니라 **구분되는가·설원에서 읽히는가**를 핀한다.
func _test_forage_look() -> void:
	var PS := preload("res://common/plant_shapes.gd")  # 원형 표·생성기는 밭 작물과 공용
	var W := preload("res://world/world.gd")
	var seen := {}
	for fid in GameData.forage:
		var d: Dictionary = GameData.forage[fid]
		assert(d.has("color"), "%s — 겉모습 색 미지정(엔진 폴백에 기대면 종이 다시 뭉친다)" % fid)
		var c := Color.from_string(String(d["color"]), Color.BLACK)
		assert(c != Color.BLACK, "%s — color 파싱 실패: %s" % [fid, str(d["color"])])
		# 정오 직광면 클리핑 천장(지면 핀과 같은 0.75). 넘으면 색상이 화면에서 순백으로 날아간다 —
		# 실측 forage_look/crop_spring2: 크림색(#e3ddc4) 무 뿌리가 흙길 위 흰 공으로 찍혔다.
		assert(maxf(maxf(c.r, c.g), c.b) <= 0.75, "%s — 색이 정오 클리핑 천장 초과: %s" % [fid, str(d["color"])])
		# 메시를 쓰는 종은 킷 접두어가 표에 있어야 한다(오타면 조용히 구체로 폴백해 버린다)
		var mp := String(d.get("mesh", ""))
		if mp != "":
			var parts := mp.split("/", false, 1)
			assert(parts.size() == 2 and PS.KIT_DIR.has(parts[0]), "%s — 알 수 없는 킷 경로: %s" % [fid, mp])
			var full: String = PS.KIT_DIR[parts[0]] + parts[1] + ".gltf"
			# 런타임 GLTFDocument 로드라 임포트 리소스가 아니다 → 파일 존재로 본다
			assert(FileAccess.file_exists(full), "%s — 킷 메시 없음: %s" % [fid, mp])
			# 배경 식생과 같은 메시를 쓰면 채집물이 데코에 위장된다(PS.KIT_DIR 주석의 실측).
			var D2 := preload("res://world/decor.gd")
			assert(not full.begins_with(D2.TT_PARK), "%s — 파크 킷은 데코 배경 어휘다: %s" % [fid, mp])
			assert(not D2.FLORA_SCALE.has(parts[1]), "%s — 데코가 흩뿌리는 종과 같은 메시: %s" % [fid, mp])
		# ── 구체 폴백 금지. 이 작업의 핵심 계약이다: 16종 중 14종이 형태 미지정이라 조용히 색
		# 구체로 떨어져 있었다(주우러 다니는 대상이 떠 있는 공). 새 종을 넣고 형태를 안 줘도
		# 같은 일이 다시 조용히 벌어지므로 데이터 쪽에서 막는다.
		var shp := String(d.get("shape", ""))
		assert(mp != "" or shp != "", "%s — 겉모습 형태 미지정: 킷 mesh도 절차 shape도 없다 = 색 구체로 떨어진다" % fid)
		if shp != "":
			assert(PS.SHAPES.has(shp), "%s — 모르는 절차 원형: %s" % [fid, shp])
		# 종끼리 색이 붙어 있으면 구분이 안 된다 — 어느 한 채널이라도 0.08은 벌어져야
		for prev in seen:
			var p: Color = seen[prev]
			var gap := maxf(maxf(absf(c.r - p.r), absf(c.g - p.g)), absf(c.b - p.b))
			assert(gap >= 0.08, "%s와 %s 색이 붙어 구분 불가 (최대 채널차 %.3f)" % [fid, prev, gap])
		seen[fid] = c
		# 겨울 채집물은 설원(C_SNOW) 위에 놓인다 = 확실히 어둡고 따뜻해야 실루엣이 남는다.
		if d["seasons"] == ["winter"]:
			assert(c.g <= W.C_SNOW.g - 0.05, "%s — 설원 위에서 명도가 붙는다 (%.3f vs 눈 %.3f)" % [fid, c.g, W.C_SNOW.g])
			assert(c.r > c.b, "%s — 겨울 채집물이 차가운 색이면 눈·얼음 조각으로 읽힌다" % fid)

	# ── 실경로: **스폰된 노드**가 그 색을 실제로 쓰는가 ──────────────
	# 위까지는 json만 읽는다 = _spawn을 옛 초록 구체 한 줄로 되돌려도 전부 통과한다(Codex 지적).
	# 데이터와 화면 사이의 배선을 여기서 끊어본다.
	var fs2: Node = preload("res://forage/forage_system.gd").new()
	for sea in [0, 1, 2, 3]:  # 네 계절 전부 — 한 계절이라도 0종이면 그 계절 채집이 통째로 없다
		GameClock.abs_day = sea * GameClock.DAYS_PER_SEASON + 5
		fs2._respawn()
		assert(not fs2._roots.is_empty(), "계절 %d에 채집물이 스폰되지 않아 실경로를 못 본다" % sea)
		for r in fs2._roots:
			var fid2 := ""
			for c2 in (r as Node).get_children():
				if c2 is Area3D and c2.has_meta("forage_id"):
					fid2 = String(c2.get_meta("forage_id"))
			assert(fid2 != "", "채집물 루트에 forage_id가 없다")
			var want := Color.from_string(String(GameData.forage[fid2]["color"]), Color.BLACK)
			var got := _look_color(r)
			assert(got.is_equal_approx(want), "%s 스폰 노드 색이 데이터와 다름 (%s vs %s)" % [fid2, str(got), str(want)])

	# ── 도감 도달성: 한 계절을 통째로 돌면 그 계절 전 종이 최소 1회는 나온다.
	# 희귀종은 원거리 지점(REMOTE_IDX)에서만 뽑히므로, 데이터에 있어도 화면에 영영 안 나올 수
	# 있다 — 그러면 도감이 설계상 완성 불가가 된다(장기 동기가 조용히 죽는다). 종수가 아니라
	# **배치 알고리즘을 통과하는가**를 본다.
	for sea2 in GameData.SEASON_IDS.size():
		var want_ids := GameData.season_filter(GameData.forage, GameData.season_id(sea2))
		var got_ids := {}
		for day in GameClock.DAYS_PER_SEASON:
			GameClock.abs_day = sea2 * GameClock.DAYS_PER_SEASON + day
			fs2._respawn()
			for r2 in fs2._roots:
				for c3 in (r2 as Node).get_children():
					if c3 is Area3D and c3.has_meta("forage_id"):
						got_ids[String(c3.get_meta("forage_id"))] = true
		for fid3 in want_ids:
			assert(got_ids.has(fid3), "%s — %s 한 계절(%d일) 내내 한 번도 안 나옴 = 도감 완성 불가"
				% [fid3, GameData.season_id(sea2), GameClock.DAYS_PER_SEASON])
	fs2.free()

	# ── 실경로 실측: _look()이 종마다 **실제로 만드는 노드를 자로 잰다** ────────────
	# 위 블록들은 json을 읽거나 색만 본다 = 형태 배선이 통째로 끊겨도 통과한다. 어제 세 번
	# 겪은 구멍(02b11cd·99e89ac·e1c0540)이 정확히 이 모양이었다 — 인자 사본을 재거나 통로만
	# 모아 놓고 값을 안 재면 프로덕션이 되돌아가도 핀이 안 문다. 여기선 프로덕션 _look을 부른다.
	var TC := preload("res://common/toon_character.gd")
	var fs3: Node = preload("res://forage/forage_system.gd").new()
	var proc_w := []   # 절차 원형의 폭 — 실루엣이 갈리는지 재는 축
	var forms := {}
	for fid4 in GameData.forage:
		var d4: Dictionary = GameData.forage[fid4]
		var nd: Node3D = fs3._look(fid4, d4.get("rare", false))
		# 색 구체 폴백을 탔는가. 절차 원형은 SurfaceTool로 구운 ArrayMesh라 SphereMesh가 아니다.
		assert(not (nd is MeshInstance3D and (nd as MeshInstance3D).mesh is SphereMesh),
			"%s — 색 구체 폴백을 탔다: 형태 지정이 실경로에 안 닿는다" % fid4)
		var ab := TC.aabb_of(nd)
		# 접지: 밑동이 y=0. 구체 시절엔 중심 피벗이라 띄워 놨는데, 킷·절차는 바닥 기준이다.
		# 킷 포도 송이가 원점 아래로 0.069 늘어져 땅에 묻혀 있었다(실측) — 그 회귀를 여기서 문다.
		assert(absf(ab.position.y) <= 0.02, "%s — 밑동이 지면에서 %+.3f (묻히거나 떴다)" % [fid4, ab.position.y])
		# 전고는 LOOK_H 대역. 벗어나면 줍는 반경(0.9)과의 관계가 깨지고 원거리 가독도 흔들린다.
		assert(ab.size.y >= 0.34 and ab.size.y <= 0.52,
			"%s — 전고 %.3f가 LOOK_H(%.2f) 대역 밖" % [fid4, ab.size.y, PS.LOOK_H])
		# 0.80은 킷 메시(송이 0.734)를 안 물었다 — 절차 원형 최대 0.474 언저리인 0.55로 조인다.
		assert(maxf(ab.size.x, ab.size.z) <= 0.55, "%s — 폭 %.3f: 줍는 반경만큼 퍼졌다" % [fid4, maxf(ab.size.x, ab.size.z)])
		var shp4 := String(d4.get("shape", ""))
		# **실제로 절차 원형으로 그려진 종만** 담는다. json에 shape가 있다는 것만으로는 부족하다:
		# 킷을 쓰는 두 종도 휴면·에셋 누락 폴백용 shape를 갖게 됐고(2026-08-31), 제철엔 킷 경로를
		# 타므로 여기 담기는 ab는 **킷 치수**다. 그대로 두면 아래 두 핀이 조용히 헐거워진다 —
		# 폭 상한 LOOK_W(0.52)에 붙은 킷 둘이 최댓값을 받쳐 주니 절차 원형들이 실제로 한 실루엣으로
		# 뭉쳐도 폭 비율이 안 물고, 화면에 한 번도 안 그려지는 계열이 forms에 등록돼 계열 수도 분다.
		# 절차 원형은 MeshInstance3D 한 장이고 킷은 노드 묶음이다(색 구체 폴백은 위에서 걸렀다).
		if shp4 != "" and nd is MeshInstance3D:
			proc_w.append(maxf(ab.size.x, ab.size.z))
			forms[String(PS.SHAPES[shp4][0])] = true
		nd.free()
	# 원형끼리 실루엣이 갈리는가. 전고는 다 같은 대역이니 **폭**이 가르는 축이다.
	# 실측(2026-08-31, 절차로 그려지는 14종만): 0.132(이삭 꽃대)~0.386(낮고 퍼진 잎다발) = 2.91배.
	# 킷 2종(둘 다 상한 0.520)을 섞어 세던 옛 판은 3.94배로 읽혀 문턱이 저절로 넉넉했다.
	proc_w.sort()
	assert(proc_w.size() >= 12, "절차 원형으로 그려지는 종이 %d개뿐 — 나머지는 킷이거나 구체다" % proc_w.size())
	assert(proc_w[-1] / proc_w[0] >= 1.8,
		"채집물 폭이 %.2f배밖에 안 갈린다 = 색만 다른 같은 실루엣" % (proc_w[-1] / proc_w[0]))
	assert(forms.size() >= 4, "형태 계열이 %d종뿐 — 14종이 한두 실루엣으로 뭉친다" % forms.size())
	# 원형 표에 사본이 있으면 두 종이 "색만 다른 같은 물건"이 된다
	var sk: Array = PS.SHAPES.keys()
	for i in sk.size():
		for j in range(i + 1, sk.size()):
			assert(PS.SHAPES[sk[i]] != PS.SHAPES[sk[j]], "형태 원형 %s와 %s가 같은 파라미터" % [sk[i], sk[j]])
	# 메시 캐시: 한 종이 여러 지점에 스폰돼도 메시는 한 장 (decor._flora_cache 규약)
	var any_shape := ""
	for fid5 in GameData.forage:
		if GameData.forage[fid5].has("shape"):
			any_shape = fid5
			break
	var c1: Node3D = fs3._look(any_shape, false)
	var c2: Node3D = fs3._look(any_shape, false)
	assert((c1 as MeshInstance3D).mesh == (c2 as MeshInstance3D).mesh,
		"%s — 스폰마다 형태 메시를 새로 깎는다(종당 1장 캐시 계약)" % any_shape)
	c1.free()
	c2.free()
	# 킷 메시(gltf)도 같은 계약이다. 캐시가 빠지면 build마다 GLTFDocument로 파일을 다시 읽는데,
	# 그건 화면에선 안 보이고 호출 빈도가 오를 때(도감 아이콘) 조용히 비싸진다 — 값으로 문다:
	# 두 번 만든 노드가 **같은 Mesh 인스턴스**를 쥐고 있으면 파일을 한 번만 읽은 것이다.
	var any_kit := ""
	for fid7 in GameData.forage:
		if GameData.forage[fid7].has("mesh"):
			any_kit = fid7
			break
	assert(any_kit != "", "킷 메시를 쓰는 종이 없다 — 이 핀이 아무것도 안 잰다")
	var k1: Node3D = fs3._look(any_kit, false)
	var k2: Node3D = fs3._look(any_kit, false)
	var km1 := _first_mesh(k1)
	var km2 := _first_mesh(k2)
	assert(km1 != null and not (km1 is SphereMesh),
		"%s — 킷 로드가 실패해 구체 폴백으로 떨어졌다" % any_kit)
	assert(km1 == km2, "%s — 킷 메시를 만들 때마다 gltf를 다시 읽는다(종당 1회 캐시 계약)" % any_kit)
	k1.free()
	k2.free()
	fs3.free()
	# 형태 배정이 **데이터에서** 오는가. 엔진에 종 이름이 박히면 종이 늘 때마다 엔진을 고치게 되고
	# 그게 이 저장소의 단일 출처 규약이 무너지는 지점이다(color·mesh가 이미 그 규약을 지킨다).
	for path in ["res://forage/forage_system.gd", "res://common/plant_shapes.gd"]:
		var src := FileAccess.get_file_as_string(path)
		for fid6 in GameData.forage:
			var bare: String = fid6.get_slice(".", 1)
			assert(not src.contains(bare), "%s에 종 이름이 하드코딩됐다: %s" % [path, bare])

# 스폰된 채집물 노드가 화면에 내는 색. 세 경로다 — 구체는 material_override의 albedo,
# 킷 메시는 surface override의 char_tint(아틀라스 곱), 절차 원형은 **메시 표면 0**에 구운
# albedo(표면 1은 곁들이 고정색이라 종 색이 아니다). 먼저 잡히는 것.
func _look_color(node: Node) -> Color:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var m := mi.material_override as ShaderMaterial
		if m != null:
			return m.get_shader_parameter("albedo")
		for i in mi.get_surface_override_material_count():
			var sm := mi.get_surface_override_material(i) as ShaderMaterial
			if sm != null:
				return sm.get_shader_parameter("char_tint")
		if mi.mesh != null and mi.mesh.get_surface_count() > 0:
			var pm := mi.mesh.surface_get_material(0) as ShaderMaterial
			if pm != null:
				return pm.get_shader_parameter("albedo")
	for c in node.get_children():
		var r := _look_color(c)
		if r != Color.BLACK:
			return r
	return Color.BLACK

# ── 겨울 표현 패스: 채집물 2종 + 지면/식생 계절 파생 ────────────────
func _test_winter_pass() -> void:
	# ── 계절 커버리지. **옛 핀은 "여름·가을 채집물 0종"을 계약으로 못박고 있었다** — 구멍을
	# 고정한 핀이라, 여름에 들에 나가도 주울 게 하나도 없는 상태가 테스트 통과였다. 이제는
	# 종수를 세지 않고 "어느 계절이든 일반 스폰이 존재한다"를 본다(종수는 늘 수 있으니).
	for s in GameData.SEASON_IDS:
		var pool := GameData.season_filter(GameData.forage, s)
		assert(not pool.is_empty(), "%s 채집물 0종 — 그 계절 채집이 통째로 없다" % s)
		var common := 0
		for fid in pool:
			if not GameData.forage[fid].get("rare", false):
				common += 1
			assert(GameData.is_collectible(fid), "%s 도감·판매 대상" % fid)
		# 희귀만 있으면 원거리 지점 밖은 전부 빈손이다(_respawn의 common_pool 폴백이 죽는다)
		assert(common > 0, "%s 채집물이 희귀뿐 — 일반 스폰 지점이 전부 빈다" % s)
	# 겨울은 작물이 0인 계절이라 채집이 유일한 육상 산출 — 봄 하위종보단 비싸게, 희귀는 없이.
	var win := GameData.season_filter(GameData.forage, "winter")
	for fid in win:
		var d: Dictionary = GameData.forage[fid]
		assert(d["seasons"] == ["winter"], "%s 겨울 전용 (실제 %s)" % [fid, str(d["seasons"])])
		var sp := GameData.sell_price(fid)
		assert(sp >= 35 and sp <= 90, "%s 판매가 대역 밖: %d" % [fid, sp])
		assert(not d.get("rare", false), "%s — 겨울 풀엔 희귀 없음(원거리도 일반 스폰)" % fid)

	# ── 리스폰 결정성: 같은 겨울날 두 번 = 같은 배치 (씬 트리 없이 _respawn 직접 호출)
	var fs: Node = preload("res://forage/forage_system.gd").new()
	GameClock.abs_day = 3 * GameClock.DAYS_PER_SEASON + 5  # 겨울 6일차
	assert(GameData.season_id(GameClock.season()) == "winter", "전제: 겨울")
	fs._respawn()
	var snap_a := _forage_snapshot(fs)
	fs._respawn()
	var snap_b := _forage_snapshot(fs)
	assert(not snap_a.is_empty(), "겨울날에 채집물이 실제로 스폰 (%d)" % snap_a.size())
	assert(snap_a == snap_b, "겨울 채집 배치 비결정적\n  %s\n  %s" % [str(snap_a), str(snap_b)])
	for e in snap_a:
		assert(e[1] in win, "겨울에 비겨울 채집물 스폰: %s" % str(e[1]))
	fs.free()

	# ── 지면·식생 계절 파생 (순수 함수 — 노드·렌더 없이 검증)
	var W := preload("res://world/world.gd")
	var D := preload("res://world/decor.gd")
	# 하네스 감지 = 세이브 쓰기 차단의 유일한 관문. 옛 판은 하네스마다 개별로 막다가 `shot` 계열을
	# 빠뜨렸다(오염 통로가 조용히 열려 있었다). 규칙은 "유저 args가 하나라도 있으면 하네스".
	assert(not W.harness_mode(PackedStringArray([])), "인자 없음 = 실제 플레이 = 세이브 정상 동작")
	for _a in [["shot"], ["shot", "npcs"], ["v_houses"], ["hour", "12"], ["weather", "clear"]]:
		assert(W.harness_mode(PackedStringArray(_a)), "하네스 %s = 세이브 쓰기 차단 대상" % [_a])
	assert(W.ground_color(3) == W.C_SNOW, "겨울 지면 = 눈 톤")
	assert(W.C_SNOW.r < 1.0 and W.C_SNOW.b > W.C_SNOW.r, "눈 톤 = 순백 아닌 차가운 근백색")
	# 옛 핀은 `for s in 3: ground_color(s) == C_GRASS` = **"봄·여름·가을 지면 무변경"을 계약으로
	# 박아** 계절 구멍 자체를 고정하고 있었다(HUD 글자만 바뀌는 상태가 테스트로 승인돼 있었다).
	# 뒤집는다: 봄은 승인값 그대로 두되, 네 계절이 서로 다른 값이어야 한다.
	assert(W.ground_color(0) == W.C_GRASS, "봄 지면 = 승인된 초지 톤(값 이동 금지)")
	var seen_ground := []
	for s in 4:
		var gsc: Color = W.ground_color(s)
		assert(not (gsc in seen_ground), "계절 %d 지면색이 앞 계절과 같다 — 화면에서 계절이 안 읽힌다" % s)
		seen_ground.append(gsc)
	# 정오 직광면은 albedo 0.75 위에서 255로 포화한다(실측). 포화하면 풀 패턴·곡률 음영이
	# 통째로 날아가므로 지면 계열 채널 상한을 테스트로 못박는다. 상한을 0.76→0.75로 조인 근거:
	# 0.76은 "클리핑 직전"이 아니라 실측에서 이미 B가 255였다(눈 지면 (241,247,255)).
	# 툰 light()는 ndl을 smoothstep(0.32,0.68)에 통과시키므로 정오 직광에서 수평 지면(ndl 0.89)과
	# 수직 벽면(ndl 0.81)이 **둘 다 shade=1.0** = 같은 전달함수다. 그래서 이 상한은 지면만의
	# 사정이 아니라 정오 직광면 전체의 화면 천장이고, 아래 실루엣 핀이 그 사실 위에 선다.
	const CLIP_ALBEDO := 0.75
	var B2 := preload("res://world/beach.gd")  # 해변 모래도 같은 수평 지면 = 같은 상한을 받는다
	# 지면·길·길가장자리는 상수 목록이 아니라 **순수 함수로 훑는다** — 계절이나 색을 추가해도
	# 여기 적는 걸 잊고 클리핑하는 값이 화면에 나가는 일이 없다(옛 목록판은 실제로 그 구조였다).
	var clip_colors := [W.C_GREEN, B2.C_SAND, B2.C_WET]
	for s in 4:
		clip_colors.append_array([W.ground_color(s), W.road_color(s), W.road_edge_color(s)])
	for gc in clip_colors:
		assert(maxf(maxf(gc.r, gc.g), gc.b) <= CLIP_ALBEDO, "지면/길 albedo가 정오 클리핑 한계 초과: %s" % gc)
	# ── 여름·가을 지면 처방 ──────────────────────────────────────────
	# 여름은 봄보다 짙고(명도↓) 채도가 한 단 위다. 밝기로 무성함을 내면 G가 255로 포화해
	# 풀 패턴이 통째로 날아간다(C_GRASS 주석의 실측) — 무성함은 ground_pattern이 낸다.
	assert(W.C_GRASS_S.s > W.C_GRASS.s and W.C_GRASS_S.v < W.C_GRASS.v,
		"여름 초지가 봄보다 짙고 진하지 않다: %s" % str(W.C_GRASS_S))
	# 가을은 마르되 죽지 않는다: G가 여전히 최대 채널이어야 초록기가 남는다(다 빼면 죽은 땅).
	assert(W.C_GRASS_A.g > W.C_GRASS_A.r and W.C_GRASS_A.g > W.C_GRASS_A.b,
		"가을 초지에서 초록기가 통째로 빠졌다 = 죽은 땅: %s" % str(W.C_GRASS_A))
	assert(W.C_GRASS_A.r / W.C_GRASS_A.g > W.C_GRASS.r / W.C_GRASS.g, "가을 초지가 봄보다 노랗지 않다")
	assert(W.C_GRASS_A.v < W.C_GRASS.v, "가을 초지가 봄보다 밝다 — 마른 풀이 아니다")
	# 가을 길이 가을 지면에 먹히면 길이 화면에서 사라진다 — 둘 다 노란 대역이라 실제 위험이다.
	# 지면은 G가 최대(위 핀), 길은 R이 최대 = hue 방향이 반대여야 띠로 읽힌다.
	assert(W.C_ROAD_A.r > W.C_ROAD_A.g, "가을 길이 지면과 같은 hue 방향 — 길이 마른 풀에 먹힌다")
	assert(W.C_ROAD_AE.v > W.C_ROAD_A.v and W.C_ROAD_AE.s < W.C_ROAD_A.s,
		"가을 길 가장자리는 길보다 밝고 옅게(마른 풀로 스밈) — 봄 쌍과 같은 관계")
	# 지면 패턴 정확값. 여름 무성 / 가을 성김 / 겨울 설원 요철.
	var pat := [W.ground_pattern(0), W.ground_pattern(1), W.ground_pattern(2), W.ground_pattern(3)]
	assert(pat == [1.0, 1.15, 0.85, 0.45], "지면 패턴 계절값이 바뀌었다: %s" % str(pat))
	# 길 색도 순수 함수라 노드 없이 검증된다(ground_color와 같은 이유 = 인라인 삼항 금지).
	# 봄·여름은 같은 흙이다 — 마른 흙길은 계절로 색이 안 변한다. 갈리는 건 낙엽과 눈뿐.
	assert(W.road_color(0) == W.C_ROAD and W.road_color(1) == W.C_ROAD, "봄·여름 흙길 = 승인된 C_ROAD")
	assert(W.road_color(2) == W.C_ROAD_A and W.road_color(3) == W.C_ROAD_W, "가을·겨울 길 색이 안 갈렸다")
	assert(W.road_edge_color(0) == W.C_ROAD_E and W.road_edge_color(1) == W.C_ROAD_E \
		and W.road_edge_color(2) == W.C_ROAD_AE and W.road_edge_color(3) == W.C_ROAD_WE,
		"길 가장자리 계절 색이 안 갈렸다")
	# 겨울 길은 설원보다 어두워야 길로 읽힌다(밝으면 눈에 묻히고, 여름 톤이면 설원 위 노란 띠).
	assert(W.C_ROAD_W.g < W.C_SNOW.g and W.C_ROAD_W.g > W.C_CUT.g, "겨울 길 톤이 설원↔진흙 사이가 아님")
	assert(W.C_ROAD_WE.g > W.C_ROAD_W.g, "겨울 길 가장자리는 길보다 밝게(설원으로 스밈)")
	# 겨울 실루엣: 눈 지면이 크림 벽토보다 확실히 어두워야 눈밭에서 집·판매상자 윤곽이 떠오른다.
	# **옛 핀은 `C_WALL.g - C_SNOW.g >= 0.15`였고, 통과하는데도 화면에서 실루엣이 사라졌다**
	# (실측 season_audit/winter_clear_life_h12: 지평선 설원 (228,234,245) vs 벽 (255,255,255) = 21).
	# 이유: C_WALL.g(0.844)는 CLIP_ALBEDO를 넘어 **화면에 존재하지 않는 여유**다. 0.75든 0.88이든
	# 벽은 똑같이 255로 찍히므로, 벽 albedo를 올려도 대비는 1도 안 늘고 핀만 헐거워진다.
	# 실제 여유는 `CLIP_ALBEDO - C_SNOW.g` = 0.07이었다 — 핀이 약속한 0.15의 절반 이하.
	# (0.07로도 버틴 건 외곽선이 윤곽을 그려줬기 때문이고, 2bde841이 그걸 전역 제거하면서 드러났다.)
	# 그래서 왼쪽 항을 **도달 가능한 천장**으로 바꾼다 = 눈만이 대비를 만들 수 있다는 사실을 핀한다.
	# 기준 0.15는 그대로 두되(느슨하게 하지 않는다) 이제 진짜 0.15다: 화면 실측 62레벨.
	assert(minf(W.C_WALL.g, CLIP_ALBEDO) - W.C_SNOW.g >= 0.15, "눈 지면과 벽토의 **화면** 명도차 부족 — 겨울 실루엣 소실")
	# 지붕 눈은 배경이 보라 기와라 **반대로 밝아야** 한다. 위 실루엣 처방으로 C_SNOW를 내렸을 때
	# 지붕 눈이 같은 상수를 쓰고 있어 기와와의 차가 무너졌다 — 두 눈이 갈렸다는 걸 여기서 못박는다.
	# 양변 모두 클리핑 천장을 통과시킨다: 천장 위 값끼리의 차는 화면에서 0이다(위 문단의 교훈).
	assert(minf(W.C_SNOW_ROOF.g, CLIP_ALBEDO) - minf(W.C_ROOF.g, CLIP_ALBEDO) >= 0.20,
		"지붕 눈과 기와의 화면 명도차 부족 — 지붕에 눈이 안 얹혀 보인다")
	assert(minf(W.C_SNOW_ROOF.g, CLIP_ALBEDO) > minf(W.C_SNOW.g, CLIP_ALBEDO),
		"지붕 눈이 지면 눈보다 어둡다 — 두 눈의 밝기 목표가 뒤집혔다")
	# 위 두 핀은 상수만 본다 = _roof_snow가 다시 C_SNOW를 칠해도 통과한다(Codex 지적).
	# 실경로로 확인: 트리 밖에서 world.gd 인스턴스의 _roof_snow만 호출해 칠해진 색을 읽는다
	# (_ready를 안 타므로 마을은 안 지어진다).
	var wn: Node3D = W.new()
	var holder := Node3D.new()
	wn.add_child(holder)
	wn._roof_snow(holder, Vector3.ZERO, Vector3(1, 0.09, 1))
	var rs := holder.get_child(0) as MeshInstance3D
	var rsm := rs.material_override as ShaderMaterial
	assert(rsm.get_shader_parameter("albedo") == W.C_SNOW_ROOF, "지붕 눈이 실제로는 C_SNOW_ROOF를 안 쓴다 (%s)" % str(rsm.get_shader_parameter("albedo")))
	wn.free()
	# C_FROST_LEAF / C_FROST는 더 이상 겨울 화면을 **직접 칠하지 않는다**(식생이 킷 텍스처로 바뀌면서
	# 서리톤은 sat_cap·val_gain·char_tint가 만든다). 그래서 이 핀은 이제 "옛 실측 목표값 두 개의
	# 서열"만 지킨다 = 아래 실경로 검사(_test_winter_veg_look)가 도달해야 할 과녁이 흔들리지 않게.
	# 겨울 룩 자체가 깨지는지는 이 핀이 아니라 그쪽이 잡는다.
	# 옛 판에는 `C_FROST_LEAF.g < C_SNOW.g`(수관 목표는 설원 아래)도 있었는데, 그건 **옛 설원
	# 0.68에 대한 서술**이었다. 지금 수관은 설원이 아니라 크림 하늘을 배경으로 잡히므로 실경로에서
	# 이미 설원보다 훨씬 밝고(실측 선형 0.640 vs 0.290), 설원을 내리자 그 항만 거짓이 됐다.
	# 설원과의 관계는 값이 아니라 서열로 _test_winter_veg_look ③④가 실경로에서 본다.
	assert(D.C_FROST_LEAF.g > D.C_FROST.g, "설경 서리톤 목표 서열 어긋남(수관 > 지피)")
	# 팔레트 단일 출처: decor.gd는 순환 preload를 피해 마을 팔레트를 복제한다(beach.gd가 이걸
	# 재사용한다). 값이 갈라지면 존을 넘을 때 같은 소재가 다른 색으로 보인다.
	assert(D.C_WOOD == W.C_WOOD and D.C_CREAM == W.C_WALL and D.C_ROOF == W.C_ROOF \
		and D.C_STONE == W.C_STONE and D.C_GREEN == W.C_GREEN and D.C_WIST == W.C_WIST,
		"decor.gd 팔레트가 world.gd와 어긋남")
	# 버킷 이름 = 킷 파일명(decor.FLORA_SCALE / TREE_KIT 키)이다 — 이름이 어긋나면 겨울 숨김·서리가
	# 조용히 아무 버킷에도 안 걸린다. 표를 순회해 대조만 하면 **표와 구현이 같이 빠져도 통과**하므로
	# (한 종을 지우면 검사할 항목까지 같이 사라진다) 기대값을 명시 리터럴로 박고, 그 목록이 곧
	# 표의 전체 키라는 것도 함께 핀한다 = 누락·리네임 어느 쪽도 조용히 못 지나간다.
	assert(D.FLORA_SCALE.keys() == ["flower_A", "flower_B", "bush", "bush_large", "grass_A", "grass_B"],
		"식생 종 목록이 바뀌었다(겨울 규칙 검사 대상과 어긋남): %s" % str(D.FLORA_SCALE.keys()))
	assert(D.TREE_KIT.keys() == ["tree", "tree_large"], "나무 종 목록이 바뀌었다: %s" % str(D.TREE_KIT.keys()))
	assert(D.DECIDUOUS == ["Forest_tree", "Forest_tree_large"], "활엽 버킷 목록이 바뀌었다: %s" % str(D.DECIDUOUS))
	assert(D.CONIFER == ["cone_slim"], "침엽 종 목록이 바뀌었다: %s" % str(D.CONIFER))
	# 꽃은 색 변종으로 갈려 있다(같은 메시, char_tint만 다른 별개 MultiMesh) — 목록을 여기
	# 다시 적지 않고 decor의 버킷 목록에서 뽑는다. 변종을 추가하고 겨울 숨김을 잊는 게
	# 실제 실패 모드라(설원에 분홍 꽃 만개), 새 변종은 자동으로 이 검사에 걸려야 한다.
	assert(D.FLORA_BUCKETS == ["flower_A", "flower_A~white", "flower_A~pink", "flower_A~lavender",
		"flower_B", "bush", "bush_large", "grass_A", "grass_B"],
		"식생 버킷 목록이 바뀌었다(드로우콜·겨울 규칙 검사 대상): %s" % str(D.FLORA_BUCKETS))
	# 라벤더는 **마을 정체색**이다(VILLAGE_SPEC §2). 킷 전환 때 한 번 조용히 사라진 전력이
	# 있어서(노랑·분홍·흰색·파랑만 남아 "라벤더 마을"에 라벤더가 없었다) 존재를 명시로 박는다.
	# 색까지 본다: 목록에만 있고 색조표에서 빠지면 흰 데이지가 되어 화면에서 다시 사라진다.
	var lav: Color = D.FLORA_TINT.get("flower_A~lavender", D.KIT_TINT)
	assert(lav.b > lav.r and lav.r > lav.g,
		"라벤더 꽃 색조가 보라(B>R>G)가 아니다 — 마을 정체색이 다시 죽는다: %s" % str(lav))
	assert(lav.b <= 0.75, "라벤더 최대 채널이 정오 클리핑 상한(0.75)을 넘음 = 화면에서 흰 점")
	var flowers := []
	for b in D.FLORA_BUCKETS:
		assert(D.kit_of(b) in D.FLORA_SCALE, "%s 버킷의 킷 파일명이 배율표에 없음" % b)
		if b.begins_with("flower"):
			flowers.append("Flora_" + b)
	assert(flowers.size() >= 4, "꽃 종류가 4색 미만 — 화단이 단색으로 읽힌다 (%s)" % str(flowers))
	# 변종은 색이 실제로 갈려야 의미가 있다. 색조표에 없으면 KIT_TINT(킷 원본 흰 데이지)이므로
	# 같은 메시의 두 변종이 **둘 다** 표에 없으면 화면에서 완전히 같은 꽃이 된다.
	var seen_tint := {}
	for b in flowers:
		var key: String = b.trim_prefix("Flora_")
		var tn: Color = D.FLORA_TINT.get(key, D.KIT_TINT)
		var base := D.kit_of(key)
		if not seen_tint.has(base):
			seen_tint[base] = []
		assert(not (tn in seen_tint[base]), "%s가 같은 메시의 다른 변종과 색까지 같다 = 드로우콜만 늘고 화면은 그대로" % key)
		(seen_tint[base] as Array).append(tn)
	# ── 꽃 = 계절 시계 ────────────────────────────────────────────────
	# 옛 핀은 "겨울만 숨김 / 봄·여름·가을 전부 보임"을 계약으로 박아 계절 구멍을 고정하고 있었다.
	# ① 이름 정규화 단일 출처: 표 키는 접두 없는 버킷명, MultiMesh 이름엔 "Flora_" 접두가 붙는다.
	assert(D.bucket_of("Flora_flower_A~pink") == "flower_A~pink" and D.bucket_of("flower_B") == "flower_B",
		"버킷 이름 정규화(bucket_of)가 접두를 못 뗀다")
	assert(D.kit_of(D.bucket_of("Flora_flower_A~lavender")) == "flower_A",
		"접두·변종 제거 조합이 킷 파일명에 못 닿는다")
	# ② 계절표가 꽃 버킷을 빠짐없이 덮는다. 미지정으로 두면 그 꽃은 사계절 내내 조용히 사라진다
	#    (푸른 flower_B가 정확히 그 위험이었다) — 목록 대조로 누락을 시끄럽게 만든다.
	var flower_keys := []
	for b in flowers:
		flower_keys.append(D.bucket_of(b))
	assert(D.FLOWER_SEASONS.keys() == flower_keys,
		"꽃 계절표가 꽃 버킷 목록과 어긋남 (표 %s / 버킷 %s)" % [str(D.FLOWER_SEASONS.keys()), str(flower_keys)])
	for nm in flowers:
		assert(D.kit_of(D.bucket_of(nm)) in D.FLORA_SCALE, "%s 버킷이 배율표에 없음" % nm)
		assert(not D.flora_visible(nm, 3), "%s 겨울엔 숨김(설원 위 만개 금지)" % nm)
	# ③ 계절마다 최소 한 종은 핀다(겨울 제외) + ④ 세 계절의 개화 조합이 서로 다르다.
	#    ③이 빠지면 그 계절 화단이 통째로 사라지고, ④가 빠지면 꽃이 계절을 안 파는 옛 상태로 돌아간다.
	var open_sets := []
	for s in 3:
		var open_now := []
		for nm in flowers:
			if D.flora_visible(nm, s):
				open_now.append(nm)
		assert(not open_now.is_empty(), "계절 %d에 피는 꽃이 한 종도 없다 — 그 계절 화단이 사라진다" % s)
		assert(not (open_now in open_sets), "계절 %d 개화 조합이 앞 계절과 같다 = 꽃이 계절을 안 판다" % s)
		open_sets.append(open_now)
	# ⑤ 라벤더(마을 정체색)는 **여름 절정**이다 — 이랑(_lavender_rows)이 만개하는 계절이 있어야
	#    "라벤더로 먹고사는 마을"이 화면에서 성립한다. 배분을 옮길 땐 이 핀을 같이 봐야 한다.
	assert(D.flora_visible("Flora_flower_A~lavender", 1), "여름에 라벤더가 안 핀다 — 이랑이 빈 땅으로 남는다")
	# 풀·덤불은 꽃 규칙 **밖**이다 = 사계절 상주(겨울엔 서리톤). 계절표에 없다고 사라지면
	# 마을이 계절마다 민짜가 된다 — 접두 규칙이 꽃만 잡는다는 걸 네 계절 전부 확인한다.
	for nm in ["Flora_grass_A", "Flora_grass_B", "Flora_bush", "Flora_bush_large"]:
		assert(D.bucket_of(nm) in D.FLORA_SCALE, "%s 버킷이 배율표에 없음" % nm)
		assert(D.flora_visible(nm, 3) and D.flora_frosted(nm, 3), "%s 겨울엔 서리톤으로 남음" % nm)
		for s in 3:
			assert(D.flora_visible(nm, s) and not D.flora_frosted(nm, s), "%s 계절 %d엔 원색으로 상주" % [nm, s])
	assert(not D.flora_frosted("Forest_tree", 3), "나무는 flora 규칙 밖")
	# 나무는 킷 교체로 전부 활엽 — 겨울엔 전 그루가 서리톤이어야 한다(초록 나무가 남으면 계절이 안 읽힌다).
	# 위에서 목록을 리터럴로 못박았으므로 여기 순회는 더 이상 자기 자신과의 비교가 아니다.
	# 슬롯 선택은 순수 함수(tree_variant_index)다 — 옛 판은 apply_season 안의 2슬롯 삼항
	# `[1 if tree_frosted(...) else 0]`이라 슬롯이 셋이 되는 순간 조용히 깨졌다.
	# 슬롯 계약 [원색, 겨울 서리, 가을 단풍]을 여기서 못박는다.
	for nm in D.DECIDUOUS:
		assert(D.tree_variant_index(nm, 0) == 0 and D.tree_variant_index(nm, 1) == 0, "%s 봄·여름은 원색 슬롯" % nm)
		assert(D.tree_variant_index(nm, 2) == 2, "%s 가을엔 단풍 슬롯" % nm)
		assert(D.tree_variant_index(nm, 3) == 1, "%s 겨울엔 서리 슬롯" % nm)
		assert(D.tree_frosted(nm, 3), "%s 겨울엔 수관 서리톤" % nm)
		for s in 3:
			assert(not D.tree_frosted(nm, s), "%s 계절 %d엔 서리 아님" % [nm, s])
	# 단풍 사본 처방 — 잎 결을 남기려면 채도를 지우고(sat) 색은 char_tint로 준다(겨울 서리와 같은 순서).
	# tint가 주황(R>G>B)이 아니면 나무가 가을에 초록·회색으로 남고, sat을 겨울(0.06)까지 내리면
	# 수피까지 같은 색 한 덩어리가 된다.
	assert(D.TREE_AUTUMN_TINT.r > D.TREE_AUTUMN_TINT.g and D.TREE_AUTUMN_TINT.g > D.TREE_AUTUMN_TINT.b,
		"단풍 색조가 주황(R>G>B)이 아니다: %s" % str(D.TREE_AUTUMN_TINT))
	assert(D.TREE_AUTUMN_SAT > D.VEG_WINTER_SAT, "단풍 채도가 겨울 서리만큼 지워졌다 — 수관·수피가 한 덩어리")
	assert(D.LEAF_TINT.r > D.LEAF_TINT.g and D.LEAF_TINT.v < D.TREE_AUTUMN_TINT.v,
		"바닥 낙엽이 수관 단풍보다 어둡지 않다 — 나무 그늘에서 지면 잎이 떠 보인다")
	# 버킷 이름 정합: DECIDUOUS가 실제 나무 종을 빠짐없이 덮는다(리네임 회귀 방지)
	for nm in D.TREE_KIT:
		assert(("Forest_" + nm) in D.DECIDUOUS, "%s가 겨울 서리 대상에서 빠졌다" % nm)
	# 해변 해송(절차 블롭)은 마을 규칙 밖 — 겨울에도 초록으로 남는 유일한 나무다
	for nm in D.CONIFER:
		assert(nm in D.BLOB_KINDS, "%s 침엽 종이 블롭 표에 없음" % nm)
		for s in 4:  # 가을 단풍·겨울 서리 어느 쪽도 안 탄다 = 사계절 원색 슬롯
			assert(D.tree_variant_index("Forest_" + nm, s) == 0, "%s 침엽수는 계절 %d에도 원색" % [nm, s])
	# 만개(화분·꽃수레 꽃, 등나무 드레이프)는 **겨울만** 숨김이다 — 들꽃(FLOWER_SEASONS)과 달리
	# 계절로 안 나눈다는 게 명시된 정책이다: 사람이 관리하는 물건이라 계절 따라 송이가 사라지면
	# 오히려 어색하고, 들꽃이 노랑 하나로 주는 가을에 마을 안 색을 붙잡아 주는 게 이쪽이다.
	assert(not D.bloom_visible(3), "겨울엔 만개 숨김")
	for s in 3:
		assert(D.bloom_visible(s), "계절 %d엔 만개(겨울만 숨김 정책)" % s)
	# 바닥 낙엽은 가을에만 깔린다(다른 계절에 남으면 초지 위 갈색 얼룩이 된다).
	for s in 4:
		assert(D.leaf_litter_visible(s) == (s == 2), "낙엽 가시성이 가을 전용이 아님 (계절 %d)" % s)

# ══ 겨울 식생 룩 — **실제 경로**를 계산으로 검증 ═══════════════════════
# 식생이 킷 텍스처로 바뀐 뒤 겨울 룩을 만드는 것은 단색 상수(C_FROST/C_FROST_LEAF)가 아니라
#   ① 킷 아틀라스 텍셀 → ② sat_cap(채도 상한) → ③ val_gain(밝기 곱) → ④ char_tint
# 네 단계다. 그래서 상수 서열만 핀하면 gain을 1.0으로 되돌려도(= 겨울에 초록·회색 식생이 남아도)
# 아무 테스트도 안 깨진다. 여기서는 **실물 메시의 UV로 실물 아틀라스를 샘플링**해서 위 네 단계를
# 그대로 계산하고, 결과 albedo가 눈 지면(C_SNOW)에 대해 어느 대역에 앉는지를 못박는다.
# 머티리얼 파라미터는 상수가 아니라 decor가 실제로 만든 머티리얼(_frost_mat / 겨울 스왑 Mesh)에서 읽는다.
func _test_winter_veg_look() -> void:
	var W := preload("res://world/world.gd")
	var D := preload("res://world/decor.gd")
	var atlas := Image.load_from_file(D.TT_PARK + "tiny_treats_texture_1.png")
	assert(atlas != null, "파크 킷 아틀라스를 못 읽음")
	var dec: Node = D.new()
	var grass: Mesh = dec._flora_mesh("grass_A")     # 여름 원본 = 겨울에도 같은 지오메트리
	# 나무 사본은 _place_forest가 부르는 그 함수(tree_slots)로 뽑고, 슬롯은 그 계약 함수로 고른다 —
	# 인자를 여기 복사해 두면 decor의 처방이 되돌아가도 이 핀이 안 문다(02b11cd와 같은 구멍).
	var slots: Array = dec.tree_slots("tree")
	var tree_s: Mesh = slots[D.tree_variant_index("Forest_tree", D.SUMMER)]
	var tree_w: Mesh = slots[D.tree_variant_index("Forest_tree", D.WINTER)]
	assert(grass != null and tree_s != null and tree_w != null, "킷 메시 로드 실패 — 에셋 경로 확인")
	var frost: ShaderMaterial = dec._frost_mat()     # 지피 서리 = MMI material_override
	assert(frost.get_shader_parameter("use_tex"), "서리 override가 아틀라스를 안 물었다(단색 폴백)")
	var snow := W.C_SNOW.srgb_to_linear()
	var g_sum := _kit_albedo(grass, atlas, grass.surface_get_material(0) as ShaderMaterial)
	var g_win := _kit_albedo(grass, atlas, frost)
	var t_sum := _kit_albedo(tree_s, atlas, tree_s.surface_get_material(0) as ShaderMaterial)
	var t_win := _kit_albedo(tree_w, atlas, tree_w.surface_get_material(0) as ShaderMaterial)
	dec.free()
	var msg := " (설원 %.3f / 풀 여름 %.3f→겨울 %.3f(×%.2f) / 수관 여름 %.3f→겨울 %.3f(×%.2f), 설원비 %.2f)" \
		% [snow.g, g_sum.g, g_win.g, g_win.g / g_sum.g, t_sum.g, t_win.g, t_win.g / t_sum.g, g_win.g / snow.g]
	print("winter veg albedo(lin):" + msg)   # assert보다 먼저 — 실패해도 실측값이 로그에 남는다
	# 이 대역들은 **설원이 아니라 같은 킷의 여름 사본**을 기준으로 잡는다. 옛 판은 셋 다 설원비였는데,
	# 겨울 실루엣 처방으로 C_SNOW를 내리자(0.68→0.575) 과녁이 통째로 따라 움직였다 — 설원을 건드릴
	# 때마다 식생 gain의 합격 대역이 조용히 바뀌는 판이라 회귀를 못 잡는다. 서리는 "같은 텍셀을
	# 얼마나 밝히느냐"는 처방이므로 여름 사본이 옳은 원점이고, 이 대역은 C_SNOW와 무관하게 고정된다.
	# ① 서리는 **밝히는** 처방이다(잎 결을 남긴 "얹힌 눈"). gain을 잃으면 눈밭 위 검은 잡초가 된다.
	#    겨울 gain을 1.0으로 되돌리면 여기서 걸린다(여름비 0.51) = 이 테스트의 존재 이유.
	assert(g_win.g > g_sum.g * 1.05, "겨울 풀이 여름 풀보다 안 밝다 — FLORA_WINTER_GAIN 처방 소실" + msg)
	# ② 그러나 더 밝히면 min(src*gain, 1.0)이 채널을 잘라 색이 흰색으로 빠지고 설원과 한 덩어리가
	#    된다 — 실측된 1차 실패(gain 2.6: 서리 풀 화면 (209,198,189)이 설원 (213,215,220)에 흡수).
	#    세 지점의 여름비는 gain 1.0 → 0.51 · **승인된 2.15 → 1.10** · 1차 실패 2.6 → 1.28이므로
	#    [1.05, 1.20]이 승인점만 통과시키고 알려진 두 실패를 다 걸러낸다.
	assert(g_win.g < g_sum.g * 1.20, "서리 풀이 하얗게 빠졌다 — 겨울 중경 실루엣 소실" + msg)
	# ③ 그 위에서 지피는 설원 **바닥 위에 놓인다** = 지면에 묻히면 안 된다. 값이 아니라 서열만
	#    본다(설원이 움직여도 뜻이 안 변하는 유일한 설원 관계다).
	assert(g_win.g > snow.g * 1.05, "서리 풀이 설원에 묻힌다 — 흰 바탕의 흰 낙서" + msg)
	# ④ 수관은 반대 목표 — 크림 하늘 배경이라 훨씬 밝아야 "가지에 얹힌 눈"으로 읽힌다(어두우면 바위
	#    덩어리). 두 목표가 반대라는 것이 옛 C_FROST_LEAF > C_FROST 서열의 실경로 판이다.
	assert(t_win.g > t_sum.g * 1.25, "서리 수관이 어둡다 — 눈 덮인 나무가 아니라 바위로 읽힌다" + msg)
	assert(t_win.g > g_win.g * 1.25, "수관·지피 서리 밝기 목표가 갈리지 않았다" + msg)

# ══ 벽토 정오 화면값 — **실제 경로**를 계산으로 검증 ═══════════════════
# 카드: "건물 벽면이 정오 직광에서 순백으로 날아간다. 흐린 비에도 흰색이다."
# 상수 서열 핀으로는 못 잡던 결함이다 — 옛 값 (0.880,0.844,0.774)은 겨울 실루엣 핀을
# 통과하면서도 화면에서는 세 채널이 다 255였다(실측 audit2_0809/beach_spawn_h12).
# 그래서 여기서는 **프로덕션이 실제로 짓는 벽**의 머티리얼을 그대로 읽어(색·레버를 인자로
# 복사하지 않는다 — e1c0540 교훈) 정오 직광면·그늘면 화면값을 계산하고 두 대역을 못박는다.
# 배선(shadow_level)이 빠지면 그늘면 값이, 색이 되돌아가면 직광면 값이 각각 운다.
func _test_wall_face_look() -> void:
	var W := preload("res://world/world.gd")
	var B := preload("res://world/beach.gd")
	var DN := preload("res://world/day_night.gd")
	# ── 전역 기본값 = 항등. 이 셰이더는 캐릭터·가구·식생·킷 소품이 전부 공유하므로 기본이
	# 움직이면 마을 전체 명암이 조용히 바뀐다(sat_cap·green_gate와 같은 규약).
	# 기본값은 소스에서 직접 본다 — shader_get_parameter_default는 --headless에서 null(실증).
	var src := FileAccess.get_file_as_string("res://lookdev/toon.gdshader")
	assert(src.contains("uniform float shadow_level : hint_range(0.0, 1.0) = 0.55;"),
		"툰 shadow_level 전역 기본이 0.55가 아니다 — 벽 레버가 전역으로 샜다")
	assert(src.contains("uniform vec4 shadow_tint : source_color = vec4(0.78, 0.66, 0.72, 1.0);"),
		"툰 shadow_tint 기본이 바뀌었다 — 아래 화면값 환산의 전제")
	var g_tint := Color(0.78, 0.66, 0.72)  # 셰이더 전역 기본 = 레버를 안 건 머티리얼이 타는 값
	# 벽 머티리얼은 **프로덕션이 짓는 그 오두막**에서 뽑는다(_roof_snow 핀과 같은 방식).
	var bh: Node3D = B.new()
	bh._hut()
	var m := (bh.get_child(0) as MeshInstance3D).material_override as ShaderMaterial
	var alb: Color = m.get_shader_parameter("albedo")
	# 레버를 안 걸면 uniform 자체가 없다(null) = 셰이더 전역 기본을 탄다. 그 경우를 그대로
	# 재현해야 "배선이 빠졌다"가 타입에러가 아니라 **값**으로 드러난다.
	var slv: Variant = m.get_shader_parameter("shadow_level")
	var sl: float = 0.55 if slv == null else float(slv)
	var tv: Variant = m.get_shader_parameter("shadow_tint")
	var tint: Color = g_tint if tv == null else tv
	# 항등 규약: 벽토가 **아닌** 머티리얼은 두 레버가 다 미설정이어야 한다(= 전역 기본 통과).
	# 오두막 지붕(C_ROOF)도 같은 make_solid를 타므로 배선이 색 조건 밖으로 새면 여기서 잡힌다.
	var roof := (bh.get_child(1) as MeshInstance3D).material_override as ShaderMaterial
	var r_tint: Variant = roof.get_shader_parameter("shadow_tint")
	var r_sl: Variant = roof.get_shader_parameter("shadow_level")
	bh.free()
	assert(r_tint == null and r_sl == null,
		"벽토가 아닌 머티리얼(오두막 지붕)에 그늘 레버가 샜다 — tint %s · level %s" % [str(r_tint), str(r_sl)])
	assert(alb.is_equal_approx(W.C_WALL), "해변 오두막 벽이 마을 벽토 팔레트가 아니다: %s" % str(alb))
	var lit := DN.face_screen(alb, sl, tint, true)
	var shade := DN.face_screen(alb, sl, tint, false)
	var msg := " (albedo %s · shadow_level %.2f · shadow_tint %s → 직광 (%d,%d,%d) / 그늘 (%d,%d,%d))" % [str(alb), sl, str(tint),
		roundi(lit.r * 255.0), roundi(lit.g * 255.0), roundi(lit.b * 255.0),
		roundi(shade.r * 255.0), roundi(shade.g * 255.0), roundi(shade.b * 255.0)]
	print("wall face screen:" + msg)   # assert보다 먼저 — 실패해도 실측값이 로그에 남는다
	# ① 직광면이 포화를 벗는다. 0.995 = 화면 254 — 한 채널이라도 여기 닿으면 곡률·음영이
	#    통째로 날아가 "순백 덩어리"가 된다(카드의 원 증상).
	assert(maxf(lit.r, maxf(lit.g, lit.b)) < 0.995, "벽 직광면이 정오에 포화한다" + msg)
	# ② 그늘면은 파스텔 크림 대역에 남아야 한다. 0.80 = 화면 204.
	#    알려진 실패 두 개가 여기 걸린다: albedo만 0.68로 내린 판(그늘 G 156)과
	#    albedo를 내리고 shadow_level 레버를 안 건 판(그늘 G 189).
	assert(shade.g >= 0.80, "벽 그늘면이 파스텔 크림에서 갈색으로 떨어졌다" + msg)
	# ③ 그렇다고 그늘까지 포화하면 안 된다 — 벽이 통째로 흰 판이 되고 겨울 실루엣도 죽는다
	#    (옛 albedo에 레버만 걸면 여기 걸린다: 그늘 (255,253,239)).
	assert(maxf(shade.r, maxf(shade.g, shade.b)) < 0.995, "벽 그늘면까지 포화 — 면이 안 갈린다" + msg)
	# ④ 두 면이 갈려야 형태가 읽힌다. 0.06 ≈ 화면 15레벨.
	assert(lit.g - shade.g >= 0.06, "벽 직광·그늘 명암차 부족 — 평평한 판으로 읽힌다" + msg)
	# ⑤ albedo 자체도 지면·채집물과 같은 천장 아래(발주 §5). 위 ①이 화면에서 같은 것을 재지만,
	#    이쪽은 조명 모델과 무관하게 서는 값이라 남긴다. **①보다 뒤에 둔다** — 앞에 두면 색만
	#    되돌린 회귀에서 이 assert가 먼저 터져 화면값 핀이 아예 안 돌아 로그에 실측이 안 남는다.
	assert(maxf(alb.r, maxf(alb.g, alb.b)) <= 0.75, "벽토 albedo가 정오 클리핑 상한 초과: %s" % str(alb))
	# ⑥ 그늘면이 **크림**으로 읽혀야 한다 = G가 B보다 위. 전역 shadow_tint는 B(0.72) > G(0.66)라
	#    캐릭터 피부 그림자용의 자주빛이 섞여 있는데, 옛 벽 albedo는 노란기(B가 R보다 0.106 아래)로
	#    그걸 덮고 있었다. albedo 채도가 0.070까지 깎이자 tint가 드러나 그늘이 분홍으로 뒤집혔다
	#    (실측 (230,209,208) = G−B 1, 옛 크림은 (243,219,211) = G−B 8).
	#    문턱은 **절대값**이다 — 프로덕션 상수에서 파생시키면 그 상수를 되돌렸을 때 문턱도 같이
	#    되돌아가 핀이 안 문다(직전 작업이 실제로 밟은 함정). 0.024 ≈ 화면 6레벨.
	assert(shade.g - shade.b >= 0.024, "벽 그늘면이 크림이 아니라 분홍으로 읽힌다" + msg)

# ══ 가을 식생 룩 — **실제 경로**를 계산으로 검증 ═══════════════════════
# 겨울(_test_winter_veg_look)과 같은 방식이다: 상수 서열이 아니라 decor가 실제로 만든 머티리얼로
# 실물 아틀라스를 샘플링해 셰이더 경로를 그대로 계산한다. 여기서 보는 것은 셋이다.
#   ① 나무: 단풍이 **잎 텍셀에만** 걸리는가(게이트). 죽으면 줄기가 다시 수관과 같은 주황이 된다.
#   ② 지피: 덤불·풀만 가을 톤을 타고 꽃은 안 타는가(꽃에 걸리면 가을 화단이 덮여 사라진다).
#   ③ 대비: 가을 4요소(수관·낙엽·지면·덤불)가 화면에서 서로 떨어져 있는가 = **단색 방지**.
func _test_autumn_veg_look() -> void:
	var W := preload("res://world/world.gd")
	var D := preload("res://world/decor.gd")
	var atlas := Image.load_from_file(D.TT_PARK + "tiny_treats_texture_1.png")
	assert(atlas != null, "파크 킷 아틀라스를 못 읽음")
	var dec: Node = D.new()
	# 슬롯 사본은 _place_forest가 실제로 부르는 함수(tree_slots)에서 받는다 — 인자를 복사해 두면
	# decor 쪽 처방이 옛 판(줄기까지 물드는 회귀)으로 되돌아가도 이 핀이 안 문다.
	var slots: Array = dec.tree_slots("tree")
	var tree_s: Mesh = slots[D.tree_variant_index("Forest_tree", D.SUMMER)]
	var tree_a: Mesh = slots[D.tree_variant_index("Forest_tree", D.AUTUMN)]
	var tree_w: Mesh = slots[D.tree_variant_index("Forest_tree", D.WINTER)]
	# 낙엽 사본도 _place_leaf_litter가 실제로 부르는 함수에서 받는다(나무 슬롯과 같은 이유).
	var litter: Mesh = dec.leaf_litter_mesh()
	var bush: Mesh = dec._flora_mesh("bush")
	var grass: Mesh = dec._flora_mesh("grass_A")
	assert(tree_s != null and tree_a != null and litter != null and bush != null, "킷 메시 로드 실패 — 에셋 경로 확인")
	var aut: ShaderMaterial = dec._autumn_mat()
	var m_s := tree_s.surface_get_material(0) as ShaderMaterial
	var m_a := tree_a.surface_get_material(0) as ShaderMaterial
	# ── 게이트 항등 규약: 켠 곳이 단풍 사본 **하나뿐**이어야 한다. 이 셰이더는 캐릭터·가구·킷
	# 소품·겨울 서리가 전부 공유하므로, 게이트가 새면 마을 전체 색이 조용히 바뀐다.
	# 기본값은 소스에서 직접 본다 — RenderingServer.shader_get_parameter_default는 --headless에서
	# 셰이더가 컴파일되지 않아 null을 준다(실증).
	for decl in ["uniform float green_gate = 0.0;", "uniform float leaf_sat : hint_range(0.0, 1.0) = 1.0;",
			"uniform vec4 leaf_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);"]:
		assert(ToonCharacter.TOON.code.contains(decl),
			"게이트 uniform 기본값이 항등이 아니다 — 이 셰이더를 쓰는 전 오브젝트가 영향을 받는다: %s" % decl)
	assert(m_s.get_shader_parameter("green_gate") == null, "여름 사본에 게이트가 샜다")
	assert(tree_w.surface_get_material(0).get_shader_parameter("green_gate") == null, "겨울 사본에 게이트가 샜다")
	assert(dec._frost_mat().get_shader_parameter("green_gate") == null, "서리 override에 게이트가 샜다")
	assert(aut.get_shader_parameter("green_gate") == null, "지피 override엔 게이트가 불필요하다(덤불엔 수피가 없다)")
	# ── ① 나무: 수피는 사계절 같은 색, 잎만 단풍 ──────────────────────
	var bark_s := _kit_albedo(tree_s, atlas, m_s, -1, true)
	var bark_a := _kit_albedo(tree_a, atlas, m_a, -1, true)
	var leaf_s := _kit_albedo(tree_s, atlas, m_s, 1, true)
	var leaf_a := _kit_albedo(tree_a, atlas, m_a, 1, true)
	var tmsg := " (수피 여름 %s → 가을 %s / 잎 여름 %s → 가을 %s)" % [str(bark_s), str(bark_a), str(leaf_s), str(leaf_a)]
	print("autumn tree albedo(lin):" + tmsg)   # assert보다 먼저 — 실패해도 실측값이 로그에 남는다
	assert(leaf_s.g > leaf_s.r, "여름 잎이 초록이 아니다 — 게이트 판정이 잎을 잘못 골랐다" + tmsg)
	assert(leaf_a.r > leaf_a.g and leaf_a.g > leaf_a.b, "단풍 잎이 주황(R>G>B)이 아니다" + tmsg)
	# 수피는 val_gain 차이(1.90/1.85 = 1.027)만 타야 한다. 게이트가 죽으면 여기서 걸린다 —
	# 게이트 없던 판의 실측 비는 (1.25, 0.82, 0.38)이었다(= 줄기가 통째로 주황).
	for ch in 3:
		var r: float = bark_a[ch] / maxf(bark_s[ch], 1e-4)
		assert(r >= 1.00 and r <= 1.06, "가을 수피가 여름 수피에서 벗어났다 — 단풍이 줄기까지 물든다" + tmsg)
	# ── ② 지피 술어: 덤불·풀만, 꽃은 사계절 제외, 겨울은 서리가 이긴다 ──
	for nm in ["Flora_bush", "Flora_bush_large", "Flora_grass_A", "Flora_grass_B"]:
		assert(D.flora_autumn(nm, 2), "%s 가을에 톤이 안 걸린다" % nm)
		for s in [0, 1, 3]:
			assert(not D.flora_autumn(nm, s), "%s 계절 %d에 가을 톤이 걸린다" % [nm, s])
		assert(D.flora_frosted(nm, 3) and not D.flora_autumn(nm, 3), "%s 겨울엔 서리가 이겨야 한다" % nm)
	for nm in ["Flora_flower_A", "Flora_flower_A~white", "Flora_flower_A~pink", "Flora_flower_A~lavender", "Flora_flower_B"]:
		for s in 4:
			assert(not D.flora_autumn(nm, s), "%s 꽃에 override가 걸리면 가을 화단이 덮여 사라진다" % nm)
	assert(not D.flora_autumn("Forest_tree", 2), "나무는 flora 규칙 밖(메시 스왑 경로)")
	# ── ③ 대비: 가을 4요소가 화면에서 서로 떨어져 있는가 ──────────────
	var s_bush := _noon_screen(_kit_albedo(bush, atlas, aut, 0, true))
	var s_grass := _noon_screen(_kit_albedo(grass, atlas, aut, 0, true))
	var s_summer := _noon_screen(_kit_albedo(bush, atlas, bush.surface_get_material(0) as ShaderMaterial, 0, true))
	var s_canopy := _noon_screen(leaf_a)
	var s_litter := _noon_screen(_kit_albedo(litter, atlas, litter.surface_get_material(0) as ShaderMaterial, 0, true))
	var s_ground := _noon_screen(W.C_GRASS_A.srgb_to_linear())
	dec.free()
	var fmsg := " (정오 화면: 덤불 %s · 풀 %s · 수관 %s · 낙엽 %s · 지면 %s / 여름 덤불 %s)" \
		% [_px(s_bush), _px(s_grass), _px(s_canopy), _px(s_litter), _px(s_ground), _px(s_summer)]
	print("autumn flora screen:" + fmsg)
	# 낙엽은 **화면에서** 갈색이어야 한다. 위 LEAF_TINT 상수 서열 핀은 상수만 보므로 프로덕션이
	# 색조를 잃어도(예: KIT_TINT) 안 문다 — 실측 R−B는 승인점 0.573 vs 색조 소실판 0.043이라
	# 0.25가 둘을 가른다. 색조를 잃으면 바닥이 흰 데이지 밭으로 남는다.
	assert(s_litter.r - s_litter.b >= 0.25, "낙엽이 갈색이 아니다 — 색조가 소실돼 바닥에 흰 꽃이 깔린다" + fmsg)
	# 가을 화면엔 이미 주황·노랑이 넷이다 — 덤불까지 그 계열로 밀면 한 색으로 뭉개져 깊이가 죽는다.
	# 승인점 실측 최소는 덤불↔수관 0.265라 0.20이 승인점을 통과시키고 "지면에 붙는" 판을 걸러낸다
	# (색조를 KIT_TINT로 되돌린 판의 덤불↔지면 = 0.171).
	# 수관↔낙엽(0.082)은 일부러 붙여 둔 승인된 쌍이라 여기서 재지 않는다.
	for p in [[s_bush, "덤불"], [s_grass, "풀"]]:
		for q in [[s_canopy, "수관"], [s_litter, "낙엽"], [s_ground, "지면"]]:
			assert(_cdist(p[0], q[0]) >= 0.20, "가을 %s과 %s이 화면에서 붙었다 — 계절이 단색으로 뭉갠다%s" % [p[1], q[1], fmsg])
	# "단풍든 덤불"이 아니라 "물기가 빠진 덤불"이다 — 초록기가 여름의 절반 아래로 내려가야 한다.
	# 덤불 tint를 원색으로 되돌리면 정확히 이 핀이 걸린다.
	var g_aut := s_bush.g - maxf(s_bush.r, s_bush.b)
	var g_sum := s_summer.g - maxf(s_summer.r, s_summer.b)
	assert(g_aut < g_sum * 0.5, "가을 덤불이 여전히 원색 초록이다 (초록기 %.3f / 여름 %.3f)%s" % [g_aut, g_sum, fmsg])
	# 지면보다 한 단 진해야 중경 실루엣이 남는다(겨울 서리 풀과 같은 이유).
	assert(s_bush.v < s_ground.v * 0.90, "가을 덤불이 지면에 묻힌다" + fmsg)
	assert(maxf(D.FLORA_AUTUMN_TINT.r, maxf(D.FLORA_AUTUMN_TINT.g, D.FLORA_AUTUMN_TINT.b)) <= 0.75,
		"가을 지피 색조가 정오 클리핑 상한 0.75를 넘는다: %s" % str(D.FLORA_AUTUMN_TINT))

func _px(c: Color) -> String:
	return "(%d,%d,%d)" % [roundi(c.r * 255), roundi(c.g * 255), roundi(c.b * 255)]

# toon.gdshader grade()를 선형공간에서 그대로 계산한다(채도 상한 → 밝기 곱 → tint).
func _toon_albedo(src: Color, sat: float, gain: float, tint: Color) -> Color:
	var mx := maxf(src.r, maxf(src.g, src.b))
	if sat < 1.0:
		var sv := (mx - minf(src.r, minf(src.g, src.b))) / maxf(mx, 1e-4)
		var t := minf(1.0, sat / maxf(sv, 1e-4))
		src = Color(lerpf(mx, src.r, t), lerpf(mx, src.g, t), lerpf(mx, src.b, t))
	return Color(minf(src.r * gain, 1.0) * tint.r, minf(src.g * gain, 1.0) * tint.g,
		minf(src.b * gain, 1.0) * tint.b)

# 메시가 실제로 참조하는 아틀라스 텍셀들의 평균 albedo(선형). 킷 UV는 팔레트 패치를 찍으므로
# 정점 UV 평균이 그 종의 대표색이 된다.
# only: 0 = 전 텍셀 / +1 = 잎(초록) 텍셀만 / −1 = 그 밖(수피) 텍셀만. 킷 나무는 표면이 한 장이라
# 수관·수피를 갈라 재려면 셰이더 게이트와 **같은 판정**을 여기서도 써야 한다.
# lin: 색조를 선형으로 환산해 곱한다 = **셰이더가 실제로 하는 일**(source_color uniform은 업로드
# 때 srgb_to_linear를 탄다). 실측 대조 — lin=true 가을 덤불 (153,173,87) vs 스크린샷 (156,181,60),
# lin=false는 (201,225,156)로 한참 밝다. 그러니 절대 화면색을 재는 가을 대비 핀은 true를 쓴다.
# ponytail: 기본값을 false로 남긴 건 _test_winter_veg_look의 승인 대역([1.05,1.20] 등)이 옛
# 근사값에 맞춰 튜닝돼 있어서다 — 그 테스트는 같은 모델 안의 **비율**만 보므로 뜻은 안 상한다.
# 겨울 룩을 다시 만질 일이 생기면 그때 대역을 lin=true 기준(2.15 → 1.026)으로 옮기고 이 인자를 지운다.
func _kit_albedo(mesh: Mesh, atlas: Image, m: ShaderMaterial, only := 0, lin := false) -> Color:
	var sat: float = m.get_shader_parameter("sat_cap")
	var gain: float = m.get_shader_parameter("val_gain")
	var tint: Color = m.get_shader_parameter("char_tint")
	var gv = m.get_shader_parameter("green_gate")
	var gate: float = 0.0 if gv == null else float(gv)
	var lsat: float = 1.0 if gate <= 0.0 else float(m.get_shader_parameter("leaf_sat"))
	var ltint: Color = Color.WHITE if gate <= 0.0 else m.get_shader_parameter("leaf_tint") as Color
	if lin:
		tint = tint.srgb_to_linear()
		ltint = ltint.srgb_to_linear()
	var acc := Color(0, 0, 0)
	var n := 0
	for s in mesh.get_surface_count():
		var uvs: PackedVector2Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_TEX_UV]
		for uv in uvs:
			var px := atlas.get_pixel(
				clampi(int(uv.x * atlas.get_width()), 0, atlas.get_width() - 1),
				clampi(int(uv.y * atlas.get_height()), 0, atlas.get_height() - 1)).srgb_to_linear()
			var grn := px.g - maxf(px.r, px.b)
			if (only > 0 and grn <= 0.0) or (only < 0 and grn > 0.0):
				continue
			var base := _toon_albedo(px, sat, gain, tint)
			if gate > 0.0:
				base = base.lerp(_toon_albedo(px, lsat, gain, ltint),
					smoothstep(gate - 0.05, gate + 0.05, grn))
			acc += base
			n += 1
	return acc / maxf(n, 1)

# 선형 albedo → 정오 수평면 화면색(sRGB). 이 저장소의 실측 환산 계수는 ×1.90이다.
func _noon_screen(alb: Color) -> Color:
	return Color(minf(alb.r * 1.90, 1.0), minf(alb.g * 1.90, 1.0), minf(alb.b * 1.90, 1.0)).linear_to_srgb()

# 채집 배치 스냅샷 [위치, forage_id] — _clear()가 queue_free 하므로 다음 _respawn 전에 뜬다.
func _forage_snapshot(fs: Node) -> Array:
	var out := []
	for r in fs._roots:
		for c in r.get_children():
			if c is Area3D:
				out.append([(r as Node3D).position, String(c.get_meta("forage_id"))])
	return out

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
	for d in range(1, GameClock.DAYS_PER_SEASON):
		if rd < 0 and days[d]:
			rd = d
		elif rd >= 0 and cd < 0 and not days[d]:
			cd = d
	assert(rd > 0 and cd > rd, "봄에 비/맑음 검증일 확보 (rd=%d cd=%d)" % [rd, cd])
	GameClock.abs_day = rd - 1
	GameClock.game_min = 1300
	assert(GameData.season_id(GameClock.season()) == "spring", "전제: 봄(계절 밖 씨앗은 심기가 거부됨)")
	var cell := _fcell(4, 2)
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
	var c3 := _fcell(5, 2)
	assert(_farm.till(c3) and _farm.plant(c3, "seed.turnip"), "비 오는 날 심기")
	assert(_farm.get_tile(c3)["watered"], "비 오는 날 심은 작물도 젖음")

func _test_v1_save_compat() -> void:
	# A단계(v1) 세이브를 그대로 로드 → 마이그레이션되어 복원 (호환)
	if FileAccess.file_exists(SaveManager.path("bak")):
		DirAccess.remove_absolute(SaveManager.path("bak"))
	var f := FileAccess.open(SaveManager.path("json"), FileAccess.WRITE)
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

	# ── 0. 소프트닝 v2 계약: 해변이 순환 preload를 피해 복제한 값은 마을과 같아야 한다.
	assert(B.C_ROAD == W.C_ROAD and B.C_ROAD_E == W.C_ROAD_E, "해변 진입로 색 = 마을 흙길 색")
	for L in [0.0, 1.4, 1.5, 3.0, 11.0, 42.0]:
		assert(B._subdiv_z(L) == W._subdiv_z(L), "해변 곡률 세분할 식이 world.gd와 어긋남 (L=%s)" % L)
	# 젖은 모래 띠는 바다 판 남단을 한가운데 물고 수면 위에 떠야 한다(직선 물가선 은폐).
	assert(B.WET_Z == B.SEA_REL.z + B.SEA_D * 0.5, "물가 띠 중심 = 바다 판 남단")
	assert(B.WET_D * 0.5 > B.WET_ERODE, "띠 반깊이가 침식 진폭보다 커야 수면 모서리가 안 샌다")

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
	assert(sea_ids.size() >= 3, "봄 바다 어종 (실제 %d)" % sea_ids.size())
	assert(pond_ids.size() >= 5, "봄 연못 어종 (실제 %d)" % pond_ids.size())
	# ── 계절 커버리지: 네 계절 × 두 낚시터 × 24시간 어디서도 빈손이 없다.
	# **옛 핀은 봄 풀만 봤고, 실제로 여름·가을·겨울은 어종이 0종이었다** — 낚시하면
	# "여긴 잡을 게 없네요"가 뜬다. 종수가 아니라 pick_fish 실경로로 본다(시간창 게이트까지).
	for s in GameData.SEASON_IDS:
		var sp2 := GameData.season_filter(GameData.fish, s)
		assert(not sp2.is_empty(), "%s 어종 0종 — 그 계절 낚시가 통째로 없다" % s)
		for spot in GameData.SPOT_IDS:
			for h in 24:
				assert(GameData.pick_fish(GameData.fish, sp2, 0.5, h, spot) != "",
					"%s %s %d시 후보 0 — 던져도 안 물린다" % [s, spot, h])
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
	# 판매가: 바다 최고가가 연못 최고가를 넘되 반지(1200) 경제를 깨지 않는다.
	# **특정 어종 id를 박아두면 새 어종이 그 위로 올라가도 통과한다** — 데이터에서 최댓값을
	# 뽑아 본다(어종을 늘릴 때 이 핀이 자동으로 따라온다).
	var sea_max := 0
	var pond_max := 0
	for fid in GameData.fish:
		var p := GameData.sell_price(fid)
		if String(GameData.fish[fid].get("spot", GameData.SPOT_POND)) == GameData.SPOT_SEA:
			sea_max = maxi(sea_max, p)
		else:
			pond_max = maxi(pond_max, p)
	assert(sea_max > pond_max, "바다 최고가(%d) > 연못 최고가(%d)" % [sea_max, pond_max])
	assert(GameData.RING_COST >= sea_max * 7, "반지값(%d)이 어종 최고가(%d) 7배 이상 유지" % [GameData.RING_COST, sea_max])
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

# ── 물 마감: 연못 둑 윤곽 + 바다 수평선 대기 띠 ─────────────────────
# 무는 것: ① 수면 AABB(중심·반경)가 안 움직였는가 — 낚시 트리거·라벨·파문 물영역·NPC keepout이
# 전부 여기서 파생하는 **모든 계약의 뿌리**다 ② 둑 최대 반경이 keepout 안인가 ③ 절차 링이
# **실제로 흔들리는가**(값을 잰다 — 배선만 확인하면 진폭 0으로 되돌아가도 안 문다)
# ④ 이음매가 정점을 공유하는가(공유 안 하면 법선이 갈려 외곽선이 이중선으로 뜬다)
# ⑤ 수면이 둑을 안 넘는가 ⑥ 물가 식생이 낚시 동선을 안 막고 한쪽으로 몰렸는가
# ⑦ 대기 띠가 **바다에만** 켜지는가(연못·강까지 켜지면 마을 물이 통째로 뿌옇게 뜬다).
# 전부 프로덕션이 부르는 그 함수를 그대로 불러서 잰다 — 인자 사본 금지(02b11cd·99e89ac·e1c0540).
func _test_water_look() -> void:
	var W := preload("res://world/world.gd")
	var D := preload("res://world/decor.gd")
	var B := preload("res://world/beach.gd")
	var N := preload("res://npc/npc_system.gd")

	# ── 1. 수면 계약 — tscn이 단일 출처이므로 tscn에서 읽는다.
	# Pond 노드만 떼어 world.gd 인스턴스에 붙인다. 호스트는 **빈 Node3D로 먼저 트리에 넣고
	# 그 다음에 스크립트를 붙인다** — _ready는 트리 진입 때 한 번 지나가므로 마을이 안 지어진다.
	# 트리 안이어야 하는 이유: Node3D.global_transform은 트리 밖에서 단위행렬을 돌려준다
	# (실측: AABB 중심이 (0,0,0)으로 나와 핀이 헛것을 쟀다) = _pond_dig의 실제 입력이 아니다.
	var ws: Node3D = preload("res://world/world.tscn").instantiate()
	var pond := ws.get_node("Pond") as Node3D
	ws.remove_child(pond)
	ws.free()
	var host := Node3D.new()
	add_child(host)
	host.set_script(W)
	host.add_child(pond)   # 이름 "Pond" 유지 → _pond_dig의 get_node 경로가 그대로 산다
	var pmesh := host.get_node("Pond/PondMesh") as MeshInstance3D
	var box: AABB = pmesh.global_transform * pmesh.mesh.get_aabb()
	var pcen := box.get_center()
	var prad := box.size.x * 0.5
	assert(pcen.is_equal_approx(Vector3(10, 0.1, 0)), "연못 수면 AABB 중심이 움직였다: %s" % pcen)
	assert(is_equal_approx(prad, 2.5), "연못 수면 반경이 움직였다: %.4f" % prad)
	assert(is_equal_approx(box.size.z * 0.5, prad), "수면이 원반이 아니다 (x %.3f vs z %.3f)" % [prad, box.size.z * 0.5])
	var water_top: float = box.position.y + box.size.y

	# ── 2. 둑 — 프로덕션 _pond_dig가 만든 메시의 정점을 자로 잰다.
	var holder := Node3D.new()
	host._pond_dig(holder)
	var ring: MeshInstance3D = null
	var chan: MeshInstance3D = null
	for ch in holder.get_children():
		var mi := ch as MeshInstance3D
		if mi == null:
			continue
		if mi.mesh is ArrayMesh:
			ring = mi
		elif mi.mesh is CylinderMesh:
			chan = mi
	assert(ring != null and chan != null, "_pond_dig가 둑 링/채널 바닥을 안 만들었다")
	var arrays: Array = (ring.mesh as ArrayMesh).surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	# 이음매 = 정점을 감아서 **공유**한다. θ=2π 링을 따로 두면 그 줄만 법선이 반쪽 평균이라
	# 외곽선이 이중선으로 뜬다(옛 주석이 조각 대신 토러스 한 장을 고른 그 이유).
	assert(verts.size() == W.POND_RING_SEG * W.POND_TUBE_SEG,
		"둑 링에 이음매 중복 정점 (정점 %d, 기대 %d)" % [verts.size(), W.POND_RING_SEG * W.POND_TUBE_SEG])
	assert(idx.size() == W.POND_RING_SEG * W.POND_TUBE_SEG * 6, "둑 링 인덱스 수가 어긋남 (%d)" % idx.size())
	# 각도 칸마다 가장 먼 정점 = 바깥 실루엣. 칸별 최대의 최대/최소가 곧 흔들림 폭이다.
	# 칸을 **반 칸 밀어** 링 단면의 각도가 칸 경계가 아니라 칸 한가운데 오게 한다(+0.5):
	# 메시 정점은 float32라 같은 단면의 10개 정점이 경계에서 좌우로 흩어졌고, 그 바람에
	# 어떤 칸은 바깥 적도 정점이 통째로 빠져 실루엣을 0.29 낮게 쟀다(실측 2.42 vs 2.70).
	var bins := W.POND_RING_SEG
	var sil := PackedFloat32Array()
	sil.resize(bins)
	sil.fill(0.0)
	var top := -INF
	for v in verts:
		var d := Vector2(v.x, v.z).length()
		top = maxf(top, v.y)
		var bi: int = posmod(int(floor((atan2(v.z, v.x) + PI) / TAU * bins + 0.5)), bins)
		sil[bi] = maxf(sil[bi], d)
	var rmax := 0.0
	var rmin := INF
	for d in sil:
		rmax = maxf(rmax, d)
		rmin = minf(rmin, d)
	var contract: float = prad + 0.05 + W.BANK_W   # 옛 토러스 outer_radius = 3.15 = 상한
	# 상한은 절대 못 넘고(keepout), 그렇다고 통째로 쪼그라들지도 않는다. 실측 최대 3.109 —
	# 하모닉 셋이 동시에 마루에 서는 각도가 없어 상한에 정확히 닿지는 않는다.
	assert(rmax <= contract + 1e-3, "둑 최대 반경이 계약(%.3f)을 넘었다: %.4f" % [contract, rmax])
	assert(rmax > contract - 0.10, "둑이 통째로 안으로 쪼그라들었다: %.4f (계약 %.3f)" % [rmax, contract])
	var keep := 0.0
	for ko in N.BUILDING_KEEPOUT:
		if (ko[0] as Vector2).is_equal_approx(Vector2(pcen.x, pcen.z)):
			keep = float(ko[1])
	assert(keep > 0.0, "npc_system에 연못 keepout이 없다")
	assert(rmax < keep + N.BLOCK_PAD, "둑 바깥(%.3f)이 NPC keepout(%.2f)을 넘었다 = 주민이 둑을 밟는다"
		% [rmax, keep + N.BLOCK_PAD])
	# **값을 재는** 핀: 링이 실제로 흔들리는가.
	# 문턱은 **절대값**이다. 처음엔 W.POND_WOBBLE에서 파생시켰는데, 그러면 진폭을 0으로
	# 되돌렸을 때 문턱까지 같이 0이 돼 float 오차만으로 통과했다(의도적 파손 1차에서 실증) —
	# 프로덕션 인자를 베낀 핀이 못 무는 바로 그 실패다.
	# 0.30 = 부감 컷 기준 링 반경 ~150px에서 ~16px 흔들림 = "도넛이 아니다"로 읽히는 최소선.
	assert(rmax - rmin > 0.30,
		"둑이 정원이다 — 바깥 실루엣 흔들림 %.3f (진폭 상수 %.2f)" % [rmax - rmin, W.POND_WOBBLE])
	# 흔들림은 **안쪽으로만**: 어느 각도에서도 계약 반경을 넘지 않는다(위 rmax 계약의 근거).
	for k in 720:
		assert(W.pond_bank_offset(k * TAU / 720.0) <= 1e-5, "둑 오프셋이 양수 = 계약 반경을 넘는다")
	# 채널 바닥(어두운 청회)은 어느 각도에서도 둑 바깥으로 안 삐져나온다.
	assert((chan.mesh as CylinderMesh).top_radius < rmin,
		"채널 바닥(%.2f)이 둑 실루엣 최소(%.2f) 밖 = 잔디 위에 어두운 테가 뜬다"
		% [(chan.mesh as CylinderMesh).top_radius, rmin])
	# §0 넘침 판정을 값으로 못박는다: 둑 상면이 수면보다 확실히 위다.
	var bank_top: float = ring.position.y + top
	assert(bank_top > water_top + 0.2, "수면(%.3f)이 둑 상면(%.3f)을 넘본다" % [water_top, bank_top])
	assert(is_equal_approx(bank_top, W.BANK_H), "둑 상면이 강둑 높이(BANK_H)와 어긋남: %.3f" % bank_top)

	# ── 3. 물가 식생 — decor의 프로덕션 배치 함수를 그대로 부른다.
	assert(D.POND_C.is_equal_approx(Vector2(pcen.x, pcen.z)), "decor의 연못 중심 복제본이 tscn과 어긋남")
	assert(D.POND_EDGE_R0 > contract, "물가 식생이 둑(%.2f) 위에서 시작한다" % contract)
	var dec = D.new()
	var buckets := {}
	for nm in D.FLORA_BUCKETS:
		buckets[nm] = []
	dec._pond_edge(buckets)
	var pts := []
	for nm in buckets:
		for t in buckets[nm]:
			pts.append(Vector2((t as Transform3D).origin.x, (t as Transform3D).origin.z))
	assert(pts.size() >= 15, "물가 식생이 %d포기 — 실루엣을 못 가린다" % pts.size())
	var cg := Vector2.ZERO
	for p in pts:
		var d: float = p.distance_to(D.POND_C)
		assert(d >= D.POND_EDGE_R0 - 1e-3 and d <= D.POND_EDGE_R1 + 1e-3, "물가 식생이 띠를 벗어남: %.3f" % d)
		assert(d > rmax, "물가 식생이 둑 위에 얹혔다: %.3f" % d)
		assert(p.distance_to(Vector2(10, 3.8)) > 2.0, "낚시 자리 앞을 막았다: %s" % p)
		cg += p
	cg /= float(pts.size())
	# 사방 균등하게 심으면 도넛에 테두리만 하나 더 두르는 꼴이다 — 한쪽으로 몰려야 실루엣이 깨진다.
	assert(cg.distance_to(D.POND_C) > 1.0, "물가 식생이 사방 균등(무게중심 이격 %.2f)" % cg.distance_to(D.POND_C))
	dec.free()
	holder.free()

	# ── 4. 대기 띠는 바다에만 — 연못·강 물 머티리얼(프로덕션 _water_mat)엔 안 걸려야 한다.
	var pond_mat := host._water_mat() as ShaderMaterial
	var ph = pond_mat.get_shader_parameter("haze")
	assert(ph == null or is_zero_approx(float(ph)), "연못·강 물에 대기 띠가 켜졌다 = 마을 물이 뿌옇게 뜬다")
	remove_child(host)
	host.free()
	# 바다 쪽은 존을 실제로 지어서 그 판의 머티리얼을 읽는다(상수 복사 아님).
	var bch = B.new()
	add_child(bch)
	var sea_mat: ShaderMaterial = null
	for ch in bch.get_children():
		var mi := ch as MeshInstance3D
		if mi == null:
			continue
		var sm := mi.material_override as ShaderMaterial
		if sm != null and sm.shader == B.WATER_SHADER:
			sea_mat = sm
	assert(sea_mat != null, "바다 판 물 머티리얼을 못 찾음")
	# 미설정 uniform은 null을 돌려준다 — float(null)은 assert 안에서 터져도 **Assertion failed로
	# 안 찍힌다**(의도적 파손 2차에서 실증: 배선을 지웠더니 핀 대신 'Nonexistent float constructor'가
	# 났다). null을 먼저 물어야 실패가 자기 이름으로 보고된다.
	var hz_p = sea_mat.get_shader_parameter("haze")
	var cc_p = sea_mat.get_shader_parameter("curve_cap")
	var fg_p = sea_mat.get_shader_parameter("foam_gap")
	assert(hz_p != null and float(hz_p) > 0.0, "바다 수평선 대기 띠가 꺼졌다 = 칼직선으로 돌아간다")
	assert(cc_p != null and is_equal_approx(float(cc_p), B.SEA_CURVE_CAP), "바다 곡률 캡 어긋남")
	assert(fg_p != null and is_equal_approx(float(fg_p), B.FOAM_GAP), "바다 파도선(서프)이 꺼졌다")
	remove_child(bch)
	bch.free()

# ── H-3: 요리 8종 (부엌 스토브) ─────────────────────────────────
# 아이템이 나는 계절 (crop/fish/forage 공통 조회) — 요리 계절 커버리지 판정용.
func _item_seasons(item_id: String) -> Array:
	for src in [GameData.crops, GameData.fish, GameData.forage]:
		if src.has(item_id):
			return src[item_id].get("seasons", [])
	return []

func _test_cooking() -> void:
	# ── 데이터 정합: 종수·재료 참조·마진 대역
	# 요리는 "가치를 더하는 소모처"다. 판매가가 재료 판매가 합의 1.25~1.6배를 벗어나면
	# (아래면 아무도 안 만들고, 위면 재료 되팔기보다 요리가 돈복사가 된다) 여기서 잡는다.
	# 작물 gold/day 대역과 같은 수법: 런타임은 이 대역을 모르고 테스트만 안다.
	var lo := 1.25
	var hi := 1.6
	assert(GameData.recipes.size() >= 8, "요리 종수 (실제 %d)" % GameData.recipes.size())
	for rid in GameData.recipes:
		var r: Dictionary = GameData.recipes[rid]
		assert(rid.begins_with("dish."), "요리 id 규약 dish.*: %s" % rid)
		assert(GameData.has_item_id(rid), "%s 아이템 레지스트리 등록" % rid)
		assert(GameData.display_name(rid) == String(r["name"]), "%s 표시 이름 해석" % rid)
		assert(GameData.sell_price(rid) == int(r["sell_price"]), "%s 판매가 해석" % rid)
		var raw := 0
		for iid in r["ingredients"]:
			assert(GameData.is_collectible(iid), "%s 재료 %s 없는 아이템" % [rid, iid])
			assert(not GameData.recipes.has(iid), "%s 재료가 요리(순환 참조)" % rid)
			raw += GameData.sell_price(iid) * int(r["ingredients"][iid])
		var margin := float(GameData.sell_price(rid)) / float(raw)
		assert(margin >= lo and margin <= hi, "%s 마진 대역(%.2f~%.2f) 밖: %.3f (재료합 %d)" % [rid, lo, hi, margin, raw])
		# 요리는 산출물 집합에만 든다 — 도감·씨앗 순환은 오염시키지 않는다
		assert(GameData.is_produce(rid), "%s 판매·선물 대상" % rid)
		assert(not GameData.is_collectible(rid), "%s 도감 대상 아님" % rid)
		assert(not (rid in GameData.all_seed_ids()), "%s 씨앗 순환 밖" % rid)
		for nid in GameData.npcs:  # 선물 취향 목록은 특정 id만 참조 = 요리는 항상 neutral
			for tier in ["loved", "liked", "disliked"]:
				assert(not (rid in GameData.npcs[nid].get("gifts", {}).get(tier, [])), "%s 취향 목록에 요리" % nid)
	# ── 계절 커버리지: 어느 계절이든 그 계절 재료만으로 만드는 요리가 하나씩 있다.
	# 겨울은 작물이 0이지만 채집·낚시 산출이 있으므로 이제 겨울도 이 계약에 든다.
	for s in GameData.SEASON_IDS:
		var found := ""
		for rid in GameData.recipes:
			var all_in := true
			for iid in GameData.recipes[rid]["ingredients"]:
				if not (s in _item_seasons(iid)):
					all_in = false
					break
			if all_in:
				found = rid
				break
		assert(found != "", "%s 제철 재료만으로 만드는 요리 없음" % s)
	# ── 요리 실행 (씬 트리 없이 순수 로직)
	var p: Node = preload("res://player/player.gd").new()
	assert(not p.can_cook("dish.salad"), "재료 0 = 요리 불가")
	assert(not p.cook("dish.salad"), "재료 없이 요리 실패")
	assert(p.inventory.is_empty(), "실패한 요리는 인벤 무변경")
	assert(not p.can_cook("dish.없음"), "모르는 레시피 = 불가")
	p._add_item("crop.turnip", 2)
	p._add_item("crop.cabbage", 1)
	assert(p.can_cook("dish.salad"), "재료 충족")
	assert(p.cook("dish.salad"), "요리 성공")
	assert(p.count("dish.salad") == 1, "요리 1개 획득")
	assert(p.count("crop.turnip") == 1 and p.count("crop.cabbage") == 0, "재료만 정확히 차감")
	assert(not p.can_cook("dish.salad"), "재료 소진 = 재요리 불가")
	assert(not ("dish.salad" in p.collection), "요리는 도감 미등록")
	assert("crop.turnip" in p.collection, "재료(자연 산출물)는 도감 등록 유지")
	# 판매상자: farm.deposit은 is_produce 게이트 하나만 본다 → 요리도 팔린다
	assert(_farm.deposit("dish.salad", 1) == 1, "판매상자가 요리 수락")
	assert(GameData.sell_price("dish.salad") > 0, "정산 가격 해석")
	_farm.shipping_bin.clear()  # 다음 취침 정산에 끼어들지 않게
	# 선물: 취향 목록 밖 = neutral (크래시 없음)
	_npcsys.state["npc.tom"]["gifted_today"] = false
	var g: Dictionary = _npcsys.give("npc.tom", "dish.salad")
	assert(g["ok"] and "받음" in String(g["msg"]), "요리 선물 = neutral: %s" % str(g["msg"]))
	p.free()
	# ── 스토브 배치 계약: 실내 문·침대와 프롬프트가 겹치지 않는다 (단일 판정이 서로를 먹지 않게)
	var I := preload("res://world/interior.gd")
	const PLAYER_R := 1.3
	assert(I.inside(I.STOVE_AT), "스토브가 실내")
	assert(I.STOVE_AT.distance_to(I.IN_DOOR) > I.STOVE_R + PLAYER_R, "스토브와 실내 문 이격 (%.2f)" % I.STOVE_AT.distance_to(I.IN_DOOR))
	assert(I.STOVE_AT.distance_to(I.BED_CENTER) > I.STOVE_R + PLAYER_R, "스토브와 침대 이격")
	# ── 세이브 표면: 새 아이템 id는 인벤토리 자유형 리스트에 흡수 = 포맷 무변경
	assert(SaveManager.VERSION == 5, "요리 추가 = 세이브 포맷 무변경 (VERSION 5 유지)")

# ── 문맥 반응 대사: 상황이 바뀌면 실제로 다른 풀에서 말이 나오는가 ────────────
# 옛 판은 아키타입당 평상시 3줄 고정이라 생일에도 폭우에도 하트 10칸에도 같은 말을 했다.
# 여기서 핀하는 건 "대사가 많다"가 아니라 **우선순위 사슬이 실제로 갈라지는가**다.
# 대사 줄 내용은 콘텐츠라 자주 바뀌므로 문장을 박지 않고, 어느 풀에서 나왔는지로 본다.
func _union_pool(id: String, keys: Array) -> Array:
	var pools: Dictionary = GameData.dialogues[String(GameData.npcs[id]["archetype"])]
	var out := []
	for k in keys:
		out.append_array(pools.get(k, []))
	return out

func _test_dialogue_context() -> void:
	var id := "npc.mira"
	var arche := String(GameData.npcs[id]["archetype"])
	var day0 := GameClock.abs_day
	var min0 := GameClock.game_min
	var st0: Dictionary = _npcsys.state[id].duplicate()
	_npcsys._festival_active = false
	_npcsys._festival_id = ""
	GameClock.game_min = 600

	# ── 1. 어느 상황에서도 빈 대사가 나오지 않는다(빈 문자열 = 이름만 뜨는 토스트).
	# 사슬 맨 끝 "normal"이 전 아키타입에 있으므로 폴백은 항상 성립해야 한다.
	for nid in GameData.npcs:
		for sea in GameClock.SEASONS.size():
			GameClock.abs_day = sea * GameClock.DAYS_PER_SEASON + 3
			assert(_npcsys._dialogue_line(nid) != "", "%s 계절 %d 대사가 빈 문자열" % [nid, sea])

	# ── 2. 계절이 바뀌면 풀이 갈린다 (평상 3줄 돌려막기가 아니게 된 근거)
	var seen_pools := {}
	for sea in GameClock.SEASONS.size():
		GameClock.abs_day = sea * GameClock.DAYS_PER_SEASON + 3
		var k := "normal." + GameData.season_id(sea)
		assert(k in _npcsys._ambient_keys(id), "%s 후보에 계절 풀 없음" % k)
		assert(not GameData.dialogues[arche].get(k, []).is_empty(), "%s 계절 대사 미작성" % k)
		seen_pools[k] = true
	assert(seen_pools.size() == 4, "네 계절이 서로 다른 풀을 쓴다 (실제 %d)" % seen_pools.size())

	# ── 3. 생일이 계절·평상을 이긴다. 선물 ×8 보너스가 있는 날인데 대사가 평소와 같으면
	# 그날이 특별한 날이라는 신호가 화면에 하나도 안 남는다.
	var b: Dictionary = GameData.npcs[id]["birthday"]
	var bsea := GameData.SEASON_IDS.find(String(b["season"]))
	GameClock.abs_day = bsea * GameClock.DAYS_PER_SEASON + int(b["day"]) - 1
	assert(_npcsys._is_birthday(id), "전제: 오늘이 생일")
	assert(_npcsys._event_keys(id)[0] == "birthday", "생일이 최우선이 아님: %s" % str(_npcsys._event_keys(id)))
	assert(_npcsys._dialogue_line(id) in GameData.dialogues[arche]["birthday"], "생일인데 생일 대사가 아님")

	# ── 4. 비 오는 날. 날씨는 GameData.is_rainy(abs_day) 단일 출처라 실제 비 오는 날을 찾아 쓴다.
	var rainy := -1
	for d in 120:
		GameClock.abs_day = d
		if GameData.is_rainy(d) and not _npcsys._is_birthday(id):
			rainy = d
			break
	assert(rainy >= 0, "1년 안에 비 오는 날이 없다(날씨 데이터 전제 붕괴)")
	GameClock.abs_day = rainy
	var keys_rain: Array = _npcsys._ambient_keys(id)
	assert("rain" in keys_rain, "비 오는 날인데 rain 풀이 후보에 없음")
	assert(_npcsys._dialogue_line(id) in _union_pool(id, keys_rain), "비 오는 날 대사가 상시 풀 밖")

	# ── 5. 선물을 준 다음 날 그걸 언급한다 = "날 기억한다"의 정체.
	GameClock.abs_day = 16  # 생일(봄 12일 = abs_day 11)을 피한다 — 생일이 사건 우선순위 위다
	_npcsys.state[id]["gifted_today"] = false
	_npcsys.state[id]["affection_points"] = 0
	_npcsys.give(id, "crop.strawberry")
	assert(int(_npcsys.state[id]["last_gift_day"]) == 16, "선물 날짜 기록 안 됨")
	GameClock.abs_day = 17
	assert("gift_thanks" in _npcsys._event_keys(id), "선물 다음 날 언급 안 함")
	assert(_npcsys._dialogue_line(id) in GameData.dialogues[arche]["gift_thanks"], "사건 풀이 상시를 못 이김")
	GameClock.abs_day = 19  # 사흘 뒤엔 더 안 꺼낸다(계속 고맙다고 하면 오히려 어색하다)
	assert(not ("gift_thanks" in _npcsys._event_keys(id)), "선물 얘기가 사흘째 계속됨")

	# ── 6. 관계가 자라면 말투가 바뀐다. 하트가 숫자로만 오르면 호감도 시스템이 안 읽힌다.
	GameClock.abs_day = 17
	_npcsys.state[id]["affection_points"] = (_npcsys.HEART_WARM - 1) * _npcsys.HEART
	assert(not ("heart_high" in _npcsys._ambient_keys(id)), "임계 미만인데 친밀 대사")
	_npcsys.state[id]["affection_points"] = _npcsys.HEART_WARM * _npcsys.HEART
	assert("heart_high" in _npcsys._ambient_keys(id), "하트 %d칸인데 친밀 대사 없음" % _npcsys.HEART_WARM)

	# ── 6b. 굶김 방지 (Codex 지적). 상시 조건은 **한번 켜지면 계속 참**이라, 이걸 사건처럼
	# 한 줄로 세우면 하트 7칸을 넘긴 순간부터 비도 계절도 영영 안 나온다 — 하필 가장 자주
	# 말 거는 주민이 두 줄에 갇힌다. 친밀 상태에서도 배경 풀이 살아 있는지 실제로 뽑아 본다.
	GameClock.abs_day = rainy
	var warm_keys: Array = _npcsys._ambient_keys(id)
	for need in ["heart_high", "rain", "normal." + GameData.season_id(GameClock.season()), "normal"]:
		assert(need in warm_keys, "친밀+비 상황에서 %s 풀이 굶었다: %s" % [need, str(warm_keys)])
	var hit := {}
	for _i in 300:
		hit[_npcsys._dialogue_line(id)] = true
	var from_rain := false
	var from_warm := false
	for ln in hit:
		if ln in GameData.dialogues[arche]["rain"]:
			from_rain = true
		if ln in GameData.dialogues[arche]["heart_high"]:
			from_warm = true
	assert(from_rain and from_warm, "친밀 상태가 날씨 대사를 굶기거나 그 반대 (비 %s / 친밀 %s)" % [from_rain, from_warm])

	# 배우자는 부부 인사가 덮어쓴다(매일 첫 대화 연출) — 대신 계절 변형으로 두 줄을 면한다
	var sp0: String = _npcsys.spouse
	_npcsys.spouse = id
	var mkey := "married." + GameData.season_id(GameClock.season())
	assert(not GameData.dialogues[arche].get(mkey, []).is_empty(), "%s 부부 계절 대사 미작성" % mkey)
	assert(_npcsys._dialogue_line(id) in GameData.dialogues[arche][mkey], "배우자인데 부부 계절 대사가 안 나옴")
	_npcsys.spouse = sp0

	# ── 7. 세이브 왕복: last_gift_day가 살아남아야 다음 날 대사가 유지된다.
	var blob: Dictionary = _npcsys.save_data()
	_npcsys.state[id]["last_gift_day"] = -1
	_npcsys.load_data(blob)
	assert(int(_npcsys.state[id]["last_gift_day"]) == 16, "last_gift_day 세이브 왕복 실패")
	# 구세이브(그 필드가 없던 판)는 -1로 흡수 — 마이그레이션 없이 로드된다
	var old_blob := {id: {"affection_points": 50, "talked_today": false, "gifted_today": false, "dates_seen": 0}}
	_npcsys.load_data(old_blob)
	assert(int(_npcsys.state[id]["last_gift_day"]) == -1, "구세이브에서 last_gift_day 기본값 흡수 실패")

	GameClock.abs_day = day0
	GameClock.game_min = min0
	_npcsys.state[id] = st0

# ══ 주민 개성 — 색조 클램프 · 체형 · 유휴 위상 ═══════════════════════
# 셋 다 "모델 한 벌로 여덟을 가르는" 장치다. 그래서 핀은 값이 아니라 **서로 구분되는가**에 박는다 —
# 너무 눌러 전부 회색으로 붙거나 위상이 한 점에 몰리면 복제감은 오히려 더 심해진다.
func _test_npc_personality() -> void:
	var N := preload("res://npc/npc_system.gd")
	# ── ① 채도·밝기 클램프 (순수 함수)
	var glow := Color(0.95, 0.72, 0.55)   # 상점 주민 원본 = 정오 클리핑 상한(0.745) 초과
	var cl: Color = N.village_tint(glow)
	assert(maxf(cl.r, maxf(cl.g, cl.b)) <= N.NPC_VAL_CEIL + 0.001, "밝기 천장 초과 (%s)" % str(cl))
	assert(_hsat(cl) <= N.NPC_SAT_CAP + 0.001, "채도 상한 초과 (%.3f)" % _hsat(cl))
	assert(absf(_hsat(cl) - _hsat(glow)) < 0.001, "밝기 축소는 비율 유지 = 채도가 보존돼야 한다")
	assert(_hsat(N.village_tint(Color(0.88, 0.58, 0.32))) <= N.NPC_SAT_CAP + 0.001, "형광 주황 채도 클램프")
	var tame := Color(0.62, 0.45, 0.32)   # 이미 마을 대역 안 = 항등
	assert(N.village_tint(tame).is_equal_approx(tame), "대역 안이면 손대지 않는다")
	# 클램프 후에도 여덟이 서로 구분되는가. 최소 거리 0.10 = 실측 최근접쌍(분홍-살구)이 0.137이라
	# 상한을 조금 더 내려도 버티고, 전부 회색으로 붙이는 값(0.4 이하)에선 즉시 터진다.
	var tints: Array[Color] = []
	for id in GameData.npcs:
		var cc: Array = GameData.npcs[id]["color"]
		tints.append(N.village_tint(Color(cc[0], cc[1], cc[2])))
	var mind := INF
	for i in tints.size():
		for j in range(i + 1, tints.size()):
			mind = minf(mind, _cdist(tints[i], tints[j]))
	assert(mind > 0.10, "클램프 후 주민 색이 서로 붙음 (최소 거리 %.3f)" % mind)
	# ── ② 체형 (npcs.json 옵션 필드)
	assert(N.body_scale({}) == Vector2.ONE, "미지정 = 1.0 (옛 동작)")
	assert(N.body_scale({"height": 5.0, "build": 0.0}) == Vector2(N.BUILD_MIN, N.HEIGHT_MAX), "범위 밖 데이터는 잘린다")
	var hs := []
	var bs := []
	for id in GameData.npcs:
		var d: Dictionary = GameData.npcs[id]
		var h := float(d.get("height", 1.0))
		var b := float(d.get("build", 1.0))
		assert(h >= N.HEIGHT_MIN and h <= N.HEIGHT_MAX, "%s height 범위 밖 %.2f" % [id, h])
		assert(b >= N.BUILD_MIN and b <= N.BUILD_MAX, "%s build 범위 밖 %.2f" % [id, b])
		hs.append(h)
		bs.append(b)
	assert(hs.max() - hs.min() > 0.10 and bs.max() - bs.min() > 0.15, "필드만 늘고 실루엣은 그대로 (h폭 %.2f b폭 %.2f)" % [hs.max() - hs.min(), bs.max() - bs.min()])
	# 상호작용 반경은 체형과 무관해야 한다 — 주민마다 말 걸리는 거리가 달라지면 게임플레이 계약이 깨진다.
	for id in _npcsys._wander:
		var ar: Area3D = _npcsys._wander[id]["area"]
		var sph: SphereShape3D = (ar.get_child(0) as CollisionShape3D).shape
		assert(is_equal_approx(sph.radius, 1.4) and is_equal_approx(ar.position.y, 1.0),
			"%s 상호작용 반경이 체형을 탔다 (r=%.2f y=%.2f)" % [id, sph.radius, ar.position.y])
	# ── ③ 유휴 위상 (결정론 + 흩어짐)
	assert(N.anim_phase(3) == N.anim_phase(3), "같은 순번 = 항상 같은 값(재현성 — randf였다면 여기서 터진다)")
	var ph := []
	for i in GameData.npcs.size():
		var p: float = N.anim_phase(i)
		assert(p >= 0.0 and p < 1.0, "순번 %d 위상이 클립 길이 밖 (%.3f)" % [i, p])
		ph.append(p)
	ph.sort()
	var gap := INF
	for i in ph.size() - 1:
		gap = minf(gap, ph[i + 1] - ph[i])
	# 황금비 수열은 세 거리 정리로 n=9에서 최소 간격 0.09를 보장한다. 옛 ID 해시 판은 실측 0.003이었다.
	assert(gap > 0.05, "위상이 한 점에 몰림 (최소 간격 %.4f)" % gap)
	assert(ph[ph.size() - 1] - ph[0] > 0.5, "위상이 클립 앞쪽에만 몰림 (폭 %.3f)" % (ph[ph.size() - 1] - ph[0]))
	for i in GameData.npcs.size():
		var sp: float = N.anim_speed(i)
		assert(sp >= 1.0 - N.SPEED_JITTER - 0.001 and sp <= 1.0 + N.SPEED_JITTER + 0.001, "순번 %d 속도 배율 범위 밖 %.4f" % [i, sp])
	assert(N.anim_speed(0) != N.anim_speed(1), "속도가 전원 같으면 시작점만 어긋나고 계속 평행하게 간다")
	# ── ④ **실제로 어긋나 있는가.** 순수 함수만 맞고 호출을 빠뜨리면 화면은 그대로다 —
	# 스폰(_spawn)과 전환(_set_walk) 양쪽을 다 태워 확인한다. 전환 쪽이 옛 판의 함정이었다.
	assert(_phase_spread() == 0, "주민 유휴 애니 위상이 겹침 — 스폰이든 전환이든 한쪽이 위상을 0으로 리셋했다")
	for id in _npcsys._wander:   # idle→walk→idle 왕복 = 전환 경로를 명시로 한 번 더 태운다
		_npcsys._set_walk(id, true)
		_npcsys._set_walk(id, false)
	assert(_phase_spread() == 0, "전환(_set_walk) 뒤 주민 유휴 위상이 다시 겹침 — play()가 위상을 0으로 리셋한다")

# 셰이더 sat_cap과 같은 채도 정의 (max−min)/max
func _hsat(c: Color) -> float:
	var mx := maxf(c.r, maxf(c.g, c.b))
	return 0.0 if mx <= 0.0 else (mx - minf(c.r, minf(c.g, c.b))) / mx

func _cdist(a: Color, b: Color) -> float:
	return Vector3(a.r, a.g, a.b).distance_to(Vector3(b.r, b.g, b.b))

# 지금 재생 중인 주민 유휴 위상 중 겹치는 쌍 수 (0이어야 한다)
func _phase_spread() -> int:
	var pos := []
	for id in _npcsys._wander:
		var ap: AnimationPlayer = _npcsys._wander[id]["anim"]
		if ap != null and ap.is_playing() and ap.current_animation == "idle":
			pos.append(ap.current_animation_position)
	assert(pos.size() >= 8, "주민 유휴 애니가 안 붙음 (%d)" % pos.size())
	var same := 0
	for i in pos.size():
		for j in range(i + 1, pos.size()):
			if absf(pos[i] - pos[j]) < 0.01:
				same += 1
	return same

# ── 밭 작물 겉모습: 실물화 + 성장 단계 + 접지 ──────────────────────
# 옛 판은 25종 전부가 같은 색 상자(0.35×0.7×0.35)를 성장률로 세로만 늘인 것이라 종 구분이
# 색 하나뿐이었다. 여기서 무는 것은 **값이 아니라**: ① 상자 폴백을 아무도 안 타는가
# ② 기른 것과 주운 것이 같은 물건으로 보이는가 ③ 단계가 형태로 갈리는가 ④ 밑동이 흙에 닿는가
# ⑤ 이웃 칸을 안 침범하는가. 전부 **프로덕션이 부르는 함수를 그대로 불러** 자로 잰다
# (인자 사본을 재던 옛 구멍 02b11cd·99e89ac·e1c0540과 같은 실패를 안 반복한다).
func _test_crop_look() -> void:
	var PS := preload("res://common/plant_shapes.gd")
	var TC := preload("res://common/toon_character.gd")
	var F := preload("res://farm/farm_system.gd")

	# ── 1. 데이터: 전 작물에 형태가 있고, 재배 채집물은 형태를 **다시 적지 않는다** ──────
	var own_shapes := {}
	for cid in GameData.crops:
		var yid := GameData.crop_yield(cid)
		if yid != cid:
			# 재배 채집물: 형태도 산출물이 정한다. crops.json에 또 적으면 기른 것과 주운 것이 갈린다.
			assert(not GameData.crops[cid].has("shape"),
				"%s가 형태를 따로 적었다 — 산출물(%s)이 단일 출처다" % [cid, yid])
			assert(not GameData.crops[cid].has("mesh"), "%s가 메시를 따로 적었다" % cid)
			var fd: Dictionary = GameData.forage[yid]
			assert(fd.has("shape") or fd.has("mesh"), "%s 산출물 %s에 형태가 없다" % [cid, yid])
			continue
		# 씨앗을 사서 심는 작물: crops.json의 shape가 표에 있어야 한다. 없으면 조용히 상자가 된다 —
		# 이번 계약의 핵심이라 데이터 쪽에서 막는다(새 작물을 넣고 형태를 안 줘도 여기서 걸린다).
		var shp := String(GameData.crops[cid].get("shape", ""))
		assert(shp != "", "%s — 겉모습 형태 미지정: 색 상자로 떨어진다" % cid)
		assert(PS.SHAPES.has(shp), "%s — 모르는 절차 원형: %s" % [cid, shp])
		assert(not own_shapes.has(shp), "%s와 %s가 같은 원형 — 색만 다른 같은 물건이 된다"
			% [cid, str(own_shapes.get(shp))])
		own_shapes[shp] = cid
	assert(own_shapes.size() == 12, "씨앗 작물 12종에 저마다의 원형 (실제 %d)" % own_shapes.size())

	# ── 2. 단계 판정(순수 함수) ────────────────────────────────────
	# 마지막 단계는 수확 가능해질 때만 — "다 자라 보이는데 못 거두는 칸"을 안 만든다.
	for st in [3, 4]:
		var g := 8
		assert(F.stage_index(0, g, st) == 0, "심은 날은 새싹")
		assert(F.stage_index(g, g, st) == st - 1, "성숙일에 마지막 단계")
		assert(F.stage_index(g + 5, g, st) == st - 1, "재수확 초과분도 마지막 단계")
		var prev := 0
		for d in range(g):
			var s: int = F.stage_index(d, g, st)
			assert(s >= prev and s <= st - 2, "단계가 %d에서 역행하거나 성숙을 앞질렀다(%d)" % [d, s])
			prev = s
		assert(F.stage_index(g - 1, g, st) == st - 2, "성숙 직전은 마지막 바로 앞 단계")
		assert(is_equal_approx(F.stage_scale(st - 1, st), 1.0), "마지막 단계는 원본 크기")
		assert(F.stage_scale(1, st) > 0.4 and F.stage_scale(1, st) < 1.0, "중간 단계는 축소")
	assert(F.stage_scale(1, 4) < F.stage_scale(2, 4), "단계가 오르면 커진다")

	# ── 3. 배선 실측: 프로덕션 crop_look이 **실제로 만드는 노드를 자로 잰다** ──────────
	var w_all := []
	var h_all := []
	var forms := {}
	var widest := ""      # 가장 넓은 종 + 그 실측값 (실패 메시지에 그대로 나간다)
	var widest_w := 0.0
	for cid2 in GameData.crops:
		var stages := int(GameData.crops[cid2].get("stages", 3))
		var node: Node3D = _farm.crop_look(cid2, stages - 1)
		# 상자 폴백을 탔는가. 절차 원형은 SurfaceTool로 구운 ArrayMesh라 BoxMesh가 아니다.
		assert(not (node is MeshInstance3D and (node as MeshInstance3D).mesh is BoxMesh),
			"%s — 색 상자 폴백을 탔다: 형태 지정이 실경로에 안 닿는다" % cid2)
		var ab := TC.aabb_of(node)
		# 접지: 밑동이 흙 윗면에 SINK만큼 박힌다(자리 노드가 흙 윗면에 있으므로 여기선 -SINK).
		assert(absf(ab.position.y + F.SINK) <= 0.006,
			"%s — 밑동이 흙에서 %+.3f (묻히거나 떴다)" % [cid2, ab.position.y + F.SINK])
		# 폭·깊이: 밭 한 칸이 0.92다. 옛 상한 0.80은 킷 메시(송이 0.734·사과 0.617)를 안 물어서
		# 이웃 칸에 붙어 보이는 걸 통과시켰다 — **절대 숫자 0.55**로 조인다(LOOK_W에서 유도하지
		# 않는다: 그 상수가 커지면 문턱도 같이 커져 조용히 통과한다).
		var w: float = maxf(ab.size.x, ab.size.z)
		if w > widest_w:
			widest_w = w
			widest = cid2
		assert(ab.size.y >= 0.18 and ab.size.y <= 0.80,
			"%s — 전고 %.3f가 밭 대역(0.18~0.80) 밖" % [cid2, ab.size.y])
		w_all.append(w)
		h_all.append(ab.size.y)
		var look_shape := String(_farm.crop_look_data(cid2).get("shape", ""))
		# 채집물 쪽과 같은 이유로 **실제로 절차 원형으로 그려진 것만** 센다 — 킷을 쓰는 종의
		# 휴면 폴백 shape가 화면에 없는 계열을 등록하면 계열 수가 부푼다(지금은 그 계열을 다른
		# 작물이 이미 그리고 있어 수가 같지만, 그 우연에 기대면 다음에 조용히 헐거워진다).
		if look_shape != "" and node is MeshInstance3D:
			forms[String(PS.SHAPES[look_shape][0])] = true
		node.free()
	# 실루엣이 갈리는가. 폭과 전고 두 축으로 본다(색 하나로만 갈리던 게 이번 작업의 문제였다).
	# 실측(2026-08-31): 폭 0.132(이삭 모양 꽃대)~0.520(킷·폭 상한) = 3.93배 · 전고 0.195(땅에 깔린
	# 열매 포기)~0.640(키 큰 대) = 3.27배. 가장 넓은 종도 밭 한 칸 0.92 안에 0.20씩 여유가 남는다.
	w_all.sort()
	h_all.sort()
	assert(w_all.size() == 25, "밭 작물 25종 (실제 %d)" % w_all.size())
	assert(widest_w <= 0.55, "가장 넓은 작물 %s가 폭 %.3f — 상한 0.55를 넘어 밭 한 칸(0.92)에서 이웃 칸에 붙는다"
		% [widest, widest_w])
	assert(w_all[-1] / w_all[0] >= 1.8, "작물 폭이 %.2f배밖에 안 갈린다" % (w_all[-1] / w_all[0]))
	assert(h_all[-1] / h_all[0] >= 1.8, "작물 전고가 %.2f배밖에 안 갈린다" % (h_all[-1] / h_all[0]))
	assert(forms.size() >= 6, "형태 계열이 %d종뿐 — 25종이 몇 실루엣으로 뭉친다" % forms.size())

	# ── 4. 기른 것 = 주운 것: 재배 채집물 13종은 채집물과 **같은 메시 한 장**을 쓴다 ───────
	var fs: Node = preload("res://forage/forage_system.gd").new()
	var shared := 0
	for cid3 in GameData.crops:
		var yid3 := GameData.crop_yield(cid3)
		if yid3 == cid3:
			continue
		var grown: Node3D = _farm.crop_look(cid3, int(GameData.crops[cid3].get("stages", 3)) - 1)
		var picked: Node3D = fs._look(yid3, GameData.forage[yid3].get("rare", false))
		var gm := _first_mesh(grown)
		var pm := _first_mesh(picked)
		assert(gm != null and pm != null, "%s 겉모습에 메시가 없다" % cid3)
		# 캐시 키가 산출물 id라 **같은 메시 한 장**이다 — 절차 원형이든 킷 메시(gltf)든.
		# 킷만 캐시가 없어서 여기가 예외였고, 그래서 그릴 때마다 gltf를 통째로 다시 읽었다.
		assert(gm == pm, "%s — 기른 것과 주운 것(%s)이 다른 메시를 쓴다" % [cid3, yid3])
		var gs := TC.aabb_of(grown).size
		var ps := TC.aabb_of(picked).size
		assert((gs - ps).length() <= 0.01,
			"%s — 기른 것과 주운 것(%s)의 크기가 다르다 (%s vs %s)" % [cid3, yid3, str(gs), str(ps)])
		# 색도 같은 물건으로 읽혀야 한다(형태만 같고 색이 갈리면 여전히 다른 물건이다)
		assert(_look_color(grown).is_equal_approx(_look_color(picked)),
			"%s — 기른 것과 주운 것의 색이 갈린다" % cid3)
		grown.free()
		picked.free()
		shared += 1
	assert(shared == 13, "재배 채집물 13종이 채집물 형태를 그대로 쓴다 (실제 %d)" % shared)
	fs.free()

	# ── 5. 새싹은 공용 한 장, 종별 메시는 종당 한 장 ───────────────
	var ids: Array = GameData.crops.keys()
	var sp_a: Node3D = _farm.crop_look(ids[0], 0)
	var sp_b: Node3D = _farm.crop_look(ids[-1], 0)
	assert(_first_mesh(sp_a) == _first_mesh(sp_b), "새싹이 종마다 따로 깎인다(공용 한 장 계약)")
	assert(TC.aabb_of(sp_a).size.y < 0.20, "새싹이 다 자란 작물만 하다")
	sp_a.free()
	sp_b.free()
	var last_st: int = int(GameData.crops[ids[0]].get("stages", 3)) - 1
	var m_a: Node3D = _farm.crop_look(ids[0], last_st)
	var m_b: Node3D = _farm.crop_look(ids[0], last_st)
	assert(_first_mesh(m_a) == _first_mesh(m_b), "%s — 그릴 때마다 메시를 새로 깎는다" % ids[0])
	m_a.free()
	m_b.free()

	# ── 6. 단계가 실제로 형태로 갈리는가 (전 작물, 프로덕션 경로) ───
	for cid4 in GameData.crops:
		var st4 := int(GameData.crops[cid4].get("stages", 3))
		var last := -1.0
		for s4 in st4:
			var nd: Node3D = _farm.crop_look(cid4, s4)
			var hh: float = TC.aabb_of(nd).size.y
			assert(hh > last, "%s 단계 %d에서 전고가 안 커진다 (%.3f ≤ %.3f)" % [cid4, s4, hh, last])
			last = hh
			nd.free()

	# ── 7. 실경로 접지·휴면: **씬에 실제로 붙은 노드**를 잰다 ──────
	# 위까지는 crop_look 반환값이다 = _refresh가 그걸 안 쓰고 옛 상자를 그려도 통과한다.
	# 여기선 till→plant→_refresh를 태우고 밭에 서 있는 노드를 재서 그 통로를 막는다.
	var per := ""   # 다년생(휴면 표현을 볼 종)
	for cid5 in GameData.crops:
		if GameData.crop_perennial(cid5):
			per = cid5
			break
	assert(per != "", "다년생이 없어 휴면 표현을 못 잰다")
	var plant_s := ""
	var off_s := ""
	for s5 in GameData.SEASON_IDS:
		if plant_s == "" and GameData.crop_plantable(per, s5):
			plant_s = s5
		if off_s == "" and not GameData.crop_in_season(per, s5):
			off_s = s5
	assert(plant_s != "" and off_s != "", "%s의 제철/비제철 계절을 못 고름" % per)
	var cell := _fcell(4, 0)  # 앞선 테스트가 안 쓴 칸
	GameClock.abs_day = GameData.SEASON_IDS.find(plant_s) * GameClock.DAYS_PER_SEASON + 2
	assert(_farm.till(cell) and _farm.plant(cell, GameData.crops[per]["seed_id"]), "심기")
	_farm.tiles[cell]["watered_growth_days"] = GameData.grow_days(per)
	# 제철: 다 자란 실물이 흙 위에 선다
	GameClock.abs_day = GameData.SEASON_IDS.find(GameData.crops[per]["seasons"][0]) * GameClock.DAYS_PER_SEASON + 2
	_farm._refresh(cell)
	var slot: Node3D = _farm._nodes[cell]["crop"]
	assert(slot.get_child_count() == 1, "밭 칸에 겉모습 노드가 하나가 아니다(%d)" % slot.get_child_count())
	var wab := TC.aabb_of(slot)  # slot.transform 포함 = 밭 좌표계(=월드) y
	assert(absf(wab.position.y - (F.SOIL_TOP - F.SINK)) <= 0.006,
		"%s — 밭에 선 밑동이 흙 윗면에서 %+.3f" % [per, wab.position.y - F.SOIL_TOP])
	assert(maxf(wab.size.x, wab.size.z) <= 0.55, "%s — 밭에서 폭 %.3f" % [per, maxf(wab.size.x, wab.size.z)])
	var ripe_col := _look_color(slot)
	assert(not ripe_col.is_equal_approx(F.DORMANT), "제철 작물이 휴면색으로 그려졌다")
	# 휴면: 계절만 넘긴다. 그루는 남되 열매색이 사라져야 한다("다 자랐는데 왜 수확이 안 되지" 방지)
	GameClock.abs_day = GameData.SEASON_IDS.find(off_s) * GameClock.DAYS_PER_SEASON + 2
	_farm._refresh(cell)
	assert(slot.visible and slot.get_child_count() >= 1, "휴면 중에도 그루는 밭에 남는다")
	assert(_look_color(slot).is_equal_approx(F.DORMANT),
		"%s 휴면이 성숙과 구분이 안 된다 (%s)" % [per, str(_look_color(slot))])
	# 세이브 표면 무변경: 밭 타일 딕셔너리에 겉모습 필드가 새면 구세이브가 갈린다
	var keys: Array = _farm.tiles[cell].keys()
	keys.sort()
	assert(keys == ["crop_id", "planted_abs_day", "tilled", "watered", "watered_growth_days"],
		"밭 타일에 필드가 늘었다: %s" % str(keys))
	_farm.tiles.erase(cell)
	_farm._refresh(cell)  # 뒷 테스트가 쓰는 밭을 원상복구

	# ── 8. 형태 배정이 데이터에서 오는가 (엔진에 종 이름 금지) ─────
	var src := FileAccess.get_file_as_string("res://farm/farm_system.gd")
	for cid6 in GameData.crops:
		var bare: String = cid6.get_slice(".", 1)
		assert(not src.contains(bare), "farm_system.gd에 종 이름이 하드코딩됐다: %s" % bare)

# ── 휴면 그루: 색이 아니라 **형태**가 "열매 없음"을 말하는가 ────────────
# 옛 판은 다 자란 실물을 그대로 깎아 놓고 노드를 갈색으로 덮기만 했다 — 실루엣이 성숙과 한 치도
# 안 달라서 화면에선 그냥 **갈색 열매**였다(실측 crops/winter_fix: 밭에 갈색 돌 셋). 색으로 재면
# 그 옛 판도 통과한다(_paint 한 줄이면 색은 언제나 맞다) — 그래서 여기선 till→plant→_refresh를
# 태워 **밭에 실제로 선 노드**의 메시와 AABB를 잰다. 문턱은 전부 절대 숫자다.
func _test_dormant_look() -> void:
	var TC := preload("res://common/toon_character.gd")
	var cell := _fcell(5, 0)   # 앞선 테스트가 안 쓴 칸
	var measured := 0
	var kit_seen := 0     # 제철엔 킷 메시를 쓰는 종(휴면에선 절차 원형으로 흘러야 한다)
	var kit_want := 0
	for cid in GameData.crops:
		if not GameData.crop_perennial(cid):
			continue
		# 제철·비제철·심는 계절을 전부 데이터에서 고른다(엔진에도 테스트에도 종 이름을 안 박는다)
		var on_s := ""
		var off_s := ""
		var plant_s := ""
		for s in GameData.SEASON_IDS:
			if on_s == "" and GameData.crop_in_season(cid, s):
				on_s = s
			if off_s == "" and not GameData.crop_in_season(cid, s):
				off_s = s
			if plant_s == "" and GameData.crop_plantable(cid, s):
				plant_s = s
		assert(on_s != "" and off_s != "" and plant_s != "",
			"%s의 제철(%s)/비제철(%s)/심는 계절(%s)을 못 고름" % [cid, on_s, off_s, plant_s])
		if _farm.crop_look_data(cid).has("mesh"):
			kit_want += 1
		_farm.tiles.erase(cell)
		_farm._refresh(cell)
		GameClock.abs_day = GameData.SEASON_IDS.find(plant_s) * GameClock.DAYS_PER_SEASON + 2
		assert(_farm.till(cell) and _farm.plant(cell, GameData.crops[cid]["seed_id"]),
			"%s 심기 실패(%s)" % [cid, plant_s])
		_farm.tiles[cell]["watered_growth_days"] = GameData.grow_days(cid)
		var slot: Node3D = _farm._nodes[cell]["crop"]
		# 제철: 다 자란 실물
		GameClock.abs_day = GameData.SEASON_IDS.find(on_s) * GameClock.DAYS_PER_SEASON + 2
		_farm._refresh(cell)
		var ripe: Node3D = slot.get_child(0)
		var rm := _first_mesh(ripe)
		var rs := TC.aabb_of(ripe).size
		if not (ripe is MeshInstance3D):
			kit_seen += 1   # 킷은 노드 묶음이다(절차 원형은 MeshInstance3D 한 장)
		assert(rm != null and rm.get_surface_count() >= 1, "%s 성숙 메시가 비었다" % cid)
		# 휴면: 계절만 넘긴다
		GameClock.abs_day = GameData.SEASON_IDS.find(off_s) * GameClock.DAYS_PER_SEASON + 2
		_farm._refresh(cell)
		var dorm: Node3D = slot.get_child(0)
		var ds := TC.aabb_of(dorm).size
		# ① 킷 경로를 안 탄다. 킷 메시는 통째로 한 덩어리라 먹는 부분을 떼어낼 수가 없다.
		assert(dorm is MeshInstance3D,
			"%s 휴면이 킷 노드 묶음(%s)으로 갔다 — 킷은 표면을 못 나눠서 색만 갈리게 된다"
			% [cid, dorm.get_class()])
		var dm := (dorm as MeshInstance3D).mesh as ArrayMesh
		# ② 캐시 키에 휴면이 들어갔는가. 안 들어가면 먼저 만든 성숙 메시를 그대로 돌려준다.
		assert(dm != rm, "%s 휴면이 성숙과 **같은 메시 인스턴스**다 — 캐시 키에 휴면이 없다" % cid)
		# ③ 종 색 표면(먹는 부분)이 아예 없다. 정점 수가 아니라 표면 자체를 센다 —
		#    빈 표면을 붙이면 곁들이가 표면 1로 밀려 잎이 종 색으로 칠해진다(실측: 빈
		#    SurfaceTool의 commit()은 표면 0개짜리 메시를 낸다).
		assert(dm.get_surface_count() == 1,
			"%s 휴면 메시 표면이 %d개 — 먹는 부분이 아직 깎여 있다" % [cid, dm.get_surface_count()])
		var dmat := dm.surface_get_material(0) as ShaderMaterial
		assert(dmat != null, "%s 휴면 표면에 머티리얼이 없다" % cid)
		var dalb = dmat.get_shader_parameter("albedo")   # 미설정이면 null — float()로 죽지 않게 존재부터 본다
		assert(dalb is Color, "%s 휴면 표면 albedo가 %s" % [cid, str(dalb)])
		assert(not (dalb as Color).is_equal_approx(_farm.crop_color(cid)),
			"%s 휴면 표면이 종 색(%s)으로 칠해졌다 — 표면 인덱스가 한 칸 밀렸다" % [cid, str(dalb)])
		# ④ 성숙 쪽엔 종 색 표면이 실제로 있다(위 ③이 "원래 없던 것"을 재고 있으면 안 된다)
		if ripe is MeshInstance3D:
			var rmat := rm.surface_get_material(0) as ShaderMaterial
			var ralb = rmat.get_shader_parameter("albedo") if rmat != null else null
			assert(ralb is Color and (ralb as Color).is_equal_approx(_farm.crop_color(cid)),
				"%s 성숙 표면 0이 종 색이 아니다 (%s)" % [cid, str(ralb)])
			var rv: int = rm.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
			assert(rv > 0, "%s 성숙 열매 표면에 정점이 0개" % cid)
		# ⑤ 실루엣이 실제로 달라졌다. 부피비로는 못 잡는다 — 마른 가지가 좁고 긴 원형보다
		#    옆으로 넓어지는 경우가 있어 커지기도 한다. 세 축의 차이를 그대로 잰다.
		#    실측(2026-08-31) 최소 0.094(잎만 마르는 종) ~ 최대 0.21 — 0.05면 여유가 있다.
		assert((ds - rs).length() >= 0.05,
			"%s 휴면 실루엣이 성숙과 사실상 같다 (%s vs %s)" % [cid, str(ds), str(rs)])
		# ⑥ 밭 한 칸(0.92)을 안 넘고 대역 안에 있다 — 마른 가지가 옆칸으로 퍼지면 안 된다
		assert(maxf(ds.x, ds.z) <= 0.55, "%s 휴면 폭 %.3f" % [cid, maxf(ds.x, ds.z)])
		assert(ds.y >= 0.12, "%s 휴면 전고 %.3f — 빈 칸으로 읽힌다" % [cid, ds.y])
		measured += 1
	assert(measured >= 6, "휴면을 잰 다년생이 %d종뿐 — 루프가 거의 안 돌았다" % measured)
	assert(kit_want >= 2, "킷 메시를 쓰는 다년생이 %d종 — 이 핀이 킷 경로를 안 잰다" % kit_want)
	assert(kit_seen == kit_want,
		"제철에 킷 노드로 그려진 종이 %d개인데 데이터상 %d개다" % [kit_seen, kit_want])
	_farm.tiles.erase(cell)
	_farm._refresh(cell)  # 뒷 테스트가 쓰는 밭을 원상복구

# ── 화면에 나가는 통화 표기가 한국어인가 ───────────────────────────────
# 화면 이름을 전부 한국어로 간 뒤에도 통화 접미사 "G"만 세 곳에 남아 있었다. 그중 하나는
# 한 문장 안에서 "골드"와 "G"를 같이 썼고, 가방의 반지 행은 같은 위젯의 두 갈래에서 G가
# **통화 단위와 키보드 키 두 뜻**으로 쓰였다("1200G" 옆에 "후보에게 G = 청혼").
#
# 그려진 라벨을 읽는 쪽은 안 골랐다: 이 문자열들은 상점 앞·청혼 가능·요리 가능 같은 상태에서만
# 그려져서 테스트가 그 상태를 셋 다 만들어야 하는데, 정작 재려는 것은 "소스에 남았나"라
# 통로만 길어진다. farm_system의 종 이름 하드코딩 핀과 같은 수법으로 소스를 훑는다.
# 키 안내의 "G"는 정당한 사용이라 갈라야 하는데 — **통화는 언제나 수량 바로 뒤에 붙는다**
# ("%dG"·"1200G"). 그 자리에만 문다. 키 안내는 수량 뒤에 오지 않는다.
func _test_currency_korean() -> void:
	var re := RegEx.new()
	re.compile("(%[ds]|[0-9])G")
	# 검출기 자가검사. 이게 없으면 정규식이 무엇도 못 잡게 망가져도 "0건 = 통과"가 된다.
	assert(re.search('"잔액 500G"') != null, "검출기가 통화 G를 못 잡는다 — 정규식이 죽었다")
	assert(re.search('"%dG 필요"') != null, "검출기가 서식 통화 G를 못 잡는다")
	assert(re.search('"후보에게 G키 = 청혼"') == null, "검출기가 키 안내를 통화로 오인한다")
	var scanned := 0
	var korean := 0     # "골드" 표기가 실제로 쓰이는 파일 수 = UI를 훑고 있다는 증거
	var bad := []
	for dir in ["res://ui/", "res://player/", "res://npc/", "res://world/"]:
		for f in DirAccess.get_files_at(dir):
			if not f.ends_with(".gd"):
				continue
			scanned += 1
			var src := FileAccess.get_file_as_string(dir + f)
			if src.contains("골드"):
				korean += 1
			var ln := 0
			for line in src.split("\n"):
				ln += 1
				# 주석 줄은 건너뛴다 — 화면에 안 나가고, 옛 표기를 설명하는 주석까지 물면
				# 다음 사람이 "왜 이렇게 고쳤나"를 못 적게 된다. 코드 줄 뒤 주석은 그대로 문다.
				if line.strip_edges().begins_with("#"):
					continue
				if re.search(line) != null:
					bad.append("%s:%d  %s" % [dir + f, ln, line.strip_edges()])
	assert(scanned >= 12, "화면 소스를 %d개만 훑었다 — 경로가 바뀌어 아무것도 안 재고 있다" % scanned)
	assert(korean >= 2, "'골드' 표기가 %d개 파일에만 있다 — 훑는 대상이 UI가 아니다" % korean)
	assert(bad.is_empty(), "화면에 통화 G가 남았다(한국어 '골드'로):\n%s" % "\n".join(bad))

# 메시가 제 AABB를 얼마나 채우는가(0~1). 겹쳐 붙인 폐곡면들의 부피 합 ÷ 상자 부피 —
# "꽉 찬 덩어리(열매·견과)"와 "성긴 마른 것(깍지·가지)"을 가르는 자다. 실루엣 비율만으로는
# 길쭉한 견과와 깍지가 안 갈려서 이 축이 필요하다.
func _mesh_fill(m: ArrayMesh) -> float:
	var vol := 0.0
	for s in m.get_surface_count():
		var a := m.surface_get_arrays(s)
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		for i in range(0, idx.size(), 3):
			vol += absf(v[idx[i]].dot(v[idx[i + 1]].cross(v[idx[i + 2]]))) / 6.0
	var s2 := m.get_aabb().size
	return vol / maxf(s2.x * s2.y * s2.z, 0.000001)

# 겉모습 노드가 실제로 쓰는 첫 메시 (절차 원형 = 자기 자신, 킷 = 하위 MeshInstance3D)
func _first_mesh(node: Node) -> Mesh:
	if node is MeshInstance3D:
		return (node as MeshInstance3D).mesh
	for c in node.get_children():
		var m := _first_mesh(c)
		if m != null:
			return m
	return null

# ── 채집물 재배 + 다년생 ────────────────────────────────────────
# ⚠ 최대 함정은 기른 것과 주운 것이 **다른 아이템**으로 갈리는 것이다(요리·선물·도감이 두 갈래).
# 그래서 json 정합만 보지 않고, 실제로 심어 키워 **수확된 id를 재고** 그걸 그대로 선물해 본다.
# 종 이름은 한 줄도 안 박는다 — 조건(다년생·겨울에 열림·가을에 심음)으로 데이터에서 골라 온다.
func _test_forage_crops() -> void:
	# ── 0. 심는 계절 ↔ 열리는 계절의 정합 (전 종 공통)
	# 심을 수 있는데 그 계절엔 안 열리는 종(가을에 심어 겨울에 여는 다년생)은 **반드시 다년생**이어야
	# 한다. 아니면 심은 다음 아침 _season_deaths가 조용히 없애 주운 아이템만 증발한다.
	for cid in GameData.crops:
		for s in GameData.SEASON_IDS:
			if GameData.crop_plantable(cid, s) and not GameData.crop_in_season(cid, s):
				assert(GameData.crop_perennial(cid),
					"%s: %s에 심는데 그 계절엔 안 열린다 — 다년생이 아니면 다음 아침 고사" % [cid, s])

	# ── 1. 데이터: 재배 항목 ↔ 채집물 아이템 계약
	var grown := {}  # 채집물 id → 그것을 맺는 재배 항목 id
	for cid in GameData.crops:
		var yid := GameData.crop_yield(cid)
		if yid == cid:
			continue  # 씨앗을 사서 심는 기존 작물
		assert(GameData.forage.has(yid), "%s 산출물이 채집물이 아님: %s" % [cid, yid])
		assert(not grown.has(yid), "%s와 %s가 같은 채집물을 맺는다: %s" % [cid, str(grown.get(yid)), yid])
		grown[yid] = cid
		# 씨앗은 산출물 그 자체이거나(주운 것을 그대로 심는다) 야생 전용 씨앗 둘 중 하나다.
		# 후자는 겨울에 열리는 종 몫 — 자세한 계약은 _test_winter_seeds가 문다. 여기선
		# **어느 쪽이든 상점에 없고 도감·판매에 안 샌다**만 본다(초반 공급원 = 들에서 얻는 것).
		var sid_c: String = GameData.crops[cid]["seed_id"]
		assert(sid_c == yid or sid_c in GameData.wild_seed_ids(), "%s 씨앗 출처 불명: %s" % [cid, sid_c])
		if sid_c != yid:
			assert(not GameData.is_produce(sid_c), "%s 전용 씨앗이 산출물로 샌다: %s" % [cid, sid_c])
		# 재배 항목 자체는 아이템이 아니다 — 도감·판매·선물에 유령 항목이 새면 안 된다
		assert(not GameData.is_collectible(cid) and not GameData.is_produce(cid), "%s가 아이템으로 샌다" % cid)
		assert(GameData.is_collectible(yid), "%s 산출물이 도감 대상이 아님" % yid)
		# 이름·값은 산출물 단일 출처 (두 번 적혀 갈리는 순간 여기서 걸린다)
		assert(GameData.display_name(cid) == GameData.display_name(yid), "%s 이름이 산출물과 갈림" % cid)
		assert(GameData.sell_price(cid) == GameData.sell_price(yid), "%s 판매가가 산출물과 갈림" % cid)
		assert(GameData.sell_price(cid) > 0, "%s 판매가 0 — 산출물 해석 실패" % cid)
		# 주울 수 있는 계절엔 밭에서도 열린다(같은 물건이라는 감각이 계절에서 깨지지 않게)
		for s in GameData.forage[yid]["seasons"]:
			assert(GameData.crop_in_season(cid, s), "%s: %s에 주울 수 있는데 밭에선 안 열림" % [cid, s])
	assert(grown.size() == 13, "재배 가능 채집물 13종 (실제 %d)" % grown.size())
	# 버섯은 이번 범위 밖(동굴 해금 후 포자 재배 — DESIGN 6.2). 엔진이 아니라 **데이터가** 막는다:
	# crops.json에 항목이 없으면 자동으로 재배 불가다.
	for fid in GameData.forage:
		if GameData.forage[fid].get("rare", false):
			assert(not grown.has(fid), "%s — 희귀 버섯은 아직 재배 대상이 아니다(동굴 해금 후)" % fid)
	assert(GameData.forage.size() - grown.size() == 3, "재배 불가 채집물 3종(버섯)")
	# 밭 타일에 새 필드를 안 만들었다 = 구세이브가 기본값으로 흡수된다. 무심코 범프하면 여기서 걸린다.
	assert(SaveManager.WORLD_VERSION == 3, "채집물 재배·다년생은 밭 타일 스키마 무변경 = WORLD_VERSION 유지")

	# ── 2. 배선: 가을에 심은 다년생이 겨울 경계를 넘어 살아남고, 겨울에 열린다.
	#    _season_deaths·일변경 성장·수확을 전부 프로덕션 경로(GameClock.sleep_to_morning)로 태운다.
	var wp := ""
	for cid in GameData.crops:
		if GameData.crop_perennial(cid) and GameData.crop_in_season(cid, "winter") \
			and GameData.crop_plantable(cid, "autumn"):
			wp = cid
			break
	assert(wp != "", "겨울에 열리는 다년생이 없다 — 겨울 농장이 성립 안 함")
	var seed_w: String = GameData.crops[wp]["seed_id"]
	var cp := _fcell(0, 0)   # 앞선 테스트가 안 쓴 밭 줄(첫 줄)
	var ca := _fcell(1, 0)
	GameClock.abs_day = 2 * GameClock.DAYS_PER_SEASON  # 가을 D1
	GameClock.game_min = 360
	assert(GameData.season_id(GameClock.season()) == "autumn", "전제: 가을 D1")
	assert(_farm.till(cp) and _farm.till(ca), "가을 괭이질")
	assert(not GameData.crop_plantable(wp, "winter"), "겨울 파종은 여전히 막힌다")
	assert(_farm.plant(cp, seed_w), "겨울에 열리는 다년생은 가을에 심는다")
	# 휴면: 제철이 아닌 동안은 물을 줘도 생장이 안 나아가고, 그래도 안 죽는다
	_farm.water(cp)
	GameClock.sleep_to_morning()
	assert(int(_farm.get_tile(cp)["watered_growth_days"]) == 0, "제철 아닌 동안 휴면(생장 정지)")
	assert(_farm.get_tile(cp)["crop_id"] == wp, "휴면 중에도 다년생은 안 죽는다")
	assert(not _farm.is_mature_at(cp), "제철 아니면 수확 대상 아님")
	# 계절 경계를 실제로 넘긴다: 가을 막날 → 겨울 D1. 한해살이 대조군을 나란히 둔다.
	GameClock.abs_day = 3 * GameClock.DAYS_PER_SEASON - 1
	assert(GameData.season_id(GameClock.season()) == "autumn", "전제: 가을 막날")
	assert(_farm.plant(ca, "seed.corn"), "대조군: 한해살이 가을 작물")
	GameClock.sleep_to_morning()
	assert(GameData.season_id(GameClock.season()) == "winter", "겨울 진입")
	assert(_farm.get_tile(ca)["crop_id"] == "", "대조군 한해살이는 계절 경계에서 고사")
	assert(_farm.get_tile(cp)["crop_id"] == wp, "다년생은 계절 경계에서 살아남는다(_season_deaths 면제)")
	# 겨울 = 제철 → 이제 자란다 → 수확
	var gd := GameData.grow_days(wp)
	for _i in gd:
		_farm.water(cp)  # 비 오는 날은 이미 젖음
		GameClock.sleep_to_morning()
	assert(int(_farm.get_tile(cp)["watered_growth_days"]) == gd, "겨울엔 제철이라 생장이 나아간다")
	assert(_farm.is_mature_at(cp), "겨울 수확 가능(가을 파종 → 겨울 수확)")
	var got: String = _farm.harvest(cp)
	assert(got == GameData.crop_yield(wp) and GameData.forage.has(got),
		"수확물이 채집물 아이템 그대로여야 한다 (실제 %s)" % got)
	# 재수확은 기존 regrow_days 기제 그대로 — 다년생용 새 기제를 만들지 않았다는 확인
	var rg := int(GameData.crops[wp].get("regrow_days", 0))
	assert(rg > 0, "%s 재수확 주기 없음 — 다년생인데 한 번만 열린다" % wp)
	assert(_farm.get_tile(cp)["crop_id"] == wp and not _farm.is_mature_at(cp), "수확해도 그루가 남는다")
	for _j in rg:
		_farm.water(cp)
		GameClock.sleep_to_morning()
	assert(_farm.is_mature_at(cp), "regrow 주기 뒤 재성숙")
	# 해를 넘긴다: 봄엔 남아 있되 열매가 없고(휴면), 이듬해 겨울에 다시 열린다
	GameClock.abs_day = 4 * GameClock.DAYS_PER_SEASON - 1  # 겨울 막날
	GameClock.sleep_to_morning()
	assert(GameData.season_id(GameClock.season()) == "spring", "봄 진입")
	assert(_farm.get_tile(cp)["crop_id"] == wp, "다년생은 해를 넘겨도 밭에 남는다")
	assert(not _farm.is_mature_at(cp), "제철 아님 = 다 자랐어도 수확 불가(휴면)")
	GameClock.abs_day = 7 * GameClock.DAYS_PER_SEASON  # 이듬해 겨울 D1
	assert(GameData.season_id(GameClock.season()) == "winter", "전제: 이듬해 겨울")
	assert(_farm.is_mature_at(cp), "이듬해 겨울에 다시 열린다 — 심은 것이 풍경으로 남는다")

	# ── 3. 한해살이 채집물: 주운 것을 심어 **같은 아이템**을 거두고, 그게 선물 취향에 그대로 먹힌다
	var sp := ""
	for cid in GameData.crops:
		if not GameData.crop_perennial(cid) and GameData.crop_yield(cid) != cid \
			and GameData.crop_plantable(cid, "spring"):
			sp = cid
			break
	assert(sp != "", "봄에 심을 수 있는 한해살이 채집물이 없다")
	var gs := GameData.grow_days(sp)
	GameClock.abs_day = _clear_run(gs + 1)  # 수동 물주기 경로 — 맑은 구간 고정
	assert(GameClock.abs_day >= 0, "봄에 맑은 %d일 연속 구간이 없음" % (gs + 1))
	GameClock.game_min = 360
	var cs := _fcell(2, 0)
	assert(_farm.till(cs) and _farm.plant(cs, GameData.crops[sp]["seed_id"]), "주운 채집물을 그대로 심는다")
	for _k in gs:
		assert(_farm.water(cs), "물주기")
		GameClock.sleep_to_morning()
	var picked: String = _farm.harvest(cs)
	assert(picked == GameData.crop_yield(sp) and GameData.forage.has(picked),
		"기른 것 = 주운 것 (실제 %s)" % picked)
	# 도감·판매·요리 재료 자격이 기른 것에도 그대로 붙는가
	assert(GameData.is_collectible(picked) and GameData.is_produce(picked), "%s 도감·판매 대상" % picked)
	assert(_farm.deposit(picked, 1) == 1, "기른 채집물도 판매상자가 받는다")
	# 선물 취향: **수확된 id 그대로** 줬을 때 중립이 아니어야 한다.
	# (기른 것이 crop.* 로 갈리면 여기서 "받음"이 되어 걸린다 — 이게 §2-2의 실제 증상이다)
	var fan := ""
	for nid in GameData.npcs:
		var g: Dictionary = GameData.npcs[nid]["gifts"]
		if picked in g.get("loved", []) or picked in g.get("liked", []):
			fan = nid
			break
	assert(fan != "", "%s를 좋아하는 주민이 없어 취향 경로를 못 잰다" % picked)
	_npcsys.state[fan]["gifted_today"] = false  # 앞선 테스트가 오늘 몫을 썼을 수 있다
	var r: Dictionary = _npcsys.give(fan, picked)
	assert(r["ok"], "선물 실패: %s" % r["msg"])
	assert(String(r["msg"]).contains("좋아함") or String(r["msg"]).contains("기뻐함"),
		"기른 채집물에 취향이 안 먹힘 — 아이템이 갈렸다: %s" % r["msg"])

# ── 첫해 겨울 농장: 겨울에 열리는 종의 씨를 늦가을 야생에서 줍는다 ──────────────
# 옛 판은 그 넷의 씨앗이 곧 열매였고 열매는 겨울에만 돋았다 = **첫해엔 심을 방법이 없었다**.
# (Y1 가을 = 씨가 세상에 없음 → Y1 겨울 = 파종 금지 → Y2 가을에야 파종 → 첫 수확 Y2 겨울.
#  겨울무만 가을에도 돋아 예외였고, 그래서 Y1 겨울 밭은 한 종에 휴면 그루터기뿐이었다.)
# 고친 것은 하나다: **씨앗**을 심는 계절의 마지막 6일 야생에 따로 돋게 했다. 열매는 그대로 겨울 전용.
# 네 축을 전부 값으로 잰다 — ① Y1 안에 넷을 다 심어 겨울에 거둔다 ② 열매는 여전히 겨울에만 돋는다
# ③ 봄·여름·가을 채집물이 안 줄었다 ④ 늦가을 6일 안에 넷을 다 줍는다.
func _test_winter_seeds() -> void:
	var FS := preload("res://forage/forage_system.gd")
	var PS := preload("res://common/plant_shapes.gd")
	var TC := preload("res://common/toon_character.gd")
	var AUT := 2 * GameClock.DAYS_PER_SEASON  # Y1 가을 D1의 abs_day

	# ── 0. 순수 함수: 자리보다 종이 많아도 날마다 밀려 전 종을 덮는가 (값 직접 계산)
	assert(FS.seeds_on([], 3, 2).is_empty(), "후보 0 = 씨앗 스폰 없음")
	assert(FS.seeds_on(["a", "b", "c", "d"], 1, 2) == ["c", "d"], "day1 슬롯2 → c,d")
	assert(FS.seeds_on(["a", "b", "c", "d"], 2, 2) == ["a", "b"], "day2 슬롯2 → a,b")
	assert(FS.SEED_POINTS.size() >= 2, "씨앗 자리가 %d개 — 한 자리면 4종 도는 데 4일" % FS.SEED_POINTS.size())
	for i in FS.SEED_POINTS:
		assert(not i in FS.REMOTE_IDX, "씨앗 자리 %d가 희귀 전용 원거리 지점과 겹친다" % i)

	# ── 1. 데이터: 야생 씨앗 4종이 상점·도감·판매 전부 밖에 있고, 심는 데는 쓰인다
	var wild := GameData.wild_seed_ids()
	assert(wild.size() == 4, "야생 씨앗 4종(겨울에 열리는 재배 종) — 실제 %d" % wild.size())
	for s in wild:
		var cid: String = GameData.crop_from_seed(s)
		assert(cid != "", "%s 씨앗↔작물 매핑 없음" % s)
		assert(s in GameData.all_seed_ids(), "%s가 씨앗 순환 집합 밖 = 골라서 심을 수가 없다" % s)
		assert(not GameData.is_collectible(s), "%s가 도감에 샜다" % s)
		assert(not GameData.is_produce(s), "%s가 판매·선물에 샜다(늦가을 채집이 돈벌이가 된다)" % s)
		assert(_farm.deposit(s, 1) == 0, "%s를 판매상자가 받았다 — 씨앗은 팔 것이 아니다" % s)
		assert(GameData.sell_price(s) == 0, "%s 매입가 %d — 0이어야 한다" % [s, GameData.sell_price(s)])
		for sea in GameData.SEASON_IDS:
			assert(not s in GameData.season_seed_ids(sea), "%s가 %s 상점 재고에 떴다" % [s, sea])
		assert(GameData.crop_plantable(cid, "autumn"), "%s는 가을에 심는 종이어야 한다" % s)
		assert(GameData.crop_in_season(cid, "winter"), "%s는 겨울에 열리는 종이어야 한다" % s)

	# ── 2. 겉모습: 씨앗도 실제 노드를 만든다(색 구체 폴백 금지), 색은 그 종 열매 색 그대로
	var fs: Node = FS.new()
	for s in wild:
		var nd: Node3D = fs._look(s, false)
		assert(not (nd is MeshInstance3D and (nd as MeshInstance3D).mesh is SphereMesh),
			"%s — 색 구체 폴백을 탔다: 씨앗 형태가 실경로에 안 닿는다" % s)
		var ab := TC.aabb_of(nd)
		assert(absf(ab.position.y) <= 0.02, "%s — 밑동이 지면에서 %+.3f (묻히거나 떴다)" % [s, ab.position.y])
		assert(ab.size.y >= 0.34 and ab.size.y <= 0.52, "%s — 전고 %.3f가 채집물 대역(0.34~0.52) 밖" % [s, ab.size.y])
		assert(maxf(ab.size.x, ab.size.z) <= 0.80,
			"%s — 폭 %.3f: 줍는 반경만큼 퍼졌다" % [s, maxf(ab.size.x, ab.size.z)])
		var yid2 := GameData.crop_yield(GameData.crop_from_seed(s))
		var want := Color.from_string(String(GameData.forage[yid2]["color"]), Color.BLACK)
		assert(_look_color(nd).is_equal_approx(want), "%s 씨앗 색이 열매(%s)와 다르다" % [s, yid2])
		nd.free()
	assert(PS.SHAPES.has(PS.SEED_SHAPE), "씨앗 원형 %s가 표에 없다" % PS.SEED_SHAPE)

	# ── 2-b. 씨앗이 **열매 어휘 밖**에 있는가 ────────────────────────────────
	# 앞선 두 판은 잎 위에 종 색 알을 얹은 잎다발이라 게임 안의 송이·핵과·견과와 어휘가 같았다
	# = 3m 밖에서 "먹는 것"으로 읽혔다(실측 forage/seeds_fix). 표를 복사해 비교하지 않고
	# **메시를 실제로 구워** 두 축으로 잰다: ① 세로로 긴가(잎다발은 옆으로 퍼진다)
	# ② 속이 성긴가(열매·견과는 꽉 찬 덩어리다 — 세로 길이만 보면 솔방울 계열과 안 갈린다).
	# 문턱은 전부 절대 숫자다: 프로덕션 값에서 유도하면 그 값이 무너질 때 문턱도 같이 무너진다.
	var sm: ArrayMesh = PS.shape_mesh(PS.SHAPES[PS.SEED_SHAPE], Color.RED)
	var sab := sm.get_aabb()
	var sw: float = maxf(sab.size.x, sab.size.z)
	var sasp: float = sab.size.y / sw
	var sfill := _mesh_fill(sm)
	assert(sasp >= 1.9, "씨앗 원형이 세로 %.3f · 가로 %.3f = %.2f배 — 옆으로 퍼진 잎다발이다"
		% [sab.size.y, sw, sasp])
	assert(sfill <= 0.30, "씨앗 원형 속참 %.3f — 꽉 찬 덩어리는 먹는 열매로 읽힌다" % sfill)
	# 같은 자로 열매·견과 어휘를 재서 실제로 갈리는지 본다. 견과가 제일 위험하다 — 그쪽도
	# "마른 갈색 덩어리"라 세로 길이만으론 안 갈린다(nut_cone은 씨앗과 세로비가 거의 같다).
	var solid := 0
	for other in ["berry_bunch", "berry_drupe", "nut_round", "nut_cone"]:
		assert(PS.SHAPES.has(other), "비교 대상 원형 %s가 표에서 사라졌다" % other)
		var ofill := _mesh_fill(PS.shape_mesh(PS.SHAPES[other], Color.RED))
		assert(ofill >= 0.35, "%s 속참 %.3f — 열매·견과 쪽이 성겨져 이 비교가 무의미해졌다" % [other, ofill])
		assert(ofill - sfill >= 0.15,
			"씨앗(%.3f)과 %s(%.3f)의 속참이 붙었다 = 화면에서 형태가 겹친다" % [sfill, other, ofill])
		solid += 1
	assert(solid == 4, "열매·견과 어휘 4종과 견줘야 하는데 %d종만 쟀다" % solid)

	# ── 3. 늦가을 창: 씨앗은 이 6일에만 돋고, 그 안에 4종을 다 얻는다 (Y1 가을 30일 전수 시뮬)
	# 문턱은 절대 숫자다 — LATE_DAYS에서 유도하면 그 값이 0이 되는 순간 문턱도 0이 되어 통과한다.
	var first_seen := {}   # 씨앗 → 처음 나온 계절일
	var fruit_leak := []
	for d in GameClock.DAYS_PER_SEASON:
		GameClock.abs_day = AUT + d
		assert(GameClock.year() == 1 and GameData.season_id(GameClock.season()) == "autumn", "전제: Y1 가을")
		var day := GameClock.day_of_season()
		fs._respawn()
		var n := 0
		for e in _forage_snapshot(fs):
			var id: String = e[1]
			if id in wild:
				n += 1
				if not first_seen.has(id):
					first_seen[id] = day
				assert(day >= 25, "씨앗 %s가 가을 D%d에 돋았다 — 늦가을(D25~30) 창 밖" % [id, day])
			elif GameData.forage[id]["seasons"] == ["winter"]:
				fruit_leak.append("D%d %s" % [day, id])
		if day < 25:
			assert(n == 0, "가을 D%d에 씨앗이 %d개 — 창 밖에서 샜다" % [day, n])
		else:
			assert(n == 2, "늦가을 D%d에 씨앗이 %d개 — 자리 2곳은 확률 없이 반드시 돋아야 한다" % [day, n])
	assert(fruit_leak.is_empty(), "겨울 열매가 가을에 샜다: %s" % str(fruit_leak))
	assert(first_seen.size() == 4, "늦가을 6일 동안 씨앗 %d종만 나왔다 (전부 4종이어야)" % first_seen.size())
	var last_day := 0
	for id2 in first_seen:
		last_day = maxi(last_day, int(first_seen[id2]))
	assert(last_day <= 26, "4종을 다 모으는 데 가을 D%d까지 걸린다 — 창(D25~30) 안에 여유가 없다" % last_day)
	# 창 안 어느 이틀 연속으로도 4종이 다 나온다 = 늦게 시작해도 못 구할 일이 없다(최악의 경우)
	for start in range(25, GameClock.DAYS_PER_SEASON):
		var got := {}
		for d2 in [start, start + 1]:
			GameClock.abs_day = AUT + d2 - 1
			fs._respawn()
			for e2 in _forage_snapshot(fs):
				if e2[1] in wild:
					got[e2[1]] = true
		assert(got.size() == 4,
			"가을 D%d~D%d 이틀에 씨앗 %d종뿐 — 늦게 시작하면 못 구한다" % [start, start + 1, got.size()])
	# 심는 계절이 아닌 계절엔 끝자락에도 씨앗이 안 돋는다
	for sea2 in [0, 1, 3]:
		for d3 in range(GameClock.DAYS_PER_SEASON - 8, GameClock.DAYS_PER_SEASON):
			GameClock.abs_day = sea2 * GameClock.DAYS_PER_SEASON + d3
			fs._respawn()
			for e3 in _forage_snapshot(fs):
				assert(not e3[1] in wild, "%s 씨앗이 %s에 돋았다" % [e3[1], GameData.season_id(sea2)])
	fs.free()

	# ── 4. 계절별 채집물 4종씩 그대로 (씨앗을 넣느라 열매를 건드리지 않았다 — 절대 숫자)
	for sea3 in GameData.SEASON_IDS:
		var cnt: int = GameData.season_filter(GameData.forage, sea3).size()
		assert(cnt == 4, "%s 채집물 %d종 — 계절당 4종이어야 한다" % [sea3, cnt])
	assert(GameData.forage.size() == 16, "채집물 16종 (실제 %d)" % GameData.forage.size())

	# ── 5. 본론: Y1 안에 넷을 다 심어 겨울에 거둔다 (프로덕션: 스폰 → 심기 → 물 → 취침 → 수확)
	# 줍기 자체(Area3D → player._pick_forage)는 실플레이어가 필요해 e2e_interact가 문다.
	# 여기선 그 프롬프트가 읽는 **바로 그 메타**에서 씨앗 id를 꺼내 쓴다.
	var picked_up := {}
	for d4 in [25, 26]:
		GameClock.abs_day = AUT + d4 - 1
		var fs2: Node = FS.new()
		fs2._respawn()
		for r in fs2._roots:
			for c in (r as Node).get_children():
				if c is Area3D and c.is_in_group("forage") and c.has_meta("forage_id"):
					var id3 := String(c.get_meta("forage_id"))
					if id3 in wild:
						picked_up[id3] = true
		fs2.free()
	assert(picked_up.size() == 4, "가을 D25~26 이틀 채집으로 씨앗 %d종 — 4종이어야" % picked_up.size())
	GameClock.abs_day = AUT + 25  # 가을 D26 = 넷을 다 손에 넣은 날
	GameClock.game_min = 360
	var cells := {}
	for i2 in wild.size():
		var cell := _fcell(i2, 3)
		assert(_farm.till(cell), "가을 괭이질 %s" % str(cell))
		assert(_farm.plant(cell, wild[i2]), "%s를 가을에 심는다 (줍자마자 그 계절 안에)" % wild[i2])
		cells[wild[i2]] = cell
	assert(GameClock.year() == 1, "전제: 아직 Y1")
	while GameData.season_id(GameClock.season()) != "winter":
		for s2 in wild:
			_farm.water(cells[s2])   # 비 오는 날은 이미 젖어 false를 낸다
		GameClock.sleep_to_morning()
	assert(GameClock.year() == 1, "겨울에 들어와도 아직 Y1 (실제 Y%d)" % GameClock.year())
	for s3 in wild:
		assert(not GameData.crop_plantable(GameData.crop_from_seed(s3), "winter"), "겨울 파종은 여전히 막힌다")
		assert(_farm.get_tile(cells[s3])["crop_id"] != "", "%s가 계절 경계에서 사라졌다" % s3)
	var grow_max := 0
	for s4 in wild:
		grow_max = maxi(grow_max, GameData.grow_days(GameData.crop_from_seed(s4)))
	for _i3 in grow_max:
		for s5 in wild:
			_farm.water(cells[s5])
		GameClock.sleep_to_morning()
	var harvested := {}
	for s6 in wild:
		var cell2: Vector2i = cells[s6]
		assert(_farm.is_mature_at(cell2), "%s가 Y1 겨울에 안 여물었다" % s6)
		var got2: String = _farm.harvest(cell2)
		assert(got2 == GameData.crop_yield(GameData.crop_from_seed(s6)) and GameData.forage.has(got2),
			"%s 수확물이 채집물 아이템이 아님: %s" % [s6, got2])
		harvested[got2] = true
	assert(harvested.size() == 4, "Y1 겨울에 거둔 종이 %d가지 — 4가지여야 한다" % harvested.size())
	assert(GameClock.year() == 1 and GameData.season_id(GameClock.season()) == "winter",
		"수확이 Y1 겨울 안에서 끝나야 한다 (실제 Y%d %s)" % [GameClock.year(), GameData.season_id(GameClock.season())])
	# 수확 뒤에도 다년생 3종은 그루가 남아 겨울 밭 풍경이 된다(겨울무는 한해살이라 재수확 대기)
	var standing := 0
	for s7 in wild:
		if _farm.get_tile(cells[s7])["crop_id"] != "":
			standing += 1
	assert(standing >= 3, "수확 뒤 겨울 밭에 남은 그루가 %d — 다년생 3종은 남아야 한다" % standing)

# ── 한국어판: 화면에 나가는 이름에 로마자가 없다 + 세이브가 쓰는 ID는 그대로다 ──
# 아이템 ID(crop.turnip…)는 세이브 키다. 이름을 한국어로 바꾸다 ID까지 건드리면
# 기존 세이브의 소지품·도감이 통째로 사라진다 — 두 축을 한 함수에서 같이 못 박는다.
# 개수는 절대 숫자다. 데이터 로드가 실패해 딕셔너리가 비면 0회 순회로 조용히 통과하므로,
# "몇 개를 실제로 재 봤는가"를 먼저 세운다.
func _test_korean_names() -> void:
	var H := preload("res://ui/hud.gd")
	var roman := RegEx.create_from_string("[A-Za-z]")
	assert(roman != null, "정규식 컴파일 실패 — 이 핀은 아무것도 검사하지 못한다")

	# ① 화면 이름: display_name()을 전 항목에 실제로 돌린 결과를 본다
	var bad := []
	var checked := 0
	for src in [GameData.crops, GameData.fish, GameData.forage, GameData.recipes]:
		for id in src:
			var nm := GameData.display_name(id)
			checked += 1
			if roman.search(nm) != null:
				bad.append("%s=%s" % [id, nm])
	for src2 in [GameData.calendar, GameData.npcs]:
		for id2 in src2:
			var nm2 := String(src2[id2]["name"])
			checked += 1
			if roman.search(nm2) != null:
				bad.append("%s=%s" % [id2, nm2])
	assert(checked == 87, "이름을 87개 재야 하는데 %d개만 쟀다 — 데이터가 덜 실렸다" % checked)
	assert(bad.is_empty(), "화면 이름에 로마자가 %d개 남았다: %s" % [bad.size(), ", ".join(bad)])

	# 씨앗 줄(HUD "씨앗: ○○", 가방 "○○ 씨앗")은 작물 이름으로 되짚어 만든다
	var seed_bad := []
	for sid in GameData.all_seed_ids():
		var snm := GameData.display_name(sid if GameData.is_collectible(sid) else GameData.crop_from_seed(sid))
		if roman.search(snm) != null:
			seed_bad.append("%s=%s" % [sid, snm])
	assert(GameData.all_seed_ids().size() == 25, "씨앗 %d종 — 25종이어야 한다" % GameData.all_seed_ids().size())
	assert(seed_bad.is_empty(), "씨앗 표시 이름에 로마자: %s" % ", ".join(seed_bad))

	# 반지 이름 + 계절·요일 표기도 매일 화면에 뜨는 글자다
	var labels: Array = [GameData.RING_NAME] + Array(H.SEASON_KO) + Array(H.WD_KO)
	assert(labels.size() == 12, "라벨을 12개 재야 한다: %d" % labels.size())
	for lb in labels:
		assert(roman.search(String(lb)) == null, "화면 라벨에 로마자: %s" % str(lb))

	# ①-2 날짜 표기: 계절·요일만 한국어고 연차·일자는 "Y1 … D12"였다. 표기를 **실제로 만들어** 본다
	# (상수를 훑지 않는다 — 포맷 문자열이 되돌아가면 여기서 물어야 한다).
	assert(H.date_ko(1, 0, 12) == "1년차 봄 12일", "연/일 표기가 바뀌었다: %s" % H.date_ko(1, 0, 12))
	assert(H.date_ko(0, 3, 30) == "겨울 30일", "연차 없는 표기: %s" % H.date_ko(0, 3, 30))
	assert(H.date_ko(2, 1, 0) == "2년차 여름", "일자 없는 표기: %s" % H.date_ko(2, 1, 0))
	var dates := []
	for y in [0, 1, 9]:
		for se in H.SEASON_KO.size():
			for dy in [0, 1, 12, 30]:
				dates.append(H.date_ko(y, se, dy))
	assert(dates.size() == 48, "날짜 표기를 48개 재야 한다: %d" % dates.size())
	for dt in dates:
		assert(roman.search(String(dt)) == null, "날짜 표기에 로마자: %s" % dt)
	# 첫 프레임용으로 hud.tscn에 박아 둔 문자열도 같은 규약이다(_refresh 전에 화면에 뜬다)
	var hud_scene: Node = preload("res://ui/hud.tscn").instantiate()
	var hud_txt := String((hud_scene.get_node("Label") as Label).text)
	hud_scene.free()
	assert(roman.search(hud_txt) == null, "hud.tscn 기본 날짜 문자열에 로마자: %s" % hud_txt)

	# ② ID 불변: 세이브 키는 소문자 ascii 그대로여야 한다
	var ascii_id := RegEx.create_from_string("^[a-z][a-z0-9_.]*$")
	var ids := []
	for src3 in [GameData.crops, GameData.fish, GameData.forage, GameData.recipes, GameData.calendar, GameData.npcs]:
		for id3 in src3:
			ids.append(String(id3))
	ids.append_array(GameData.all_seed_ids())
	ids.append(GameData.RING_ID)
	assert(ids.size() == 113, "ID를 113개 재야 하는데 %d개다" % ids.size())
	for id4 in ids:
		assert(ascii_id.search(id4) != null, "ID가 소문자 ascii가 아니다 = 세이브 파손: %s" % id4)
	for must in ["crop.turnip", "fish.carp", "forage.wild_apple", "dish.salad",
			"festival.flower", "npc.mira", "seed.turnip", "ring.moonlight"]:
		assert(must in ids, "세이브가 쓰던 ID가 사라졌다: %s" % must)

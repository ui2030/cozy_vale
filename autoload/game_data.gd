extends Node
# 데이터 로드 + 참조 무결성 검증 (DESIGN 11.3). 코드가 아닌 res://data/*.json로 콘텐츠.

# 계절 canonical ID — 시즌 인덱스↔문자열의 단일 출처 (npc 생일·farm 고사·calendar 검증 공용)
const SEASON_IDS := ["spring", "summer", "autumn", "winter"]

# 낚시터 canonical ID. fish.json "spot" 필드와 물가 Area3D 메타 "spot"의 단일 출처.
# 필드가 없는 기존 어종은 SPOT_POND — 데이터 마이그레이션 없이 기본값으로 흡수한다.
const SPOT_POND := "pond"
const SPOT_SEA := "sea"
const SPOT_IDS := [SPOT_POND, SPOT_SEA]

# 프러포즈 아이템 (DESIGN 6.5). 유일한 비산출물 아이템이라 json 파일 대신 여기 상수.
# is_produce=false 로 두는 것이 계약: 판매상자·선물 취향 판정·도감·씨앗 순환에서 전부 자동 배제된다.
# 가격 1200 근거: 시작 골드 500(1일차 구매 불가) + 최고가 산출물 catfish 150의 8배
# + 순무 12타일 한 사이클(4일) 총매출 720 → 농사 위주 수입 ~150~250/일에서 5~8일 저축.
const RING_ID := "ring.moonlight"
const RING_NAME := "달빛 꽃반지"
const RING_COST := 1200

var crops := {}            # crop_id → 정의
var fish := {}             # fish_id → 정의 (낚시)
var forage := {}           # forage_id → 정의 (채집)
var recipes := {}          # dish_id → 정의 (요리 — 부엌 스토브에서 재료를 소모해 만든다)
var npcs := {}             # npc_id → 정의
var calendar := {}         # festival_id → 정의 (축제 선언)
var dialogues := {}        # archetype → {normal:[], festival:[]}
var _seed_to_crop := {}    # seed_id → crop_id

func _ready() -> void:
	crops = _load_json("res://data/crops.json")
	fish = _load_json("res://data/fish.json")
	forage = _load_json("res://data/forage.json")
	recipes = _load_json("res://data/recipes.json")
	npcs = _load_json("res://data/npcs.json")
	calendar = _load_json("res://data/calendar.json")
	dialogues = _load_json("res://data/dialogues.json")
	for cid in crops:
		_seed_to_crop[crops[cid]["seed_id"]] = cid
	_validate()  # has_item_id가 seed 포함해야 하므로 매핑 뒤에

func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	assert(f != null, "데이터 파일 없음: " + path)
	var res: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	assert(typeof(res) == TYPE_DICTIONARY, "JSON 파싱 실패: " + path)
	return res

func _validate() -> void:
	# 참조 무결성: 필수 필드 + seed_id 유일성
	var seeds := {}
	for cid in crops:
		var c: Dictionary = crops[cid]
		for key in ["name", "seed_id", "seasons", "grow_days", "sell_price", "seed_cost", "stages"]:
			assert(c.has(key), "%s 에 %s 누락" % [cid, key])
		assert(not seeds.has(c["seed_id"]), "seed_id 중복: " + c["seed_id"])
		seeds[c["seed_id"]] = true
		assert(not c["seasons"].is_empty(), "%s 계절 비어있음(어디서도 못 심음)" % cid)
		for s in c["seasons"]:
			assert(s in SEASON_IDS, "%s 계절 잘못됨: %s" % [cid, str(s)])
		# color(성장 단계 색)는 선택 필드 — 있으면 [r,g,b] 0..1. 없으면 런타임 기본값.
		var col: Array = c.get("color", [])
		assert(col.is_empty() or col.size() == 3, "%s color = [r,g,b] 아님" % cid)
		for v in col:
			assert(float(v) >= 0.0 and float(v) <= 1.0, "%s color 0..1 벗어남: %s" % [cid, str(v)])
	# 물고기·채집물 필수 필드 + 계절 유효 + difficulty(낚시 판정폭) 범위
	for fid in fish:
		var d: Dictionary = fish[fid]
		for key in ["name", "sell_price", "seasons", "difficulty"]:
			assert(d.has(key), "%s 에 %s 누락" % [fid, key])
		assert(String(d.get("spot", SPOT_POND)) in SPOT_IDS, "%s spot 잘못됨: %s" % [fid, str(d.get("spot"))])
		var diff := float(d["difficulty"])
		assert(diff >= 0.0 and diff <= 1.0, "%s difficulty 0..1 벗어남: %f" % [fid, diff])
		# weight 0 이하면 pick_fish의 가중 추첨에서 영원히 안 뽑힌다(조용히 없는 어종이 된다)
		assert(float(d.get("weight", 1.0)) > 0.0, "%s weight 0 이하 = 절대 안 잡힘" % fid)
		# _hour_ok는 [시작,끝] 두 칸을 전제로 인덱싱한다 — 모양이 틀리면 거기서 터진다
		var hrs_raw: Variant = d.get("hours", [])
		assert(hrs_raw is Array, "%s hours가 배열이 아님: %s" % [fid, str(hrs_raw)])
		var hrs: Array = hrs_raw
		assert(hrs.is_empty() or hrs.size() == 2, "%s hours = [시작,끝] 아님: %s" % [fid, str(hrs)])
		if hrs.size() == 2:
			assert(int(hrs[0]) >= 0 and int(hrs[0]) < 24, "%s hours 시작이 0..23 밖: %s" % [fid, str(hrs)])
			assert(int(hrs[1]) > int(hrs[0]) and int(hrs[1]) <= 48, "%s hours 끝이 시작 이하/과대: %s" % [fid, str(hrs)])
		for s in d["seasons"]:
			assert(s in SEASON_IDS, "%s 계절 잘못됨: %s" % [fid, str(s)])
	for fid in forage:
		var d: Dictionary = forage[fid]
		for key in ["name", "sell_price", "seasons"]:
			assert(d.has(key), "%s 에 %s 누락" % [fid, key])
		for s in d["seasons"]:
			assert(s in SEASON_IDS, "%s 계절 잘못됨: %s" % [fid, str(s)])
	# 요리: 필수 필드 + 재료 참조 무결성. 재료는 자연 산출물(crop/fish/forage)만 —
	# 요리를 재료로 삼으면 마진 검증(테스트)이 연쇄가 되고 순환 참조가 조용히 성립한다.
	for rid in recipes:
		var r: Dictionary = recipes[rid]
		for key in ["name", "sell_price", "ingredients"]:
			assert(r.has(key), "%s 에 %s 누락" % [rid, key])
		assert(not r["ingredients"].is_empty(), "%s 재료 없음(공짜 요리)" % rid)
		for iid in r["ingredients"]:
			assert(is_collectible(iid), "%s 재료 %s 없는 아이템(또는 요리)" % [rid, iid])
			assert(int(r["ingredients"][iid]) > 0, "%s 재료 %s 수량 0 이하" % [rid, iid])
	# 아이템 ID 전역 유일성: crop/seed/fish/forage/dish 충돌시 조회가 조용히 가려짐 (Codex)
	var ids := {}
	for key in crops.keys() + _seed_to_crop.keys() + fish.keys() + forage.keys() + recipes.keys():
		assert(not ids.has(key), "아이템 ID 충돌: " + key)
		ids[key] = true
	# NPC 선물 목록의 아이템 ID 참조 무결성 (통합 검사)
	for nid in npcs:
		var g: Dictionary = npcs[nid].get("gifts", {})
		for tier in ["loved", "liked", "disliked"]:
			for item_id in g.get(tier, []):
				assert(has_item_id(item_id), "%s 선물 %s: 없는 아이템 %s" % [nid, tier, item_id])
	# 축제 선언 검증: 필수 필드 + 계절 유효 + 날짜 1..DAYS_PER_SEASON + 시간창 정합
	# (계절,일) 유일성도 계약이다: festival_on()이 먼저 걸린 하나만 돌려주므로 같은 날 두 축제를
	# 선언하면 나머지가 조용히 사라진다(달력 패널·기상 토스트·결혼식 회피가 전부 어긋난다).
	var fest_days := {}
	for fid in calendar:
		var f: Dictionary = calendar[fid]
		for key in ["name", "season", "day", "start_min", "end_min", "plaza"]:
			assert(f.has(key), "%s 에 %s 누락" % [fid, key])
		assert(f["season"] in SEASON_IDS, "%s 계절 잘못됨: %s" % [fid, str(f["season"])])
		assert(int(f["day"]) >= 1 and int(f["day"]) <= GameClock.DAYS_PER_SEASON, "%s day 범위 밖: %d" % [fid, int(f["day"])])
		assert(int(f["start_min"]) < int(f["end_min"]), "%s start_min < end_min 위반" % fid)
		assert(f["plaza"] is Array and f["plaza"].size() == 2, "%s plaza = [x,z] 아님" % fid)
		# decor 오타는 조용히 "장식 없음"으로 지나가므로 여기서 잡는다 (festival_system _build_decor의 match와 동기화)
		assert(String(f.get("decor", "")) in ["", "flower", "harvest", "lantern"], "%s decor 값 모름: %s" % [fid, str(f.get("decor", ""))])
		var fday: String = "%s:%d" % [str(f["season"]), int(f["day"])]
		assert(not fest_days.has(fday), "%s 축제일 중복: %s (이미 %s)" % [fid, fday, str(fest_days.get(fday, ""))])
		fest_days[fday] = fid
	# 대사 참조 무결성: 모든 NPC 아키타입에 대사 풀 존재 + normal 비어있지 않음
	for nid in npcs:
		var arche: String = npcs[nid].get("archetype", "")
		assert(float(npcs[nid].get("walk_speed", 1.6)) > 0.0, "%s walk_speed는 양수여야 함(0이면 그 자리에 굳음)" % nid)
		assert(dialogues.has(arche), "%s archetype '%s' 대사 풀 없음" % [nid, arche])
		assert(not dialogues[arche].get("normal", []).is_empty(), "%s normal 대사 비어있음" % arche)
		# 결혼 후보(candidate)는 연애 대사가 다 있어야 함 (F단계: 데이트 → 청혼 → 결혼식 → 부부)
		if npcs[nid].get("candidate", false):
			for key in ["date_invite", "date1", "date2", "propose_accept", "propose_reject", "wedding", "married"]:
				assert(not dialogues[arche].get(key, []).is_empty(), "%s(%s) %s 대사 없음" % [nid, arche, key])

# 통합 아이템 ID 레지스트리 (작물·씨앗·물고기·채집물·요리·반지)
func has_item_id(item_id: String) -> bool:
	return item_id == RING_ID or crops.has(item_id) or _seed_to_crop.has(item_id) \
		or fish.has(item_id) or forage.has(item_id) or recipes.has(item_id)

# 판매·선물 가능 아이템 — 씨앗·반지 제외. 자연 산출물 + 요리.
# 요리를 여기 포함시키는 것이 계약이다: 판매상자(farm.deposit)·선물(_give)·가방 소지품 표시가
# 전부 이 한 판정을 보므로, 요리가 자동으로 팔리고 선물된다(취향 목록 밖 = neutral).
func is_produce(item_id: String) -> bool:
	return is_collectible(item_id) or recipes.has(item_id)

# 도감 대상 = 자연 산출물만. 요리는 만든 것이라 도감에 넣지 않는다(수집 진도율 왜곡 방지).
func is_collectible(item_id: String) -> bool:
	return crops.has(item_id) or fish.has(item_id) or forage.has(item_id)

# 가중치·시간대·낚시터 반영 물고기 선택 (순수 함수, test_core 단위검증).
# defs=fish 정의 맵, pool=계절 통과 fish_id 목록, rng_value∈[0,1), hour=현재 시(0..23),
# spot=낚시터("pond" 연못·강 / "sea" 바다).
# weight 없으면 1. hours([시작,끝]) 없으면 항상 후보. spot 없으면 "pond"(기존 어종 마이그레이션 0).
# 걸러내기를 호출부가 아니라 여기서 하는 이유: pool의 계약은 "계절 통과 목록"이고,
# 낚시터 판정을 호출부마다 되풀이하면 새 물가를 놓치기 쉽다(단일 지점 필터).
static func pick_fish(defs: Dictionary, pool: Array, rng_value: float, hour: int, spot := SPOT_POND) -> String:
	var cands := []
	var total := 0.0
	for fid in pool:
		var d: Dictionary = defs[fid]
		if String(d.get("spot", SPOT_POND)) != spot:
			continue
		if not _hour_ok(d.get("hours", []), hour):
			continue
		var w := float(d.get("weight", 1.0))
		cands.append([fid, w])
		total += w
	if cands.is_empty():
		return ""
	var r := clampf(rng_value, 0.0, 1.0) * total
	for c in cands:
		r -= c[1]
		if r < 0.0:
			return c[0]
	return cands[cands.size() - 1][0]  # 부동소수 안전망

# hours=[start,end]. end>24=자정 넘김(예 [18,26]=18시~익일2시). 빈 배열=항상 가능.
static func _hour_ok(hours: Array, hour: int) -> bool:
	if hours.is_empty():
		return true
	var start := int(hours[0])
	var end := int(hours[1])
	return (hour >= start and hour < end) or (hour + 24 >= start and hour + 24 < end)

# source(crops/fish/forage) 중 해당 계절에 나는 id 목록
func season_filter(source: Dictionary, sid: String) -> Array:
	var out := []
	for id in source:
		if sid in source[id].get("seasons", []):
			out.append(id)
	return out

func crop_from_seed(seed_id: String) -> String:
	return _seed_to_crop.get(seed_id, "")

# 그 계절에 심을 수 있는 작물인가 — 상점 재고·심기 차단·계절 고사가 전부 이 한 판정을 쓴다.
func crop_in_season(crop_id: String, sid: String) -> bool:
	return sid in crops.get(crop_id, {}).get("seasons", [])

# 그 계절 상점 재고(= 심을 수 있는 씨앗). 정렬은 all_seed_ids 순서 단일 출처라
# 상점·Q순환·가방 패널의 순서가 어긋날 수 없다. 겨울은 빈 배열(설계: 낚시·채집의 계절).
func season_seed_ids(sid: String) -> Array:
	var out := []
	for seed_id in all_seed_ids():
		if crop_in_season(_seed_to_crop[seed_id], sid):
			out.append(seed_id)
	return out

func sell_price(item_id: String) -> int:
	for src in [crops, fish, forage, recipes]:
		if src.has(item_id):
			return int(src[item_id].get("sell_price", 0))
	return 0

func seed_cost(seed_id: String) -> int:
	var cid := crop_from_seed(seed_id)
	return int(crops.get(cid, {}).get("seed_cost", 0))

func grow_days(crop_id: String) -> int:
	return int(crops.get(crop_id, {}).get("grow_days", 1))

func stage_count(crop_id: String) -> int:
	return int(crops.get(crop_id, {}).get("stages", 1))

func all_seed_ids() -> Array:
	return _seed_to_crop.keys()

func display_name(item_id: String) -> String:
	if item_id == RING_ID:
		return RING_NAME
	for src in [crops, fish, forage, recipes]:
		if src.has(item_id):
			return src[item_id].get("name", item_id)
	return item_id

func season_id(idx: int) -> String:
	return SEASON_IDS[idx]

# 해당 (계절,일)의 축제 정의 (없으면 {})
func festival_on(season: String, day: int) -> Dictionary:
	for fid in calendar:
		var f: Dictionary = calendar[fid]
		if f["season"] == season and int(f["day"]) == day:
			return f
	return {}

# ── 날씨 ────────────────────────────────────────────────────────
# 하루 단위 결정적 강수: abs_day만 보고 정하므로 저장할 상태가 없다(채집 리스폰과 같은 패턴,
# DESIGN 11.1 저장 표면 최소). 구세이브도 그대로 호환 — 세이브 포맷 무변경.
# 축제날은 강제 맑음(비 오는 꽃축제는 없다).
const RAIN_PCT := 25

# 결정적 정수 믹서. Variant.hash()를 안 쓰는 이유: 엔진 버전·플랫폼 간 안정성이 계약이 아니라
# 언젠가 값이 바뀌면 과거 날짜 날씨가 통째로 달라진다(Codex 지적). 시드 상수로 채집 해시와 분리해
# "비 오는 날엔 항상 희귀 채집물" 같은 우연 상관을 막는다.
static func rain_roll(abs_day: int) -> int:
	var x := (abs_day + 0x51ED2701) * 0x9E3779B1
	x = ((x ^ (x >> 15)) * 0x2C1B3C6D) & 0x7FFFFFFFFFFF
	x = ((x ^ (x >> 13)) * 0x297A2D39) & 0x7FFFFFFFFFFF
	return (x ^ (x >> 16)) & 0x7FFFFFFF

func is_rainy(abs_day: int) -> bool:
	if not festival_on(SEASON_IDS[GameClock.season_at(abs_day)], GameClock.day_of_season_at(abs_day)).is_empty():
		return false
	return rain_roll(abs_day) % 100 < RAIN_PCT

# 해당 (계절,일)이 생일인 주민 이름 목록
func birthdays_on(season: String, day: int) -> Array:
	var out := []
	for nid in npcs:
		var b: Dictionary = npcs[nid]["birthday"]
		if b["season"] == season and int(b["day"]) == day:
			out.append(npcs[nid]["name"])
	return out

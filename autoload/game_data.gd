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
	var yields := {}
	for cid in crops:
		var c: Dictionary = crops[cid]
		var yid := crop_yield(cid)
		# 산출물이 따로 있는 항목(주운 채집물을 그대로 심는다)은 name·sell_price·seed_cost를
		# 다시 적지 않는다 — 그 아이템 정의가 단일 출처다(두 번 적으면 값이 갈린다).
		var need := ["seed_id", "seasons", "grow_days", "stages"] if yid != cid \
			else ["name", "seed_id", "seasons", "grow_days", "sell_price", "seed_cost", "stages"]
		for key in need:
			assert(c.has(key), "%s 에 %s 누락" % [cid, key])
		if yid != cid:
			assert(fish.has(yid) or forage.has(yid), "%s yield_id가 없는 산출물: %s" % [cid, yid])
			assert(not yields.has(yid), "%s와 %s가 같은 산출물을 맺음: %s" % [cid, str(yields.get(yid)), yid])
			yields[yid] = cid
			# 씨앗은 둘 중 하나다: ① 산출물 그 자체(주운 것을 그대로 심는다) ② 야생에서만 줍는 전용
			# 씨앗. ②는 겨울에 열리는 종 몫이다 — 열매가 겨울에만 돋으니 씨가 곧 열매면 첫해엔
			# 심을 방법이 없다(Y1 가을=씨 없음, Y1 겨울=파종 금지). 전용 씨앗은 상점에도 도감에도
			# 없으므로 **산출물로 새면 안 된다** — 새는 순간 팔리고 선물되고 도감에 유령이 뜬다.
			if String(c["seed_id"]) != yid:
				assert(not is_produce(String(c["seed_id"])),
					"%s 전용 씨앗이 산출물로 샌다: %s" % [cid, c["seed_id"]])
		assert(not seeds.has(c["seed_id"]), "seed_id 중복: " + c["seed_id"])
		seeds[c["seed_id"]] = true
		assert(not c["seasons"].is_empty(), "%s 계절 비어있음(어디서도 못 심음)" % cid)
		for s in c["seasons"]:
			assert(s in SEASON_IDS, "%s 계절 잘못됨: %s" % [cid, str(s)])
		# plant_seasons(선택) = 심을 수 있는 계절. 없으면 seasons와 같다.
		if c.has("plant_seasons"):
			assert(not c["plant_seasons"].is_empty(), "%s plant_seasons 비어있음(어디서도 못 심음)" % cid)
			for s in c["plant_seasons"]:
				assert(s in SEASON_IDS, "%s plant_seasons 잘못됨: %s" % [cid, str(s)])
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
	# 씨앗이 곧 산출물인 항목은 새 id를 만들지 않으므로 여기서 뺀다(자기 자신과 충돌 판정된다).
	var seed_only := []
	for cid in crops:
		if String(crops[cid]["seed_id"]) != crop_yield(cid):
			seed_only.append(crops[cid]["seed_id"])
	var ids := {}
	for key in crops.keys() + seed_only + fish.keys() + forage.keys() + recipes.keys():
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
		# 빈 풀을 선언해두면 대사 선택이 그 key를 조용히 건너뛴다 = 써 둔 줄 alignment 착각의 원인.
		# 상황별 풀(생일·비·계절…)은 **없어도 되지만 비어 있으면 안 된다**.
		for key in dialogues[arche]:
			var lines: Array = dialogues[arche][key]
			# 1줄 풀은 그 상황 내내 같은 문장 하나다 — 계절 풀이면 30일 동안 한 문장이다.
			# 빈 배열은 조용히 건너뛰어져서 "썼는데 안 나온다"의 원인이 된다.
			assert(lines.size() >= 2, "%s '%s' 풀이 %d줄 — 최소 2줄(없앨 거면 key째 지운다)" % [arche, key, lines.size()])
			for ln in lines:
				assert(ln is String and String(ln).strip_edges() != "", "%s '%s'에 빈 대사 줄" % [arche, key])
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
# 산출물이 따로 있는 재배 항목(채집물 재배)도 제외: 그건 아이템이 아니라 "기르는 법"이고
# 실제 아이템은 그 채집물 쪽이다 — 넣으면 도감·판매·선물이 두 갈래로 갈린다.
func is_collectible(item_id: String) -> bool:
	return (crops.has(item_id) and crop_yield(item_id) == item_id) or fish.has(item_id) or forage.has(item_id)

# 재배 산출물 id. 없으면 작물 id 자신(씨앗을 사서 심는 기존 작물).
# 주운 채집물을 그대로 심는 항목은 **그 채집물 아이템**을 맺는다 — 기른 것과 주운 것이 같은
# 아이템이라야 요리 재료·선물 취향·도감이 한 갈래로 남는다(설계 §2-2).
func crop_yield(crop_id: String) -> String:
	return String(crops.get(crop_id, {}).get("yield_id", crop_id))

# 다년생 = 계절 경계에서 뽑히지 않는다. 그게 다년생의 정의다 — 제철이 아니면 휴면할 뿐 죽지 않는다.
func crop_perennial(crop_id: String) -> bool:
	return bool(crops.get(crop_id, {}).get("perennial", false))

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

# 그 계절에 **열매가 맺히는가**. 계절 고사·휴면·수확 가능 판정이 이 한 판정을 쓴다.
# (다년생 도입 전에는 "심을 수 있는 계절"과 같은 뜻이었다 — 이제 crop_plantable로 갈렸다.)
func crop_in_season(crop_id: String, sid: String) -> bool:
	return sid in crops.get(crop_id, {}).get("seasons", [])

# 그 계절에 **심을 수 있는가**. 겨울에 열리는 다년생은 가을에만 심는다(겨울 파종은 설계상 없다)
# — 그런 항목만 plant_seasons를 적고, 없으면 seasons와 같다.
func crop_plantable(crop_id: String, sid: String) -> bool:
	var c: Dictionary = crops.get(crop_id, {})
	return sid in c.get("plant_seasons", c.get("seasons", []))

# 그 계절 상점 재고. 정렬은 all_seed_ids 순서 단일 출처라 상점·Q순환·가방 패널의 순서가
# 어긋날 수 없다. 겨울은 빈 배열(설계: 파종 없는 계절 = 낚시·채집의 계절).
# 산출물이 따로 있는 항목(채집물 재배)은 재고에서 통째로 뺀다: 씨앗값에 사서 산출물로 되팔면
# 무한 골드가 되고, 애초에 **들에서 얻는 것**이 그 공급원이라는 설계다(주운 열매를 그대로 심든,
# 늦가을 야생 씨앗을 줍든). 옛 판정은 "씨앗이 곧 아이템인가"였는데 그건 앞엣것만 걸렀다.
func season_seed_ids(sid: String) -> Array:
	var out := []
	for seed_id in all_seed_ids():
		var cid: String = _seed_to_crop[seed_id]
		if crop_plantable(cid, sid) and crop_yield(cid) == cid:
			out.append(seed_id)
	return out

# 야생에서만 줍는 전용 씨앗 — 산출물이 따로 있는데 씨앗이 그 산출물이 아닌 항목.
# 상점(season_seed_ids)·도감(is_collectible)·판매(is_produce) 전부 자동으로 밖이다.
# 정렬해 돌려준다 = 스폰 순번이 Dictionary 순회 순서에 안 흔들린다.
func wild_seed_ids() -> Array:
	var out := []
	for cid in crops:
		var sid := String(crops[cid]["seed_id"])
		if crop_yield(cid) != cid and sid != crop_yield(cid):
			out.append(sid)
	out.sort()
	return out

# 재배 항목을 물어봐도 산출물 값으로 답한다(값을 두 번 적지 않는다).
func sell_price(item_id: String) -> int:
	var y := crop_yield(item_id)
	for src in [crops, fish, forage, recipes]:
		if src.has(y):
			return int(src[y].get("sell_price", 0))
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
	var y := crop_yield(item_id)  # 재배 항목은 이름도 산출물 것 — 두 번 적으면 갈린다
	for src in [crops, fish, forage, recipes]:
		if src.has(y):
			return src[y].get("name", y)
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

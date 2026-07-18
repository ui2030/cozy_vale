extends Node
# 데이터 로드 + 참조 무결성 검증 (DESIGN 11.3). 코드가 아닌 res://data/*.json로 콘텐츠.

# 계절 canonical ID — 시즌 인덱스↔문자열의 단일 출처 (npc 생일·farm 고사·calendar 검증 공용)
const SEASON_IDS := ["spring", "summer", "autumn", "winter"]

var crops := {}            # crop_id → 정의
var npcs := {}             # npc_id → 정의
var calendar := {}         # festival_id → 정의 (축제 선언)
var _seed_to_crop := {}    # seed_id → crop_id

func _ready() -> void:
	crops = _load_json("res://data/crops.json")
	npcs = _load_json("res://data/npcs.json")
	calendar = _load_json("res://data/calendar.json")
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
		for key in ["name", "seed_id", "grow_days", "sell_price", "seed_cost", "stages"]:
			assert(c.has(key), "%s 에 %s 누락" % [cid, key])
		assert(not seeds.has(c["seed_id"]), "seed_id 중복: " + c["seed_id"])
		seeds[c["seed_id"]] = true
	# NPC 선물 목록의 아이템 ID 참조 무결성 (통합 검사)
	for nid in npcs:
		var g: Dictionary = npcs[nid].get("gifts", {})
		for tier in ["loved", "liked", "disliked"]:
			for item_id in g.get(tier, []):
				assert(has_item_id(item_id), "%s 선물 %s: 없는 아이템 %s" % [nid, tier, item_id])
	# 축제 선언 검증: 필수 필드 + 계절 유효 + 날짜 1..28 + 시간창 정합
	for fid in calendar:
		var f: Dictionary = calendar[fid]
		for key in ["name", "season", "day", "start_min", "end_min", "plaza"]:
			assert(f.has(key), "%s 에 %s 누락" % [fid, key])
		assert(f["season"] in SEASON_IDS, "%s 계절 잘못됨: %s" % [fid, str(f["season"])])
		assert(int(f["day"]) >= 1 and int(f["day"]) <= GameClock.DAYS_PER_SEASON, "%s day 범위 밖: %d" % [fid, int(f["day"])])
		assert(int(f["start_min"]) < int(f["end_min"]), "%s start_min < end_min 위반" % fid)
		assert(f["plaza"] is Array and f["plaza"].size() == 2, "%s plaza = [x,z] 아님" % fid)

# 통합 아이템 ID 레지스트리 (현재 = 작물 + 씨앗. 도구·채집물 추가시 여기 확장)
func has_item_id(item_id: String) -> bool:
	return crops.has(item_id) or _seed_to_crop.has(item_id)

func crop_from_seed(seed_id: String) -> String:
	return _seed_to_crop.get(seed_id, "")

func sell_price(crop_id: String) -> int:
	return int(crops.get(crop_id, {}).get("sell_price", 0))

func seed_cost(seed_id: String) -> int:
	var cid := crop_from_seed(seed_id)
	return int(crops.get(cid, {}).get("seed_cost", 0))

func grow_days(crop_id: String) -> int:
	return int(crops.get(crop_id, {}).get("grow_days", 1))

func stage_count(crop_id: String) -> int:
	return int(crops.get(crop_id, {}).get("stages", 1))

func all_seed_ids() -> Array:
	return _seed_to_crop.keys()

func display_name(crop_id: String) -> String:
	return crops.get(crop_id, {}).get("name", crop_id)

func season_id(idx: int) -> String:
	return SEASON_IDS[idx]

# 해당 (계절,일)의 축제 정의 (없으면 {})
func festival_on(season: String, day: int) -> Dictionary:
	for fid in calendar:
		var f: Dictionary = calendar[fid]
		if f["season"] == season and int(f["day"]) == day:
			return f
	return {}

# 해당 (계절,일)이 생일인 주민 이름 목록
func birthdays_on(season: String, day: int) -> Array:
	var out := []
	for nid in npcs:
		var b: Dictionary = npcs[nid]["birthday"]
		if b["season"] == season and int(b["day"]) == day:
			out.append(npcs[nid]["name"])
	return out

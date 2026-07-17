extends Node
# 데이터 로드 + 참조 무결성 검증 (DESIGN 11.3). 코드가 아닌 res://data/*.json로 콘텐츠.

var crops := {}            # crop_id → 정의
var npcs := {}             # npc_id → 정의
var _seed_to_crop := {}    # seed_id → crop_id

func _ready() -> void:
	crops = _load_json("res://data/crops.json")
	npcs = _load_json("res://data/npcs.json")
	_validate()
	for cid in crops:
		_seed_to_crop[crops[cid]["seed_id"]] = cid

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

# 통합 아이템 ID 레지스트리 (현재 = 작물. 도구·채집물 추가시 여기 확장)
func has_item_id(item_id: String) -> bool:
	return crops.has(item_id)

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

extends Node
# 세이브 (DESIGN 11.1). JSON 단일 파일, 원자적 교체, save_version 마이그레이션, bak 폴백.
# 저장 요청은 큐잉 후 다음 프레임 처리 (신호 연결 순서 문제 회피 — Codex 지적).

const VERSION := 4
# 월드 레이아웃 판(마을 P1). 정적 지오메트리/충돌체가 바뀌면 범프 → 구세이브의 플레이어
# 위치가 신규 충돌체 안에 박혔을 수 있으므로 로드 시 광장으로 폴백(신규 게임엔 영향 없음).
const WORLD_VERSION := 2
const PLAZA_SPAWN := Vector3(0, 2, -3.5)  # 광장 안(분수 r1·밭 밖), 스폰/폴백 공용
const F_JSON := "user://save.json"
const F_BAK := "user://save.bak"
const F_TMP := "user://save.tmp"

var _queued_reason := ""

# save_version v → v+1 순수 함수 체인 (키 = from_version).
var _migrations := {
	1: func(d: Dictionary) -> Dictionary:  # v1(clock/player) → v2(농사·인벤·소지금)
		var sys: Dictionary = d.get("systems", {})
		sys["farming"] = sys.get("farming", {"tiles": {}, "shipping_bin": []})
		d["systems"] = sys
		var pl: Dictionary = d.get("player", {})
		pl["inventory"] = pl.get("inventory", [])
		pl["gold"] = pl.get("gold", 500)
		d["player"] = pl
		return d,
	2: func(d: Dictionary) -> Dictionary:  # v2 → v3 (주민)
		var sys: Dictionary = d.get("systems", {})
		sys["npc"] = sys.get("npc", {})
		d["systems"] = sys
		return d,
	3: func(d: Dictionary) -> Dictionary:  # v3 → v4 (도감)
		var pl: Dictionary = d.get("player", {})  # player 없어도 생성 후 채움
		pl["collection"] = pl.get("collection", [])
		d["player"] = pl
		return d,
}

func _ready() -> void:
	set_process(false)  # 기본 활성이면 첫 프레임에 무요청 _write 실행(하네스 세이브 오염 원인)

func request_save(reason := "") -> void:
	_queued_reason = reason
	set_process(true)

func _process(_delta: float) -> void:
	set_process(false)
	_write(_gather())

func _gather() -> Dictionary:
	var data := {
		"save_version": VERSION,
		"meta": {"reason": _queued_reason, "saved_abs_day": GameClock.abs_day, "world_version": WORLD_VERSION},
		"clock": GameClock.to_dict(),
		"player": {},
		"systems": {},  # B~F: systems.farming / systems.npc / systems.relationships
	}
	var p := _player()
	if p != null and p.has_method("save_data"):
		data["player"] = p.save_data()
	var farm := _farm()
	if farm != null and farm.has_method("save_data"):
		data["systems"]["farming"] = farm.save_data()
	var npc := _npc()
	if npc != null and npc.has_method("save_data"):
		data["systems"]["npc"] = npc.save_data()
	return data

func load_game() -> bool:
	var data := _read(F_JSON)
	if data.is_empty():
		data = _read(F_BAK)  # json 손상 시 폴백
	if data.is_empty():
		return false
	data = _migrate(data)
	GameClock.from_dict(data.get("clock", {}))
	var p := _player()
	if p != null and p.has_method("load_data") and data.has("player"):
		p.load_data(data["player"])
		# 월드 판이 바뀐 세이브 → 저장 위치가 신규 충돌체에 박혔을 수 있어 광장으로 폴백
		if int(data.get("meta", {}).get("world_version", 0)) != WORLD_VERSION:
			p.global_position = PLAZA_SPAWN
	var farm := _farm()
	if farm != null and farm.has_method("load_data"):
		farm.load_data(data.get("systems", {}).get("farming", {}))
	var npc := _npc()
	if npc != null and npc.has_method("load_data"):
		npc.load_data(data.get("systems", {}).get("npc", {}))
	return true

func _migrate(data: Dictionary) -> Dictionary:
	var v := int(data.get("save_version", 1))  # 무버전 세이브 = 최초 포맷(v1)로 간주
	while v < VERSION:
		if not _migrations.has(v):
			push_error("save_version %d → %d 마이그레이션 함수 없음" % [v, v + 1])
			break
		data = _migrations[v].call(data)
		v += 1
		data["save_version"] = v
	return data

func _write(data: Dictionary) -> void:
	var txt := JSON.stringify(data, "  ")
	var f := FileAccess.open(F_TMP, FileAccess.WRITE)
	if f == null:
		push_error("세이브 tmp 쓰기 실패")
		return
	f.store_string(txt)
	f.close()  # flush + close
	# 원자적 회전: 이전 bak 삭제 → json→bak → tmp→json (Windows rename 안전)
	var dir := DirAccess.open("user://")
	if dir.file_exists("save.bak"):
		dir.remove("save.bak")
	if dir.file_exists("save.json"):
		dir.rename("save.json", "save.bak")
	dir.rename("save.tmp", "save.json")

func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var res: Variant = JSON.parse_string(txt)
	if typeof(res) != TYPE_DICTIONARY:
		return {}
	return res

func _player() -> Node:
	return get_tree().get_first_node_in_group("player")

func _farm() -> Node:
	return get_tree().get_first_node_in_group("farm")

func _npc() -> Node:
	return get_tree().get_first_node_in_group("npc_system")

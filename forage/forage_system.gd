extends Node3D
# 채집물 스폰 (day_changed마다 리스폰). 당일 상태는 저장 안 함 — abs_day 기반 결정적 배치라
# 같은 날 재로드해도 동일하게 재생성됨(파생 상태, DESIGN 11.1 저장 표면 최소).

const ToonChar := preload("res://common/toon_character.gd")
const Shapes := preload("res://common/plant_shapes.gd")  # 원형 표·생성기(밭 작물과 공용)

# ── 겉모습 = forage.json ────────────────────────────────────────────
# 옛 판은 전 종이 같은 초록 구체(희귀만 금색)였다. 두 가지가 동시에 깨져 있었다:
# ① 6종이 화면에서 구분이 안 된다 ② 초록 구체가 겨울 설원 위에서 형광 점으로 뜬다.
# 종별 색·형태는 **데이터가 정한다**(엔진에 종 하드코딩 금지) — json의 "color"(hex)와
# "mesh"("<킷>/<이름>") / "shape"(절차 원형). 표와 생성기는 plant_shapes.gd에 있다.
#
# json에 색이 없을 때의 폴백 = 옛 동작 그대로. 희귀 금색은 "원거리서 식별" 계약이라 유지한다.
const C_COMMON := Color(0.5, 0.75, 0.35)
const C_RARE := Color(0.86, 0.68, 0.20)

# 스폰 후보 지점 — 밭 Rect2i(4,7,8,4)·침대(5)·상점(-5)·상자(-2,4)·연못(10,0,0) 회피
# (5,0,8)은 밭이 옮겨오면서 밭 안이 됐다 → 옛 밭 자리 초지로 물렸다. 판매상자(5,5.8)에서
# 3이상 띄워 둔다 — 프롬프트는 종류가 아니라 **가장 가까운** Area를 고르므로 같이 두면 "줍기"가 이긴다.
const SPAWN_POINTS := [
	Vector3(-6, 0, 8), Vector3(-3, 0, 9), Vector3(2, 0, 9), Vector3(8, 0, 5.5),
	Vector3(-9, 0, 5), Vector3(-8, 0, -4), Vector3(-3, 0, -6), Vector3(6, 0, -7),
]
const SPAWN_PCT := 55  # 각 지점 스폰 확률(%)
# 밭·침대·상점서 먼 외곽 지점(뒤 4개) — 여기서만 낮은 확률로 희귀 채집물.
const REMOTE_IDX := [4, 5, 6, 7]
const RARE_PCT := 20  # 원거리 지점에서 일반 대신 희귀가 나올 확률(%)

# 원거리 지점의 희귀 등장 결정 (순수 함수, test_core 단위검증). 결정적 해시 h 기준.
# 반환: 희귀면 rare_id, 아니면 "" (일반 스폰 유지). 스폰여부(h%100)와 겹치지 않는 자리 사용.
static func pick_rare(is_remote: bool, h: int, rare_ids: Array) -> String:
	if not is_remote or rare_ids.is_empty():
		return ""
	if (h / 100) % 100 < RARE_PCT:
		return rare_ids[(h / 10000) % rare_ids.size()]
	return ""

var _roots := []  # 현재 스폰된 root Node3D

func _ready() -> void:
	add_to_group("forage_system")
	if not GameClock.day_changed.is_connected(_on_day_changed):
		GameClock.day_changed.connect(_on_day_changed)
	_respawn.call_deferred()  # 세이브 로드로 abs_day 확정된 뒤 첫 배치

func _on_day_changed(_prev: int, _abs_day: int) -> void:
	_respawn()

func _respawn() -> void:
	_clear()
	var pool := GameData.season_filter(GameData.forage, GameData.season_id(GameClock.season()))
	if pool.is_empty():
		return
	var rare_pool := []   # 희귀는 원거리 전용
	var common_pool := []
	for id in pool:
		if GameData.forage[id].get("rare", false):
			rare_pool.append(id)
		else:
			common_pool.append(id)
	for i in SPAWN_POINTS.size():
		var h := absi(hash([GameClock.abs_day, i]))  # 결정적: 같은 날 재로드 = 같은 배치
		if h % 100 < SPAWN_PCT:
			var rid := pick_rare(i in REMOTE_IDX, h, rare_pool)
			if rid != "":
				_spawn(SPAWN_POINTS[i], rid, true)
			elif not common_pool.is_empty():
				_spawn(SPAWN_POINTS[i], common_pool[h % common_pool.size()], false)

func _clear() -> void:
	for r in _roots:
		if is_instance_valid(r):
			r.queue_free()
	_roots.clear()

func _spawn(pos: Vector3, fid: String, rare := false) -> void:
	var root := Node3D.new()
	root.position = pos
	root.add_child(_look(fid, rare))
	var area := Area3D.new()
	area.add_to_group("forage")
	area.set_meta("forage_id", fid)
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.9
	cs.shape = sh
	area.add_child(cs)
	area.position = Vector3(0, 0.5, 0)
	root.add_child(area)
	add_child(root)
	_roots.append(root)

# 종별 겉모습 노드. 형태가 없거나(데이터 미지정) 에셋 로드가 실패하면 옛 구체로 폴백하되
# **색은 그대로 쓴다** — 에셋이 빠져도 종 구분은 살아 있다.
# 형태 자체는 plant_shapes.build가 만든다(밭 작물과 같은 경로·같은 메시 캐시).
func _look(fid: String, rare: bool) -> Node3D:
	var d: Dictionary = GameData.forage.get(fid, {})
	var col := Color.from_string(String(d.get("color", "")), C_RARE if rare else C_COMMON)
	var n := Shapes.build(d, col, fid)
	if n != null:
		return n
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = Shapes.LOOK_H * 0.5
	sm.height = Shapes.LOOK_H
	mi.mesh = sm
	mi.material_override = ToonChar.make_solid(col, Shapes.OUTLINE_W)
	mi.position = Vector3(0, Shapes.LOOK_H * 0.57, 0)  # 구체는 피벗이 중심이라 띄운다(킷은 바닥 기준)
	return mi


# 플레이어가 주우면 해당 채집물 노드 제거
func remove(area: Area3D) -> void:
	var root := area.get_parent()
	_roots.erase(root)
	if is_instance_valid(root):
		root.queue_free()

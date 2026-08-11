extends Node3D
# 채집물 스폰 (day_changed마다 리스폰). 당일 상태는 저장 안 함 — abs_day 기반 결정적 배치라
# 같은 날 재로드해도 동일하게 재생성됨(파생 상태, DESIGN 11.1 저장 표면 최소).

const ToonChar := preload("res://common/toon_character.gd")
const Decor := preload("res://world/decor.gd")  # 킷 로드 규약(load_kit·충돌 벗기기·식생 밝기) 재사용

# ── 겉모습 = forage.json ────────────────────────────────────────────
# 옛 판은 전 종이 같은 초록 구체(희귀만 금색)였다. 두 가지가 동시에 깨져 있었다:
# ① 6종이 화면에서 구분이 안 된다 ② 초록 구체가 겨울 설원 위에서 형광 점으로 뜬다.
# 종별 색·메시는 **데이터가 정한다**(엔진에 종 하드코딩 금지) — json의 "color"(hex)와
# 선택 "mesh"("<킷>/<이름>"). 여기 있는 건 킷 접두어 표뿐이다.
#
# **파크 킷(Decor.TT_PARK)은 채집물에 쓰면 안 된다.** decor.gd가 그 킷의 여섯 종(flower_A·B,
# grass_A·B, bush, bush_large)을 683개 흩뿌린 게 마을 배경이다 — 채집물이 같은 메시를 쓰면
# 배경 식생에 위장돼 "주울 수 있는 것"으로 안 읽힌다(실측 forage_look/crop_spring: 민들레가
# 화단 꽃과 구분 불가, 부추는 흙길 위에 누운 잎 하나). 배경 어휘 밖의 킷만 쓴다.
const KIT_DIR := {
	"picnic": "res://assets/tinytreats/Tiny_Treats_Pleasant_Picnic_1.0_FREE/Assets/gltf/",
}
# 목표 전고. 킷 메시는 원본 크기가 제각각(파크 꽃 0.14 · 피크닉 포도 0.05)이라 AABB로 재서
# 여기 맞춘다 = json에 배율을 또 적지 않는다. 옛 구체 전고 0.56과 같은 대역이라 줍는 반경
# (Area3D 0.9)과의 관계도 그대로다.
const LOOK_H := 0.50
# json에 색이 없을 때의 폴백 = 옛 동작 그대로. 희귀 금색은 "원거리서 식별" 계약이라 유지한다.
const C_COMMON := Color(0.5, 0.75, 0.35)
const C_RARE := Color(0.86, 0.68, 0.20)

# 스폰 후보 지점 — 밭 Rect2i(0,2,8,4)·침대(5)·상점(-5)·상자(-2,4)·연못(10,0,0) 회피
const SPAWN_POINTS := [
	Vector3(-6, 0, 8), Vector3(-3, 0, 9), Vector3(2, 0, 9), Vector3(5, 0, 8),
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

# 종별 겉모습 노드. 메시가 없거나(데이터 미지정) 에셋 로드가 실패하면 옛 구체로 폴백하되
# **색은 그대로 쓴다** — 에셋이 빠져도 종 구분은 살아 있다.
func _look(fid: String, rare: bool) -> Node3D:
	var d: Dictionary = GameData.forage.get(fid, {})
	var col := Color.from_string(String(d.get("color", "")), C_RARE if rare else C_COMMON)
	var mp := String(d.get("mesh", ""))
	if mp != "":
		var parts := mp.split("/", false, 1)
		if parts.size() == 2 and KIT_DIR.has(parts[0]):
			var n := Decor.load_kit(KIT_DIR[parts[0]] + parts[1] + ".gltf", 1.0, 0.0, Decor.VEG_GAIN)
			if n != null:
				Decor._strip_collision(n)  # 킷 충돌체가 붙으면 채집물이 통행을 막는다
				_tint(n, col)
				var h: float = ToonChar.aabb_of(n).size.y
				n.scale = Vector3.ONE * (LOOK_H / h) if h > 0.001 else Vector3.ONE
				return n
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = LOOK_H * 0.5
	sm.height = LOOK_H
	mi.mesh = sm
	mi.material_override = ToonChar.make_solid(col, 0.006)
	mi.position = Vector3(0, LOOK_H * 0.57, 0)  # 구체는 피벗이 중심이라 띄운다(킷 메시는 바닥 기준)
	return mi

# 킷이 깔아둔 char_tint(KIT_TINT)만 종별 색으로 갈아끼운다. sat_cap·val_gain은 건드리지 않는다
# = 아틀라스 결이 살아 있는 채로 색상만 도는 것(decor.gd FLORA_TINT와 같은 수법).
static func _tint(node: Node, col: Color) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		for i in mi.get_surface_override_material_count():
			var m := mi.get_surface_override_material(i) as ShaderMaterial
			if m != null:
				m.set_shader_parameter("char_tint", col)
	for c in node.get_children():
		_tint(c, col)

# 플레이어가 주우면 해당 채집물 노드 제거
func remove(area: Area3D) -> void:
	var root := area.get_parent()
	_roots.erase(root)
	if is_instance_valid(root):
		root.queue_free()

extends Node3D
# 채집물 스폰 (day_changed마다 리스폰). 당일 상태는 저장 안 함 — abs_day 기반 결정적 배치라
# 같은 날 재로드해도 동일하게 재생성됨(파생 상태, DESIGN 11.1 저장 표면 최소).

const ToonChar := preload("res://common/toon_character.gd")

# 스폰 후보 지점 — 밭 Rect2i(0,2,8,4)·침대(5)·상점(-5)·상자(-2,4)·연못(10,0,0) 회피
const SPAWN_POINTS := [
	Vector3(-6, 0, 8), Vector3(-3, 0, 9), Vector3(2, 0, 9), Vector3(5, 0, 8),
	Vector3(-9, 0, 5), Vector3(-8, 0, -4), Vector3(-3, 0, -6), Vector3(6, 0, -7),
]
const SPAWN_PCT := 55  # 각 지점 스폰 확률(%)

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
	for i in SPAWN_POINTS.size():
		var h := absi(hash([GameClock.abs_day, i]))  # 결정적: 같은 날 재로드 = 같은 배치
		if h % 100 < SPAWN_PCT:
			_spawn(SPAWN_POINTS[i], pool[h % pool.size()])

func _clear() -> void:
	for r in _roots:
		if is_instance_valid(r):
			r.queue_free()
	_roots.clear()

func _spawn(pos: Vector3, fid: String) -> void:
	var root := Node3D.new()
	root.position = pos
	var mesh := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.28
	sm.height = 0.56
	mesh.mesh = sm
	mesh.material_override = ToonChar.make_solid(Color(0.5, 0.75, 0.35), 0.006)
	mesh.position = Vector3(0, 0.32, 0)
	root.add_child(mesh)
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

# 플레이어가 주우면 해당 채집물 노드 제거
func remove(area: Area3D) -> void:
	var root := area.get_parent()
	_roots.erase(root)
	if is_instance_valid(root):
		root.queue_free()

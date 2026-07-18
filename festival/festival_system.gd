extends Node3D
# 축제 시스템 (DESIGN 6.8). calendar.json 시간창을 level 트리거로 판정 —
# 활성 시 NpcSystem에 광장 배치·축제 상태 위임하고 광장 장식을 생성.
# 시간 파생은 전부 GameClock (자기 달력 소유 금지). 상태는 abs_day/game_min 파생이라 세이브 무변경.

const ToonChar := preload("res://common/toon_character.gd")
const DECOR_RING := 3.3   # 장식 링 (NPC 링보다 크게 감쌈)
const PASTELS := [
	Color(1.0, 0.75, 0.85), Color(1.0, 0.9, 0.6),
	Color(0.75, 0.85, 1.0), Color(0.85, 0.75, 1.0),
]

var _active_id := ""      # 현재 활성 축제 id ("" = 없음)
var _decor: Node3D = null

func _ready() -> void:
	add_to_group("festival_system")
	if not GameClock.tick.is_connected(_on_tick):
		GameClock.tick.connect(_on_tick)
	evaluate()  # from_dict는 신호 emit 안 하므로 세이브 로드 후 World가 재호출

func _on_tick(_abs_day: int, _game_min: int) -> void:
	evaluate()

# level 트리거: 지금 축제 시간창인지 판정해 상태 전이 (idempotent)
func evaluate() -> void:
	var now := _festival_now()
	if now == _active_id:
		return
	if _active_id != "":
		_exit()
	if now != "":
		_enter(now)
	_active_id = now

func _festival_now() -> String:
	var sid := GameData.season_id(GameClock.season())
	var day := GameClock.day_of_season()
	var m := GameClock.game_min
	for fid in GameData.calendar:
		var f: Dictionary = GameData.calendar[fid]
		if f["season"] == sid and int(f["day"]) == day and m >= int(f["start_min"]) and m < int(f["end_min"]):
			return fid
	return ""

func _enter(fid: String) -> void:
	var pa: Array = GameData.calendar[fid]["plaza"]
	var plaza := Vector2(pa[0], pa[1])
	var npc := get_tree().get_first_node_in_group("npc_system")
	if npc != null:
		npc.enter_festival(plaza)
	_build_decor(plaza)

func _exit() -> void:
	var npc := get_tree().get_first_node_in_group("npc_system")
	if npc != null:
		npc.exit_festival()
	if _decor != null:
		_decor.queue_free()
		_decor = null

# ── 광장 장식 (꽃 링 + 꽃잎 파티클) ─────────────────────────────
func _build_decor(plaza: Vector2) -> void:
	if _decor != null:  # 방어: 중복 생성 방지
		_decor.queue_free()
	_decor = Node3D.new()
	_decor.position = Vector3(plaza.x, 0, plaza.y)
	add_child(_decor)
	for i in 8:  # 꽃 화단 링
		var m := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.28
		s.height = 0.56
		m.mesh = s
		m.material_override = ToonChar.make_solid(PASTELS[i % PASTELS.size()], 0.006)
		var ang := TAU * i / 8.0
		m.position = Vector3(cos(ang) * DECOR_RING, 0.28, sin(ang) * DECOR_RING)
		_decor.add_child(m)
	_decor.add_child(_make_petals())

func _make_petals() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 60
	p.lifetime = 4.0
	p.position = Vector3(0, 4, 0)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(DECOR_RING, 0.2, DECOR_RING)
	pm.gravity = Vector3(0, -0.8, 0)
	pm.initial_velocity_min = 0.1
	pm.initial_velocity_max = 0.4
	pm.angular_velocity_min = -90.0
	pm.angular_velocity_max = 90.0
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.15, 0.15)
	p.draw_pass_1 = quad
	# ponytail: 파티클은 네이티브 빌보드 StandardMaterial (툰셰이더는 인스턴스 변환 미지원)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.72, 0.82)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	p.material_override = mat
	return p

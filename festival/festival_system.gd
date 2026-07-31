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
const CRATE := Color(0.62, 0.44, 0.28)   # 궤짝 목재 (decor.gd C_WOOD 계열)
const HARVEST := [                        # 수확물: 호박 주황 · 옥수수 금색
	Color(0.94, 0.52, 0.18), Color(0.96, 0.80, 0.30),
]
const WOOD := Color(0.55, 0.40, 0.26)     # 등불 기둥
const GLOW := Color(1.00, 0.82, 0.52)     # 등불 유리·점광 (decor.gd 가로등보다 살짝 붉게)
const LANTERN_E := 0.8                    # 상시 가로등(1.1)보다 약하게 = 보조광
const LANTERN_RANGE := 6.0
# 등불은 장식 링(3.3)보다 밖에, 등갓은 주민 머리 위에 둔다 — 안쪽·눈높이에 두면 광장 카메라에서
# 등갓이 주민 얼굴을 그대로 가린다(실측). 상시 가로등이 등갓을 y3.0에 두는 것과 같은 이유.
const LANTERN_RING := 4.6
const LANTERN_POST_H := 2.4
const LANTERN_SHADE_Y := 1.45             # 기둥 로컬 (월드 y = POST_H/2 + 1.45 = 2.65)

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
	var f: Dictionary = GameData.calendar[fid]
	var pa: Array = f["plaza"]
	var plaza := Vector2(pa[0], pa[1])
	var npc := get_tree().get_first_node_in_group("npc_system")
	if npc != null:
		npc.enter_festival(plaza, fid)  # fid = 축제별 대사 풀 선택 키
	_build_decor(plaza, String(f.get("decor", "")))

func _exit() -> void:
	var npc := get_tree().get_first_node_in_group("npc_system")
	if npc != null:
		npc.exit_festival()
	if _decor != null:
		_decor.queue_free()
		_decor = null

# ── 광장 장식 (calendar.json "decor" 키로 분기) ─────────────────
# ""(별빛 축제) = 장식 없음. 밤하늘 별·은하수와 상시 가로등이 그 축제의 그림이라
# 광장에 뭘 더 세우면 오히려 하늘을 가린다.
func _build_decor(plaza: Vector2, kind: String) -> void:
	if _decor != null:  # 방어: 중복 생성 방지
		_decor.queue_free()
		_decor = null
	if kind == "":
		return
	_decor = Node3D.new()
	_decor.position = Vector3(plaza.x, 0, plaza.y)
	add_child(_decor)
	match kind:
		"flower": _decor_flower()
		"harvest": _decor_harvest()
		"lantern": _decor_lantern()

# 꽃축제: 파스텔 화단 링 + 꽃잎 파티클
func _decor_flower() -> void:
	for i in 8:
		var m := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.28
		s.height = 0.56
		m.mesh = s
		m.material_override = ToonChar.make_solid(PASTELS[i % PASTELS.size()], 0.006)
		_decor.add_child(m)
		m.position = _ring_pos(i, 8, 0.28)
	_decor.add_child(_make_petals())

# 수확제: 호박·옥수수 색 나무 궤짝 링 + 그 위에 얹은 수확물 한 덩이
func _decor_harvest() -> void:
	for i in 8:
		var crate := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.7, 0.5, 0.7)
		crate.mesh = bm
		crate.material_override = ToonChar.make_solid(CRATE, 0.006)
		_decor.add_child(crate)
		crate.position = _ring_pos(i, 8, 0.25)
		crate.rotation.y = TAU * i / 8.0
		var produce := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.24
		sm.height = 0.44
		produce.mesh = sm
		produce.material_override = ToonChar.make_solid(HARVEST[i % HARVEST.size()], 0.006)
		crate.add_child(produce)
		produce.position = Vector3(0, 0.47, 0)

# 등불 축제: 낮은 기둥 + 발광 등갓 + 따뜻한 점광. 겨울 저녁 축제라 항상 켜둔다
# (상시 가로등과 달리 축제 시간창에만 존재하므로 낮 소등 판정이 필요 없다).
func _decor_lantern() -> void:
	for i in 8:
		var post := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.07
		cm.bottom_radius = 0.07
		cm.height = LANTERN_POST_H
		post.mesh = cm
		post.material_override = ToonChar.make_solid(WOOD, 0.004)
		_decor.add_child(post)
		post.position = _ring_pos(i, 8, LANTERN_POST_H * 0.5, LANTERN_RING)
		var shade := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.24
		sm.height = 0.54
		shade.mesh = sm
		shade.material_override = ToonChar.make_solid(GLOW, 0.004)
		post.add_child(shade)
		shade.position = Vector3(0, LANTERN_SHADE_Y, 0)
		var o := OmniLight3D.new()
		o.light_color = GLOW
		o.light_energy = LANTERN_E
		o.omni_range = LANTERN_RANGE
		post.add_child(o)
		o.position = Vector3(0, LANTERN_SHADE_Y, 0)

func _ring_pos(i: int, n: int, y: float, r := DECOR_RING) -> Vector3:
	var ang := TAU * i / float(n)
	return Vector3(cos(ang) * r, y, sin(ang) * r)

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

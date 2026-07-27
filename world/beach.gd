extends Node3D
# 바닷가 존 (H단계). interior.gd와 같은 "같은 월드 격리 좌표" 패턴 — 씬 전환이 없으므로
# 시계·세이브·오토로드·낮밤·비·하늘이 전부 그대로 돈다. 마을(|x|,|z|≤40)과 실내(120,120)에
# 겹치지 않는 (-150,150)에 짓고, 그룹 "door" Area3D 좌표 텔레포트로만 오간다.
#
# 마을 Ground(80×80)는 여기까지 오지 않는다 → 자체 받침(모래 plane + 충돌 박스)을 깐다.
# 바다는 연못·강과 같은 water.gdshader = 같은 툰 물이고, 낚시도 같은 "water" 그룹 트리거다.
# 다른 점은 메타 "spot"="sea" 하나 — 이것이 어종 풀을 바다 쪽으로 가른다.
#
# 마을 쪽 접근로(흙길·표지판·게이트)도 여기서 짓는다: 게이트 좌표 짝이 한 파일에 있어야
# 왕복 계약(도착점이 반대편 트리거 밖)을 눈으로 검증할 수 있다 — interior.gd가 OUT_DOOR를
# 들고 있는 것과 같은 이유.

const ToonChar := preload("res://common/toon_character.gd")
const Interior := preload("res://world/interior.gd")  # 오두막 문 목적지(집 실내) 단일 출처
const WATER_SHADER := preload("res://world/water.gdshader")

const ORIGIN := Vector3(-150, 0, 150)
const GROUND_Y := 0.10   # 지면 상면 — 마을 Ground 상면과 같은 높이(플레이어 낙하·발높이 동일)
const WATER_Y := 0.16    # 수면 — 강 물면과 같은 값(같은 셰이더라 높이도 맞춰 둔다)

# 모래사장(보는 판) / 바다(보는 판). rel = ORIGIN 기준.
# 판은 걷는 영역보다 한참 넓다: 고정 카메라가 좌우 ±38°·앞 74까지 담아서 걷는 경계까지만
# 깔면 프레임 구석에 존 밖 허공이 뚫린다(실측). 통행 제한은 아래 둘레 벽이 따로 한다.
const SAND_REL := Vector3(0, 0, 3.0)
const SAND_W := 150.0     # 걷는 폭(±24)의 3배. 존 끝에 서면 화면 가로 끝이 x≈±80까지 닿는다(실측)
const SAND_D := 64.0      # z ∈ [-29, 35] — 얕은 물 밑·존 남단 바깥까지
const SEA_REL := Vector3(0, 0, -25.0)
const SEA_W := 150.0      # 모래와 같은 폭 — 좁으면 원경 좌우 구석에서 수면이 끊긴다
const SEA_D := 42.0       # z ∈ [-46, -4] — 원경까지 채워 수평선이 화면 위에서 닫힌다
const SHORE_Z := -4.3     # 물가 충돌선. 바다로 걸어 들어가 허공에 떨어지는 것 방지
const WALK_HALF_X := 24.0 # 걷는 영역 반폭
const WALK_Z1 := 16.0     # 걷는 영역 남단
const WALL_H := 3.0

# ── 문 전환 (절대좌표 상수: test_core가 노드 없이 읽는 계약) ─────────
const B_SPAWN := Vector3(-150, 1.2, 158.6)   # 마을→해변 도착. 게이트 트리거 밖 + 바다를 정면에
const B_GATE := Vector3(-150, 1.0, 162.0)    # 해변 남단 게이트 "E: 마을로"
const HUT_REL := Vector3(6.5, 0, 2.0)        # 오두막 피벗(rel) — 모래사장 동쪽, 물가 동선 밖.
                                             # x=9는 도착 프레임 오른쪽 끝에 잘렸다(실측) → 6.5
const HUT_W := 5.0
const HUT_H := 3.4
const H_DOOR := Vector3(-143.5, 1.0, 155.4)  # 오두막 남향 문 앞 "E: 집으로" (rel 6.5, z=2+2.55+0.85)
const V_GATE := Vector3(24, 1.0, 32.5)       # 마을 남동 흙길 끝 "E: 바닷가로"
const V_SPAWN := Vector3(24, 2.0, 29.4)      # 해변→마을 도착. 게이트 트리거 밖(북쪽)
const DOOR_R := 0.7                          # interior와 동일 (프롬프트 사거리 = 이것 + InteractArea 1.3)
const FACE_N := Vector3(0, 0, -1)            # 북향 = 바다/마을 쪽. 카메라가 남(+Z)에 있어 정면이 다 보인다
const SPOT := "sea"                          # 낚시터 구분 — fish.json "spot"과 짝

# 팔레트: 마을 컬러박스 계열과 같은 채도대. world.gd 상수를 preload하지 않는 이유는
# world.gd가 이 스크립트를 preload하기 때문(순환 방지).
const C_SAND := Color(0.87, 0.80, 0.66)   # 마른 모래(웜톤). 채도를 더 주면 노을에 형광 노랑이 된다(실측)
const C_WET := Color(0.72, 0.68, 0.60)    # 젖은 모래 = 물가 라인. 갈색기를 빼야 노을에 주황 띠로 안 뜬다
const C_ROCK := Color(0.63, 0.62, 0.58)
const C_WOOD := Color(0.54, 0.40, 0.25)
const C_WALL := Color(0.90, 0.85, 0.76)
const C_ROOF := Color(0.42, 0.31, 0.56)
const C_PINE := Color(0.36, 0.50, 0.31)   # 해송(숲 띠 침엽수보다 살짝 짙게)

func _ready() -> void:
	add_to_group("beach")
	_sand()
	_sea()
	_props()
	_hut()
	_walls()
	_doors()
	_village_path()
	_wave_audio()

# ── 지면 ─────────────────────────────────────────────────────────
# 가시 판은 분할된 PlaneMesh로 깐다: 툰 셰이더의 월드 곡률이 정점 단위라 넓은 판을 한 장
# (정점 4개)으로 두면 곡률이 안 먹고 마을 지면과 어긋난다(world.tscn Ground도 80분할).
func _sand() -> void:
	_plane(SAND_REL + Vector3(0, GROUND_Y, 0), SAND_W, SAND_D, 40, C_SAND)
	# 물가 라인: 파도가 적신 띠. 수면 남단(z=-4) 바로 아래에 붙이고 모래 상면보다 살짝 띄워
	# z-fighting을 피한다. 플레이어는 물가 충돌선(-4.3+반경)까지 와서 이 띠 위에 선다.
	_plane(Vector3(0, GROUND_Y + 0.02, SHORE_Z + 1.3), SAND_W, 2.2, 4, C_WET)
	_collide(SAND_REL + Vector3(0, GROUND_Y - 0.3, 0), Vector3(SAND_W, 0.6, SAND_D))

func _sea() -> void:
	# ponytail: 해저 판은 두지 않는다 — 툰 물이 불투명이라 절대 안 보이고, 수면보다 넓게 깔면
	# 원경 구석에 어두운 판때기만 삐져나온다(실측). 수면 너머는 하늘 = 수평선.
	var m := ShaderMaterial.new()
	m.shader = WATER_SHADER
	_plane(SEA_REL + Vector3(0, WATER_Y, 0), SEA_W, SEA_D, 40, C_SAND).material_override = m  # 색은 물 셰이더로 덮음
	# 낚시 트리거: 물가 앞 띠만 덮는다(원경까지 덮으면 Area 중심이 멀어져 문 판정과 경합).
	# z ∈ [-17, -3] — 물가 충돌선(-4.3)에서 플레이어가 서면 InteractArea(1.3)가 넉넉히 닿는다.
	var a := Area3D.new()
	a.add_to_group("water")
	a.set_meta("spot", SPOT)
	a.position = ORIGIN + Vector3(0, 0.5, -10.0)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(SEA_W - 14.0, 2.0, 14.0)
	cs.shape = sh
	a.add_child(cs)
	a.add_child(_label("바다", 1.4))
	add_child(a)

# 바위·해송. 결정적 시드(스샷 재현) — 마을 숲 띠와 같은 방식.
func _props() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260728
	for r in [Vector2(-12.5, -3.2), Vector2(-6.0, -1.4), Vector2(13.5, -2.6), Vector2(19.0, 0.4)]:
		var s := rng.randf_range(0.7, 1.25)
		_sphere(Vector3(r.x, GROUND_Y + 0.25 * s, r.y), 0.75 * s, C_ROCK)
		_sphere(Vector3(r.x + 0.9 * s, GROUND_Y + 0.12 * s, r.y + 0.5 * s), 0.42 * s, C_ROCK)
	# 해송은 |x|≥13에만: 도착 지점 정남(|x|<5)에 두면 카메라 코앞이라 화면을 통째로 가린다(실측).
	# 걷는 영역(±24) 바깥 것들은 해안이 계속 이어져 보이게 하는 원경 장식 — 넓은 모래 판이
	# 텅 빈 사막으로 읽히지 않게 한다(마을 숲 띠와 같은 역할).
	for t in [Vector2(-20.0, 12.5), Vector2(-13.5, 14.0), Vector2(14.0, 13.5), Vector2(20.5, 9.5),
			Vector2(-31.0, 6.0), Vector2(-42.0, 0.0), Vector2(30.0, 3.0), Vector2(41.0, 8.0)]:
		_pine(t, rng.randf_range(0.9, 1.3))

# 해송: 줄기(원통) + 원뿔 수관 — world.gd _tree 침엽수 레시피와 같은 조립.
func _pine(at: Vector2, s: float) -> void:
	_cyl(Vector3(at.x, GROUND_Y + 0.9 * s, at.y), 0.22 * s, 1.8 * s, C_WOOD)
	var cone := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = 1.1 * s
	cm.height = 2.6 * s
	cone.mesh = cm
	cone.material_override = ToonChar.make_solid(C_PINE, 0.006)
	cone.position = ORIGIN + Vector3(at.x, GROUND_Y + 3.1 * s, at.y)
	add_child(cone)

# 귀가 오두막: 문이 남향(+z)이라 카메라(플레이어 뒤 +Z·위)가 몸통에 가리지 않는다.
# 마을 컬러박스 _house와 같은 조립(벽·처마·문짝) — 프리미티브 재사용.
func _hut() -> void:
	var c := HUT_REL
	var half := HUT_W * 0.5
	_box(Vector3(c.x, HUT_H * 0.5 + GROUND_Y, c.z), Vector3(HUT_W, HUT_H, HUT_W), C_WALL)
	_box(Vector3(c.x, HUT_H + 0.2 + GROUND_Y, c.z), Vector3(HUT_W + 0.5, 0.5, HUT_W + 0.5), C_ROOF)
	_box(Vector3(c.x, 0.9 + GROUND_Y, c.z + half + 0.05), Vector3(0.9, 1.8, 0.12), C_WOOD, 0.004)
	_collide(Vector3(c.x, HUT_H * 0.5 + GROUND_Y, c.z), Vector3(HUT_W, HUT_H, HUT_W))

# 보이지 않는 둘레 벽: 북=물가선(바다 진입 차단), 남/동/서=존 경계(허공 낙하 차단).
func _walls() -> void:
	var z0 := SHORE_Z
	var z1 := WALK_Z1
	var mid := (z0 + z1) * 0.5
	var depth := z1 - z0
	var span := WALK_HALF_X * 2.0
	_collide(Vector3(0, WALL_H * 0.5, z0 - 0.3), Vector3(span, WALL_H, 0.6))
	_collide(Vector3(0, WALL_H * 0.5, z1 + 0.3), Vector3(span, WALL_H, 0.6))
	for s in [-1.0, 1.0]:
		_collide(Vector3(s * (WALK_HALF_X + 0.3), WALL_H * 0.5, mid), Vector3(0.6, WALL_H, depth))

func _doors() -> void:
	_door(B_GATE, V_SPAWN, "E: 마을로", FACE_N)
	_door(V_GATE, B_SPAWN, "E: 바닷가로", FACE_N)
	_door(H_DOOR, Interior.IN_SPAWN, "E: 집으로", Interior.FACE_IN)

# 마을 남동 접근로: 집4(24,20) 남쪽 흙길 + 표지판. 둘 다 무충돌 장식이다 —
# 마을 쪽에 새 충돌체를 만들지 않으므로 WORLD_VERSION 범프가 필요 없다(구세이브 위치가
# 새 충돌체에 박힐 수 없다). 강(마을 남면을 감싼다)은 여기서 x≈-7까지 물러나 있어 간섭 없다.
func _village_path() -> void:
	var road := _box_at(Vector3(24, 0.16, 28.5), Vector3(2.4, 0.05, 11.0), C_WOOD, 0.0)
	road.name = "BeachRoad"
	# 표지판: 기둥 + 판 + 라벨. 길 서쪽에 비켜 세워 게이트 프롬프트와 겹치지 않게.
	_box_at(Vector3(22.4, 0.9, 32.5), Vector3(0.14, 1.8, 0.14), C_WOOD, 0.004)
	_box_at(Vector3(22.4, 1.75, 32.5), Vector3(1.5, 0.6, 0.1), C_WALL, 0.004)
	var l := _label("바닷가 ↓", 2.5)
	l.position = Vector3(22.4, 2.5, 32.5)
	add_child(l)

# 파도 소리: 물가 선을 따라 등간격 3D 에미터(world.gd 물가 앰비언스와 같은 패턴·같은 루프).
# 피치를 낮게 흩어 놓으면 같은 물소리가 시냇물이 아니라 파도로 읽힌다.
func _wave_audio() -> void:
	if Sfx.water_loop == null or Sfx.silent:  # 헤드리스면 에미터 자체를 안 만든다
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260728
	for i in 5:
		var x := -18.0 + i * 9.0
		var sp := AudioStreamPlayer3D.new()
		sp.stream = Sfx.water_loop
		sp.bus = Sfx.bus_or_master("Ambience")
		sp.unit_size = 7.0
		sp.max_distance = 22.0
		sp.volume_db = -3.0
		sp.pitch_scale = rng.randf_range(0.70, 0.86)  # 낮은 피치 = 파도
		sp.position = ORIGIN + Vector3(x, 0.3, SHORE_Z - 1.5)
		add_child(sp)
		sp.play(rng.randf() * Sfx.water_loop.get_length())

# ── 조립 헬퍼 (rel = ORIGIN 기준) ────────────────────────────────
func _plane(rel: Vector3, w: float, d: float, sub: int, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(w, d)
	pm.subdivide_width = sub
	pm.subdivide_depth = sub
	mi.mesh = pm
	mi.material_override = ToonChar.make_solid(color, 0.0)
	mi.position = ORIGIN + rel
	add_child(mi)
	return mi

func _box(rel: Vector3, size: Vector3, color: Color, outline := 0.006) -> MeshInstance3D:
	return _box_at(ORIGIN + rel, size, color, outline)

func _box_at(at: Vector3, size: Vector3, color: Color, outline := 0.006) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = ToonChar.make_solid(color, outline)
	mi.position = at
	add_child(mi)
	return mi

func _sphere(rel: Vector3, r: float, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 1.7  # 살짝 눌린 돌
	mi.mesh = sm
	mi.material_override = ToonChar.make_solid(color, 0.006)
	mi.position = ORIGIN + rel
	add_child(mi)

func _cyl(rel: Vector3, r: float, h: float, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	mi.mesh = cm
	mi.material_override = ToonChar.make_solid(color, 0.004)
	mi.position = ORIGIN + rel
	add_child(mi)

func _collide(rel: Vector3, size: Vector3) -> void:
	var sb := StaticBody3D.new()
	sb.position = ORIGIN + rel
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	sb.add_child(cs)
	add_child(sb)

# 문 = 그룹 "door" Area3D + 메타(목적지·문구·도착 방향). player.gd는 메타만 읽는다.
func _door(at: Vector3, to: Vector3, label: String, face: Vector3) -> void:
	var a := Area3D.new()
	a.add_to_group("door")
	a.position = at
	a.set_meta("door_to", to)
	a.set_meta("door_label", label)
	a.set_meta("door_face", face)
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = DOOR_R
	cs.shape = sh
	a.add_child(cs)
	add_child(a)

func _label(text: String, y: float) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = Vector3(0, y, 0)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	l.pixel_size = 0.0007
	l.font_size = 96
	l.outline_size = 24
	return l

# ── 순수 판정 (test_core가 노드 없이 검증) ────────────────────────
# 이 좌표가 해변 존인가. 문 앞 여유까지 포함해 문턱에서 판정이 깜빡이지 않게 한다.
static func inside(p: Vector3) -> bool:
	return absf(p.x - ORIGIN.x) < WALK_HALF_X + 4.0 and p.z - ORIGIN.z > SEA_REL.z - 6.0 \
		and p.z - ORIGIN.z < WALK_Z1 + 4.0

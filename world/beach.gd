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
# 팔레트·절차 블롭 나무 단일 출처. world.gd는 beach.gd를 preload하므로 역방향은 순환이지만,
# decor.gd는 world/beach 어느 쪽도 참조하지 않아 안전하다(마을 드레싱과 같은 값을 그대로 쓴다).
const Decor := preload("res://world/decor.gd")
const WATER_SHADER := preload("res://world/water.gdshader")
const GROUND_SHADER := preload("res://world/ground.gdshader")  # 마을 초지와 같은 절차 지면 패턴
const ROAD_SHADER := preload("res://world/road.gdshader")      # 마을 흙길과 같은 침식 가장자리

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
# 젖은 모래 띠 = 물가선. 바다 판 남단(SEA_REL.z + SEA_D/2)을 띠 **한가운데** 두고 수면 위에 깐다 —
# 띠 가장자리만 침식해 봐야 그 밑에서 바다 판의 자로 그은 직선 남단이 그대로 드러난다.
const WET_Z := SEA_REL.z + SEA_D * 0.5
const WET_D := 3.6        # 띠 깊이. 반깊이 1.8 > WET_ERODE = 어떤 각도에서도 수면 모서리가 안 샌다
const WET_ERODE := 1.2    # 물가선 물결 진폭(m). 반깊이보다 작아야 바다 판 남단이 안 드러난다
# 접지 그림자 판 높이 — 젖은 모래 띠(WATER_Y+0.02)보다 위. 모래(GROUND_Y) 높이에 깔면 띠가
# 덮은 자리(갯바위 절반이 그 안이다)에서 깊이 판정에 걸려 그림자가 통째로 사라진다.
const SHADOW_Y := WATER_Y + 0.03
# 원경 곡률이 멈추는 뷰 깊이(m) — water.gdshader curve_cap. 툰 월드 곡률(v.y −= 0.006·z²)은
# 수면을 뷰 깊이 35 부근 크레스트에서 끊어서, 도착 지점에선 바다가 세로 33px짜리 띠로만 남았다
# (실측 sea/before_beach_spawn_h12). 이 깊이 밖을 평평하게 두면 판 남단이 그대로 수평선이 된다.
# 40인 근거: 걷는 영역 어디서 보든 물가선(z_rel −4.3)의 뷰 깊이는 최대 36(최대 줌아웃 1.6배)이라
# 항상 캡 **안**이다 → 물가 이음매의 곡률은 모래·젖은 띠와 언제나 일치한다(SEA_*/WET_* 계약 불변).
const SEA_CURVE_CAP := 40.0
const FOAM_GAP := 6.0     # 파도선 간격(m). 물가선 기준 반복 — 42m 판에 7줄쯤 들어온다
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

# 팔레트(소프트닝 v2): 건물·목재·석재·침엽은 Decor 상수를 그대로 쓴다 = 마을과 같은 파스텔.
# 아래 상수는 해변 전용이거나, 순환 preload를 피하려 복제한 것뿐이다(복제분은 test_core가 핀).
#
# 모래는 **지면 계열 albedo 상한 0.76**을 지킨다 — 정오 수평면은 그 위에서 255로 포화한다
# (world.gd C_GRASS 실측). 옛 0.87은 상한을 한참 넘겨 낮 모래사장이 통째로 흰 판이었다(전 스샷).
const C_SAND := Color(0.750, 0.718, 0.653)  # 마른 모래(웜톤). hue 40° 보존, 채도 0.24→0.13
const C_WET := Color(0.660, 0.634, 0.586)   # 젖은 모래 = 물가 띠. 같은 hue 한 단 어둡게(젖음 대비)
const C_ROCK := Color(0.660, 0.654, 0.631)  # 갯바위 — 파스텔 시프트(채도 ×0.55, 명도 +5%p)
const C_SHELL := Color(0.750, 0.700, 0.700) # 조개 — 모래와 같은 명도 상한, 분홍기로만 갈린다
const C_WEED := Color(0.470, 0.545, 0.470)  # 해초 — 젖은 모래(0.66)보다 확실히 어두운 초록
# 마을 흙길 색 = world.gd C_ROAD / C_ROAD_E와 같은 값. 순환 preload를 피한 복제라 어긋나면
# 진입로만 색이 튄다 — test_core가 동일성을 핀한다(decor 등나무 앵커와 같은 규약).
const C_ROAD := Color(0.700, 0.619, 0.476)
const C_ROAD_E := Color(0.720, 0.673, 0.590)

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
	# 마을 초지와 같은 절차 패턴 셰이더 재사용(새 셰이더 복제 금지) — 단색 판이면 낮 모래사장이
	# 무늬 0인 거대한 판때기로 읽힌다. uniform만 모래로 튠: 칸을 잘게, 감광을 얕게 = 체커가
	# 아니라 은은한 모래 얼룩.
	var sm := ShaderMaterial.new()
	sm.shader = GROUND_SHADER
	sm.set_shader_parameter("albedo", C_SAND)
	# 초지 값(cell 1.4 · 감광 0.11)을 그대로 쓰면 모래가 **타일 바닥**으로 읽힌다(실측) — 잔디는
	# 깎은 자국으로 보이지만 모래엔 그런 독법이 없다. 두 가지로 갈랐다:
	#   · mottle=0 — 칸별 랜덤은 셀 경계가 각져서 모자이크 타일이 된다(실측, 모래에선 치명적).
	#     둥근 체커 항(smoothstep)만 남기면 경계가 통째로 부드럽다.
	#   · 칸을 넓히고(2.4m) 감광을 얕게(0.05) — 격자가 아니라 완만한 모래 언덕 음영으로 읽힌다.
	sm.set_shader_parameter("cell", 2.4)
	sm.set_shader_parameter("shade_depth", 0.05)
	sm.set_shader_parameter("mottle", 0.0)
	_plane(SAND_REL + Vector3(0, GROUND_Y, 0), SAND_W, SAND_D, 40, C_SAND).material_override = sm
	# 물가 라인: 파도가 적신 띠. 마을 흙길과 같은 road.gdshader로 가장자리를 갉으면(라운드 SDF −
	# 월드 fbm) 그대로 물결치는 물가선이 된다. 수면(WATER_Y)보다 위에 깔아 바다 판의 직선 남단을
	# 띠가 덮는다. 플레이어는 물가 충돌선(-4.3+반경)까지 와서 이 띠 위에 선다.
	var wm := ShaderMaterial.new()
	wm.shader = ROAD_SHADER
	wm.set_shader_parameter("albedo", C_WET)
	wm.set_shader_parameter("edge_color", C_SAND)  # 마른 모래로 스미며 사라진다
	wm.set_shader_parameter("half_ext", Vector2(SAND_W * 0.5, WET_D * 0.5))
	wm.set_shader_parameter("corner", 1.2)   # 반깊이 1.8보다 작아야 SDF가 성립
	wm.set_shader_parameter("erode", WET_ERODE)
	wm.set_shader_parameter("fade", 0.35)    # 0.9면 띠 전체가 edge_color = 젖은 티가 안 난다(실측)
	_plane(Vector3(0, WATER_Y + 0.02, WET_Z), SAND_W, WET_D, 40, C_WET).material_override = wm
	_collide(SAND_REL + Vector3(0, GROUND_Y - 0.3, 0), Vector3(SAND_W, 0.6, SAND_D))

func _sea() -> void:
	# ponytail: 해저 판은 두지 않는다 — 툰 물이 불투명이라 절대 안 보이고, 수면보다 넓게 깔면
	# 원경 구석에 어두운 판때기만 삐져나온다(실측). 수면 너머는 하늘 = 수평선.
	var m := ShaderMaterial.new()
	m.shader = WATER_SHADER
	# 바다를 바다로 읽히게 하는 세 가지. 전부 같은 셰이더의 uniform이라 연못·강은 손대지 않는다.
	m.set_shader_parameter("curve_cap", SEA_CURVE_CAP)  # ① 원경 볼륨 = 수평선
	m.set_shader_parameter("foam_gap", FOAM_GAP)        # ② 밀려오는 흰 파도선
	m.set_shader_parameter("foam_z", ORIGIN.z + WET_Z)  # 위상 0 = 물가선(젖은 모래 띠 한가운데)
	# ③ 하이라이트 패치를 좁힌다: 연못 값(0.60)이면 수면 절반이 흰 얼룩이라 파도선이 묻힌다.
	m.set_shader_parameter("coverage", 0.74)
	var sea := _plane(SEA_REL + Vector3(0, WATER_Y, 0), SEA_W, SEA_D, 40, C_SAND)
	sea.material_override = m  # 색은 물 셰이더로 덮음
	# 캡의 대가: 이 판만 툰 곡률로 말려 내려가지 않으니 150 떨어진 마을 컷 하늘에 물비늘 리본으로
	# 남는다(실측 audit2_0809/open_pav_h12 좌상단). 판을 좁히면 수평선이 깨지고, 캡을 거리로
	# 게이팅하면 원경 볼륨 자체가 흔들린다 → 존 밖에선 그냥 안 그린다(라벨과 같은 네이티브 거리 컬링).
	# 70인 근거(카메라 = 플레이어 + offset(0,6.5,9.5)): 걷는 영역 어디서 봐도 판 중심까지 최대 57
	# (남동 구석 컷 55), 가장 가까운 마을 시점인 남서 숲(-30,26)조차 판 **동쪽 끝**까지 82다.
	# 페이드 없이 자른다 — 존 왕복은 좌표 텔레포트라 경계를 걸어서 넘는 프레임이 없다.
	sea.visibility_range_end = 70.0
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
		_contact(r.x + 0.45 * s, r.y + 0.25 * s, 1.05 * s)  # 두 돌을 한 장으로 덮는다
	# 해송은 |x|≥13에만: 도착 지점 정남(|x|<5)에 두면 카메라 코앞이라 화면을 통째로 가린다(실측).
	# 걷는 영역(±24) 바깥 것들은 해안이 계속 이어져 보이게 하는 원경 장식 — 넓은 모래 판이
	# 텅 빈 사막으로 읽히지 않게 한다(마을 숲 띠와 같은 역할).
	for t in [Vector2(-20.0, 12.5), Vector2(-13.5, 14.0), Vector2(14.0, 13.5), Vector2(20.5, 9.5),
			Vector2(-31.0, 6.0), Vector2(-42.0, 0.0), Vector2(30.0, 3.0), Vector2(41.0, 8.0)]:
		# 회전은 같은 rng 스트림에서(결정적) — 안 돌리면 8그루가 같은 로브 방향 = 복붙 실루엣.
		_pine(t, rng.randf_range(0.9, 1.3), rng.randf() * TAU)
	_litter(rng)

# 모래 소품: 조개·유목·해초. 갯바위 4·해송 8만으로는 걷는 영역(±24 × z −4~16)이 여전히 빈
# 판때기다 — 도착 프레임의 화면 아래 절반이 통째로 무늬 없는 모래였다(실측 before_beach_spawn_h12).
# 전부 무충돌 장식(마을 decor.gd와 같은 규약) — 통행은 둘레 벽만이 정한다.
# 접지 그림자는 안 깐다: SHADOW_Y(0.19)가 이 소품들 키(0.1~0.35)와 겹쳐 판이 소품을 가른다.
# 좌표는 손으로 고른 표다(갯바위·해송과 같은 문법). 오두막 발치(rel 6.5 ±3.5)와 물가 낚시
# 자리(|x|<3, z −4~0)는 비워 프롬프트·문 앞 그림을 가리지 않는다.
func _litter(rng: RandomNumberGenerator) -> void:
	# 조개: 눌린 반구 한 쌍(짝조개). 모래보다 밝고 분홍기라 정오에도 실루엣이 남는다.
	# 도착 시점 정면(|x|<4, z>8)은 비운다 — 카메라 코앞이라 조개 하나가 화면 아래를 채운다(실측).
	for c in [Vector2(-4.6, 0.4), Vector2(3.6, -1.2), Vector2(-11.0, 4.6), Vector2(13.2, 5.0),
			Vector2(-17.5, 9.0), Vector2(-6.8, 9.2), Vector2(9.5, 13.5), Vector2(17.5, 12.0)]:
		var s := rng.randf_range(0.8, 1.25)
		_sphere(Vector3(c.x, GROUND_Y, c.y), 0.30 * s, C_SHELL)
		_sphere(Vector3(c.x + 0.34 * s, GROUND_Y, c.y + 0.18 * s), 0.19 * s, C_SHELL)
	# 유목: 밀려 올라온 통나무 토막. 눕혀야(x축 90°) 모래에 박힌 말뚝이 안 된다. z 성분 = 눕힌 뒤 방향각.
	for w in [Vector3(-14.0, 1.6, 0.7), Vector3(8.0, 8.8, -0.4), Vector3(-2.4, 14.2, 1.9),
			Vector3(20.0, 3.4, 2.6)]:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.16
		cm.bottom_radius = 0.20
		cm.height = rng.randf_range(1.5, 2.4)
		mi.mesh = cm
		mi.material_override = ToonChar.make_solid(Decor.C_WOOD_D, 0.006)
		mi.rotation = Vector3(PI * 0.5, w.z, 0.0)
		mi.position = ORIGIN + Vector3(w.x, GROUND_Y + 0.16, w.y)
		add_child(mi)
	# 해초: 물가에 밀려온 짙은 초록 무더기. 젖은 모래 띠 위(WATER_Y+0.04)에 얹는다.
	for g in [Vector2(-8.2, -3.0), Vector2(6.2, -3.4), Vector2(-19.0, -2.4), Vector2(15.0, -2.8),
			Vector2(-1.0, -3.6)]:
		for _i in 3:
			var p: Vector2 = g + Vector2(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.35, 0.35))
			_sphere(Vector3(p.x, WATER_Y + 0.04, p.y), rng.randf_range(0.16, 0.28), C_WEED)

# 해송: 절차 블롭 침엽(decor.gd 단일 출처).
# **미해결 격차**: 마을 나무는 킷 모델로 전면 교체했는데 해변만 절차 블롭이 남았다 — 파크 킷에
# 침엽수가 없어서다. 존을 넘으면 나무 그림체가 갈린다. 침엽 킷을 구하면 여기도 같이 넘긴다.
func _pine(at: Vector2, s: float, rot: float) -> void:
	var mi := MeshInstance3D.new()
	# 해송 = 홀쭉한 침엽. 마을 나무가 파크 킷으로 전면 교체된 뒤 BLOB_KINDS에 남은 유일한 종이다
	# (킷에 침엽수가 없다) — 즉 지금은 이 호출부가 blob_mesh의 단독 사용처다.
	mi.mesh = Decor.blob_mesh(Decor.BLOB_KINDS["cone_slim"], Decor.C_CONIF)
	mi.scale = Vector3.ONE * (s * 3.4)  # 옛 원뿔 전고(~4.4s)와 같은 키 = 마을 숲 띠 스케일 대역
	mi.rotation.y = rot
	mi.position = ORIGIN + Vector3(at.x, GROUND_Y, at.y)
	add_child(mi)
	_contact(at.x, at.y, 1.15 * s)  # 수관 반경(0.38 × 3.4s) 대역

# 귀가 오두막: 문이 남향(+z)이라 카메라(플레이어 뒤 +Z·위)가 몸통에 가리지 않는다.
# 마을 컬러박스 _house와 같은 조립(벽·처마·문짝) — 프리미티브 재사용.
func _hut() -> void:
	var c := HUT_REL
	var half := HUT_W * 0.5
	_box(Vector3(c.x, HUT_H * 0.5 + GROUND_Y, c.z), Vector3(HUT_W, HUT_H, HUT_W), Decor.C_CREAM)
	_box(Vector3(c.x, HUT_H + 0.2 + GROUND_Y, c.z), Vector3(HUT_W + 0.5, 0.5, HUT_W + 0.5), Decor.C_ROOF)
	_box(Vector3(c.x, 0.9 + GROUND_Y, c.z + half + 0.05), Vector3(0.9, 1.8, 0.12), Decor.C_WOOD, 0.004)
	_collide(Vector3(c.x, HUT_H * 0.5 + GROUND_Y, c.z), Vector3(HUT_W, HUT_H, HUT_W))
	_contact(c.x, c.z, half + 0.6)   # 처마(HUT_W+0.5) 밖으로 여유 — 벽 밑에만 깔면 오두막에 다 가린다

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
	# 마을 흙길과 **같은 셰이더**(road.gdshader): 라운드 SDF − 월드 fbm 침식 + 불투명 discard.
	# half_ext는 박스마다 다르므로 호출부가 넣는다(world.gd _road와 같은 계약).
	var sz := Vector3(2.4, 0.05, 11.0)  # 폭은 마을 ROAD_W와 같은 2.4
	var road := _box_at(Vector3(24, 0.16, 28.5), sz, C_ROAD, 0.0)
	road.name = "BeachRoad"
	var rm := ShaderMaterial.new()
	rm.shader = ROAD_SHADER
	rm.set_shader_parameter("albedo", C_ROAD)
	rm.set_shader_parameter("edge_color", C_ROAD_E)
	rm.set_shader_parameter("half_ext", Vector2(sz.x * 0.5, sz.z * 0.5))
	road.material_override = rm
	# 표지판: 기둥 + 판 + 라벨. 길 서쪽에 비켜 세워 게이트 프롬프트와 겹치지 않게.
	_box_at(Vector3(22.4, 0.9, 32.5), Vector3(0.14, 1.8, 0.14), Decor.C_WOOD, 0.004)
	_box_at(Vector3(22.4, 1.75, 32.5), Vector3(1.5, 0.6, 0.1), Decor.C_CREAM, 0.004)
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
	bm.subdivide_depth = _subdiv_z(size.z)
	mi.mesh = bm
	mi.material_override = ToonChar.solid_or_wood(color, size, outline)
	mi.position = at
	add_child(mi)
	return mi

# 접지 그림자: 오브젝트 밑 어두운 타원 판 하나(무충돌). 판 조립은 ToonChar 공용 —
# 캐릭터 그림자(player·npc_system)와 같은 판이라야 한 존에서 문법이 갈리지 않는다.
func _contact(x: float, z: float, r: float) -> void:
	var mi := ToonChar.contact_shadow(r)
	mi.position = ORIGIN + Vector3(x, SHADOW_Y, z)
	add_child(mi)

func _sphere(rel: Vector3, r: float, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 1.7  # 살짝 눌린 돌
	mi.mesh = sm
	mi.material_override = ToonChar.make_solid(color, 0.006)
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
	l.fixed_size = true
	l.pixel_size = 0.0007
	l.font_size = 36   # 화면 ~20px(fov 48·720p) = HUD 프롬프트(24px) 한 단 아래. world.tscn과 같은 값
	l.outline_size = 9  # 96/24와 같은 0.25 비율
	# 거리 페이드 — world.tscn 마을 라벨과 같은 방식(FADE_SELF). fixed_size라 라벨은 거리를
	# 무시하고 같은 크기로 그려진다 → 해변의 "바다"가 150u 떨어진 마을 광장 컷 하늘에
	# 그대로 떠 있었다(audit_0808/open_pav_h12). 거리 하나로 끊는다.
	# 소거 거리는 마을과 같은 22, 페이드 폭만 6→3으로 좁혔다 — lookdev/shots/sky_label 실측
	# (화면 알파에서 역산한 카메라~라벨 거리):
	#   게이트 컷 "바닷가 ↓" ~10 / 물가(낚시 자리) "바다" 17.5 = 안내로 읽혀야 하는 근거리
	#   해변 도착 컷 "바다" ~25 = 바다가 이미 화면 절반이라 잉여 / 마을 컷 150+ = 하늘 잡음
	# 마을 값 22/6을 그대로 쓰면 페이드 시작(16)이 낚시 자리(17.5)를 먹어 "바다"가 75% 유령이 되고,
	# end를 25~26으로 늘리면 이번엔 도착 컷에 4~7% 유령이 남는다. → 19까지 100%, 22 밖 소거.
	l.visibility_range_end = 22.0
	l.visibility_range_end_margin = 3.0
	l.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	return l

# ── 순수 판정 (test_core가 노드 없이 검증) ────────────────────────
# 곡률 셰이더(v.y -= 0.006·z²)는 정점 단위 — 세분할 없는 긴 박스는 장축이 현으로 근사돼
# 가운데가 지면 아래로 잠긴다(진입로 11u면 ~0.18 침하). world.gd _subdiv_z와 같은 식 —
# 순환 preload를 피한 복제라 test_core가 동일성을 핀한다.
static func _subdiv_z(len_z: float) -> int:
	return maxi(0, int(len_z / 1.5) - 1)

# 이 좌표가 해변 존인가. 문 앞 여유까지 포함해 문턱에서 판정이 깜빡이지 않게 한다.
static func inside(p: Vector3) -> bool:
	return absf(p.x - ORIGIN.x) < WALK_HALF_X + 4.0 and p.z - ORIGIN.z > SEA_REL.z - 6.0 \
		and p.z - ORIGIN.z < WALK_Z1 + 4.0

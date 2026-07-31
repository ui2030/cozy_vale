extends Node3D
# 마을 드레싱 (P3 1차) — 소품·꽃 덤불·숲 띠. **전부 무충돌 장식**이다.
# WORLD_VERSION 3 유지의 근거가 "데코는 통행·상호작용을 건드리지 않는다"이므로,
# ① 로드한 GLB에서 충돌체를 벗기고 ② 빌드 끝에 데코 루트 전체를 스캔해 로그로 증명한다.
#
# 에셋: Kenney Nature Kit 2.1 (CC0) — assets/props/*.glb. 이 repo 관례대로 Godot 임포트
# 파이프라인이 아니라 ToonChar.load_glb 런타임 로드(가구 전례: world/interior.gd).
# 킷 원본 색은 마을 팔레트와 다르므로 머티리얼 이름 → VILLAGE_SPEC §2 팔레트로 다시 칠한다.
#
# 툰 변환 순서: decor는 자체 변환한다(GLB=ToonChar.apply, 절차 메시=make_solid). world.gd의
# _convert_statics는 material_override가 StandardMaterial3D인 노드만 보므로 여기 것은 전부 스킵된다.

const ToonChar := preload("res://common/toon_character.gd")
const DayNight := preload("res://world/day_night.gd")  # 가로등 점등 시각 판정(단일 출처)
const DIR := "res://assets/props/"
const OUTLINE := 0.006   # world.gd 정적물과 같은 연필선 두께
const GROUND_Y := 0.10   # 지면 상면 (world.tscn Ground / beach.gd GROUND_Y와 동일)

# ── 팔레트 (VILLAGE_SPEC §2, 낮 기준 — world.gd 상수와 같은 값) ──────
# 파스텔 시프트(소프트닝 v1) — world.gd와 같은 규칙·같은 값(채도 −15%p / ×0.55 하한, 명도 +5%p).
const C_WOOD   := Color(0.590, 0.480, 0.362)  # 브라운
const C_WOOD_D := Color(0.470, 0.372, 0.283)  # 목재 음영
const C_STONE  := Color(0.770, 0.758, 0.735)
const C_CREAM  := Color(0.880, 0.844, 0.774)  # 크림 (world.gd C_WALL과 같은 값)
const C_ROOF   := Color(0.509, 0.429, 0.610)  # 보라 진
const C_GREEN  := Color(0.652, 0.710, 0.494)  # 그린 (풀·덤불)
const C_LEAF   := Color(0.576, 0.650, 0.444)  # 활엽 수관 — 지면(0.627,0.72,0.576)보다 깊게
const C_CONIF  := Color(0.509, 0.600, 0.439)  # 침엽수(어두운 그린)
const C_YELLOW := Color(0.880, 0.776, 0.432)  # 개나리
const C_LAV    := Color(0.656, 0.572, 0.740)  # 라벤더/보라 중
const C_LILAC  := Color(0.840, 0.758, 0.840)  # 라일락
const C_WIST   := Color(0.720, 0.649, 0.790)  # 등나무 보라
const C_GLASS  := Color(1.00, 0.90, 0.62)  # 가로등 유리(옐로 창불빛)
# 서리 앉은 마른 풀. 눈 지면(world.gd C_SNOW 0.67~0.76)보다 확실히 아래여야 실루엣이 읽힌다 —
# 비슷한 값으로 두면 흰 바탕에 흰 낙서가 되어 풀포기가 사라진다(실측).
const C_FROST  := Color(0.48, 0.54, 0.56)
# 수관용 서리톤은 풀포기용보다 훨씬 밝다. 풀은 흰 눈 지면 위에 놓여 어두워야 읽히지만, 수관은
# 크림 하늘을 배경으로 서 있어서 C_FROST를 쓰면 화면에 (113,124,142)로 나와 눈 덮인 나무가
# 아니라 바위 덩어리로 보인다(실측). 눈 지면(0.71/0.73/0.76) 바로 아래 = 가지에 얹힌 눈.
const C_FROST_LEAF := Color(0.66, 0.70, 0.74)

# Kenney 머티리얼 이름 → 마을 팔레트. 없는 이름은 원본색 유지 + 로그로 알린다.
const MAT_COLORS := {
	"leafsGreen": C_LEAF, "leafsDark": C_CONIF, "grass": C_GREEN,
	"woodBark": C_WOOD, "woodBarkDark": C_WOOD_D, "wood": C_WOOD, "woodDark": C_WOOD_D,
	"dirt": C_STONE, "colorYellow": C_YELLOW, "colorPurple": C_LAV, "_defaultMat": C_CREAM,
}

# ── 데코 금지 존 (Codex MUST-FIX 2) ─────────────────────────────────
# 기능(통행·상호작용·연출)을 침범하면 안 되는 곳. 소품·꽃·나무 전부 이 판정을 통과해야 한다.
const NO_DECOR_CIRCLES := [
	[Vector2(0, 0), 2.4],        # 분수 (충돌 r1 + 접근 여유)
	[Vector2(0, -6), 4.0],       # 축제·결혼 집합 링 (FEST_RING 2.3 / 축제 장식 DECOR_RING 3.3)
	[Vector2(0, -3.5), 2.2],     # 기본 스샷 지점 (world.gd festival/hour 인자)
	[Vector2(10, 0), 4.6],       # 연못(수면 r2.5) + 낚시 프롬프트 지점(10,3.8)
	[Vector2(-5, -5), 2.2],      # 상점 카운터 (프롬프트)
	[Vector2(9.5, 7), 2.0],      # 판매 상자 (프롬프트)
	[Vector2(3, 18.3), 2.6],     # 플레이어 집 문 트리거 (Interior.OUT_DOOR)
	[Vector2(3, 20.6), 2.6],     # 집에서 나오는 자리 (Interior.OUT_SPAWN)
	[Vector2(29, -24), 4.0],     # 풍차 대지
	[Vector2(29, -18.5), 4.0],   # 풍차 램프
]
# 건물 footprint + 0.6 패드 [중심, 반폭x, 반폭z]
const BUILDINGS := [
	[Vector2(0, -18), 3.6, 3.1], [Vector2(-20, -14), 2.6, 2.6], [Vector2(-24, 2), 2.6, 2.6],
	[Vector2(-14, 22), 2.6, 2.6], [Vector2(24, 20), 2.6, 2.6], [Vector2(-7, -7), 2.1, 2.1],
	[Vector2(3, 15), 3.1, 3.1], [Vector2(-26, 14), 2.6, 2.6],
]
const FARM := Rect2(-0.8, 1.2, 9.6, 5.6)          # 밭 타일 x[0,8] z[2,6] + 0.8 (farm_system.REGION)
const CAM_LANE := Rect2(-2.0, -4.5, 4.0, 12.0)    # 스샷 카메라(플레이어 +z9.5)와 광장 사이 시선
const BEACH_LANE := Rect2(20.0, 21.0, 8.0, 20.0)  # 해변 접근로 + 게이트(24,32.5)·스폰(24,29.4)
const ROAD_KEEP := 1.9      # 길 중심선(폭 2.4)에서 비우는 거리
const RIVER_KEEP := 3.0     # 강 중심선 (npc_system RIVER_AVOID 2.9와 정합)
const BRIDGE_KEEP := 4.5    # 다리 데크 + 진입로

# 식생 전용 추가 금지(기능이 아니라 그림 문제 — NPC가 꽃밭에 서 있지 않게)
const NPC_ANCHORS := [  # npc_system.ANCHORS
	Vector2(-4.5, 3.5), Vector2(-3.5, -3.5), Vector2(12, -3.5),
	Vector2(13, 6.2), Vector2(27, -12), Vector2(3, 10.5),
]
const NPC_HOMES := [  # data/npcs.json home 9곳
	Vector2(-20, -9), Vector2(22, 17), Vector2(-19, 20), Vector2(-6, 19), Vector2(-24, -3),
	Vector2(-15, -11), Vector2(-8, 6), Vector2(-8, -4), Vector2(-22, 10),
]
const ANCHOR_KEEP := 3.6    # ANCHOR_R_MAX 3.0 + 여유
const HOME_KEEP := 4.5      # 집 앞 정지·배회 중심
const PLAZA_R := 6.4        # 광장 판석 위엔 식생 금지(판석이 보여야 한다)
# 종별 배율 [최소, 최대] — 원본 높이가 제각각이라 한 배율로 묶으면 풀포기가 갈대가 된다(실측).
const FLORA_SCALE := {
	"flower_yellowA": Vector2(2.4, 3.4),   # 원본 0.19 → 0.46~0.65
	"flower_purpleA": Vector2(2.4, 3.4),   # 원본 0.24 → 0.58~0.82
	"plant_bushSmall": Vector2(2.0, 3.0),  # 원본 0.21 → 0.42~0.63
	"grass": Vector2(1.3, 2.0),            # 원본 0.25 → 0.33~0.50 (꽃보다 낮게)
}
const WALK_HALF := 33.0     # 초지 스프링클 범위(숲 띠 안쪽)

# ── 소품 배치표 [종류, x, z, yaw(도)] ────────────────────────────────
# 광장 각도는 방사 6갈래 길 사이 빈 구간을 골랐다(빌드 로그가 위반을 잡는다).
const PROPS := [
	# 가로등 — 광장 림 4(길·축제링·카메라 시선 사이 빈 구간) + 길목 4
	["lamp", 5.38, -1.54, 0], ["lamp", -5.35, -0.75, 0],
	["lamp", -3.98, 3.34, 0], ["lamp", 4.13, -6.61, 0],
	["lamp", 13.43, 3.15, 0],   # 동 다리 진입로
	["lamp", -9.50, -4.25, 0],  # 상점 앞
	["lamp", 6.60, 12.60, 0],   # 플레이어 집 가는 남길
	["lamp", 2.60, -14.60, 0],  # 회관 앞
	# 벤치 — 광장 2(분수 향) + 강변 1(다리 향) + 정자 양옆 2
	["bench", 4.30, 0.91, -102], ["bench", -3.21, -3.57, 42],
	["bench", 12.40, 8.60, 109], ["bench", -29.20, 14.00, 90], ["bench", -22.80, 14.00, -90],
	# 표지판 — 길목(판면이 광장을 향하도록 yaw)
	["sign", 6.89, -3.66, -62], ["sign", -7.42, -2.41, 72],
	["sign", 3.40, -9.00, -21], ["sign", -3.80, 9.60, 158],
	# 화분 — 상점 앞 1 + 집 앞 2 + 회관 앞 1
	["planter", -4.60, -9.60, 0], ["planter", 0.20, 18.20, 0],
	["planter", 5.80, 18.20, 0], ["planter", -2.60, -14.60, 0],
	# 꽃수레 — 상점 앞
	["cart", -8.20, -9.15, 25],
]
# 나무 울타리 [시작, 끝] — 막힌 구간의 기둥은 건너뛴다(그 자리가 자연스러운 출입구가 된다)
const FENCES = [
	[Vector2(3.4, 7.2), Vector2(8.6, 7.2)],       # 밭 남쪽(길·판매상자 비켜)
	[Vector2(-0.2, 12.8), Vector2(-0.2, 17.6)],   # 플레이어 집 앞마당 서
	[Vector2(6.4, 13.0), Vector2(6.4, 17.6)],     # 플레이어 집 앞마당 동
	[Vector2(2.3, -8.5), Vector2(2.3, -14.5)],    # 회관 북길 동측
	[Vector2(-2.3, -8.5), Vector2(-2.3, -14.5)],  # 회관 북길 서측
	[Vector2(11.4, 9.6), Vector2(11.4, 14.4)],    # 동 다리 남측 강변 난간
	[Vector2(14.6, 3.6), Vector2(14.6, 0.0)],     # 동 다리 북측 강변 난간
	[Vector2(13.79, -13.86), Vector2(18.05, -16.85)],  # 북동 다리 진입부
	[Vector2(-29.4, 10.6), Vector2(-22.6, 10.6)], # 정자 마당 북
	[Vector2(-29.4, 17.4), Vector2(-22.6, 17.4)], # 정자 마당 남
]
const FENCE_S := 2.6        # fence_simple 원본 1.0 → 높이 0.35×2.6 = 0.91 (캐릭터 2.1의 절반)

# ── 가로등 (밤에만 점등 — interior.gd 전례: DayNight.sample의 태양 에너지에서 파생) ──
const LAMP_E := 1.1
const LAMP_RANGE := 8.0

var _cache := {}                       # glb 이름 → 원본 노드(반복 로드 방지)
var _lights: Array[OmniLight3D] = []
var _blooms: Array[Node3D] = []        # 겨울에 숨길 만개 노드(화분·꽃수레 꽃, 등나무 드레이프 루트)
var _tree_mesh := {}                   # 활엽수 MMI 이름 → [원색 Mesh, 겨울 수관 서리 Mesh]
var _unknown_mats := {}                # 팔레트에 없는 킷 머티리얼 이름(로그용)
# 검증 전용: 탑다운 도식용 좌표 수집 (headless는 MultiMesh 버퍼를 되읽지 못해 원본을 따로 남긴다)
var _dumping := "decordump" in OS.get_cmdline_user_args()
var _mm_pts := {}
var _n_props := 0
var _n_flora := 0
var _n_trees := 0

# world.gd가 _build_village 안에서(= _convert_statics 이전에) 호출한다.
# 강·다리·길 좌표는 world.gd에서 인자로 받는다(양방향 preload = 순환 참조 방지).
var _river: Array[Vector2] = []
var _bridges: Array[Vector2] = []
var _roads: Array = []  # [Vector2 a, Vector2 b]

func build(river_pts: Array, bridges: Array, roads: Array) -> void:
	add_to_group("decor")  # world.gd _apply_season이 계절 전환·로드 때 호출
	for p in river_pts:
		_river.append(p)
	for b in bridges:
		_bridges.append(b)
	for r in roads:  # [중심, 길이(로컬+Z), y회전(도)] → 선분 양 끝점
		var d := Vector2(sin(deg_to_rad(r[2])), cos(deg_to_rad(r[2]))) * (float(r[1]) * 0.5)
		_roads.append([r[0] - d, r[0] + d])
	_roads.append([Vector2(24, 23.0), Vector2(24, 34.0)])  # beach.gd _village_path 흙길

	_place_props()
	_place_fences()
	_place_flora()
	_place_forest()
	_wisteria()
	_audit()

# ══ 에셋 로드 ══════════════════════════════════════════════════════
func _glb(nm: String) -> Node3D:
	if not _cache.has(nm):
		var n := ToonChar.load_glb(DIR + nm + ".glb", OUTLINE)
		if n == null:
			return null
		_strip_collision(n)   # MUST-FIX 1: 킷엔 없지만 방어적으로 먼저 벗긴다
		_repaint(n)
		_cache[nm] = n
	return (_cache[nm] as Node3D).duplicate() as Node3D

# MultiMesh용 Mesh: 인스턴스별 surface override가 없으므로 머티리얼을 Mesh에 박는다.
# 캐시를 우회해 새로 로드 = 개별 노드가 쓰는 Mesh 리소스를 공유 변형하지 않는다(Codex MUST-FIX).
# swap = 팔레트 위에 덧씌울 {킷 머티리얼 이름: 색} — 계절 사본(겨울 수관)을 별도 Mesh로 뽑는 데 쓴다.
func _mm_mesh(nm: String, swap := {}) -> Mesh:
	var n := ToonChar.load_glb(DIR + nm + ".glb", OUTLINE)
	if n == null:
		return null
	_repaint(n, swap)
	var mi := _first_mesh(n)
	if mi == null:
		n.free()
		return null
	var mesh := mi.mesh as ArrayMesh
	if mesh == null:
		n.free()
		return null
	for i in mesh.get_surface_count():
		mesh.surface_set_material(i, mi.get_surface_override_material(i))
	n.free()  # Mesh는 RefCounted라 여기 참조로 살아 있다
	return mesh

func _first_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		return node as MeshInstance3D
	for c in node.get_children():
		var m := _first_mesh(c)
		if m != null:
			return m
	return null

# 킷 원본색 → 마을 팔레트. ToonChar.apply가 깔아둔 toon 머티리얼의 albedo만 바꾼다.
func _repaint(node: Node, swap := {}) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mi := node as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			var mat_name := "" if src == null else src.resource_name
			var m := mi.get_surface_override_material(i) as ShaderMaterial
			if m == null:
				continue
			if MAT_COLORS.has(mat_name):
				m.set_shader_parameter("albedo", swap.get(mat_name, MAT_COLORS[mat_name]))
			else:
				_unknown_mats[mat_name] = true
	for c in node.get_children():
		_repaint(c, swap)

# MUST-FIX 1: 데코에 충돌체가 섞이면 통행 계약이 깨진다 — 즉시 free(큐 대기 아님, 감사에서 세지지 않게).
func _strip_collision(node: Node) -> void:
	for c in node.get_children():
		if c is CollisionObject3D or c is CollisionShape3D:
			node.remove_child(c)
			c.free()
		else:
			_strip_collision(c)

# ══ 금지 존 판정 ════════════════════════════════════════════════════
# 기능 침범 금지 — 소품·꽃·나무 공통. river_keep은 강가 바위처럼 물가에 붙어야 하는 것만 낮춘다.
func _blocked(p: Vector2, river_keep := RIVER_KEEP) -> bool:
	for c in NO_DECOR_CIRCLES:
		if p.distance_to(c[0]) < c[1]:
			return true
	for b in BUILDINGS:
		if absf(p.x - b[0].x) < b[1] and absf(p.y - b[0].y) < b[2]:
			return true
	if FARM.has_point(p) or CAM_LANE.has_point(p) or BEACH_LANE.has_point(p):
		return true
	for r in _roads:
		if _seg_dist(p, r[0], r[1]) < ROAD_KEEP:
			return true
	for br in _bridges:
		if p.distance_to(br) < BRIDGE_KEEP:
			return true
	return _river_dist(p) < river_keep

# 식생 추가 금지 — 판석 위/NPC가 서 있는 자리엔 꽃을 심지 않는다.
func _blocked_flora(p: Vector2) -> bool:
	if _blocked(p) or p.length() < PLAZA_R:
		return true
	for a in NPC_ANCHORS:
		if p.distance_to(a) < ANCHOR_KEEP:
			return true
	for h in NPC_HOMES:
		if p.distance_to(h) < HOME_KEEP:
			return true
	return false

func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 0.0001:
		return p.distance_to(a)
	return p.distance_to(a + ab * clampf((p - a).dot(ab) / l2, 0.0, 1.0))

func _river_dist(p: Vector2) -> float:
	var best := INF
	for i in _river.size() - 1:
		best = minf(best, _seg_dist(p, _river[i], _river[i + 1]))
	return best

# ══ 절차 지오메트리 (world.gd _box/_cyl와 같은 결) ═════════════════
func _box(parent: Node, center: Vector3, size: Vector3, color: Color, outline := OUTLINE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = ToonChar.make_solid(color, outline)
	mi.position = center
	parent.add_child(mi)
	return mi

func _cyl(parent: Node, center: Vector3, radius: float, height: float, color: Color, outline := OUTLINE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	mi.mesh = cm
	mi.material_override = ToonChar.make_solid(color, outline)
	mi.position = center
	parent.add_child(mi)
	return mi

# ══ 소품 ═══════════════════════════════════════════════════════════
func _place_props() -> void:
	var root := Node3D.new()
	root.name = "Props"
	add_child(root)
	for p in PROPS:
		var at := Vector2(p[1], p[2])
		if _blocked(at):
			push_warning("decor: 소품 %s (%.1f, %.1f) 금지 존 — 배치 생략" % [p[0], at.x, at.y])
			continue
		var n := Node3D.new()
		n.position = Vector3(at.x, GROUND_Y, at.y)
		n.rotation.y = deg_to_rad(p[3])
		root.add_child(n)
		n.name = p[0]  # 탑다운 도식(decordump)이 종류를 읽는 이름 (Godot이 lamp/lamp2… 로 유일화)
		match p[0]:
			"lamp": _lamp(n)
			"bench": _bench(n)
			"sign": _sign(n)
			"planter": _planter(n)
			"cart": _cart(n)
		_n_props += 1

# 가로등: 석재 받침 + 목재 기둥 + 크림 등갓 + 보라 갓지붕. 밤에만 켜지는 OmniLight 1개.
func _lamp(p: Node3D) -> void:
	_cyl(p, Vector3(0, 0.12, 0), 0.26, 0.24, C_STONE)
	_cyl(p, Vector3(0, 1.5, 0), 0.09, 2.6, C_WOOD, 0.004)
	_box(p, Vector3(0, 3.02, 0), Vector3(0.42, 0.5, 0.42), C_GLASS, 0.004)
	_box(p, Vector3(0, 3.34, 0), Vector3(0.56, 0.14, 0.56), C_ROOF, 0.004)
	var o := OmniLight3D.new()
	o.position = Vector3(0, 3.0, 0)
	o.light_color = Color(1.0, 0.86, 0.62)
	o.omni_range = LAMP_RANGE
	o.light_energy = 0.0
	p.add_child(o)
	_lights.append(o)

# 벤치: 등받이 있는 목재 벤치(로컬 -z가 등받이 = yaw로 정면을 정한다)
func _bench(p: Node3D) -> void:
	_box(p, Vector3(0, 0.56, 0), Vector3(1.7, 0.12, 0.52), C_WOOD, 0.004)
	_box(p, Vector3(0, 0.9, -0.24), Vector3(1.7, 0.56, 0.1), C_WOOD, 0.004)
	for s in [-1.0, 1.0]:
		_box(p, Vector3(0.7 * s, 0.28, 0), Vector3(0.12, 0.56, 0.46), C_WOOD_D, 0.004)

func _sign(p: Node3D) -> void:
	var n := _glb("sign")
	if n == null:
		return
	n.scale = Vector3.ONE * 3.6
	p.add_child(n)

# 화분: 목재 통 + 흙 + 꽃 3송이
func _planter(p: Node3D) -> void:
	_box(p, Vector3(0, 0.26, 0), Vector3(0.88, 0.52, 0.88), C_WOOD, 0.004)
	_box(p, Vector3(0, 0.54, 0), Vector3(0.7, 0.06, 0.7), C_WOOD_D, 0.0)
	var kinds := ["flower_yellowA", "flower_purpleA", "flower_yellowA"]
	for i in 3:
		var f := _glb(kinds[i])
		if f == null:
			continue
		var a := TAU * i / 3.0
		f.position = Vector3(cos(a) * 0.2, 0.56, sin(a) * 0.2)
		f.scale = Vector3.ONE * 2.6
		f.rotation.y = a
		p.add_child(f)
		_blooms.append(f)  # 겨울엔 빈 화분만 남는다

# 꽃수레: 목재 짐칸 + 바퀴 2 + 꽃 무더기 (상점 앞 생활감)
func _cart(p: Node3D) -> void:
	_box(p, Vector3(0, 0.72, 0), Vector3(1.5, 0.44, 0.9), C_WOOD, 0.004)
	_box(p, Vector3(0, 0.5, 0), Vector3(1.2, 0.16, 0.7), C_WOOD_D, 0.004)
	_box(p, Vector3(1.05, 0.55, 0), Vector3(0.7, 0.09, 0.09), C_WOOD_D, 0.0)  # 손잡이
	for s in [-1.0, 1.0]:
		var w := _cyl(p, Vector3(0, 0.38, 0.5 * s), 0.36, 0.1, C_WOOD_D, 0.004)
		w.rotation.x = PI * 0.5
	for i in 5:
		var f := _glb("flower_yellowA" if i % 2 == 0 else "flower_purpleA")
		if f == null:
			continue
		f.position = Vector3(-0.5 + i * 0.25, 0.94, (i % 2) * 0.3 - 0.15)
		f.scale = Vector3.ONE * 2.8
		f.rotation.y = i * 1.1
		p.add_child(f)
		_blooms.append(f)  # 겨울엔 빈 수레만 남는다

# ══ 울타리 ═════════════════════════════════════════════════════════
func _place_fences() -> void:
	var root := Node3D.new()
	root.name = "Fences"
	add_child(root)
	for run in FENCES:
		var a: Vector2 = run[0]
		var b: Vector2 = run[1]
		var span := (b - a).length()
		var n := maxi(1, int(round(span / FENCE_S)))
		var dir := (b - a) / float(n)
		for k in n:
			var c: Vector2 = a + dir * (k + 0.5)
			if _blocked(c):
				continue  # 길·다리가 지나가는 자리는 비운다 = 출입구
			var seg := _glb("fence_simple")
			if seg == null:
				return
			seg.position = Vector3(c.x, GROUND_Y, c.y)
			seg.rotation.y = atan2(-dir.y, dir.x)  # 조각 장축 = 로컬 +X
			seg.scale = Vector3.ONE * FENCE_S
			root.add_child(seg)
			_n_props += 1

# ══ 꽃 덤불 식생 (MultiMesh만) ═════════════════════════════════════
# 존: ① 길가 띠 ② 광장 둘레 화단 ③ 강변 양안 ④ 초지 옅은 스프링클(민짜 초록 방지).
func _place_flora() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260731
	var buckets := {"flower_yellowA": [], "flower_purpleA": [], "plant_bushSmall": [], "grass": []}

	# ① 길가 띠 — 길 중심선에서 2.3~4.2 벗어난 양쪽
	for r in _roads:
		var a: Vector2 = r[0]
		var b: Vector2 = r[1]
		var span := (b - a).length()
		var dir := (b - a) / maxf(span, 0.01)
		var perp := Vector2(-dir.y, dir.x)
		for k in int(span / 2.6):
			for s in [1.0, -1.0]:
				if rng.randf() < 0.28:
					continue
				var c: Vector2 = a + dir * ((k + rng.randf()) * 2.6) + perp * (s * rng.randf_range(2.3, 4.2))
				_add_flora(buckets, c, rng, ["flower_yellowA", "flower_yellowA", "flower_purpleA", "flower_purpleA", "plant_bushSmall", "grass"])

	# ② 광장 둘레 화단 — 판석 바깥 링(방사길 사이 구간만 남는다)
	for _i in 220:
		var ang := rng.randf() * TAU
		var rad := rng.randf_range(6.6, 9.6)
		_add_flora(buckets, Vector2(cos(ang), sin(ang)) * rad, rng,
			["flower_yellowA", "flower_purpleA", "flower_purpleA", "plant_bushSmall"])

	# ③ 강변 양안 — 물폭3 + 강둑 바깥
	for i in _river.size() - 1:
		var a: Vector2 = _river[i]
		var b: Vector2 = _river[i + 1]
		var span := (b - a).length()
		var dir := (b - a) / maxf(span, 0.01)
		var perp := Vector2(-dir.y, dir.x)
		for k in int(span / 3.0):
			for s in [1.0, -1.0]:
				if rng.randf() < 0.30:
					continue
				var c: Vector2 = a + dir * ((k + rng.randf()) * 3.0) + perp * (s * rng.randf_range(3.2, 5.2))
				_add_flora(buckets, c, rng, ["flower_purpleA", "flower_purpleA", "flower_yellowA", "grass", "plant_bushSmall"])

	# ④ 초지 스프링클 — 풀포기·덤불만 옅게(꽃은 위 세 존에서만)
	for _i in 190:
		var c := Vector2(rng.randf_range(-WALK_HALF, WALK_HALF), rng.randf_range(-WALK_HALF, WALK_HALF))
		_add_flora(buckets, c, rng, ["grass", "grass", "grass", "plant_bushSmall"])

	for nm in buckets:
		if (buckets[nm] as Array).is_empty():
			continue
		_multimesh(_mm_mesh(nm), buckets[nm], "Flora_" + nm)
		_n_flora += (buckets[nm] as Array).size()

# 한 자리에 3~6포기를 뭉쳐 심는다 — 낱개로 흩뿌리면 "잡초 노이즈"로 보이고 화단으로 안 읽힌다.
func _add_flora(buckets: Dictionary, at: Vector2, rng: RandomNumberGenerator, kinds: Array) -> void:
	if _blocked_flora(at):
		return
	for _i in rng.randi_range(3, 6):
		var p := at + Vector2(rng.randf_range(-0.9, 0.9), rng.randf_range(-0.9, 0.9))
		if _blocked_flora(p):
			continue
		var nm: String = kinds[rng.randi() % kinds.size()]
		var sc: Vector2 = FLORA_SCALE[nm]
		var t := Transform3D()
		t = t.scaled(Vector3.ONE * rng.randf_range(sc.x, sc.y))
		t = t.rotated(Vector3.UP, rng.randf() * TAU)
		t.origin = Vector3(p.x, GROUND_Y, p.y)
		(buckets[nm] as Array).append(t)

# ══ 겨울 식생 (계절 파생 — 저장 없음, transform 재빌드 없음) ═══════
# 꽃(개나리·라벤더)은 겨울에 숨긴다: 눈 지면 위에 만개한 꽃이 계절 감각을 통째로 깬다.
# 풀·덤불은 숨기는 대신 서리톤으로 남긴다 — 통째로 지우면 마을이 민짜 눈판이 되고
# 길가 띠·광장 화단 링·강변의 밀도와 실루엣이 같이 사라진다(꽃만 빼도 계절은 읽힌다).
# 침엽수는 겨울에도 초록 — 눈 마을의 실루엣을 지고 있는 건 이쪽이다. 활엽수는 수관만 서리톤으로
# 내린다(줄기는 원색): 겨울 설원에 초록 수관이 떠 있으면 계절이 통째로 안 읽힌다(실측).
const WINTER := 3
const FLORA_HIDE_WINTER := ["Flora_flower_yellowA", "Flora_flower_purpleA"]
const DECIDUOUS := ["Forest_blob_wide", "Forest_blob_round"]  # 절차 블롭 나무 중 활엽 버킷

static func flora_visible(nm: String, season: int) -> bool:
	return not (season == WINTER and nm in FLORA_HIDE_WINTER)

static func flora_frosted(nm: String, season: int) -> bool:
	return season == WINTER and nm.begins_with("Flora_") and flora_visible(nm, season)

static func tree_frosted(nm: String, season: int) -> bool:
	return season == WINTER and nm in DECIDUOUS

# 만개한 꽃(화분·꽃수레의 개별 꽃 GLB, 등나무 드레이프)은 겨울에 숨긴다. 서리톤으로 남기지 않는
# 이유: 꽃(Flora_flower_*)이 이미 겨울 숨김이라 규칙이 하나로 통일되고, 회색으로 물든 만개 송이는
# 눈 위에 매달린 이물처럼 보인다. 빈 화분·빈 수레·맨 퍼걸러가 겨울 그림으로 맞다.
static func bloom_visible(season: int) -> bool:
	return season != WINTER

# world.gd _apply_season이 계절 전환 신호 + 로드 직후에 부른다(축제 evaluate와 같은 규약).
func apply_season(sea: int) -> void:
	for c in get_children():
		var mmi := c as MultiMeshInstance3D
		if mmi == null:
			continue
		var nm := String(mmi.name)
		if _tree_mesh.has(nm):  # 활엽수: transform 버퍼는 그대로 두고 Mesh만 갈아 끼운다
			mmi.multimesh.mesh = _tree_mesh[nm][1 if tree_frosted(nm, sea) else 0]
			continue
		if not nm.begins_with("Flora_"):
			continue
		mmi.visible = flora_visible(nm, sea)
		# 색은 MultiMeshInstance3D의 material_override로만 바꾼다. MultiMesh의 Mesh 표면
		# 머티리얼을 고쳐 쓰면 같은 GLB를 쓰는 개별 소품(화분 꽃·꽃수레)과 리소스를 공유할
		# 위험 + 원색 복구용 백업 보관까지 딸려온다. override는 null로 지우면 원색이 돌아온다.
		mmi.material_override = ToonChar.make_solid(C_FROST, OUTLINE) if flora_frosted(nm, sea) else null
	for b in _blooms:
		b.visible = bloom_visible(sea)

# ══ 절차 블롭 나무 ═════════════════════════════════════════════════
# 각진 로우폴리 수관 대신 둥근 뭉게 수관. 겹친 구 여러 개가 아니라 **로브로 부풀린 단일 폐곡면** —
# 구를 겹치면 inverted-hull 외곽선이 교차 곡선을 따라 내부 헤일로를 그린다(Codex MUST-FIX 5).
# 줄기는 별도 표면(별도 색)이지만 수관 안에 완전히 잠겨 있어 헐이 밖으로 새지 않는다.
# 파라미터 [수관 반경, 수관 y중심, y스쿼시, 상단 테이퍼(1=구/0.25=침엽), 줄기 반경, 줄기 높이, 로브 세기]
const BLOB_KINDS := {
	"blob_wide":  [0.44, 0.62, 0.72, 0.92, 0.085, 0.38, 0.22],  # 낮고 넓은 활엽 (동숲 비율)
	"blob_round": [0.36, 0.78, 0.94, 0.86, 0.070, 0.50, 0.26],  # 동글동글한 활엽
	"cone_tall":  [0.38, 0.74, 1.50, 0.30, 0.078, 0.28, 0.15],  # 부드러운 원뿔 침엽
	"cone_slim":  [0.32, 0.66, 1.70, 0.24, 0.066, 0.24, 0.13],  # 가는 침엽
}
const CONIFER := ["cone_tall", "cone_slim"]
# 로브 방향 — 수관을 몇 방향으로만 부풀려 완벽한 구가 아닌 뭉게구름 실루엣을 만든다.
const LOBES := [Vector3(1, 0.3, 0.4), Vector3(-0.8, 0.15, 0.6), Vector3(0.25, 0.55, -1), Vector3(-0.45, -0.15, -0.85)]

func _blob_mesh(k: Array, leaf: Color) -> ArrayMesh:
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 22
	sm.rings = 12
	var a := sm.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	for i in v.size():
		var n := v[i].normalized()
		var bulge := 1.0
		for d in LOBES:
			bulge += float(k[6]) * pow(maxf(n.dot((d as Vector3).normalized()), 0.0), 2.0)
		var t := (n.y + 1.0) * 0.5                    # 0=아래 1=위
		var taper: float = lerpf(1.0, float(k[3]), t * t)  # 위로 갈수록 좁아진다
		v[i] = Vector3(n.x * taper, n.y * float(k[2]), n.z * taper) * (bulge * float(k[0]))
		v[i].y += float(k[1])
	var tmp := ArrayMesh.new()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_INDEX] = a[Mesh.ARRAY_INDEX]
	tmp.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	# 정점을 옮겼으니 법선을 다시 만든다 — 인덱스 메시라 스무스 셰이딩(각진 면이 안 남는다).
	var st := SurfaceTool.new()
	st.create_from(tmp, 0)
	st.generate_normals()
	var out := st.commit() as ArrayMesh
	# 통통한 줄기(아래가 넓은 원통). 수관 밑동에 파묻히게 배치.
	var cm := CylinderMesh.new()
	cm.top_radius = float(k[4]) * 0.8
	cm.bottom_radius = float(k[4]) * 1.35
	cm.height = float(k[5])
	cm.radial_segments = 12
	cm.rings = 1
	var ca := cm.surface_get_arrays(0)
	var cv: PackedVector3Array = ca[Mesh.ARRAY_VERTEX]
	for i in cv.size():
		cv[i].y += float(k[5]) * 0.5
	ca[Mesh.ARRAY_VERTEX] = cv
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ca)
	out.surface_set_material(0, ToonChar.make_solid(leaf, OUTLINE))
	out.surface_set_material(1, ToonChar.make_solid(C_WOOD, OUTLINE))
	return out

# ══ 숲 띠 (경계 |x| 또는 |z| ∈ [34,40] 저밀도, 절차 블롭 MultiMesh) ══
func _place_forest() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260724  # 컬러박스와 같은 시드 = 띠 실루엣 연속성
	var kinds := BLOB_KINDS.keys()
	var buckets := {}
	for k in kinds:
		buckets[k] = []
	for edge in 4:  # 0=북(-z) 1=남(+z) 2=서(-x) 3=동(+x)
		for _i in 26:  # 띠 한 변당 — 이보다 낮으면 곡률에 가려 '숲 띠'로 안 읽힌다(실측)
			var along := rng.randf_range(-39.0, 39.0)
			var band := rng.randf_range(33.5, 39.5)
			var pos: Vector2
			match edge:
				0: pos = Vector2(along, -band)
				1: pos = Vector2(along, band)
				2: pos = Vector2(-band, along)
				_: pos = Vector2(band, along)
			if _blocked(pos):
				continue
			var nm: String = kinds[rng.randi() % kinds.size()]
			var t := Transform3D()
			t = t.scaled(Vector3.ONE * rng.randf_range(2.7, 4.0))
			t = t.rotated(Vector3.UP, rng.randf() * TAU)
			t.origin = Vector3(pos.x, GROUND_Y, pos.y)
			(buckets[nm] as Array).append(t)
	for nm in buckets:
		if (buckets[nm] as Array).is_empty():
			continue
		var full: String = "Forest_" + nm
		var kp: Array = BLOB_KINDS[nm]
		var summer := _blob_mesh(kp, C_CONIF if nm in CONIFER else C_LEAF)
		_multimesh(summer, buckets[nm], full)
		_n_trees += (buckets[nm] as Array).size()
		if tree_frosted(full, WINTER):
			# 겨울용 사본을 빌드 때 미리 뽑아 둔다. MultiMeshInstance3D엔 표면별 override가 없어
			# material_override로 물들이면 줄기까지 서리색이 된다 — 수관 색만 바꾼 Mesh를 스왑한다.
			_tree_mesh[full] = [summer, _blob_mesh(kp, C_FROST_LEAF)]

	# 강변 바위 몇 개 — 물길이 지형에 박혀 보이게(개별 노드, 무충돌)
	var rocks := Node3D.new()
	rocks.name = "Rocks"
	add_child(rocks)
	for i in _river.size() - 1:
		for s in [1.0, -1.0]:
			var a: Vector2 = _river[i]
			var b: Vector2 = _river[i + 1]
			var dir := (b - a).normalized()
			var c: Vector2 = a + (b - a) * rng.randf_range(0.25, 0.75) + Vector2(-dir.y, dir.x) * (s * rng.randf_range(2.6, 3.4))
			if _blocked(c, 2.4):
				continue  # 강가엔 붙이되(river_keep 2.4) 물 위·다른 금지 존은 제외
			var r := _glb("rock_smallA" if (i + int(s)) % 2 == 0 else "rock_smallB")
			if r == null:
				continue
			r.position = Vector3(c.x, GROUND_Y, c.y)
			r.scale = Vector3.ONE * rng.randf_range(2.2, 3.8)
			r.rotation.y = rng.randf() * TAU
			rocks.add_child(r)
			_n_props += 1

# ══ 등나무(보라) 처마 — 퍼걸러·회관 파사드·다리 난간 (VILLAGE_SPEC §3) ══
func _wisteria() -> void:
	var root := Node3D.new()
	root.name = "Wisteria"
	add_child(root)
	_blooms.append(root)  # 등나무는 낙엽성 — 겨울엔 퍼걸러·난간 골조만 남는다
	# 정자 퍼걸러(-26,14): 지붕 4.2각(y2.7~3.05) 가장자리에서 늘어뜨린다
	for i in 14:
		var t := i / 14.0 * TAU
		var e := Vector2(cos(t), sin(t))
		var m := maxf(absf(e.x), absf(e.y))
		var p := Vector2(-26, 14) + e / m * 2.0
		_drape(root, Vector3(p.x, 2.55, p.y), 0.5 + fmod(i * 0.37, 0.5))
	# 회관 파사드(0,-18): 남면 처마 아래(z=-15.6)
	for i in 7:
		_drape(root, Vector3(-2.55 + i * 0.85, 4.62, -15.30), 0.7 + fmod(i * 0.41, 0.8))
	# 다리 난간 포인트 — 데크는 강을 가로지르므로 흐름 수직(perp)이 난간 장축이다(world.gd _arch_bridge와 동일식)
	for br in _bridges:
		var ang := _river_dir_at(br)
		var flow := Vector2(sin(ang), cos(ang))
		var perp := Vector2(cos(ang), -sin(ang))
		for fs in [-1.0, 1.0]:
			for ps in [-1.0, 1.0]:
				var q: Vector2 = br + flow * (1.5 * fs) + perp * (2.2 * ps)
				# 1.10 = 풀 아치 데크 갓돌 상단 = world.gd deck_top(2.2) + 0.40
				#      = (DECK_CROWN 1.30 − (DECK_ARC_R 4.35 − √(4.35² − 2.2²))) + 0.40 = 0.703 + 0.40.
				# world.gd가 decor.gd를 preload하므로 역방향 preload는 순환 — 파생식을 주석으로
				# 남기고 상수로 박는다. 어긋나면 test_core의 deck_top 핀이 잡는다.
				_drape(root, Vector3(q.x, 1.10, q.y), 0.45)

# 점 p에서 가장 가까운 강 세그먼트의 흐름 방향(y회전각) — world.gd _river_dir_at와 같은 식.
func _river_dir_at(p: Vector2) -> float:
	var best := 0.0
	var best_d := INF
	for i in _river.size() - 1:
		var d := _seg_dist(p, _river[i], _river[i + 1])
		if d < best_d:
			best_d = d
			best = atan2(_river[i + 1].x - _river[i].x, _river[i + 1].y - _river[i].y)
	return best

# 등나무 송이: 아래로 가늘어지는 보라 2단 (간단 메시 — 발주서 허용)
func _drape(parent: Node, at: Vector3, drop: float) -> void:
	_box(parent, at + Vector3(0, -drop * 0.3, 0), Vector3(0.22, drop * 0.6, 0.22), C_WIST, 0.004)
	_box(parent, at + Vector3(0, -drop * 0.78, 0), Vector3(0.13, drop * 0.42, 0.13), C_LILAC, 0.004)

# ══ 공통 ═══════════════════════════════════════════════════════════
func _multimesh(mesh: Mesh, xforms: Array, nm: String) -> void:
	if mesh == null:
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	if _dumping:
		var pts := PackedVector2Array()
		for t in xforms:
			pts.append(Vector2((t as Transform3D).origin.x, (t as Transform3D).origin.z))
		_mm_pts[nm] = pts
	var mmi := MultiMeshInstance3D.new()
	mmi.name = nm
	mmi.multimesh = mm
	add_child(mmi)

# MUST-FIX 1: 데코 루트 아래 충돌체가 하나도 없음을 런타임 로그로 증명한다.
func _audit() -> void:
	var bodies := _count_collision(self)
	print("decor: props=%d flora=%d trees=%d lights=%d collision_bodies=%d"
		% [_n_props, _n_flora, _n_trees, _lights.size(), bodies])
	if bodies > 0:
		push_error("decor: 충돌체 %d개가 데코 트리에 남았다 — 통행 계약 위반" % bodies)
	if not _unknown_mats.is_empty():
		print("decor: 팔레트 미지정 머티리얼 ", _unknown_mats.keys())
	if _dumping:  # 탑다운 도식 대조용 좌표 덤프(검증 전용)
		_dump()

# 배치 좌표를 한 줄 JSON으로 뱉는다 — PIL 도식 스크립트가 stdout에서 파싱한다.
func _dump() -> void:
	var out := {"props": [], "mm": {}}
	for group in ["Props", "Fences", "Rocks"]:
		var g := get_node_or_null(group)
		if g == null:
			continue
		for c in g.get_children():
			var kind: String = String(c.name).rstrip("0123456789") if group == "Props" else String(group).to_lower()
			out["props"].append([snappedf((c as Node3D).position.x, 0.01), snappedf((c as Node3D).position.z, 0.01), kind])
	for nm in _mm_pts:
		var pts := []
		for v in (_mm_pts[nm] as PackedVector2Array):
			pts.append([snappedf(v.x, 0.01), snappedf(v.y, 0.01)])
		out["mm"][nm] = pts
	print("DECOR_DUMP ", JSON.stringify(out))

func _count_collision(node: Node) -> int:
	var n := 0
	if (node is CollisionObject3D or node is CollisionShape3D) and not node.is_queued_for_deletion():
		n += 1
	for c in node.get_children():
		n += _count_collision(c)
	return n

# 가로등 점등: 실내등(interior.gd)과 같은 방식 — 태양 에너지가 떨어지면 켜진다.
func _process(_dt: float) -> void:
	if _lights.is_empty():
		return
	var sun_e: float = DayNight.sample(GameClock.game_min / 60.0)["sun_e"]
	var e: float = LAMP_E * (1.0 - smoothstep(0.25, 0.9, sun_e))
	for o in _lights:
		o.light_energy = e

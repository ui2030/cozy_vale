extends Node3D
# 플레이어 집 실내 (G단계). 같은 월드의 격리 좌표 (120,120) — 씬 전환 없음 = 시계·세이브·
# 오토로드·NPC 시스템이 전부 그대로 돈다. 문(Area3D group "door")으로 좌표 텔레포트만 한다.
#
# 지붕 없는 오픈탑 + 남(카메라 쪽) 벽 생략: 추종 카메라가 뒤(+Z)·위에서 ~29° 하향이라
# 지붕이나 앞벽이 있으면 방 안이 아예 안 보인다. 대신 벽을 캐릭터(2.1)보다 한참 높게 세워
# 실내감을 낸다. 남쪽은 보이지 않는 충돌벽으로만 막는다.
#
# 에셋: Kenney Furniture Kit 2.0 (CC0) — assets/furniture/*.glb. Godot 임포트 파이프라인을
# 쓰지 않는 이 repo 관례대로 ToonChar.load_glb 런타임 로드(= preload 불가) + 툰 셰이더.

const ToonChar := preload("res://common/toon_character.gd")
const DayNight := preload("res://world/day_night.gd")
const DIR := "res://assets/furniture/"

const ORIGIN := Vector3(120, 0, 120)  # 마을(|x|,|z| ≤ 40)·강·숲 띠에서 충분히 먼 격리 좌표
const HALF := 5.0        # 내부 반폭 (x·z 공통) → 방 10×10
const TILE := 2.0        # 바닥·벽 조각 배율 = 격자 한 칸(킷 조각이 1×1u라 그대로 칸 크기)
const FSC := 2.6         # 가구 배율 — 격자보다 크게. 캐릭터가 2.1로 치비 비율이라 킷 기본(×2)은
                         # 식탁이 무릎높이로 보인다(첫 스샷 실측). ×2.6이면 식탁 0.86 = 사람 눈에 맞다.
const WALL_YS := 2.6     # 벽 높이 배율 (킷 1.29 × 2.6 = 3.35 ≈ 캐릭터 1.6배). 오픈탑이라 낮으면 실내감이 안 남
const FLOOR_Y := 0.10    # 바닥 상면 = 가구 발높이 (floorFull 두께 0.05×TILE)
const OUTLINE := 0.004

# ── 문 전환 (절대좌표: test_core가 노드 없이 읽는 순수 상수) ──────────
const OUT_DOOR := Vector3(3, 1.0, 18.3)          # 집 앞 트리거 (플레이어 집 남향 문 z≈17.55 바로 앞)
const OUT_SPAWN := Vector3(3, 2.0, 20.6)         # 나왔을 때 서는 곳 — 트리거 밖(E 연타 왕복 차단)
const IN_DOOR := ORIGIN + Vector3(0, 1.0, -4.2)  # 실내 doorway 앞 (북쪽 벽 = 카메라 정면)
const IN_SPAWN := ORIGIN + Vector3(0, 1.2, 3.6)  # 들어왔을 때 서는 곳 — 방 남단, 방 전체가 프레임에 들어옴
const DOOR_R := 0.7                              # 문 트리거 반경 (플레이어 InteractArea 1.3 + 이것 = 프롬프트 사거리 2.0)
const FACE_IN := Vector3(0, 0, -1)               # 들어가면 방 안쪽(북)을 본다 = 방 전체가 보인다
const FACE_OUT := Vector3(0, 0, 1)               # 나오면 집을 등지고 남쪽을 본다
const SPOUSE_SPOT := ORIGIN + Vector3(1.8, 0, 3.0)  # 배우자 실내 정위치 (식탁 남동, 동선 밖)
const BED_CENTER := ORIGIN + Vector3(-3.0, 0.9, -3.43)  # bedDouble 실측 중심 (2.50×2.94)
const BED_SIZE := Vector3(2.50, 1.1, 2.94)

# ── 야간 실내등 ──────────────────────────────────────────────────
const LAMP_E := 1.2                       # 최대 밝기 (밤). 2.2는 방 전체가 균일하게 떠서 아늑함이 죽었다
const LAMP_COL := Color(1.0, 0.86, 0.66)  # 따뜻한 전구색
const LAMP_RANGE := 7.5                   # 모서리는 어둡게 남겨야 등불로 읽힌다

# 벽 조각: [glb, 축, 좌표] — 북(z=-HALF)은 x축으로, 동/서는 z축으로 늘어선다.
# 남(+z)은 카메라 쪽이라 생략. 문은 북쪽 벽 중앙 = 방에 들어서면 정면에 보인다.
const WALL_N := ["wall", "wall", "wallDoorway", "wallWindow", "wall"]  # x = -4,-2,0,2,4
const WALL_W := ["wall", "wall", "wall", "wallWindow", "wall"]         # z = -4,-2,0,2,4
const WALL_E := ["wall", "wall", "wallWindow", "wall", "wall"]

# 조각별 색조 곱(ToonChar.load_glb tint). Kenney 킷은 전부 크림·흰 계열이라 그대로 쓰면
# 벽·바닥·가구가 한 덩어리로 붕 뜬다(실측). 바닥은 따뜻한 목재로, 벽은 살짝 식혀 분리하고,
# 흰 벽에 묻히던 흰 냉장고에만 푸른기를 준다. 없는 조각은 원본색(흰 tint).
const TINTS := {
	"floorFull": Color(0.97, 0.90, 0.82),      # 살짝만 — 강하게 주면 형광 주황이 된다(실측)
	"kitchenFridge": Color(0.78, 0.86, 0.94),  # 흰 벽에 흰 냉장고가 통째로 사라져서
}

# 가구: [glb, x, z, rot_deg, y]. 좌표=ORIGIN 기준, rot 0 = Kenney 기본(정면이 +z=남=카메라 쪽).
# 킷 원점은 "정면 아래 모서리"라 뒷면이 -z로 자란다 → 북벽에 붙이려면 rot 0 + z를 벽쪽으로.
const FURNITURE := [
	["bedDouble", -3.0, -4.9, 180, 0.0],      # 북서: 머리맡을 북벽에 (rot180 = 몸통이 +z로 자람)
	["sideTable", -3.0, -1.0, 0, 0.0],        # 침대 발치 협탁
	["lampRoundTable", -3.0, -1.15, 0, 0.99], # 협탁 위 (sideTable 높이 0.38×FSC)
	["kitchenStove", 1.9, -3.75, 0, 0.0],     # 북동: 부엌 라인 (뒷면이 북벽)
	["kitchenSink", 3.1, -3.75, 0, 0.0],
	["kitchenFridge", 4.3, -4.15, 0, 0.0],
	["bookcaseClosedDoors", -4.35, 0.8, 90, 0.0],  # 서벽 (rot90 = 정면이 +x = 방 안쪽)
	["rugRectangle", 0.0, 1.4, 0, 0.01],      # 중앙 러그 (바닥 위 살짝)
	["table", 0.0, 0.6, 0, 0.0],              # 러그 위 식탁
	["chair", -1.8, 0.2, 90, 0.0],            # 식탁 서쪽 의자 (동쪽을 봄)
	["chair", 1.8, 0.2, -90, 0.0],            # 식탁 동쪽 의자
	["lampRoundFloor", 4.3, 1.8, 0, 0.0],     # 동쪽 스탠드
	["pottedPlant", -4.4, 3.4, 0, 0.0],       # 남서 화분
]
# 큰 가구만 대강 충돌 [x, z, w, d] (침대·책장·냉장고·식탁) — 나머진 통과 허용(오두막이 좁다)
const SOLIDS := [
	[-3.0, -3.43, 2.50, 2.94], [-4.67, 0.8, 0.65, 1.04],
	[4.3, -4.52, 1.12, 0.75], [0.0, 0.02, 2.18, 1.17],
]

var _cache := {}          # glb 이름 → 원본 Node3D (같은 조각 반복 로드 방지)
var _lamps: Array[OmniLight3D] = []

func _ready() -> void:
	add_to_group("interior")
	_ground_pad()
	_floor()
	_walls()
	for f in FURNITURE:
		_place(f[0], Vector3(f[1], FLOOR_Y + f[4], f[2]), f[3])
	for s in SOLIDS:
		_collide(Vector3(s[0], 1.0, s[1]), Vector3(s[2], 2.0, s[3]))
	_shell_collision()
	_bed()
	_doors()
	_lights()
	for n in _cache.values():  # 배치용 원본은 트리 밖 — 놔두면 종료 시 누수로 잡힌다
		if n != null:
			(n as Node).free()
	_cache.clear()

# ── 조립 ─────────────────────────────────────────────────────────
# GLB 1회 로드 후 복제 배치. rel = ORIGIN 기준 좌표, sc = 가로 배율, ysc = 세로 배율.
func _place(name: String, rel: Vector3, rot_deg: float, sc := FSC, ysc := 0.0) -> void:
	if not _cache.has(name):
		_cache[name] = ToonChar.load_glb(DIR + name + ".glb", OUTLINE, TINTS.get(name, Color.WHITE))
	var proto: Node3D = _cache[name]
	if proto == null:
		return  # 에셋 누락 폴백: 그 조각만 비운다(방은 그대로 선다)
	var n: Node3D = proto.duplicate()
	n.scale = Vector3(sc, sc if ysc == 0.0 else ysc, sc)
	n.rotation.y = deg_to_rad(rot_deg)
	n.position = ORIGIN + rel
	add_child(n)

func _floor() -> void:
	# floorFull 원점이 +z 모서리라(로컬 z∈[-1,0]) 타일 중심을 맞추려면 반 칸 밀어 놓는다.
	for ix in 5:
		for iz in 5:
			_place("floorFull", Vector3(-4.0 + ix * TILE, 0, -4.0 + iz * TILE + TILE * 0.5), 0, TILE)

func _walls() -> void:
	for i in 5:
		var c := -4.0 + i * TILE
		_place(WALL_N[i], Vector3(c, 0, -HALF), 0, TILE, WALL_YS)      # 북: 정면(+z)이 방 안쪽
		_place(WALL_W[i], Vector3(-HALF, 0, c), 90, TILE, WALL_YS)     # 서: 정면이 +x
		_place(WALL_E[i], Vector3(HALF, 0, c), -90, TILE, WALL_YS)     # 동: 정면이 -x

# 방 밖은 지형이 없다(Ground는 원점 80×80). 줌아웃·모서리에서 허공이 보이지 않게 넓은 받침을 깐다.
func _ground_pad() -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(30, 0.5, 30)
	mi.mesh = bm
	mi.material_override = ToonChar.make_solid(Color(0.62, 0.8, 0.52), 0.0)  # 마을 지면과 같은 초지색
	mi.position = ORIGIN + Vector3(0, -0.45, 0)
	add_child(mi)

# 바닥 + 4면 벽 충돌(남쪽은 보이지 않는 벽 — 문 없는 열린 면으로 나가 허공에 떨어지는 것 방지)
func _shell_collision() -> void:
	_collide(Vector3(0, -0.1, 0), Vector3(2 * HALF + 1.0, 0.4, 2 * HALF + 1.0))  # 상면 y=0.10
	for s in [-1.0, 1.0]:
		_collide(Vector3(0, 1.7, s * (HALF + 0.05)), Vector3(2 * HALF + 0.4, 3.4, 0.3))
		_collide(Vector3(s * (HALF + 0.05), 1.7, 0), Vector3(0.3, 3.4, 2 * HALF + 0.4))

func _collide(rel: Vector3, size: Vector3) -> void:
	var sb := StaticBody3D.new()
	sb.position = ORIGIN + rel
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	sb.add_child(cs)
	add_child(sb)

# 취침 침대: 야외 침대를 대체(world.tscn Bed 삭제 + WORLD_VERSION 범프). 그룹·라벨 규약 동일.
func _bed() -> void:
	var a := Area3D.new()
	a.add_to_group("bed")
	a.position = BED_CENTER
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = BED_SIZE
	cs.shape = sh
	a.add_child(cs)
	a.add_child(_label("침대", 1.2))
	add_child(a)

func _doors() -> void:
	_door(OUT_DOOR, IN_SPAWN, "E: 들어가기", FACE_IN)
	_door(IN_DOOR, OUT_SPAWN, "E: 나가기", FACE_OUT)

# 문 = 그룹 "door" Area3D + 메타(목적지·문구·도착 방향). player.gd는 메타만 읽는다 = 프롬프트 레지스트리.
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

# 실내등: 낮엔 태양광으로 충분하니 꺼두고 밤에만 켠다. 시각 판정은 day_night.sample()의
# 태양 에너지를 그대로 읽어 쓴다 — 승인된 룩 상수를 복제하지 않기 위함(단일 출처).
func _lights() -> void:
	for at in [Vector3(-3.0, 1.5, -2.05), Vector3(4.2, 1.9, 1.6)]:  # 협탁 램프 / 스탠드 위치
		var o := OmniLight3D.new()
		o.position = ORIGIN + at
		o.light_color = LAMP_COL
		o.omni_range = LAMP_RANGE
		o.light_energy = 0.0
		add_child(o)
		_lamps.append(o)

func _process(_dt: float) -> void:
	var sun_e: float = DayNight.sample(GameClock.game_min / 60.0)["sun_e"]
	var e: float = LAMP_E * (1.0 - smoothstep(0.25, 0.9, sun_e))
	for o in _lamps:
		o.light_energy = e

# ── 순수 판정 (test_core가 노드 없이 검증) ────────────────────────
# 이 좌표가 실내인가. 문 앞 여유(+3)까지 실내로 봐서 문턱에서 판정이 깜빡이지 않게 한다.
static func inside(p: Vector3) -> bool:
	return absf(p.x - ORIGIN.x) < HALF + 3.0 and absf(p.z - ORIGIN.z) < HALF + 3.0

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

# ══ 절차 형태 원형 ═════════════════════════════════════════════════
# 킷 재고에 야생 채집물로 쓸 비(非)파크 메시는 apple·grapes뿐이고 둘 다 이미 배정돼 있다 —
# 나머지 14종이 색 구체로 떨어져 있었다. 파크 킷 꽃·풀에 색만 입히는 안은 위 KIT_DIR 주석의
# 이유로 금지다(배경 식생 785개에 위장된다). 그래서 **원형 4종을 절차로 만들고 14종을 얹는다**.
# 종당 고유 메시 14개는 안 깎는다: 색이 이미 종별로 갈려 있고(색 핀이 채널차 0.08을 보장) 원형과
# 비율이 한 겹 더 가른다. 문법은 decor.blob_mesh 전례를 그대로 따른다(정점 워프 + 파라미터 배열).
#
# **어느 원형을 쓸지는 json의 "shape"가 정한다** — color·mesh와 같은 규약이라 엔진엔 종 이름이
# 없다(테스트가 이 파일 소스를 훑어 종 이름을 금지한다). 슬롯 의미는 form마다 다르다:
#   cap     [갓 반경, 갓 높이, 갓 벌어짐(1=반구·<1 뿔·>1 나팔), 대 반경, 대 높이]
#   cluster [알 반경, 알 개수, 송이 반경, 세로 배율, 자루 높이]
#   tuft    [잎 길이, 잎 폭, 잎 수, 벌어짐(도), 코어 반경, 코어 y비(잎 길이 기준·음수=잎 아래), 코어 개수]
#   nut     [알 반경, 알 높이, 끝 뾰족도(0=뿔·1=구), 꼭지 높이]
#
# 전고는 LOOK_H(0.50) 대역으로 **처음부터 저작**한다 — 킷처럼 AABB로 재서 전고를 맞추면
# 균일 배율이라 납작한 원형이 옆으로 불어난다(시도 후 되돌림: 전고 정규화를 넣었더니 낮고 퍼진
# 잎다발 원형이 폭 1.28m = 줍는 반경 0.9보다 넓어져 통행 방해가 된다, 계산 실측).
# 지면 접지만 AABB로 잡는다(_look).
const SHAPES := {
	# 버섯 — 갓의 벌어짐이 세 종을 가른다(둥근 갓 / 좁은 뿔 / 나팔). 대는 반드시 갓 아래로
	# 삐져나와야 한다 — 갓만 땅에 놓이면 그냥 색 돔이라 구체 시절과 다를 바 없다(실측 1차).
	"mushroom_dome":  ["cap", 0.195, 0.155, 0.90, 0.055, 0.250],
	# 뿔은 0.22·0.45까지 열어도 원거리에선 "고깔"로 읽혔다(실측 1·2차). 0.62 = 끝이 뭉툭한
	# 탄두형 + 대를 0.26까지 뽑아야 갓/대가 나뉜다 — 지면 곡률이 먼 물체의 밑동을 먹기 때문에
	# 대는 넉넉해야 한다(짧은 대는 흙길 위에서 통째로 사라졌다).
	"mushroom_cone":  ["cap", 0.105, 0.220, 0.62, 0.045, 0.260],
	"mushroom_flare": ["cap", 0.125, 0.120, 1.50, 0.040, 0.320],
	# 송이 — 알 크기·개수·세로 배율이 "포도알 뭉치 / 오디 / 이삭"을 가른다.
	"berry_bunch":    ["cluster", 0.072,  7, 0.105, 1.15, 0.14],
	"berry_drupe":    ["cluster", 0.052, 11, 0.080, 1.85, 0.12],
	"floret_spike":   ["cluster", 0.030, 15, 0.040, 3.40, 0.18],
	# 잎 다발 — 잎은 전부 곁들이 초록이고 **종 색은 코어**(뿌리·꽃·열매)가 낸다. 코어 y비가
	# 밑동(뿌리) / 잎 사이(열매) / 잎 위(꽃)를 가른다 = 다섯 종이 같은 초록 덩어리로 안 뭉친다.
	"leaf_blade":     ["tuft", 0.47, 0.075, 5, 13, 0.055, 0.09, 1],
	"leaf_bush":      ["tuft", 0.42, 0.150, 7, 28, 0.055, 0.42, 3],
	# 뿌리 코어는 y비가 양수면 잎 밑동이 알을 감싸 안 보인다(실측 1차: 설원 위에서 초록 잎만
	# 읽혔다) — 음수로 잎 아래에 앉혀야 알이 드러나고 "잎 달린 뿌리"로 읽힌다.
	"leaf_root":      ["tuft", 0.34, 0.100, 5, 24, 0.105, -0.20, 1],
	"leaf_bloom":     ["tuft", 0.30, 0.090, 6, 30, 0.090, 1.25, 1],
	"leaf_sprig":     ["tuft", 0.34, 0.130, 5, 26, 0.055, 0.92, 3],
	# 견과 — 납작 둥근 알 / 길쭉한 솔방울. 뾰족도를 0.2 아래로 주면 매끈한 원뿔이 돼 "고깔"로
	# 읽힌다(실측 1차) — 배가 부른 물방울이라야 알맹이로 보인다.
	"nut_round":      ["nut", 0.170, 0.340, 0.28, 0.060],
	"nut_cone":       ["nut", 0.115, 0.380, 0.34, 0.055],
}
# 곁들이 색(대·잎·자루). 종 색이 아니라 **원형이 고르는 고정색**이다 — 두 톤이라야 근경에서
# "단색 덩어리 하나"로 안 읽힌다(decor.gd의 절차 폐곡면 실패 사유와 같은 지적).
# 잎 초록은 배경 식생(킷 아틀라스 × VEG_GAIN)보다 한 단 진하게 — 같은 초록이면 또 위장된다.
const C_STEM := Color(0.72, 0.66, 0.52)  # 버섯 대 · 견과 꼭지
const C_LEAF := Color(0.34, 0.52, 0.26)  # 잎 · 송이 자루
const OUTLINE_W := 0.006                 # 옛 구체와 같은 외곽선 폭

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
				# 킷 메시가 다 바닥 기준인 건 아니다 — 포도 송이는 원점보다 0.069 아래로 늘어져
				# 땅에 묻힌 채 찍혔다(실측). 절차 경로와 같은 규약으로 밑동을 지면에 앉힌다.
				n.position.y = -ToonChar.aabb_of(n).position.y
				return n
	var shp := String(d.get("shape", ""))
	if SHAPES.has(shp):
		var mi2 := MeshInstance3D.new()
		mi2.mesh = _shape(fid, shp, col)
		# 밑동을 지면에 앉힌다 = 피벗 바닥 기준(킷 경로와 같은 규약, 구체 폴백만 중심 피벗이라
		# 띄웠다). 저작 원점이 y=0이어도 눕힌 잎·자루가 조금씩 파고들어 AABB로 잡는다.
		mi2.position.y = -mi2.mesh.get_aabb().position.y
		return mi2
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = LOOK_H * 0.5
	sm.height = LOOK_H
	mi.mesh = sm
	mi.material_override = ToonChar.make_solid(col, OUTLINE_W)
	mi.position = Vector3(0, LOOK_H * 0.57, 0)  # 구체는 피벗이 중심이라 띄운다(킷 메시는 바닥 기준)
	return mi

# 종당 메시 1장. 한 종이 여러 지점에 스폰돼도 새로 깎지 않는다(decor._flora_cache 전례).
# 색이 메시 표면에 구워지므로 캐시 키는 원형이 아니라 **종**이다.
var _shape_cache := {}

func _shape(fid: String, shp: String, col: Color) -> ArrayMesh:
	if not _shape_cache.has(fid):
		_shape_cache[fid] = shape_mesh(SHAPES[shp], col)
	return _shape_cache[fid]

# 원형 메시. 표면 0 = 종 색(먹는 부분), 표면 1 = 곁들이(대·잎·자루).
# static = 노드 없이도 만든다(decor.blob_mesh와 같은 규약 — 테스트가 직접 부른다).
static func shape_mesh(k: Array, col: Color) -> ArrayMesh:
	var body := SurfaceTool.new()   # 표면 0
	var side := SurfaceTool.new()   # 표면 1
	body.begin(Mesh.PRIMITIVE_TRIANGLES)
	side.begin(Mesh.PRIMITIVE_TRIANGLES)
	var acc := C_STEM
	match String(k[0]):
		"cap":
			_stalk(side, float(k[4]), float(k[5]))
			body.append_from(_dome(float(k[3])), 0, Transform3D(
				Basis().scaled(Vector3(float(k[1]), float(k[2]), float(k[1]))),
				Vector3(0, float(k[5]), 0)))
		"cluster":
			acc = C_LEAF
			_stalk(side, float(k[1]) * 0.34, float(k[5]) + float(k[3]) * float(k[4]))
			_blobs(body, int(k[2]), float(k[1]), float(k[3]), float(k[4]), float(k[5]))
		"tuft":
			acc = C_LEAF
			_leaves(side, float(k[1]), float(k[2]), int(k[3]), float(k[4]))
			var cy := float(k[1]) * float(k[6])
			if float(k[6]) > 0.35:  # 잎보다 위에 뜬 코어는 받쳐 줄 자루가 없으면 공중에 뜬다
				_stalk(side, float(k[5]) * 0.28, cy)
			_blobs(body, int(k[7]), float(k[5]), float(k[5]) * 0.85 if int(k[7]) > 1 else 0.0,
				0.5, cy)
		"nut":
			_teardrop_into(body, float(k[1]), float(k[2]), float(k[3]))
			var tip := CylinderMesh.new()
			tip.top_radius = 0.001
			tip.bottom_radius = float(k[1]) * 0.26
			tip.height = float(k[4])
			tip.radial_segments = 8
			tip.rings = 1
			side.append_from(tip, 0, Transform3D(Basis(),
				Vector3(0, float(k[2]) + float(k[4]) * 0.5, 0)))
	# append_from은 붙일 때 법선에 basis를 그대로 곱한다 = 눌러 만든 잎에서 법선이 뒤집힌 방향으로
	# 쏠린다. 합쳐서 다시 만든다(인덱스 → 스무스 셰이딩, blob_mesh와 같은 마무리).
	for st in [body, side]:
		st.index()
		st.generate_normals()
	var m := body.commit()
	side.commit(m)
	m.surface_set_material(0, ToonChar.make_solid(col, OUTLINE_W))
	m.surface_set_material(1, ToonChar.make_solid(acc, OUTLINE_W))
	return m

# 반구(밑이 평평한 갓)를 위로 갈수록 좁히거나(뿔) 넓히는(나팔) 워프. 단위 크기 — 호출부가 scale.
static func _dome(flare: float, seg := 16) -> ArrayMesh:
	var sp := SphereMesh.new()
	sp.radius = 1.0
	sp.height = 1.0  # 반구는 height를 통째로 쓴다(2.0을 주면 y가 0~2 = 갓 높이가 두 배, 실측)
	sp.is_hemisphere = true
	sp.radial_segments = seg
	sp.rings = 6
	var a := sp.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	for i in v.size():
		var f: float = lerpf(1.0, flare, clampf(v[i].y, 0.0, 1.0))
		v[i] = Vector3(v[i].x * f, v[i].y, v[i].z * f)
	a[Mesh.ARRAY_VERTEX] = v
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	return m

# 위로 갈수록 좁아지는 알(견과). taper 0=뿔 1=구. 밑동이 y=0, 꼭대기가 y=h.
static func _teardrop_into(st: SurfaceTool, r: float, h: float, taper: float) -> void:
	var sp := SphereMesh.new()
	sp.radius = 1.0
	sp.height = 2.0
	sp.radial_segments = 14
	sp.rings = 8
	var a := sp.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	for i in v.size():
		var t: float = (v[i].y + 1.0) * 0.5
		var f: float = lerpf(1.0, taper, t * t)  # 아래는 통통하게 두고 위만 모은다
		v[i] = Vector3(v[i].x * f, v[i].y, v[i].z * f)
	a[Mesh.ARRAY_VERTEX] = v
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	st.append_from(m, 0, Transform3D(Basis().scaled(Vector3(r, h * 0.5, r)), Vector3(0, h * 0.5, 0)))

# 자루·대 — 밑동이 살짝 굵어야 뽑아 놓은 것처럼 안 보인다.
static func _stalk(st: SurfaceTool, r: float, h: float) -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r * 1.3
	cm.height = h
	cm.radial_segments = 10
	cm.rings = 1
	st.append_from(cm, 0, Transform3D(Basis(), Vector3(0, h * 0.5, 0)))

# 알 뭉치. 가운데가 통통하고 위아래로 좁아지는 송이 — 등반경으로 쌓으면 실루엣이 막대가 된다.
# spread 0이면 한 알을 축에 놓는다(잎 다발의 뿌리·꽃 코어가 이 경로).
static func _blobs(st: SurfaceTool, n: int, r: float, spread: float, squash: float, y0: float) -> void:
	var sp := SphereMesh.new()
	sp.radius = r
	sp.height = r * 2.0
	sp.radial_segments = 10
	sp.rings = 6
	var col_h := spread * 2.0 * squash
	for i in n:
		var t: float = (i + 0.5) / float(n)
		var rr: float = spread * (0.25 + 0.75 * sqrt(maxf(1.0 - pow(2.0 * t - 1.0, 2.0), 0.0)))
		var ang: float = i * 2.39996323  # 황금각 — 한 방향으로만 쌓이지 않게
		st.append_from(sp, 0, Transform3D(Basis(),
			Vector3(cos(ang) * rr, y0 + col_h * t, sin(ang) * rr)))

# 잎 = 납작하게 눌러 길게 뽑은 타원체를 밑동에서 방사로 세우고 바깥으로 눕힌 것.
static func _leaves(st: SurfaceTool, ln: float, w: float, n: int, tilt: float) -> void:
	var sp := SphereMesh.new()
	sp.radius = 1.0
	sp.height = 2.0
	sp.radial_segments = 8
	sp.rings = 5
	for i in n:
		var ang: float = TAU * i / float(n) + 0.4  # 0.4 = 정면에 잎 하나가 딱 오지 않게 비튼다
		var b := Basis.from_euler(Vector3(0, ang, 0)) * Basis.from_euler(Vector3(deg_to_rad(tilt), 0, 0))
		st.append_from(sp, 0, Transform3D(b, Vector3.ZERO)
			* Transform3D(Basis().scaled(Vector3(w * 0.5, ln * 0.5, w * 0.16)), Vector3(0, ln * 0.5, 0)))

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

extends RefCounted
# 식물 겉모습 원형 — 채집물(forage_system)과 밭 작물(farm_system) **공용**.
#
# 5b6566d에서 채집물 전용으로 지었던 절차 생성기를 그대로 끌어올린 것이다(새 틀이 아니다).
# 밭 작물 25종도 같은 어휘로 만들어야 "기른 라벤더 ≠ 주운 라벤더"가 안 생긴다 — 재배 채집물
# 13종은 아예 **같은 메시 한 장**을 공유한다(mesh_for의 캐시 키 = 산출물 id).
# 밭 몫으로는 root(뿌리채소) / bush(열매채소) / vine(덩굴) 세 계열을 표에 **더했다**.
#
# 어느 원형을 쓸지는 데이터가 정한다 — forage.json·crops.json의 "shape". 엔진엔 종 이름이
# 한 줄도 없다(테스트가 이 파일 소스를 훑어 금지한다).

const ToonChar := preload("res://common/toon_character.gd")
const Decor := preload("res://world/decor.gd")  # 킷 로드 규약(load_kit·충돌 벗기기·식생 밝기)

# 킷 메시 접두어. **파크 킷(Decor.TT_PARK)은 쓰면 안 된다** — decor.gd가 그 킷 여섯 종을
# 683개 흩뿌린 게 마을 배경이라, 같은 메시를 쓰면 "주울 수 있는 것"으로 안 읽힌다(실측
# forage_look/crop_spring). 배경 어휘 밖의 킷만 쓴다.
const KIT_DIR := {
	"picnic": "res://assets/tinytreats/Tiny_Treats_Pleasant_Picnic_1.0_FREE/Assets/gltf/",
}
# 킷 메시 목표 전고. 원본 크기가 제각각(파크 꽃 0.14 · 피크닉 포도 0.05)이라 AABB로 재서
# 여기 맞춘다 = json에 배율을 또 적지 않는다.
const LOOK_H := 0.50
# 킷 메시 폭 상한. **전고만 맞추면 가로로 퍼진 원본이 그대로 옆으로 남는다** — 송이는 폭 0.734,
# 사과는 0.617까지 불어 밭 한 칸(0.92)에 양옆 0.09씩만 남겼다(실측 winter_y1). 절차 원형 중
# 제일 넓은 것이 0.474(덩굴 수박)이니 그 언저리로 자른다 = 한 칸에 양옆 0.20씩 남는다.
# 0.48까지 조이면 송이 전고가 0.327로 내려가 채집물 전고 대역(0.34~0.52) 밖으로 나간다 —
# 0.52가 "폭을 최대한 줄이되 키를 대역 안에 두는" 값이다(실측).
const LOOK_W := 0.52

# 곁들이 색(대·잎·자루). 종 색이 아니라 **원형이 고르는 고정색**이다 — 두 톤이라야 근경에서
# "단색 덩어리 하나"로 안 읽힌다(decor.gd의 절차 폐곡면 실패 사유와 같은 지적).
# 잎 초록은 배경 식생(킷 아틀라스 × VEG_GAIN)보다 한 단 진하게 — 같은 초록이면 위장된다.
const C_STEM := Color(0.72, 0.66, 0.52)  # 버섯 대 · 견과 꼭지
const C_LEAF := Color(0.34, 0.52, 0.26)  # 잎 · 줄기 · 자루
const OUTLINE_W := 0.006

# ══ 원형 표 ════════════════════════════════════════════════════════
# 슬롯 의미는 form마다 다르다:
#   cap     [갓 반경, 갓 높이, 갓 벌어짐(1=반구·<1 뿔·>1 나팔), 대 반경, 대 높이]
#   cluster [알 반경, 알 개수, 송이 반경, 세로 배율, 자루 높이]
#   tuft    [잎 길이, 잎 폭, 잎 수, 벌어짐(도), 코어 반경, 코어 y비(잎 길이 기준·음수=잎 아래), 코어 개수,
#            (선택) 코어 퍼짐 배율 — 없으면 0.85 = 알들이 한 덩어리로 붙는다]
#   nut     [알 반경, 알 높이, 끝 뾰족도(0=뿔·1=구), 꼭지 높이]
#   root    [뿌리 반경, 흙 위 노출 높이, 밑동 좁힘(0=뿔·1=구), 잎 길이, 잎 폭, 잎 수, 잎 벌어짐(도)]
#   bush    [줄기 높이, 잎 길이, 잎 수, 잎 벌어짐(도), 열매 반경, 열매 개수, 매달린 폭, 열매 세로 늘임]
#   vine    [열매 반경, 눌림(1=구·<1 납작), 잎 길이, 잎 폭, 잎 수, 잎 벌어짐(도)]
#
# 전고는 **처음부터 저작**한다 — AABB로 재서 전고를 맞추면 균일 배율이라 납작한 원형이 옆으로
# 불어난다(시도 후 되돌림: 전고 정규화를 넣었더니 낮고 퍼진 잎다발이 폭 1.28m = 줍는 반경 0.9보다
# 넓어졌다). 지면 접지만 AABB로 잡는다(build).
const SHAPES := {
	# ── 채집물 어휘 (5b6566d) ──────────────────────────────────────
	# 버섯 — 갓의 벌어짐이 세 종을 가른다(둥근 갓 / 좁은 뿔 / 나팔). 대는 반드시 갓 아래로
	# 삐져나와야 한다 — 갓만 땅에 놓이면 그냥 색 돔이라 구체 시절과 다를 바 없다(실측 1차).
	"mushroom_dome":  ["cap", 0.195, 0.155, 0.90, 0.055, 0.250],
	# 뿔은 0.22·0.45까지 열어도 원거리에선 "고깔"로 읽혔다(실측 1·2차). 0.62 = 끝이 뭉툭한
	# 탄두형 + 대를 0.26까지 뽑아야 갓/대가 나뉜다 — 지면 곡률이 먼 물체의 밑동을 먹는다.
	"mushroom_cone":  ["cap", 0.105, 0.220, 0.62, 0.045, 0.260],
	"mushroom_flare": ["cap", 0.125, 0.120, 1.50, 0.040, 0.320],
	# 송이 — 알 크기·개수·세로 배율이 "포도알 뭉치 / 오디 / 이삭"을 가른다.
	"berry_bunch":    ["cluster", 0.072,  7, 0.105, 1.15, 0.14],
	"berry_drupe":    ["cluster", 0.052, 11, 0.080, 1.85, 0.12],
	"floret_spike":   ["cluster", 0.030, 15, 0.040, 3.40, 0.18],
	# 잎 다발 — 잎은 전부 곁들이 초록이고 **종 색은 코어**(뿌리·꽃·열매)가 낸다. 코어 y비가
	# 밑동 / 잎 사이 / 잎 위를 가른다 = 다섯 종이 같은 초록 덩어리로 안 뭉친다.
	"leaf_blade":     ["tuft", 0.47, 0.075, 5, 13, 0.055, 0.09, 1],
	"leaf_bush":      ["tuft", 0.42, 0.150, 7, 28, 0.055, 0.42, 3],
	# 뿌리 코어는 y비가 양수면 잎 밑동이 알을 감싸 안 보인다(실측 1차) — 음수로 잎 아래에 앉힌다.
	"leaf_root":      ["tuft", 0.34, 0.100, 5, 24, 0.105, -0.20, 1],
	"leaf_bloom":     ["tuft", 0.30, 0.090, 6, 30, 0.090, 1.25, 1],
	"leaf_sprig":     ["tuft", 0.34, 0.130, 5, 26, 0.055, 0.92, 3],
	# 견과 — 납작 둥근 알 / 길쭉한 솔방울. 뾰족도 0.2 아래는 매끈한 원뿔이라 "고깔"로 읽힌다.
	"nut_round":      ["nut", 0.170, 0.340, 0.28, 0.060],
	"nut_cone":       ["nut", 0.115, 0.380, 0.34, 0.055],
	# 야생 씨앗(늦가을) — 잎 사이로 알 셋이 **따로따로** 달린 씨앗 꼬투리. 종 색은 그 종의 열매
	# 색을 그대로 쓰므로 **형태는 넷이 공유한다**: "이건 씨앗이다"가 먼저 읽히고 어느 종인지는
	# 색이 말한다.
	# 1차 판(잎 25° · 알 5개 · 퍼짐 기본 0.85 · y비 0.62)은 알이 전부 겹쳐 한 덩어리가 되고
	# 곧게 선 잎이 그걸 감싸서 **튤립 봉오리**로 읽혔다(실측 forage/seeds_after). 셋을 고쳤다:
	# 잎을 44°까지 눕혀 컵 모양을 깨고, 알을 셋으로 줄여 퍼짐 2.6으로 떼어 놓고, y비를 0.50으로
	# 내려 자루가 드러나게 했다 — 알이 여럿이라는 게 보여야 "씨앗"으로 읽힌다.
	"seed_pod":       ["tuft", 0.40, 0.085, 4, 44, 0.040, 0.50, 3, 2.6],

	# ── 밭 어휘 (2026-08-26) ──────────────────────────────────────
	# 갓 난 싹은 실제로 종 구분이 안 된다 — 전 작물이 이 하나를 나눠 쓴다(공용 새싹).
	# 전고 0.11: 흙 타일(높이 0.10)과 같은 대역이라 "이제 막 텄다"로 읽힌다.
	"sprout":         ["tuft", 0.13, 0.055, 3, 52, 0.020, -0.06, 1],
	# 뿌리채소 — 흙 위로 드러난 어깨(뒤집은 물방울: 위가 굵고 밑이 좁다) + 그 위에 잎.
	# 밑동 좁힘이 "통통한 구근 / 좁고 긴 뿌리 / 거의 공(결구)"을 가른다.
	"root_bulb":      ["root", 0.135, 0.170, 0.50, 0.25, 0.095, 5, 42],
	"root_taproot":   ["root", 0.080, 0.240, 0.22, 0.30, 0.075, 6, 22],
	"root_head":      ["root", 0.175, 0.260, 0.92, 0.24, 0.170, 6, 68],
	"root_tuber":     ["root", 0.105, 0.115, 0.72, 0.28, 0.130, 7, 46],
	# 열매채소 — 줄기에 열매가 매달린다. 줄기 높이 + 열매 세로 늘임이 종을 가른다:
	# 키 큰 포기 / 길쭉한 꼬투리 / 늘어진 큰 열매 / 땅에 깔린 작은 열매 / 좁쌀 열매 / 이삭.
	"bush_tall":      ["bush", 0.46, 0.24, 5, 40, 0.070, 5, 0.075, 1.00],
	"bush_pod":       ["bush", 0.34, 0.20, 4, 44, 0.048, 5, 0.062, 1.90],
	"bush_drop":      ["bush", 0.40, 0.23, 5, 42, 0.062, 3, 0.070, 1.75],
	"bush_low":       ["bush", 0.17, 0.26, 6, 66, 0.045, 5, 0.105, 1.00],
	"bush_berry":     ["bush", 0.22, 0.20, 8, 58, 0.030, 9, 0.085, 1.00],
	# 이삭은 잎을 거의 세워야(18°) 밭에서 유일하게 위로 솟은 실루엣이 된다.
	"bush_stalk":     ["bush", 0.64, 0.44, 5, 18, 0.058, 2, 0.045, 2.30],
	# 덩굴 — 땅에 눕힌 잎 + 그 위에 놓인 큰 열매 하나. 눌림이 구/납작을 가른다.
	"vine_melon":     ["vine", 0.185, 0.88, 0.26, 0.130, 5, 74],
	"vine_gourd":     ["vine", 0.205, 0.66, 0.24, 0.150, 6, 78],
}
const SPROUT_SHAPE := "sprout"  # 공용 새싹(위 표의 항목) — 엔진이 아는 형태 이름은 이 둘뿐
const SEED_SHAPE := "seed_pod"  # 야생 씨앗 공용 원형(종 구분은 색이 낸다)

# ── 겉모습 노드 ────────────────────────────────────────────────────
# 킷 메시 → 절차 원형 순. 둘 다 없으면 null = 호출부가 폴백을 정한다(구체 / 상자).
# key = 메시 캐시 키. 재배 채집물이 **산출물 id**를 넘기면 주운 것과 같은 메시 한 장을 쓴다.
static func build(d: Dictionary, col: Color, key: String) -> Node3D:
	var mp := String(d.get("mesh", ""))
	if mp != "":
		var n := _kit_node(mp, col, key)
		if n != null:
			return n
	var shp := String(d.get("shape", ""))
	if SHAPES.has(shp):
		var mi := MeshInstance3D.new()
		mi.mesh = mesh_for(key, shp, col)
		# 밑동을 지면에 앉힌다 = 피벗 바닥 기준. 저작 원점이 y=0이어도 눕힌 잎·자루가 조금씩
		# 파고들어 AABB로 잡는다.
		mi.position.y = -mi.mesh.get_aabb().position.y
		return mi
	return null

# 종당 메시 1장. 여러 지점·여러 밭칸에 같은 종이 서도 새로 깎지 않는다(decor._flora_cache 전례).
# 색이 메시 표면에 구워지므로 캐시 키는 원형이 아니라 **종**이다.
static var _mesh_cache := {}

# 킷 메시도 **같은 계약**이다 — 절차 원형만 캐시가 있어서, 킷을 쓰는 종은 build를 부를 때마다
# gltf를 통째로 다시 읽고 있었다. 캐시 키는 절차 쪽과 같은 **종** id다: 색·배율·접지가 전부
# 그 종에서 나오므로 사본끼리 갈릴 여지가 없고, 재배 채집물이 산출물 id를 넘기면 밭 것과
# 주운 것이 같은 원본을 쓴다.
# 쥐는 것은 노드가 아니라 PackedScene이다 — decor._kit처럼 완성 노드를 들고 duplicate하면
# **정적 참조라 종료까지 안 풀린다**(실측: 종료 시 누수 객체 8 → 22). 리소스는 참조계수라
# 그 자국이 안 남고, 사본끼리 Mesh·머티리얼을 공유하는 건 duplicate와 같다.
static var _kit_cache := {}

static func _kit_node(mp: String, col: Color, key: String) -> Node3D:
	if not _kit_cache.has(key):
		var parts := mp.split("/", false, 1)
		if parts.size() != 2 or not KIT_DIR.has(parts[0]):
			return null
		var n := Decor.load_kit(KIT_DIR[parts[0]] + parts[1] + ".gltf", 1.0, 0.0, Decor.VEG_GAIN)
		if n == null:
			return null  # 에셋 누락 = 호출부 폴백(구체·상자)으로 흘린다
		Decor._strip_collision(n)  # 킷 충돌체가 붙으면 채집물·작물이 통행을 막는다
		tint(n, col)
		# 전고 정규화와 폭 상한 중 **작은 배율**을 쓴다. 전고만 맞추면 납작하고 넓은 원본(송이)이
		# 옆으로 넘치고, 폭만 맞추면 길쭉한 원본이 밭에서 안 보인다.
		var s: Vector3 = ToonChar.aabb_of(n).size
		var w: float = maxf(s.x, s.z)
		n.scale = Vector3.ONE * minf(LOOK_H / s.y, LOOK_W / w) if s.y > 0.001 and w > 0.001 			else Vector3.ONE
		# 킷 메시가 다 바닥 기준인 건 아니다 — 포도 송이는 원점보다 0.069 아래로 늘어져
		# 땅에 묻힌 채 찍혔다(실측). 절차 경로와 같은 규약으로 밑동을 지면에 앉힌다.
		n.position.y = -ToonChar.aabb_of(n).position.y
		var ps := PackedScene.new()
		ps.pack(n)
		n.free()
		_kit_cache[key] = ps
	return (_kit_cache[key] as PackedScene).instantiate() as Node3D

static func mesh_for(key: String, shp: String, col: Color) -> ArrayMesh:
	if not _mesh_cache.has(key):
		_mesh_cache[key] = shape_mesh(SHAPES[shp], col)
	return _mesh_cache[key]

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
			# 퍼짐 = 알 반경 × 배율. 기본 0.85면 알들이 서로 겹쳐 한 덩어리가 된다(꽃 코어가 그걸 쓴다).
			var sprd := float(k[8]) if k.size() > 8 else 0.85
			_blobs(body, int(k[7]), float(k[5]), float(k[5]) * sprd if int(k[7]) > 1 else 0.0,
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
		"root":
			acc = C_LEAF
			# 뒤집은 물방울 = 어깨가 위, 밑동이 흙 속으로 좁아진다. 똑바로 세우면(위가 뾰족)
			# 밭에서 "땅에 꽂힌 고깔"로 읽혔다 — 뿌리채소는 어깨가 드러나는 게 실제 모습이다.
			_teardrop_into(body, float(k[1]), float(k[2]), float(k[3]), true)
			_leaves(side, float(k[4]), float(k[5]), int(k[6]), float(k[7]), float(k[2]) * 0.85)
		"bush":
			acc = C_LEAF
			_stalk(side, 0.028, float(k[1]))
			_leaves(side, float(k[2]), float(k[2]) * 0.24, int(k[3]), float(k[4]))
			# 열매는 줄기 중단(0.30h)부터 꼭대기(0.95h)까지. _blobs의 세로 폭은 매달린 폭에
			# 묶여 있어서(spread·2·squash) 원하는 구간에서 squash를 역산한다.
			var ext := float(k[1]) * 0.65
			_blobs(body, int(k[6]), float(k[5]), float(k[7]),
				ext / maxf(2.0 * float(k[7]), 0.001), float(k[1]) * 0.30, float(k[8]))
		"vine":
			acc = C_LEAF
			_leaves(side, float(k[3]), float(k[4]), int(k[5]), float(k[6]))
			# 알 하나를 눌러 땅에 놓는다 — 중심 y = 반경×눌림이라야 밑이 정확히 y=0.
			_blobs(body, 1, float(k[1]), 0.0, 1.0, float(k[1]) * float(k[2]), float(k[2]))
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
# flip = 위아래를 바꾼다(뿌리채소: 어깨가 위, 밑이 좁다).
static func _teardrop_into(st: SurfaceTool, r: float, h: float, taper: float, flip := false) -> void:
	var sp := SphereMesh.new()
	sp.radius = 1.0
	sp.height = 2.0
	sp.radial_segments = 14
	sp.rings = 8
	var a := sp.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	for i in v.size():
		var t: float = (v[i].y + 1.0) * 0.5
		if flip:
			t = 1.0 - t
		var f: float = lerpf(1.0, taper, t * t)  # 굵은 쪽은 통통하게 두고 반대쪽만 모은다
		v[i] = Vector3(v[i].x * f, v[i].y, v[i].z * f)
	a[Mesh.ARRAY_VERTEX] = v
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	st.append_from(m, 0, Transform3D(Basis().scaled(Vector3(r, h * 0.5, r)), Vector3(0, h * 0.5, 0)))

# 자루·대·줄기 — 밑동이 살짝 굵어야 뽑아 놓은 것처럼 안 보인다.
static func _stalk(st: SurfaceTool, r: float, h: float) -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r * 1.3
	cm.height = h
	cm.radial_segments = 10
	cm.rings = 1
	st.append_from(cm, 0, Transform3D(Basis(), Vector3(0, h * 0.5, 0)))

# 알 뭉치. 가운데가 통통하고 위아래로 좁아지는 송이 — 등반경으로 쌓으면 실루엣이 막대가 된다.
# spread 0이면 한 알을 축에 놓는다(잎 다발의 코어·덩굴 열매가 이 경로).
# fy = 알 하나하나의 세로 늘임(1=구). 꼬투리·가지·이삭처럼 길쭉한 열매가 이걸 쓴다.
static func _blobs(st: SurfaceTool, n: int, r: float, spread: float, squash: float, y0: float,
		fy := 1.0) -> void:
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
		st.append_from(sp, 0, Transform3D(Basis().scaled(Vector3(1.0, fy, 1.0)),
			Vector3(cos(ang) * rr, y0 + col_h * t, sin(ang) * rr)))

# 잎 = 납작하게 눌러 길게 뽑은 타원체를 밑동에서 방사로 세우고 바깥으로 눕힌 것.
# y0 = 잎이 나는 높이(뿌리채소는 드러난 어깨 위에서 난다).
static func _leaves(st: SurfaceTool, ln: float, w: float, n: int, tilt: float, y0 := 0.0) -> void:
	var sp := SphereMesh.new()
	sp.radius = 1.0
	sp.height = 2.0
	sp.radial_segments = 8
	sp.rings = 5
	for i in n:
		var ang: float = TAU * i / float(n) + 0.4  # 0.4 = 정면에 잎 하나가 딱 오지 않게 비튼다
		var b := Basis.from_euler(Vector3(0, ang, 0)) * Basis.from_euler(Vector3(deg_to_rad(tilt), 0, 0))
		st.append_from(sp, 0, Transform3D(b, Vector3(0, y0, 0))
			* Transform3D(Basis().scaled(Vector3(w * 0.5, ln * 0.5, w * 0.16)), Vector3(0, ln * 0.5, 0)))

# 킷이 깔아둔 char_tint(KIT_TINT)만 종별 색으로 갈아끼운다. sat_cap·val_gain은 건드리지 않는다
# = 아틀라스 결이 살아 있는 채로 색상만 도는 것(decor.gd FLORA_TINT와 같은 수법).
static func tint(node: Node, col: Color) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		for i in mi.get_surface_override_material_count():
			var m := mi.get_surface_override_material(i) as ShaderMaterial
			if m != null:
				m.set_shader_parameter("char_tint", col)
	for c in node.get_children():
		tint(c, col)

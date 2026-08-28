class_name ToonCharacter
extends RefCounted
# GLB 런타임 로드 + 툰셰이더 적용 (lookdev·player 공용). Godot 임포트 불필요.

const TOON := preload("res://lookdev/toon.gdshader")
const OUTLINE := preload("res://lookdev/outline.gdshader")
const CONTACT := preload("res://world/contact.gdshader")
const WOOD := preload("res://world/wood.gdshader")

# 목재 팔레트 — world.gd C_WOOD / C_WOOD_D와 같은 값(test_core가 일치를 핀한다).
# 여기 복제하는 이유는 순환 preload 회피다(decor.gd가 마을 팔레트를 복제하는 것과 같은 전례).
const WOOD_C := Color(0.590, 0.480, 0.362)
const WOOD_D := Color(0.470, 0.372, 0.283)

# ── 크림 벽토의 그림자 레버 (벽면 순백 포화 처방) ─────────────────────
# 벽토는 정오 직광에서 세 채널이 다 255로 날아가 있었다(실측 beach_spawn_h12·windmill_h12:
# 직광 (255,255,255) / 그늘 (243,219,211)). albedo 하나로는 못 푼다 — 툰 light()의 lit:그늘
# 간격이 파스텔 대역보다 넓어서, 직광이 포화를 벗는 값까지 내리면 그늘이 갈색으로 떨어진다
# (world.gd C_WALL 주석의 실패 기록). 그래서 **머티리얼별 shadow_level**로 간격 자체를 좁힌다.
#
# WALL_SHADOW는 그 레버의 단일 튜닝 지점이다(0.55=셰이더 전역 기본 … 1.0=그늘 밝기 최대).
# 1.00에서도 벽은 평평해지지 않는다 — 그늘면 명암이 shadow_tint(0.78,0.66,0.72)에서 나오기
# 때문이다(해변 오두막 h12 clear 실측: 직광 (248,241,234) vs 그늘 (230,209,208) = G 32레벨).
# 상한값이라 여유가 없다: 그늘을 더 올려야 하면 다음 레버는 shadow_tint다.
# 0.80도 찍어 봤다(shots/wall/B_*) — 그늘 (221,199,199)로 한 단 탁해져 근접 컷에서 크림이
# 회색 쪽으로 읽힌다. 3안 비교표는 lookdev/shots/wall/비교표_벽면포화_20260829.md.
const CREAM_C := Color(0.742, 0.727, 0.690)
const WALL_SHADOW := 1.00

# 접지 그림자 판이 놓이는 월드 높이. 마을·해변·실내의 지면 상면이 전부 0.10이고 그 위 0.10을 띄운다 —
# 판이 밟고 선 표면보다 아래면 깊이 판정에 통째로 먹힌다. 넘어야 하는 것들(실측):
# 마을 흙길 상면 0.185 · 판석 0.14 · 밭 흙 0.11 / 해변 젖은 모래 띠 0.18 · 소품 그림자 판 0.19
# (0.19와 1cm 띄워야 갯바위·해송 판과 겹칠 때 z-fight 하지 않는다) / 실내 바닥 0.10 · 러그 0.16.
# ponytail: 다리 위는 호출측이 deck_lift를 더한다. 풍차 언덕 대지(상면 2.5)처럼 지형이 통째로
# 솟은 곳에선 판이 땅속에 묻혀 안 보인다 — 지형이 늘면 그때 발밑 높이를 인자로 받게 고친다.
const CONTACT_Y := 0.20

# 캐릭터 접지 그림자 코어 반경(플레이어·주민 공용 단일 레버, 꼬마는 ×KID_MULT).
# 치비 고양이는 폭이 ~1.3m(전고 2.1)이고 카메라가 30° 저각이라 몸통이 발밑 지면을 통째로
# 가린다 — 판이 몸통 반폭(0.65)보다 좁으면 그림자가 아예 안 보인다(실측 r0.35: 주민 8명
# 전원 그림자 0px). 몸통 폭 대역까지 키워야 판이 발 앞뒤로 삐져나와 접지로 읽힌다.
const CONTACT_R := 0.55

# 캐릭터 외곽선 두께의 단일 튜닝 레버 — 월드 단위(m). 연필선 톤.
# 셰이더 width는 오브젝트 공간이라 모델 native 스케일이 다르면 굵기가 제각각 된다
# (수녀님 리빌드로 native 높이 98→0.98 됐을 때 실측 확인). 그래서 노드 스케일을
# 확정한 뒤 set_outline_width(node, OUTLINE_WORLD / 스케일)로 나눠 넣는다.
const OUTLINE_WORLD := 0.002

# ── 외곽선 전역 스위치 (기본 off) ────────────────────────────────────
# 유저 판정: "윤곽선 넣어두니 너무 없어보여 없는 게 나아". inverted-hull 선을 마을 전반에서 끈다.
# 덤으로 "물체마다 선 굵기가 달라 보이던" 것도 같이 사라진다 — width가 **오브젝트 공간**이라
# 노드 배율에 그대로 비례했기 때문이고(같은 0.006이 배율 3.6짜리 표지판에선 화면상 3.6배),
# 배율로 나눠 넣던 보정 규약 자체가 필요 없어진다.
#
# 호출부(make_solid·load_glb·load_kit·_box/_cyl…)는 두께 인자를 그대로 넘긴 채 둔다 —
# **머티리얼 생산 지점 한 곳**에서만 차단하는 게 최소 diff이고, 되돌릴 땐 이 값만 true로 준다.
# next_pass가 null이면 패스 자체가 안 돌아 드로우콜도 같이 빠진다(= 그냥 안 보이게 하는 게 아니다).
const OUTLINE_ON := false

# 외곽선 머티리얼의 단일 생산 지점. 꺼져 있거나 두께 0이면 null(= next_pass 없음).
static func outline_mat(w: float) -> ShaderMaterial:
	if not OUTLINE_ON or w <= 0.0:
		return null
	var o := ShaderMaterial.new()
	o.shader = OUTLINE
	o.set_shader_parameter("width", w)
	return o

# GLB 로드해 툰 적용된 씬 반환 (실패시 null). tint = 개체 색조 곱(기본 흰=무변경)
static func load_glb(path: String, outline_width: float, tint := Color.WHITE) -> Node3D:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		push_error("GLB 로드 실패: " + path)
		return null
	var model := doc.generate_scene(state)
	apply(model, outline_width, tint)
	return model

# GLB에 딸려온 AnimationPlayer 찾기 (generate_scene이 루트 밑에 둠). 없으면 null
static func find_anim(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for c in node.get_children():
		var a := find_anim(c)
		if a != null:
			return a
	return null

static func apply(node: Node, outline_width: float, tint := Color.WHITE) -> void:
	if node is MeshInstance3D and node.mesh != null:
		var mesh: Mesh = node.mesh
		for i in mesh.get_surface_count():
			var orig: Material = node.get_active_material(i)
			if orig == null:
				orig = mesh.surface_get_material(i)
			var tex: Texture2D = null
			var col := Color(0.85, 0.82, 0.85)
			if orig is BaseMaterial3D:
				tex = orig.albedo_texture
				col = orig.albedo_color
			var mat := ShaderMaterial.new()
			mat.shader = TOON
			mat.set_shader_parameter("char_tint", tint)
			if tex != null:
				mat.set_shader_parameter("use_tex", true)
				mat.set_shader_parameter("albedo_tex", tex)
			else:
				mat.set_shader_parameter("albedo", col)
			mat.next_pass = outline_mat(outline_width)
			node.set_surface_override_material(i, mat)
	for c in node.get_children():
		apply(c, outline_width, tint)

# apply()가 깔아둔 외곽선 두께만 일괄 교체 (노드 스케일 확정 뒤 호출).
static func set_outline_width(node: Node, w: float) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		for i in mi.get_surface_override_material_count():
			var m := mi.get_surface_override_material(i) as ShaderMaterial
			if m != null and m.next_pass is ShaderMaterial:
				(m.next_pass as ShaderMaterial).set_shader_parameter("width", w)
	for c in node.get_children():
		set_outline_width(c, w)

# 단색 툰 머티리얼 (곡률 포함). 바닥·건물·NPC·작물 공용.
# 절차 조각의 머티리얼 단일 진입점 — **색이 곧 재질이다**. 목재 팔레트로 칠하는 박스·원통은
# 자동으로 나뭇결(wood.gdshader)을 받는다. 호출부를 하나씩 고치지 않는 이유: 목재는 문·울타리·
# 궤짝·풍차 날개·부두처럼 세 파일에 흩어져 있어서, 호출부마다 재질을 고르게 하면 새로 만드는
# 목재 조각이 조용히 민 갈색으로 빠진다. 팔레트 색이 곧 스위치면 그 누락이 불가능하다.
#
# 결 방향 = 그 조각의 **최장변**. 실제 제재목이 켜지는 방향이고, 짧은 변 쪽 마구리에 나이테가
# 동심원으로 뜬다. 원통은 호출부가 (지름, 높이, 지름)으로 넘긴다 = 축 방향 그대로.
static func solid_or_wood(color: Color, size: Vector3, outline_width := 0.0) -> ShaderMaterial:
	var ax := Vector3.RIGHT
	if size.y >= size.x and size.y >= size.z:
		ax = Vector3.UP
	elif size.z > size.x:
		ax = Vector3.BACK
	return _wood_or(color, ax, outline_width)

# 원통은 **크기와 무관하게** 결이 로컬 Y다 — CylinderMesh 축이 그렇다. 최장변 규칙을 그대로
# 쓰면 납작한 조각(수레바퀴 r0.36 × h0.1)이 가로축을 골라 마구리에 나이테가 안 뜬다.
# 그런데 바퀴야말로 통나무를 가로로 켠 조각이라 나이테가 제일 떠야 하는 자리다(Codex 지적).
static func solid_or_wood_cyl(color: Color, outline_width := 0.0) -> ShaderMaterial:
	return _wood_or(color, Vector3.UP, outline_width)

static func _wood_or(color: Color, axis: Vector3, outline_width: float) -> ShaderMaterial:
	if not (color.is_equal_approx(WOOD_C) or color.is_equal_approx(WOOD_D)):
		return make_solid(color, outline_width)
	return make_wood(color, outline_width, axis)

# 나뭇결 머티리얼. 추재(어두운 띠)는 색에서 파생한다 = 팔레트를 두 번 적지 않는다.
# 0.21(≒C_WOOD_D)로 시작했다가 화면 대비가 11%뿐이라 안 보여서 0.32로 올렸다 — 목재 조각들이
# 서로 이웃해 있어(문·문틀·울타리 기둥) 대비가 약하면 셋 다 한 덩어리로 읽힌다.
static func make_wood(color: Color, outline_width := 0.0, dir := Vector3.RIGHT) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = WOOD
	m.set_shader_parameter("wood_color", color)
	m.set_shader_parameter("ring_color", color.darkened(0.32))
	m.set_shader_parameter("grain_dir", dir)
	m.next_pass = outline_mat(outline_width)
	return m

# shadow_level = 0.0 은 **항등**이다(uniform을 아예 안 건드림 → 셰이더 전역 기본 0.55).
# 캐릭터·가구·식생·킷 소품이 이 셰이더를 전부 공유하므로 전역 기본은 손대지 않는다
# (sat_cap·val_gain·green_gate와 같은 규약).
#
# 레버를 **색에서 파생**시키는 이유는 나뭇결(solid_or_wood)과 같다: 벽토는 마을 탑·시계탑·
# 해변 오두막·표지판처럼 세 파일에 흩어져 있어서, 호출부마다 레버를 넘기게 하면 새로 짓는
# 벽 조각이 조용히 옛 포화 경로로 빠진다. 팔레트 색이 곧 스위치면 그 누락이 불가능하다.
# (발주는 make_solid에 선택 인자를 열라고 했는데, 그 모양이면 _box·_cyl·solid_or_wood·
#  _wood_or·beach._box_at까지 인자를 관통시켜야 하고 누락 통로는 그대로 남는다.)
static func make_solid(color: Color, outline_width := 0.0, shadow_level := 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TOON
	m.set_shader_parameter("albedo", color)
	var sl := shadow_level
	if sl <= 0.0 and color.is_equal_approx(CREAM_C):
		sl = WALL_SHADOW
	if sl > 0.0:
		m.set_shader_parameter("shadow_level", sl)
	m.next_pass = outline_mat(outline_width)
	return m

# 접지 그림자 판(곱셈 블렌드, 무충돌). r = 균일하게 어두운 코어 반경 — 판은 1.25r까지 깔고
# 그 사이가 페이드다(contact.gdshader core 0.8). 캐릭터·해변 소품 공용.
static func contact_shadow(r: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(r * 2.5, r * 2.5)
	pm.subdivide_width = 4   # 곡률이 정점 단위 — 4장이면 판 안쪽도 지면 곡선을 탄다
	pm.subdivide_depth = 4
	mi.mesh = pm
	var m := ShaderMaterial.new()
	m.shader = CONTACT
	mi.material_override = m
	return mi

# 트리 밖(스폰 전) 노드에도 안전 — global_transform 대신 로컬 변환 누적
static func aabb_of(node: Node, xform := Transform3D(), acc := AABB()) -> AABB:
	var t := xform
	if node is Node3D:
		t = xform * (node as Node3D).transform
	if node is VisualInstance3D:
		var b: AABB = t * node.get_aabb()
		acc = b if acc.size == Vector3.ZERO else acc.merge(b)
	for c in node.get_children():
		acc = aabb_of(c, t, acc)
	return acc

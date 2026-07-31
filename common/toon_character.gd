class_name ToonCharacter
extends RefCounted
# GLB 런타임 로드 + 툰셰이더 적용 (lookdev·player 공용). Godot 임포트 불필요.

const TOON := preload("res://lookdev/toon.gdshader")
const OUTLINE := preload("res://lookdev/outline.gdshader")

# 캐릭터 외곽선 두께의 단일 튜닝 레버 — 월드 단위(m). 연필선 톤.
# 셰이더 width는 오브젝트 공간이라 모델 native 스케일이 다르면 굵기가 제각각 된다
# (수녀님 리빌드로 native 높이 98→0.98 됐을 때 실측 확인). 그래서 노드 스케일을
# 확정한 뒤 set_outline_width(node, OUTLINE_WORLD / 스케일)로 나눠 넣는다.
const OUTLINE_WORLD := 0.002

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
			var o := ShaderMaterial.new()
			o.shader = OUTLINE
			o.set_shader_parameter("width", outline_width)
			mat.next_pass = o
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
static func make_solid(color: Color, outline_width := 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TOON
	m.set_shader_parameter("albedo", color)
	if outline_width > 0.0:
		var o := ShaderMaterial.new()
		o.shader = OUTLINE
		o.set_shader_parameter("width", outline_width)
		m.next_pass = o
	return m

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

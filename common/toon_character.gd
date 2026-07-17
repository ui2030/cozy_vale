class_name ToonCharacter
extends RefCounted
# GLB 런타임 로드 + 툰셰이더 적용 (lookdev·player 공용). Godot 임포트 불필요.

const TOON := preload("res://lookdev/toon.gdshader")
const OUTLINE := preload("res://lookdev/outline.gdshader")

# GLB 로드해 툰 적용된 씬 반환 (실패시 null)
static func load_glb(path: String, outline_width: float) -> Node3D:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		push_error("GLB 로드 실패: " + path)
		return null
	var model := doc.generate_scene(state)
	apply(model, outline_width)
	return model

static func apply(node: Node, outline_width: float) -> void:
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
		apply(c, outline_width)

static func aabb_of(node: Node, acc := AABB()) -> AABB:
	if node is VisualInstance3D:
		var b: AABB = node.global_transform * node.get_aabb()
		acc = b if acc.size == Vector3.ZERO else acc.merge(b)
	for c in node.get_children():
		acc = aabb_of(c, acc)
	return acc

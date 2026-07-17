extends Node3D
# 룩데브 씬 — 셀 셰이딩 + inverted-hull 외곽선 (DESIGN.md 11.5)
# lookdev/character/ 에 .glb 있으면 그걸 로드해 툰셰이더 적용(오토핏),
# 없으면 프리미티브. `godot --path . -- shot` 로 스크린샷 1장 후 종료.

const TOON := preload("res://lookdev/toon.gdshader")
const OUTLINE := preload("res://lookdev/outline.gdshader")
const CHAR_DIR := "res://lookdev/character"

func _ready() -> void:
	_setup_environment()
	_setup_light()

	var glb := _find_glb()
	if glb != "":
		_load_character(glb)
	else:
		_ground(30.0)
		_build_primitives()
		_fixed_camera()

	if "shot" in OS.get_cmdline_user_args():
		await _capture_and_quit()


# ── 캐릭터 GLB 로드 ─────────────────────────────────────────────
func _ground(sz: float) -> void:
	_add_mesh(PlaneMesh.new(), Vector3.ZERO, Color(0.62, 0.80, 0.52), 0.0, Vector2(sz, sz))


func _find_glb() -> String:
	var d := DirAccess.open(CHAR_DIR)
	if d == null:
		return ""
	for f in d.get_files():
		if f.to_lower().ends_with(".glb") or f.to_lower().ends_with(".gltf"):
			return CHAR_DIR + "/" + f
	return ""


func _load_character(path: String) -> void:
	# 런타임 glTF 로드 (Godot 임포트 불필요 — 드롭한 파일 바로 사용)
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		push_error("GLB 로드 실패: " + path)
		_build_primitives(); _fixed_camera(); return
	var model := doc.generate_scene(state)
	add_child(model)

	var box := _aabb_of(model)
	# 바닥에 앉히고 중앙 정렬
	model.position -= Vector3(box.get_center().x, box.position.y, box.get_center().z)
	var size := box.size.length()
	_ground(maxf(box.size.x, box.size.z) * 2.5)  # 모델 크기 비례 바닥
	_apply_toon_recursive(model, max(size * 0.004, 0.003))  # 외곽선 두께 = 모델 크기 비례
	_frame_camera(Vector3(0, box.size.y * 0.5, 0), size)
	print("character loaded: ", path, "  size=", box.size)


func _aabb_of(node: Node, acc := AABB()) -> AABB:
	if node is VisualInstance3D:
		var b: AABB = node.get_aabb()
		b = node.global_transform * b
		acc = b if acc.size == Vector3.ZERO else acc.merge(b)
	for c in node.get_children():
		acc = _aabb_of(c, acc)
	return acc


func _apply_toon_recursive(node: Node, outline_w: float) -> void:
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
			o.set_shader_parameter("width", outline_w)
			mat.next_pass = o
			node.set_surface_override_material(i, mat)
	for c in node.get_children():
		_apply_toon_recursive(c, outline_w)


# ── 프리미티브 폴백 ─────────────────────────────────────────────
func _build_primitives() -> void:
	var body := CapsuleMesh.new()
	body.radius = 0.45; body.height = 1.6
	_add_mesh(body, Vector3(-1.2, 0.8, 0.0), Color(0.86, 0.55, 0.66))
	var head := SphereMesh.new()
	head.radius = 0.55; head.height = 1.1
	_add_mesh(head, Vector3(-1.2, 1.95, 0.0), Color(0.98, 0.86, 0.78))
	for i in 3:
		var crop := SphereMesh.new()
		crop.radius = 0.35; crop.height = 0.7
		_add_mesh(crop, Vector3(0.6 + i * 0.9, 0.35, 0.4), Color(0.95, 0.62, 0.42))
	var box := BoxMesh.new()
	box.size = Vector3(0.9, 0.9, 0.9)
	_add_mesh(box, Vector3(1.4, 0.45, -1.3), Color(0.72, 0.52, 0.36))


func _toon_material(base: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TOON
	m.set_shader_parameter("albedo", base)
	var o := ShaderMaterial.new()
	o.shader = OUTLINE
	m.next_pass = o
	return m


func _add_mesh(mesh: Mesh, pos: Vector3, color: Color, _unused := 0.0, plane_size := Vector2.ZERO) -> void:
	if mesh is PlaneMesh and plane_size != Vector2.ZERO:
		mesh.size = plane_size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	var mat := _toon_material(color)
	if mesh is PlaneMesh:
		mat.next_pass = null  # 바닥 외곽선 없음
	mi.material_override = mat
	add_child(mi)


# ── 카메라 ─────────────────────────────────────────────────────
func _fixed_camera() -> void:
	_frame_camera(Vector3(0, 0.9, 0), 6.5)


func _frame_camera(target: Vector3, size: float) -> void:
	var cam := Camera3D.new()
	cam.fov = 32.0
	add_child(cam)
	var dist: float = max(size * 1.5, 2.0)
	var dir := Vector3(0.9, 0.75, 0.9).normalized()
	cam.look_at_from_position(target + dir * dist, target, Vector3.UP)


func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.93, 0.90, 0.85)  # 따뜻한 오프화이트
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.76, 0.82)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _setup_light() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -125, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)


func _capture_and_quit() -> void:
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("res://lookdev/shots")
	img.save_png("res://lookdev/shots/lookdev.png")
	print("saved lookdev/shots/lookdev.png")
	get_tree().quit()

extends Node3D
# 룩데브 씬 — 셀 셰이딩 + inverted-hull 외곽선 실물 확인 (DESIGN.md 11.5)
# 지오메트리를 런타임에 구성 (.tscn 손편집보다 안정적).
# `godot --path . -- shot` 로 실행하면 스크린샷 1장 저장 후 종료.

const TOON := preload("res://lookdev/toon.gdshader")
const OUTLINE := preload("res://lookdev/outline.gdshader")

func _ready() -> void:
	_setup_environment()
	_setup_camera()
	_setup_light()

	# 바닥 (파스텔 연두)
	_add_mesh(PlaneMesh.new(), Vector3.ZERO, Color(0.62, 0.80, 0.52), 0.0, Vector2(16, 16))

	# 캐릭터 스탠드인: 몸통 캡슐 + 머리 구
	var body := CapsuleMesh.new()
	body.radius = 0.45
	body.height = 1.6
	_add_mesh(body, Vector3(-1.2, 0.8, 0.0), Color(0.86, 0.55, 0.66))
	var head := SphereMesh.new()
	head.radius = 0.55
	head.height = 1.1
	_add_mesh(head, Vector3(-1.2, 1.95, 0.0), Color(0.98, 0.86, 0.78))

	# 작물 스탠드인: 구 3개 (심긴 밭 느낌)
	for i in 3:
		var crop := SphereMesh.new()
		crop.radius = 0.35
		crop.height = 0.7
		_add_mesh(crop, Vector3(0.6 + i * 0.9, 0.35, 0.4), Color(0.95, 0.62, 0.42))

	# 상자 (판매 상자 톤 확인)
	var box := BoxMesh.new()
	box.size = Vector3(0.9, 0.9, 0.9)
	_add_mesh(box, Vector3(1.4, 0.45, -1.3), Color(0.72, 0.52, 0.36))

	if "shot" in OS.get_cmdline_user_args():
		await _capture_and_quit()


func _toon_material(base: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TOON
	m.set_shader_parameter("albedo", base)
	var o := ShaderMaterial.new()
	o.shader = OUTLINE
	m.next_pass = o
	return m


func _add_mesh(mesh: Mesh, pos: Vector3, color: Color, outline_scale := 1.0, plane_size := Vector2.ZERO) -> void:
	if mesh is PlaneMesh and plane_size != Vector2.ZERO:
		mesh.size = plane_size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	var mat := _toon_material(color)
	# 바닥은 외곽선 불필요
	if mesh is PlaneMesh:
		mat.next_pass = null
	mi.material_override = mat
	add_child(mi)


func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.70, 0.85, 0.92)  # 하늘색 배경
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.60, 0.72)
	env.ambient_light_energy = 0.9  # 그림자 밴드가 순검정 안 되게
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC  # 11.5
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _setup_camera() -> void:
	var cam := Camera3D.new()
	cam.position = Vector3(5.5, 5.5, 5.5)
	cam.look_at(Vector3(0, 0.9, 0), Vector3.UP)
	cam.fov = 32.0  # 쿼터뷰 왜곡 줄임
	add_child(cam)


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

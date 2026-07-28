extends Node3D
# 수녀 NPC 물리 테스트 씬 — SpringBoneSimulator3D 로 베일/치마/펜던트 출렁임.
#   실행:  godot --path . lookdev/nun_physics.tscn -- shot   (스크린샷 3장 후 종료)
# setup_springs()는 게임 NPC 코드에서 재사용 가능한 static 함수.
const Toon := preload("res://common/toon_character.gd")  # class_name 아닌 preload 참조
const TWOSIDED := preload("res://lookdev/toon_twosided.gdshader")  # 급회전 시 치마 안쪽 검게 뒤집힘 방지

const GLB := "res://assets/nun.glb"   # 게임이 쓰는 실물과 같은 파일로 검증
const SHOT_DIR := "C:/Users/ui2030/Documents/cozy-vale/lookdev/shots/수녀님/renders/재조립_v2/pose/"
var shot_prefix := ""  # "before_" / "after_" via 3rd cmdline user arg

var model: Node3D
var skel: Skeleton3D

# ── 재사용 가능한 스프링 설정 ────────────────────────────────────
# 치비 캐릭터 → 무거운 천 느낌: 높은 stiffness/drag, 작은 gravity (모델된 드레이프 유지)
static func _sphere(skel_: Skeleton3D, bone: String, off: Vector3, r: float) -> void:
	var s := SpringBoneCollisionSphere3D.new()
	s.radius = r
	skel_.add_child(s)
	s.set_bone_name(bone)
	s.set_position_offset(off)

static func _capsule(skel_: Skeleton3D, bone: String, off: Vector3, r: float, h: float) -> void:
	var c := SpringBoneCollisionCapsule3D.new()
	c.radius = r; c.height = h
	skel_.add_child(c)
	c.set_bone_name(bone)
	c.set_position_offset(off)

static func setup_springs(sk: Skeleton3D) -> SpringBoneSimulator3D:
	# 충돌체(머리·가슴·골반·다리) — 옷이 몸을 뚫지 않게
	_sphere(sk, "Head", Vector3(0, 0.02, 0), 0.14)
	_sphere(sk, "Spine02", Vector3(0, 0.0, 0), 0.10)  # 정합 조립 후 드레스 슬림화에 맞춤
	_sphere(sk, "Pelvis", Vector3(0, 0.0, 0), 0.10)
	_capsule(sk, "Pelvis", Vector3(0, -0.18, 0), 0.09, 0.42)  # 다리 볼륨
	# 다리 충돌구 — 걷기 시 스윙하는 다리가 치마/프릴을 앞서 밀어내 발 관통 방지.
	# Pelvis 캡슐은 하퇴·발 높이까지 안 닿아, 다리가 앞으로 나가면 프릴에 콜라이더가 없었음.
	# 정적 ±30° 포즈 A/B에선 차이 미미했으나(치마 물리본 2개라 발높이 장벽 약함) 무해하고
	# 게임 각도에서 발은 프릴 아래로만 노출돼 합격. 동적 보행 시 스윙 다리 밀어냄 기대.
	for lb in ["L_Thigh", "R_Thigh"]:
		_sphere(sk, lb, Vector3.ZERO, 0.07)
	for lb in ["L_Calf", "R_Calf"]:
		_sphere(sk, lb, Vector3.ZERO, 0.06)
	for lb in ["L_Foot", "R_Foot"]:
		_sphere(sk, lb, Vector3.ZERO, 0.05)
	# 어깨 충돌구 — 베일 옆/뒷자락이 급회전·스냅백 시 몸통·얼굴로 파고들지 않게.
	for cb in ["L_Clavicle", "R_Clavicle"]:
		_sphere(sk, cb, Vector3.ZERO, 0.08)

	# 체인: [root, end, stiffness, drag, gravity, joint_radius]
	# 베일 복원(2026-07-22): Blender에서 5줄을 각 4~5본으로 세분(veil_XX_01..04/05).
	# 세분 전엔 줄당 본 2개라 자락 하반부가 _02에 강체 스키닝 → 스윙 시 판자로 꺾이고 음영 깨짐.
	# 이제 하반부까지 관절이 이어져 연속 곡면 굽힘. gravity 미소로 드레이프 복귀.
	var chains: Array = []
	for tag in ["F", "FL", "L", "BL", "B", "BR", "R", "FR"]:
		chains.append(["skirt_%s_01" % tag, "skirt_%s_02" % tag, 0.62, 0.70, 0.002, 0.025])
	# 베일: BC/BL/BR 5본(_05), FL/FR 4본(_04)
	# stiffness는 치마(0.62)와 동급으로 — 자락이 넓은 시트라 너무 낮으면 급회전 시
	# 시트가 급각도로 접혀 자기교차+검은 음영. drag 높여 오버슈트 링잉 억제.
	for tag in ["BC", "BL", "BR"]:
		chains.append(["veil_%s_01" % tag, "veil_%s_05" % tag, 0.60, 0.72, 0.003, 0.020])
	for tag in ["FL", "FR"]:
		chains.append(["veil_%s_01" % tag, "veil_%s_04" % tag, 0.62, 0.72, 0.003, 0.020])
	chains.append(["pendant_01", "pendant_01", 0.55, 0.60, 0.004, 0.015])

	var sim := SpringBoneSimulator3D.new()
	sim.name = "NunSprings"
	sk.add_child(sim)
	sim.setting_count = chains.size()
	for i in chains.size():
		var c: Array = chains[i]
		sim.set_root_bone_name(i, c[0])
		sim.set_end_bone_name(i, c[1])
		sim.set_extend_end_bone(i, true)
		sim.set_end_bone_length(i, 0.04)
		sim.set_stiffness(i, c[2])
		sim.set_drag(i, c[3])
		sim.set_gravity(i, c[4])
		sim.set_gravity_direction(i, Vector3(0, -1, 0))
		sim.set_radius(i, c[5])
		sim.set_enable_all_child_collisions(i, true)
	return sim

# ── 씬 ───────────────────────────────────────────────────────────
# toon 머티리얼을 양면 변형으로 교체(파라미터·외곽선 next_pass 유지). 얇은 천 관통면 검정 방지.
static func _make_twosided(node: Node) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mi := node as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var m := mi.get_surface_override_material(i)
			if m is ShaderMaterial:
				(m as ShaderMaterial).shader = TWOSIDED
	for c in node.get_children():
		_make_twosided(c)

static func _find(node: Node, cls) -> Node:
	if is_instance_of(node, cls):
		return node
	for c in node.get_children():
		var r := _find(c, cls)
		if r: return r
	return null

func _ready() -> void:
	_environment(); _light()
	model = Toon.load_glb(GLB, 0.004)
	if model == null:
		push_error("nun.glb 로드 실패"); return
	add_child(model)
	_make_twosided(model)
	skel = _find(model, Skeleton3D) as Skeleton3D
	if skel == null:
		push_error("Skeleton3D 없음")
	else:
		print("bones=", skel.get_bone_count(), " springs setup")
		setup_springs(skel)
	_camera()
	if "walk" in OS.get_cmdline_user_args():
		_run_walk()
	elif "shot" in OS.get_cmdline_user_args():
		_run_shot()

var main_cam: Camera3D

func _camera() -> void:
	main_cam = Camera3D.new()
	main_cam.fov = 34.0
	add_child(main_cam)
	main_cam.look_at_from_position(Vector3(1.25, 0.6, 1.95), Vector3(0, 0.46, 0), Vector3.UP)

func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.56, 0.62)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.78, 0.84)
	env.ambient_light_energy = 0.78
	var we := WorldEnvironment.new(); we.environment = env
	add_child(we)

func _light() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -120, 0)
	sun.light_energy = 1.1
	add_child(sun)
	# 정면 필 라이트 — 베일 그림자에 눈이 묻히지 않게 얼굴 밝힘
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18, -8, 0)
	fill.light_energy = 0.85
	add_child(fill)

func _run_shot() -> void:
	var uargs := OS.get_cmdline_user_args()
	for a in uargs:
		if a == "before" or a == "after":
			shot_prefix = a + "_"
	# 게임 카메라(하향 약 34°, fov 48) — 베일 얼굴 가림·스윙 지연 검증용
	var gcam := Camera3D.new(); gcam.fov = 48.0; add_child(gcam)
	gcam.look_at_from_position(Vector3(0.0, 1.34, 1.33), Vector3(0.0, 0.45, 0.0), Vector3.UP)
	# 탑뷰(위에서 수직 내려봄) — 목걸이가 닫힌 고리인지 확인
	var tcam := Camera3D.new(); tcam.fov = 30.0; add_child(tcam)
	tcam.look_at_from_position(Vector3(0.0, 2.05, -0.001), Vector3(0.0, 0.55, 0.0), Vector3(0, 0, -1))
	# 순측면(정확히 옆) — 체인이 목 뒤로 도는지, 베일 공기층 확인
	var pcam := Camera3D.new(); pcam.fov = 26.0; add_child(pcam)
	pcam.look_at_from_position(Vector3(1.9, 0.62, 0.0), Vector3(0.0, 0.58, 0.0), Vector3.UP)
	# 안정화
	for i in 40: await get_tree().physics_frame
	main_cam.make_current(); await _cap("nun_god_rest")
	gcam.make_current(); await _cap("nun_god_rest_game")
	tcam.make_current(); await _cap("nun_top")
	pcam.make_current(); await _cap("nun_pureside")
	# 얼굴 정면 클로즈업 — 감은 눈·속눈썹 노출 검증(#1)
	var fcam := Camera3D.new(); fcam.fov = 22.0; add_child(fcam)
	fcam.look_at_from_position(Vector3(0, 1.02, 0.78), Vector3(0, 0.70, 0.02), Vector3.UP)  # 위-앞에서 내려봄(코지 게임 시점)
	fcam.make_current()
	await _cap("nun_god_face")
	# 측면 클로즈업 — 목걸이 체인이 가슴 표면에 밀착됐는지 프로필 검증
	var scam := Camera3D.new(); scam.fov = 30.0; add_child(scam)
	scam.look_at_from_position(Vector3(1.45, 0.60, 0.42), Vector3(0.0, 0.50, 0.02), Vector3.UP)
	scam.make_current()
	await _cap("nun_god_side")
	scam.queue_free()
	fcam.queue_free()
	# 요(yaw) 임펄스: 60도까지 휘둘렀다가 0으로 스냅 → 오버슈트로 출렁임 유도
	for i in range(12):
		model.rotation.y = deg_to_rad(60.0) * float(i) / 12.0
		await get_tree().physics_frame
	main_cam.make_current(); await _cap("nun_god_swing")   # 회전 정점 — 베일/치마 뒤따름
	gcam.make_current(); await _cap("nun_god_swing_game")  # 게임각도: 얼굴 가림 검증(#4)
	model.rotation.y = 0.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	main_cam.make_current(); await _cap("nun_god_overshoot")  # 스냅백 직후 — 관성 출렁임
	gcam.make_current(); await _cap("nun_god_overshoot_game")
	for i in 10: await get_tree().physics_frame
	main_cam.make_current(); await _cap("nun_god_settle")
	get_tree().quit()

func _swing_thigh(bname: String, deg: float, axis: Vector3) -> void:
	var idx := skel.find_bone(bname)
	if idx < 0:
		push_error("no bone " + bname); return
	var rq := skel.get_bone_rest(idx).basis.get_rotation_quaternion()
	skel.set_bone_pose_rotation(idx, rq * Quaternion(axis, deg_to_rad(deg)))

# 걷기 중간 스텝 FK 포즈 — 발이 프릴을 뚫는지 검증(다리 콜라이더 효과 확인)
func _run_walk() -> void:
	var ax := Vector3(1, 0, 0)
	_swing_thigh("L_Thigh", 30.0, ax)   # 왼다리 앞 (발주 스펙 ±30°)
	_swing_thigh("R_Thigh", -22.0, ax)  # 오른다리 뒤
	for i in 50: await get_tree().physics_frame
	await _cap("nun_walk_front")
	# 전측면 로우앵글 — 앞발이 프릴을 뚫는지 가장 잘 보임
	var scam := Camera3D.new(); scam.fov = 34.0; add_child(scam)
	scam.look_at_from_position(Vector3(0.7, 0.22, 1.15), Vector3(0.0, 0.16, 0.0), Vector3.UP)
	scam.make_current()
	await _cap("nun_walk_lowside")
	# 게임 카메라 각도(하향 약 34°, fov 48)
	var gcam := Camera3D.new(); gcam.fov = 48.0; add_child(gcam)
	gcam.look_at_from_position(Vector3(0.0, 1.34, 1.33), Vector3(0.0, 0.45, 0.0), Vector3.UP)
	gcam.make_current()
	await _cap("nun_walk_game")
	get_tree().quit()

func _cap(nm: String) -> void:
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(SHOT_DIR + shot_prefix + nm + ".png")
	print("shot ", shot_prefix + nm)

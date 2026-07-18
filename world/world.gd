extends Node3D
# A단계 월드 루트. 환경/조명 세팅 + 세이브 로드.

const ToonChar := preload("res://common/toon_character.gd")

@onready var _sun: DirectionalLight3D = $Sun

func _ready() -> void:
	_sun.rotation_degrees = Vector3(-52, -125, 0)
	_add_env()
	_convert_statics(self)  # 정적 물체(바닥·건물)를 곡면 툰으로 통일
	if not SaveManager.load_game():
		print("새 게임 시작")
	# from_dict는 신호를 안 쏘므로 로드된 시각으로 축제 배치를 즉시 재평가 (축제날 아침 로드 누락 방지)
	if "festival" in OS.get_cmdline_user_args():  # 스크린샷 검증용 강제 축제
		GameClock.abs_day = 14   # spring D15
		GameClock.game_min = 720  # 12:00
		var pl := get_tree().get_first_node_in_group("player")
		if pl != null:  # 광장이 카메라에 잡히도록 플레이어를 광장 근처로
			pl.global_position = Vector3(0, 2, 0)
	get_tree().call_group("festival_system", "evaluate")
	if "pausemenu" in OS.get_cmdline_user_args():  # 스크린샷 검증용 메뉴 열기
		get_tree().call_group("pause_menu", "open_menu")
	if "bedshot" in OS.get_cmdline_user_args():  # 스크린샷 검증용: 침대 옆(프롬프트+라벨)
		var pb := get_tree().get_first_node_in_group("player")
		if pb != null:
			pb.global_position = Vector3(3.6, 2, 0)
	if "pond" in OS.get_cmdline_user_args():  # 검증용: 연못 물가(낚시 프롬프트)
		var pp := get_tree().get_first_node_in_group("player")
		if pp != null:
			pp.global_position = Vector3(10, 2, 3.8)
	if "fishing" in OS.get_cmdline_user_args():  # 검증용: 낚시 미니게임 열린 상태
		var pf := get_tree().get_first_node_in_group("player")
		if pf != null:
			pf.global_position = Vector3(10, 2, 3.8)
		var fg := get_tree().get_first_node_in_group("fishing")
		if fg != null:
			fg.start("fish.bluegill", 0.4)
	if "collection" in OS.get_cmdline_user_args():  # 검증용: 도감 패널(일부 발견)
		var pc := get_tree().get_first_node_in_group("player")
		if pc != null:
			pc.collection = ["crop.turnip", "crop.cabbage", "fish.carp", "forage.dandelion"]
		var cp := get_tree().get_first_node_in_group("collection_panel")
		if cp != null:
			cp.visible = true
			cp._rebuild()

# StandardMaterial3D 정적 메시 → 곡면 툰 (투명물=조준칸 제외)
func _convert_statics(node: Node) -> void:
	if node is MeshInstance3D:
		var m = node.material_override
		if m is StandardMaterial3D and m.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
			node.material_override = ToonChar.make_solid(m.albedo_color, 0.0)
	for c in node.get_children():
		_convert_statics(c)

	if "shot" in OS.get_cmdline_user_args():
		await _shot()

func _shot() -> void:
	# 플레이어 착지 + 시계 진행 후 촬영
	GameClock.state = GameClock.State.FAST
	await get_tree().create_timer(1.5).timeout
	if "walkshot" in OS.get_cmdline_user_args():  # 검증용: 걷기 스트라이드 프레임 고정
		var pw := get_tree().get_first_node_in_group("player")
		if pw != null and pw._anim != null and pw._anim.has_animation("walk"):
			pw.set_physics_process(false)  # 정지 중 idle 덮어쓰기 차단
			pw._face_dir(Vector3(1, 0, 0))  # +X 향해 측면 프로필
			pw._anim.play("walk")
			pw._anim.seek(0.35, true)  # 스트라이드 중간 프레임
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("res://lookdev/shots")
	img.save_png("res://lookdev/shots/world.png")
	print("saved world.png  clock=", GameClock.hour(), ":", GameClock.minute())
	get_tree().quit()

func _add_env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.93, 0.90, 0.85)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.76, 0.82)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

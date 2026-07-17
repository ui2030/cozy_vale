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

extends Node3D
# A단계 월드 루트. 환경/조명 세팅 + 세이브 로드.

@onready var _sun: DirectionalLight3D = $Sun

func _ready() -> void:
	_sun.rotation_degrees = Vector3(-52, -125, 0)
	_add_env()
	if not SaveManager.load_game():
		print("새 게임 시작")

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

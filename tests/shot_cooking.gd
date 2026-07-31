extends Node
# H-3(요리) 스크린샷 하네스. 창 있는 실행 전용 — 헤드리스는 캡처 불가.
#   godot --path . res://tests/shot_cooking.tscn -- prompt|panel|toast|bag
# shot_crops.gd와 같은 수법: 배치·촬영을 tests/에 두어 게임 코드에 검증 훅을 더 얹지 않는다.
# 유저 세이브는 SaveManager.suspended로 막고, 셸에서도 백업/복원한다.

const SHOT_DIR := "res://lookdev/shots/cooking_h3/"
const I := preload("res://world/interior.gd")

func _ready() -> void:
	SaveManager.suspended = true
	add_child(preload("res://world/world.tscn").instantiate())
	_run.call_deferred()

func _run() -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var what: String = args[0] if args.size() > 0 else "prompt"
	GameClock.abs_day = GameClock.DAYS_PER_SEASON  # 결정적 컷(여름 D1) — 실내라 계절 자체는 그림에 안 나온다
	GameClock.game_min = 11 * 60  # 낮 = 실내등 꺼짐, 창으로 들어오는 빛
	GameClock.state = GameClock.State.PAUSED
	var player := get_tree().get_first_node_in_group("player")
	player.global_position = I.STOVE_AT + Vector3(0, 0, 1.4)  # 스토브 앞
	player._face_dir(Vector3(0, 0, -1))                       # 부엌(북)을 본다
	# 재료를 일부만 채운다 — "만들 수 있는 행 / 재료 모자란 행"이 한 컷에 같이 보이게
	for r in [["crop.turnip", 2], ["crop.cabbage", 1], ["crop.strawberry", 2],
			["crop.tomato", 1], ["forage.leek", 1]]:
		player._add_item(r[0], r[1])
	await get_tree().create_timer(1.5).timeout  # 착지 + 조명 안정
	match what:
		"panel":
			player._try_interact()   # 스토브 = 요리 패널
		"toast":
			player._try_interact()
			await get_tree().process_frame
			player.cook("dish.salad")  # 완성 토스트 + 행 갱신
			await get_tree().create_timer(0.3).timeout
		"bag":
			player.cook("dish.salad")
			player.cook("dish.jam")
			var ip := get_tree().get_first_node_in_group("inventory_panel")
			ip.visible = true
			ip._rebuild()
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	img.save_png(SHOT_DIR + what + ".png")
	print("saved ", SHOT_DIR, what, ".png  prompt='", player.interact_prompt(), "'")
	get_tree().quit()

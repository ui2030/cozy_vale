extends Node
# H-1(작물 12종) 스크린샷 하네스. 창 있는 실행 전용 — 헤드리스는 캡처 불가.
#   godot --path . res://tests/shot_crops.tscn -- shop|shopseeds|farm
# world.gd에 검증 훅을 더 얹지 않으려고 배치·촬영을 여기서 한다(쓰기 범위 = tests/).
# 유저 세이브는 SaveManager.suspended로 막고, 셸에서도 백업/복원한다.

const SHOT_DIR := "res://lookdev/shots/crops_h1/"

func _ready() -> void:
	SaveManager.suspended = true  # world._ready의 로드는 읽기 전용, 이후 쓰기는 전면 차단
	add_child(preload("res://world/world.tscn").instantiate())
	_run.call_deferred()

func _run() -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var what: String = args[0] if args.size() > 0 else "farm"
	# 맑은 평일 정오 (비 오는 컷·상점 휴무 회피). winter 샷만 겨울, 나머지는 여름.
	var first: int = 84 if what == "winter" else 28
	for d in range(first, first + 28):
		GameClock.abs_day = d
		if not GameData.is_rainy(d) and GameClock.weekday() != 6:
			break
	# 상점 컷은 아침 8시 — 정오엔 주민이 상점 앞에 서서 프롬프트가 대화로 먹힌다(가장 가까운 대상 판정).
	GameClock.game_min = (12 * 60) if what == "farm" else (8 * 60)
	var player := get_tree().get_first_node_in_group("player")
	player.gold = 500
	match what:
		"farm":
			_plant_showcase()
			player.global_position = Vector3(2.5, 2, 6.2)  # 밭 서쪽에 비켜서 작물을 가리지 않게
			player._face_dir(Vector3(0, 0, -1))
			# 추종 카메라를 세우고 밭을 내려다보게 수동 배치(world.gd의 여백 샷과 같은 수법).
			# 플레이어 집이 밭 바로 남쪽이라 기본 추종 위치(+Z 9.5)는 집 안으로 들어간다.
			var cam: Camera3D = find_child("Camera", true, false)
			cam.set_process(false)
			cam.global_position = Vector3(5.5, 7.0, 11.0)
			cam.look_at(Vector3(5.5, 0.3, 4.0), Vector3.UP)
		"shopseeds":
			player.global_position = Vector3(-5, 2, -3.4)
			player._face_dir(Vector3(0, 0, -1))
			player._add_item("seed.tomato", 2)   # 이번 계절 보유
			player._add_item("seed.turnip", 1)   # 철 지난 보유분도 목록에 남는지 확인용
			_open_bag()
		"winter":
			player.global_position = Vector3(-5, 2, -3.4)  # 겨울 상점: 재고 0 처리 확인
			player._face_dir(Vector3(0, 0, -1))
			_open_bag()
		_:  # shop — 상점 프롬프트 + 실제 구매 토스트
			player.global_position = Vector3(-5, 2, -3.4)
			player._face_dir(Vector3(0, 0, -1))
	await get_tree().create_timer(1.5).timeout  # 착지 + 조명·물 셰이더 안정
	if what == "shop" or what == "winter":
		player._buy_seed()  # 여름 = 제철 씨앗 구매 성공 / 겨울 = 재고 없음 안내
		await get_tree().create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	img.save_png(SHOT_DIR + what + ".png")
	print("saved ", SHOT_DIR, what, ".png  season=", GameData.season_id(GameClock.season()),
		" day=", GameClock.day_of_season(), " rain=", GameData.is_rainy(GameClock.abs_day))
	get_tree().quit()

func _open_bag() -> void:
	var panel := get_tree().get_first_node_in_group("inventory_panel")
	panel.visible = true
	panel._rebuild()

# 여름 밭 진열: 성장 중 / 다 자람을 나란히 두고 작물별 색을 한 컷에 담는다.
func _plant_showcase() -> void:
	var farm := get_tree().get_first_node_in_group("farm")
	for r in [  # [칸, 씨앗, 물 준 성장일] — grow_days 도달 = 성숙
		[Vector2i(4, 5), "seed.tomato", 2], [Vector2i(5, 5), "seed.tomato", 7],
		[Vector2i(6, 5), "seed.pepper", 5], [Vector2i(7, 5), "seed.watermelon", 12],
		[Vector2i(4, 4), "seed.corn", 4], [Vector2i(5, 4), "seed.corn", 9],
		[Vector2i(6, 4), "seed.watermelon", 6], [Vector2i(7, 4), "seed.pepper", 2],
	]:
		var cell: Vector2i = r[0]
		farm.till(cell)
		farm.plant(cell, r[1])
		farm.tiles[cell]["watered_growth_days"] = int(r[2])
		farm.tiles[cell]["watered"] = true
		farm._refresh(cell)

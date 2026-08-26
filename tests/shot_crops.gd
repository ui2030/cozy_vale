extends Node
# H-1(작물 12종) 스크린샷 하네스. 창 있는 실행 전용 — 헤드리스는 캡처 불가.
#   godot --path . res://tests/shot_crops.tscn -- shop|shopseeds|farm
# world.gd에 검증 훅을 더 얹지 않으려고 배치·촬영을 여기서 한다(쓰기 범위 = tests/).
# 유저 세이브는 SaveManager.suspended로 막고, 셸에서도 백업/복원한다.

const SHOT_DIR := "res://lookdev/shots/crops_h1/"
const FARM_DIR := "res://lookdev/shots/farm/"  # 채집물 재배·다년생 컷
# 모드 → 계절 인덱스. 없으면 여름.
const MODE_SEASON := {"winter": 3, "perennial": 2, "winter_farm": 2}
# 밭을 내려다보는 컷을 쓰는 모드
const FARM_MODES := ["farm", "forage_grow", "perennial", "winter_farm"]

func _ready() -> void:
	SaveManager.suspended = true  # world._ready의 로드는 읽기 전용, 이후 쓰기는 전면 차단
	add_child(preload("res://world/world.tscn").instantiate())
	_run.call_deferred()

func _run() -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var what: String = args[0] if args.size() > 0 else "farm"
	# 맑은 평일 정오 (비 오는 컷·상점 휴무 회피).
	var first: int = int(MODE_SEASON.get(what, 1)) * GameClock.DAYS_PER_SEASON
	if what == "winter_farm":
		first = 3 * GameClock.DAYS_PER_SEASON - 1  # 가을 막날에 심고 겨울로 넘긴다
	for d in range(first, first + GameClock.DAYS_PER_SEASON):
		GameClock.abs_day = d
		if not GameData.is_rainy(d) and GameClock.weekday() != 6:
			break
	if what == "winter_farm":
		GameClock.abs_day = 3 * GameClock.DAYS_PER_SEASON - 1  # 위 루프 무시(파종일은 고정)
	# 상점 컷은 아침 8시 — 정오엔 주민이 상점 앞에 서서 프롬프트가 대화로 먹힌다(가장 가까운 대상 판정).
	GameClock.game_min = (12 * 60) if what in FARM_MODES else (8 * 60)
	var player := get_tree().get_first_node_in_group("player")
	player.gold = 500
	match what:
		"farm", "forage_grow", "perennial", "winter_farm":
			match what:
				"farm": _plant_showcase()
				"forage_grow": _forage_showcase()
				"perennial": _perennial_showcase()
				"winter_farm": _winter_farm_showcase()
			player.global_position = Vector3(2.5, 2, 6.2)  # 밭 서쪽에 비켜서 작물을 가리지 않게
			player._face_dir(Vector3(0, 0, -1))
			# 추종 카메라를 세우고 밭을 내려다보게 수동 배치(world.gd의 여백 샷과 같은 수법).
			# 플레이어 집이 밭 바로 남쪽이라 기본 추종 위치(+Z 9.5)는 집 안으로 들어간다.
			var cam: Camera3D = find_child("Camera", true, false)
			cam.set_process(false)
			cam.global_position = Vector3(5.5, 7.0, 11.0)
			cam.look_at(Vector3(5.5, 0.3, 4.0), Vector3.UP)
			if what != "farm":
				# 채집물 재배 컷은 종을 색으로 가려야 하므로 더 바짝 붙는다. 플레이어는 밭 서쪽
				# 밖으로 빼서 앞줄(x1~)을 안 가리게 한다 — 기존 farm 컷 구도는 그대로 둔다.
				player.global_position = Vector3(-1.5, 2, 6.5)
				cam.global_position = Vector3(4.0, 5.2, 10.6)
				cam.look_at(Vector3(4.0, 0.4, 4.6), Vector3.UP)
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
	var dir: String = FARM_DIR if what in ["forage_grow", "perennial", "winter_farm"] else SHOT_DIR
	DirAccess.make_dir_recursive_absolute(dir)
	img.save_png(dir + what + ".png")
	print("saved ", dir, what, ".png  season=", GameData.season_id(GameClock.season()),
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
		_place(farm, r[0], r[1], int(r[2]))

# 한 칸에 심고 성장일을 직접 놓는다(며칠을 실제로 돌리지 않고 단계를 진열하기 위한 하네스 수법).
func _place(farm: Node, cell: Vector2i, seed_id: String, days: int) -> void:
	farm.till(cell)
	if not farm.plant(cell, seed_id):
		push_error("심기 거부: %s @ %s (%s)" % [seed_id, cell, GameData.season_id(GameClock.season())])
		return
	farm.tiles[cell]["watered_growth_days"] = days
	farm.tiles[cell]["watered"] = true
	farm._refresh(cell)

# 그 계절에 심을 수 있는 **채집물 재배** 항목 (종 이름을 박지 않고 데이터에서 고른다)
func _forage_crops(sid: String, bearing: bool) -> Array:
	var out := []
	for cid in GameData.crops:
		if GameData.crop_yield(cid) == cid or not GameData.crop_plantable(cid, sid):
			continue
		if GameData.crop_in_season(cid, sid) == bearing:
			out.append(cid)
	return out

# 여름 밭: 채집물 재배 3종을 성장 중 / 다 자람으로 나란히 — 주운 걸 심으면 자란다는 컷.
func _forage_showcase() -> void:
	var farm := get_tree().get_first_node_in_group("farm")
	var ids := _forage_crops("summer", true)
	for i in ids.size():
		var cid: String = ids[i]
		var gd: int = GameData.grow_days(cid)
		# 낮은 성장 단계는 앞줄 울타리에 가리므로 뒷줄(z=4)에 둔다 — 같은 종을 세로로 짝지어 진열
		_place(farm, Vector2i(i + 1, 4), GameData.crops[cid]["seed_id"], maxi(1, gd / 3))  # 성장 중
		_place(farm, Vector2i(i + 1, 5), GameData.crops[cid]["seed_id"], gd)               # 다 자람
	# 대조군: 씨앗을 사서 심는 기존 작물도 같은 프레임에 (같은 밭의 어휘라는 걸 보이게)
	_place(farm, Vector2i(5, 5), "seed.tomato", 7)
	_place(farm, Vector2i(6, 5), "seed.pepper", 5)

# 가을 밭: 다년생이 열매를 맺은 상태 + 겨울에 열릴 다년생의 휴면(마른 갈색) 대조.
func _perennial_showcase() -> void:
	var farm := get_tree().get_first_node_in_group("farm")
	var bearing := _forage_crops("autumn", true)
	var dormant := _forage_crops("autumn", false)
	for i in bearing.size():
		var cid: String = bearing[i]
		_place(farm, Vector2i(i + 1, 5), GameData.crops[cid]["seed_id"], GameData.grow_days(cid))
	for j in dormant.size():
		var cid2: String = dormant[j]
		_place(farm, Vector2i(j + 1, 4), GameData.crops[cid2]["seed_id"], 0)  # 휴면 = 생장 0

# 겨울 밭: 가을에 심은 다년생만 남아 열린 상태. 한해살이(corn)는 계절 경계에서 실제로 고사시킨다
# — 값을 박지 않고 프로덕션 _season_deaths를 태워서 찍는 컷이다.
func _winter_farm_showcase() -> void:
	var farm := get_tree().get_first_node_in_group("farm")
	var winter_ids := _forage_crops("autumn", false)  # 가을에 심고 가을엔 안 열리는 것 = 겨울 다년생
	for i in winter_ids.size():
		_place(farm, Vector2i(i + 1, 5), GameData.crops[winter_ids[i]]["seed_id"], 0)
	_place(farm, Vector2i(5, 5), "seed.corn", 4)  # 한해살이 대조군 — 겨울로 넘어가며 사라져야 한다
	GameClock.sleep_to_morning()  # 가을 막날 → 겨울 D1 (여기서 고사·생존이 갈린다)
	while GameData.is_rainy(GameClock.abs_day):  # 맑은 겨울날까지 (비 오는 컷 회피)
		GameClock.sleep_to_morning()
	GameClock.game_min = 12 * 60
	for i2 in winter_ids.size():  # 겨울에 자란 만큼을 진열 (성숙 = 수확 가능)
		var cell := Vector2i(i2 + 1, 5)
		if farm.tiles.has(cell) and farm.tiles[cell]["crop_id"] != "":
			farm.tiles[cell]["watered_growth_days"] = GameData.grow_days(winter_ids[i2])
			farm.tiles[cell]["watered"] = true
	farm._refresh_all()

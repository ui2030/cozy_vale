extends Node
# H-1(작물 12종) 스크린샷 하네스. 창 있는 실행 전용 — 헤드리스는 캡처 불가.
#   godot --path . res://tests/shot_crops.tscn -- shop|shopseeds|farm
# world.gd에 검증 훅을 더 얹지 않으려고 배치·촬영을 여기서 한다(쓰기 범위 = tests/).
# 유저 세이브는 SaveManager.suspended로 막고, 셸에서도 백업/복원한다.

const SHOT_DIR := "res://lookdev/shots/crops_h1/"
const FARM_DIR := "res://lookdev/shots/farm/"  # 채집물 재배·다년생 컷
const CROP_DIR := "res://lookdev/shots/crops/"  # 작물 실물화 컷 (2026-08-26)
# 작물 컷 모드 → 계절. stages·ground는 여름 밭에서, winter는 가을에 심어 겨울로 넘긴다.
const CROP_SEASON := {"spring": 0, "summer": 1, "autumn": 2, "stages": 1, "ground": 1, "winter": 2}
# 진열 줄(앞→뒤) — 밭 REGION 기준 z 오프셋. 9종까지는 두 줄로 끝나게 ROW_MAX를 5로 둔다.
# (옛 판은 광장 포석이 밭 북서쪽을 덮어 "포장 위의 작물"로 찍혔다 — 밭을 광장 밖으로 옮겨
#  근본 수정했으므로 줄을 동쪽·남쪽으로 피해 놓던 회피값을 걷어냈다.)
const ROW_Z := [3, 2, 1]
const ROW_MAX := 5
const ROW_X0 := [2, 2, 2]   # 줄별 시작 칸(REGION 기준 x 오프셋) — 8칸 폭 가운데 5칸
# 모드 → 계절 인덱스. 없으면 여름.
const MODE_SEASON := {"winter": 3, "perennial": 2, "winter_farm": 2}
# 밭을 내려다보는 컷을 쓰는 모드
const FARM_MODES := ["farm", "forage_grow", "perennial", "winter_farm"]
const FarmScript := preload("res://farm/farm_system.gd")

# 하네스 좌표는 전부 밭 REGION 원점 기준 오프셋 — 밭을 옮겨도 컷 구도가 그대로 따라온다.
func _fcell(dx: int, dz: int) -> Vector2i:
	return FarmScript.REGION.position + Vector2i(dx, dz)

func _fx(off: float) -> float:
	return float(FarmScript.REGION.position.x) + off

func _fz(off: float) -> float:
	return float(FarmScript.REGION.position.y) + off

func _ready() -> void:
	SaveManager.suspended = true  # world._ready의 로드는 읽기 전용, 이후 쓰기는 전면 차단
	add_child(preload("res://world/world.tscn").instantiate())
	_run.call_deferred()

func _run() -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var what: String = args[0] if args.size() > 0 else "farm"
	if what == "crops":  # 작물 실물화 전용 구도 — 아래 기존 모드와 카메라가 통째로 다르다
		await _crops_shot(args[1] if args.size() > 1 else "summer",
			args[2] if args.size() > 2 else "after")
		return
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
			player.global_position = Vector3(_fx(-2.0), 2, _fz(1.5))  # 밭 서쪽에 비켜서 작물을 가리지 않게
			player._face_dir(Vector3(0, 0, -1))
			# 추종 카메라를 세우고 밭을 내려다보게 수동 배치(world.gd의 여백 샷과 같은 수법).
			# 플레이어 집이 밭 바로 남쪽이라 기본 추종 위치(+Z 9.5)는 집 안으로 들어간다.
			var cam: Camera3D = find_child("Camera", true, false)
			cam.set_process(false)
			cam.global_position = Vector3(_fx(5.5), 7.0, _fz(9.0))
			cam.look_at(Vector3(_fx(5.5), 0.3, _fz(2.0)), Vector3.UP)
			if what != "farm":
				# 채집물 재배 컷은 종을 색으로 가려야 하므로 더 바짝 붙는다. 플레이어는 밭 서쪽
				# 밖으로 빼서 앞줄(x1~)을 안 가리게 한다 — 기존 farm 컷 구도는 그대로 둔다.
				player.global_position = Vector3(_fx(-2.0), 2, _fz(1.5))
				cam.global_position = Vector3(_fx(4.0), 5.2, _fz(8.6))
				cam.look_at(Vector3(_fx(4.0), 0.4, _fz(2.6)), Vector3.UP)
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

# ── 작물 실물화 컷 ────────────────────────────────────────────────
# 옛 farm 컷은 광장이 화면을 채우고 작물이 하단 모서리에 걸려 증거가 안 됐다(발주 지적).
# 여기선 밭 앞 세 줄만 프레임에 담는다: fov 48→36, 카메라를 이랑 앞 5m 높이 2.6에.
# 카메라를 밭 앞 3.3m·높이 3.8에 두고 47° 내려본다 — 지면 가시 구간이 밭 4줄 그 자체가 된다.
# 울타리(decor FENCES)는 밭 **북쪽** 가장자리라 프레임에서 작물 뒤 배경으로 들어간다.
var _used_x := []    # 실제로 심은 칸의 x 중심들
var _focus_x := 0.0  # 그 양 끝의 한가운데 = 카메라가 겨누는 x (_crops_shot에서 밭 가운데로 초기화)

func _crops_shot(kind: String, tag: String) -> void:
	var sea: int = int(CROP_SEASON.get(kind, 1))
	var world := get_tree().get_first_node_in_group("world")
	GameClock.abs_day = world.season_day(sea, false)  # 그 계절 첫 맑은 비축제일 = weather clear
	GameClock.game_min = 12 * 60
	world._apply_season(sea)
	get_tree().call_group("hud", "_refresh")
	var farm := get_tree().get_first_node_in_group("farm")
	match kind:
		"winter":
			_winter_field(farm)
			world._apply_season(GameClock.season())  # 계절이 넘어갔다 = 지면·식생 다시 평가
		"stages":
			_stage_showcase(farm)
		_:
			_field_showcase(farm, GameData.season_id(sea))
	get_tree().call_group("hud", "_refresh")
	_focus_x = _fx(4.0)
	if not _used_x.is_empty():
		_used_x.sort()
		_focus_x = (_used_x[0] + _used_x[-1]) * 0.5
	var player := get_tree().get_first_node_in_group("player")
	player.global_position = Vector3(_fx(-2.0), 2, _fz(1.5))  # 밭 서쪽 밖 = 프레임 밖
	player._face_dir(Vector3(0, 0, -1))
	var cam: Camera3D = world.find_child("Camera", true, false)
	cam.set_process(false)
	if kind == "ground":
		# 접지 근경: 앞줄을 **옆에서** 훑는다. 묻히면 밑동이 잘리고 뜨면 흙과 틈이 보인다.
		# 앞(z=7 쪽)에서 잡았더니 앞줄 흙 타일 윗면이 얕은 각으로 화면 3분의 1을 먹고 밑동을
		# 통째로 가렸다(실측 ground_after 1차) — 줄과 같은 z에서 눈높이 0.40으로 훑는다.
		cam.fov = 24.0
		cam.global_position = Vector3(_focus_x - 3.4, 0.40, _fz(ROW_Z[0] + 0.5))
		cam.look_at(Vector3(_focus_x - 1.2, 0.13, _fz(ROW_Z[0] + 0.5)), Vector3.UP)
	else:
		# 1차 시도 (fov 36 · 카메라 z 9.0 · 높이 2.6)는 화면 위 절반을 광장이 먹고 남쪽 울타리가
		# 앞줄을 가로질렀다 — 발주가 지적한 옛 farm 컷과 같은 실패라 되돌렸다(실측 spring_before 1차).
		# 2차(fov 31 · z 8.2 · 높이 3.1)는 앞줄 흙이 화면 아래로 잘렸다(실측 stages_after 1차).
		# 3차: 다섯 칸 줄에서 끝 종이 화면 밖으로 걸렸다(실측 autumn_after 2차) — fov를 넓히는
		# 대신 카메라를 0.3 물렸다(가로 5.39→5.71m, 작물 크기는 5%만 준다).
		cam.fov = 35.0
		cam.global_position = Vector3(_focus_x, 3.95, _fz(6.3))
		cam.look_at(Vector3(_focus_x, 0.30, _fz(2.75)), Vector3.UP)
	await get_tree().create_timer(1.5).timeout  # 착지 + 조명·계절 셰이더 안정
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(CROP_DIR)
	img.save_png(CROP_DIR + kind + "_" + tag + ".png")
	print("saved ", kind, "_", tag, ".png  season=", GameData.season_id(GameClock.season()),
		" day=", GameClock.day_of_season(), " rain=", GameData.is_rainy(GameClock.abs_day))
	get_tree().quit()

# 그 계절 밭에 실제로 서 있을 수 있는 전 종 (심을 수 있고 그 계절에 열린다) — 데이터에서 고른다.
func _season_crops(sid: String) -> Array:
	var out := []
	for cid in GameData.crops:
		if GameData.crop_plantable(cid, sid) and GameData.crop_in_season(cid, sid):
			out.append(cid)
	out.sort()
	return out

# 종을 줄로 갈라 다 자란 상태로 진열. 한 프레임에서 종끼리 실루엣이 갈리는지 보는 컷.
func _field_showcase(farm: Node, sid: String) -> void:
	_place_rows(farm, _season_crops(sid), -1)

# rows/per로 나눠 밭 가운데 정렬해 심는다. days < 0 이면 그 종의 성숙일.
func _place_rows(farm: Node, ids: Array, days: int) -> void:
	if ids.is_empty():
		return
	var rows: int = mini(ROW_Z.size(), int(ceil(ids.size() / float(ROW_MAX))))
	var per: int = int(ceil(ids.size() / float(rows)))
	for i in ids.size():
		var cid: String = ids[i]
		var row: int = mini(i / per, ROW_Z.size() - 1)
		var cell := _fcell(clampi(ROW_X0[row] + (i % per), 0, 7), ROW_Z[row])
		_place(farm, cell, GameData.crops[cid]["seed_id"],
			GameData.grow_days(cid) if days < 0 else days)

# 성장 단계: 같은 종을 새싹 → 중간 → 성숙으로 한 줄에. 단계 수가 다른 두 종(4·3)을 위아래로.
# 단계별 대표 생장일은 **프로덕션 판정(farm.stage_index)에 물어서** 고른다 — 값을 복제하지 않는다.
func _stage_showcase(farm: Node) -> void:
	var ids := _season_crops(GameData.season_id(GameClock.season()))
	var pick := []
	for want in [4, 3]:
		for cid in ids:
			if int(GameData.crops[cid].get("stages", 3)) == want:
				pick.append(cid)
				break
	for r in pick.size():
		var cid2: String = pick[r]
		var grow: int = GameData.grow_days(cid2)
		var st: int = int(GameData.crops[cid2].get("stages", 3))
		var seen := {}
		for d in range(grow + 1):
			var s: int = farm.stage_index(d, grow, st)
			if seen.has(s):
				continue
			seen[s] = true
			_place(farm, _fcell(ROW_X0[r] + seen.size() - 1, ROW_Z[r]), GameData.crops[cid2]["seed_id"], d)

# 겨울 밭: 가을에 심은 것만 남는다. 앞줄 = 겨울에 열리는 것(수확 가능), 뒷줄 = 휴면 그루.
# 계절 경계는 프로덕션 _season_deaths를 실제로 태워 넘는다 — 값을 박지 않는다.
func _winter_field(farm: Node) -> void:
	GameClock.abs_day = 3 * GameClock.DAYS_PER_SEASON - 1  # 가을 막날
	var bear := []   # 겨울에 열린다
	var rest := []   # 가을에 심어 겨울엔 휴면하는 다년생
	for cid in GameData.crops:
		if not GameData.crop_plantable(cid, "autumn"):
			continue
		if GameData.crop_in_season(cid, "winter"):
			bear.append(cid)
		elif GameData.crop_perennial(cid):
			rest.append(cid)
	bear.sort()
	rest.sort()
	for i in mini(bear.size(), ROW_MAX):
		_place(farm, _fcell(ROW_X0[0] + i, ROW_Z[0]), GameData.crops[bear[i]]["seed_id"], 0)
	for j in mini(rest.size(), ROW_MAX):
		_place(farm, _fcell(ROW_X0[1] + j, ROW_Z[1]), GameData.crops[rest[j]]["seed_id"],
			GameData.grow_days(rest[j]))
	GameClock.sleep_to_morning()  # 가을 막날 → 겨울 D1 (여기서 고사·생존이 갈린다)
	while GameData.is_rainy(GameClock.abs_day):  # 맑은 겨울날까지
		GameClock.sleep_to_morning()
	GameClock.game_min = 12 * 60
	for i2 in mini(bear.size(), ROW_MAX):  # 겨울에 자란 만큼 = 수확 가능
		var cell := _fcell(ROW_X0[0] + i2, ROW_Z[0])
		if farm.tiles.has(cell) and farm.tiles[cell]["crop_id"] != "":
			farm.tiles[cell]["watered_growth_days"] = GameData.grow_days(bear[i2])
			farm.tiles[cell]["watered"] = true
	farm._refresh_all()

func _open_bag() -> void:
	var panel := get_tree().get_first_node_in_group("inventory_panel")
	panel.visible = true
	panel._rebuild()

# 여름 밭 진열: 성장 중 / 다 자람을 나란히 두고 작물별 색을 한 컷에 담는다.
func _plant_showcase() -> void:
	var farm := get_tree().get_first_node_in_group("farm")
	for r in [  # [칸, 씨앗, 물 준 성장일] — grow_days 도달 = 성숙
		[_fcell(2, 3), "seed.tomato", 2], [_fcell(3, 3), "seed.tomato", 7],
		[_fcell(4, 3), "seed.pepper", 5], [_fcell(5, 3), "seed.watermelon", 12],
		[_fcell(2, 2), "seed.corn", 4], [_fcell(3, 2), "seed.corn", 9],
		[_fcell(4, 2), "seed.watermelon", 6], [_fcell(5, 2), "seed.pepper", 2],
	]:
		_place(farm, r[0], r[1], int(r[2]))

# 한 칸에 심고 성장일을 직접 놓는다(며칠을 실제로 돌리지 않고 단계를 진열하기 위한 하네스 수법).
func _place(farm: Node, cell: Vector2i, seed_id: String, days: int) -> void:
	farm.till(cell)
	if not farm.plant(cell, seed_id):
		push_error("심기 거부: %s @ %s (%s)" % [seed_id, cell, GameData.season_id(GameClock.season())])
		return
	_used_x.append(cell.x + 0.5)  # 카메라를 실제로 심은 칸의 한가운데에 맞춘다
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
		# 낮은 성장 단계는 앞줄에 두면 작아서 안 읽힌다 — 뒷줄에 두고 같은 종을 세로로 짝지어 진열
		_place(farm, _fcell(i + 1, 2), GameData.crops[cid]["seed_id"], maxi(1, gd / 3))  # 성장 중
		_place(farm, _fcell(i + 1, 3), GameData.crops[cid]["seed_id"], gd)               # 다 자람
	# 대조군: 씨앗을 사서 심는 기존 작물도 같은 프레임에 (같은 밭의 어휘라는 걸 보이게)
	_place(farm, _fcell(5, 3), "seed.tomato", 7)
	_place(farm, _fcell(6, 3), "seed.pepper", 5)

# 가을 밭: 다년생이 열매를 맺은 상태 + 겨울에 열릴 다년생의 휴면(마른 갈색) 대조.
func _perennial_showcase() -> void:
	var farm := get_tree().get_first_node_in_group("farm")
	var bearing := _forage_crops("autumn", true)
	var dormant := _forage_crops("autumn", false)
	for i in bearing.size():
		var cid: String = bearing[i]
		_place(farm, _fcell(i + 1, 3), GameData.crops[cid]["seed_id"], GameData.grow_days(cid))
	for j in dormant.size():
		var cid2: String = dormant[j]
		_place(farm, _fcell(j + 1, 2), GameData.crops[cid2]["seed_id"], 0)  # 휴면 = 생장 0

# 겨울 밭: 가을에 심은 다년생만 남아 열린 상태. 한해살이(corn)는 계절 경계에서 실제로 고사시킨다
# — 값을 박지 않고 프로덕션 _season_deaths를 태워서 찍는 컷이다.
func _winter_farm_showcase() -> void:
	var farm := get_tree().get_first_node_in_group("farm")
	# 가을에 심어 **겨울에 열리는** 것 전부 = 첫해 겨울 밭에 실제로 서 있을 종. 옛 판은 "가을엔
	# 안 열리는 것"으로 골라서 겨울무(가을에도 열린다)가 빠진 3종 컷이었다 — 4종을 다 담는다.
	var winter_ids := []
	for cid in GameData.crops:
		if GameData.crop_yield(cid) != cid and GameData.crop_plantable(cid, "autumn") \
			and GameData.crop_in_season(cid, "winter"):
			winter_ids.append(cid)
	winter_ids.sort()
	for i in winter_ids.size():
		_place(farm, _fcell(i + 1, 3), GameData.crops[winter_ids[i]]["seed_id"], 0)
	_place(farm, _fcell(5, 3), "seed.corn", 4)  # 한해살이 대조군 — 겨울로 넘어가며 사라져야 한다
	GameClock.sleep_to_morning()  # 가을 막날 → 겨울 D1 (여기서 고사·생존이 갈린다)
	while GameData.is_rainy(GameClock.abs_day):  # 맑은 겨울날까지 (비 오는 컷 회피)
		GameClock.sleep_to_morning()
	GameClock.game_min = 12 * 60
	for i2 in winter_ids.size():  # 겨울에 자란 만큼을 진열 (성숙 = 수확 가능)
		var cell := _fcell(i2 + 1, 3)
		if farm.tiles.has(cell) and farm.tiles[cell]["crop_id"] != "":
			farm.tiles[cell]["watered_growth_days"] = GameData.grow_days(winter_ids[i2])
			farm.tiles[cell]["watered"] = true
	farm._refresh_all()

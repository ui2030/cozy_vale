extends Node
# 채집물 겉모습 스크린샷 하네스. 창 있는 실행 전용(헤드리스는 캡처 불가).
#   godot --path . res://tests/shot_forage.tscn -- spring|summer|autumn|winter|ground <꼬리표>
# world.gd의 `-- forage` 하네스는 **실제로 스폰된 첫 지점** 옆에 선다 — 그 지점이 집 뒤라
# 추종 카메라가 지붕에 박힌 컷이 나왔다(실측 forage/spring_before 1차). 종이 하루에 4~5개만,
# 그것도 지도 곳곳에 흩어져 스폰되므로 "그 계절 전 종을 한 컷에" 비교하려면 진열이 필요하다.
# shot_crops.gd의 _plant_showcase와 같은 수법: 배치만 하네스가 하고 **겉모습은 프로덕션
# 경로(_spawn→_look)를 그대로 통과**시킨다.

const SHOT_DIR := "res://lookdev/shots/forage/"
const ROW_Z := 9.0    # 광장 남쪽 초지. 밭 Rect2i(0,2,8,4)·플레이어집 밖이고 SPAWN_POINTS도 여기 쓴다
const ROW_GAP := 1.25  # 전고 0.50짜리가 안 겹치면서 4종이 프레임 안에 다 들어가는 간격
                       # (1.5는 좌우 끝 종이 화면 밖으로 잘렸다 — 실측 *_before 1차)

func _ready() -> void:
	SaveManager.suspended = true  # world._ready의 로드는 읽기 전용, 이후 쓰기는 전면 차단
	add_child(preload("res://world/world.tscn").instantiate())
	_run.call_deferred()

func _run() -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var what: String = args[0] if args.size() > 0 else "spring"
	var tag: String = args[1] if args.size() > 1 else "after"
	var sea: int = maxi(0, GameData.SEASON_IDS.find("summer" if what == "ground" else what))
	var world := get_tree().get_first_node_in_group("world")
	GameClock.abs_day = world.season_day(sea, false)  # 그 계절의 첫 맑고 축제 아닌 날 = weather clear
	GameClock.game_min = 12 * 60
	GameClock.state = GameClock.State.PAUSED
	world._apply_season(sea)
	# PAUSED면 tick이 안 와서 HUD 라벨이 세이브 로드값에 멈춘다(world._shot_hour의 실측과 같은 함정)
	get_tree().call_group("hud", "_refresh")

	# 그 계절 전 종을 한 줄로 진열 (희귀 포함 — 원거리 전용이라 평소 한 컷에 안 잡힌다)
	var fs := get_tree().get_first_node_in_group("forage_system")
	fs._clear()
	var pool := GameData.season_filter(GameData.forage, GameData.season_id(sea))
	var x0 := -ROW_GAP * (pool.size() - 1) * 0.5
	for i in pool.size():
		var fid: String = pool[i]
		fs._spawn(Vector3(x0 + ROW_GAP * i, 0, ROW_Z), fid, GameData.forage[fid].get("rare", false))

	var player := get_tree().get_first_node_in_group("player")
	player.global_position = Vector3(0, 2, ROW_Z + 6.0)  # 카메라 뒤 = 진열을 안 가린다
	var cam: Camera3D = world.find_child("Camera", true, false)
	cam.set_process(false)
	if what == "ground":
		# 접지 확인: 눈높이를 밑동까지 내린 측면 근경. 묻히면 밑동이 잘리고 뜨면 틈이 보인다.
		# 줄 끝(가는 대를 가진 종)을 잡는다 — 굵은 밑동보다 대 하나가 접지 오차를 훨씬 잘 드러낸다.
		var last := x0 + ROW_GAP * (pool.size() - 1)
		cam.global_position = Vector3(last + 0.55, 0.45, ROW_Z + 1.25)
		cam.look_at(Vector3(last, 0.12, ROW_Z), Vector3.UP)  # 밑동을 살짝 내려다본다
	else:
		cam.global_position = Vector3(0, 0.95, ROW_Z + 3.6)
		cam.look_at(Vector3(0, 0.26, ROW_Z), Vector3.UP)
	await get_tree().create_timer(1.2).timeout  # 조명·계절 셰이더 안정
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	img.save_png(SHOT_DIR + what + "_" + tag + ".png")
	print("saved ", what, "_", tag, ".png  종=", pool.size(), " abs_day=", GameClock.abs_day,
		" rain=", GameData.is_rainy(GameClock.abs_day))
	get_tree().quit()

extends Node3D
# A단계 월드 루트. 환경/조명 세팅 + 세이브 로드.

const ToonChar := preload("res://common/toon_character.gd")
const Interior := preload("res://world/interior.gd")  # 실내 스폰·침대 좌표 단일 출처
const Beach := preload("res://world/beach.gd")        # 해변 스폰·게이트 좌표 단일 출처
const Decor := preload("res://world/decor.gd")        # P3 드레싱(소품·꽃·숲) — 전부 무충돌
const WATER_SHADER := preload("res://world/water.gdshader")
const SKY_SHADER := preload("res://world/sky.gdshader")
const PLAZA_SHADER := preload("res://world/plaza.gdshader")
const GROUND_SHADER := preload("res://world/ground.gdshader")
const ROAD_SHADER := preload("res://world/road.gdshader")
const BRIDGE_SHADER := preload("res://world/bridge.gdshader")

@onready var _sun: DirectionalLight3D = $Sun

var _vp_pinned := false  # 조망 시점(v_*) 하네스가 플레이어를 잡아 뒀다 = hour 하네스가 덮어쓰지 않는다

# 바람의 지휘봉풍 애니메이션 물 머티리얼(연못·강·분수 공용, base=C_WATER 기본값).
func _water_mat() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = WATER_SHADER
	return m

# 돌다리 석조(벽돌 켜 쌓기) 머티리얼. 외곽선은 make_solid과 같은 next_pass 방식.
func _bridge_mat() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = BRIDGE_SHADER
	var o := ShaderMaterial.new()
	o.shader = ToonChar.OUTLINE
	o.set_shader_parameter("width", 0.004)
	m.next_pass = o
	return m

func _ready() -> void:
	_sun.rotation_degrees = Vector3(-52, -125, 0)
	_add_env()
	_build_village()        # 마을 P1 컬러박스 (임시 지오메트리, make_solid=곡면 툰)
	_convert_statics(self)  # tscn 정적 물체(바닥·기능물)를 곡면 툰으로 통일
	_ground_shader()        # 초지 바닥만 절차 풀 패턴으로 교체(_convert_statics의 단색 툰 위에)
	_water_audio()          # 물가 3D 앰비언스 (연못·분수·강)
	GameClock.season_changed.connect(func(_prev: int, sea: int) -> void: _apply_season(sea))
	if not SaveManager.load_game():
		print("새 게임 시작")
	# 스크린샷 검증용 강제 축제: `-- festival [계절]` (계절 생략 = spring, 기존 호출 그대로).
	# 날짜·시각은 calendar.json에서 파생한다 — 하네스가 축제 데이터를 복제하지 않게(단일 출처).
	if "festival" in OS.get_cmdline_user_args():
		SaveManager.suspended = true  # 시계를 축제일로 옮기므로 유저 세이브 보호(interior/beach와 같은 정책)
		var fargs := OS.get_cmdline_user_args()
		var fsea := "spring"
		var fai := fargs.find("festival")
		if fai + 1 < fargs.size() and fargs[fai + 1] in GameData.SEASON_IDS:
			fsea = fargs[fai + 1]
		var found := false
		for fid in GameData.calendar:
			var f: Dictionary = GameData.calendar[fid]
			if f["season"] == fsea:
				GameClock.abs_day = GameData.SEASON_IDS.find(fsea) * GameClock.DAYS_PER_SEASON + int(f["day"]) - 1
				# 시간창 진입 직후(조명·집합 안정 구간). 1시간 미만짜리 축제가 생겨도 창 밖으로 나가지 않게 clamp.
				GameClock.game_min = mini(int(f["start_min"]) + 60, int(f["end_min"]) - 1)
				found = true
				print("festival shot: ", fid, " abs_day=", GameClock.abs_day, " ", GameClock.hour(), ":00")
				break
		if not found:
			push_warning("festival 하네스: %s 계절에 축제 없음 — 시계 유지" % fsea)
		var pl := get_tree().get_first_node_in_group("player")
		if pl != null:  # 광장이 카메라에 잡히도록 플레이어를 광장 남쪽(분수·밭 밖)으로
			pl.global_position = Vector3(0, 2, -3.5)
		if "calendar" in fargs:  # `-- festival <계절> calendar` = 그 계절 달력 패널 컷
			var cp := get_tree().get_first_node_in_group("calendar_panel")
			if cp != null:
				cp.visible = true
				cp._rebuild()  # 시계를 옮긴 뒤라 그 계절 그리드로 다시 그린다
	# from_dict는 신호를 안 쏘므로 로드된 시각으로 축제 배치를 즉시 재평가 (축제날 아침 로드 누락 방지)
	get_tree().call_group("festival_system", "evaluate")
	if "pausemenu" in OS.get_cmdline_user_args():  # 스크린샷 검증용 메뉴 열기
		get_tree().call_group("pause_menu", "open_menu")
	if "bedshot" in OS.get_cmdline_user_args():  # 스크린샷 검증용: 침대 옆(프롬프트+라벨)
		var pb := get_tree().get_first_node_in_group("player")
		if pb != null:
			pb.global_position = Interior.BED_CENTER + Vector3(1.8, 1.2, 0.8)  # 실내 침대 남동쪽
	# 마을 조망 시점(북향 고정 카메라) — 각 지점 남쪽에 플레이어를 두면 북쪽 구조물이 잡힘
	var _vp := {
		"v_windmill":  Vector3(29, 2, -15),   # 강 건너 풍차 언덕(29,-24)
		"v_bridge_ne": Vector3(23, 2, -9),    # 북동 다리(23,-16) 앞
		"v_bridge_e":  Vector3(17, 2, 14),    # 동 다리(17,7) 앞
		"v_bridge_sw": Vector3(-3.5, 2, 37),  # 남서 다리(-3.5,30) 앞
		"v_bridgetop": Vector3(23, 2, -16),   # 북동 다리 위에서 강 내려다보기
		"v_houses":    Vector3(-20, 2, -6),   # 주민 집1(북서 -20,-14)
		"v_pavilion":  Vector3(-26, 2, 20),   # 정자(서 -26,14)
		"v_hall":      Vector3(0, 2, -11),    # 시계탑 회관(0,-18) 근접(고정카메라라 첨탑 상단은 프레임 위)
		"v_forest":    Vector3(-30, 2, 26),   # 남서 숲 띠 경계(P3 드레싱 검증)
	}
	for _k in _vp:
		if _k in OS.get_cmdline_user_args():
			var pv := get_tree().get_first_node_in_group("player")
			if pv != null:
				pv.global_position = _vp[_k]
				_vp_pinned = true  # `-- hour N`이 뒤에서 광장으로 되돌리지 않게(조망+시각 조합 컷)
	# 아치 개구부 컷: `-- shot v_arch` — 북동 다리를 하류(남서)에서 수면 높이로 마주본다.
	# 고정 추종 카메라(북향·높이6.5)로는 아치가 데크·플레이어에 가려 안 잡힌다.
	if "v_arch" in OS.get_cmdline_user_args():
		var ca := $Camera as Camera3D
		ca.set_process(false)
		ca.global_position = Vector3(21.1, 0.75, -10.3)  # 강 중심선 하류 6
		ca.look_at(Vector3(23, 0.45, -16), Vector3.UP)   # 다리 아래 개구부
		_vp_pinned = true
	# 여백 체감 샷: 광장 중심에서 4방(주거/정자/강·풍차/생활) — 게임 카메라 각도(피치·거리) 유지한 채
	# 카메라를 4 방위로 오빗(추종 스크립트 정지 후 수동 배치). 구역 간 트임을 한 컷에 담기 위함.
	var _open := {
		"v_open_res":  Vector2(-22, -6),  # 주거(북서 집 링)
		"v_open_pav":  Vector2(-26, 14),  # 정자(서)
		"v_open_river": Vector2(24, -18), # 강·풍차(북동)
		"v_open_life": Vector2(3, 15),    # 생활(남 밭·플레이어집)
	}
	for _k in _open:
		if _k in OS.get_cmdline_user_args():
			_frame_open(_open[_k])
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
	if "npcs" in OS.get_cmdline_user_args():  # 검증용: 주민 8명 색조 구분 (shot npcs)
		GameClock.game_min = 720  # 정오
		var pnp := get_tree().get_first_node_in_group("player")
		if pnp != null:
			pnp.global_position = Vector3(0, 2, 6)
		var nsys := get_tree().get_first_node_in_group("npc_system")
		if nsys != null and nsys.has_method("pose_for_shot"):
			nsys.pose_for_shot()
	if "wedding" in OS.get_cmdline_user_args():  # 검증용: 결혼식 광장 집합 (shot wedding)
		SaveManager.set_process(false)   # 유저 세이브 보호
		GameClock.game_min = 9 * 60       # 결혼식 시각(NpcSystem.WEDDING_HOUR)
		for d in GameClock.DAYS_PER_SEASON:  # 봄의 첫 맑은 평일(축제 아님) — 비 오는 결혼식 컷 방지
			if not GameData.is_rainy(d) and GameData.festival_on("spring", GameClock.day_of_season_at(d)).is_empty():
				GameClock.abs_day = d
				break
		var pwd := get_tree().get_first_node_in_group("player")
		if pwd != null:  # 광장 집합 지점(0,-6) 남서 — 분수에 가리지 않게 비켜 섬
			pwd.global_position = Vector3(-2.5, 2, -1.0)
			pwd._face_dir(Vector3(0, 0, -1))  # 광장(북) 향해 = 배우자와 마주보기
		var nwd := get_tree().get_first_node_in_group("npc_system")
		if nwd != null:
			nwd.engaged = {"id": "npc.mira", "wedding_abs_day": GameClock.abs_day}
			nwd._check_wedding()         # 즉시 식 진행(주민 집합 + 배우자 마주보기)
		SaveManager.set_process(false)   # _wed()의 request_save 취소 (가짜 결혼 세이브 방지)
	if "collection" in OS.get_cmdline_user_args():  # 검증용: 도감 패널(일부 발견)
		var pc := get_tree().get_first_node_in_group("player")
		if pc != null:
			pc.collection = ["crop.turnip", "crop.cabbage", "fish.carp", "forage.dandelion"]
		var cp := get_tree().get_first_node_in_group("collection_panel")
		if cp != null:
			cp.visible = true
			cp._rebuild()
	if "inventory" in OS.get_cmdline_user_args():  # 검증용: 가방 패널(여러 종 보유)
		SaveManager.set_process(false)  # 소지품·소지금을 덮어쓰므로 유저 세이브 보호
		GameClock.game_min = 720        # 정오 (판독 가능한 밝기)
		var pi := get_tree().get_first_node_in_group("player")
		if pi != null:
			pi.gold = 730
			pi.inventory = [
				{"id": "seed.turnip", "qty": 3}, {"id": "seed.cabbage", "qty": 1},
				{"id": "crop.turnip", "qty": 5}, {"id": "crop.strawberry", "qty": 2},
				{"id": "fish.carp", "qty": 1}, {"id": "forage.dandelion", "qty": 4},
			]
			pi.select_seed("seed.cabbage")  # 선택 표시가 첫 항목이 아닌 걸 스샷으로 확인
			pi.stats_changed.emit()         # HUD 씨앗 수량 갱신
		var ip := get_tree().get_first_node_in_group("inventory_panel")
		if ip != null:
			ip.visible = true
			ip._rebuild()
	var _args := OS.get_cmdline_user_args()
	# 실내 검증: -- interior [spouse] [hour N]. 플레이어를 실내 스폰에 세운다.
	# `-- shot interior` = 낮 컷, `-- interior hour 21` = 밤 컷, `-- interior spouse hour 7` = 아침 배우자 컷.
	# suspended=true는 set_process(false)보다 강한 차단 — 취침 등 게임 코드의 request_save까지 막는다.
	# `-- interior door hour 13` = 집 앞 문 프롬프트 컷.
	if "interior" in _args:
		SaveManager.suspended = true
		var pin := get_tree().get_first_node_in_group("player")
		if pin != null:
			pin.global_position = (Interior.OUT_DOOR + Vector3(0, 0, 1.0)) if "door" in _args else Interior.IN_SPAWN
			pin._face_dir(Interior.FACE_IN)  # 둘 다 북(집 문 / 방 안쪽)을 본다
	# 해변 검증: -- beach [gate|hut] [hour N]. 기본은 해변 도착 지점(바다를 정면에).
	# gate = 마을 남동 흙길 끝 게이트(마을 쪽), hut = 해변 오두막 문 앞. 둘 다 프롬프트 사거리 안.
	if "beach" in _args:
		SaveManager.suspended = true
		var pbe := get_tree().get_first_node_in_group("player")
		if pbe != null:
			if "gate" in _args:
				pbe.global_position = Beach.V_GATE + Vector3(0, 1.0, -1.6)  # 게이트 북쪽(마을에서 내려온 자리)
				pbe._face_dir(Vector3(0, 0, 1))                             # 게이트·표지판을 마주본다
			elif "hut" in _args:
				pbe.global_position = Beach.H_DOOR + Vector3(0, 0.2, 1.4)   # 문 남쪽 = 오두막이 프레임 안
				pbe._face_dir(Beach.FACE_N)
			elif "edge" in _args:  # 존 남동 구석 — 프레임 구석에 존 밖 허공이 뚫리는지 확인용
				pbe.global_position = Beach.ORIGIN + Vector3(Beach.WALK_HALF_X - 1.0, 1.2, Beach.WALK_Z1 - 1.0)
				pbe._face_dir(Beach.FACE_N)
			elif "shore" in _args:  # 물가(낚시 자리) — 바다가 프레임을 채우는지 확인용
				pbe.global_position = Beach.ORIGIN + Vector3(-2.0, 1.2, Beach.SHORE_Z + 1.2)
				pbe._face_dir(Beach.FACE_N)
			else:
				pbe.global_position = Beach.B_SPAWN
				pbe._face_dir(Beach.FACE_N)
	# 날씨 검증: -- weather rain|snow|clear. 날씨는 abs_day 결정적이라 강제 스위치를 두는 대신
	# 원하는 날씨의 첫 날로 시계를 옮긴다(실제 판정 함수를 그대로 통과 — 프로덕션 코드에 테스트 훅 0).
	# snow = 같은 강수 판정을 겨울에서 찾는다(weather.gd가 겨울이면 눈으로 그린다).
	var _wi := _args.find("weather")
	if _wi != -1 and _wi + 1 < _args.size():
		SaveManager.set_process(false)  # 세이브 미변경
		var wv: String = _args[_wi + 1]
		if not wv in ["rain", "snow", "clear"]:  # 오타가 조용히 "강수"로 새면 엉뚱한 컷이 찍힌다
			push_warning("weather 하네스: 모르는 값 '%s' — rain|snow|clear" % wv)
		var want: bool = wv != "clear"
		var base: int = WINTER * GameClock.DAYS_PER_SEASON if wv == "snow" else 0
		for d in GameClock.DAYS_PER_SEASON:  # 한 계절 안에서 (rain/clear는 기존대로 봄)
			if GameData.is_rainy(base + d) == want:
				GameClock.abs_day = base + d
				break
		print("weather shot: abs_day=", GameClock.abs_day, " rainy=", GameData.is_rainy(GameClock.abs_day))
	# 계절 검증: -- season <계절>. 그 계절의 첫 "맑고 축제 아닌" 날로 옮긴다(지면·식생만 보이게).
	var _si := _args.find("season")
	if _si != -1 and _si + 1 < _args.size() and _args[_si + 1] in GameData.SEASON_IDS:
		SaveManager.suspended = true  # 시계를 옮기므로 유저 세이브 보호(festival 하네스와 같은 정책)
		var sid: String = _args[_si + 1]
		var sb: int = GameData.SEASON_IDS.find(sid) * GameClock.DAYS_PER_SEASON
		# `-- season <계절> <일차>` = 그 계절의 특정 일차로 직행(계절 말일 HUD 컷용). 생략하면 기존대로 첫 맑은 날.
		if _si + 2 < _args.size() and _args[_si + 2].is_valid_int():
			GameClock.abs_day = sb + clampi(int(_args[_si + 2]), 1, GameClock.DAYS_PER_SEASON) - 1
		else:
			for d in GameClock.DAYS_PER_SEASON:
				if not GameData.is_rainy(sb + d) and GameData.festival_on(sid, d + 1).is_empty():
					GameClock.abs_day = sb + d
					break
		print("season shot: ", sid, " abs_day=", GameClock.abs_day)
	# 시계를 옮기는 하네스(festival·wedding·weather·season)와 세이브 로드를 전부 지난 뒤 1회 —
	# from_dict는 신호를 안 쏘므로 여기서 계절 표현(지면 눈 톤·식생)을 명시 재평가한다.
	_apply_season(GameClock.season())
	# 채집물 검증: -- forage. 좌표를 복제하지 않고 실제로 스폰된 첫 채집물 옆에 선다.
	if "forage" in _args:
		await get_tree().process_frame  # forage_system의 _respawn.call_deferred 완료 대기
		var fa := get_tree().get_first_node_in_group("forage") as Area3D
		var pfo := get_tree().get_first_node_in_group("player")
		if fa != null and pfo != null:
			# 남동쪽으로 비켜 선다 — 정남에 서면 채집물이 캐릭터 몸통에 완전히 가린다(실측).
			pfo.global_position = fa.global_position + Vector3(1.0, 0.6, 1.0)
			pfo._face_dir(Vector3(-1, 0, -1))
	# 낮밤 검증: -- hour N (시계를 N시로 강제, PAUSED 고정 → FAST shot 흐름과 분리). 세이브 미변경.
	var _hi := _args.find("hour")
	if _hi != -1 and _hi + 1 < _args.size():
		SaveManager.set_process(false)  # SaveManager._process 기본활성 1프레임 자동쓰기 억제 → 세이브 무변경
		GameClock.game_min = int(_args[_hi + 1]) * 60
		GameClock.state = GameClock.State.PAUSED
		var ph := get_tree().get_first_node_in_group("player")
		if ph != null and not _vp_pinned and not "interior" in _args and not "beach" in _args and not "forage" in _args:  # 세이브 무관하게 광장 조망으로 고정
			ph.global_position = Vector3(0, 2, -3.5)
		if "spouse" in _args:  # 시각 확정 뒤에 기혼화 — 배우자 실내 배치는 시각(place_at) 파생이다
			var nsp := get_tree().get_first_node_in_group("npc_system")
			if nsp != null:
				nsp.spouse = "npc.mira"
		await _shot_hour(int(_args[_hi + 1]))
	# 스크린샷 캡처는 배치용 cmdline 처리를 모두 마친 뒤 한 번만 (기존엔 _convert_statics
	# 재귀 말미에 있어 노드마다 호출되던 것을 _ready 종단으로 이전 — 1회 캡처).
	if "shot" in OS.get_cmdline_user_args():
		await _shot()

# 물가 소리: 연못·분수 + 강 폴리라인을 따라 ~9 간격으로 AudioStreamPlayer3D를 심는다.
# 강은 길어서(전장 ~90) 점 음원 하나로는 다리 근처에서만 들린다 — 등간격 다발이 선을 흉내낸다.
# 같은 루프라 위상이 겹치면 콤필터링(금속성 울림)이 나므로 시작 지점을 무작위로 어긋뜨린다.
func _water_audio() -> void:
	if Sfx.water_loop == null or Sfx.silent:  # 헤드리스면 에미터 자체를 안 만든다
		return
	var spots := [Vector3(10, 0.3, 0), Vector3(0, 0.7, 0)]  # 연못(world.tscn) / 분수(광장 중앙)
	for i in RIVER_PTS.size() - 1:
		var a: Vector2 = RIVER_PTS[i]
		var b: Vector2 = RIVER_PTS[i + 1]
		var n := maxi(1, int(round((b - a).length() / 9.0)))
		for k in n:
			var c: Vector2 = a + (b - a) * ((k + 0.5) / float(n))
			spots.append(Vector3(c.x, 0.3, c.y))
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260727
	for s in spots:
		var sp := AudioStreamPlayer3D.new()
		sp.stream = Sfx.water_loop
		sp.bus = Sfx.bus_or_master("Ambience")
		sp.unit_size = 6.0        # 이 거리부터 감쇠 시작
		sp.max_distance = 18.0    # 넘으면 무음 (카메라가 아니라 플레이어 리스너 기준)
		sp.volume_db = -4.0
		# 루프가 1.9초로 짧다 — 시작 위상과 피치를 에미터마다 흩어 놔야 여러 개가 동시에 들릴 때
		# 같은 파형이 겹쳐 나는 금속성 울림(콤필터링)과 "똑같은 소리 반복" 느낌이 사라진다.
		sp.pitch_scale = rng.randf_range(0.88, 1.12)
		sp.position = s
		add_child(sp)
		sp.play(rng.randf() * Sfx.water_loop.get_length())

# StandardMaterial3D 정적 메시 → 곡면 툰 (투명물=조준칸 제외)
func _convert_statics(node: Node) -> void:
	if node is MeshInstance3D:
		var par := node.get_parent()
		if par != null and par.is_in_group("water"):  # 연못(water 그룹) 수면 → 애니 물
			node.material_override = _water_mat()
		else:
			var m = node.material_override
			if m is StandardMaterial3D and m.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
				node.material_override = ToonChar.make_solid(m.albedo_color, 0.0)
	for c in node.get_children():
		_convert_statics(c)

# 초지 바닥(world.tscn Ground/GroundMesh) → 절차 풀 패턴 셰이더. albedo는 _apply_season이 구동한다.
func _ground_shader() -> void:
	var gm := get_node_or_null("Ground/GroundMesh") as MeshInstance3D
	if gm == null:
		return
	var m := ShaderMaterial.new()
	m.shader = GROUND_SHADER
	gm.material_override = m

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
	# -- out <상대경로> 로 저장 위치 지정 (없으면 world.png — 기존 동작)
	var args := OS.get_cmdline_user_args()
	var oi := args.find("out")
	var _def := "interior/day.png" if "interior" in args else "world.png"
	var rel: String = args[oi + 1] if oi != -1 and oi + 1 < args.size() else _def
	DirAccess.make_dir_recursive_absolute("res://lookdev/shots/" + rel.get_base_dir())
	img.save_png("res://lookdev/shots/" + rel)
	print("saved ", rel, "  clock=", GameClock.hour(), ":", GameClock.minute())
	get_tree().quit()

# 낮밤 조명 검증 캡처: PAUSED 유지(시계 N:00 고정), 조명 안정 후 1회 캡처. 세이브 미변경.
func _shot_hour(hn: int) -> void:
	# PAUSED라 GameClock.tick이 안 온다 → HUD 시각 라벨이 세이브 로드값에 멈춰 샷마다 엉뚱한
	# 시각이 찍혔다(실측). 강제 시각을 적용한 뒤 한 번 갱신해 준다.
	get_tree().call_group("hud", "_refresh")
	await get_tree().create_timer(0.6).timeout  # 물리 착지 + day_night 파라미터 적용 대기
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var args := OS.get_cmdline_user_args()
	var wi := args.find("weather")
	var oi := args.find("out")
	var rel := "daynight/hour_%02d.png" % hn
	if oi != -1 and oi + 1 < args.size():  # -- out <상대경로>가 있으면 최우선 (_shot 전례)
		rel = args[oi + 1]
	elif "interior" in args:  # 실내 샷은 별도 폴더로 (배우자·문 컷은 파일명 접두로 구분)
		var pre := ("spouse_" if "spouse" in args else "") + ("door_" if "door" in args else "")
		rel = "interior/%shour_%02d.png" % [pre, hn]
	elif "beach" in args:   # 해변 샷 (게이트·오두막·구석·물가 컷은 파일명 접두로 구분)
		var pre := ""
		for k in ["gate", "hut", "edge", "shore"]:
			if k in args:
				pre = k + "_"
		rel = "beach/%shour_%02d.png" % [pre, hn]
	elif wi != -1 and wi + 1 < args.size():  # 날씨 강제 샷은 별도 폴더로
		rel = "weather/%s_hour_%02d.png" % [args[wi + 1], hn]
	DirAccess.make_dir_recursive_absolute("res://lookdev/shots/" + rel.get_base_dir())
	img.save_png("res://lookdev/shots/" + rel)
	print("saved ", rel)
	get_tree().quit()

# 여백 체감 샷: 카메라를 광장 중앙 대상으로, 존 반대편 위에서 게임카메라 각도(수평9.5·높이6.5,
# 피치 ~34°)로 바라보게 수동 배치. 추종 스크립트는 정지시켜 프레임 고정.
func _frame_open(zone: Vector2) -> void:
	var cam := $Camera as Camera3D
	cam.set_process(false)
	var d := zone.normalized()
	cam.global_position = Vector3(-d.x * 9.5, 6.5, -d.y * 9.5)  # 광장 반대편 위
	cam.look_at(Vector3(d.x * 6.0, 1.2, d.y * 6.0), Vector3.UP) # 존 방향으로
	var pl := get_tree().get_first_node_in_group("player")
	if pl != null:
		pl.global_position = Vector3(d.x * 2.0, 2, d.y * 2.0)   # 광장 중앙 스케일 기준

func _add_env() -> void:
	var env := Environment.new()
	# 시간대 하늘(sky.gdshader). ambient는 COLOR로 두고 day_night.gd가 명시 제어(sky가 ambient 구동 안 함).
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = SKY_SHADER
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.76, 0.82)  # 낮 승인값(day_night가 시각별로 덮어씀)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

# ══ 마을 P1 컬러박스 ══════════════════════════════════════════════
# 임시 지오메트리로 전체 레이아웃 + 구역 팔레트 단색(SPEC §2 낮 기준). make_solid이 곡면 툰
# (월드 곡률) 셰이더를 이미 적용하므로 _convert_statics 불필요. 각 건물에 P2 Tripo 교체용
# footprint/피벗(바닥중심)/전고 주석. 좌표: x=동+, z=남+, 북=-z. 지면충돌 40×40(x,z∈[-20,20]).
# 파스텔 시프트(소프트닝 v1): 채도 −15%p(단, 이미 옅은 색은 ×0.55까지만) · 명도 +5%p 상한 0.88.
# 색상(hue)은 전부 보존 — 특히 지붕 보라는 마을 아이덴티티다. 예외(불변): 물·눈·하늘·조명·판석.
const C_ROOF  := Color(0.509, 0.429, 0.610)  # 보라 진 — 지붕 기와(마을 아이덴티티)
const C_ROOF2 := Color(0.656, 0.572, 0.740)  # 보라 중 — 지붕 밝은면
# 크림 벽토는 채도를 규칙대로(0.16→0.09) 깎으면 정오 직광면에서 B채널까지 255로 포화해
# 건물이 순백 덩어리가 된다(실측). 0.12까지만 깎아 포화해도 따뜻한 크림으로 읽히게 남긴다.
const C_WALL  := Color(0.880, 0.844, 0.774)  # 크림 — 벽토/석재
const C_WOOD  := Color(0.590, 0.480, 0.362)  # 브라운 — 목재
const C_ROAD  := Color(0.700, 0.619, 0.476)  # 흙길 — 파스텔 모래빛
const C_ROAD_E := Color(0.720, 0.673, 0.590)  # 길 가장자리 — 풀로 옅어지는 톤(같은 hue, 채도만 낮춤)
const C_STONE := Color(0.770, 0.758, 0.735)  # 석재 회 — 다리/계단/분수
const C_DRESSED := Color(0.700, 0.688, 0.667)  # 다듬돌(갓돌·이맛돌) — 같은 hue 한 단 아래
const C_GREEN := Color(0.652, 0.710, 0.494)  # 그린 — 언덕(수평면이라 0.72 이하로 묶는다)
const C_WATER := Color(0.50, 0.72, 0.85)  # 물 — 강(연못과 통일). 승인 색 = 파스텔 시프트 예외.
const C_WIST  := Color(0.720, 0.649, 0.790)  # 등나무 보라 — 퍼걸러
# 지면(world.tscn Ground/GroundMesh) 계절색 = ground.gdshader의 albedo uniform을 구동한다.
# 명도 0.80은 정오 수평면에서 G채널 255로 클리핑됐다(실측 (212,255,172)) — 패턴이 통째로 날아가는
# 값이라 0.72로 내리고 채도도 0.35→0.20으로 낮췄다. 이제 (213,245,196)쯤 = 파스텔 초지.
const C_GRASS := Color(0.627, 0.720, 0.576)  # 초지
# 눈: 순백 금지. 툰 라이팅(태양1.0 + 환경광0.55)이 albedo를 ~3.3배로 올려 화면에 낸다 —
# 실측(정오 초지 albedo 0.62 → 화면 212). albedo 0.76을 넘기면 지면이 255로 클리핑돼
# 음영·곡률이 통째로 날아가고 크림색 하늘과 지평선에서 붙어버린다.
# 0.71/0.73/0.76 → 화면 ~(238,244,254): 밝되 클리핑 직전, 청기가 남아 설원으로 읽힌다.
# (청기를 더 주면 설원이 아니라 언 호수로 보인다 — R/G/B 간격을 좁게 유지할 것.)
const C_SNOW  := Color(0.71, 0.73, 0.76)

func _build_village() -> void:
	var v := Node3D.new()
	v.name = "Village"
	add_child(v)
	_plaza(v)
	_roads(v)
	_fountain(v, Vector3.ZERO)
	# 시계탑 회관 — footprint 6×5, 피벗(0,-18). 2층 몸체(H5) + 시계탑(2.3각, 총고~10). SOLID.
	_house(v, Vector3(0, 0, -18), 6, 5, 5, true)
	_clock_tower(v, Vector3(0, 5, -18))
	# 주민 집 3채 — 광장 외곽 링에 사방 분산(북서/서/남서). footprint 4×4, 전고 4. SOLID.
	_house(v, Vector3(-20, 0, -14), 4, 4, 4, true)  # House1 피벗(-20,-14) 북서
	_house(v, Vector3(-24, 0, 2), 4, 4, 4, true)    # House2 피벗(-24,2) 서
	_house(v, Vector3(-14, 0, 22), 4, 4, 4, true)   # House3 피벗(-14,22) 남서
	# House4 피벗(24,20) 남동 강 건너 — 지도 패널의 동안(東岸) 건물 재현. 북향 문(동 다리 길 방향).
	_house(v, Vector3(24, 0, 20), 4, 4, 4, true, -1.0)
	# 상점 박스(광장 북서 림, 불변) — footprint 3×3, 피벗(-7,-7), 전고 3. SOLID. 트리거=tscn Shop(-5,-5).
	_house(v, Vector3(-7, 0, -7), 3, 3, 3, true)
	# 플레이어 집(남, 밭 남쪽) — footprint 5×5, 피벗(3,15), 전고 5. DECOR(무충돌: 실내 문 접근용).
	# (6,13)→(3,15): 광장 림 이격 5.07→6.5로 규정(≥6) 충족 (Fable 검수 반영)
	# door_sign +1 = 남향 문. 길은 북에서 오지만 문은 남면이어야 한다 — 추종 카메라가 플레이어
	# 뒤(+Z)·위에 있어서 북면 문 앞에 서면 집 몸통이 카메라와 플레이어 사이를 통째로 가린다.
	# 실측: 지붕 먼쪽 모서리(z=12.25,y=5.45)를 넘어 보려면 플레이어가 z<6.2여야 한다(문은 z=12.45).
	_house(v, Vector3(3, 0, 15), 5, 5, 5, false, 1.0)
	# 정자(서, 집C와 ≥8) — footprint 4×4, 피벗(-26,14), 전고 3. DECOR(개방 퍼걸러).
	_pavilion(v, Vector3(-26, 0, 14))
	_river_and_bridges(v)
	_windmill_hill(v)
	# 드레싱: 소품·꽃 덤불·숲 띠(원통+구 나무를 대체). 자체 툰 변환 + 무충돌 감사를 하므로
	# _convert_statics 이전/이후 어느 쪽이든 안전하지만, 규약대로 이전에 트리에 넣는다.
	var decor := Decor.new()
	decor.name = "Decor"
	v.add_child(decor)
	decor.build(RIVER_PTS, BRIDGES, ROADS)

# 박스 메시(툰 단색). center=박스 중심.
func _box(parent: Node, center: Vector3, size: Vector3, color: Color, outline := 0.006) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = ToonChar.make_solid(color, outline)
	mi.position = center
	parent.add_child(mi)
	return mi

func _cyl(parent: Node, center: Vector3, radius: float, height: float, color: Color, outline := 0.006) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	mi.mesh = cm
	mi.material_override = ToonChar.make_solid(color, outline)
	mi.position = center
	parent.add_child(mi)
	return mi

# 보이지 않는 정적 충돌 박스. center=박스 중심.
func _collide(parent: Node, center: Vector3, size: Vector3, rot_y := 0.0, rot_x := 0.0) -> void:
	var sb := StaticBody3D.new()
	sb.position = center
	sb.rotation = Vector3(rot_x, rot_y, 0)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	sb.add_child(cs)
	parent.add_child(sb)

# 건물: 피벗=바닥중심(base.x,base.z), 벽 w×d, 전고 h. solid이면 충돌체.
func _house(parent: Node, base: Vector3, w: float, d: float, h: float, solid: bool, door_sign := 1.0) -> void:
	# door_sign: +1=남향 문(기본), -1=북향 문(광장을 등지는 남쪽 건물용)
	var cx := base.x
	var cz := base.z
	_box(parent, Vector3(cx, h * 0.5, cz), Vector3(w, h, d), C_WALL)            # 벽토(크림)
	_box(parent, Vector3(cx, h + 0.2, cz), Vector3(w + 0.5, 0.5, d + 0.5), C_ROOF)   # 보라 기와 처마
	_box(parent, Vector3(cx, h + 0.55, cz), Vector3(w * 0.6, 0.4, d * 0.6), C_ROOF2) # 지붕 마루 밝은면
	_box(parent, Vector3(cx, 0.9, cz + door_sign * (d * 0.5 + 0.05)), Vector3(0.9, 1.8, 0.12), C_WOOD, 0.004)  # 문(목재)
	if solid:
		_collide(parent, Vector3(cx, h * 0.5, cz), Vector3(w, h, d))

func _clock_tower(parent: Node, base: Vector3) -> void:
	# base=몸체 위(y=5). 탑 shaft 2.3각 h3(y5→8) + 보라 원뿔 지붕캡 + 남향 큰 시계면 + 깃발. 총고~9.7(≤10).
	var cx := base.x
	var cz := base.z
	var y := base.y
	_box(parent, Vector3(cx, y + 1.5, cz), Vector3(2.3, 3.0, 2.3), C_WALL)           # 탑 몸통
	_box(parent, Vector3(cx, y + 3.2, cz), Vector3(2.7, 0.4, 2.7), C_ROOF)           # 지붕 처마
	# 뾰족 지붕(원뿔 = CylinderMesh top_radius 0). 보라.
	var cap := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = 1.4
	cm.height = 1.2
	cap.mesh = cm
	cap.material_override = ToonChar.make_solid(C_ROOF, 0.006)
	cap.position = Vector3(cx, y + 4.0, cz)  # 밑면 y3.4→꼭짓점 y4.6
	parent.add_child(cap)
	# 시계면: 탑 하부(몸체 지붕 바로 위, world y~6.3)에 둬 고정 게임카메라(위를 못 봄)에서도 인지.
	# 고대비: 보라 테 + 흰 문자판 + 보라 바늘 → 크림 탑에서 즉시 읽힘.
	_box(parent, Vector3(cx, y + 1.3, cz + 1.22), Vector3(1.6, 1.6, 0.12), C_ROOF, 0.004)     # 보라 테
	_box(parent, Vector3(cx, y + 1.3, cz + 1.30), Vector3(1.2, 1.2, 0.06), Color(0.98, 0.97, 0.94), 0.004)  # 흰 문자판
	_box(parent, Vector3(cx, y + 1.3, cz + 1.36), Vector3(0.12, 0.7, 0.05), C_ROOF, 0.0)      # 시침
	_box(parent, Vector3(cx, y + 1.3, cz + 1.36), Vector3(0.55, 0.12, 0.05), C_ROOF, 0.0)     # 분침
	_box(parent, Vector3(cx, y + 4.55, cz), Vector3(0.07, 0.6, 0.07), C_WOOD, 0.0)            # 깃대(원뿔 꼭짓점 위)
	_box(parent, Vector3(cx + 0.33, y + 4.7, cz), Vector3(0.6, 0.34, 0.04), C_ROOF2, 0.0)     # 깃발 (총고 top≈world9.87 ≤10)

func _fountain(parent: Node, at: Vector3) -> void:
	# 3단 분수(반경≤1.2), 광장 중앙. 충돌 r1 h2(플레이어 진입 차단).
	_cyl(parent, at + Vector3(0, 0.3, 0), 1.2, 0.6, C_STONE)
	_cyl(parent, at + Vector3(0, 0.75, 0), 0.8, 0.4, C_STONE)
	_cyl(parent, at + Vector3(0, 1.15, 0), 0.35, 0.5, C_STONE)
	_cyl(parent, at + Vector3(0, 0.62, 0), 1.0, 0.1, C_WATER, 0.0).material_override = _water_mat()  # 수면(애니 물)
	var sb := StaticBody3D.new()
	sb.position = at + Vector3(0, 1, 0)
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 1.0
	sh.height = 2.0
	cs.shape = sh
	sb.add_child(cs)
	parent.add_child(sb)

func _plaza(parent: Node) -> void:
	# 크림 판석 원형 바닥 r6 — 시각 전용 교체(메시·좌표·높이·반경 불변, 충돌체 없음).
	# 흰 디스크 → 절차 판석 패턴(world/plaza.gdshader, 텍스처 파일 0).
	var mi := _cyl(parent, Vector3(0, 0.08, 0), 6.0, 0.12, C_WALL, 0.0)
	var m := ShaderMaterial.new()
	m.shader = PLAZA_SHADER
	mi.material_override = m

# 방사 6갈래 + 다리 연결로. [중심, 길이(로컬+Z), y회전(도)] — rot=atan2(dx,dz)로 장축을 방향에 정렬.
# 지도 충실화(Fable 탑다운 대조 반영): 모든 다리는 길로 연결 + 동안(東岸) 경로.
# decor.gd가 "길 위·길가 데코 금지" 판정에 이 배열을 그대로 읽는다(좌표 단일 출처).
const ROAD_W := 2.4
const ROADS := [
	[Vector2(0, -12), 12.0, 0.0],           # N→회관(0,-18)
	[Vector2(-12.5, -8.7), 18.0, -125.0],   # NW→House1(-20,-14)
	[Vector2(-15.4, 4.9), 20.0, -72.0],     # W→정자·집2 방면(조준점 -25,8)
	[Vector2(-8.6, 13.5), 20.0, -33.0],     # SW→House3(-14,22)
	[Vector2(2.1, 9.2), 7.0, 11.0],         # S→플레이어집(3,15)
	[Vector2(11.3, 4.6), 12.0, 68.0],       # E→동 다리(17,7)
	[Vector2(12.6, -10.1), 20.5, 125.0],    # NE→북동 다리(23,-16)
	[Vector2(-2.5, 17.25), 23.0, -5.0],     # S외곽→남서 다리(-3.5,30)
	[Vector2(27.45, -14.8), 3.2, 79.0],     # 동안 북: 북동 다리 동단→풍차 램프 발치(강둑·대지 회피)
	[Vector2(22, 12.75), 10.3, 23.0],       # 동안 남: 동 다리→집4(24,20)
	# 플레이어집 남측 진입로: 남향 문(벽면 z=17.55) 앞이 맨땅이라 실외 스폰(3,20.6)이 길 위에 서게 한다.
	# 85°는 S외곽길(-5°)과 정확히 직교 — 길 박스가 전부 같은 평면(y=0.185)이라 비스듬히 물리면
	# 겹친 자리가 z-fighting 하거나 쐐기 틈이 남는다. 서단은 S외곽길 중심선에서 동쪽 1.2(=반폭) 지점.
	[Vector2(1.23, 20.34), 5.57, 85.0],
]

func _roads(parent: Node) -> void:
	for r in ROADS:
		_road(parent, Vector3(r[0].x, 0.16, r[0].y), Vector3(ROAD_W, 0.05, r[1]), r[2])

func _road(parent: Node, center: Vector3, size: Vector3, rot_deg: float) -> void:
	var mi := _box(parent, center, size, C_ROAD, 0.0)
	mi.rotation.y = deg_to_rad(rot_deg)
	# 하드 엣지 제거: 전용 셰이더가 라운드 사각 SDF − 노이즈로 가장자리를 갉아낸다(discard).
	# half_ext는 박스마다 다르므로 여기서 넣는다(셰이더 기본값은 폴백일 뿐).
	var rm := ShaderMaterial.new()
	rm.shader = ROAD_SHADER
	rm.set_shader_parameter("albedo", C_ROAD)
	rm.set_shader_parameter("edge_color", C_ROAD_E)  # 팔레트 단일 출처 = 셰이더 기본값에 안 맡긴다
	rm.set_shader_parameter("half_ext", Vector2(size.x * 0.5, size.z * 0.5))
	mi.material_override = rm
	# 곡률 셰이더(v.y -= 0.006·z²)는 정점 단위 — 세분할 없는 긴 박스는 장축이 현(직선)으로
	# 근사돼 가운데가 지면 아래로 잠긴다(N길 12u 실증, 처짐 0.0015·Δd²  vs 부상고 0.085).
	# 장축을 ~1.5u 간격으로 쪼개면 지면(60분할 평면)과 같은 곡선을 탄다.
	(mi.mesh as BoxMesh).subdivide_depth = maxi(1, int(size.z / 1.5))

func _pavilion(parent: Node, base: Vector3) -> void:
	# 정자 4×4 퍼걸러: 기둥4 + 등나무 지붕 + 테이블. 개방(무충돌).
	var cx := base.x
	var cz := base.z
	for sx in [-1.7, 1.7]:
		for sz in [-1.7, 1.7]:
			_box(parent, Vector3(cx + sx, 1.3, cz + sz), Vector3(0.25, 2.6, 0.25), C_WOOD)
	_box(parent, Vector3(cx, 2.7, cz), Vector3(4.2, 0.25, 4.2), C_WOOD)          # 상단 프레임
	_box(parent, Vector3(cx, 2.95, cz), Vector3(3.6, 0.2, 3.6), C_WIST, 0.004)   # 등나무 보라
	_box(parent, Vector3(cx, 0.5, cz), Vector3(1.2, 1.0, 1.2), C_WOOD)           # 테이블

# 강: S자 곡류 폴리라인(마을 남동면을 감쌈). 폭3 침하 채널 + 물면 + 양안 강둑(v1.2 시각 기준).
# 통행은 폴리라인 따라 분절된 충돌벽이 좌우(다리 3곳만 gap). 채널·물면·강둑은 무충돌.
const RIVER_PTS := [
	Vector2(30, -34), Vector2(24, -20), Vector2(20, -8), Vector2(18, 2),
	Vector2(16, 12), Vector2(6, 26), Vector2(-12, 34),
]
const BRIDGES := [Vector2(23, -16), Vector2(17, 7), Vector2(-3.5, 30.2)]  # 북동/동/남서
const BRIDGE_GAP := 2.4  # 다리에서 충돌벽을 비우는 반경(폭 방향 통과 확보)

func _river_and_bridges(parent: Node) -> void:
	for i in RIVER_PTS.size() - 1:
		var a: Vector2 = RIVER_PTS[i]
		var b: Vector2 = RIVER_PTS[i + 1]
		var ang := atan2(b.x - a.x, b.y - a.y)  # 로컬+Z가 a→b 향하게 y회전
		var mid := (a + b) * 0.5
		var span := (b - a).length()
		var perp := Vector2((b - a).y, -(b - a).x).normalized()  # 강 수직(강둑 오프셋)
		var floor_box := _box(parent, Vector3(mid.x, -0.02, mid.y), Vector3(3.2, 0.3, span + 0.4), Color(0.401, 0.572, 0.650), 0.0)
		floor_box.rotation.y = ang  # 어두운 채널 바닥(깊이감)
		var water := _box(parent, Vector3(mid.x, 0.16, mid.y), Vector3(3.0, 0.14, span + 0.4), C_WATER, 0.0)
		water.rotation.y = ang      # 밝은 물면(강둑보다 낮게 inset), 폭3
		water.material_override = _water_mat()  # 애니 물(연못과 통일)
		for s in [1.0, -1.0]:       # 양안 강둑(브라운) — 물면보다 ~0.45 높아 파인 채널로 읽힘
			var bc: Vector2 = mid + perp * (2.05 * s)
			var bank := _box(parent, Vector3(bc.x, 0.35, bc.y), Vector3(1.0, 0.7, span + 0.4), C_WOOD, 0.004)
			bank.rotation.y = ang
		_river_wall_seg(parent, a, b, ang)  # 분절 충돌벽(다리 gap 제외)
	for br in BRIDGES:
		_arch_bridge(parent, br, _river_dir_at(br))

# 세그먼트를 ~1.4 간격 짧은 벽으로 채우되, 다리(BRIDGE_GAP) 근처 스텝은 비운다(다리로만 통과).
func _river_wall_seg(parent: Node, a: Vector2, b: Vector2, ang: float) -> void:
	var span := (b - a).length()
	var n := maxi(1, int(round(span / 1.4)))
	var step := (b - a) / float(n)
	for k in n:
		var c: Vector2 = a + step * (k + 0.5)
		var skip := false
		for br in BRIDGES:
			if c.distance_to(br) < BRIDGE_GAP:
				skip = true
				break
		if not skip:
			_collide(parent, Vector3(c.x, 0.5, c.y), Vector3(3, 1.5, step.length() + 0.1), ang)

# 점 p에서 가장 가까운 강 세그먼트의 흐름 방향(y회전각).
func _river_dir_at(p: Vector2) -> float:
	var best := 0.0
	var best_d := INF
	for i in RIVER_PTS.size() - 1:
		var a: Vector2 = RIVER_PTS[i]
		var b: Vector2 = RIVER_PTS[i + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var d := p.distance_to(a + ab * t)
		if d < best_d:
			best_d = d
			best = atan2(ab.x, ab.y)
	return best

# 석조 아치 다리: 강 수직으로 데크가 채널을 가로지름. 전부 무충돌(통행 = 강 충돌벽의 다리 gap).
# 로컬 프레임(holder에 rotation.y=ang): +X = 강을 가로지름, +Z = 흐름 방향, 원점 = 다리 중심.
#
# 통행 계약 불변:
#  · 데크 박스(6×0.3×3, 중심 y=0.75 → 상면 0.9)는 값까지 그대로다 — npc_system.DECK_Y=0.9 파생.
#  · 중앙 통로 z∈(-1.3,1.3)엔 아무것도 새로 넣지 않는다. 다리엔 충돌이 없어 플레이어·NPC는
#    데크 아래 지면 높이로 지나간다 — 아치 구조를 통로에 채우면 캐릭터가 돌 속에 파묻힌다.
#    그래서 아치는 양 측벽(스팬드럴)에만 뚫고, 가운데는 예전처럼 비워 둔다.
#  · 충돌체 0 유지(CSGShape3D.use_collision 기본 false).
const ARCH_R := 3.5     # 아치 원 반지름 — 크면 완만한 세그먼트 아치. 데크 밑(0.6) 안에 들어가야 한다.
const ARCH_CY := -2.90  # 아치 원 중심 y (관정 = ARCH_CY + ARCH_R = 0.60 = 데크 밑면, 스프링 = 지면 y0)
const ARCH_N := 11      # 홍예석(voussoir) 개수 — 아치 곡선을 두르는 다듬돌

func _arch_bridge(parent: Node, at: Vector2, ang: float) -> void:
	var h := Node3D.new()
	h.position = Vector3(at.x, 0, at.y)
	h.rotation.y = ang
	parent.add_child(h)
	# 데크(보도) — 위치·크기 불변, 재질만 석조 벽돌 패턴으로.
	_box(h, Vector3(0, 0.75, 0), Vector3(6, 0.3, 3), C_STONE, 0.0).material_override = _bridge_mat()
	# 아치 측벽 2장 − 원기둥 = 단경간 세그먼트 아치(관정 y=0.60 = 데크 밑면, 스프링 ±1.96).
	# 수면(폭3.0·상면0.23) 위로 3.13 트인다. 벽 밑(-0.1)은 지면에 묻혀 접지로 읽힌다.
	var arch := CSGCombiner3D.new()
	for s in [1.0, -1.0]:
		var w := CSGBox3D.new()
		w.size = Vector3(6, 1.0, 0.25)
		w.position = Vector3(0, 0.4, 1.425 * s)
		arch.add_child(w)
	var cut := CSGCylinder3D.new()
	cut.radius = ARCH_R
	cut.height = 3.4          # 측벽 두 장을 한 번에 관통
	cut.sides = 64            # 곡선이 각지지 않게
	cut.rotation.x = PI * 0.5  # 축을 흐름 방향으로 = 아치가 강을 가로질러 뚫린다
	cut.position = Vector3(0, ARCH_CY, 0)
	cut.operation = CSGShape3D.OPERATION_SUBTRACTION
	arch.add_child(cut)
	arch.material_override = _bridge_mat()
	h.add_child(arch)
	for s in [1.0, -1.0]:
		# 난간(파라펫) — 예전 난간(z 1.40~1.60, 상단 1.30)과 발자국이 같다: 데크 상면을 더
		# 잠식하지 않고, decor.gd 등나무 앵커(z=±1.5, y=1.32)도 그대로 난간 위에 얹힌다.
		_box(h, Vector3(0, 1.035, 1.5 * s), Vector3(6, 0.27, 0.20), C_STONE, 0.0).material_override = _bridge_mat()
		# 갓돌·이맛돌은 벽돌 패턴 없는 다듬돌(민면). C_STONE 그대로면 정오 직광에서 흰색으로
		# 포화해 벽돌면과 붙는다(실측) — 한 단 낮춰야 매끈한 돌로 읽힌다.
		var cap := _cyl(h, Vector3(0, 1.17, 1.5 * s), 0.13, 6.1, C_DRESSED, 0.004)  # 둥근 갓돌(상단 1.30)
		cap.rotation.z = PI * 0.5
		# 홍예석(voussoir) 링 — 아치 곡선을 다듬돌로 두른다. 개구부가 낮고 넓어(수면 위 높이 0.37)
		# 곡선만으론 슬릿처럼 읽혔다(실측) — 컨셉아트 "강가 다리"처럼 링이 있어야 아치로 보인다.
		# 통로(z<1.3) 침범 금지 — 측벽 두께 안에만 두고 바깥으로 0.05 튀어나온다.
		# 링은 채널(강둑 사이 |x|<1.6)까지만 — 그 밖은 강둑(높이 0.7)에 묻혀 떠 있는 돌로 보인다(실측).
		var th_max := asin(1.6 / (ARCH_R + 0.1))
		for i in ARCH_N:
			var th := lerpf(-th_max, th_max, i / float(ARCH_N - 1))
			var key := i == ARCH_N / 2  # 가운데 = 이맛돌(키스톤), 한 단 크게
			var v := _box(h, Vector3(sin(th) * (ARCH_R + 0.1), ARCH_CY + cos(th) * (ARCH_R + 0.1), 1.45 * s),
				Vector3(0.36, 0.30 if key else 0.20, 0.30), C_DRESSED, 0.004)
			v.rotation.z = -th  # 로컬 +Y가 원 중심 반대 방향(=반경 방향)을 향하게

func _windmill_hill(parent: Node) -> void:
	# 풍차 언덕(북동, 강 건너 — 북동 다리로 접근): 대지 4×4 피벗(29,-24) 전고2.5 + 램프(~17°) + 풍차.
	# ponytail: 계단은 램프로 대체(P3 드레싱), 램프=경사길 도보 등반.
	var px := 29.0
	var pz := -24.0
	var top := 2.5
	_box(parent, Vector3(px, top * 0.5, pz), Vector3(4, top, 4), C_GREEN, 0.004)  # 초지 대지
	_collide(parent, Vector3(px, top * 0.5, pz), Vector3(4, top, 4))
	# 램프: 대지 남면(z=-22)→지면. 길이8 폭3 상승2.5 → ~17°. 가시+충돌(도보 등반).
	var ramp_len := 8.0
	var ramp_ang := atan2(top, ramp_len - 1.0)
	var rc := Vector3(px, top * 0.5, pz + 6.0)  # 중심 z=-18
	var ramp := _box(parent, rc, Vector3(3, 0.3, ramp_len), C_STONE, 0.004)
	ramp.rotation.x = ramp_ang
	_collide(parent, rc, Vector3(3, 0.3, ramp_len), 0.0, ramp_ang)
	# 풍차: 탑(원통) + 지붕 + 날개(십자).
	_cyl(parent, Vector3(px, top + 1.8, pz), 1.1, 3.6, C_WALL)
	_box(parent, Vector3(px, top + 3.9, pz), Vector3(2.6, 0.5, 2.6), C_ROOF)
	_box(parent, Vector3(px, top + 2.6, pz - 1.2), Vector3(0.4, 4.0, 0.35), C_WOOD, 0.004)  # 날개 세로
	_box(parent, Vector3(px, top + 2.6, pz - 1.2), Vector3(4.0, 0.4, 0.35), C_WOOD, 0.004)  # 날개 가로

# ══ 계절 표현 (지면 톤 + 식생) ═════════════════════════════════════
# 조명(day_night.gd 키프레임)은 건드리지 않는다 — 승인된 룩. 계절은 지면색과 식생으로만 읽힌다.
# 광장 판석은 석재로 둔다(쓸어놓은 광장 = 축제 바닥이 계속 읽힌다), 해변 모래도 무변경.
const WINTER := 3

# 순수 함수: 계절 인덱스 → 지면 albedo (test_core 단위검증, 노드 불필요)
static func ground_color(season: int) -> Color:
	return C_SNOW if season == WINTER else C_GRASS

# 지면 패턴 강도. 겨울엔 절반 — 풀 2톤이 아니라 설원 요철 정도로만 남는다.
static func ground_pattern(season: int) -> float:
	return 0.45 if season == WINTER else 1.0

# 계절 상태 재적용. 신호가 없는 경로(세이브 로드·하네스의 시계 이동)에서도 한 번 명시 호출한다
# — festival_system의 "로드 후 evaluate" 전례와 같은 규약.
func _apply_season(sea: int) -> void:
	var gm := get_node_or_null("Ground/GroundMesh") as MeshInstance3D
	var m := (gm.material_override if gm != null else null) as ShaderMaterial
	if m != null:  # _ground_shader()가 깔아 둔 ground.gdshader (albedo·pattern uniform 계약)
		m.set_shader_parameter("albedo", ground_color(sea))
		m.set_shader_parameter("pattern", ground_pattern(sea))
	get_tree().call_group("decor", "apply_season", sea)

# 마을 경계 숲 띠(|x| 또는 |z| ∈ [34,40])는 P3에서 실나무 GLB MultiMesh로 이관 — decor.gd _place_forest.

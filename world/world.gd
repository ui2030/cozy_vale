extends Node3D
# A단계 월드 루트. 환경/조명 세팅 + 세이브 로드.

const ToonChar := preload("res://common/toon_character.gd")
const Interior := preload("res://world/interior.gd")  # 실내 스폰·침대 좌표 단일 출처
const Beach := preload("res://world/beach.gd")        # 해변 스폰·게이트 좌표 단일 출처
const Decor := preload("res://world/decor.gd")        # P3 드레싱(소품·꽃·숲) — 전부 무충돌
const DayNight := preload("res://world/day_night.gd") # 창불빛 점등 판정(가로등·실내등과 같은 단일 출처)
const WATER_SHADER := preload("res://world/water.gdshader")
const SKY_SHADER := preload("res://world/sky.gdshader")
const PLAZA_SHADER := preload("res://world/plaza.gdshader")
const GROUND_SHADER := preload("res://world/ground.gdshader")
const ROAD_SHADER := preload("res://world/road.gdshader")
const BRIDGE_SHADER := preload("res://world/bridge.gdshader")
const WINDOW_SHADER := preload("res://world/window.gdshader")

@onready var _sun: DirectionalLight3D = $Sun

var _vp_pinned := false  # 조망 시점(v_*) 하네스가 플레이어를 잡아 뒀다 = hour 하네스가 덮어쓰지 않는다
var _sails: Node3D  # 풍차 날개 허브 — 아주 느리게 돈다(노드 하나 회전 = 프레임 비용 무시 가능)
var _windows: Array[MeshInstance3D] = []  # 밤 창불빛 판 (아래 _window)
var _win_mat: ShaderMaterial              # 전부 공유하는 머티리얼 1장 = 프레임당 쓰기 1회

func _process(delta: float) -> void:
	if _sails != null:
		_sails.rotation.z += delta * 0.25  # ≈25초/바퀴
	if _win_mat != null:
		# 가로등·실내등과 같은 계수. 낮(f=0)엔 노드를 통째로 숨겨 그리지도 않는다 = 낮 룩 무변경.
		var f := DayNight.night_factor(GameClock.game_min / 60.0)
		_win_mat.set_shader_parameter("glow", f)
		for w in _windows:
			w.visible = f > 0.02

# 바람의 지휘봉풍 애니메이션 물 머티리얼(연못·강·분수 공용, base=C_WATER 기본값).
func _water_mat() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = WATER_SHADER
	return m

# 돌다리 석조(벽돌 켜 쌓기) 머티리얼. 외곽선은 make_solid과 같은 next_pass 방식.
func _bridge_mat(uv_shift := 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = BRIDGE_SHADER
	m.set_shader_parameter("uv_shift", Vector2(uv_shift, 0.0))  # 휜 데크 세그먼트의 벽돌 켜 이어붙이기
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
		# 언덕 위(대지 상면 y2.5). 살짝 띄워 두고 떨어뜨린다 — 대지 충돌체가 없으면 지면까지
		# 꺼져 그림에 바로 드러난다(도보 등반 가능 여부의 촬영 검증).
		"v_windmilltop": Vector3(29, 4.5, -22.6),
		"v_bridge_ne": Vector3(23, 2, -9),    # 북동 다리(23,-16) 앞
		"v_bridge_e":  Vector3(17, 2, 14),    # 동 다리(17,7) 앞
		"v_bridge_sw": Vector3(-3.5, 2, 37),  # 남서 다리(-3.5,30) 앞
		"v_bridgetop": Vector3(23, 2, -16),   # 북동 다리 위에서 강 내려다보기
		"v_houses":    Vector3(-20, 2, -6),   # 주민 집1(북서 -20,-14)
		"v_pavilion":  Vector3(-26, 2, 20),   # 정자(서 -26,14)
		"v_hall":      Vector3(0, 2, -11),    # 시계탑 회관(0,-18) 근접(고정카메라라 첨탑 상단은 프레임 위)
		"v_forest":    Vector3(-30, 2, 26),   # 남서 숲 띠 경계(P3 드레싱 검증)
		"v_bend":      Vector3(11, 2, 30),    # 강 최대 굽이(6,26·30.5°) 바깥쪽 — 물·둑 이음새 검증
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
		# 좌표를 복제하지 않고 BRIDGES에서 파생 — 다리를 옮기면 카메라도 따라온다.
		var bn: Vector2 = BRIDGES[0]
		var fa := _river_dir_at(bn)
		var fl := Vector2(sin(fa), cos(fa)) * 6.0  # 강 중심선 하류 6
		ca.global_position = Vector3(bn.x + fl.x, 0.75, bn.y + fl.y)
		ca.look_at(Vector3(bn.x, 0.45, bn.y), Vector3.UP)  # 다리 아래 개구부
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
			_vp_pinned = true  # `-- hour N`이 뒤에서 광장으로 되돌리지 않게(연못+시각 조합 컷)
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
	_ground_mat(gm)

# 메시를 초지 셰이더(절차 풀 패턴)로 바꾸고 "ground_shader" 그룹에 넣는다 — 지면과 언덕이
# 같은 문법·같은 계절색을 쓰게 하는 단일 출처(_apply_season이 그룹을 통째로 구동).
func _ground_mat(mi: MeshInstance3D, outline := 0.0) -> void:
	var m := ShaderMaterial.new()
	m.shader = GROUND_SHADER
	if outline > 0.0:
		var o := ShaderMaterial.new()
		o.shader = ToonChar.OUTLINE
		o.set_shader_parameter("width", outline)
		m.next_pass = o
	mi.material_override = m
	mi.add_to_group("ground_shader")

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
# 이 명도는 못 내린다(겨울 실루엣 카드에서 0.68까지 실측 시도) — 툰 라이팅의 lit/그늘 비가
# ~1.4라, 직광면이 포화를 벗는 값(≤0.73)으로 내리면 그늘면이 (243,219,211) 파스텔 크림에서
# (185,156,138) 갈색으로 떨어져 회관·집 근접 컷이 마을 파스텔 정체성을 잃는다(실측 스샷).
# 즉 벽은 그늘면 기준으로 고정하고, 겨울 실루엣은 눈 지면 쪽에서 벌린다(C_SNOW 참조).
const C_WALL  := Color(0.880, 0.844, 0.774)  # 크림 — 벽토/석재
const C_WOOD  := Color(0.590, 0.480, 0.362)  # 브라운 — 목재
const C_ROAD  := Color(0.700, 0.619, 0.476)  # 흙길 — 파스텔 모래빛
const C_ROAD_E := Color(0.720, 0.673, 0.590)  # 길 가장자리 — 풀로 옅어지는 톤(같은 hue, 채도만 낮춤)
# 강둑 흙 — C_ROAD(흙길) × 0.889. hue 보존, 한 단 눅눅한 흙. ×0.94는 흙길과 거의 같은 밝기라
# 길이 강에 닿는 자리에서 둑과 길이 한 덩어리로 뭉쳤다(실측 스샷). 목재 브라운(C_WOOD)을 쓰면
# 둑이 "각목 두 줄"로 읽힌다(유저 실플레이 지적) — 울타리·다리 난간과 같은 색이라 더 그렇다.
const C_BANK  := Color(0.622, 0.550, 0.422)
# 언덕 절개면(풍차 언덕 단차·사면). 강둑 흙 그대로 쓰면 정오에 흙길(0.700)과 명도가 붙어
# 사면 전체가 옛 "탠 슬래브" 한 덩어리로 다시 뭉친다(실측 after 2차) — 한 단 어둡게.
const C_CUT   := Color(0.510, 0.451, 0.346)
const C_CHANNEL := Color(0.401, 0.572, 0.650)  # 침하 채널 바닥(강·연못 공용) — 물보다 어두운 청회
const C_STONE := Color(0.770, 0.758, 0.735)  # 석재 회 — 다리/계단/분수
const C_DRESSED := Color(0.700, 0.688, 0.667)  # 다듬돌(갓돌·이맛돌) — 같은 hue 한 단 아래
# 그린 — decor.gd의 풀·덤불(수평면이라 0.72 이하로 묶는다). 풍차 언덕은 초지 셰이더로 옮겼다.
const C_GREEN := Color(0.552, 0.645, 0.508)  # 값 근거는 decor.gd 같은 상수 주석(노란 종이조각 풀)
const C_WATER := Color(0.50, 0.72, 0.85)  # 물 — 강(연못과 통일). 승인 색 = 파스텔 시프트 예외.
const C_WIST  := Color(0.720, 0.649, 0.790)  # 등나무 보라 — 퍼걸러
# 지면(world.tscn Ground/GroundMesh) 계절색 = ground.gdshader의 albedo uniform을 구동한다.
# 명도 0.80은 정오 수평면에서 G채널 255로 클리핑됐다(실측 (212,255,172)) — 패턴이 통째로 날아가는
# 값이라 0.72로 내리고 채도도 0.35→0.20으로 낮췄다. 이제 (213,245,196)쯤 = 파스텔 초지.
const C_GRASS := Color(0.627, 0.720, 0.576)  # 초지
# 눈: 순백 금지. 툰 라이팅(태양1.0 + 환경광0.55)이 albedo를 ~3.3배로 올려 화면에 낸다 —
# 실측(정오 초지 albedo 0.62 → 화면 212). albedo 0.75를 넘기면 지면이 255로 클리핑돼
# 음영·곡률이 통째로 날아가고 크림색 하늘과 지평선에서 붙어버린다.
# 0.71/0.73/0.76은 "클리핑 직전"이 아니라 이미 B가 255였고(실측 (241,247,255)), 더 나쁜 건
# 크림 벽토의 직광면(255,255,255)과 명도가 붙어 집·판매상자 실루엣이 통째로 사라진 것이다.
# 벽은 그늘면 파스텔을 지켜야 해서 못 내린다(C_WALL 주석) → 눈을 한 단 내려 벌린다.
# 0.66/0.68/0.71 → 화면 ~(221,228,238): 클리핑 없이 설원 요철이 살고, 흰 벽(255)과 명도차
# ~28로 실루엣이 읽힌다. 판석(255,242,210)·길보다 살짝 어두운 대신 청기로 눈으로 읽힌다.
# (청기를 더 주면 설원이 아니라 언 호수로 보인다 — R/G/B 간격을 좁게 유지할 것.)
const C_SNOW  := Color(0.66, 0.68, 0.71)

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
	_pond_dig(v)
	_windmill_hill(v)
	# 드레싱: 소품·꽃 덤불·숲 띠(원통+구 나무를 대체). 자체 툰 변환 + 무충돌 감사를 하므로
	# _convert_statics 이전/이후 어느 쪽이든 안전하지만, 규약대로 이전에 트리에 넣는다.
	var decor := Decor.new()
	decor.name = "Decor"
	v.add_child(decor)
	decor.build(RIVER_PTS, BRIDGES, ROADS)

# 곡률 셰이더(v.y -= 0.006·z²)는 정점 단위 — 세분할 없는 긴 박스는 장축이 현(직선)으로
# 근사돼 가운데가 지면 아래로 잠긴다(처짐 0.0015·L², N길 12u·강 물면 15u 실증). 장축을
# ~1.5u로 쪼개면 지면(60분할 평면)과 같은 곡선을 탄다. z<3이면 0 = 추가 정점 없음.
# test_core가 이 수식으로 물 박스 계약을 검증하므로 복제 금지(단일 출처).
static func _subdiv_z(len_z: float) -> int:
	return maxi(0, int(len_z / 1.5) - 1)

# 박스 메시(툰 단색). center=박스 중심.
func _box(parent: Node, center: Vector3, size: Vector3, color: Color, outline := 0.006) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.subdivide_depth = _subdiv_z(size.z)
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
	# 밤 창불빛 — 4면 각 2짝. 마을이 밤에 "캄캄한 색박스 무리"로 죽어 있던 것의 직접 처방
	# (실측 audit_0808/hall_h21·life_h21: 창 지오메트리가 아예 없다). 무충돌 = WORLD_VERSION 유지.
	var wy := h * 0.55  # 문(상단 1.8)보다 위, 회관 처마 등나무(y4.62)보다 아래
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_window(parent, Vector3(cx + sx * w * 0.28, wy, cz + sz * (d * 0.5 + 0.03)), Vector3(0.7, 0.8, 0.06))
			_window(parent, Vector3(cx + sx * (w * 0.5 + 0.03), wy, cz + sz * d * 0.28), Vector3(0.06, 0.8, 0.7))
	if solid:
		_collide(parent, Vector3(cx, h * 0.5, cz), Vector3(w, h, d))

# 창불빛 판: 벽에 붙는 얇은 박스 + window.gdshader(unshaded + 월드 곡률). 낮엔 glow 0 +
# visible=false라 그리지도 않는다. _convert_statics는 StandardMaterial3D만 보므로 통과한다.
func _window(parent: Node, center: Vector3, size: Vector3) -> void:
	if _win_mat == null:
		_win_mat = ShaderMaterial.new()
		_win_mat.shader = WINDOW_SHADER
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _win_mat
	mi.position = center
	mi.visible = false
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # 불 켜진 창이 제 벽에 그림자를 던지면 안 된다
	parent.add_child(mi)
	_windows.append(mi)

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

const PLAZA_R := 6.0  # 판석 원반 반경 — 길 끝 겹침(_lap_to_plaza)이 같은 값을 읽는다(단일 출처)

func _plaza(parent: Node) -> void:
	# 크림 판석 원형 바닥 r6 — 시각 전용 교체(메시·좌표·높이·반경 불변, 충돌체 없음).
	# 흰 디스크 → 절차 판석 패턴(world/plaza.gdshader, 텍스처 파일 0).
	var mi := _cyl(parent, Vector3(0, 0.08, 0), PLAZA_R, 0.12, C_WALL, 0.0)
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

# 길 끝단이 다리 데크에 겹치지 않게 조립 때 잘라내는 반경. 평판 다리 시절엔 색·높이가 같아
# 안 보였지만, 풀 아치 돌다리에선 길 박스가 "일자 목재"처럼 아치에 겹쳐 보인다(유저 실플레이 지적).
# 데크 리프트 소멸 지점(DECK_EDGE 3.4) + 0.2 — ROADS 데이터는 그대로 두고(decor 길가 판정 공유)
# 빌드에서만 클립한다.
const BRIDGE_TRIM := 3.6
# 길 끝을 판석 안으로 밀어 넣는 깊이. 옛 길은 광장 림(r6)에서 딱 끝났는데, road.gdshader가
# 끝단을 라운딩(corner 0.75)하고 노이즈로 최대 erode 0.45 갉아내므로 실제 끝은 r6.2~6.7에
# 남았다 — 판석과 길 사이에 초승달 잔디가 그어진 이유(실측 audit_0808/open_pav_h12).
# 0.7이면 침식 최악(0.45)에도 끝이 r5.75 = 판석 위라 잔디 틈이 생길 수 없고, 판석 위로 0.25~0.7
# 물린 흙이 "판석 가장자리에 밟혀 올라온 흙"으로 읽힌다. 길 상면 0.185 > 판석 상면 0.14라
# 겹친 구간은 길이 위로 오고, 길 박스 밑면 0.135는 판석 속이라 z-fighting도 없다.
const PLAZA_LAP := 0.7
# 다리 진입로 조각이 데크 축으로 파고드는 깊이(다리 로컬 x). 데크 상면은 x2.7에서 0.28,
# x3.02(석재 끝)에서 0.10이라 길 상면 0.185가 이 구간에서 석재 밑으로 물린다 = 흙이 돌 밑으로
# 이어진다. BRIDGE_TRIM(3.6)만으론 남던 0.6~1.0 잔디 띠가 사라진다.
const APRON_X := 2.7
# 강둑을 비우는 다리 중심 반경. 둑 오프셋 기준 흐름 방향 ±2.2가 비어 파라펫(z±1.6)을 넉넉히 벗어난다.
const BANK_GAP := 3.0
# ── 강 물면 ────────────────────────────────────────────────────
# 상면 0.23은 아래 강둑 주석과 weather.gd 빗방울 파문이 함께 쓰는 기준값이다 — 파문이 이보다
# 낮으면 불투명 툰 물에 통째로 가려 비 오는 날 수면만 잠잠해진다(실측). 값을 옮기면 둘 다 따라온다.
const WATER_TOP := 0.23
const WATER_H := 0.14   # 물면 박스 두께(상면에서 아래로) — 어두운 채널 바닥 상면 0.13 위에 얹힌다
const RIVER_W := 3.0    # 물면 폭. 반폭 1.5 = 파문 물 판정 반경
# ── 강둑 치수 ──────────────────────────────────────────────────
# 물 상면 0.23이 초지 상면 0.10보다 **높다** — 물이 잔디 위에 떠 있고, 그 단차를 가려서
# "파인 개울"로 읽히게 하는 게 둑의 유일한 임무다. 그래서 높이는 마음대로 못 낮춘다.
# 옛 값(폭1.0·높이0.7)은 그 임무를 초과 달성해 통나무 두 줄로 읽혔다(유저 실플레이 지적).
# 0.45 = 물 위 턱 0.22 · 잔디 위 노출 0.35. 폭 0.6이라 위에서 봐도 띠가 얇다.
const BANK_W := 0.6
const BANK_H := 0.45
# 안쪽 모서리를 옛 값 그대로 1.55에 붙들어 둔다(BANK_OFF − BANK_W/2). 물 반폭 1.5 대비
# 0.05 틈은 채널 바닥(어두운 상면 0.13)이 실선처럼 비치는 자리 — 현행 그림 그대로.
# 얇아진 만큼 바깥쪽만 안으로 들어온다.
const BANK_OFF := 1.85
# 물·채널바닥 박스를 세그먼트 길이보다 이만큼 길게 뽑는다(끝당 절반). 폴리라인이 각 Δ로 꺾이면
# 바깥 모서리 마이터를 채우는 데 끝당 1.5·tan(Δ/2)가 필요하다 — 옛 0.4는 Δ≤15.2°까지만 커버해
# J4(24.2°)·J5(30.5°)에 잔디 쐐기가 남았다. 1.4 = 끝당 0.7 → Δ≤50°. 안쪽 겹침은 물 셰이더가
# world_xz 기반이라 무늬가 이어져 무해.
const RIVER_PAD := 1.4

func _roads(parent: Node) -> void:
	for r in ROADS:
		var u := Vector2(sin(deg_to_rad(r[2])), cos(deg_to_rad(r[2])))
		var a: Vector2 = r[0] - u * (float(r[1]) * 0.5)
		var b: Vector2 = r[0] + u * (float(r[1]) * 0.5)
		a = _lap_to_plaza(a, b)
		b = _lap_to_plaza(b, a)
		for br in BRIDGES:
			var a0 := a
			a = _trim_to_bridge(a, b, br)
			if a != a0:
				_approach(parent, a, br)
			var b0 := b
			b = _trim_to_bridge(b, a, br)
			if b != b0:
				_approach(parent, b, br)
		var seg_len := (b - a).length()
		if seg_len < 0.5:
			continue  # 통째로 다리 밑이면 생략
		var c := (a + b) * 0.5
		_road(parent, Vector3(c.x, 0.16, c.y), Vector3(ROAD_W, 0.05, seg_len), r[2])

# 끝점 p가 다리 원(BRIDGE_TRIM) 안이면 q 방향으로 물러나 원 경계에 놓는다(원-직선 교점 근).
static func _trim_to_bridge(p: Vector2, q: Vector2, br: Vector2) -> Vector2:
	if p.distance_to(br) >= BRIDGE_TRIM:
		return p
	var u := (q - p).normalized()
	var f := p - br
	var fu := f.dot(u)
	var disc := fu * fu - (f.length_squared() - BRIDGE_TRIM * BRIDGE_TRIM)
	return p + u * (-fu + sqrt(disc))  # 안쪽이면 disc>0·해>0 보장

# 광장 림에서 끝나는 길 끝점 p를 판석 안쪽으로 PLAZA_LAP만큼 더 밀어 넣는다(_trim_to_bridge의 반대).
# 길 직선 위에서만 움직이므로 ROADS의 회전각 r[2]가 그대로 유효하다. 방사형 길이라 이동 후
# 반경은 r5.3±0.03 — 원-직선 정해를 풀 필요가 없다.
static func _lap_to_plaza(p: Vector2, q: Vector2) -> Vector2:
	if p.length() > PLAZA_R + 0.6:
		return p  # 광장 림에서 시작하는 끝이 아니다(다리·집·해변 쪽 끝)
	return p + (p - q).normalized() * (p.length() - (PLAZA_R - PLAZA_LAP))

# 다리 진입로: 잘린 길 끝(반경 BRIDGE_TRIM)을 데크 발치에 잇는 짧은 흙길 조각.
# 길 접근각이 데크 축과 최대 55° 어긋나 있어(NE 길·동안 남길) 원형 트림만으론 길 끝이
# 다리 **옆** 잔디에 남는다(실측 audit_0808/bridge_ne_h12·bridge_e_h12). 조각은 그 끝을
# 데크 축 위 로컬(±APRON_X, 0)까지 잇는다 = 흙길이 돌다리 발치로 모여드는 진입 마당.
func _approach(parent: Node, from: Vector2, br: Vector2) -> void:
	var ang := _river_dir_at(br)
	var d := from - br
	var lx := d.x * cos(ang) - d.y * sin(ang)   # deck_lift와 같은 로컬 투영 (로컬 +X = 강 횡단)
	var side := 1.0 if lx >= 0.0 else -1.0
	var to: Vector2 = br + Vector2(cos(ang), -sin(ang)) * (APRON_X * side)  # 로컬(±APRON_X,0)→월드
	var v := to - from
	var l := v.length()
	if l < 0.5:
		return  # 이미 데크 발치까지 와 있다(짧은 조각은 침식 때문에 오히려 얼룩이 된다)
	var c := (from + to) * 0.5
	_road(parent, Vector3(c.x, 0.16, c.y), Vector3(ROAD_W, 0.05, l), rad_to_deg(atan2(v.x, v.y)))

func _road(parent: Node, center: Vector3, size: Vector3, rot_deg: float) -> MeshInstance3D:
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
	return mi

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
# 다리 중심은 강 중심선(폴리라인) 위에 있어야 한다 — 벗어나면 양안 강둑 컷이 비대칭이 되고
# 아치가 채널에 편심으로 걸린다. 북동은 옛 (23,-16)이 S1 위 최근접점에서 0.32 어긋나 있었다.
const BRIDGES := [Vector2(22.7, -16.1), Vector2(17, 7), Vector2(-3.5, 30.2)]  # 북동/동/남서
const BRIDGE_GAP := 2.4  # 다리에서 충돌벽을 비우는 반경(폭 방향 통과 확보)

func _river_and_bridges(parent: Node) -> void:
	for i in RIVER_PTS.size() - 1:
		var a: Vector2 = RIVER_PTS[i]
		var b: Vector2 = RIVER_PTS[i + 1]
		var ang := atan2(b.x - a.x, b.y - a.y)  # 로컬+Z가 a→b 향하게 y회전
		var mid := (a + b) * 0.5
		var span := (b - a).length()
		var perp := Vector2((b - a).y, -(b - a).x).normalized()  # 강 수직(강둑 오프셋)
		var floor_box := _box(parent, Vector3(mid.x, -0.02, mid.y), Vector3(3.2, 0.3, span + RIVER_PAD), C_CHANNEL, 0.0)
		floor_box.rotation.y = ang  # 어두운 채널 바닥(깊이감)
		var water := _box(parent, Vector3(mid.x, WATER_TOP - WATER_H * 0.5, mid.y), Vector3(RIVER_W, WATER_H, span + RIVER_PAD), C_WATER, 0.0)
		water.rotation.y = ang      # 밝은 물면(강둑보다 낮게 inset), 폭3
		water.material_override = _water_mat()  # 애니 물(연못과 통일)
		var dir := (b - a) / span   # 흐름 단위벡터(끝조각 연장 방향)
		var ext_a := _bank_ext(i, false)
		var ext_b := _bank_ext(i, true)
		for s in [1.0, -1.0]:       # 양안 강둑(흙) — 물면보다 0.22 높아 파인 채널로 읽힘
			# 다리 근처는 비운다(충돌벽과 같은 분절 방식) — 둑이 아치 발치(데크 끝 높이 ~0.55)
			# 보다 높으면 다리 끝이 흙에 먹힌 그림이 된다(유저 실플레이 지적).
			var bsteps := maxi(1, int(ceil(span / 1.4)))
			var bstep := (b - a) / bsteps
			for k in bsteps:
				# 굽이 바깥 결손은 런의 첫/끝 조각만 관절 쪽으로 늘려 마이터로 만난다.
				# (전 조각 균일 패딩은 겹침마다 외곽선 next_pass가 이중선을 그린다.)
				var e0 := ext_a if k == 0 else 0.0
				var e1 := ext_b if k == bsteps - 1 else 0.0
				var bc: Vector2 = a + bstep * (k + 0.5) + perp * (BANK_OFF * s) + dir * ((e1 - e0) * 0.5)
				var near_bridge := false
				for br in BRIDGES:
					if bc.distance_to(br) < BANK_GAP:
						near_bridge = true
						break
				if near_bridge:
					continue
				var bank := _box(parent, Vector3(bc.x, BANK_H * 0.5, bc.y), Vector3(BANK_W, BANK_H, bstep.length() + 0.1 + e0 + e1), C_BANK, 0.004)
				bank.rotation.y = ang
		_river_wall_seg(parent, a, b, ang)  # 분절 충돌벽(다리 gap 제외)
	for br in BRIDGES:
		_arch_bridge(parent, br, _river_dir_at(br))

# 세그먼트 i의 강둑 런을 관절 쪽으로 얼마나 늘려야 굽이 바깥에서 이웃 런과 마이터로 만나는가.
# 오프셋 라인(BANK_OFF)끼리의 교점이 관절에서 BANK_OFF·tan(Δ/2)만큼 앞서 있어 그만큼 모자란다.
# at_end=false는 a끝(정점 i), true는 b끝(정점 i+1). 강 양 끝 정점은 굽이가 없으므로 0.
static func _bank_ext(i: int, at_end: bool) -> float:
	var j: int = i + 1 if at_end else i
	if j <= 0 or j >= RIVER_PTS.size() - 1:
		return 0.0
	var p0: Vector2 = RIVER_PTS[j - 1]
	var p1: Vector2 = RIVER_PTS[j]
	var p2: Vector2 = RIVER_PTS[j + 1]
	return BANK_OFF * tan(absf((p1 - p0).angle_to(p2 - p1)) * 0.5)

# 연못(world.tscn Pond)을 **강과 같은 문법**으로 판다: 어두운 채널 바닥 + 물 상면보다 높은 둑.
# 옛 연못은 지면 위에 얹힌 파란 원반이라 물가에 선 캐릭터가 물 위에 서 있었다(audit_0808/pond_h12).
# 수면 디스크·낚시 트리거·라벨은 손대지 않는다(세이브·프롬프트 계약) — 중심·반경은 수면 메시
# AABB에서 읽으므로 tscn이 단일 출처다(weather.gd 파문 물영역이 쓰는 그 방식).
# 강과 같은 값: 채널 바닥 상면 0.13 · 물과 둑 사이 틈 0.05(바닥이 실선으로 비침) · 둑 폭 BANK_W ·
# 둑 상면 BANK_H. 다만 둑은 박스 줄이 아니라 토러스 한 장이다 — 원형 런에선 조각마다 마이터가
# 겹쳐 이음매 외곽선이 이중선으로 뜬다(강둑 주석의 그 문제). 단면만 둥글고 폭·높이·색은 강과 같다.
# 무충돌(강둑과 동일). NPC는 연못 keepout 2.9+BLOCK_PAD 0.3 = 3.2 밖으로만 다니므로 둑 바깥
# 모서리(반경 3.15)를 밟지 않는다 — npc_system.BUILDING_KEEPOUT과의 계약.
func _pond_dig(parent: Node) -> void:
	var mi := get_node_or_null("Pond/PondMesh") as MeshInstance3D
	if mi == null or mi.mesh == null:
		push_warning("연못 수면 메시 없음 — 채널·둑 생략")
		return
	var box: AABB = mi.global_transform * mi.mesh.get_aabb()
	var c := box.get_center()
	var r := box.size.x * 0.5
	_cyl(parent, Vector3(c.x, -0.02, c.z), r + 0.1, 0.3, C_CHANNEL, 0.0)  # 채널 바닥(상면 0.13)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = r + 0.05
	tm.outer_radius = r + 0.05 + BANK_W
	ring.mesh = tm
	ring.material_override = ToonChar.make_solid(C_BANK, 0.004)
	ring.position = Vector3(c.x, BANK_H - BANK_W * 0.5, c.z)  # 튜브 상면 = BANK_H
	parent.add_child(ring)

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

# 점 p에서 가장 가까운 강 세그먼트의 흐름 방향(y회전각). deck_lift도 쓰므로 static.
static func _river_dir_at(p: Vector2) -> float:
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
#  · 데크 상면 곡선의 단일 출처 = 아래 deck_top(). npc_system.DECK_Y/_deck_y, player의 시각
#    리프트가 전부 여기서 파생한다(식 복제 금지 — test_core가 어긋남을 잡는다).
#  · 중앙 통로 z∈(-1.3,1.3)엔 아무것도 새로 넣지 않는다. 다리엔 충돌이 없어 플레이어·NPC는
#    데크 아래 지면 높이로 지나간다 — 아치 구조를 통로에 채우면 캐릭터가 돌 속에 파묻힌다.
#    그래서 아치는 양 측벽(스팬드럴)에만 뚫고, 가운데는 예전처럼 비워 둔다.
#  · 충돌체 0 유지(CSGShape3D.use_collision 기본 false).
const ARCH_R := 2.68    # 아치 원 반지름 — 관정 = ARCH_CY + ARCH_R = 0.85 (데크 밑면 1.00 아래 0.15)
const ARCH_CY := -1.83  # 아치 원 중심 y (스프링 = 지면 y0에서 ±1.958 → 개구부 폭 3.92 > 물폭 3.0)
const ARCH_N := 11      # 홍예석(voussoir) 개수 — 아치 곡선을 두르는 다듬돌

# ── 풀 아치 프로파일 (평탄 구간 없는 연속 원호) ──────────────────────
# 양 끝(±3.0, 0.10)과 관정(0, 1.30)을 지나는 원호 하나. 옛 스무스스텝은 관정이 평평해
# "혹등"으로 읽혔다 — 원호는 끝까지 곡률이 살아 동물의숲식 둥근 석교가 된다.
# 반지름 R = (a² + h²)/2h (a=반경간, h=상승) — 끝 경사 43.6°, 셰이더 투영축이 뒤집히는
# 45°보다 여전히 낮다(게다가 세그먼트마다 모델 로컬 법선이 +Y라 애초에 안 뒤집힌다).
# |x| 3.0~3.4는 원호 끝 0.10을 지면 0으로 무는 짧은 테이퍼(14°) — 리프트가 트리거 반경
# 경계에서 딱 0이라 다리를 벗어날 때 발이 튀지 않는다.
const DECK_CROWN := 1.30   # 관정 높이 (= npc_system.DECK_Y)
const DECK_END := 0.10     # 원호 끝 높이 = 지면 상면(GroundMesh y=0.1)
const DECK_HALF_X := 3.0   # 경간 6의 절반 = 원호 구간
const DECK_EDGE := 3.4     # 리프트가 0이 되는 반경 (= npc_system.DECK_HALF, 데크 양끝 웨이포인트)
const DECK_ARC_R := (DECK_HALF_X * DECK_HALF_X + (DECK_CROWN - DECK_END) * (DECK_CROWN - DECK_END)) / (2.0 * (DECK_CROWN - DECK_END))
const DECK_SEG := 16       # 곡선을 나눈 판석 수 (조각당 5.5° — 실루엣이 각지지 않게)
# 데크 폭(로컬 z) — 리프트는 데크 위에서만. 축에서 벗어난 강바닥까지 들어올리면 다리 옆에서
# 몸이 공중에 뜬다(NPC는 축 위만 걷지만 플레이어는 아무 데나 간다).
const DECK_Z_HALF := 1.5   # 데크 반폭(= 데크 박스 z=3, 난간 중심)
const DECK_Z_EDGE := 2.0   # 여기서 리프트 0

static func deck_top(x: float) -> float:
	var d := absf(x)
	if d >= DECK_EDGE:
		return 0.0
	if d > DECK_HALF_X:  # 원호 끝(0.10) → 지면(0) 테이퍼
		return DECK_END * (DECK_EDGE - d) / (DECK_EDGE - DECK_HALF_X)
	return DECK_CROWN - (DECK_ARC_R - sqrt(DECK_ARC_R * DECK_ARC_R - d * d))

# 월드 좌표 p에서 밟고 있는 데크 상면 높이 (다리 밖이면 0). NPC·플레이어 공용 단일 출처.
# 다리 로컬 프레임으로 투영해서 쓴다: +X = 강 횡단(데크 축), +Z = 흐름. 반경거리로 재면
# 다리 옆(흐름 방향)으로 비켜서도 리프트가 걸려 강 위에 떠 있는 그림이 나온다.
static func deck_lift(p: Vector2) -> float:
	var best := 0.0
	for br in BRIDGES:
		var ang := _river_dir_at(br)  # holder rotation.y와 동일 — 로컬 +Z가 흐름
		var d: Vector2 = p - br
		var lx := d.x * cos(ang) - d.y * sin(ang)
		var lz := d.x * sin(ang) + d.y * cos(ang)
		var fade := clampf((DECK_Z_EDGE - absf(lz)) / (DECK_Z_EDGE - DECK_Z_HALF), 0.0, 1.0)
		best = maxf(best, deck_top(lx) * fade)
	return best

func _arch_bridge(parent: Node, at: Vector2, ang: float) -> void:
	var h := Node3D.new()
	h.position = Vector3(at.x, 0, at.y)
	h.rotation.y = ang
	parent.add_child(h)
	# 데크·난간·갓돌을 deck_top() 곡선 위 세그먼트로 깐다(= 휜 데크). 세그먼트 상면이 현(chord)에
	# 놓이도록 로컬 수직으로 두께의 절반만큼 내린다. 길이는 dx가 아니라 현 길이여야 한다 —
	# 경사 35°에서 dx만 쓰면 조각 사이가 벌어진다.
	var s_run := 0.0  # 누적 호길이 → 셰이더 uv_shift(조각마다 벽돌 켜가 리셋되지 않게)
	for i in DECK_SEG:
		var x0 := lerpf(-DECK_HALF_X, DECK_HALF_X, i / float(DECK_SEG))
		var x1 := lerpf(-DECK_HALF_X, DECK_HALF_X, (i + 1) / float(DECK_SEG))
		var y0 := deck_top(x0)
		var y1 := deck_top(x1)
		var th := atan2(y1 - y0, x1 - x0)
		var chord := Vector2(x1 - x0, y1 - y0).length()
		var mid := Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, 0)
		var up := Vector3(-sin(th), cos(th), 0)  # 세그먼트 로컬 수직
		var shift := s_run + chord * 0.5         # BoxMesh는 중심이 원점 → 중심까지의 호길이
		s_run += chord
		var deck := _box(h, mid - up * 0.15, Vector3(chord * 1.06, 0.3, 3), C_STONE, 0.0)
		deck.rotation.z = th
		deck.material_override = _bridge_mat(shift)
		for s in [1.0, -1.0]:
			# 난간(파라펫) — 데크 상면에서 0.27, 갓돌 상단은 그 위 0.13 (= 데크 상면 +0.40).
			# decor.gd 등나무 앵커가 이 +0.40을 파생값으로 박아 둔다(순환 preload 불가 → 주석 유도).
			var rail := _box(h, mid + up * 0.135 + Vector3(0, 0, 1.5 * s), Vector3(chord * 1.06, 0.27, 0.20), C_STONE, 0.0)
			rail.rotation.z = th
			rail.material_override = _bridge_mat(shift)
			# 갓돌·이맛돌은 벽돌 패턴 없는 다듬돌(민면). C_STONE 그대로면 정오 직광에서 흰색으로
			# 포화해 벽돌면과 붙는다(실측) — 한 단 낮춰야 매끈한 돌로 읽힌다.
			# 조각을 15% 겹쳐 꺾인 이음매를 메운다(민면이라 겹침이 안 보인다).
			var cap := _cyl(h, mid + up * 0.27 + Vector3(0, 0, 1.5 * s), 0.13, chord * 1.15, C_DRESSED, 0.004)
			cap.rotation.z = PI * 0.5 + th
	# 아치 측벽 2장 − 원기둥 = 단경간 세그먼트 아치(관정 y=0.85, 스프링 ±1.96).
	# 수면(폭3.0·상면0.23) 위로 0.62 트인다(옛 0.37). 벽 밑(-0.1)은 지면에 묻혀 접지로 읽힌다.
	var arch := CSGCombiner3D.new()
	for s in [1.0, -1.0]:
		var w := CSGBox3D.new()
		w.size = Vector3(6, 1.5, 0.25)   # 관정 데크 밑(1.15)까지 닿게 (y -0.1 ~ 1.4)
		w.position = Vector3(0, 0.65, 1.425 * s)
		arch.add_child(w)
	# 벽 윗변을 데크 원호 밑으로 깎는다 — 데크와 **동심원** 하나로 교집합(INTERSECTION).
	# 반지름을 0.15 줄이면 법선 방향 0.15 아래 = 어디서나 데크 슬래브(두께 0.3) 한가운데다.
	# (v2의 직선 램프 근사는 원호에선 안 맞는다. 곡선 컷이 오히려 프리미티브 하나로 끝난다.)
	var cap_cut := CSGCylinder3D.new()
	cap_cut.radius = DECK_ARC_R - 0.15
	cap_cut.height = 3.4       # 측벽 두 장을 한 번에 덮는다(z 방향으로 잘리지 않게)
	cap_cut.sides = 64
	cap_cut.rotation.x = PI * 0.5
	cap_cut.position = Vector3(0, DECK_CROWN - DECK_ARC_R, 0)  # 데크 원호의 중심
	cap_cut.operation = CSGShape3D.OPERATION_INTERSECTION
	arch.add_child(cap_cut)
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
	# 풍차 언덕(북동, 강 건너 — 북동 다리로 접근): 대지 4×4 피벗(29,-24) 전고2.5 + 남면 경사 + 풍차.
	#
	# 대지·단은 **초지 셰이더**(_ground_mat) — 주변 초지와 같은 절차 풀 패턴·같은 계절색.
	#
	# ── 실루엣: 대지 하나(4×4 박스)는 "잔디 얹은 상자"였다(실측 windmill_h12). 남면(z=-22)을
	#    맞춘 낮은 단 2개를 두르면 3단(0.6 / 1.25 / 2.5)이 되어 언덕으로 읽힌다. 단의 최대
	#    코너 반경 3.89는 decor.gd 풍차 대지 keepout(r4.0) 안 — 소품이 단에 먹히지 않는다.
	#    (대지 4×4×2.5 피벗(29,-24)은 좌표·치수 불변 — 다리 접근 동선과 충돌 계약.)
	var px := 29.0
	var pz := -24.0
	var top := 2.5
	for t in [[5.4, 4.8, 0.6], [4.7, 4.4, 1.25], [4.0, 4.0, 2.5]]:  # [폭x, 깊이z, 높이]
		var s := Vector3(float(t[0]), float(t[2]), float(t[1]))
		var c := Vector3(px, s.y * 0.5, pz + 2.0 - s.z * 0.5)
		# 흙 절개면: 같은 상자를 0.06 넓고 0.06 낮게 겹쳐 **수직면만** 흙으로 덮는다(윗면은 초지).
		# 툰 light()는 면 방향으로 명암이 거의 안 갈린다 — 초지끼리는 단차·경사를 줘도 같은 톤이라
		# 언덕이 통째로 사라졌다(실측 after 1차). 강둑과 같은 계열의 흙(C_CUT)이라야 켜가 읽힌다.
		_box(parent, Vector3(c.x, (s.y - 0.06) * 0.5, c.z), Vector3(s.x + 0.06, s.y - 0.06, s.z + 0.06), C_CUT, 0.004)
		_ground_mat(_box(parent, c, s, C_GRASS, 0.004), 0.004)
		_collide(parent, c, s)
	# ── 남면 경사: 초지 쐐기 + 그 위 흙길. 옛 두께 0.3 슬래브는 지면 위에 떠 하드엣지로 잘린
	#    "혓바닥"이었다(실측). 두께를 3.4로 키워 아랫면을 지면 밑에 묻으면 옆에서 본 단면이
	#    삼각형 = 쐐기가 된다. **윗면(=걷는 면)·폭·각도는 옛 슬래브와 같은 평면**이라 동선 불변.
	#    길은 마을 도로와 같은 road.gdshader(라운드 SDF − 노이즈 침식) — 하드엣지가 사라지고,
	#    폭을 ROAD_W(2.4)로 줄여 쐐기 초지가 길 양옆에 0.3씩 남는다(= 풀언덕 위의 오솔길).
	var ramp_len := 8.0
	var ramp_ang := atan2(top, ramp_len - 1.0)
	var rc := Vector3(px, top * 0.5, pz + 6.0)  # 중심 z=-18 (옛 슬래브 중심 — 불변)
	var up := Vector3(0, cos(ramp_ang), sin(ramp_ang))  # rotation.x=ang 후의 로컬 +Y
	var wedge_c := rc - up * 1.55  # 윗면이 옛 슬래브 윗면(rc + up*0.15)과 같은 평면에 오게
	# 외곽선은 0 — 대부분 지면 아래인 상자에 외곽선 셸을 씌우면 셸이 잔디를 뚫고 나와 사면 양옆에
	# 점선 두 줄이 그어진다(실측 after 1차). 쐐기는 흙 절개면 색으로 갈린다.
	# 덧폭은 0.04(면당 0.02)까지만 — 0.06이면 사면 발치(윗면이 지면과 같은 높이인 구간)에서
	# 절개면이 잔디 밖으로 0.03 삐져나와 길 양옆에 갈색 실선 두 줄이 그어진다(실측 after 3차).
	var wedge_e := _box(parent, wedge_c - up * 0.06, Vector3(3.04, 3.4, ramp_len + 0.04), C_CUT, 0.0)
	wedge_e.rotation.x = ramp_ang
	var wedge := _box(parent, wedge_c, Vector3(3, 3.4, ramp_len), C_GRASS, 0.0)
	wedge.rotation.x = ramp_ang
	_ground_mat(wedge)
	_collide(parent, wedge_c, Vector3(3, 3.4, ramp_len), 0.0, ramp_ang)
	var path := _road(parent, rc + up * 0.15, Vector3(ROAD_W, 0.1, ramp_len), 0.0)
	path.rotation.x = ramp_ang  # 절반만 쐐기에 묻혀 동일면 z-fighting이 없다
	# ── 풍차: 사다리꼴 탑 + 원뿔 지붕(_clock_tower 문법) + 문 + 4팔 격자 날개.
	#    옛 조립은 원통 + 보라 슬래브 + 각목 십자 2개라 "방앗간 간판"으로 읽혔다(실측).
	# 탑 높이 3.7 = 상한이다. 고정 게임카메라의 접근 시점(v_windmill)에서 프레임 상단이 월드
	# y≈8.2다(실측) — 4.2로 올렸더니 보라 원뿔 지붕이 통째로 프레임 밖으로 잘려 "지붕 없는
	# 원통"이 됐다. 3.7이면 원뿔 꼭짓점 7.72·꼭대기 장식 7.86이 프레임 안에 들어온다.
	var th := 3.7
	var tower := _cyl(parent, Vector3(px, top + th * 0.5, pz), 1.35, th, C_WALL)
	(tower.mesh as CylinderMesh).top_radius = 0.95  # 아래가 넓은 몸통 = 풍차의 기본 실루엣
	_cyl(parent, Vector3(px, top + th + 0.16, pz), 1.5, 0.32, C_ROOF, 0.004)  # 보라 처마 링
	var cap := _cyl(parent, Vector3(px, top + th + 0.92, pz), 1.4, 1.2, C_ROOF)
	(cap.mesh as CylinderMesh).top_radius = 0.0  # 원뿔 모자
	_box(parent, Vector3(px, top + th + 1.66, pz), Vector3(0.34, 0.34, 0.34), C_ROOF2, 0.004)  # 마루 밝은면
	_box(parent, Vector3(px, top + 0.9, pz + 1.24), Vector3(0.8, 1.8, 0.16), C_WOOD, 0.004)    # 문(경사 쪽 남면)
	# 날개는 마을(남서)을 향한 **남면**에 단다 — 옛 위치(pz−1.2)는 탑 뒤라 팔 끝만 삐죽 나왔다.
	# 대(spar) 하나로는 판자로 읽힌다: 살 4줄 + 돛천 한 폭이 있어야 풍차 날개가 된다.
	# 날개 원판면은 z=-21.7 = 대지 남면(-22)보다 **밖**이다. 옛 십자는 대지 한가운데(pz−1.2)에
	# 최저점 y3.1로 걸려 있어 대지 위에 선 플레이어(발2.5·캡슐1.6)를 상시 관통했다 — 원판을
	# 대지 밖으로 빼면 걸어다니는 면과 겹치지 않는다. (램프 최상단 0.8폭 구간만 팔 끝이 스친다.)
	_sails = Node3D.new()
	_sails.position = Vector3(px, top + th - 0.2, pz + 2.3)
	parent.add_child(_sails)
	_cyl(_sails, Vector3(0, 0, -0.55), 0.3, 1.6, C_WOOD).rotation.x = PI * 0.5  # 풍축(탑까지 잇는다)
	for i in 4:
		var arm := Node3D.new()
		arm.rotation.z = TAU * i / 4.0
		_sails.add_child(arm)
		_box(arm, Vector3(0, 1.05, 0), Vector3(0.17, 2.1, 0.13), C_WOOD, 0.004)       # 대
		_box(arm, Vector3(0.33, 1.2, -0.06), Vector3(0.48, 1.6, 0.06), C_ROOF2, 0.004)  # 돛천
		for j in 4:
			_box(arm, Vector3(0.3, 0.6 + j * 0.42, 0.02), Vector3(0.66, 0.09, 0.07), C_WOOD, 0.0)  # 살

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
	# _ground_mat()이 깔아 둔 ground.gdshader들 (albedo·pattern uniform 계약) = 지면 + 풍차 언덕
	for n in get_tree().get_nodes_in_group("ground_shader"):
		var m := (n as MeshInstance3D).material_override as ShaderMaterial
		if m != null:
			m.set_shader_parameter("albedo", ground_color(sea))
			m.set_shader_parameter("pattern", ground_pattern(sea))
	get_tree().call_group("decor", "apply_season", sea)

# 마을 경계 숲 띠(|x| 또는 |z| ∈ [34,40])는 P3에서 실나무 GLB MultiMesh로 이관 — decor.gd _place_forest.

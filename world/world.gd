extends Node3D
# A단계 월드 루트. 환경/조명 세팅 + 세이브 로드.

const ToonChar := preload("res://common/toon_character.gd")
const WATER_SHADER := preload("res://world/water.gdshader")
const SKY_SHADER := preload("res://world/sky.gdshader")

@onready var _sun: DirectionalLight3D = $Sun

# 바람의 지휘봉풍 애니메이션 물 머티리얼(연못·강·분수 공용, base=C_WATER 기본값).
func _water_mat() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = WATER_SHADER
	return m

func _ready() -> void:
	_sun.rotation_degrees = Vector3(-52, -125, 0)
	_add_env()
	_build_village()        # 마을 P1 컬러박스 (임시 지오메트리, make_solid=곡면 툰)
	_convert_statics(self)  # tscn 정적 물체(바닥·기능물)를 곡면 툰으로 통일
	_water_audio()          # 물가 3D 앰비언스 (연못·분수·강)
	if not SaveManager.load_game():
		print("새 게임 시작")
	# from_dict는 신호를 안 쏘므로 로드된 시각으로 축제 배치를 즉시 재평가 (축제날 아침 로드 누락 방지)
	if "festival" in OS.get_cmdline_user_args():  # 스크린샷 검증용 강제 축제
		GameClock.abs_day = 14   # spring D15
		GameClock.game_min = 720  # 12:00
		var pl := get_tree().get_first_node_in_group("player")
		if pl != null:  # 광장이 카메라에 잡히도록 플레이어를 광장 남쪽(분수·밭 밖)으로
			pl.global_position = Vector3(0, 2, -3.5)
	get_tree().call_group("festival_system", "evaluate")
	if "pausemenu" in OS.get_cmdline_user_args():  # 스크린샷 검증용 메뉴 열기
		get_tree().call_group("pause_menu", "open_menu")
	if "bedshot" in OS.get_cmdline_user_args():  # 스크린샷 검증용: 침대 옆(프롬프트+라벨)
		var pb := get_tree().get_first_node_in_group("player")
		if pb != null:
			pb.global_position = Vector3(3, 2, 17.2)  # 플레이어 집 침대(3,16) 남쪽
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
	}
	for _k in _vp:
		if _k in OS.get_cmdline_user_args():
			var pv := get_tree().get_first_node_in_group("player")
			if pv != null:
				pv.global_position = _vp[_k]
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
	# 날씨 검증: -- weather rain|clear. 날씨는 abs_day 결정적이라 강제 스위치를 두는 대신
	# 원하는 날씨의 첫 봄날로 시계를 옮긴다(실제 판정 함수를 그대로 통과 — 프로덕션 코드에 테스트 훅 0).
	var _wi := _args.find("weather")
	if _wi != -1 and _wi + 1 < _args.size():
		SaveManager.set_process(false)  # 세이브 미변경
		var want: bool = _args[_wi + 1] == "rain"
		for d in 28:  # 봄 안에서 (계절 고사·채집 풀 영향 없이)
			if GameData.is_rainy(d) == want:
				GameClock.abs_day = d
				break
		print("weather shot: abs_day=", GameClock.abs_day, " rainy=", GameData.is_rainy(GameClock.abs_day))
	# 낮밤 검증: -- hour N (시계를 N시로 강제, PAUSED 고정 → FAST shot 흐름과 분리). 세이브 미변경.
	var _hi := _args.find("hour")
	if _hi != -1 and _hi + 1 < _args.size():
		SaveManager.set_process(false)  # SaveManager._process 기본활성 1프레임 자동쓰기 억제 → 세이브 무변경
		GameClock.game_min = int(_args[_hi + 1]) * 60
		GameClock.state = GameClock.State.PAUSED
		var ph := get_tree().get_first_node_in_group("player")
		if ph != null:  # 세이브 무관하게 광장 조망으로 고정
			ph.global_position = Vector3(0, 2, -3.5)
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
	var rel: String = args[oi + 1] if oi != -1 and oi + 1 < args.size() else "world.png"
	DirAccess.make_dir_recursive_absolute("res://lookdev/shots/" + rel.get_base_dir())
	img.save_png("res://lookdev/shots/" + rel)
	print("saved ", rel, "  clock=", GameClock.hour(), ":", GameClock.minute())
	get_tree().quit()

# 낮밤 조명 검증 캡처: PAUSED 유지(시계 N:00 고정), 조명 안정 후 1회 캡처. 세이브 미변경.
func _shot_hour(hn: int) -> void:
	await get_tree().create_timer(0.6).timeout  # 물리 착지 + day_night 파라미터 적용 대기
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var args := OS.get_cmdline_user_args()
	var wi := args.find("weather")
	var rel := "daynight/hour_%02d.png" % hn
	if wi != -1 and wi + 1 < args.size():  # 날씨 강제 샷은 별도 폴더로
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
const C_ROOF  := Color(0.42, 0.31, 0.56)  # 보라 진 — 지붕 기와(마을 아이덴티티)
const C_ROOF2 := Color(0.56, 0.43, 0.69)  # 보라 중 — 지붕 밝은면
const C_WALL  := Color(0.90, 0.85, 0.76)  # 크림 — 벽토/석재
const C_WOOD  := Color(0.54, 0.40, 0.25)  # 브라운 — 목재/흙길
const C_STONE := Color(0.72, 0.70, 0.66)  # 석재 회 — 다리/계단/분수
const C_GREEN := Color(0.58, 0.66, 0.36)  # 그린 — 언덕
const C_WATER := Color(0.50, 0.72, 0.85)  # 물 — 강(연못과 통일)
const C_WIST  := Color(0.62, 0.50, 0.74)  # 등나무 보라 — 퍼걸러

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
	# 플레이어 집(남, 밭 남쪽) — footprint 5×5, 피벗(3,15), 전고 5. DECOR(무충돌: 편입 침대 접근용).
	# (6,13)→(3,15): 광장 림 이격 5.07→6.5로 규정(≥6) 충족 (Fable 검수 반영)
	# door_sign -1 = 북향 문(광장·남측 길 방향 — 남향 기본문이면 길이 문 반대면에 닿음)
	_house(v, Vector3(3, 0, 15), 5, 5, 5, false, -1.0)
	# 정자(서, 집C와 ≥8) — footprint 4×4, 피벗(-26,14), 전고 3. DECOR(개방 퍼걸러).
	_pavilion(v, Vector3(-26, 0, 14))
	_river_and_bridges(v)
	_windmill_hill(v)
	_forest_belt(v)

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
	_cyl(parent, Vector3(0, 0.08, 0), 6.0, 0.12, C_WALL, 0.0)  # 크림 판석 원형 바닥 r6

func _roads(parent: Node) -> void:
	# 방사 6갈래(폭 2.4, 흙길 브라운). 광장 림(r6)→각 구역까지 길게 뻗어 여백 연출.
	# center=림~구역 중점, rot=atan2(dx,dz)(박스 장축 z를 방향에 정렬). 방향은 스샷 튜닝 대상.
	var y := 0.16
	_road(parent, Vector3(0, y, -12), Vector3(2.4, 0.05, 12), 0)          # N→회관(0,-18)
	_road(parent, Vector3(-12.5, y, -8.7), Vector3(2.4, 0.05, 18), -125)  # NW→House1(-20,-14)
	_road(parent, Vector3(-15.4, y, 4.9), Vector3(2.4, 0.05, 20), -72)    # W→정자·집2 방면(조준점 -25,8)
	_road(parent, Vector3(-8.6, y, 13.5), Vector3(2.4, 0.05, 20), -33)    # SW→House3(-14,22)
	_road(parent, Vector3(2.1, y, 9.2), Vector3(2.4, 0.05, 7), 11)        # S→플레이어집(3,15)
	_road(parent, Vector3(11.3, y, 4.6), Vector3(2.4, 0.05, 12), 68)      # E→동 다리(17,7)
	# 지도 충실화(Fable 탑다운 대조 반영): 모든 다리는 길로 연결 + 동안(東岸) 경로.
	_road(parent, Vector3(12.6, y, -10.1), Vector3(2.4, 0.05, 20.5), 125)  # NE→북동 다리(23,-16)
	_road(parent, Vector3(-2.5, y, 17.25), Vector3(2.4, 0.05, 23), -5)     # S외곽→남서 다리(-3.5,30)
	_road(parent, Vector3(27.45, y, -14.8), Vector3(2.4, 0.05, 3.2), 79)   # 동안 북: 북동 다리 동단→풍차 램프 발치(강둑·대지 회피, Codex MUST-FIX)
	_road(parent, Vector3(22, y, 12.75), Vector3(2.4, 0.05, 10.3), 23)     # 동안 남: 동 다리→집4(24,20)

func _road(parent: Node, center: Vector3, size: Vector3, rot_deg: float) -> void:
	var mi := _box(parent, center, size, C_WOOD, 0.0)
	mi.rotation.y = deg_to_rad(rot_deg)

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
		var floor_box := _box(parent, Vector3(mid.x, -0.02, mid.y), Vector3(3.2, 0.3, span + 0.4), Color(0.28, 0.5, 0.6), 0.0)
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

# 석조 아치 다리: 강 수직(perp)으로 데크가 채널을 가로지름. 데크·난간·교각 무충돌(통행=벽 gap).
func _arch_bridge(parent: Node, at: Vector2, ang: float) -> void:
	var flow := Vector2(sin(ang), cos(ang))       # 강 흐름 방향(로컬+Z)
	var perp := Vector2(cos(ang), -sin(ang))      # 가로지르는 방향(로컬+X)
	var deck := _box(parent, Vector3(at.x, 0.75, at.y), Vector3(6, 0.3, 3), C_STONE, 0.004)
	deck.rotation.y = ang                          # X=6 가로지름(폭 확보), Z=3 보도폭
	for s in [1.0, -1.0]:                           # 난간(흐름 방향 양측)
		var rc: Vector2 = at + flow * (1.5 * s)
		var rail := _box(parent, Vector3(rc.x, 1.05, rc.y), Vector3(6, 0.5, 0.2), C_STONE, 0.004)
		rail.rotation.y = ang
	for s in [1.0, -1.0]:                           # 교각(가로 양끝)
		var pc: Vector2 = at + perp * 3.0 * s
		var pier := _box(parent, Vector3(pc.x, 0.4, pc.y), Vector3(1.2, 0.8, 3), C_STONE, 0.004)
		pier.rotation.y = ang

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

# 마을 경계 숲 띠: |x| 또는 |z| ∈ [34,40] 저밀도 나무(원통 줄기 + 구/원뿔 수관). 무충돌.
# 결정론적 시드로 배치(스샷 재현). 통행 방해 없음(무충돌·경계 바깥 띠).
func _forest_belt(parent: Node) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260724
	for edge in 4:  # 0=북(-z) 1=남(+z) 2=서(-x) 3=동(+x)
		for _i in 11:
			var along := rng.randf_range(-38.0, 38.0)
			var band := rng.randf_range(34.0, 39.0)
			var pos: Vector2
			match edge:
				0: pos = Vector2(along, -band)
				1: pos = Vector2(along, band)
				2: pos = Vector2(-band, along)
				_: pos = Vector2(band, along)
			_tree(parent, pos, rng.randf_range(0.85, 1.35), rng.randf() < 0.5)

func _tree(parent: Node, at: Vector2, s: float, coniferous: bool) -> void:
	var green := Color(0.42, 0.55, 0.32) if coniferous else C_GREEN
	_cyl(parent, Vector3(at.x, 0.9 * s, at.y), 0.22 * s, 1.8 * s, C_WOOD, 0.004)  # 줄기
	if coniferous:  # 침엽수 = 원뿔 수관
		var cone := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = 1.1 * s
		cm.height = 2.6 * s
		cone.mesh = cm
		cone.material_override = ToonChar.make_solid(green, 0.006)
		cone.position = Vector3(at.x, (1.8 + 1.3) * s, at.y)
		parent.add_child(cone)
	else:  # 활엽수 = 구 수관
		var ball := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.2 * s
		sm.height = 2.4 * s
		ball.mesh = sm
		ball.material_override = ToonChar.make_solid(green, 0.006)
		ball.position = Vector3(at.x, (1.8 + 0.9) * s, at.y)
		parent.add_child(ball)

extends Node3D
# 주민 시스템 (DESIGN 6.4). 데이터 구동 — npcs.json에서 주민 스폰·호감도·대화·선물.
# 비주얼 = 주인공 고양이 모델 색조 변형 재사용(_make_visual 어댑터 한 곳만 거침 → 종족별
# 실물 모델 교체 용이). 낮엔 npcs.json "schedule"대로 명명 앵커를 걸어서 오가고 도착하면 그
# 앵커 반경 배회, 밤·축제 중엔 정지(우선순위: 축제 > 밤 > 스케줄 > 배회).

const WorldScript := preload("res://world/world.gd")  # 강 폴리라인·다리 좌표 단일 출처
const Interior := preload("res://world/interior.gd")  # 실내 좌표·배우자 정위치 단일 출처
const HEART := 25       # 25포인트 = 하트 1칸
const MAX_AFF := 250    # 10칸
const FESTIVAL_MULT := 2  # 축제 중 대화 호감도 배율
const FEST_RING := 2.3    # 광장 링 배치 반경
const ToonChar := preload("res://common/toon_character.gd")

const CAT_GLB := "res://assets/cat_anim.glb"  # idle/walk 애니 포함 (player와 공용 모델)
const KID_IDS := ["npc.momo", "npc.pip"]       # 꼬마(동물 종족) — 작게
const NPC_SCALE := 2.1        # 플레이어와 동일
const KID_MULT := 0.8         # 꼬마 축소
const NPC_Y := 0.05           # 발 접지 오프셋 (플레이어 기준, 스크린샷 튜닝)
# 배회 파라미터
const WANDER_SPEED := 1.6     # 플레이어 5.0보다 느리게
const WANDER_R_MIN := 4.0
const WANDER_R_MAX := 6.0
const WAIT_MIN := 5.0
const WAIT_MAX := 15.0
const WALK_SCALE := 1.6       # cat walk 애니 재생속도
const ARRIVE := 0.15          # 목표 도착 판정 거리
const DAY_START := 8          # 활동 시작 시각
const DAY_END := 20           # 활동 종료 시각(이후 그 자리 정지 — 스케줄이 19시 home으로 넣어둠)
const FACE_TIME := 0.25       # 대화/선물 시 플레이어 쪽으로 도는 트윈 길이
const FACE_HOLD := 6.0        # 돈 뒤 배회 재개까지 그 방향 유지 시간(초)
# 회피할 장애물 keep-out(중심, 반경). world.gd _build_village + world.tscn의 solid/가시물과
# 동기화 필수 — P2 Tripo 교체 시 함께 갱신. 배회 목표점 거르기 + 보행 구간 우회 공용.
const BUILDING_KEEPOUT := [
	[Vector2(0, -18), 4.0],   # 회관
	[Vector2(-20, -14), 3.0], # 집1
	[Vector2(-24, 2), 3.0],   # 집2
	[Vector2(-14, 22), 3.0],  # 집3
	[Vector2(-7, -7), 2.5],   # 상점 박스
	[Vector2(3, 15), 3.5],    # 플레이어 집 (v1.4 이동 반영)
	[Vector2(24, 20), 3.0],   # 집4 (남동 강 건너)
	[Vector2(0, 0), 2.0],     # 분수 (광장 중앙, 충돌 r1)
	[Vector2(-5, -5), 1.6],   # 상점 카운터 (world.tscn Shop)
	[Vector2(9.5, 7), 1.1],   # 판매 상자 (world.tscn ShippingBin)
	[Vector2(10, 0), 2.9],    # 연못 (수면 r2.5)
	[Vector2(29, -18.5), 3.4],# 풍차 언덕 램프
	[Vector2(29, -24), 3.2],  # 풍차 대지
]
# 밭은 여기 없다: 마을 동쪽 길이 밭 모서리를 지나므로 통과 보행은 허용하고, 서 있는 목표점만
# _farm.in_region으로 거른다(작물 위에 안 서게).

# ── 하루 스케줄 (데이터 구동: npcs.json "schedule") ──────────────────
# 명명 앵커 좌표(home만 npcs.json). world.gd _build_village 실측 기준 — 건물·물·밭 밖.
const ANCHORS := {
	"plaza": Vector2(-4.5, 3.5),    # 광장 판석(r6) 남서 림, 분수 밖
	"shop": Vector2(-3.5, -3.5),    # 상점 앞마당 (건물 -7,-7 / 카운터 -5,-5 앞)
	"pond": Vector2(12, -3.5),      # 연못(10,0) 북동 물가
	"bridge": Vector2(13, 6.2),     # 동 다리(17,7) 서쪽 발치
	"windmill": Vector2(27, -12),   # 풍차 언덕 램프 발치 (강 건너 = 다리 경유)
	# 배우자 전용(F단계): 플레이어 집(피벗 3,15 / 북향 문 z=12.45) 앞. keepout r3.5 밖(거리 4.5),
	# 밭 REGION(x0..7, z2..5) 밖, 강 밖 — test_core 관통·도하 불변식이 지킴.
	"player_home": Vector2(3, 10.5),
}
const ANCHOR_R_MIN := 1.5   # 장소 앵커 배회 반경 (집보다 좁게 = 모여 있는 그림)
const ANCHOR_R_MAX := 3.0
const RIVER_AVOID := 2.9    # 강 중심선 이 거리 안엔 목표점 금지 (물폭3 + 양안 강둑)
const DECK_HALF := 3.4      # 다리 데크 반폭(가로 6) — 경유 웨이포인트 = 데크 양끝
const DECK_Y := 0.9         # 데크 상면 y (world.gd _arch_bridge: 중심 0.75 + 두께 0.3/2)
const DECK_KEEP := 4.0      # 목표점 금지 반경(데크 밑에 서지 않게)
const BLOCK_PAD := 0.3      # 구간이 장애물 원을 이만큼 침범하면 우회
const DETOUR_PAD := 1.5     # 우회점을 원 밖 이만큼 띄움
const DETOUR_MAX := 4       # 한 구간당 우회 삽입 상한

# ── 연애·결혼 (DESIGN 6.5) ──────────────────────────────────────────
# 청혼 조건 = ♥10(만렙) + 데이트 이벤트 2회 완주. 데이트는 하트가 열쇠를 주고(9칸·10칸),
# 대화(E)가 방아쇠를 당기고, 도착 판정은 기존 스케줄 앵커 인프라를 그대로 쓴다.
const PROPOSE_HEARTS := 10    # 청혼 가능 최소 하트 (= MAX_AFF/HEART 만렙)
const DATES_REQUIRED := 2     # 청혼 전 완주해야 하는 데이트 횟수
const DATE_HEARTS := [9, 10]  # 데이트 1·2가 열리는 최소 하트
const DATE_PLACES := ["pond", "windmill"]  # 데이트 1=연못, 2=풍차 언덕(강 건너 = 다리 경유)
const DATE_RADIUS := 3.0      # 플레이어가 앵커 이 거리 안에 오면 데이트 성사
const DATE_BONUS := HEART / 2 # 데이트 완주 호감 보너스
const DATE_LINE_SEC := 2.6    # 도착 대사 시퀀스 한 줄 노출(초)
const PLACE_NAMES := {"pond": "연못", "windmill": "풍차 언덕", "plaza": "광장", "shop": "상점 앞", "player_home": "집 앞"}
const ENGAGE_DAYS := 3        # 약혼 → 결혼식까지 일수
const WEDDING_HOUR := 9       # 결혼식 시각(그 날 09시 도달 시)
const WEDDING_WINDOW_H := 1   # 이 시간 안에 도달했을 때만 식 연출(지나쳤으면 즉시 완혼 폴백)
const WEDDING_HOLD_MIN := 30  # 광장 집합 유지(게임분)
const WEDDING_PLAZA := Vector2(0, -6)  # 광장 북측(분수 r2 밖) — 꽃축제와 같은 집합 지점
const SPOUSE_MORNING_H := 6   # 배우자 아침 = 기상시각부터 플레이어 집 앞
const SPOUSE_EVENING_H := 18  # 배우자 저녁 = 다시 플레이어 집 앞 (밤엔 그 자리 정지)
const HOME_HIDE_R := 7.0      # 밤 귀가 연출: 자기 집 이 반경 안이면 "집에 들어감"으로 숨김

# affection_points 0~250 저장, hearts는 파생 (Codex: F단계 청혼조건 재작업 방지)
var state := {}         # npc_id → {affection_points, talked_today, gifted_today, dates_seen}
var spouse := ""        # 배우자 npc_id ("" = 미혼)
var engaged := {}       # {} 또는 {id, wedding_abs_day}
var _wedding_end := -1  # 결혼식 집합 종료 절대분(abs_day*1440+game_min). -1 = 진행중 아님
var _date := {}         # 진행 중 데이트 {} 또는 {id, place, idx} — 저장 안 함(당일 한정 연출)
var npc_nodes := {}     # npc_id → 스폰 root Node3D (축제 이동용, FestivalSystem이 호출)
var _wander := {}       # npc_id → {target:Vector3, wait:float, anim:AnimationPlayer, cur:String}
var _festival_active := false
var _festival_id := ""     # 진행 중 축제 id (대사 풀 선택용). 결혼식은 ""=축제 공용 대사
var _shot_frozen := false  # 스크린샷 배치 시 배회 정지
var _spouse_indoor := false  # 배우자가 지금 실내(플레이어 집 안)에 배치돼 있는가
var _farm: Node

func _ready() -> void:
	add_to_group("npc_system")
	_farm = get_tree().get_first_node_in_group("farm")
	for id in GameData.npcs:
		state[id] = {"affection_points": 0, "talked_today": false, "gifted_today": false, "dates_seen": 0}
		_spawn(id)
	snap_to_schedule()  # 시작 시각의 장소에서 출발 (새 게임 06시면 전원 집)
	if not GameClock.day_changed.is_connected(_on_day_changed):
		GameClock.day_changed.connect(_on_day_changed)

func _spawn(id: String) -> void:
	var n: Dictionary = GameData.npcs[id]
	var root := Node3D.new()
	var home: Array = n["home"]
	root.position = Vector3(home[0], 0, home[1])
	var vis := _make_visual(id, n)
	if vis != null:
		root.add_child(vis)
	# 상호작용용 Area3D (대화·선물 판정)
	var area := Area3D.new()
	area.add_to_group("npc")
	area.set_meta("npc_id", id)
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 1.4
	cs.shape = sh
	area.add_child(cs)
	area.position = Vector3(0, 1.0, 0)
	root.add_child(area)
	add_child(root)
	_attach_springs(vis)   # 트리에 붙은 뒤에 — 스켈레톤이 준비돼야 본 이름 조회가 된다
	npc_nodes[id] = root
	_wander[id] = {
		"target": root.position, "wait": randf_range(0.0, WAIT_MAX),
		"anim": ToonChar.find_anim(vis) if vis != null else null, "cur": "",
		"place": "home", "path": [],   # path = 남은 경유 웨이포인트(Vector2)
		"vis": vis, "area": area, "hidden": false,  # 밤 귀가 페이드용
	}

# ── 비주얼 어댑터 (종족별 실물 모델 교체는 여기만 수정) ──────────────
# npcs.json에 "model" 필드 있으면 그 GLB를 실물 로드(색조 tint 없이 원본 텍스처).
# 성인 키 = cat×NPC_SCALE 에 맞춰 AABB 높이 정규화(꼬마면 ×KID_MULT). 없으면 기존 고양이 색조.
const MODEL_TARGET_H := 2.1    # 실물 GLB NPC 목표 월드 높이 (성인 기준)

func _make_visual(id: String, ndef: Dictionary) -> Node3D:
	var model_path := String(ndef.get("model", ""))
	if model_path != "":
		var m: Node3D = ToonChar.load_glb(model_path, ToonChar.OUTLINE_WORLD)  # tint=흰=원본색
		if m != null:
			var box := ToonChar.aabb_of(m)
			var ms := 1.0
			if box.size.y > 0.001:
				ms = MODEL_TARGET_H / box.size.y * (KID_MULT if id in KID_IDS else 1.0)
			m.scale = Vector3(ms, ms, ms)
			ToonChar.set_outline_width(m, ToonChar.OUTLINE_WORLD / ms)  # 오브젝트→월드 굵기 보정
			m.position.y = NPC_Y - box.position.y * ms  # 모델 발바닥(AABB 최저점)을 접지
			m.rotation.y = PI  # 앞=+Z → look_at(-Z) 보정 (cat과 동일)
			return m
		# 로드 실패 시 아래 고양이 색조 폴백으로 진행
	var c: Array = ndef["color"]
	var tint := Color(c[0], c[1], c[2])
	var cat: Node3D = ToonChar.load_glb(CAT_GLB, ToonChar.OUTLINE_WORLD, tint)
	if cat == null:
		return _fallback_capsule(tint)  # 폴백: 색상 캡슐
	var s := NPC_SCALE * (KID_MULT if id in KID_IDS else 1.0)
	cat.scale = Vector3(s, s, s)
	ToonChar.set_outline_width(cat, ToonChar.OUTLINE_WORLD / s)  # 오브젝트→월드 굵기 보정
	cat.position.y = NPC_Y
	cat.rotation.y = PI  # 앞=+Z, look_at은 -Z 기준 → 180° 보정 (player와 동일)
	var anim := ToonChar.find_anim(cat)
	if anim != null:
		for a in ["idle", "walk"]:
			if anim.has_animation(a):
				anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
		if anim.has_animation("idle"):
			anim.play("idle")
	return cat

# 옷 물리(베일·치마·펜던트) — 모델에 물리본이 있는 NPC만. 없으면 아무것도 안 한다.
# 셋업은 lookdev/nun_physics.gd 의 검증된 static 을 그대로 재사용.
const NunPhysics := preload("res://lookdev/nun_physics.gd")

func _attach_springs(vis: Node3D) -> void:
	if vis == null:
		return
	var sk := NunPhysics._find(vis, Skeleton3D) as Skeleton3D
	if sk == null or sk.has_node("NunSprings"):
		return
	for b in ["veil_BC_01", "skirt_F_01", "pendant_01"]:
		if sk.find_bone(b) < 0:
			return
	NunPhysics.setup_springs(sk)

func _fallback_capsule(tint: Color) -> Node3D:
	var mesh := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.4
	cap.height = 1.6
	mesh.mesh = cap
	mesh.material_override = ToonChar.make_solid(tint, 0.008)
	mesh.position = Vector3(0, 1.0, 0)
	return mesh

# ── 배회 (순수 보간, 경로탐색·충돌 없음 — DESIGN 11) ────────────────
func _process(delta: float) -> void:
	_check_wedding()  # 모든 early-return 앞 — 메뉴/밤/축제 중에도 예약된 결혼식은 진행돼야 한다
	_check_date()     # 데이트 도착 판정·밤 중단도 배회 정지와 무관하게 돌아야 한다
	_update_spouse_indoor()  # 실내 배치·복귀는 밤/일시정지에도 판정 (배우자 저녁 18시~는 밤과 겹친다)
	_update_home_hide()      # 밤 귀가 연출도 마찬가지 (PAUSED인 스크린샷 하네스에서도 보여야 한다)
	if _shot_frozen or _festival_active or GameClock.state == GameClock.State.PAUSED or not _is_daytime():
		for id in npc_nodes:  # 축제=광장 배치 유지, 그 외=idle
			_set_walk(id, false)
		return
	for id in npc_nodes:
		if _spouse_indoor and String(id) == spouse:
			continue  # 실내 배치 중 = 실외 배회·스케줄이 이 노드를 건드리지 않는다
		_wander_step(id, delta)

# ── 배우자 실내 동거 (G단계) ────────────────────────────────────
# 기혼 + 배우자 스케줄이 player_home + 플레이어가 실내에 있음 → 배우자를 실내 정위치로 배치.
# 경로탐색으로 들여보내지 않는다 — 실내는 격리 좌표라 route()의 강·건물 판정 밖이다(배치로 충분).
func _update_spouse_indoor() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var place := "" if spouse == "" else place_at(_schedule(spouse), GameClock.hour())
	var want := spouse_indoors(spouse, place, player != null and Interior.inside(player.global_position))
	if want == _spouse_indoor:
		if want:  # 실내 유지: 정위치 고정(다른 로직이 밀어냈어도 되돌림)
			npc_nodes[spouse].position = Interior.SPOUSE_SPOT
		return
	_spouse_indoor = want
	if want:
		var st: Dictionary = _wander[spouse]
		st["path"] = []
		st["wait"] = 0.0
		npc_nodes[spouse].position = Interior.SPOUSE_SPOT
		_set_walk(spouse, false)
		_set_hidden(spouse, false)  # 실내에선 항상 보인다(밤 귀가 숨김과 배타)
	elif spouse != "" and npc_nodes.has(spouse):
		snap_to_schedule()  # 실내 → 실외: 그 시각 앵커로 복귀

# 순수 판정 (test_core 단위검증)
static func spouse_indoors(spouse_id: String, place: String, player_inside: bool) -> bool:
	return spouse_id != "" and player_inside and place == "player_home"

# ── 밤 귀가 연출 ────────────────────────────────────────────────
# 활동 종료(DAY_END) 후 자기 집 앞에 서 있는 주민을 숨겨 "집에 들어감"으로 읽히게 한다.
# 축제(결혼식 포함) 중엔 강제 가시, 실내 배치된 배우자도 제외.
func _update_home_hide() -> void:
	for id in npc_nodes:
		var home: Array = GameData.npcs[id]["home"]
		var p: Vector3 = npc_nodes[id].position
		var at_home := Vector2(p.x, p.z).distance_to(Vector2(home[0], home[1])) < HOME_HIDE_R
		var indoor: bool = _spouse_indoor and String(id) == spouse
		_set_hidden(id, night_hidden(GameClock.hour(), at_home, _festival_active, indoor))

# 순수 판정 (test_core 단위검증)
static func night_hidden(h: int, at_home: bool, festival: bool, indoor_spouse: bool) -> bool:
	return at_home and not festival and not indoor_spouse and (h < DAY_START or h >= DAY_END)

# 모델 숨김 + 상호작용 비활성.
# 상호작용 차단은 "npc" 그룹 탈퇴로 한다 — Area3D.monitorable을 껐다 켜면 두 Area가 그대로
# 멈춰 있는 한 브로드페이즈 쌍이 다시 안 맺혀 영구히 감지 불능이 된다(실측). 그룹은
# player._area_kind()가 매 판정마다 읽으므로 즉시·양방향으로 확실하다.
# ponytail: toon.gdshader에 알파가 없어 진짜 알파 페이드는 불가 — 스케일 축소로 대신한다.
func _set_hidden(id: String, hide: bool) -> void:
	var st: Dictionary = _wander[id]
	if bool(st["hidden"]) == hide:
		return
	st["hidden"] = hide
	var area: Area3D = st["area"]
	if hide:
		area.remove_from_group("npc")
	else:
		area.add_to_group("npc")
	var vis: Node3D = st["vis"]
	if vis == null:
		return
	if not st.has("base_scale"):
		st["base_scale"] = vis.scale
	var base: Vector3 = st["base_scale"]
	var old = st.get("hide_tween")
	if old != null and (old as Tween).is_valid():
		(old as Tween).kill()  # 반대 전환이 겹치면 뒤늦은 콜백이 다시 숨겨버린다
	var tw := create_tween()
	st["hide_tween"] = tw
	if hide:
		tw.tween_property(vis, "scale", base * 0.01, 0.4)
		tw.tween_callback(func() -> void: vis.visible = false)
	else:
		vis.visible = true
		tw.tween_property(vis, "scale", base, 0.4)

func _is_daytime() -> bool:
	var h := GameClock.hour()
	return h >= DAY_START and h < DAY_END

func _wander_step(id: String, delta: float) -> void:
	var st: Dictionary = _wander[id]
	var node: Node3D = npc_nodes[id]
	_follow_schedule(id)
	if st["wait"] > 0.0:
		st["wait"] = float(st["wait"]) - delta
		_set_walk(id, false)
		return
	var target: Vector3 = st["target"]
	var flat := Vector3(target.x - node.position.x, 0, target.z - node.position.z)
	if flat.length() < ARRIVE:  # 도착
		var path: Array = st["path"]
		if not path.is_empty():   # 경유점 → 쉬지 않고 다음 구간
			st["target"] = _v3(path.pop_front())
			return
		st["wait"] = randf_range(WAIT_MIN, WAIT_MAX)
		st["target"] = _pick_target(id)
		_set_walk(id, false)
		return
	var step := minf(WANDER_SPEED * delta, flat.length())  # 프레임 드랍 시 목표 초과 방지
	node.position += flat.normalized() * step
	node.position.y = _deck_y(Vector2(node.position.x, node.position.z))  # 다리 위면 데크 높이
	node.look_at(node.global_position + flat, Vector3.UP)  # yaw만 (flat.y=0)
	_set_walk(id, true)

# 스케줄 장소가 바뀌었으면 그 앵커까지의 경로를 깐다(순간이동 없음 — 걸어서 간다).
func _follow_schedule(id: String) -> void:
	var st: Dictionary = _wander[id]
	var place := place_at(_schedule(id), GameClock.hour())
	if place == st["place"]:
		return
	st["place"] = place
	var node: Node3D = npc_nodes[id]
	var path := route(Vector2(node.position.x, node.position.z), _anchor_pos(id, place))
	st["target"] = _v3(path.pop_front())
	st["path"] = path
	st["wait"] = 0.0

# 현재 장소 앵커 반경의 랜덤점. 밭·강·다리데크·keepout 회피(목표점만 거름 — DESIGN 11).
func _pick_target(id: String) -> Vector3:
	var place := String(_wander[id]["place"])
	var c := _anchor_pos(id, place)
	var at_home := place == "home"
	for _i in 8:
		var ang := randf() * TAU
		var r := randf_range(WANDER_R_MIN if at_home else ANCHOR_R_MIN, WANDER_R_MAX if at_home else ANCHOR_R_MAX)
		var p := c + Vector2(cos(ang), sin(ang)) * r
		if _farm != null and _farm.in_region(Vector2i(floori(p.x), floori(p.y))):
			continue
		if _river_dist(p) < RIVER_AVOID or _near_bridge(p, DECK_KEEP) or _inside_block(p):
			continue
		return Vector3(p.x, 0, p.y)
	return Vector3(c.x, 0, c.y)

# ── 스케줄 파생 + 경로 (순수 함수 — test_core 단위검증) ─────────────
# 시각(0~23) → 그 시각의 장소 id. 스케줄은 시각 오름차순, 첫 항목 이전(이른 아침)은 home.
static func place_at(sched: Array, h: int) -> String:
	var place := "home"
	for e in sched:
		if int(e["h"]) <= h:
			place = String(e["place"])
	return place

# from→to 웨이포인트(도착점 포함). 강을 건너면 최단 다리의 데크 양끝을 경유로 삽입.
static func route(from: Vector2, to: Vector2) -> Array:
	if not needs_bridge(from, to):
		return _detour(from, to)
	var gate: Array = []
	var best := INF
	for br in WorldScript.BRIDGES:
		var g := _gates(br, from)
		var l: float = from.distance_to(g[0]) + g[0].distance_to(g[1]) + g[1].distance_to(to)
		if l < best:
			best = l
			gate = g
	return _detour(from, gate[0]) + [gate[1]] + _detour(gate[1], to)

# 구간이 다리 밖에서 강을 가로지르는가 (강은 다리 3곳으로만 통행 — world.gd 충돌벽 gap과 동일 규칙)
static func needs_bridge(a: Vector2, b: Vector2) -> bool:
	for i in WorldScript.RIVER_PTS.size() - 1:
		var x = Geometry2D.segment_intersects_segment(a, b, WorldScript.RIVER_PTS[i], WorldScript.RIVER_PTS[i + 1])
		if x != null and not _near_bridge(x, 1.2):
			return true
	return false

# 다리 데크 양끝(강 가로지르는 방향). from에서 가까운 쪽이 먼저 = 진입단.
static func _gates(br: Vector2, from: Vector2) -> Array:
	var flow := Vector2.RIGHT
	var best := INF
	for i in WorldScript.RIVER_PTS.size() - 1:
		var a: Vector2 = WorldScript.RIVER_PTS[i]
		var b: Vector2 = WorldScript.RIVER_PTS[i + 1]
		var d := _near_on(a, b, br).distance_to(br)
		if d < best:
			best = d
			flow = (b - a).normalized()
	var perp := Vector2(flow.y, -flow.x) * DECK_HALF
	return [br - perp, br + perp] if from.distance_to(br - perp) <= from.distance_to(br + perp) else [br + perp, br - perp]

# 직선 구간이 장애물 원을 지나면 원 밖으로 밀어낸 우회점을 끼운다(A* 아님 — 허브형 마을이라
# 한두 개면 충분). 후보 4개 중 다른 장애물·강에 안 걸리고 짧은 쪽.
# ponytail: 실패해도 직선 폴백 — 실제 스케줄 전 구간이 뚫리는지는 test_core가 지킨다.
static func _detour(from: Vector2, to: Vector2) -> Array:
	var out: Array = []
	var cur := from
	for _i in DETOUR_MAX:
		var ko := _block_hit(cur, to)
		if ko.is_empty():
			break
		var c: Vector2 = ko[0]
		var rr := float(ko[1]) + DETOUR_PAD
		var u := (to - cur).normalized()
		if u == Vector2.ZERO:
			break
		var perp := Vector2(-u.y, u.x)
		var n := _near_on(cur, to, c) - c
		n = n.normalized() if n.length() > 0.2 else perp
		var best := to
		var best_s := INF
		for w: Vector2 in [c + n * rr, c - n * rr, c + perp * rr, c - perp * rr]:
			# 가중합: 원 안(치명) > 막힌 구간 > 길이
			var s := cur.distance_to(w) + w.distance_to(to)
			s += 100000.0 * float(_inside_block(w)) + 1000.0 * float(_bad(cur, w) + _bad(w, to))
			if s < best_s:
				best_s = s
				best = w
		out.append(best)
		cur = best
	out.append(to)
	return out

static func _bad(a: Vector2, b: Vector2) -> int:
	return (1 if not _block_hit(a, b).is_empty() else 0) + (2 if needs_bridge(a, b) else 0)

# 구간이 처음 침범하는 keepout 원 [중심, 반경] (없으면 [])
static func _block_hit(a: Vector2, b: Vector2) -> Array:
	var hit: Array = []
	var best := INF
	for ko in BUILDING_KEEPOUT:
		var q := _near_on(a, b, ko[0])
		if q.distance_to(ko[0]) < float(ko[1]) + BLOCK_PAD:
			var t := q.distance_to(a)
			if t < best:
				best = t
				hit = ko
	return hit

static func _inside_block(p: Vector2) -> bool:
	for ko in BUILDING_KEEPOUT:
		if p.distance_to(ko[0]) < float(ko[1]) + BLOCK_PAD:
			return true
	return false

static func _near_bridge(p: Vector2, r: float) -> bool:
	for br in WorldScript.BRIDGES:
		if p.distance_to(br) < r:
			return true
	return false

static func _river_dist(p: Vector2) -> float:
	var d := INF
	for i in WorldScript.RIVER_PTS.size() - 1:
		d = minf(d, _near_on(WorldScript.RIVER_PTS[i], WorldScript.RIVER_PTS[i + 1], p).distance_to(p))
	return d

# 선분 ab 위에서 p에 가장 가까운 점
static func _near_on(a: Vector2, b: Vector2, p: Vector2) -> Vector2:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 0.0001:
		return a
	return a + ab * clampf((p - a).dot(ab) / l2, 0.0, 1.0)

# 다리 위를 지날 때만 데크 높이로 들어올림 — 발이 물에 잠기거나 데크를 관통하는 그림 방지.
# (배회 목표는 DECK_KEEP 밖이라 강을 건너는 중에만 0이 아니다)
static func _deck_y(p: Vector2) -> float:
	var d := INF
	for br in WorldScript.BRIDGES:
		d = minf(d, p.distance_to(br))
	return DECK_Y * smoothstep(DECK_HALF, DECK_HALF - 1.9, d)

static func _v3(p: Vector2) -> Vector3:
	return Vector3(p.x, 0, p.y)

# 우선순위: 데이트 > 배우자 > npcs.json (축제·밤은 _process 단계에서 이 위에 얹힌다)
func _schedule(id: String) -> Array:
	if not _date.is_empty() and id == String(_date["id"]):
		return [{"h": 0, "place": String(_date["place"])}]  # 하루 종일 그 앵커 = 데이트 장소로 직행
	var base: Array = GameData.npcs[id].get("schedule", [])
	return spouse_schedule(base) if id == spouse else base

func _anchor_pos(id: String, place: String) -> Vector2:
	if ANCHORS.has(place):
		return ANCHORS[place]
	var home: Array = GameData.npcs[id]["home"]  # "home" + 알 수 없는 place 폴백
	return Vector2(home[0], home[1])

# 현재 시각의 스케줄 장소로 즉시 배치 (로드·취침 점프·축제 종료 — 단체 행군 방지).
# 이미 그 장소 반경 안이면 위치는 그대로 두고 상태만 정렬(자정 day_changed 제자리 순간이동 방지).
func snap_to_schedule() -> void:
	for id in npc_nodes:
		if _spouse_indoor and String(id) == spouse:
			continue  # 실내 배치 중인 배우자는 실외 앵커로 끌어내지 않는다
		var st: Dictionary = _wander[id]
		var place := place_at(_schedule(id), GameClock.hour())
		var a := _anchor_pos(id, place)
		var node: Node3D = npc_nodes[id]
		st["place"] = place
		st["path"] = []
		node.position.y = 0.0
		if Vector2(node.position.x, node.position.z).distance_to(a) > WANDER_R_MAX:
			node.position = _v3(a) if place == "home" else _pick_target(id)
		st["target"] = _pick_target(id)
		st["wait"] = randf_range(0.0, WAIT_MAX)

# 말 건 플레이어 쪽으로 비주얼 yaw 회전 (전 주민 공통, talk·give가 호출).
# 루트를 wander와 같은 look_at 규약으로 돌려(비주얼 rotation.y=PI 보정 재사용) 이중보정 없음.
# 짧은 트윈 후 FACE_HOLD 동안 wait 상태로 두어 배회 look_at이 다음 프레임에 덮지 않게 함.
func _face_player(id: String) -> void:
	var node: Node3D = npc_nodes.get(id)
	if node == null:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var flat := player.global_position - node.global_position
	flat.y = 0.0
	if flat.length() < 0.01:
		return
	var yaw := node.global_transform.looking_at(node.global_position + flat, Vector3.UP).basis.get_euler().y
	var cur := node.rotation.y
	yaw = cur + wrapf(yaw - cur, -PI, PI)  # 최단 회전
	var st: Dictionary = _wander[id]
	var old = st.get("face_tween")
	if old != null and (old as Tween).is_valid():
		(old as Tween).kill()
	var tw := create_tween()
	tw.tween_property(node, "rotation:y", yaw, FACE_TIME)
	st["face_tween"] = tw
	# wait만 늘린다 — 이동 목표·경유 큐는 그대로 두고 그 자리에 멈춰 서서 yaw 유지, 뒤에 이어감
	st["wait"] = maxf(float(st["wait"]), FACE_HOLD)
	_set_walk(id, false)

# walk/idle 전환 (같은 클립 재요청 무시)
func _set_walk(id: String, walking: bool) -> void:
	var st: Dictionary = _wander[id]
	var anim: AnimationPlayer = st["anim"]
	var want := "walk" if walking else "idle"
	if anim == null or st["cur"] == want:
		return
	st["cur"] = want
	if anim.has_animation(want):
		anim.play(want, 0.2, WALK_SCALE if walking else 1.0)

# 스크린샷용: 전 주민 카메라 앞 격자 배치 + 배회 정지 (world.gd "npcs" cmdline)
func pose_for_shot() -> void:
	_shot_frozen = true
	var ids := npc_nodes.keys()
	for i in ids.size():
		var node: Node3D = npc_nodes[ids[i]]
		node.position = Vector3(-4.5 + (i % 4) * 3.0, 0.0, 1.0 - (i / 4) * 3.0)
		node.rotation.y = PI  # 카메라(+Z쪽) 바라보게
		_set_walk(ids[i], false)

func hearts(id: String) -> int:
	return int(state[id]["affection_points"]) / HEART

# 대화: 하루 1회 +5 (축제 중 ×2)
func talk(id: String) -> Dictionary:
	_face_player(id)  # 대화 성사 여부와 무관하게 플레이어를 향해 돎
	var s: Dictionary = state[id]
	var nm: String = GameData.npcs[id]["name"]
	if s["talked_today"]:
		return {"ok": false, "msg": nm + ": (오늘 대화함)"}
	s["talked_today"] = true
	var gain := 5
	var extra := ""
	if _festival_active:
		gain *= FESTIVAL_MULT
		extra = "  (축제 ×%d)" % FESTIVAL_MULT
	_add(id, gain)
	# 데이트 이벤트 방아쇠 (하트 조건 충족 + 순서 = 이번 대화가 데이트 제안이 된다)
	var di := date_index(id)
	if di >= 0:
		_start_date(id, di)
		return {"ok": true, "msg": "%s: %s  (%s에서 만나요!)  ♥ %d/10" % [
			nm, _pool_line(id, "date_invite"), PLACE_NAMES[DATE_PLACES[di]], hearts(id)]}
	# 하트를 토스트 꼬리에 노출 = 청혼 진행 단계(♥9 데이트1 → ♥10 데이트2 → 청혼)를 스스로 발견
	return {"ok": true, "msg": "%s: %s  ♥ %d/10%s" % [nm, _dialogue_line(id), hearts(id), extra]}

# 아키타입별 대사 랜덤 1줄 (배우자면 부부 아침 인사 > 축제별 > 축제 공용 > 평상).
# 축제별 풀 key = 축제 id 그대로 = calendar.json이 단일 출처(중간 매핑표 없음). 결혼식은
# _festival_id가 ""라 공용 "festival" 풀로 떨어진다(기존 동작 그대로).
func _dialogue_line(id: String) -> String:
	if id == spouse:
		var married := _pool_line(id, "married")  # 대화는 하루 1회 성사 = 하루 첫 대화
		if married != "":
			return married
	var pool: Dictionary = GameData.dialogues.get(String(GameData.npcs[id]["archetype"]), {})
	var lines: Array = pool.get("normal", [])
	if _festival_active:
		var per_fest: Array = pool.get(_festival_id, [])
		var fest: Array = pool.get("festival", [])
		if not per_fest.is_empty():
			lines = per_fest
		elif not fest.is_empty():
			lines = fest
	return "" if lines.is_empty() else lines[randi() % lines.size()]

# 아키타입 대사 풀 key에서 랜덤 1줄 (없으면 "")
func _pool_line(id: String, key: String) -> String:
	var lines: Array = GameData.dialogues.get(String(GameData.npcs[id]["archetype"]), {}).get(key, [])
	return "" if lines.is_empty() else lines[randi() % lines.size()]

# ── 축제 (FestivalSystem이 상태만 설정, 호감도·이동은 여기 소유) ──
func enter_festival(plaza: Vector2, fid := "") -> void:
	_festival_active = true
	_festival_id = fid
	_spouse_indoor = false  # 축제 > 실내 동거 (배우자도 광장으로)
	var ids := npc_nodes.keys()
	var n := ids.size()
	for i in n:
		var ang := TAU * i / float(maxi(n, 1))
		var pos := plaza + Vector2(cos(ang), sin(ang)) * FEST_RING
		npc_nodes[ids[i]].position = Vector3(pos.x, 0, pos.y)
		_set_hidden(ids[i], false)  # 밤 축제(결혼식 포함)에도 전원 보이게

func exit_festival() -> void:
	_festival_active = false
	_festival_id = ""
	snap_to_schedule()  # 그 시각 스케줄 장소로 복귀 (밤이면 집 — 데이터가 단일 출처)

# ── 연애·결혼 (DESIGN 6.5) ──────────────────────────────────────
func is_candidate(id: String) -> bool:
	return bool(GameData.npcs.get(id, {}).get("candidate", false))

# ── 데이트 이벤트 (청혼 전 필수 2회) ────────────────────────────
# 트리거=대화(하루 1회 성사라 자동으로 하루 1회). NPC는 지정 앵커로 걸어가고(스케줄 오버라이드
# = 축제 > 데이트 > 밤 > 스케줄), 플레이어가 그 앵커 근처에 오면 성사. 안 오면 밤에 중단(미소진).
# 다음에 열리는 데이트 번호 (없으면 -1)
func date_index(id: String) -> int:
	if not is_candidate(id) or spouse != "" or not engaged.is_empty() or not _date.is_empty():
		return -1
	if not GameData.festival_on(GameData.season_id(GameClock.season()), GameClock.day_of_season()).is_empty():
		return -1  # 축제일엔 시작 금지 (주민이 광장에 묶여 있다)
	var seen := int(state[id]["dates_seen"])
	if seen >= DATE_HEARTS.size():
		return -1
	return seen if hearts(id) >= int(DATE_HEARTS[seen]) else -1  # 순서 보장: seen번째만 열림

func _start_date(id: String, idx: int) -> void:
	_date = {"id": id, "place": String(DATE_PLACES[idx]), "idx": idx}
	var st: Dictionary = _wander[id]
	st["wait"] = 0.0  # 대사 후 곧바로 출발 (_face_player가 늘려둔 대기 해제)

# 도착·중단 판정 (idempotent, 매 프레임)
func _check_date() -> void:
	if _date.is_empty():
		return
	var id := String(_date["id"])
	if not _is_daytime():  # 밤 = 중단, 데이트는 소진되지 않음(다음에 다시 발생)
		_date = {}
		_toast("%s와의 약속은 다음 기회에..." % GameData.npcs[id]["name"])
		return
	if _festival_active:
		return  # 축제 우선 — 주민이 광장에 있는 동안은 판정 정지
	var a: Vector2 = ANCHORS[String(_date["place"])]
	var node: Node3D = npc_nodes.get(id)
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if node == null or player == null:
		return
	if Vector2(node.position.x, node.position.z).distance_to(a) > ANCHOR_R_MAX + 0.5:
		return  # NPC가 아직 가는 중
	if Vector2(player.global_position.x, player.global_position.z).distance_to(a) > DATE_RADIUS:
		return  # 도착해서 기다리는 중
	_finish_date(id, int(_date["idx"]))

func _finish_date(id: String, idx: int) -> void:
	_date = {}  # 오버라이드 해제 → _follow_schedule이 원래 장소로 다시 걸어감(순간이동 없음)
	state[id]["dates_seen"] = maxi(int(state[id]["dates_seen"]), idx + 1)
	_add(id, DATE_BONUS)
	_face_player(id)
	SaveManager.request_save("date")
	_play_date_lines(id, "date%d" % (idx + 1))

# 도착 특별 대사 시퀀스 (토스트 한 줄씩). 상태 변경은 위에서 이미 끝났다 = 여긴 연출만.
func _play_date_lines(id: String, key: String) -> void:
	var nm: String = GameData.npcs[id]["name"]
	for line in GameData.dialogues.get(String(GameData.npcs[id]["archetype"]), {}).get(key, []):
		_toast("%s: %s" % [nm, line])
		Sfx.play("talk")
		await get_tree().create_timer(DATE_LINE_SEC).timeout
	_toast("%s와의 시간이 특별했어요.  ♥ %d/10" % [nm, hearts(id)])

# 청혼(반지 소지 중 G). 수락(ok=true)일 때만 호출측이 반지를 소모한다 — 거절은 무소모.
func propose(id: String) -> Dictionary:
	_face_player(id)  # 대화·선물과 같은 상호작용
	var nm: String = GameData.npcs[id]["name"]
	if spouse != "" or not engaged.is_empty():
		return {"ok": false, "msg": "%s: 당신에겐 이미 약속한 사람이 있잖아요." % nm}
	if not is_candidate(id):
		return {"ok": false, "msg": "%s: 마음은 고맙지만... 그런 사이는 아니에요." % nm}
	# 거절 대사에 다음 단계 힌트를 붙인다 — 하트 부족과 데이트 미완주를 구분
	if hearts(id) < PROPOSE_HEARTS:
		return {"ok": false, "msg": "%s: %s  ♥ %d/%d" % [nm, _pool_line(id, "propose_reject"), hearts(id), PROPOSE_HEARTS]}
	if int(state[id]["dates_seen"]) < DATES_REQUIRED:
		return {"ok": false, "msg": "%s: %s  (함께한 데이트 %d/%d)" % [
			nm, _pool_line(id, "propose_reject"), int(state[id]["dates_seen"]), DATES_REQUIRED]}
	engaged = {"id": id, "wedding_abs_day": wedding_day_for(GameClock.abs_day + ENGAGE_DAYS)}
	SaveManager.request_save("proposal")  # 데이트·결혼식과 같은 즉시 저장 정책
	var days := int(engaged["wedding_abs_day"]) - GameClock.abs_day
	return {"ok": true, "msg": "%s: %s  (%d일 뒤 아침 광장에서 결혼식!)" % [nm, _pool_line(id, "propose_accept"), days]}

# 결혼식 날짜 — 축제날과 겹치면 하루 미룸(광장이 두 행사에 동시에 쓰이지 않게)
func wedding_day_for(d: int) -> int:
	for _i in 4:
		if GameData.festival_on(GameData.season_id(GameClock.season_at(d)), GameClock.day_of_season_at(d)).is_empty():
			return d
		d += 1
	return d

# 절대분 = abs_day*1440 + game_min. 결혼식 집합 종료를 이걸로 재는 이유: game_min만 쓰면
# 식 중 자정을 넘길 때(취침·로드) 비교가 뒤집혀 광장 집합이 풀리지 않는다 (Codex 지적).
func _abs_min() -> int:
	return GameClock.abs_day * GameClock.MINUTES_PER_DAY + GameClock.game_min

# idempotent 체크(매 프레임): 집합 종료 → 예약된 결혼식 도달 판정.
func _check_wedding() -> void:
	if _wedding_end >= 0 and _abs_min() >= _wedding_end:
		_wedding_end = -1
		exit_festival()
	if engaged.is_empty():
		return
	var wd := int(engaged["wedding_abs_day"])
	if GameClock.abs_day > wd or (GameClock.abs_day == wd and GameClock.hour() >= WEDDING_HOUR):
		_wed()

func _wed() -> void:
	var id := String(engaged["id"])
	var wd := int(engaged["wedding_abs_day"])
	spouse = id
	engaged = {}
	var nm: String = GameData.npcs[id]["name"]
	if GameClock.abs_day == wd and GameClock.hour() < WEDDING_HOUR + WEDDING_WINDOW_H:
		enter_festival(WEDDING_PLAZA)  # 주민 광장 집합 (축제 API 재활용)
		_stand_with_player(id)
		_wedding_end = _abs_min() + WEDDING_HOLD_MIN
		_toast("%s와 결혼했습니다!  “%s”" % [nm, _pool_line(id, "wedding")])
		Sfx.play("talk")
	else:
		# 취침·로드로 식 시간창을 지나침 → 연출 없이 즉시 완혼(상태 꼬임 방지 폴백)
		_toast("%s와의 결혼식을 마쳤습니다." % nm)
	SaveManager.request_save("wedding")

# 식 연출: 배우자를 플레이어 앞에 세워 마주보게 (광장 링 배치 뒤에 덮어씀)
func _stand_with_player(id: String) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var node: Node3D = npc_nodes.get(id)
	if player == null or node == null:
		return
	var fwd := -player.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.01:
		fwd = Vector3(0, 0, 1)
	node.position = player.global_position + fwd.normalized() * 1.6
	node.position.y = 0.0
	_face_player(id)

func _toast(msg: String) -> void:
	get_tree().call_group("hud", "toast", msg)

# 결혼 후 배우자 스케줄 오버라이드 (순수 함수). npcs.json 원본·home 좌표 불변 — 런타임 파생.
# 아침(기상 06시~)·저녁(18시~) = 플레이어 집 앞, 낮 = 원래 자기 스케줄 유지
# ("결혼하면 끝이 아니라 생활이 이어지는 느낌" — DESIGN 6.5).
static func spouse_schedule(base: Array) -> Array:
	var out: Array = [{"h": SPOUSE_MORNING_H, "place": "player_home"}]
	for e in base:
		var h := int(e["h"])
		if h > SPOUSE_MORNING_H and h < SPOUSE_EVENING_H and String(e["place"]) != "home":
			out.append({"h": h, "place": String(e["place"])})  # 새 딕셔너리 = 원본 불변
	out.append({"h": SPOUSE_EVENING_H, "place": "player_home"})
	return out

# 선물: 하루 1회, 취향별 ±, 생일 ×8, 0~250 clamp
func give(id: String, item_id: String) -> Dictionary:
	_face_player(id)  # 선물도 같은 상호작용 — 플레이어를 향해 돎
	var s: Dictionary = state[id]
	var nm: String = GameData.npcs[id]["name"]
	if s["gifted_today"]:
		return {"ok": false, "msg": nm + " (오늘 선물 받음)"}
	var pref := _preference(id, item_id)
	var delta: int = {"loved": 40, "liked": 20, "neutral": 8, "disliked": -20}[pref]
	if _is_birthday(id):
		delta *= 8  # 생일 보너스
	s["gifted_today"] = true
	_add(id, delta)
	var react: String = {"loved": "기뻐함!", "liked": "좋아함", "neutral": "받음", "disliked": "싫어함.."}[pref]
	return {"ok": true, "msg": "%s %s (%+d) ♥ %d/10" % [nm, react, delta, hearts(id)]}

func _preference(id: String, item_id: String) -> String:
	var g: Dictionary = GameData.npcs[id]["gifts"]
	if item_id in g.get("loved", []): return "loved"
	if item_id in g.get("liked", []): return "liked"
	if item_id in g.get("disliked", []): return "disliked"
	return "neutral"

func _is_birthday(id: String) -> bool:
	var b: Dictionary = GameData.npcs[id]["birthday"]
	return GameData.season_id(GameClock.season()) == b["season"] and GameClock.day_of_season() == int(b["day"])

func _add(id: String, d: int) -> void:
	state[id]["affection_points"] = clampi(int(state[id]["affection_points"]) + d, 0, MAX_AFF)

func _on_day_changed(_prev: int, _abs_day: int) -> void:
	for id in state:
		state[id]["talked_today"] = false
		state[id]["gifted_today"] = false
	snap_to_schedule()  # 취침으로 시각이 점프해도 아침엔 그 시각 장소에 이미 가 있게

# ── 저장 ───────────────────────────────────────────────────────
# npc_id 키(호감도) 옆에 결혼 상태를 평면 배치 (save_version 5). load_data는 state 키만 훑으므로
# 추가 키가 섞여도 무해하고, npc_id는 "npc." 접두라 spouse/engaged와 충돌하지 않는다.
func save_data() -> Dictionary:
	var d := state.duplicate(true)
	d["spouse"] = spouse if spouse != "" else null
	d["engaged"] = engaged.duplicate() if not engaged.is_empty() else null
	return d

func load_data(d: Dictionary) -> void:
	# 세이브에 있는 NPC만 덮어쓰고, 없는 NPC는 _ready 기본값 유지 (Codex: 기본값 보강)
	for id in state:
		if d.has(id):
			var s: Dictionary = d[id]
			# 방어: 구버전 hearts 필드만 있으면 ×25 변환 (현 세이브엔 affection_points)
			var pts := int(s.get("affection_points", int(s.get("hearts", 0)) * HEART))
			state[id]["affection_points"] = clampi(pts, 0, MAX_AFF)
			state[id]["talked_today"] = bool(s.get("talked_today", false))
			state[id]["gifted_today"] = bool(s.get("gifted_today", false))
			state[id]["dates_seen"] = clampi(int(s.get("dates_seen", 0)), 0, DATE_HEARTS.size())
	# 결혼 상태 복원. 없는 npc_id(데이터 삭제)면 미혼으로 되돌림 — 유령 배우자 방지.
	var sp := String(d.get("spouse", "") if d.get("spouse") != null else "")
	spouse = sp if state.has(sp) else ""
	engaged = {}
	var eng = d.get("engaged")
	if eng is Dictionary and state.has(String(eng.get("id", ""))):
		engaged = {"id": String(eng["id"]), "wedding_abs_day": int(eng.get("wedding_abs_day", 0))}
	_wedding_end = -1  # 식 도중 저장/로드 → 연출은 재생 안 함(married 상태는 이미 확정)
	_date = {}         # 데이트는 저장하지 않는다 — 로드하면 그날 다시 제안받는다(미소진)
	_spouse_indoor = false  # 실내 배치는 매 프레임 재판정 — 스냅이 배우자를 건너뛰지 않게 먼저 해제
	snap_to_schedule()  # 위치는 저장 안 함 — 로드한 시각의 장소에서 시작(집→광장 단체 행군 방지)

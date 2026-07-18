extends Node3D
# 주민 시스템 (DESIGN 6.4). 데이터 구동 — npcs.json에서 주민 스폰·호감도·대화·선물.
# 비주얼 = 주인공 고양이 모델 색조 변형 재사용(_make_visual 어댑터 한 곳만 거침 → 종족별
# 실물 모델 교체 용이). 낮엔 집 반경 배회, 밤·축제 중엔 정지(축제는 광장 배치 우선).

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
const OUTLINE_W := 0.004
# 배회 파라미터
const WANDER_SPEED := 1.6     # 플레이어 5.0보다 느리게
const WANDER_R_MIN := 4.0
const WANDER_R_MAX := 6.0
const WAIT_MIN := 5.0
const WAIT_MAX := 15.0
const WALK_SCALE := 1.6       # cat walk 애니 재생속도
const ARRIVE := 0.15          # 목표 도착 판정 거리
const DAY_START := 8          # 배회 시작 시각
const DAY_END := 20           # 배회 종료 시각
const POND_XZ := Vector2(10, 0)
const POND_AVOID := 3.0

# affection_points 0~250 저장, hearts는 파생 (Codex: F단계 청혼조건 재작업 방지)
var state := {}         # npc_id → {affection_points, talked_today, gifted_today}
var npc_nodes := {}     # npc_id → 스폰 root Node3D (축제 이동용, FestivalSystem이 호출)
var _wander := {}       # npc_id → {target:Vector3, wait:float, anim:AnimationPlayer, cur:String}
var _festival_active := false
var _shot_frozen := false  # 스크린샷 배치 시 배회 정지
var _farm: Node

func _ready() -> void:
	add_to_group("npc_system")
	_farm = get_tree().get_first_node_in_group("farm")
	for id in GameData.npcs:
		state[id] = {"affection_points": 0, "talked_today": false, "gifted_today": false}
		_spawn(id)
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
	npc_nodes[id] = root
	_wander[id] = {
		"target": root.position, "wait": randf_range(0.0, WAIT_MAX),
		"anim": ToonChar.find_anim(vis) if vis != null else null, "cur": "",
	}

# ── 비주얼 어댑터 (종족별 실물 모델 교체는 여기만 수정) ──────────────
func _make_visual(id: String, ndef: Dictionary) -> Node3D:
	var c: Array = ndef["color"]
	var tint := Color(c[0], c[1], c[2])
	var cat: Node3D = ToonChar.load_glb(CAT_GLB, OUTLINE_W, tint)
	if cat == null:
		return _fallback_capsule(tint)  # 폴백: 색상 캡슐
	var s := NPC_SCALE * (KID_MULT if id in KID_IDS else 1.0)
	cat.scale = Vector3(s, s, s)
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
	if _shot_frozen or _festival_active or GameClock.state == GameClock.State.PAUSED or not _is_daytime():
		for id in npc_nodes:  # 축제=광장 배치 유지, 그 외=idle
			_set_walk(id, false)
		return
	for id in npc_nodes:
		_wander_step(id, delta)

func _is_daytime() -> bool:
	var h := GameClock.hour()
	return h >= DAY_START and h < DAY_END

func _wander_step(id: String, delta: float) -> void:
	var st: Dictionary = _wander[id]
	var node: Node3D = npc_nodes[id]
	if st["wait"] > 0.0:
		st["wait"] = float(st["wait"]) - delta
		_set_walk(id, false)
		return
	var target: Vector3 = st["target"]
	var flat := Vector3(target.x - node.position.x, 0, target.z - node.position.z)
	if flat.length() < ARRIVE:  # 도착 → 대기 후 다음 목표
		st["wait"] = randf_range(WAIT_MIN, WAIT_MAX)
		st["target"] = _pick_target(id)
		_set_walk(id, false)
		return
	var step := minf(WANDER_SPEED * delta, flat.length())  # 프레임 드랍 시 목표 초과 방지
	node.position += flat.normalized() * step
	node.look_at(node.global_position + flat, Vector3.UP)  # yaw만 (flat.y=0)
	_set_walk(id, true)

# 집 반경 4~6m 랜덤점. 밭·연못 회피(목표점만 거름, 경로탐색 금지). 실패시 집 폴백.
func _pick_target(id: String) -> Vector3:
	var home: Array = GameData.npcs[id]["home"]
	var hp := Vector2(home[0], home[1])
	for _i in 8:
		var ang := randf() * TAU
		var r := randf_range(WANDER_R_MIN, WANDER_R_MAX)
		var p := hp + Vector2(cos(ang), sin(ang)) * r
		if _farm != null and _farm.in_region(Vector2i(floori(p.x), floori(p.y))):
			continue
		if p.distance_to(POND_XZ) < POND_AVOID:
			continue
		return Vector3(p.x, 0, p.y)
	return Vector3(home[0], 0, home[1])

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

# 스크린샷용: 주민 8명 카메라 앞 격자 배치 + 배회 정지 (world.gd "npcs" cmdline)
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
	return {"ok": true, "msg": "%s: %s  H%d%s" % [nm, _dialogue_line(id), hearts(id), extra]}

# 아키타입별 대사 랜덤 1줄 (축제 중이면 축제 풀 우선). 계절·호감도 분기는 H단계 몫.
func _dialogue_line(id: String) -> String:
	var arche: String = GameData.npcs[id]["archetype"]
	var pool: Dictionary = GameData.dialogues.get(arche, {})
	var fest: Array = pool.get("festival", [])
	var lines: Array = fest if (_festival_active and not fest.is_empty()) else pool.get("normal", [])
	return "" if lines.is_empty() else lines[randi() % lines.size()]

# ── 축제 (FestivalSystem이 상태만 설정, 호감도·이동은 여기 소유) ──
func enter_festival(plaza: Vector2) -> void:
	_festival_active = true
	var ids := npc_nodes.keys()
	var n := ids.size()
	for i in n:
		var ang := TAU * i / float(maxi(n, 1))
		var pos := plaza + Vector2(cos(ang), sin(ang)) * FEST_RING
		npc_nodes[ids[i]].position = Vector3(pos.x, 0, pos.y)

func exit_festival() -> void:
	_festival_active = false
	for id in npc_nodes:  # 집 위치로 복귀 (데이터가 단일 출처)
		var home: Array = GameData.npcs[id]["home"]
		npc_nodes[id].position = Vector3(home[0], 0, home[1])
		_wander[id]["target"] = npc_nodes[id].position  # 배회 재개 기준 리셋
		_wander[id]["wait"] = randf_range(0.0, WAIT_MAX)

# 선물: 하루 1회, 취향별 ±, 생일 ×8, 0~250 clamp
func give(id: String, item_id: String) -> Dictionary:
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
	return {"ok": true, "msg": "%s %s (%+d) H%d" % [nm, react, delta, hearts(id)]}

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

# ── 저장 ───────────────────────────────────────────────────────
func save_data() -> Dictionary:
	return state.duplicate(true)

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

extends Node3D
# 주민 시스템 (DESIGN 6.4). 데이터 구동 — npcs.json에서 주민 스폰·호감도·대화·선물.
# 모델 독립: 실제 캐릭터 메시 전까지 플레이스홀더 캡슐(색상별).

const HEART := 25       # 25포인트 = 하트 1칸
const MAX_AFF := 250    # 10칸
const FESTIVAL_MULT := 2  # 축제 중 대화 호감도 배율
const FEST_RING := 2.3    # 광장 링 배치 반경
const ToonChar := preload("res://common/toon_character.gd")

# affection_points 0~250 저장, hearts는 파생 (Codex: F단계 청혼조건 재작업 방지)
var state := {}         # npc_id → {affection_points, talked_today, gifted_today}
var npc_nodes := {}     # npc_id → 스폰 노드 (축제 이동용, FestivalSystem이 호출)
var _festival_active := false

func _ready() -> void:
	add_to_group("npc_system")
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
	var mesh := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.4
	cap.height = 1.6
	mesh.mesh = cap
	var c: Array = n["color"]
	mesh.material_override = ToonChar.make_solid(Color(c[0], c[1], c[2]), 0.008)  # 곡면 툰 + 외곽선
	mesh.position = Vector3(0, 1.0, 0)
	root.add_child(mesh)
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

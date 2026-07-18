extends CharacterBody3D
# 플레이어 이동 + 농사 상호작용 (DESIGN 11.4). 조준 = 바라보는 앞 1타일.

signal stats_changed       # 소지금/인벤/선택 변경 → HUD 갱신
signal message(text: String)  # 대화/선물/상점 피드백 → HUD 토스트

@export var speed := 5.0
@export var gravity := 24.0

var gold := 500
var inventory := []          # [{id, qty}]
var selected_seed := ""      # 선택 씨앗 id (구매·심기 대상)

var _last_dir := Vector3(0, 0, 1)  # 조준 방향 (정지시 유지)
var _farm: Node
var _npcsys: Node
var _highlight: MeshInstance3D

@onready var _interact_area: Area3D = $InteractArea

const CAT_GLB := "res://assets/cat_anim.glb"  # idle/walk 애니 포함 (cat.glb 교체 아님)
const ToonChar := preload("res://common/toon_character.gd")  # class_name 대신 preload(헤드리스 안전)
@export var visual_scale := 2.1
@export var visual_y := -0.85  # 발바닥을 캡슐 밑면에 맞춤 (스크린샷 보고 튜닝)
# walk 재생속도 배율. 무슬립 이론값은 ~8.9(치비 다리엔 과속) → 가독 우선 절충값, 스크린샷 튜닝.
@export var walk_speed_scale := 1.6

var _anim: AnimationPlayer
var _cur_anim := ""

func _setup_visual() -> void:
	var cat: Node3D = ToonChar.load_glb(CAT_GLB, 0.004)
	if cat == null:
		return  # 폴백: 기본 캡슐 유지
	$Mesh.visible = false
	cat.scale = Vector3(visual_scale, visual_scale, visual_scale)
	cat.position.y = visual_y
	cat.rotation.y = PI  # 앞=+Z, Godot look_at은 -Z 기준 → 180° 보정 (실측 확정)
	add_child(cat)
	_anim = ToonChar.find_anim(cat)
	if _anim != null:
		for n in ["idle", "walk"]:
			if _anim.has_animation(n):
				_anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
		_play_anim("idle")

# walk/idle 전환 (0.2s 블렌드). 같은 클립 재요청은 무시(재시작 방지)
func _play_anim(clip: String) -> void:
	if _anim == null or _cur_anim == clip or not _anim.has_animation(clip):
		return
	_cur_anim = clip
	var spd := walk_speed_scale if clip == "walk" else 1.0
	_anim.play(clip, 0.2, spd)

func _ready() -> void:
	_farm = get_tree().get_first_node_in_group("farm")
	_npcsys = get_tree().get_first_node_in_group("npc_system")
	_setup_visual()
	_face_dir(_last_dir)  # 정지 스폰도 조준(_last_dir=아래)과 일치하게
	_make_highlight()
	if selected_seed == "":
		_select_first_seed()
	stats_changed.emit()

func _physics_process(delta: float) -> void:
	if GameClock.state == GameClock.State.PAUSED:  # 메뉴 열림 = 조작 정지
		velocity = Vector3.ZERO
		return
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var dir := Vector3(input.x, 0.0, input.y)
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	move_and_slide()

	if dir.length() > 0.1:
		_face_dir(dir)
	# 수평 속도로 walk/idle 전환
	_play_anim("walk" if Vector2(velocity.x, velocity.z).length() > 0.1 else "idle")
	_update_highlight()

# 이동/조준 방향으로 몸을 돌림 (_last_dir = 조준 기준, 건드리지 않음)
func _face_dir(dir: Vector3) -> void:
	_last_dir = dir.normalized()
	var t := global_position + _last_dir
	look_at(Vector3(t.x, global_position.y, t.z), Vector3.UP)

func _unhandled_input(event: InputEvent) -> void:
	if GameClock.state == GameClock.State.PAUSED:  # 메뉴 열림 = 상호작용 차단
		return
	if event.is_action_pressed("interact"):
		_try_interact()
	elif event.is_action_pressed("use_tool"):
		_use_tool()
	elif event.is_action_pressed("cycle_seed"):
		_cycle_seed()
	elif event.is_action_pressed("give"):
		_give()

# ── 조준 ───────────────────────────────────────────────────────
func _cardinal(d: Vector3) -> Vector3:
	if absf(d.x) > absf(d.z):
		return Vector3(signf(d.x), 0, 0)
	return Vector3(0, 0, signf(d.z))

func _aim_cell() -> Vector2i:
	var base := global_position + _cardinal(_last_dir)
	return Vector2i(floori(base.x), floori(base.z))

func _make_highlight() -> void:
	_highlight = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(0.98, 0.98)
	_highlight.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1, 1, 0.3, 0.35)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_highlight.material_override = m
	get_tree().current_scene.add_child.call_deferred(_highlight)

func _update_highlight() -> void:
	if _highlight == null or _farm == null:
		return
	var cell := _aim_cell()
	_highlight.position = Vector3(cell.x + 0.5, 0.13, cell.y + 0.5)
	_highlight.visible = _farm.in_region(cell)

# ── 도구 사용 (상황별) ─────────────────────────────────────────
func _use_tool() -> void:
	if _farm == null:
		return
	var cell := _aim_cell()
	if _farm.is_mature_at(cell):
		var cid: String = _farm.harvest(cell)
		if cid != "":
			_add_item(cid, 1)
		return
	var t: Dictionary = _farm.get_tile(cell)
	if not t.is_empty() and t.get("crop_id", "") != "":
		_farm.water(cell)  # 심긴 상태 → 물
		return
	if not t.is_empty() and t.get("crop_id", "") == "":
		if selected_seed != "" and _count(selected_seed) > 0:  # 갈아엎음 + 씨앗 → 심기
			if _farm.plant(cell, selected_seed):
				_remove_item(selected_seed, 1)
		return
	_farm.till(cell)  # 맨땅 → 괭이질

# ── 상호작용 (침대/상점/판매상자/대화) ─────────────────────────
# 겹친 대상 중 가장 가까운 것 {kind, area}. 프롬프트·실행 공용 (판정 단일화).
func interact_target() -> Dictionary:
	var best: Area3D = null
	var best_kind := ""
	var best_d := INF
	for a in _interact_area.get_overlapping_areas():
		var kind := _area_kind(a)
		if kind == "":
			continue
		var d := global_position.distance_squared_to(a.global_position)
		if d < best_d:
			best_d = d; best = a; best_kind = kind
	return {} if best == null else {"kind": best_kind, "area": best}

func _area_kind(a: Area3D) -> String:
	for k in ["bed", "shop", "bin", "npc"]:
		if a.is_in_group(k):
			return k
	return ""

# HUD 프롬프트 문구 (대상 없으면 "")
func interact_prompt() -> String:
	var t := interact_target()
	if t.is_empty():
		return ""
	match t["kind"]:
		"bed": return "E: 취침"
		"shop": return "E: 상점"
		"bin": return "E: 판매 상자"
		"npc": return "E: 대화 — " + GameData.npcs[t["area"].get_meta("npc_id")]["name"]
	return ""

func _try_interact() -> void:
	var t := interact_target()
	if t.is_empty():
		message.emit("주변에 상호작용할 것이 없어요")
		return
	match t["kind"]:
		"bed": _sleep()
		"shop": _buy_seed()
		"bin": _deposit_all()
		"npc":
			var r: Dictionary = _npcsys.talk(t["area"].get_meta("npc_id"))
			message.emit(r["msg"])

func _give() -> void:
	var npc_area := _nearest_npc()
	if npc_area == null:
		return
	for e in inventory:
		if GameData.crops.has(e["id"]):  # 작물만 선물
			var r: Dictionary = _npcsys.give(npc_area.get_meta("npc_id"), e["id"])
			if r["ok"]:
				_remove_item(e["id"], 1)
			message.emit(r["msg"])
			return
	message.emit("줄 작물 없음")

func _nearest_npc() -> Area3D:
	for a in _interact_area.get_overlapping_areas():
		if a.is_in_group("npc"):
			return a
	return null

func _sleep() -> void:
	var ss := get_tree().get_first_node_in_group("sleep_screen")
	if ss != null:
		ss.request_sleep()  # 확인 다이얼로그 → 페이드 → sleep+저장
	else:  # 폴백: 화면 없으면 즉시 (안전)
		GameClock.sleep_to_morning()
		SaveManager.request_save("sleep")

func _buy_seed() -> void:
	if selected_seed == "":
		return
	if GameClock.weekday() == 6:  # 일요일 휴무
		message.emit("Shop closed (Sun)")
		return
	var cost := GameData.seed_cost(selected_seed)
	if gold >= cost:
		gold -= cost
		_add_item(selected_seed, 1)
		message.emit("Bought " + GameData.display_name(GameData.crop_from_seed(selected_seed)) + " seed")
	else:
		message.emit("골드 부족")

func _deposit_all() -> void:
	for e in inventory.duplicate():
		if GameData.crops.has(e["id"]):  # 작물만 판매상자로
			var accepted: int = _farm.deposit(e["id"], int(e["qty"]))  # 실제 수락량만 차감(증발 방지)
			if accepted > 0:
				_remove_item(e["id"], accepted)

# ── 소지금/인벤 ────────────────────────────────────────────────
func add_gold(n: int) -> void:
	gold += n
	stats_changed.emit()

func _add_item(id: String, qty: int) -> void:
	for e in inventory:
		if e["id"] == id:
			e["qty"] = int(e["qty"]) + qty
			stats_changed.emit(); return
	inventory.append({"id": id, "qty": qty})
	stats_changed.emit()

func _remove_item(id: String, qty: int) -> void:
	for e in inventory:
		if e["id"] == id:
			e["qty"] = int(e["qty"]) - qty
			if e["qty"] <= 0:
				inventory.erase(e)
			stats_changed.emit(); return

func _count(id: String) -> int:
	for e in inventory:
		if e["id"] == id:
			return int(e["qty"])
	return 0

func _select_first_seed() -> void:
	var seeds := GameData.all_seed_ids()
	if seeds.size() > 0:
		selected_seed = seeds[0]

func _cycle_seed() -> void:
	var seeds := GameData.all_seed_ids()
	if seeds.is_empty():
		return
	var i := seeds.find(selected_seed)
	selected_seed = seeds[(i + 1) % seeds.size()]
	stats_changed.emit()

# ── 저장 ───────────────────────────────────────────────────────
func save_data() -> Dictionary:
	return {
		"pos": [global_position.x, global_position.y, global_position.z],
		"gold": gold,
		"inventory": inventory.duplicate(true),
		"selected_seed": selected_seed,
	}

func load_data(d: Dictionary) -> void:
	var p: Array = d.get("pos", [0.0, 2.0, 0.0])
	global_position = Vector3(p[0], p[1], p[2])
	gold = int(d.get("gold", 500))
	inventory = d.get("inventory", []).duplicate(true)
	selected_seed = d.get("selected_seed", "")
	if selected_seed == "":
		_select_first_seed()
	stats_changed.emit()

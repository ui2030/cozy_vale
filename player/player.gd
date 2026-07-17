extends CharacterBody3D
# 플레이어 이동 + 농사 상호작용 (DESIGN 11.4). 조준 = 바라보는 앞 1타일.

signal stats_changed  # 소지금/인벤/선택 변경 → HUD 갱신

@export var speed := 5.0
@export var gravity := 24.0

var gold := 500
var inventory := []          # [{id, qty}]
var selected_seed := ""      # 선택 씨앗 id (구매·심기 대상)

var _last_dir := Vector3(0, 0, 1)  # 조준 방향 (정지시 유지)
var _farm: Node
var _highlight: MeshInstance3D

@onready var _interact_area: Area3D = $InteractArea

func _ready() -> void:
	_farm = get_tree().get_first_node_in_group("farm")
	_make_highlight()
	if selected_seed == "":
		_select_first_seed()
	stats_changed.emit()

func _physics_process(delta: float) -> void:
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
		_last_dir = dir.normalized()
		var t := global_position + _last_dir
		look_at(Vector3(t.x, global_position.y, t.z), Vector3.UP)
	_update_highlight()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		_try_interact()
	elif event.is_action_pressed("use_tool"):
		_use_tool()
	elif event.is_action_pressed("cycle_seed"):
		_cycle_seed()

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

# ── 상호작용 (침대/상점/판매상자) ──────────────────────────────
func _try_interact() -> void:
	for a in _interact_area.get_overlapping_areas():
		if a.is_in_group("bed"):
			_sleep(); return
		if a.is_in_group("shop"):
			_buy_seed(); return
		if a.is_in_group("bin"):
			_deposit_all(); return

func _sleep() -> void:
	GameClock.sleep_to_morning()   # clock → day_changed 구독자(농사) 정산
	SaveManager.request_save("sleep")  # 그 다음 저장 (큐잉)

func _buy_seed() -> void:
	if selected_seed == "":
		return
	var cost := GameData.seed_cost(selected_seed)
	if gold >= cost:
		gold -= cost
		_add_item(selected_seed, 1)

func _deposit_all() -> void:
	for e in inventory.duplicate():
		if GameData.crops.has(e["id"]):  # 작물만 판매상자로
			_farm.deposit(e["id"], int(e["qty"]))
			_remove_item(e["id"], int(e["qty"]))

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

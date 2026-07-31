extends CharacterBody3D
# 플레이어 이동 + 농사 상호작용 (DESIGN 11.4). 조준 = 바라보는 앞 1타일.

signal stats_changed       # 소지금/인벤/선택 변경 → HUD 갱신
signal message(text: String)  # 대화/선물/상점 피드백 → HUD 토스트

@export var speed := 5.0
@export var gravity := 24.0

var gold := 500
var inventory := []          # [{id, qty}]
var selected_seed := ""      # 선택 씨앗 id (구매·심기 대상)
var collection := []         # 발견한 산출물 id (도감)

var _last_dir := Vector3(0, 0, 1)  # 조준 방향 (정지시 유지)
var _farm: Node
var _npcsys: Node
var _highlight: MeshInstance3D
var _fishing: Node           # 낚시 미니게임 (지연 조회 — HUD 초기화 순서 안전)

@onready var _interact_area: Area3D = $InteractArea

const CAT_GLB := "res://assets/cat_anim.glb"  # idle/walk 애니 포함 (cat.glb 교체 아님)
const ToonChar := preload("res://common/toon_character.gd")  # class_name 대신 preload(헤드리스 안전)
const WorldScript := preload("res://world/world.gd")  # 다리 데크 곡선 단일 출처 (world.gd는 player를 preload 안 함 = 무순환)
@export var visual_scale := 2.1
@export var visual_y := -0.85  # 발바닥을 캡슐 밑면에 맞춤 (스크린샷 보고 튜닝)
# walk 재생속도 배율. 무슬립 이론값은 ~8.9(치비 다리엔 과속) → 가독 우선 절충값, 스크린샷 튜닝.
@export var walk_speed_scale := 1.6

var _anim: AnimationPlayer
var _visual: Node3D          # GLB 루트 — 다리 위 시각 리프트를 여기에 건다
var _cur_anim := ""
var _step_t := 0.0  # 발소리 간격 누적 (걷는 동안만)

const STEP_INTERVAL := 0.42  # 발소리 주기(초) — walk 클립 보속에 맞춘 실측 절충값

func _setup_visual() -> void:
	var cat: Node3D = ToonChar.load_glb(CAT_GLB, ToonChar.OUTLINE_WORLD)
	if cat == null:
		return  # 폴백: 기본 캡슐 유지
	$Mesh.visible = false
	cat.scale = Vector3(visual_scale, visual_scale, visual_scale)
	ToonChar.set_outline_width(cat, ToonChar.OUTLINE_WORLD / visual_scale)  # 오브젝트→월드 굵기 보정
	cat.position.y = visual_y
	cat.rotation.y = PI  # 앞=+Z, Godot look_at은 -Z 기준 → 180° 보정 (실측 확정)
	add_child(cat)
	_visual = cat
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
	# 3D 소리는 플레이어 기준으로 들린다. 기본 리스너인 Camera3D는 뒤로 9.5·위로 6.5 떨어져
	# 있어 그대로 두면 물가 감쇠 거리가 카메라 기준이 돼 어긋난다.
	var listener := AudioListener3D.new()
	add_child(listener)
	listener.make_current()
	_face_dir(_last_dir)  # 정지 스폰도 조준(_last_dir=아래)과 일치하게
	_make_highlight()
	if selected_seed == "":
		_select_first_seed()
	stats_changed.emit()

# 낚시 중 = 이동/상호작용 정지. 지연 조회(HUD 늦게 준비돼도 안전), 시계는 계속 흐름.
func _is_fishing() -> bool:
	if _fishing == null:
		_fishing = get_tree().get_first_node_in_group("fishing")
	return _fishing != null and _fishing.is_active()

func _physics_process(delta: float) -> void:
	if GameClock.state == GameClock.State.PAUSED or _is_fishing():  # 메뉴/낚시 = 조작 정지
		velocity = Vector3.ZERO
		_play_anim("idle")  # 걷던 중 정지돼도 제자리걸음 안 남게
		_deck_lift()  # 정지 중(메뉴·낚시·스샷 하네스 PAUSED)에도 다리 위 높이는 맞아야 한다
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
	var moving := Vector2(velocity.x, velocity.z).length() > 0.1
	_play_anim("walk" if moving else "idle")
	_footsteps(delta, moving)
	_update_highlight()
	_deck_lift()  # move_and_slide 뒤 위치 기준 — 다리에 올라설 때 한 프레임 밀리지 않게

# 다리 위 시각 리프트. 다리엔 충돌이 없어(통행 계약) 몸통은 지면 높이 그대로 지나간다 —
# 그러면 돌다리에 발이 파묻힌다. 몸통(CharacterBody3D)을 올리면 is_on_floor가 풀려 중력이
# 도로 끌어내리고, 카메라가 몸통을 추종하므로 화면이 튄다. 그래서 비주얼 자식만 올린다.
# 높이 곡선은 world.gd deck_lift 단일 출처 = NPC 발높이와 같은 값.
func _deck_lift() -> void:
	if _visual != null:
		_visual.position.y = visual_y + WorldScript.deck_lift(Vector2(global_position.x, global_position.z))

# 걷는 동안 STEP_INTERVAL마다 발소리. 멈추면 다음 첫 걸음이 바로 나도록 누적값을 채워 둔다.
func _footsteps(delta: float, moving: bool) -> void:
	if not moving:
		_step_t = STEP_INTERVAL
		return
	_step_t += delta
	if _step_t >= STEP_INTERVAL:
		_step_t = 0.0
		Sfx.play("step", -6.0)

# 이동/조준 방향으로 몸을 돌림 (_last_dir = 조준 기준, 건드리지 않음)
func _face_dir(dir: Vector3) -> void:
	_last_dir = dir.normalized()
	var t := global_position + _last_dir
	look_at(Vector3(t.x, global_position.y, t.z), Vector3.UP)

func _unhandled_input(event: InputEvent) -> void:
	if GameClock.state == GameClock.State.PAUSED or _is_fishing():  # 메뉴/낚시 = 상호작용 차단
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
	# 소리는 전부 "실제로 상태가 바뀐 경우"에만 — 헛손질에 효과음이 나면 성공 피드백이 망가진다.
	if _farm.is_mature_at(cell):
		var cid: String = _farm.harvest(cell)
		if cid != "":
			_add_item(cid, 1)
			Sfx.play("harvest")
		return
	var t: Dictionary = _farm.get_tile(cell)
	if not t.is_empty() and t.get("crop_id", "") != "":
		if _farm.water(cell):  # 심긴 상태 → 물 (이미 준 날은 false)
			Sfx.play("water")
		return
	if not t.is_empty() and t.get("crop_id", "") == "":
		var sid := active_seed()
		if sid != "" and count(sid) > 0:  # 갈아엎음 + 씨앗 → 심기
			if _farm.plant(cell, sid):
				_remove_item(sid, 1)
				Sfx.play("plant")
			else:  # 빈 타일이 확인된 뒤라 실패 사유는 계절뿐 (씨앗은 소모되지 않음)
				message.emit("지금 계절엔 심을 수 없어요")
		return
	if _farm.till(cell):  # 맨땅 → 괭이질
		Sfx.play("hoe")

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
	for k in ["bed", "shop", "bin", "npc", "water", "forage", "door", "stove"]:
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
		"water": return "E: 낚시"
		"forage": return "E: 줍기"
		"stove": return "E: 요리"
		"door": return String(t["area"].get_meta("door_label", "E: 문"))
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
			if r["ok"]:  # 오늘 이미 대화한 상대는 무음 (대사만)
				Sfx.play("talk")
			message.emit(r["msg"])
		"water": _start_fishing(t["area"])
		"forage": _pick_forage(t["area"])
		"stove": _open_cooking()
		"door": _use_door(t["area"])

# 부엌 스토브 = 요리 패널. 여는 E가 같은 프레임에 패널의 닫기로 다시 판정되지 않게 소비한다
# (낚시 시작과 같은 이유 — HUD 패널이 트리 역순으로 입력을 먼저 받는다).
func _open_cooking() -> void:
	var panel := get_tree().get_first_node_in_group("cooking_panel")
	if panel == null:
		return
	panel.open()
	get_viewport().set_input_as_handled()

# 문 = 좌표 텔레포트 (씬 전환 없음). 도착점은 반대편 문 트리거 밖이라 E 연타로 왕복하지 않는다.
func _use_door(area: Area3D) -> void:
	global_position = area.get_meta("door_to")
	velocity = Vector3.ZERO
	_face_dir(area.get_meta("door_face", Vector3(0, 0, 1)))
	Sfx.play("ui_open")

# 낚시터(연못/바다)는 물가 Area3D의 메타 "spot"이 정한다 — 없으면 "pond"(기존 연못·강 그대로).
func _start_fishing(area: Area3D = null) -> void:
	if _fishing == null:
		_fishing = get_tree().get_first_node_in_group("fishing")
	var pool := GameData.season_filter(GameData.fish, GameData.season_id(GameClock.season()))
	if _fishing == null or pool.is_empty():
		message.emit("여긴 잡을 게 없네요")
		return
	var spot := GameData.SPOT_POND if area == null else String(area.get_meta("spot", GameData.SPOT_POND))
	var fid: String = GameData.pick_fish(GameData.fish, pool, randf(), GameClock.hour(), spot)
	if fid == "":  # 시간대 필터로 후보 0 (밤물고기만 남는 낮 등)
		message.emit("지금은 물릴 게 없네요")
		return
	_fishing.start(fid, float(GameData.fish[fid].get("difficulty", 0.5)))
	get_viewport().set_input_as_handled()  # 시작 E가 즉시 판정되는 것 방지

func _pick_forage(area: Area3D) -> void:
	var fid: String = area.get_meta("forage_id", "")
	if fid == "":
		return
	var fs := get_tree().get_first_node_in_group("forage_system")
	if fs != null:
		fs.remove(area)
	_add_item(fid, 1)
	Sfx.play("pickup")

func _give() -> void:
	var npc_area := _near("npc")
	if npc_area == null:
		return
	var npc_id: String = npc_area.get_meta("npc_id")
	# 청혼: 반지 소지 + 결혼 후보에게 G. 거절이면 반지를 소모하지 않는다(_npcsys가 ok로 알려줌).
	# 반지는 산출물이 아니라 아래 선물 루프에 애초에 걸리지 않는다 → 비후보에게 오소모 불가.
	if count(GameData.RING_ID) > 0 and _npcsys.is_candidate(npc_id):
		message.emit(propose_with_ring(npc_id)["msg"])
		return
	for e in inventory:
		if GameData.is_produce(e["id"]):  # 산출물(작물·물고기·채집물) + 요리 선물
			var r: Dictionary = _npcsys.give(npc_id, e["id"])
			if r["ok"]:
				_remove_item(e["id"], 1)
			message.emit(r["msg"])
			return
	message.emit("줄 것이 없어요")

# 청혼 실행: 수락일 때만 반지 소모. Area3D 없이도 검증 가능하게 분리(test_core가 직접 호출).
func propose_with_ring(npc_id: String) -> Dictionary:
	var r: Dictionary = _npcsys.propose(npc_id)
	if r["ok"]:
		_remove_item(GameData.RING_ID, 1)
		Sfx.play("talk")
	return r

# 겹친 상호작용 Area3D 중 그 그룹 첫 것 (npc·shop 공용)
func _near(group: String) -> Area3D:
	for a in _interact_area.get_overlapping_areas():
		if a.is_in_group(group):
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
	if GameClock.weekday() == 6:  # 일요일 휴무
		message.emit("Shop closed (Sun)")
		return
	var stock := GameData.season_seed_ids(GameData.season_id(GameClock.season()))
	if stock.is_empty():  # 겨울 = 씨앗 재고 0 (설계상 낚시·채집의 계절)
		message.emit("이번 계절엔 씨앗을 팔지 않아요")
		return
	var sid := active_seed()
	if not sid in stock:  # 철 지난 보유 씨앗을 든 채 상점에 온 경우
		message.emit("이번 계절 씨앗만 팔아요 (Q로 전환)")
		return
	var cost := GameData.seed_cost(sid)
	if gold < cost:
		message.emit("골드 부족")
		return
	gold -= cost
	_add_item(sid, 1)
	Sfx.play("coin")
	message.emit("Bought " + GameData.display_name(GameData.crop_from_seed(sid)) + " seed")

# 프러포즈 아이템 구매 (가방 패널 버튼 → 여기). 씨앗 구매와 같은 상점 규칙(휴무·골드).
# 씨앗 순환·선택 집합엔 넣지 않는다 — 반지는 all_seed_ids 밖의 단일 아이템.
func buy_ring() -> void:
	if count(GameData.RING_ID) > 0:
		message.emit("이미 " + GameData.RING_NAME + "을 가지고 있어요")
		return
	if _near("shop") == null:
		message.emit(GameData.RING_NAME + "은 상점에서만 살 수 있어요")
		return
	if GameClock.weekday() == 6:  # 일요일 휴무 (씨앗 구매와 동일)
		message.emit("Shop closed (Sun)")
		return
	if gold < GameData.RING_COST:
		message.emit("골드 부족 (%dG 필요)" % GameData.RING_COST)
		return
	gold -= GameData.RING_COST
	_add_item(GameData.RING_ID, 1)
	Sfx.play("coin")
	message.emit(GameData.RING_NAME + " 구매! 마음에 둔 사람에게 G")

# ── 요리 (부엌 스토브) ─────────────────────────────────────────
# 재료 전량 보유 판정. 모르는 레시피는 false(패널·테스트 공용 단일 판정).
func can_cook(recipe_id: String) -> bool:
	if not GameData.recipes.has(recipe_id):
		return false
	var ing: Dictionary = GameData.recipes[recipe_id]["ingredients"]
	for iid in ing:
		if count(iid) < int(ing[iid]):
			return false
	return true

# 요리 실행: 재료 차감 → 요리 1개. Area3D 없이도 검증 가능하게 분리(test_core가 직접 호출).
func cook(recipe_id: String) -> bool:
	if not can_cook(recipe_id):
		return false
	var ing: Dictionary = GameData.recipes[recipe_id]["ingredients"]
	for iid in ing:
		_remove_item(iid, int(ing[iid]))
	_add_item(recipe_id, 1)
	Sfx.play("harvest")
	message.emit(GameData.display_name(recipe_id) + " 완성!")
	return true

func _deposit_all() -> void:
	var any := false
	for e in inventory.duplicate():
		if GameData.is_produce(e["id"]):  # 산출물(작물·물고기·채집물) + 요리 판매상자로
			var accepted: int = _farm.deposit(e["id"], int(e["qty"]))  # 실제 수락량만 차감(증발 방지)
			if accepted > 0:
				_remove_item(e["id"], accepted)
				any = true
	if any:  # 빈손으로 상자를 열면 무음
		Sfx.play("deposit")

# ── 소지금/인벤 ────────────────────────────────────────────────
func add_gold(n: int) -> void:
	gold += n
	stats_changed.emit()

func _add_item(id: String, qty: int) -> void:
	_discover(id)  # 스택 증가 경로에서도 최초 발견 등록 (early-return 앞)
	for e in inventory:
		if e["id"] == id:
			e["qty"] = int(e["qty"]) + qty
			stats_changed.emit(); return
	inventory.append({"id": id, "qty": qty})
	stats_changed.emit()

# 도감: 자연 산출물 최초 획득이면 등록 + 토스트 (요리는 도감 대상 아님 = is_collectible)
func _discover(id: String) -> void:
	if not GameData.is_collectible(id) or id in collection:
		return
	collection.append(id)
	message.emit("도감 등록: " + GameData.display_name(id))

func _remove_item(id: String, qty: int) -> void:
	for e in inventory:
		if e["id"] == id:
			e["qty"] = int(e["qty"]) - qty
			if e["qty"] <= 0:
				inventory.erase(e)
			stats_changed.emit(); return

func count(id: String) -> int:  # UI(HUD·가방 패널)도 읽는 공개 조회
	for e in inventory:
		if e["id"] == id:
			return int(e["qty"])
	return 0

# 가방 패널 클릭 선택 (Q 순환과 같은 집합·같은 신호 — 두 경로가 어긋나지 않게 여기로 단일화)
func select_seed(id: String) -> void:
	if id == selected_seed or not id in GameData.all_seed_ids():
		return
	selected_seed = id
	stats_changed.emit()

# Q 순환·가방 패널 공용 집합: 보유(>0) 씨앗 ∪ 이번 계절 상점 재고.
# 12종을 통째로 돌리면 소음이라 "지금 쓸 수 있는 것"만 남긴다. 철 지난 보유 씨앗은
# 재고엔 없어도 남아 있으니 순환·패널 양쪽에 계속 보인다(재고 확인 가능).
func cycle_seeds() -> Array:
	var stock := GameData.season_seed_ids(GameData.season_id(GameClock.season()))
	var out := []
	for sid in GameData.all_seed_ids():  # 정렬 단일 출처
		if sid in stock or count(sid) > 0:
			out.append(sid)
	return out

# 실제로 적용되는 선택 씨앗. 계절이 바뀌어 선택이 순환 집합 밖으로 밀리면 첫 후보로 스냅해서
# 읽는 쪽(HUD·상점·심기·패널 강조)을 통일한다 — selected_seed(저장 표면)는 건드리지 않는다.
func active_seed() -> String:
	var seeds := cycle_seeds()
	if seeds.is_empty():  # 겨울 무보유 = 고를 씨앗 자체가 없음
		return ""
	return selected_seed if selected_seed in seeds else seeds[0]

func _select_first_seed() -> void:
	var seeds := cycle_seeds()
	if seeds.size() > 0:
		selected_seed = seeds[0]

func _cycle_seed() -> void:
	var seeds := cycle_seeds()
	if seeds.is_empty():
		return
	var i := seeds.find(active_seed())  # 스냅된 자리 다음으로 — 계절 바뀐 뒤 첫 Q가 제자리 걸음 안 함
	selected_seed = seeds[(i + 1) % seeds.size()]
	stats_changed.emit()

# ── 저장 ───────────────────────────────────────────────────────
func save_data() -> Dictionary:
	return {
		"pos": [global_position.x, global_position.y, global_position.z],
		"gold": gold,
		"inventory": inventory.duplicate(true),
		"selected_seed": selected_seed,
		"collection": collection.duplicate(),
	}

func load_data(d: Dictionary) -> void:
	var p: Array = d.get("pos", [0.0, 2.0, 0.0])
	global_position = Vector3(p[0], p[1], p[2])
	gold = int(d.get("gold", 500))
	inventory = d.get("inventory", []).duplicate(true)
	collection = d.get("collection", []).duplicate()
	selected_seed = d.get("selected_seed", "")
	if selected_seed == "":
		_select_first_seed()
	stats_changed.emit()

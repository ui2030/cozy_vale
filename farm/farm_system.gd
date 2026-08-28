extends Node3D
# 밭 타일맵 단일 소유 (DESIGN 6.2 / 11.3). 타일 상태·성장·판매상자 정산.
# day_changed 처리 순서 고정(Codex): 정산 → 성장 → 계절고사 → 물리셋 → (저장은 호출측).

const REGION := Rect2i(0, 2, 8, 4)  # 밭 구역: cell x[0..7], z[2..5]
const ToonChar := preload("res://common/toon_character.gd")

var tiles := {}          # Vector2i → {tilled, crop_id, planted_abs_day, watered_growth_days, watered}
var shipping_bin := []   # [{id, qty}] — 인벤에서 즉시 차감돼 여기 저장(중복·증발 방지)
var _nodes := {}         # Vector2i → {soil: MeshInstance3D, crop: Node3D(겉모습 자리), key: String}

func _ready() -> void:
	add_to_group("farm")
	if not GameClock.day_changed.is_connected(_on_day_changed):
		GameClock.day_changed.connect(_on_day_changed)  # 이중구독 방지

func in_region(cell: Vector2i) -> bool:
	return REGION.has_point(cell)

# 비 오는 날은 심긴 작물이 전부 젖어 있다(자동 물주기). watered를 새로 놓는 자리는 전부 이걸 통과시켜
# "오늘 비면 젖음"이 한 군데서만 결정되게 한다 — 일변경 리셋·심기·재수확·세이브 로드 공통.
func _wet_today() -> bool:
	return GameData.is_rainy(GameClock.abs_day)

func _center(cell: Vector2i) -> Vector3:
	return Vector3(cell.x + 0.5, 0.0, cell.y + 0.5)

# ── 타일 조작 (player가 조준 셀로 호출) ─────────────────────────
func get_tile(cell: Vector2i) -> Dictionary:
	return tiles.get(cell, {})

func is_mature_at(cell: Vector2i) -> bool:
	var t: Dictionary = tiles.get(cell, {})
	var cid: String = t.get("crop_id", "")
	# 제철이 아니면 다 자랐어도 열매가 없다(다년생 휴면). 한해살이는 어차피 다음 아침 고사한다.
	return cid != "" and _in_season(cid) \
		and int(t.get("watered_growth_days", 0)) >= GameData.grow_days(cid)

func _in_season(crop_id: String) -> bool:
	return GameData.crop_in_season(crop_id, GameData.season_id(GameClock.season()))

func till(cell: Vector2i) -> bool:
	if not in_region(cell) or tiles.has(cell):
		return false
	tiles[cell] = {"tilled": true, "crop_id": "", "planted_abs_day": -1, "watered_growth_days": 0, "watered": false}
	_refresh(cell)
	return true

func plant(cell: Vector2i, seed_id: String) -> bool:
	var t: Dictionary = tiles.get(cell, {})
	if t.is_empty() or t.get("crop_id", "") != "":
		return false
	var cid := GameData.crop_from_seed(seed_id)
	# 철 지난 씨앗은 심는 순간 막는다 — 심으면 다음 아침 _season_deaths가 조용히 없애 씨앗만 증발한다.
	# 심을 수 있는 계절(plant_seasons)은 열리는 계절(seasons)과 다를 수 있다: 겨울에 열리는
	# 다년생은 가을에 심는다. 겨울 파종 금지는 데이터가 정한다(엔진에 계절 이름을 안 박는다).
	if cid == "" or not GameData.crop_plantable(cid, GameData.season_id(GameClock.season())):
		return false
	t["crop_id"] = cid
	t["planted_abs_day"] = GameClock.abs_day
	t["watered_growth_days"] = 0
	t["watered"] = _wet_today()  # 비 오는 날 심으면 즉시 젖음
	_refresh(cell)
	return true

func water(cell: Vector2i) -> bool:
	var t: Dictionary = tiles.get(cell, {})
	if t.is_empty() or t.get("crop_id", "") == "" or t.get("watered", false):
		return false
	t["watered"] = true
	_refresh(cell)
	return true

func harvest(cell: Vector2i) -> String:
	if not is_mature_at(cell):
		return ""
	var t: Dictionary = tiles[cell]
	var cid: String = t["crop_id"]
	var regrow := int(GameData.crops[cid].get("regrow_days", 0))
	if regrow > 0:
		t["watered_growth_days"] = GameData.grow_days(cid) - regrow  # 재수확
		t["watered"] = _wet_today()
	else:
		t["crop_id"] = ""
		t["planted_abs_day"] = -1
		t["watered_growth_days"] = 0
		t["watered"] = false
	_refresh(cell)
	return GameData.crop_yield(cid)  # 기른 것 = 주운 것 (채집물 재배는 그 채집물 아이템을 낸다)

# ── 판매상자 ───────────────────────────────────────────────────
func deposit(item_id: String, qty: int) -> int:
	if not GameData.is_produce(item_id) or qty <= 0:
		return 0  # 산출물(작물·물고기·채집물)만 판매 가능
	for e in shipping_bin:
		if e["id"] == item_id:
			e["qty"] = int(e["qty"]) + qty
			return qty
	shipping_bin.append({"id": item_id, "qty": qty})
	return qty

# ── 일 변경 정산 (순서 고정) ────────────────────────────────────
func _on_day_changed(_prev: int, _abs_day: int) -> void:
	_settle_shipping()      # 1. 전날 판매상자 정산
	for cell in tiles:      # 2. 물 준 작물만 성장 누적 (제철 아니면 휴면 — 다년생이 겨울잠을 잔다)
		var t: Dictionary = tiles[cell]
		if t.get("crop_id", "") != "" and t.get("watered", false) and _in_season(t["crop_id"]):
			t["watered_growth_days"] = int(t["watered_growth_days"]) + 1
	_season_deaths()        # 3. 계절 경계 작물 고사
	var rain := _wet_today()  # 4. 물 리셋 (비 오는 날은 리셋 대신 전부 자동 물주기)
	for cell in tiles:
		tiles[cell]["watered"] = rain
	_refresh_all()

func _settle_shipping() -> void:
	var total := 0
	for e in shipping_bin:
		total += GameData.sell_price(e["id"]) * int(e["qty"])
	if total > 0:
		var p := get_tree().get_first_node_in_group("player")
		if p != null and p.has_method("add_gold"):
			p.add_gold(total)
	shipping_bin.clear()

func _season_deaths() -> void:
	var sn: String = GameData.season_id(GameClock.season())
	for cell in tiles:
		var t: Dictionary = tiles[cell]
		var cid: String = t.get("crop_id", "")
		if cid != "":
			# 다년생은 면제 — 심은 것이 풍경으로 남는다(제철이 아니면 휴면할 뿐 안 죽는다).
			if not GameData.crop_perennial(cid) and not GameData.crop_in_season(cid, sn):
				t["crop_id"] = ""
				t["watered_growth_days"] = 0
				t["planted_abs_day"] = -1

# ── 시각화 ─────────────────────────────────────────────────────
# 옛 판은 종을 안 가리는 색 상자(0.35×0.7×0.35) 하나를 성장률로 **세로만** 늘였다 — 무를 심었는지
# 딸기를 심었는지 상자 색으로만 알았다. 지금은 채집물과 **같은 절차 원형**(plant_shapes)으로 종마다
# 실물을 깎는다. 재배 채집물 13종은 캐시 키로 **산출물 id**를 넘겨 주운 것과 같은 메시 한 장을 쓴다
# = 기른 라벤더와 주운 라벤더가 갈릴 여지 자체가 없다.
const Shapes := preload("res://common/plant_shapes.gd")
const SOIL_TOP := 0.11   # 흙 타일 윗면 (중심 0.06 + 높이 0.1의 절반)
# 밑동을 흙에 살짝 박는다. 지면 곡률(toon.gdshader v.y −= 0.006·z²)은 흙 타일과 작물이 같은
# 깊이라 같이 휘어 상쇄되지만, 정확히 0으로 맞추면 원거리에서 실 같은 틈이 보인다(채집물이
# 겪은 밑동 잠김의 반대 증상). 0.012 = 흙 타일 두께(0.1)의 1/8.
const SINK := 0.012
const SPROUT := Color(0.35, 0.62, 0.28)   # 공용 새싹 색 = 전 작물 공통 출발점
const RIPE_FALLBACK := Color(0.85, 0.75, 0.25)  # color 필드 없는 작물(구데이터) 기본 열매색
const DORMANT := Color(0.42, 0.36, 0.28)  # 휴면(제철 아님) = 열매 없는 마른 그루. 열매색과 안 섞이는 갈색.

# 성장 단계 (crops.json "stages" = 3 또는 4). 옛 판처럼 메시 하나를 세로로 늘이면 실물에선
# **납작하게 눌린 뿌리**가 된다 — 단계를 형태로 가른다: 0 = 공용 새싹(갓 난 싹은 실제로 종
# 구분이 안 된다), 마지막 = 종별 실물, 중간 = 종별 형태를 균등 축소.
# 마지막 단계는 **수확 가능해질 때만** 준다 — 다 자라 보이는데 못 거두는 칸을 안 만든다.
static func stage_index(days: int, grow: int, stages: int) -> int:
	var st := maxi(stages, 2)
	var g := maxi(grow, 1)
	if days >= g:
		return st - 1
	return clampi(int(floor(float(days) / float(g) * float(st - 1))), 0, st - 2)

# 단계별 **균등** 배율(세로만 늘이지 않는다). 하한 0.45 = 새싹 다음 칸이 다 자란 것의 절반쯤 —
# 더 낮추면 화면에서 새싹과 구분이 안 갔다(계산 실측: 0.30이면 전고 0.15로 새싹 0.11에 붙는다).
static func stage_scale(stage: int, stages: int) -> float:
	return lerpf(0.45, 1.0, float(stage) / float(maxi(stages - 1, 1)))

func crop_color(crop_id: String) -> Color:
	var c: Array = GameData.crops.get(crop_id, {}).get("color", [])
	if c.size() == 3:
		return Color(c[0], c[1], c[2])
	# 채집물 재배는 색을 다시 적지 않는다 — 주운 것과 같은 아이템이니 그 색이 곧 이 색이다.
	var y := GameData.crop_yield(crop_id)
	if y != crop_id:
		return Color.from_string(String(GameData.forage.get(y, {}).get("color", "")), RIPE_FALLBACK)
	return RIPE_FALLBACK

# 그 종의 겉모습 데이터. 재배 채집물은 **산출물(채집물) 정의를 그대로** 본다 — 형태도 색도
# 한 곳에서만 정해지니 기른 것과 주운 것이 갈릴 여지가 없다(색은 crop_color가 같은 규약).
func crop_look_data(crop_id: String) -> Dictionary:
	var y := GameData.crop_yield(crop_id)
	return GameData.forage.get(y, {}) if y != crop_id else GameData.crops.get(crop_id, {})

# 단계에 맞는 겉모습 노드. 밑동은 AABB로 앉힌다 — **배율을 준 뒤에** 재야 맞는다(먼저 앉히고
# 배율을 주면 원점이 같이 밀려 뜨거나 묻힌다).
func crop_look(crop_id: String, stage: int) -> Node3D:
	var n: Node3D = null
	if stage <= 0:
		n = Shapes.build({"shape": Shapes.SPROUT_SHAPE}, SPROUT, Shapes.SPROUT_SHAPE)
	else:
		n = Shapes.build(crop_look_data(crop_id), crop_color(crop_id), GameData.crop_yield(crop_id))
		if n != null:
			# 곱한다 — 킷 메시는 build가 전고를 맞추느라 이미 배율을 걸어 놨다(덮어쓰면 원본
			# 크기로 되돌아간다: 사과가 0.50 → 0.36으로 줄어 주운 것과 크기가 갈렸다, 실측).
			n.scale *= stage_scale(stage,
				int(GameData.crops.get(crop_id, {}).get("stages", 3)))
	if n == null:
		# 형태 미지정 = 옛 색 상자. 새 작물을 넣고 형태를 안 주면 조용히 여기로 떨어지므로
		# **테스트가 전 종이 이 길을 안 타는지** 문다(채집물의 구체 폴백과 같은 규약).
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.35, 0.7, 0.35)
		mi.mesh = bm
		mi.material_override = ToonChar.make_solid(crop_color(crop_id), 0.005)
		mi.position.y = 0.35
		return mi
	# build가 배율 1 기준으로 이미 앉혀 놨다 — 0으로 되돌리고 다시 재야 한다. 그냥 재면 옛 원점이
	# 섞여 들어가 밑이 두 번 밀린다(실측: 눕힌 잎이 아래로 0.009 나온 덩굴 작물이 그만큼 묻혔다).
	n.position.y = 0.0
	n.position.y = -ToonChar.aabb_of(n).position.y - SINK
	return n

# 휴면(다년생 제철 아님) = 열매 없는 마른 그루. 메시를 다시 깎지 않고 노드 전체를 마른 갈색으로
# 덮는다 — 절차 원형이든 킷 메시든 같은 한 줄로 먹는다. 옛 판의 DORMANT 표현을 실물에서 유지:
# 이게 없으면 "다 자랐는데 왜 수확이 안 되지"가 된다.
static func _paint(node: Node, col: Color) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = ToonChar.make_solid(col, 0.005)
	for c in node.get_children():
		_paint(c, col)

func _refresh(cell: Vector2i) -> void:
	var t: Dictionary = tiles.get(cell, {})
	if t.is_empty():
		if _nodes.has(cell):
			_nodes[cell]["soil"].queue_free()
			_nodes[cell]["crop"].queue_free()
			_nodes.erase(cell)
		return
	if not _nodes.has(cell):
		_nodes[cell] = _make_nodes(cell)
	var n: Dictionary = _nodes[cell]
	# 흙: 물 주면 진하게
	var soil_mat: ShaderMaterial = n["soil"].material_override
	soil_mat.set_shader_parameter("albedo", Color(0.30, 0.20, 0.13) if t.get("watered", false) else Color(0.45, 0.31, 0.20))
	# 작물: 겉모습은 (종·단계·휴면)으로만 갈린다. 키가 그대로면 노드를 다시 만들지 않는다 —
	# 일변경마다 32칸을 새로 깎으면 킷 메시(gltf) 로드까지 딸려 온다.
	var slot: Node3D = n["crop"]
	var cid: String = t.get("crop_id", "")
	var key := ""
	if cid != "":
		var dorm := not _in_season(cid)
		var stage := stage_index(int(t.get("watered_growth_days", 0)), GameData.grow_days(cid),
			int(GameData.crops.get(cid, {}).get("stages", 3)))
		key = "%s|%d|%d" % [cid, stage, int(dorm)]
		if String(n.get("key", "")) != key:
			_clear_slot(slot)
			var look := crop_look(cid, stage)
			if dorm:
				_paint(look, DORMANT)
			slot.add_child(look)
	elif String(n.get("key", "")) != "":
		_clear_slot(slot)
	n["key"] = key
	slot.visible = cid != ""

# queue_free는 프레임 끝에 처리된다 — 같은 프레임에 두 번 새로 그리면 옛 겉모습이 겹쳐 남는다.
func _clear_slot(slot: Node3D) -> void:
	for c in slot.get_children():
		slot.remove_child(c)
		c.queue_free()

func _make_nodes(cell: Vector2i) -> Dictionary:
	var soil := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.92, 0.1, 0.92)
	soil.mesh = sm
	soil.material_override = ToonChar.make_solid(Color(0.45, 0.31, 0.20), 0.0)
	soil.position = _center(cell) + Vector3(0, 0.06, 0)
	add_child(soil)
	# 작물 자리 = 흙 윗면에 선 빈 그릇. 겉모습 노드만 갈아 끼운다(단계·휴면이 바뀔 때).
	var slot := Node3D.new()
	slot.position = _center(cell) + Vector3(0, SOIL_TOP, 0)
	add_child(slot)
	return {"soil": soil, "crop": slot, "key": ""}

func _refresh_all() -> void:
	for cell in tiles:
		_refresh(cell)

# ── 저장/로드 (Vector2i ↔ "x,z" 경계 변환) ──────────────────────
func save_data() -> Dictionary:
	var out := {}
	for cell in tiles:
		out["%d,%d" % [cell.x, cell.y]] = tiles[cell]
	return {"tiles": out, "shipping_bin": shipping_bin.duplicate(true)}

func load_data(d: Dictionary) -> void:
	for cell in _nodes:
		_nodes[cell]["soil"].queue_free()
		_nodes[cell]["crop"].queue_free()
	_nodes.clear()
	tiles.clear()
	for key in d.get("tiles", {}):
		var parts: PackedStringArray = key.split(",")
		var t: Dictionary = d["tiles"][key]
		# JSON 라운드트립 int→float 정규화 (산술 필드)
		t["watered_growth_days"] = int(t.get("watered_growth_days", 0))
		t["planted_abs_day"] = int(t.get("planted_abs_day", -1))
		# 날씨 도입 이전 세이브(비 오는 날인데 watered=false)를 로드 시각에 맞춰 보정.
		# 신규 세이브는 이미 젖은 채로 저장되므로 idempotent.
		t["watered"] = bool(t.get("watered", false)) or _wet_today()
		t["tilled"] = bool(t.get("tilled", true))
		tiles[Vector2i(int(parts[0]), int(parts[1]))] = t
	shipping_bin = d.get("shipping_bin", []).duplicate(true)
	for e in shipping_bin:
		e["qty"] = int(e["qty"])
	_refresh_all()

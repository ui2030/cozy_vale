extends Node3D
# 밭 타일맵 단일 소유 (DESIGN 6.2 / 11.3). 타일 상태·성장·판매상자 정산.
# day_changed 처리 순서 고정(Codex): 정산 → 성장 → 계절고사 → 물리셋 → (저장은 호출측).

const REGION := Rect2i(0, 2, 8, 4)  # 밭 구역: cell x[0..7], z[2..5]
const ToonChar := preload("res://common/toon_character.gd")

var tiles := {}          # Vector2i → {tilled, crop_id, planted_abs_day, watered_growth_days, watered}
var shipping_bin := []   # [{id, qty}] — 인벤에서 즉시 차감돼 여기 저장(중복·증발 방지)
var _nodes := {}         # Vector2i → {soil: MeshInstance3D, crop: MeshInstance3D}

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
	return t.get("crop_id", "") != "" and int(t.get("watered_growth_days", 0)) >= GameData.grow_days(t["crop_id"])

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
	if cid == "" or not GameData.crop_in_season(cid, GameData.season_id(GameClock.season())):
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
	return cid

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
	for cell in tiles:      # 2. 물 준 작물만 성장 누적
		var t: Dictionary = tiles[cell]
		if t.get("crop_id", "") != "" and t.get("watered", false):
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
		if t.get("crop_id", "") != "":
			if not GameData.crop_in_season(t["crop_id"], sn):
				t["crop_id"] = ""
				t["watered_growth_days"] = 0
				t["planted_abs_day"] = -1

# ── 시각화 ─────────────────────────────────────────────────────
const SPROUT := Color(0.35, 0.62, 0.28)   # 새싹 = 전 작물 공통 출발색
const RIPE_FALLBACK := Color(0.85, 0.75, 0.25)  # color 필드 없는 작물(구데이터) 기본 열매색

func crop_color(crop_id: String) -> Color:
	var c: Array = GameData.crops.get(crop_id, {}).get("color", [])
	return Color(c[0], c[1], c[2]) if c.size() == 3 else RIPE_FALLBACK

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
	# 작물: 성장률로 높이·색
	var crop: MeshInstance3D = n["crop"]
	var cid: String = t.get("crop_id", "")
	if cid == "":
		crop.visible = false
	else:
		crop.visible = true
		var frac := clampf(float(t["watered_growth_days"]) / float(maxi(GameData.grow_days(cid), 1)), 0.05, 1.0)
		crop.scale = Vector3(1, frac, 1)
		crop.position = _center(cell) + Vector3(0, 0.11 + 0.35 * frac, 0)  # 밑면 접지
		var cm: ShaderMaterial = crop.material_override
		var ripe := crop_color(cid)  # 다 자란 색은 작물별(crops.json) — 12종을 밭에서 구분
		cm.set_shader_parameter("albedo", ripe if is_mature_at(cell) else SPROUT.lerp(ripe, frac))

func _make_nodes(cell: Vector2i) -> Dictionary:
	var soil := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.92, 0.1, 0.92)
	soil.mesh = sm
	soil.material_override = ToonChar.make_solid(Color(0.45, 0.31, 0.20), 0.0)
	soil.position = _center(cell) + Vector3(0, 0.06, 0)
	add_child(soil)
	var crop := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(0.35, 0.7, 0.35)
	crop.mesh = cm
	crop.material_override = ToonChar.make_solid(Color(0.35, 0.62, 0.28), 0.005)
	# 아래 기준으로 자라게 원점을 밑면에
	crop.position = _center(cell) + Vector3(0, 0.1, 0)
	crop.scale = Vector3(1, 0.05, 1)
	add_child(crop)
	return {"soil": soil, "crop": crop}

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

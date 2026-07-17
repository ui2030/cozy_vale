extends Node3D
# 밭 타일맵 단일 소유 (DESIGN 6.2 / 11.3). 타일 상태·성장·판매상자 정산.
# day_changed 처리 순서 고정(Codex): 정산 → 성장 → 계절고사 → 물리셋 → (저장은 호출측).

const REGION := Rect2i(0, 2, 8, 4)  # 밭 구역: cell x[0..7], z[2..5]
const SEASON_NAMES := ["spring", "summer", "autumn", "winter"]

var tiles := {}          # Vector2i → {tilled, crop_id, planted_abs_day, watered_growth_days, watered}
var shipping_bin := []   # [{id, qty}] — 인벤에서 즉시 차감돼 여기 저장(중복·증발 방지)
var _nodes := {}         # Vector2i → {soil: MeshInstance3D, crop: MeshInstance3D}

func _ready() -> void:
	add_to_group("farm")
	if not GameClock.day_changed.is_connected(_on_day_changed):
		GameClock.day_changed.connect(_on_day_changed)  # 이중구독 방지

func in_region(cell: Vector2i) -> bool:
	return REGION.has_point(cell)

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
	if cid == "":
		return false
	t["crop_id"] = cid
	t["planted_abs_day"] = GameClock.abs_day
	t["watered_growth_days"] = 0
	t["watered"] = false
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
		t["watered"] = false
	else:
		t["crop_id"] = ""
		t["planted_abs_day"] = -1
		t["watered_growth_days"] = 0
		t["watered"] = false
	_refresh(cell)
	return cid

# ── 판매상자 ───────────────────────────────────────────────────
func deposit(item_id: String, qty: int) -> int:
	if not GameData.crops.has(item_id) or qty <= 0:
		return 0  # 작물만 판매 가능
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
	for cell in tiles:      # 4. 물 리셋
		tiles[cell]["watered"] = false
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
	var sn: String = SEASON_NAMES[GameClock.season()]
	for cell in tiles:
		var t: Dictionary = tiles[cell]
		if t.get("crop_id", "") != "":
			var seasons: Array = GameData.crops[t["crop_id"]].get("seasons", [])
			if not seasons.has(sn):
				t["crop_id"] = ""
				t["watered_growth_days"] = 0
				t["planted_abs_day"] = -1

# ── 시각화 ─────────────────────────────────────────────────────
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
	var soil_mat: StandardMaterial3D = n["soil"].material_override
	soil_mat.albedo_color = Color(0.30, 0.20, 0.13) if t.get("watered", false) else Color(0.45, 0.31, 0.20)
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
		var cm: StandardMaterial3D = crop.material_override
		cm.albedo_color = Color(0.85, 0.75, 0.25) if is_mature_at(cell) else Color(0.35, 0.62, 0.28)

func _make_nodes(cell: Vector2i) -> Dictionary:
	var soil := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.92, 0.1, 0.92)
	soil.mesh = sm
	soil.material_override = StandardMaterial3D.new()
	soil.position = _center(cell) + Vector3(0, 0.06, 0)
	add_child(soil)
	var crop := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(0.35, 0.7, 0.35)
	crop.mesh = cm
	crop.material_override = StandardMaterial3D.new()
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
		t["watered"] = bool(t.get("watered", false))
		t["tilled"] = bool(t.get("tilled", true))
		tiles[Vector2i(int(parts[0]), int(parts[1]))] = t
	shipping_bin = d.get("shipping_bin", []).duplicate(true)
	for e in shipping_bin:
		e["qty"] = int(e["qty"])
	_refresh_all()

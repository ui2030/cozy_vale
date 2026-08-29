extends Control
# 도감 패널 (B키 토글). 카테고리별(작물/물고기/채집물) 전체 슬롯 — 발견=이름, 미발견="???".
# 발견 현황은 player.collection 단일 출처 조회. 낚시 중엔 열지 않음.

const Hud := preload("res://ui/hud.gd")  # 패널 배경 단일 출처(여백·불투명도)
const Shapes := preload("res://common/plant_shapes.gd")  # 밭·채집물이 쓰는 그 실물 메시
const ToonChar := preload("res://common/toon_character.gd")

# ── 아이콘 ────────────────────────────────────────────────────────
# 아이콘 그림을 따로 그리지 않는다. 밭에 서 있고 풀숲에 놓여 있는 **그 메시**를 작은
# SubViewport에 한 번 그려서 쓴다 = 겉모습의 단일 출처가 여전히 crops.json/forage.json이고,
# 종이 늘어도 아이콘 작업이 따로 생기지 않는다.
const ICON_PX := 44       # 행에 놓이는 변 길이. 32로는 뿌리·이삭이 무엇인지 안 읽혔다(실측)
const ICON_RENDER := 88   # 렌더 해상도 — 2배로 그려 반으로 줄인다(계단 완화)
const CELL_W := 150       # 칸 폭. 아이콘 44 + 간격 4를 뺀 102가 이름 몫이다
# 미발견 실루엣. 도감의 재미는 빈칸을 채우는 것이라 형태만 남기고 색을 죽인다.
# 어두운 사본을 따로 굽지 않고 아이콘 한 장을 modulate로 눌러 쓴다.
const SILHOUETTE := Color(0.08, 0.07, 0.09, 0.85)

var _list: VBoxContainer
var _scroll: ScrollContainer
var _icons := {}  # 아이템 id → Texture2D(없으면 null). 패널 수명 동안 한 번만 만든다.

func _ready() -> void:
	add_to_group("collection_panel")
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(360, 100)
	Hud.style_panel(panel)
	add_child(panel)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	_list.custom_minimum_size = Vector2(CELL_W * 3 + 12, 0)
	_scroll = Hud.scroll_body(panel, _list)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("collection"):
		var fg := get_tree().get_first_node_in_group("fishing")
		if fg != null and fg.is_active():  # 낚시 중엔 무시
			return
		visible = not visible
		Sfx.play("ui_open" if visible else "ui_close")
		if visible:
			_rebuild()
		get_viewport().set_input_as_handled()

func _rebuild() -> void:
	# 가방·요리 패널과 같은 이유로 먼저 떼고 지운다: queue_free만 하면 이번 프레임 끝까지 자식으로
	# 남아 목록 높이가 옛 행까지 합산된다(높이를 재서 스크롤을 맞추므로 그대로면 두 배로 잡힌다).
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var p := get_tree().get_first_node_in_group("player")
	var col: Array = p.collection if p != null else []
	var title := Label.new()
	title.text = "도감"
	title.add_theme_font_size_override("font_size", 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_list.add_child(title)
	_section("작물", GameData.crops, col)
	_section("물고기", GameData.fish, col)
	_section("채집물", GameData.forage, col)
	Hud.fit_scroll(_scroll)

func _section(title: String, source: Dictionary, col: Array) -> void:
	# 아이템인 것만 센다 — 산출물이 따로 있는 재배 항목(채집물 재배)은 도감 슬롯이 아니다.
	# 넣으면 영영 못 채우는 "???"가 생겨 진도율이 고장난다.
	var ids := []
	for id in source:
		if GameData.is_collectible(id):
			ids.append(id)
	var found := 0
	for id in ids:
		if id in col:
			found += 1
	var head := Label.new()
	head.add_theme_font_size_override("font_size", 18)
	head.text = "%s  (%d/%d)" % [title, found, ids.size()]
	_list.add_child(head)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 4)
	for id in ids:
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 4)
		cell.custom_minimum_size = Vector2(CELL_W, ICON_PX)
		var tex := _icon(id)
		if tex != null:  # 실물 메시가 없는 항목(물고기)은 아이콘 없이 이름만 — 임시 도형은 안 넣는다
			var ic := TextureRect.new()
			ic.texture = tex
			ic.custom_minimum_size = Vector2(ICON_PX, ICON_PX)
			# EXPAND_IGNORE_SIZE가 없으면 최소 크기가 **텍스처 크기**(88)라 행이 두 배로 벌어진다.
			ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			# 패널이 픽셀아트라 NEAREST를 상속한다 — 2배 렌더를 그대로 줄이면 계단이 진다.
			ic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			ic.modulate = Color.WHITE if id in col else SILHOUETTE
			cell.add_child(ic)
		else:
			# 아이콘이 없는 항목도 그 자리만큼은 비워 둔다 — 안 그러면 이름 왼쪽 끝이
			# 구간마다 어긋나 목록의 세로선이 들쭉날쭉해진다. 그림을 넣는 게 아니라 자리만.
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(ICON_PX, ICON_PX)
			cell.add_child(gap)
		var name_lb := Label.new()
		name_lb.add_theme_font_size_override("font_size", 15)
		name_lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_lb.text = GameData.display_name(id) if id in col else "???"
		cell.add_child(name_lb)
		grid.add_child(cell)
	_list.add_child(grid)

# 아이콘 한 장. 실물 메시를 SubViewport에 넣고 **한 프레임만** 그린 뒤 그 텍스처를 계속 쓴다
# (UPDATE_ONCE = 그리고 나면 스스로 꺼진다). 패널을 다시 열어도 여기 캐시가 그대로 돌아온다.
func _icon(id: String) -> Texture2D:
	if _icons.has(id):
		return _icons[id]
	_icons[id] = null
	var look := _look_of(id)
	if look != null:
		var vp := SubViewport.new()
		vp.size = Vector2i(ICON_RENDER, ICON_RENDER)
		vp.transparent_bg = true
		vp.own_world_3d = true  # 마을 조명·계절 환경이 아이콘에 새어 들어오지 않게
		vp.msaa_3d = Viewport.MSAA_4X
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		var ab := ToonChar.aabb_of(look)
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		# 대각선 길이면 어느 방향에서 봐도 안 잘린다(원형마다 가로세로 비가 제각각이다).
		cam.size = maxf(ab.size.length(), 0.01) * 1.1
		cam.near = 0.05
		cam.far = 4.0
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-42, -34, 0)
		vp.add_child(cam)
		vp.add_child(light)
		vp.add_child(look)
		add_child(vp)
		# look_at은 트리 안에서만 된다 — 붙인 뒤에 겨눈다. 살짝 위·옆 = 3/4 시점.
		# 거리 1.0은 짧게 잡은 값이다: 툰 셰이더가 시야 거리²로 화면을 휘므로(curve_strength
		# 0.006) 멀리서 잡으면 아이콘이 프레임 아래로 밀린다(4m면 0.096 = 프레임의 20%).
		cam.position = ab.get_center() + Vector3(0.25, 0.30, 1.0).normalized()
		cam.look_at(ab.get_center(), Vector3.UP)
		_icons[id] = vp.get_texture()
	return _icons[id]

# 그 아이템의 실물 겉모습 노드. 형태·색의 출처는 밭·채집물이 보는 그 json 그대로다.
# 물고기는 실물 메시가 아예 없다(낚시는 미니게임이라 어종 모델이 없다) → null.
func _look_of(id: String) -> Node3D:
	if GameData.forage.has(id):
		var fd: Dictionary = GameData.forage[id]
		return Shapes.build(fd, Color.from_string(String(fd.get("color", "")), Color.WHITE), id)
	if GameData.crops.has(id):
		var cd: Dictionary = GameData.crops[id]
		var c: Array = cd.get("color", [])
		if c.size() == 3:
			return Shapes.build(cd, Color(c[0], c[1], c[2]), id)
	return null

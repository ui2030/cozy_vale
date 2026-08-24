extends Control
# 개발자 확인용 계절·날씨·시각 조작 패널 (F3 토글). 릴리즈 빌드엔 노드 자체가 없다.
#
# 결정론 규약: 프로덕션 판정 함수(GameData.is_rainy / World.ground_color)에 디버그 분기를
# 심지 않는다. 스크린샷 하네스와 **똑같은 수단**만 쓴다 — 원하는 조건이 성립하는 날로 시계를
# 옮기고(World.season_day), 신호가 없는 경로라 World._apply_season을 한 번 명시 호출한다
# (world.gd _ready 말미와 같은 규약). 날씨 입자·하늘·조명은 weather.gd / day_night.gd가
# 매 프레임 abs_day·game_min을 폴링하므로 시계만 옮기면 저절로 따라온다.
#
# 세이브: 패널이 열리는 순간 SaveManager.suspended를 세우고 **다시 내리지 않는다**(세션 단방향
# 래치). 닫아도 유지되므로 디버그로 옮긴 시계가 나중 취침·판매 저장에 섞여 유저 세이브를
# 오염시킬 경로가 없다. suspended는 _write()의 공통 관문이라 request_save 우회 호출도 막힌다.
#
# 시계를 멈추지 않는다(PAUSED 금지) — PAUSED는 player._physics_process를 멈춰 캐릭터가
# 공중에 뜬다(하네스가 캡처 직전 내려꽂는 이유). 그림체 확인 중엔 발이 땅에 붙어 있어야 한다.

const Hud := preload("res://ui/hud.gd")  # 패널 배경 단일 출처(여백 18·알파 0.95·크림 테두리·라운드 10)

const SEASON_KO := ["봄", "여름", "가을", "겨울"]
const WINTER := 3
const HOURS := [6, 8, 12, 18, 21]

var _status: Label
var _world: Node
var _sbtn: Array[Button] = []  # 계절 4칸 — 지금 계절이 눌린 상태로 남는다
var _wbtn: Array[Button] = []  # 날씨 3칸(맑음·비·눈)

func _ready() -> void:
	if not OS.is_debug_build():
		queue_free()  # 릴리즈: 패널도 F3 등록도 없다
		return
	add_to_group("debug_panel")
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# 액션은 여기서 등록한다 — InputSetup(프로덕션)에 두면 일시정지 메뉴의 조작키 화면에 샌다.
	if not InputMap.has_action("debug_panel"):
		InputMap.add_action("debug_panel")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_F3
		InputMap.action_add_event("debug_panel", ev)
	_build()
	GameClock.tick.connect(func(_a, _m): if visible: _refresh())

func _build() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 96)  # HUD 시각 라벨(상단)·토스트 아래
	Hud.style_panel(panel)
	add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)
	var t := Label.new()
	t.text = "개발자 패널 (F3)"
	t.add_theme_font_size_override("font_size", 20)
	vb.add_child(t)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 15)
	vb.add_child(_status)
	# 계절·날씨는 토글 버튼 = 지금 고른 칸이 눌린 채로 남는다(포커스 테두리와 헷갈리지 않게).
	var srow := _row(vb, "계절")
	for i in SEASON_KO.size():
		_sbtn.append(_btn(srow, SEASON_KO[i], func(): pick_season(i), true))
	var wrow := _row(vb, "날씨")
	_wbtn.append(_btn(wrow, "맑음", func(): pick_weather(false, false), true))
	_wbtn.append(_btn(wrow, "비", func(): pick_weather(true, false), true))
	_wbtn.append(_btn(wrow, "눈", func(): pick_weather(true, true), true))
	var hrow := _row(vb, "시각")
	for h in HOURS:
		_btn(hrow, "%d시" % h, func(): pick_hour(h))
	# 옛 안내 라벨("지면·식생 톤은 겨울만 다름")은 지웠다 — 계절을 사계절로 벌린 뒤 거짓말이 됐다.
	# 이제 계절 버튼 하나로 지면색·길색·지면 패턴(World.ground_color/road_color/ground_pattern)과
	# 나무 단풍·꽃 개화·바닥 낙엽(Decor.apply_season)이 전부 함께 바뀐다.

func _row(vb: VBoxContainer, title: String) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 4)
	var l := Label.new()
	l.text = title
	l.custom_minimum_size = Vector2(44, 0)
	hb.add_child(l)
	vb.add_child(hb)
	return hb

func _btn(hb: HBoxContainer, text: String, cb: Callable, toggle := false) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = toggle
	b.custom_minimum_size = Vector2(56, 0)
	b.pressed.connect(cb)
	hb.add_child(b)  # Button은 기본 focus_mode ALL — 마우스 클릭 + 방향키/Enter 둘 다 동작
	return b

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_panel"):
		if visible:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()

func open() -> void:
	SaveManager.suspended = true  # 단방향 래치: close()에서도 풀지 않는다
	visible = true
	Sfx.play("ui_open")
	_refresh()
	_sbtn[GameClock.season()].grab_focus()  # 방향키 조작 시작점 = 지금 계절 칸

func close() -> void:
	visible = false
	Sfx.play("ui_close")

# ── 조작 (버튼과 하네스가 같은 진입점을 쓴다) ─────────────────────
func pick_season(idx: int) -> void:
	_goto(idx, GameData.is_rainy(GameClock.abs_day))  # 날씨는 유지한 채 계절만

# snow=true면 겨울로 함께 넘어간다 — 같은 강수일을 weather.gd가 겨울에만 눈으로 그린다.
# 겨울에서 "비"를 고르면 봄으로 나간다(겨울 비는 이 게임에 존재하지 않는다).
func pick_weather(rain: bool, snow: bool) -> void:
	var sea := GameClock.season()
	if snow:
		sea = WINTER
	elif rain and sea == WINTER:
		sea = 0
	_goto(sea, rain)

func pick_hour(h: int) -> void:
	GameClock.game_min = h * 60
	_after()

# 하네스용: 토큰 하나를 대응하는 버튼으로 누른다(모르는 토큰은 false). 패널 조작을 스크린샷으로
# 증명하려면 하네스가 버튼과 **같은 경로**를 타야 한다 — 별도 적용 코드를 만들면 증명이 아니다.
func press(token: String) -> bool:
	if token in GameData.SEASON_IDS:
		pick_season(GameData.SEASON_IDS.find(token))
	elif token == "clear":
		pick_weather(false, false)
	elif token == "rain":
		pick_weather(true, false)
	elif token == "snow":
		pick_weather(true, true)
	elif token.is_valid_int():
		pick_hour(int(token))
	else:
		return false
	return true

func _goto(sea: int, rain: bool) -> void:
	var w := _wo()
	if w == null:
		return
	GameClock.abs_day = w.season_day(sea, rain)
	w._apply_season(sea)  # 신호 없는 시계 이동 = 하네스와 같은 명시 재적용
	_after()

func _after() -> void:
	get_tree().call_group("hud", "_refresh")  # 다음 tick(≈0.6초)을 기다리지 않고 라벨 즉시 갱신
	_refresh()

func _wo() -> Node:
	if _world == null:
		_world = get_tree().get_first_node_in_group("world")
	return _world

func _refresh() -> void:
	var sea := GameClock.season()
	var rain := GameData.is_rainy(GameClock.abs_day)
	var wi := (2 if sea == WINTER else 1) if rain else 0  # 겨울 강수 = 눈
	for i in _sbtn.size():
		_sbtn[i].set_pressed_no_signal(i == sea)
	for i in _wbtn.size():
		_wbtn[i].set_pressed_no_signal(i == wi)
	_status.text = "%s D%d · %s · %02d:%02d · 세이브 잠금" % [
		SEASON_KO[sea], GameClock.day_of_season(), ["맑음", "비", "눈"][wi],
		GameClock.hour(), GameClock.minute(),
	]

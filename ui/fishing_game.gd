extends Control
# 낚시 타이밍 미니게임 (HUD 자식). 물가 E → 시작, 마커 좌우 핑퐁, interact 1회 판정.
# 시계는 계속 흐름(낚시=시간 소모 게임플레이). 이동 잠금은 player가 is_active() 조회로 처리.

const Hud := preload("res://ui/hud.gd")  # 패널 배경 단일 출처(여백·불투명도·크림 테두리)

const SPEED := 1.15   # 마커 왕복 속도 (bar/초)
const BAR_W := 420.0
const BAR_H := 34.0
const PAD := 18.0     # panel_style content_margin과 같은 값 = 안쪽 여백 수동 배치용
const TIP_H := 30.0   # 제목 줄(어종 + 조작 안내)
const GAP := 10.0     # 제목과 게이지 사이
const BOTTOM := 110.0 # 화면 아래 여백 — HUD 프롬프트 줄(하단 중앙)을 덮지 않는 높이

var _active := false
var _fish_id := ""
var _half := 0.12
var _marker := 0.0
var _dir := 1.0

var _panel: Panel
var _bar: Panel
var _zone: Panel
var _mark: Panel
var _tip: Label

# ── 순수 판정 함수 (test_core 단위검증) ─────────────────────────
# 난이도 0(쉬움)=넓은 존, 1(어려움)=좁은 존. 존은 항상 중앙(0.5).
static func zone_half_width(difficulty: float) -> float:
	return lerpf(0.17, 0.06, clampf(difficulty, 0.0, 1.0))

static func in_zone(marker: float, half: float) -> bool:
	return absf(marker - 0.5) <= half

# ───────────────────────────────────────────────────────────────
func _ready() -> void:
	add_to_group("fishing")
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()

func is_active() -> bool:
	return _active

func start(fish_id: String, difficulty: float) -> void:
	_fish_id = fish_id
	_half = zone_half_width(difficulty)
	_marker = 0.0
	_dir = 1.0
	_active = true
	visible = true
	Sfx.play("cast")
	_layout()

func _process(delta: float) -> void:
	if not _active or GameClock.state == GameClock.State.PAUSED:
		return
	_marker += _dir * SPEED * delta
	if _marker >= 1.0:
		_marker = 1.0; _dir = -1.0
	elif _marker <= 0.0:
		_marker = 0.0; _dir = 1.0
	_mark.position = Vector2(_marker * (BAR_W - _mark.size.x), 0)

func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return
	if event.is_action_pressed("interact"):
		_judge()
		get_viewport().set_input_as_handled()

func _judge() -> void:
	var ok := in_zone(_marker, _half)
	_active = false
	visible = false
	Sfx.play("fish_success" if ok else "fish_fail")
	if ok:
		var p := get_tree().get_first_node_in_group("player")
		if p != null:
			p._add_item(_fish_id, 1)  # 도감 등록 훅 경유
		_toast("%s 낚음!" % GameData.display_name(_fish_id))
	else:
		_toast("놓쳤어요")

func _toast(text: String) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("toast"):
		hud.toast(text)

# ── 게이지 UI (중앙 하단, 절대좌표 — 앵커 프리셋 충돌 회피) ─────────
# 벌거벗은 ColorRect 3장은 밝은 지면 위에 회색 막대로 떠 보이고 안내 글자가 배경에 먹혔다
# (실측 audit2_0809/fishing_h12). 다른 패널과 같은 hud.panel_style() 위에 얹고, 트랙/존/바늘을
# 각각 다른 색·모서리로 갈라 무엇이 무엇인지 색으로 읽히게 한다.
func _build() -> void:
	var vp := get_viewport().get_visible_rect().size
	var pw := BAR_W + PAD * 2.0
	var ph := TIP_H + GAP + BAR_H + PAD * 2.0
	_panel = Panel.new()
	_panel.add_theme_stylebox_override("panel", Hud.panel_style())
	_panel.size = Vector2(pw, ph)
	_panel.position = Vector2(vp.x * 0.5 - pw * 0.5, vp.y - BOTTOM - ph)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	_tip = Label.new()
	_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip.size = Vector2(BAR_W, TIP_H)
	_tip.position = Vector2(PAD, PAD)
	_tip.add_theme_font_size_override("font_size", 20)
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_tip)
	_bar = Panel.new()  # 트랙 = 바늘이 지나는 빈 칸
	_bar.add_theme_stylebox_override("panel", _flat(Color(0.30, 0.27, 0.34), 6))
	_bar.size = Vector2(BAR_W, BAR_H)
	_bar.position = Vector2(PAD, PAD + TIP_H + GAP)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_bar)
	_zone = Panel.new()  # 성공 존 = 파스텔 민트
	_zone.add_theme_stylebox_override("panel",
		_flat(Color(0.60, 0.86, 0.62), 6, Color(0.88, 0.98, 0.86, 0.9)))
	_zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_child(_zone)
	_mark = Panel.new()  # 바늘 = 크림·짙은 테두리(존 위에서도 선다)
	_mark.add_theme_stylebox_override("panel",
		_flat(Color(1.0, 0.82, 0.42), 4, Color(0.32, 0.24, 0.18, 0.9)))
	_mark.size = Vector2(12, BAR_H)
	_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_child(_mark)

func _flat(bg: Color, radius: int, border := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	if border.a > 0.0:
		sb.border_color = border
		sb.set_border_width_all(2)
	return sb

func _layout() -> void:
	_tip.text = "%s  —  E로 초록 칸에서 멈추기!" % GameData.display_name(_fish_id)
	# 존을 바 폭에 매핑 (중앙 0.5 ± half)
	_zone.position = Vector2((0.5 - _half) * BAR_W, 0)
	_zone.size = Vector2(2.0 * _half * BAR_W, BAR_H)
	_mark.position = Vector2(0, 0)

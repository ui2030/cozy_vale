extends Control
# 낚시 타이밍 미니게임 (HUD 자식). 물가 E → 시작, 마커 좌우 핑퐁, interact 1회 판정.
# 시계는 계속 흐름(낚시=시간 소모 게임플레이). 이동 잠금은 player가 is_active() 조회로 처리.

const SPEED := 1.15   # 마커 왕복 속도 (bar/초)
const BAR_W := 420.0
const BAR_H := 34.0

var _active := false
var _fish_id := ""
var _half := 0.12
var _marker := 0.0
var _dir := 1.0

var _bar: Panel
var _zone: ColorRect
var _mark: ColorRect
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

# ── 바 UI (중앙 하단, 절대좌표 — 앵커 프리셋 충돌 회피) ─────────
func _build() -> void:
	var vp := get_viewport().get_visible_rect().size
	_bar = Panel.new()
	_bar.size = Vector2(BAR_W, BAR_H)
	_bar.position = Vector2(vp.x * 0.5 - BAR_W * 0.5, vp.y - 150.0)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar)
	_zone = ColorRect.new()
	_zone.color = Color(0.35, 0.8, 0.45, 0.6)  # 성공 존
	_zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_child(_zone)
	_mark = ColorRect.new()
	_mark.color = Color(1.0, 0.85, 0.2)  # 마커
	_mark.size = Vector2(10, BAR_H)
	_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_child(_mark)
	_tip = Label.new()
	_tip.text = "E: 타이밍!"
	_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip.size = Vector2(BAR_W, 24)
	_tip.position = Vector2(0, -30)
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_child(_tip)

func _layout() -> void:
	# 존을 바 폭에 매핑 (중앙 0.5 ± half)
	_zone.position = Vector2((0.5 - _half) * BAR_W, 0)
	_zone.size = Vector2(2.0 * _half * BAR_W, BAR_H)
	_mark.position = Vector2(0, 0)

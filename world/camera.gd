extends Camera3D
# 동물의 숲식 추종 카메라 — 캐릭터 뒤쪽에서 낮은 각도로 따라감 (고정 회전).
# 마우스 휠 줌: fov가 아니라 offset 벡터 배율로 (월드 곡률 셰이더가 카메라 거리 기반).

@export var offset := Vector3(0, 6.5, 9.5)  # 뒤(+Z)+위, 완만한 하향 (~35°)
@export var look_height := 1.2
@export var fov_deg := 48.0

const ZOOM_MIN := 0.5    # 기본 offset의 배율 하한 (가장 가까이)
const ZOOM_MAX := 1.6    # 배율 상한 (가장 멀리)
const ZOOM_STEP := 0.12  # 휠 한 칸당 배율 변화
const ZOOM_LERP := 8.0   # 보간 속도 (클수록 빠르게 목표 도달)

var _target: Node3D
var _zoom := 1.0         # 현재(보간 중) offset 배율
var _zoom_target := 1.0  # 휠로 조절되는 목표 배율 (세션 한정, 세이브 안 함)

func _ready() -> void:
	_target = get_tree().get_first_node_in_group("player")
	fov = fov_deg

func _unhandled_input(event: InputEvent) -> void:
	if GameClock.state == GameClock.State.PAUSED:
		return  # 일시정지 메뉴/취침 중엔 줌 금지
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_target = clampf(_zoom_target - ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)  # 확대(가까이)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_target = clampf(_zoom_target + ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)  # 축소(멀리)
			get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if _target == null:
		return
	_zoom = lerp(_zoom, _zoom_target, clampf(delta * ZOOM_LERP, 0.0, 1.0))
	global_position = _target.global_position + offset * _zoom
	look_at(_target.global_position + Vector3.UP * look_height, Vector3.UP)
